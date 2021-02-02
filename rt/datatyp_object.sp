import "rt/datatyp_object.hsp"

import <"std/lib">

import "rt/util.hsp"
import "rt/object.hsp"

using std::lib::NULL;

namespace shadow { namespace rt {

func type object* copy_datatyp(type object* obj) {
	check(obj->kind == object_kind::DATATYP,
		"Expected a datatype object to copy!");
	type datatyp_object* dto = new type datatyp_object(1);
	check(dto != NULL as type datatyp_object*,
		"Could not allocate new datatype object to copy to!");
	dto->name = obj->which.dto->name;
	if (obj->which.dto->data == NULL as type rt::object*)
		dto->data = obj->which.dto->data;
	else
		dto->data = copy_object(obj->which.dto->data);

	type object* ret = new type object(1);
	check(ret != NULL as type object*,
		"Could not allocate new object to copy a datatype object into!");
	ret->kind = object_kind::DATATYP;
	ret->which.dto = dto;
	return ret;
}

func type object* init_datatyp(char* name, type object* obj) {
	type datatyp_object* dto = new type datatyp_object(1);
	check(dto != NULL as type datatyp_object*,
		"Could not allocate new datatype object!");
	dto->name = name;
	dto->data = obj;

	type object* ret = new type object(1);
	check(ret != NULL as type object*,
		"Could not allocate new object to place a new datatype object into!");
	ret->kind = object_kind::DATATYP;
	ret->which.dto = dto;
	return ret;
}

} } // namespace shadow::rt
