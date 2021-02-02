import "rt/ops.hsp"

import <"std/lib">
import <"std/string">

import "rt/prim_object.hsp"
import "rt/object.hsp"
import "rt/util.hsp"

using std::lib::NULL;
using std::string::strlen;
using std::string::strcpy;
using std::string::strcat;

namespace shadow { namespace rt {

namespace string_ops {

static constexpr unsigned int CONCAT = 0x0;

} // namespace string_ops

func[static] type object* string_binop(type object* o1, type object* o2, unsigned int op) {
	check_string(o1, "Expected a string lhs for a string binary operation!");
	check_string(o2, "Expected a string rhs for a string binary operation!");

	char* s1 = o1->which.po->which.s, s2 = o2->which.po->which.s;
	switch (op) {
	case string_ops::CONCAT: {
		char* ret = new char((strlen(s1) + strlen(s2) + 1) * sizeof{char});
		ret = strcpy(ret, s1);
		ret = strcat(ret, s2);
		return init_string(ret);
	}
	}

	unreachable("Invalid binary operation provided for two strings!");
	return NULL as type object*;
}

func type object* concat_string(type object* o1, type object* o2) {
	return string_binop(o1, o2, string_ops::CONCAT);
}

} } // namespace shadow::rt
