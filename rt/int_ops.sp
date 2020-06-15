import "rt/ops.hsp"

import <"std/lib">

import "rt/prim_object.hsp"
import "rt/object.hsp"
import "rt/util.hsp"

using std::lib::NULL;

namespace shadow { namespace rt {

namespace int_ops {

static constexpr unsigned int ADD = 0x0,
	SUB = 0x1,
	MUL = 0x2,
	DIV = 0x3,
	MOD = 0x4,
	SHL = 0x5,
	SHR = 0x6,
	BAND = 0x7,
	BOR = 0x8,
	XOR = 0x9,
	PLUS = 0xa,
	MINUS = 0xb,
	CMPL = 0xc;

} // namespace int_ops

func[static] type object* int_binop(type object* o1, type object* o2, unsigned int op) {
	check_int(o1, "Expected an integer lhs for an integer binary operation!");
	check_int(o2, "Expected an integer rhs for an integer binary operation!");

	int i1 = o1->which.po->which.i, i2 = o2->which.po->which.i, res;
	switch (op) {
	case int_ops::ADD: return init_int(i1 + i2);
	case int_ops::SUB: return init_int(i1 - i2);
	case int_ops::MUL: return init_int(i1 * i2);
	case int_ops::DIV: return init_int(i1 / i2);
	case int_ops::MOD: return init_int(i1 % i2);
	case int_ops::SHL: return init_int(i1 << i2);
	case int_ops::SHR: return init_int(i1 >> i2);
	case int_ops::BAND: return init_int(i1 & i2);
	case int_ops::BOR: return init_int(i1 | i2);
	case int_ops::XOR: return init_int(i1 ^ i2);
	}

	unreachable("Invalid binary operation provided for two integers!");
	return NULL as type object*;
}

func[static] type object* int_unop(type object* o1, unsigned int op) {
	check_int(o1, "Expected an integer for an integer unary operation!");
	
	int i1 = o1->which.po->which.i;
	switch (op) {
	case int_ops::PLUS: return init_int(+i1);
	case int_ops::MINUS: return init_int(-i1);
	case int_ops::CMPL: return init_int(~i1);
	}

	unreachable("Invalid unary operation provided for an integer!");
	return NULL as type object*;
}

func type object* add_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::ADD);
}

func type object* sub_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::SUB);
}

func type object* mul_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::MUL);
}

func type object* div_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::DIV);
}

func type object* mod_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::MOD);
}

func type object* shl_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::SHL);
}

func type object* shr_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::SHR);
}

func type object* band_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::BAND);
}

func type object* bor_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::BOR);
}

func type object* xor_int(type object* o1, type object* o2) {
	return int_binop(o1, o2, int_ops::XOR);
}

func type object* plus_int(type object* o1) {
	return int_unop(o1, int_ops::PLUS);
}

func type object* minus_int(type object* o1) {
	return int_unop(o1, int_ops::MINUS);
}

func type object* cmpl_int(type object* o1) {
	return int_unop(o1, int_ops::CMPL);
}

} } // namespace shadow::rt
