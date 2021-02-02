import "src/compile.hsp"

import <"std/io">
import <"std/lib">
import <"std/ctype">
import <"stdx/vector">
import <"stdx/string">
import <"std/syscall">

import "cgen/cgen.hsp"
import "tck/debug.hsp"
import "tck/util.hsp"
import "tck/constrain.hsp"
import "util/error.hsp"
import "util/symtab.hsp"
import "tck/env.hsp"
import "lex/lex.hsp"
import "lex/token.hsp"
import "util/error.hsp"
import "parse/parse.hsp"
import "ast/ast.hsp"
import "tck/unify.hsp"
import "util/stack.hsp"
import "util/file.hsp"
import "cgen/cgen.hsp"
import "cgen/util.hsp"

using namespace shadow;
using namespace stdx::vector;
using namespace stdx::string;
using std::io::printf;
using std::lib::NULL;
using std::lib::malloc;
using std::ctype::isalpha;
using std::ctype::isalnum;
using std::lib::rand;
using std::lib::srand;
using std::syscall::direct_gettimeofday;
using std::syscall::timeval;
using std::syscall::timezone;
using std::syscall::direct_open;
using std::syscall::O_RDONLY;

namespace shadow { namespace compile {

func[static] void print_module_name(type vector::vector* module_name) {
	for (unsigned int i = 0; i < vector::size(module_name); i++) {
		char* curr = vector::at(module_name, i) as char** @;
		if (curr != NULL as char*) printf(".%s", curr);
	}
}

func[static] bool parse_module_metadata_helper(const char* file_name, const char* header,
	type vector::vector* data, type util::symtab* st) {
	type string::string* data_string = string::new_string("");
	for (unsigned int i = 0; i < vector::size(data); i++) {
		type string::string* s = vector::at(data, i) as type string::string** @;
		data_string = string::add(data_string, s);
		data_string = string::addc(data_string, "\n");
	}

	type lex::buffer* buf = malloc(sizeof{type lex::buffer}) as type lex::buffer*;
	lex::init_buffer(buf, file_name as char*, string::data(data_string), true);
	type parse::parser* p = malloc(sizeof{type parse::parser}) as type parse::parser*;
	parse::init_parser(p, buf);

	type string::string* err_text_start = string::new_string(
		"Error parsing metadata file for header: '");
	err_text_start = string::addc(err_text_start, header);
	err_text_start = string::addc(err_text_start, "'");
	type lex::token* ptok = parse::peek(p);
	while (ptok->tok_type != lex::tokens::EOF) {
		if (ptok->tok_type != lex::tokens::IDENT) {
			util::report_token_error(util::error_kind::ERR, buf, ptok,
				string::data(string::addc(err_text_start, "; expected an identifier!")));
			return false;
		}

		parse::pop(p);
		char* ident_text = tck::extract_token_text(NULL as type tck::env*, ptok);

		ptok = parse::peek(p);
		if (ptok->tok_type != lex::tokens::EQUALS) {
			util::report_token_error(util::error_kind::ERR, buf, ptok,
				string::data(string::addc(err_text_start, "; expected an '='!")));
			return false;
		}

		parse::pop(p);
		type ast::typ* t = parse::parse_typ(p);
		if (t == NULL as type ast::typ*) return false;

		ptok = parse::peek(p);
		if (ptok->tok_type != lex::tokens::DOLLAR_SIGN) {
			util::report_token_error(util::error_kind::ERR, buf, ptok,
				string::data(string::addc(err_text_start, "; expected a '$'!")));
			return false;
		}

		// printf("Found: %s = ", ident_text), tck::print_typ(NULL as type tck::env*, t), printf("\n");
		util::symtab_set(st, ident_text$ as byte*, t$ as byte*);

		parse::pop(p);
		ptok = parse::peek(p);
	}

	return true;
}

func type tck::module* parse_module_metadata(type vector::vector* module_name,
	type tck::module* module_context) {
	type string::string* file_name = string::new_string("");
	for (unsigned int i = 0; i < vector::size(module_name); i++) {
		char* curr = vector::at(module_name, i) as char** @;
		if (curr != NULL as char*) {
			file_name = string::addc(file_name, MOD_FILE_SEP);
			file_name = string::addc(file_name, curr);
		}
	}
	type string::string* full_module_name = file_name;
	file_name = string::addc(file_name, ".");
	file_name = string::addc(file_name, MOD_FILE_EXT);
	file_name = util::path_cat(GLOBAL_MOD_DIR, string::data(file_name));

	// printf("File name: %s\n", string::data(file_name));

	if (!util::file_exists(string::data(file_name))) {
		printf("The metadata file for the module: '");
		print_module_name(module_name);
		printf("' not found!\n");
		return NULL as type tck::module*;
	}

	type util::symtab* st = parse_metadata_file(string::data(file_name));
	if (st == NULL as type util::symtab*) return NULL as type tck::module*;

	type tck::module* ret = malloc(sizeof{type tck::module})
		as type tck::module*;
	tck::init_module(ret, NULL as char*, module_context, module_context->global_module, false);

	type tck::env* curr_env = malloc(sizeof{type tck::env}) as type tck::env*;
	tck::init_env(curr_env, NULL as type parse::parser*, ret);
	ret->e = curr_env;

	bool name_header_hit = false, namespaces_header_hit = false,
		types_header_hit = false, symbols_header_hit = false,
		datatypes_header_hit = false, datatype_constructors_header_hit = false,
		visibility_header_hit = false, submodules_header_hit = false,
		imported_modules_header_hit = false;
	for (unsigned int i = 0; i < util::symtab_num_entries(st); i++) {
		type string::string* curr_header = vector::at(st->keys, i) as type string::string** @;
		type vector::vector* curr_members = vector::at(st->values, i) as type vector::vector** @;

		if (string::eqc(curr_header, MOD_NAME_HEADER)) {
			if (vector::size(curr_members) != 1) {
				printf("Expected a (single) name in module '");
				print_module_name(module_name);
				printf("''s metadata file!\n");
				return NULL as type tck::module*;
			}

			name_header_hit = true;
			type string::string* extracted_module_name = vector::at(curr_members, 0)
				as type string::string** @;
			// printf("Module name: %s\n", string::data(extracted_module_name));
			ret->module_name = string::data(extracted_module_name);
		}
		else if (string::eqc(curr_header, MOD_NAMESPACES_HEADER)) {
			ret->namespaces = curr_members;
			namespaces_header_hit = true;

			/* printf ("Module namespaces:\n");
			for (unsigned int i = 0; i < vector::size(ret->namespaces); i++) {
				printf("%s\n", string::data(vector::at(ret->namespaces, i) as type string::string** @));
			} */
		}
		else if (string::eqc(curr_header, MOD_TYPES_HEADER)) {
			if (!parse_module_metadata_helper(string::data(file_name), MOD_TYPES_HEADER,
				curr_members, curr_env->global_scope.typ_2_typ_var)) {
				printf("Could not parse types in module '");
				print_module_name(module_name);
				printf("''s metadata file!\n");
				return NULL as type tck::module*;
			}

			types_header_hit = true;
		}
		else if (string::eqc(curr_header, MOD_SYMBOLS_HEADER)) {
			if (!parse_module_metadata_helper(string::data(file_name), MOD_SYMBOLS_HEADER,
				curr_members, curr_env->global_scope.sym_2_typ_var)) {
				printf("Could not parse symbols in module '");
				print_module_name(module_name);
				printf("''s metadata file!\n");
				return NULL as type tck::module*;
			}
			
			symbols_header_hit = true;
		}
		else if (string::eqc(curr_header, MOD_DATATYPES_HEADER)) {
			if (!parse_module_metadata_helper(string::data(file_name), MOD_DATATYPES_HEADER,
				curr_members, curr_env->global_scope.datatyp_2_typ_var)) {
				printf("Could not parse datatypes in module '");
				print_module_name(module_name);
				printf("''s metadata file!\n");
				return NULL as type tck::module*;
			}
	
			datatypes_header_hit = true;
		}
		else if (string::eqc(curr_header, MOD_DATATYPE_CONSTRUCTORS_HEADER)) {
			if (!parse_module_metadata_helper(string::data(file_name), MOD_DATATYPE_CONSTRUCTORS_HEADER,
				curr_members, curr_env->global_scope.datatyp_constructor_2_typ_var)) {
				printf("Could not parse datatype constructors in module '");
				print_module_name(module_name);
				printf("''s metadata file!\n");
				return NULL as type tck::module*;
			}

			datatype_constructors_header_hit = true;
		}
		else if (string::eqc(curr_header, MOD_VISIBILITY_HEADER)) {
			bool visibility;
			if (!extract_metadata_bool(curr_members, visibility$)) {
				printf("Expected a (single) valid visibility in module '");
				print_module_name(module_name);
				printf("''s metadata file!\n");
				return NULL as type tck::module*;
			}

			visibility_header_hit = true;
			// printf("Module visibility: %s\n", visibility ? "true" : "false");
			ret->visibility = visibility;
		}
		else if (string::eqc(curr_header, MOD_SUBMODULES_HEADER)) {
			for (unsigned int i = 0; i < vector::size(curr_members); i++) {
				type string::string* curr = vector::at(curr_members, i) as type string::string** @;
				char* curr_str = string::data(curr);
				type vector::vector* new_module_name = vector::new_vector(sizeof{char*});
				for (unsigned int i = 0; i < vector::size(module_name); i++) {
					char* curr_mn_str = vector::at(module_name, i) as char** @;
					util::maybe_report_ice(!vector::append(new_module_name, curr_mn_str$ as byte*) as bool,
						"Could not construct hierarchy for submodule name!");
				}
				util::maybe_report_ice(!vector::append(new_module_name, curr_str$ as byte*) as bool,
					"Could not finish constructing full submodule name!");

				// printf("Submodule name: "), print_module_name(new_module_name), printf("\n");
				type tck::module* sub_ret = parse_module_metadata(new_module_name, ret);
				if (sub_ret == NULL as type tck::module*)
					return NULL as type tck::module*;
				util::symtab_set(ret->submodules, curr_str$ as byte*, sub_ret$ as byte*);

				// printf("\n");
			}

			submodules_header_hit = true;
		}
		else if (string::eqc(curr_header, MOD_IMPORTED_MODULES_HEADER)) {
			for (unsigned int i = 0; i < vector::size(curr_members); i++){
				type string::string* curr = vector::at(curr_members, i) as type string::string** @;
				char* imported_str = string::data(curr)[1]$;
				char* full_imported_str = string::data(curr);

				// printf("Imported module name: %s\n", imported_str);

				type vector::vector* wrapper = vector::new_vector(sizeof{char*});
				util::maybe_report_ice(!vector::append(wrapper, imported_str$ as byte*) as bool,
					"Could not wrap imported module name");

				type tck::module* imported_ret = parse_module_metadata(wrapper, ret);
				if (imported_ret == NULL as type tck::module*)
					return NULL as type tck::module*;

				util::symtab_set(ret->imported_modules, full_imported_str$ as byte*, imported_ret$ as byte*);

				// printf("\n");
			}

			imported_modules_header_hit = true;
		}
		else {
			printf("%s[%u]: Unrecognized header: '%s' found in the metadata file!\n",
				string::data(file_name), i + 1, string::data(curr_header));
			return NULL as type tck::module*;
		}
	}

	if (!name_header_hit || !namespaces_header_hit
		|| !types_header_hit || !symbols_header_hit
		|| !datatypes_header_hit || !datatype_constructors_header_hit
		|| !visibility_header_hit || !submodules_header_hit
		|| !imported_modules_header_hit) {
		printf("Missing a header in module '");
		print_module_name(module_name);
		printf("''s metadata file!");
		return NULL as type tck::module*;
	}

	return ret;
}

} } // namespace shadow::compile
