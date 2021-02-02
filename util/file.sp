import "util/file.hsp"

import <"stdx/string">
import <"stdx/vector">
import <"std/io">
import <"std/syscall">
import <"std/lib">
import <"std/string">

import "util/error.hsp"

using namespace stdx::string;
using namespace stdx::vector;
using std::syscall::direct_stat;
using std::syscall::stat;
using std::syscall::direct_open;
using std::syscall::direct_open2;
using std::syscall::O_RDONLY;
using std::syscall::O_DIRECTORY;
using std::syscall::direct_close;
using std::syscall::direct_read;
using std::syscall::O_WRONLY;
using std::syscall::O_CREAT;
using std::syscall::O_APPEND;
using std::syscall::O_TRUNC;
using std::syscall::direct_write;
using std::string::strlen;
using std::string::strncpy;
using std::string::strchr;
using std::lib::malloc;
using std::lib::realloc;
using std::lib::free;
using std::lib::NULL;
using std::io::printf;
using std::syscall::S_IRUSR;
using std::syscall::S_IWUSR;
using std::syscall::direct_getdents;
using std::syscall::LINUX_DIRENT_d_name_OFFSET;
using std::syscall::LINUX_DIRENT_d_off_OFFSET;
using std::syscall::LINUX_DIRENT_d_reclen_OFFSET;
using std::syscall::DT_REG;
using std::syscall::DT_DIR;
using std::syscall::direct_lseek;
using std::syscall::SEEK_SET;
using std::syscall::SEEK_CUR;
using std::syscall::direct_openat;
using std::syscall::AT_FDCWD;
using std::syscall::S_ISREG;
using std::syscall::direct_unlink;
using std::syscall::direct_rmdir;

