import "rt/ops.hsp"

import <"std/lib">

import "rt/prim_object.hsp"
import "rt/object.hsp"
import "rt/util.hsp"

using std::lib::NULL;

namespace shadow { namespace rt {

namespace real_ops {

static constexpr unsigned int ADD = 0x0,
	SUB = 0x1,
	MUL = 0x2,
	DIV = 0x3,
	PLUS = 0x4,
	MINUS = 0x5;

} // namespace real_ops

func[static] type object* real_binop(type object* o1, type object* o2, unsigned int op) {
	check_real(o1, "Expected a real lhs for a real binary operation!");
	check_real(o2, "Expected a real rhs for a real binary operation!");

	double d1 = o1->which.po->which.d, d2 = o2->which.po->which.d;
	switch (op) {
	case real_ops::ADD: return init_real(d1 + d2);
	case real_ops::SUB: return init_real(d1 - d2);
	case real_ops::MUL: return init_real(d1 * d2);
	case real_ops::DIV: return init_real(d1 / d2);
	}

	unreachable("Invalid binary operation provided for two reals!");
	return NULL as type object*;
}

func[static] type object* real_unop(type object* o1, unsigned int op) {
	check_real(o1, "Expected a real for a real unary operation!");

	double d1 = o1->which.po->which.d;
	switch (op) {
	case real_ops::PLUS: return init_real(+d1);
	case real_ops::MINUS: return init_real(-d1);
	}

	unreachable("Invalid unary operation provided for a real!");
	return NULL as type object*;
}

func type object* add_real(type object* o1, type object* o2) {
	return real_binop(o1, o2, real_ops::ADD);
}

func type object* sub_real(type object* o1, type object* o2) {
	return real_binop(o1, o2, real_ops::SUB);
}

func type object* mul_real(type object* o1, type object* o2) {
	return real_binop(o1, o2, real_ops::MUL);
}

func type object* div_real(type object* o1, type object* o2) {
	return real_binop(o1, o2, real_ops::DIV);
}

func type object* plus_real(type object* o1) {
	return real_unop(o1, real_ops::PLUS);
}

func type object* minus_real(type object* o1) {
	return real_unop(o1, real_ops::MINUS);
}

} } // namespace shadow::rt
