import "util/file.hsp"

import <"std/io">
import <"std/syscall">
import <"std/lib">
import <"std/string">

using std::syscall::direct_stat;
using std::syscall::stat;
using std::syscall::direct_open;
using std::syscall::direct_open2;
using std::syscall::O_RDONLY;
using std::syscall::direct_close;
using std::syscall::direct_read;
using std::syscall::O_WRONLY;
using std::syscall::O_CREAT;
using std::syscall::direct_write;
using std::string::strlen;
using std::lib::malloc;
using std::lib::NULL;
using std::io::printf;
using std::syscall::S_IRUSR;
using std::syscall::S_IWUSR;

namespace shadow { namespace util {

func char* read_file(char* path) {
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

func bool write_file(char* path, char* text) {
	int fd = direct_open2(path, O_WRONLY | O_CREAT, S_IRUSR | S_IWUSR);
	if (fd == -1) return false;

	int ret_code = direct_write(fd, text, strlen(text));
	if (ret_code < 0) return false;

	direct_close(fd);
	return true;
}

} } // namespace shadow::util
