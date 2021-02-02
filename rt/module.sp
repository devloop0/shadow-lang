import "rt/module.hsp"

import <"stdx/string">
import <"std/string">
import <"std/lib">
import <"std/io">
import <"std/arg">

import "rt/util.hsp"
import "rt/scope.hsp"
import "util/symtab.hsp"
import "rt/object.hsp"

using namespace stdx::string;
using std::string::strcmp;
using std::lib::malloc;
using std::lib::NULL;
using std::io::printf;
using std::arg::va_list;
using std::arg::va_start;
using std::arg::va_arg;
using std::arg::va_end;

namespace shadow { namespace rt {

static const char* MOD_SCOPE_NAME = "$";

// should be the same as compile::MOD_FILE_SEP
static const char* MOD_SEP = "@";

namespace internal {

static type util::symtab* global_module;
static type util::symtab* module_cache;

} // namespace internal

func[static] bool symtab_str_cmp(const byte* a, const byte* b) {
	const char* f = a as const char** @,
		s = b as const char** @;
	return !strcmp(f, s) as bool;
}

func[static] type util::symtab* create_module_helper(const char* full_name,
	type util::symtab* global_scope, bool is_global) {
	type util::symtab* ret = malloc(sizeof{type util::symtab})
		as type util::symtab*;
	util::init_symtab(ret, sizeof{char*}, sizeof{type util::symtab*},
		symtab_str_cmp, NULL as type util::symtab*);

	const char* tmp = MOD_SCOPE_NAME;
	util::symtab_set(ret, tmp$ as byte*, global_scope$ as byte*);

	if (!is_global) {
		util::symtab_set(internal::module_cache, full_name$ as byte*,
			ret$ as byte*);
	}

	return ret;
}

func type util::symtab* module_scope(type util::symtab* mod) {
	const char* tmp = MOD_SCOPE_NAME;
	byte* lookup_check = util::symtab_lookup(mod, tmp$ as byte*, false);
	check(lookup_check != NULL, "Expected a valid global scope for a module!");
	return lookup_check as type util::symtab** @;
}

func type util::symtab* global_module() {
	return internal::global_module;
}

func type util::symtab* init_module_subsystem(
	type util::symtab* global_scope) {
	internal::module_cache = malloc(sizeof{type util::symtab})
		as type util::symtab*;
	util::init_symtab(internal::module_cache, sizeof{char*}, sizeof{type util::symtab*},
		symtab_str_cmp, NULL as type util::symtab*);

	internal::global_module =
		create_module_helper("", global_scope, true);
	return internal::global_module;
}

func type util::symtab* lookup_module(const char* full_name) {
	byte* lookup_check = util::symtab_lookup(internal::module_cache,
		full_name$ as byte*, false);
	type string::string* err = string::new_string(
		"Could not find the provided module name: ");
	err = string::addc(err, full_name);
	err = string::addc(err, ".");
	check(lookup_check != NULL, string::data(err));

	string::delete_string(err);
	return lookup_check as type util::symtab** @;
}

func type util::symtab* lookup_or_create_module(const char* full_name) {
	byte* lookup_check = util::symtab_lookup(internal::module_cache,
		full_name$ as byte*, false);
	if (lookup_check != NULL)
		return lookup_check as type util::symtab** @;

	type util::symtab* gs = create_scope(NULL as type util::symtab*);
	return create_module_helper(full_name, gs, false);
}

func type object* lookup_name(const char* curr_mod_ctx,
	type util::symtab* scope, unsigned int num, ...) {
	check(num != 0, "Expected a valid name to lookup!");

	type va_list* args = va_start(num$ as byte*, sizeof{char*});

	char* initial;
	va_arg(args, initial$ as byte*, sizeof(initial), alignof(initial));

	if (num == 1) {
		type object* res = scope_lookup(scope, initial);
		va_end(args);
		return res;
	}

	if (initial == NULL as char* && num == 2) {
		char* sym_name;
		va_arg(args, sym_name$ as byte*, sizeof(sym_name),
			alignof(sym_name));

		type util::symtab* gs = module_scope(internal::global_module);
		type object* res = scope_lookup(gs, sym_name);
		va_end(args);
		return res;
	}

	type string::string* full_name = string::new_string("");
	if (initial != NULL as char*) {
		full_name = string::concatc(full_name, curr_mod_ctx);
		full_name = string::concatc(full_name, MOD_SEP);
		full_name = string::concatc(full_name, initial);
	}
	
	for (unsigned int _ = 1; _ < num - 1; _++) {
		char* name;
		va_arg(args, name$ as byte*, sizeof(name), alignof(name));
		full_name = string::concatc(full_name, MOD_SEP);
		full_name = string::concatc(full_name, name);
	}

	type util::symtab* mod = lookup_module(string::data(full_name));
	type util::symtab* ms = module_scope(mod);

	char* sym_name;
	va_arg(args, sym_name$ as byte*, sizeof(sym_name), alignof(sym_name));
	type object* res = scope_lookup(ms, sym_name);
	va_end(args);

	return res;
}

} } // namespace shadow::rt
