import "rt/row_object.hsp"

import <"std/string">
import <"stdx/vector">
import <"std/lib">
import <"std/arg">

import "rt/util.hsp"
import "rt/object.hsp"

using namespace stdx::vector;
using std::lib::NULL;
using std::arg::va_list;
using std::arg::va_start;
using std::arg::va_end;
using std::arg::va_arg;
using std::string::strcmp;

namespace shadow { namespace rt {

func type object* init_row(unsigned int num, ...) {
	type va_list* args = va_start(num$ as byte*, sizeof{byte*});

	type vector::vector* keys = vector::new_vector(sizeof{char*}),
		values = vector::new_vector(sizeof{type object*});
	for (unsigned int i = 0; i < num; i++) {
		char* k;
		type object* o;

		va_arg(args, k$ as byte*, sizeof(k), alignof(k));
		va_arg(args, o$ as byte*, sizeof(o), alignof(o));
		type object* copy = copy_object(o);

		check(!vector::append(keys, k$ as byte*) as bool,
			"Could not insert member name into row object!");
		check(!vector::append(values, copy$ as byte*) as bool,
			"Could not insert member value into row object!");
	}

	va_end(args);

	type row_object* ro = new type row_object(1);
	check(ro != NULL as type row_object*,
		"Could not construct new row object!");
	type object* ret = new type object(1);
	check(ret != NULL as type object*,
		"Could not construct new object containing a row!");

	ret->kind = object_kind::ROW;
	ret->which.ro = ro;
	ro->keys = keys;
	ro->values = values;
	return ret;
}

func type object* copy_row(type object* o) {
	check_row(o, "Expected a row object to copy here!");

	type row_object* ro = o->which.ro;
	type vector::vector* keys = vector::new_vector(sizeof{char*}),
		values = vector::new_vector(sizeof{type object*});
	for (unsigned int i = 0; i < vector::size(ro->keys); i++) {
		char* k = vector::at(keys, i) as char** @;
		type object* o = vector::at(values, i) as type object** @;
		type object* copy = copy_object(o);

		check(!vector::append(keys, k$ as byte*) as bool,
			"Could not insert copied member name into row object!");
		check(!vector::append(values, o$ as byte*) as bool,
			"Could not insert copied member value into row object!");
	}

	type row_object* ret_ro = new type row_object(1);
	check(ret_ro != NULL as type row_object*,
		"Could not construct a new row object to copy into!");
	type object* ret = new type object(1);
	check(ret != NULL as type object*,
		"Could not construct a new object containing a row to copy into!");

	ret->kind = object_kind::ROW;
	ret->which.ro = ret_ro;
	ret_ro->keys = keys;
	ret_ro->values = values;
	return ret;
}

func type object* select_member(type object* r, char* k) {
	check_row(r, "Expected a row object to select from here!");
	check(k != NULL as char*, "Expected a non-NULL member to select!");

	type row_object* ro = r->which.ro;
	for (unsigned int i = 0; i < vector::size(ro->keys); i++) {
		char* c = vector::at(ro->keys, i) as char** @;
		if (strcmp(k, c) == 0) {
			type object* o = vector::at(ro->values, i) as type object** @;
			type object* copy = copy_object(o);
			return copy;
		}
	}

	unreachable("Member name to select not found in row!");
	return NULL as type object*;
}

} } // namespace shadow::rt
