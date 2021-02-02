import "tck/constrain.hsp"

import <"stdx/vector">
import <"stdx/string">
import <"std/string">
import <"std/io">
import <"std/lib">

import "ast/ast.hsp"
import "tck/env.hsp"
import "tck/util.hsp"
import "src/compile.hsp"
import "util/symtab.hsp"
import "lex/token.hsp"
import "util/error.hsp"

using namespace stdx::vector;
using namespace stdx::string;
using std::io::printf;
using std::lib::NULL;
using std::string::strncmp;

namespace shadow { namespace tck {

func bool handle_mod_import(type env* e, type ast::mod_import* mi) {
	type vector::vector* module_name = get_name_from_identifier(e, mi->module_ref);
	type vector::vector* full_module_name = to_fully_qualified_name(e, module_name);
	type string::string* full_module_name_str = string::new_string("");
	for (unsigned int i = 0; i < vector::size(full_module_name); i++) {
		char* curr = vector::at(full_module_name, i) as char** @;
		if (curr != NULL as char*) {
			full_module_name_str = string::addc(full_module_name_str, compile::MOD_FILE_SEP);
			full_module_name_str = string::addc(full_module_name_str, curr);
		}
	}
	char* full_module_name_pstr = string::data(full_module_name_str);
	byte* lookup_check = util::symtab_lookup(e->mod_ref->imported_modules,
		full_module_name_pstr$ as byte*, false);
	if (lookup_check != NULL) return true;

	type module* mod = compile::parse_module_metadata(full_module_name, e->mod_ref);
	if (mod == NULL as type module*) return false;

	type string::string* curr_module_name = tck::extract_module_name(e->mod_ref,
		compile::MOD_FILE_SEP);
	bool curr_is_global = e->mod_ref == e->mod_ref->global_module;
	bool curr_is_parent_module = false;
	if (string::length(curr_module_name) <= string::length(full_module_name_str)) {
		curr_is_parent_module = true;
		for (unsigned int i = 0; i < string::length(curr_module_name); i++) {
			if (string::data(curr_module_name)[i] != string::data(full_module_name_str)[i]) {
				curr_is_parent_module = false;
				break;
			}
		}
	}

	type lex::token* err_tok = get_non_null_token(mi->module_ref);
	if (!mod->visibility && (!curr_is_parent_module || curr_is_global)) {
		util::report_token_error(util::error_kind::ERR, e->par->buf, err_tok,
			"Could not import this module since it is invisible externally.");
		return false;
	}

	util::symtab_set(e->mod_ref->imported_modules, full_module_name_pstr$ as byte*, mod$ as byte*);
	return true;
}

} } // namespace shadow::tck
