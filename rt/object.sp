import "rt/object.hsp"

import <"std/lib">

import "rt/util.hsp"
import "rt/prim_object.hsp"
import "rt/tup_object.hsp"
import "rt/row_object.hsp"
import "rt/fun_object.hsp"
import "rt/datatyp_object.hsp"

using std::lib::NULL;

namespace shadow { namespace rt {

func type object* copy_object(type object* o) {
	switch (o->kind) {
	case object_kind::PRIM:
		return copy_prim(o);
	case object_kind::TUP:
		return copy_tup(o);
	case object_kind::FUN:
		return copy_fun(o);
	case object_kind::ROW:
		return copy_row(o);
	case object_kind::DATATYP:
		return copy_datatyp(o);
	}

	unreachable("Unrecognized object type!");
}

} } // namespace shadow::rt
