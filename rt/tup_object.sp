import "rt/tup_object.hsp"

import <"stdx/vector">
import <"std/arg">
import <"std/lib">

import "rt/object.hsp"
import "rt/util.hsp"

using namespace stdx::vector;
using std::arg::va_list;
using std::arg::va_start;
using std::arg::va_arg;
using std::arg::va_end;
using std::lib::NULL;

namespace shadow { namespace rt {

func type object* init_tup(unsigned int num, ...) {
	type va_list* args = va_start(num$ as byte*, sizeof{type object*});

	type vector::vector* tup = vector::new_vector(sizeof{type object*});
	for (unsigned int i = 0; i < num; i++) {
		type object* o;
		va_arg(args, o$ as byte*, sizeof(o), alignof(o));
		type object* copy = copy_object(o);
		check(!vector::append(tup, copy$ as byte*) as bool,
			"Could not insert constructed element into tuple!");
	}

	va_end(args);

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct new tuple object!");
	ret->kind = object_kind::TUP;
	ret->which.tup = tup;
	return ret;
}

func type object* copy_tup(type object* o) {
	check(o != NULL as type object*, "Expected a non-NULL tuple object to copy here!");
	check(o->kind == object_kind::TUP, "Expected a tuple object to copy here!");

	type vector::vector* tup = vector::new_vector(sizeof{type object*});

	for (unsigned int i = 0; i < vector::size(o->which.tup); i++) {
		type object* o = vector::at(o->which.tup, i) as type object** @;
		type object* copy = copy_object(o);

		check(!vector::append(tup, copy$ as byte*) as bool,
			"Could not insert copied element into tuple!");
	}

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not construct copied tuple object!");
	ret->kind = object_kind::TUP;
	ret->which.tup = tup;
	return ret;
}

} } // namespace shadow::rt
