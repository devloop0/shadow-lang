import "rt/cmps.hsp"

import <"std/lib">

import "rt/object.hsp"
import "rt/prim_object.hsp"
import "rt/util.hsp"

using std::lib::NULL;

namespace shadow { namespace rt {

namespace cmp_ops {

static constexpr unsigned int LT = 0x0,
	LE = 0x1,
	GT = 0x2,
	GE = 0x3;

} // namespace cmp_ops

func[static] type object* int_cmp(type object* o1, type object* o2, unsigned int op) {
	check_int(o1, "Expected an integer lhs for an integer ordering comparison operation!");
	check_int(o2, "Expected an integer rhs for an integer ordering comparison operation!");

	int i1 = o1->which.po->which.i, i2 = o2->which.po->which.i;
	switch (op) {
	case cmp_ops::LT: return init_bool(i1 < i2);
	case cmp_ops::GT: return init_bool(i1 > i2);
	case cmp_ops::LE: return init_bool(i1 <= i2);
	case cmp_ops::GE: return init_bool(i1 >= i2);
	}

	unreachable("Unexpected integer ordering comparison operation found!");
	return NULL as type object*;
}

func[static] type object* real_cmp(type object* o1, type object* o2, unsigned int op) {
	check_real(o1, "Expected a real lhs for a real ordering comparison operation!");
	check_real(o2, "Expected a real rhs for a real ordering comparison operation!");

	double d1 = o1->which.po->which.d, d2 = o2->which.po->which.d;
	switch (op) {
	case cmp_ops::LT: return init_bool(d1 < d2);
	case cmp_ops::GT: return init_bool(d1 > d2);
	case cmp_ops::LE: return init_bool(d1 <= d2);
	case cmp_ops::GE: return init_bool(d1 >= d2);
	}

	unreachable("Unexpected real ordering comparison operation found!");
	return NULL as type object*;
}

func type object* int_lt(type object* o1, type object* o2) {
	return int_cmp(o1, o2, cmp_ops::LT);
}

func type object* int_gt(type object* o1, type object* o2) {
	return int_cmp(o1, o2, cmp_ops::GT);
}

func type object* int_le(type object* o1, type object* o2) {
	return int_cmp(o1, o2, cmp_ops::LE);
}

func type object* int_ge(type object* o1, type object* o2) {
	return int_cmp(o1, o2, cmp_ops::GE);
}

func type object* real_lt(type object* o1, type object* o2) {
	return real_cmp(o1, o2, cmp_ops::LT);
}

func type object* real_gt(type object* o1, type object* o2) {
	return real_cmp(o1, o2, cmp_ops::GT);
}

func type object* real_le(type object* o1, type object* o2) {
	return real_cmp(o1, o2, cmp_ops::LE);
}

func type object* real_ge(type object* o1, type object* o2) {
	return real_cmp(o1, o2, cmp_ops::GE);
}

} } // namespace shadow::rt
