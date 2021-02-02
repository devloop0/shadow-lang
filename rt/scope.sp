import "rt/scope.hsp"

import <"std/string">
import <"std/io">
import <"std/lib">

import "rt/util.hsp"
import "util/symtab.hsp"
import "rt/module.hsp"

using std::lib::malloc;
using std::string::strcmp;
using std::lib::NULL;

namespace shadow { namespace rt {

func[static] bool symtab_str_cmp(const byte* a, const byte* b) {
	const char* f = a as const char** @,
	s = b as const char** @;
	return !strcmp(f, s) as bool;
}

func type util::symtab* create_scope(type util::symtab* parent_scope) {
	type util::symtab* s = malloc(sizeof{type util::symtab})
		as type util::symtab*;
	util::init_symtab(s, sizeof{char*}, sizeof{type rt::object*},
		symtab_str_cmp, parent_scope);
	return s;
}

func type util::symtab* init_rt() {
	type util::symtab* s = create_scope(NULL as type util::symtab*);
	type util::symtab* gm = init_module_subsystem(s);
	return s;
}
		
func type util::symtab* scope_push(type util::symtab* parent_scope) {
	return create_scope(parent_scope);
}
		
func type rt::object* scope_lookup(type util::symtab* scope, char* name) {
	return util::symtab_lookup(scope, name$ as byte*, true)
		as type rt::object** @;
}
		
func void scope_set(type util::symtab* scope, char* name,
	type rt::object* obj) {
	util::symtab_set(scope, name$ as byte*, obj$ as byte*);
}

func type util::symtab* scope_pop(type util::symtab* scope) {
	return scope->parent;
}

} } // namespace shadow::rt
