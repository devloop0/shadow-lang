import "rt/util.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/vector">

import "rt/row_object.hsp"
import "rt/object.hsp"
import "rt/prim_object.hsp"

using namespace stdx::vector;
using std::io::printf;
using std::lib::abort;
using std::lib::NULL;

namespace shadow { namespace rt {

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

func void runtime_error(char* msg) {
	printf("Runtime error: %s\n", msg);
	abort();
}

} } // namespace shadow::rt
