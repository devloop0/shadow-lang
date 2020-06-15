import "rt/prim_object.hsp"

import <"std/string">
import <"std/lib">

import "rt/object.hsp"
import "rt/util.hsp"

using std::string::memcpy;
using std::string::strcpy;
using std::string::strlen;
using std::lib::NULL;

namespace shadow { namespace rt {

func type object* init_bool(bool b) {
	type prim_object* p = new type prim_object(1);
	check(p != NULL as type prim_object*, "Could not construct bool primitive!");

	p->kind = prim_kind::BOOL;
	p->which.b = b;

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct bool object!");
	ret->kind = object_kind::PRIM;
	ret->which.po = p;
	return ret;
}

func type object* init_int(int i) {
	type prim_object* p = new type prim_object(1);
	check(p != NULL as type prim_object*, "Could not construct int primitive!");

	p->kind = prim_kind::INT;
	p->which.i = i;

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct int object!");
	ret->kind = object_kind::PRIM;
	ret->which.po = p;
	return ret;
}

func type object* init_char(char c) {
	type prim_object* p = new type prim_object(1);
	check(p != NULL as type prim_object*, "Could not construct char primitive!");

	p->kind = prim_kind::CHAR;
	p->which.c = c;

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct char object!");
	ret->kind = object_kind::PRIM;
	ret->which.po = p;
	return ret;
}

func type object* init_unit() {
	type prim_object* p = new type prim_object(1);
	check(p != NULL as type prim_object*, "Could not construct unit primitive!");

	p->kind = prim_kind::UNIT;

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct unit object!");
	ret->kind = object_kind::PRIM;
	ret->which.po = p;
	return ret;
}

func type object* init_real(double d) {
	type prim_object* p = new type prim_object(1);
	check(p != NULL as type prim_object*, "Could not construct double primitive!");

	p->kind = prim_kind::REAL;
	p->which.d = d;

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct real object!");
	ret->kind = object_kind::PRIM;
	ret->which.po = p;
	return ret;
}

func type object* init_string(char* s) {
	type prim_object* p = new type prim_object(1);
	check(p != NULL as type prim_object*, "Could not construct string primitive!");

	p->kind = prim_kind::STRING;
	p->which.s = new char(strlen(s) + 1);
	strcpy(p->which.s, s);

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct string object!");
	ret->kind = object_kind::PRIM;
	ret->which.po = p;
	return ret;
}

func type object* copy_prim(type object* src) {
	check(src->kind == object_kind::PRIM, "Expected a primitive object to copy here!");

	type prim_object* dst_p = new type prim_object(1);
	check(dst_p != NULL as type prim_object*, "Could not construct a primitive copy!");

	type prim_object* src_p = src->which.po;
	dst_p->kind = src_p->kind;
	switch (dst_p->kind) {
	case prim_kind::STRING:
		dst_p->which.s = new char(strlen(src_p->which.s) + 1);
		strcpy(dst_p->which.s, src_p->which.s);
		break;
	case prim_kind::INT:
		dst_p->which.i = src_p->which.i;
		break;
	case prim_kind::CHAR:
		dst_p->which.c = src_p->which.c;
		break;
	case prim_kind::REAL:
		dst_p->which.d = src_p->which.d;
		break;
	case prim_kind::BOOL:
		dst_p->which.b = src_p->which.b;
		break;
	case prim_kind::UNIT:
		break;
	default:
		unreachable("Unrecognized primitive type for copy!");
		break;
	}

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct copied primitive object!");
	ret->kind = object_kind::PRIM;
	ret->which.po = dst_p;
	return ret;
}

} } // namespace shadow::rt
