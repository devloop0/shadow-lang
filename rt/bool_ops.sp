import "rt/ops.hsp"

import <"std/lib">

import "rt/prim_object.hsp"
import "rt/object.hsp"
import "rt/util.hsp"

using std::lib::NULL;

namespace shadow { namespace rt {

namespace bool_ops {

static constexpr unsigned int AND = 0x0,
	OR = 0x1,
	NOT = 0x2;

} // namespace bool_ops

func[static] type object* bool_binop(type object* o1, type object* o2, unsigned int op) {
	check_bool(o1, "Expected a boolean lhs for a boolean binary operation!");
	check_bool(o2, "Expected a boolean rhs for a boolean binary operation!");
	
	bool b1 = o1->which.po->which.b, b2 = o2->which.po->which.b;
	switch (op) {
	case bool_ops::AND: return init_bool(b1 && b2);
	case bool_ops::OR: return init_bool(b1 || b2);
	}

	unreachable("Invalid binary operation provided for two booleans!");
	return NULL as type object*;
}

func[static] type object* bool_unop(type object* o1, unsigned int op) {
	check_bool(o1, "Expected a boolean for a boolean unary operation!");

	bool b1 = o1->which.po->which.b;
	switch (op) {
	case bool_ops::NOT: return init_bool(!b1);
	}

	unreachable("Invalid unary operation provided for a boolean!");
	return NULL as type object*;
}

func type object* and_bool(type object* o1, type object* o2) {
	return bool_binop(o1, o2, bool_ops::AND);
}

func type object* or_bool(type object* o1, type object* o2) {
	return bool_binop(o1, o2, bool_ops::OR);
}

func type object* not_bool(type object* o1) {
	return bool_unop(o1, bool_ops::NOT);
}

} } // namespace shadow::rt
