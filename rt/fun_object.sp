import "rt/fun_object.hsp"

import <"std/lib">

import "rt/object.hsp"
import "rt/util.hsp"
import "util/symtab.hsp"

using std::lib::NULL;

namespace shadow { namespace rt {

func type object* init_fun(type util::symtab* scope, fn type object*(type util::symtab*, type object*) fun) {
	type fun_object* fo = new type fun_object(1);
	check(fo != NULL as type fun_object*, "Could create new function object!");
	fo->scope = scope;
	fo->fun = fun;

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not create new object wrapping a function!");
	ret->kind = object_kind::FUN;
	ret->which.fo = fo;
	return ret;
}

func type object* copy_fun(type object* o) {
	check(o->kind == object_kind::FUN, "Expected a function object to copy here!");
	
	type fun_object* fo = new type fun_object(1);
	check(fo != NULL as type fun_object*, "Could not create a copy of a function object!");
	fo->scope = o->which.fo->scope;
	fo->fun = o->which.fo->fun;

	type object* ret = new type object(1);
	check(ret != NULL as type object*, "Could not create a copy of an object wrapping a function!");
	ret->kind = object_kind::FUN;
	ret->which.fo = o->which.fo;
	return ret;
}

} } // namespace shadow::rt
