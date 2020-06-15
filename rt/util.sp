import "rt/util.hsp"

import <"std/string">
import <"std/io">
import <"std/lib">
import <"stdx/vector">

import "rt/row_object.hsp"
import "rt/object.hsp"
import "rt/prim_object.hsp"
import "util/symtab.hsp"
import "util/stack.hsp"

using namespace stdx::vector;
using std::lib::malloc;
using std::string::strcmp;
using std::io::printf;
using std::lib::abort;
using std::lib::NULL;

namespace shadow { namespace rt {

func[static] bool symtab_str_cmp(const byte* a, const byte* b) {
	const char* f = a as const char** @,
	s = b as const char** @;
	return !strcmp(f, s) as bool;
}

func[static] type util::symtab* create_scope_helper(
	type util::symtab* parent_scope) {
	type util::symtab* s = malloc(sizeof{type util::symtab})
		as type util::symtab*;
	util::init_symtab(s, sizeof{char*}, sizeof{type rt::object*},
		symtab_str_cmp, parent_scope);
	return s;
}

func type util::symtab* init_rt() {
	return create_scope_helper(NULL as type util::symtab*);
}
		
func type util::symtab* scope_push(type util::symtab* parent_scope) {
	return create_scope_helper(parent_scope);
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

func void check(bool b, char* msg) {
	if (!b) {
		printf("Assertion error: %s\n", msg);
		abort();
	}
}

func void check_row(type object* o, char* msg) {
	check(o != NULL as type object*, msg);
	check(o->kind == object_kind::ROW, msg);

	type row_object* ro = o->which.ro;
	check(vector::size(ro->keys) == vector::size(ro->values), msg);
}

func[static] void check_primitive(type object* o, char* msg,
	unsigned int kind) {
	check(o != NULL as type object*, msg);
	check(o->kind == object_kind::PRIM, msg);
	check(o->which.po->kind == kind, msg);
}

func void check_int(type object* o, char* msg) {
	check_primitive(o, msg, prim_kind::INT);
}

func void check_real(type object* o, char* msg) {
	check_primitive(o, msg, prim_kind::REAL);
}

func void check_string(type object* o, char* msg) {
	check_primitive(o, msg, prim_kind::STRING);
}

func void check_bool(type object* o, char* msg) {
	check_primitive(o, msg, prim_kind::BOOL);
}

func void check_char(type object* o, char* msg) {
	check_primitive(o, msg, prim_kind::CHAR);
}

func void check_unit(type object* o, char* msg) {
	check_primitive(o, msg, prim_kind::UNIT);
}

func void unreachable(char* msg) {
	printf("Unreachable: %s\n", msg);
	abort();
}

} } // namespace shadow::rt
