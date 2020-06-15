import "rt/cmps.hsp"

import <"stdx/vector">
import <"std/string">

import "rt/row_object.hsp"
import "rt/fun_object.hsp"
import "rt/object.hsp"
import "rt/prim_object.hsp"
import "rt/util.hsp"
import "util/symtab.hsp"

using std::string::strcmp;
using namespace stdx::vector;

namespace shadow { namespace rt {

func[static] bool raw_equality_cmp(type object* o1, type object* o2, bool eq) {
	check(o1->kind == o2->kind, "Expected to compare two objects of the same type for (in)equality!");

	switch (o1->kind) {
	case object_kind::PRIM: {
		type prim_object* p1 = o1->which.po, p2 = o2->which.po;
		check(p1->kind == p2->kind, "Expected to compare two primitive objects of the same type for (in)equality!");

		switch (p1->kind) {
		case prim_kind::INT: {
			int i1 = p1->which.i, i2 = p2->which.i;
			return eq ? (i1 == i2) : (i1 != i2);
		}
		case prim_kind::CHAR: {
			char c1 = p1->which.c, c2 = p2->which.c;
			return eq ? (c1 == c2) : (c1 != c2);
		}
		case prim_kind::STRING: {
			char* s1 = p1->which.s, s2 = p2->which.s;
			int cmp_res = strcmp(s1, s2);
			return eq ? (cmp_res == 0) : (cmp_res != 0);
		}
		case prim_kind::BOOL: {
			bool b1 = p1->which.b, b2 = p2->which.b;
			return eq ? (b1 == b2) : (b1 != b2);
		}
		case prim_kind::REAL: {
			double d1 = p1->which.d, d2 = p2->which.d;
			return eq ? (d1 == d2) : (d1 != d2);
		}
		case prim_kind::UNIT: return eq;
		}

		unreachable("Unexpected primitive object type found for (in)equality!");
		return false;
	}
		break;
	case object_kind::TUP: {
		type vector::vector* tup1 = o1->which.tup, tup2 = o2->which.tup;
		check(vector::size(tup1) == vector::size(tup2), "Expected two tuples of equal length to compare for (in)equality!");

		bool is_eq = true;
		for (unsigned int i = 0; i < vector::size(tup1); i++) {
			type object* o1 = vector::at(tup1, i) as type object** @,
				o2 = vector::at(tup2, i) as type object** @;

			if (!raw_equality_cmp(o1, o2, true)) {
				is_eq = false;
				break;
			}
		}

		return eq ? is_eq : !is_eq;
	}
		break;
	case object_kind::FUN: {
		type fun_object* fun1 = o1->which.fo, fun2 = o2->which.fo;
		return eq
			? (fun1->scope == fun2->scope && fun1->fun == fun2->fun)
			: (fun1->scope != fun2->scope || fun1->fun != fun2->fun);
	}
		break;
	case object_kind::ROW: {
		type row_object* row1 = o1->which.ro, row2 = o2->which.ro;
		check(vector::size(row1->keys) == vector::size(row2->keys),
			"Expected the number of keys in a comparison between two row objects to match!");
		check(vector::size(row1->values) == vector::size(row2->values),
			"Expected the number of values in a comparison between two row objects match!");
		check(vector::size(row1->keys) == vector::size(row1->values)
			&& vector::size(row2->keys) == vector::size(row2->values),
			"Expected the number of keys to match the number of values in row objects in a comparison!");

		bool is_eq = true;
		for (unsigned int i = 0; i < vector::size(row1->keys); i++) {
			char* key1 = vector::at(row1->keys, i) as char** @;
			type object* o1 = vector::at(row1->values, i) as type object** @;
			bool hit = false;
			for (unsigned int j = 0; j < vector::size(row2->keys); j++) {
				char* key2 = vector::at(row2->keys, j) as char** @;
				type object* o2 = vector::at(row2->values, j) as type object** @;
				if (strcmp(key1, key2) == 0) {
					hit = true;
					if (!raw_equality_cmp(o1, o2, true))
						is_eq = false;
					break;
				}
			}
			check(hit, "Expected to find a key in both row objects in a comparison!");
			if (!is_eq) break;
		}
		return eq ? is_eq : !is_eq;
	}
		break;
	}

	unreachable("Unexpected object kind found when comparing two objects for (in)equality!");
	return false;
}

func type object* eq(type object* o1, type object* o2) {
	return init_bool(raw_equality_cmp(o1, o2, true));
}

func type object* ne(type object* o1, type object* o2) {
	return init_bool(raw_equality_cmp(o1, o2, false));
}

} } // namespace shadow::rt
