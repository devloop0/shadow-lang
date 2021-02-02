import "src/compile.hsp"

import <"stdx/vector">
import <"stdx/string">
import <"std/io">
import <"std/lib">

import "util/file.hsp"
import "util/symtab.hsp"
import "util/error.hsp"

using namespace stdx::vector;
using namespace stdx::string;

using std::io::printf;
using std::lib::malloc;
using std::lib::NULL;

namespace shadow { namespace compile {

func[static] bool symtab_stdx_str_cmp(const byte* a, const byte* b) {
	type string::string* sa = a as type string::string** @,
		sb = b as type string::string** @;
	return string::eq(sa, sb);
}

func type util::symtab* parse_metadata_file(const char* path) {
	type vector::vector* lines = util::read_lines(path);

	type util::symtab* ret = malloc(sizeof{type util::symtab})
		as type util::symtab*;
	util::init_symtab(ret, sizeof{type string::string*}, sizeof{type vector::vector*},
		symtab_stdx_str_cmp, NULL as type util::symtab*);

	type vector::vector* curr_members = NULL as type vector::vector*;
	for (unsigned int i = 0; i < vector::size(lines); i++) {
		type string::string* curr = vector::at(lines, i) as type string::string** @;

		if (string::length(curr) == 0) continue;

		if (string::at(curr, 0) == '\t') {
			if (curr_members == NULL as type vector::vector*) {
				printf("%s[%u]: No header associated with this ('%s') member!\n",
					path, i + 1, string::data(curr)[1]$);
				return NULL as type util::symtab*;
			}

			type string::string* tab_removed = string::new_string(string::data(curr)[1]$);
			util::maybe_report_ice(!vector::append(curr_members, tab_removed$ as byte*) as bool,
				"Could not keep track of members of a header while parsing a metadata file!");
		}
		else {
			byte* check = util::symtab_lookup(ret, curr$ as byte*, false);
			if (check == NULL) {
				curr_members = vector::new_vector(sizeof{type string::string*});
				util::symtab_set(ret, curr$ as byte*, curr_members$ as byte*);
			}
			else
				curr_members = check as type vector::vector** @;
		}
	}

	return ret;
}

func bool extract_metadata_bool(type vector::vector* vals, bool* res) {
	if (vector::size(vals) != 1) {
		return false;
	}
	type string::string* line = vector::at(vals, 0) as type string::string** @;

	if (string::ceq("true", line)) {
		res@ = true;
		return true;
	}
	else if (string::ceq("false", line)) {
		res@ = false;
		return true;
	}
	return false;
}

func type module_config* parse_module_config(const char* module_root,
	const char* module_name) {
	type string::string* cfg_path = util::path_cat(module_root, MOD_SDW_CFG);

	type module_config* cfg = malloc(sizeof{type module_config})
		as type module_config*;
	cfg->visibility = false;
	cfg->src_visibility = false;
	cfg->sp_resources = vector::new_vector(sizeof{type string::string*});

	if (!util::file_exists(string::data(cfg_path))) return cfg;

	type util::symtab* res = parse_metadata_file(string::data(cfg_path));
	if (res == NULL as type util::symtab*) return NULL as type module_config*;

	for (unsigned int i = 0; i < vector::size(res->keys); i++) {
		type string::string* header = vector::at(res->keys, i) as type string::string** @;
		type vector::vector* members = vector::at(res->values, i) as type vector::vector** @;

		if (string::ceq(CFG_VISIBILITY_HEADER, header)) {
			bool res;
			if (!extract_metadata_bool(members, res$)) {
				printf("Invalid value(s) found for the '%s' header in '%s''s module config!\n",
					CFG_VISIBILITY_HEADER, module_name);
				return NULL as type module_config*;
			}
			cfg->visibility = res;
		}
		else if (string::ceq(CFG_SRC_VISIBILITY_HEADER, header)) {
			bool res;
			if (!extract_metadata_bool(members, res$)) {
				printf("Invalid value(s) found for the '%s' header in '%s''s module config!\n",
					CFG_SRC_VISIBILITY_HEADER, module_name);
				return NULL as type module_config*;
			}
			cfg->src_visibility = res;
		}
		else if (string::ceq(CFG_SP_RESOURCES_HEADER, header))
			cfg->sp_resources = members;
		else {
			printf("Unexpected header: '%s' found in module: '%s''s config!\n",
				string::data(header), module_name);
			return NULL as type module_config*;
		}
	}

	return cfg;
}

} } // namespace shadow::compile