namespace shadow { namespace util {

func bool file_exists(const char* path) {
	type stat st;
	int ret_code = direct_stat(path, st$);
	return ret_code == 0 && S_ISREG(st.st_mode);
}

func type vector::vector* read_lines(const char* path) {
	type vector::vector* ret = vector::new_vector(sizeof{type string::string*});
	char* line;

	int fd = direct_open(path, O_RDONLY);
	if (fd == -1) return ret;

	while ((line = read_line(fd)) != NULL as char*) {
		type string::string* tmp = string::new_string(line);
		maybe_report_ice(!vector::append(ret, tmp$ as byte*) as bool,
			"Could not keep track of read line!");
	}

	direct_close(fd);

	return ret;
}

func char* read_line(int fd) {
	constexpr unsigned int INITIAL_SIZE = 32;
	constexpr char NEW_LINE = '\n';
	
	char* line = malloc(sizeof{char} * INITIAL_SIZE) as char*;
	if (line == NULL as char*) {
		return line;
	}

	unsigned int capacity = INITIAL_SIZE;
	unsigned int size = 0;

	int read_result;
	bool err = true;
	while ((read_result = direct_read(fd, line[size]$, (capacity - size) - 1)) > 0) {
		char* search_result = strchr(line[size]$, NEW_LINE);

		size += read_result;
		if (search_result != NULL as char*) {
			unsigned int true_size =
				(search_result as unsigned int) - (line as unsigned int);
			line[true_size] = '\0';
			int tmp = direct_lseek(fd, -((size - true_size) - 1), SEEK_CUR);
			if (tmp == -1) {
				err = true;
				break;
			}

			line = realloc(line as byte*, (true_size + 1) * sizeof{char}) as char*;
			if (line == NULL as char*) {
				err = true;
				break;
			}

			return line;
		}

		capacity <<= 1;
		line = realloc(line as byte*, capacity * sizeof{char}) as char*;
		if (line == NULL as char*) {
			err = true;
			break;
		}

		err = false;
	} 

	if (err) {
		free(line as byte*);
		return NULL as char*;
	}

	line[size] = '\0';
	line = realloc(line as byte*, (size + 1) * sizeof{char}) as char*;

	return line;
}

func char* read_file(const char* path) {
	type stat st;
	int ret_code = direct_stat(path, st$);

	if (ret_code == -1) return NULL as char*;

	int fd = direct_open(path, O_RDONLY);
	if (fd == -1) return NULL as char*;

	char* ret = malloc((st.st_size + 1) * sizeof{char})
		as char*;

	ret_code = direct_read(fd, ret, st.st_size);
	if (ret_code < 0) return NULL as char*;
	ret[st.st_size as unsigned int] = 0;

	direct_close(fd);
	return ret;
}

func bool write_file(const char* path, const char* text) {
	int fd = direct_open2(path, O_WRONLY | O_CREAT, S_IRUSR | S_IWUSR);
	if (fd == -1) return false;

	int ret_code = direct_write(fd, text, strlen(text));
	if (ret_code < 0) return false;

	direct_close(fd);
	return true;
}

func bool append_lines(const char* path, type vector::vector* lines) {
	int fd = direct_open2(path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR);
	if (fd == -1) return false;

	for (unsigned int i = 0; i < vector::size(lines); i++) {
		type string::string* line = vector::at(lines, i) as type string::string** @;
		char nl = '\n';
		
		int ret_code = direct_write(fd, string::data(line), string::length(line));
		if (ret_code < 0) return false;

		ret_code = direct_write(fd, nl$, 1);
		if (ret_code < 0) return false;
	}

	direct_close(fd);
	return true;
}

func type dir_entries* list_dir(const char* path) {
	constexpr unsigned int BUF_SIZE = 1024;

	int fd = direct_openat(AT_FDCWD, path, O_RDONLY | O_DIRECTORY);
	if (fd == -1) return NULL as type dir_entries*;

	type dir_entries* dents = malloc(sizeof{type dir_entries}) as type dir_entries*;
	dents->files = vector::new_vector(sizeof{type string::string*});
	dents->dirs = vector::new_vector(sizeof{type string::string*});
	for ( ; ; ) {
		byte* buf = stk byte(BUF_SIZE);
		int nread = direct_getdents(fd, buf, BUF_SIZE);
		if (nread == -1) {
			vector::delete_vector(dents->files);
			vector::delete_vector(dents->dirs);
			free(dents as byte*);

			dents = NULL as type dir_entries*;
			break;
		}
		if (nread == 0)
			break;
		char* d_name = buf[LINUX_DIRENT_d_name_OFFSET]$ as char*;
		long d_off = buf[LINUX_DIRENT_d_off_OFFSET]$ as long* @;
		unsigned short d_reclen = buf[LINUX_DIRENT_d_reclen_OFFSET]$ as unsigned short* @;
		char d_type = buf[d_reclen - 1]$ as char* @;
		
		type string::string* file = string::new_string(d_name);
		type vector::vector* to_use = NULL as type vector::vector*;
		switch (d_type) {
		case DT_DIR:
			to_use = dents->dirs;
			break;
		case DT_REG:
			to_use = dents->files;
			break;
		}
		if (to_use != NULL as type vector::vector*) {
			util::maybe_report_ice(!vector::append(to_use, file$ as byte*) as bool,
				"Could not keep track of directory entries in directory!");
		}
		direct_lseek(fd, d_off, SEEK_SET);
	}
	direct_close(fd);
	return dents;
}

func type string::string* basename(char* path) {
	unsigned int path_len = strlen(path);
	bool non_slash_hit = false;
	unsigned int start = 0, end = path_len;
	for (unsigned int i = path_len; i > 0 ; i--) {
		unsigned int index = i - 1;
		char curr = path[index];
		if (curr == '/') {
			if (!non_slash_hit) {}
			else {
				start = index + 1;
				break;
			}
		}
		else {
			if (!non_slash_hit) end = index + 1;
			non_slash_hit = true;
		}
	}

	util::maybe_report_ice(end >= start,
		"Expected a valid substring to extract from the path to form a basename.");
	if (!non_slash_hit) {
		return string::new_string(path_len == 0 ? "" : "/");
	}
	else {
		char* s = malloc((end - start) + 1) as char*;
		strncpy(s, path[start]$, end - start);
		s[end - start] = '\0';
		type string::string* ret = string::new_string(s);
		free(s as byte*);
		return ret;
	}
	
}

func type string::string* path_cat(const char* root, const char* next) {
	type string::string* ret = string::new_string(root);
	type string::string* ret2 = string::addc(ret, PATH_SEP);
	type string::string* ret3 = string::addc(ret2, next);

	string::delete_string(ret);
	string::delete_string(ret2);
	return ret3;
}

func bool delete_file(const char* path) {
	return direct_unlink(path) == 0;
}

func bool delete_dir(const char* path, bool rec) {
	type dir_entries* dents = list_dir(path);
	bool success = true;

	for (unsigned int i = 0; i < vector::size(dents->files); i++) {
		type string::string* curr = vector::at(dents->files, i)
			as type string::string** @;
		type string::string* full = path_cat(path, string::data(curr));
		success = delete_file(string::data(full)) && success;

		string::delete_string(full);
		string::delete_string(curr);
	}

	if (!rec) {
		for (unsigned int i = 0; i < vector::size(dents->dirs); i++)
			string::delete_string(vector::at(dents->dirs, i) as type string::string** @);
		free(dents as byte*);

		return direct_rmdir(path) == 0 && success;
	}

	for (unsigned int i = 0; i < vector::size(dents->dirs); i++) {
		type string::string* curr = vector::at(dents->dirs, i)
			as type string::string** @;
		if (string::ceq(".", curr) || string::ceq("..", curr))
			continue;

		type string::string* full = path_cat(path, string::data(curr));
		success = delete_dir(string::data(full), rec) && success;

		string::delete_string(full);
		string::delete_string(curr);
	}

	vector::delete_vector(dents->files);
	vector::delete_vector(dents->dirs);
	free(dents as byte*);

	return success && direct_rmdir(path) == 0;
}

} } // namespace shadow::util
