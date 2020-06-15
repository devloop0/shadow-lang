import "rt/io.hsp"

import <"stdx/vector">
import <"std/io">
import <"std/lib">

import "rt/util.hsp"
import "rt/object.hsp"
import "rt/fun_object.hsp"
import "rt/prim_object.hsp"
import "rt/tup_object.hsp"
import "rt/row_object.hsp"

using std::lib::NULL;
using std::io::printf;
using namespace stdx::vector;

namespace shadow { namespace rt { namespace io {

func[static] int print_helper(type object* obj, bool d) {
	check(obj != NULL as type object*, "Expected a non-NULL rt::object* to print!");

	int ret = 0;
	switch (obj->kind) {
	case object_kind::PRIM: {
		type prim_object* pobj = obj->which.po;
		switch (pobj->kind) {
		case prim_kind::INT:
			ret += printf("%d", pobj->which.i);
			break;
		case prim_kind::CHAR:
			ret += (d ? printf("'") : 0);
			ret += printf("%c", pobj->which.c);
			ret += (d ? printf("'") : 0);
			break;
		case prim_kind::STRING:
			ret += (d ? printf("\"") : 0);
			ret += printf("%s", pobj->which.s);
			ret += (d ? printf("\"") : 0);
			break;
		case prim_kind::REAL:
			// TODO: Remove this limitation!
			unreachable("Currently, printing real's is not supported by rt::io::print_helper!");
			return -1;
		case prim_kind::UNIT:
			ret += printf("()");
			break;
		case prim_kind::BOOL:
			ret += printf("%s", pobj->which.b ? "true" : "false");
			break;
		}
	}
		break;
	case object_kind::TUP: {
		type vector::vector* tup = obj->which.tup;

		ret += printf("(");
		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type object* curr = vector::at(tup, i) as type object** @;

			print_helper(curr, d);
			if (i != vector::size(tup) - 1) ret += printf(", ");
		}
		ret += printf(")");
	}
		break;
	case object_kind::FUN: {
		ret += printf("[fn 0x%p]", obj->which.fo->fun);
	}
		break;
	case object_kind::ROW: {
		type row_object* row = obj->which.ro;
		check(vector::size(row->keys) == vector::size(row->values),
			"Expected a consistent row object to print!");

		ret += printf("{");
		for (unsigned int i = 0; i < vector::size(row->keys); i++) {
			char* key = vector::at(row->keys, i) as char** @;
			type object* curr = vector::at(row->values, i) as type object** @;
			ret += printf("%s: ", key);
			ret += print_helper(curr, d);
			if (i != vector::size(row->keys) - 1) ret += printf(", ");
		}
		ret += printf("}");
	}
		break;
	default:
		unreachable("Unknown rt::object_kind found in rt::io::print_helper!");
		return -1;
	}

	return ret;
}

func int print(type object* obj) {
	return print_helper(obj, false);
}

func int println(type object* obj) {
	return print_helper(obj, false) + printf("\n");
}

func int debug(type object* obj) {
	return print_helper(obj, true);
}

func int debugln(type object* obj) {
	return print_helper(obj, true) + printf("\n");
}

} } } // namespace shadow::rt::io
