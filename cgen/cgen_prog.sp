import "cgen/cgen.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/vector">
import <"stdx/string">

import "cgen/util.hsp"
import "util/error.hsp"
import "ast/ast.hsp"

using std::lib::malloc;
using std::io::printf;
using namespace stdx::vector;
using namespace stdx::string;
using std::lib::NULL;

namespace shadow { namespace cgen {

func void cgen_prog(type cgen_ctx* c, type ast::prog* p) {
	type vector::vector* tlcs = p->top_level_constructs;

	type string::string** header_prologue = [
		string::new_string("import <\"std/lib\">"),
		string::new_string("import <\"stdx/vector\">"),
		string::new_string("import <\"std/io\">"),
		string::new_string("import <\"std/string\">"),
		string::new_string(""),
		string::new_string("import \"rt/object.hsp\""),
		string::new_string("import \"rt/prim_object.hsp\""),
		string::new_string("import \"rt/tup_object.hsp\""),
		string::new_string("import \"rt/row_object.hsp\""),
		string::new_string("import \"rt/fun_object.hsp\""),
		string::new_string("import \"rt/io.hsp\""),
		string::new_string("import \"rt/util.hsp\""),
		string::new_string("import \"util/symtab.hsp\""),
		string::new_string(""),
		string::new_string("import \"rt/ops.hsp\""),
		string::new_string("import \"rt/cmps.hsp\""),
		string::new_string(""),
		string::new_string("using std::lib::malloc;"),
		string::new_string("using std::lib::NULL;"),
		string::new_string("using std::string::strcmp;"),
		string::new_string("using namespace stdx::vector;"),
		string::new_string(""),
		string::new_string("namespace rt = shadow::rt;"),
		string::new_string("namespace util = shadow::util;"),
		string::new_string("namespace rtio = shadow::rt::io;"),
		string::new_string("namespace stdio = std::io;"),
		string::new_string(""),
		string::new_string("namespace myprog {"),
		string::new_string(""),
		NULL as type string::string*
	], header_epilogue = [
		string::new_string(""),
		string::new_string("} // namespace myprog"),
		string::new_string(""),
		NULL as type string::string*
	];

	type string::string** main_prologue = [
		string::new_string("namespace myprog { namespace internal {"),
		string::new_string(""),
		string::new_string("func int sdw_main(type rt::object* argc, type rt::object* argv) {"),
		string::new_string("\ttype util::symtab* scope = rt::init_rt();"),
		NULL as type string::string*
	], main_epilogue = [
		string::new_string("\treturn 0;"),
		string::new_string("}"),
		string::new_string(""),
		string::new_string("} } // namespace myprog::internal"),
		string::new_string(""),
		string::new_string("func int main(int argc, char** argv) {"),
		string::new_string("\ttype rt::object* wrapped_argc = rt::init_int(argc);"),
		string::new_string("\ttype rt::object* wrapped_argv = rt::init_unit();"),
		string::new_string("\treturn myprog::internal::sdw_main(wrapped_argc, wrapped_argv);"),
		string::new_string("}"),
		string::new_string(""),
		NULL as type string::string*
	];

	type string::string** body_prologue = [
		string::new_string("namespace myprog {"),
		string::new_string(""),
		NULL as type string::string*
	], body_epilogue = [
		string::new_string("} // namespace myprog"),
		string::new_string(""),
		NULL as type string::string*
	];

	add_all_strings(c, c->cd->header, header_prologue);
	add_all_strings(c, c->cd->main, main_prologue);
	add_all_strings(c, c->cd->body, body_prologue);

	for (unsigned int i = 0; i < vector::size(tlcs); i++) {
		type ast::top_level* tl = vector::at(tlcs, i) as type ast::top_level** @;
		switch (tl->kind) {
		case ast::top_level_kind::DECL: {
			type cgen_data* cd = malloc(sizeof{type cgen_data}) as type cgen_data*;
			init_cgen_data(cd);
			cgen_decl(c, cd, tl->which.top_level_decl);
			add_cgen_data(c->cd, cd, 0, 1);
		}
			break;
		default:
			util::report_ice("Unexpected top-level construct kind found!");
		}
	}

	add_all_strings(c, c->cd->header, header_epilogue);
	add_all_strings(c, c->cd->body, body_epilogue);
	add_all_strings(c, c->cd->main, main_epilogue);
}

} } // namespace shadow::cgen
