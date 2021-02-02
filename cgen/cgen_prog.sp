import "cgen/cgen.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/vector">
import <"stdx/string">

import "tck/util.hsp"
import "cgen/util.hsp"
import "util/error.hsp"
import "ast/ast.hsp"
import "src/compile.hsp"

using std::lib::malloc;
using std::io::printf;
using namespace stdx::vector;
using namespace stdx::string;
using std::lib::NULL;

namespace shadow { namespace cgen {

func void cgen_prog(type cgen_ctx* c, type ast::prog* p, bool add_entry_point,
	type string::string* namespace_name) {
	type vector::vector* tlcs = p->top_level_constructs;

	type string::string** header_prologue = [
		string::new_string("import <\"std/lib\">"),
		string::new_string("import <\"stdx/vector\">"),
		string::new_string("import <\"std/io\">"),
		string::new_string("import <\"std/string\">"),
		string::new_string(""),
		string::new_string("import \"rt/scope.hsp\""),
		string::new_string("import \"rt/module.hsp\""),
		string::new_string("import \"rt/object.hsp\""),
		string::new_string("import \"rt/prim_object.hsp\""),
		string::new_string("import \"rt/tup_object.hsp\""),
		string::new_string("import \"rt/row_object.hsp\""),
		string::new_string("import \"rt/fun_object.hsp\""),
		string::new_string("import \"rt/datatyp_object.hsp\""),
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
		NULL as type string::string*
	], header_epilogue = [
		string::new_string(""),
		string::cadd("} // namespace ", namespace_name),
		string::new_string(""),
		NULL as type string::string*
	];

	type string::string** main_prologue = [
		string::addc(string::cadd("namespace ", namespace_name), " { namespace internal {")
		string::new_string(""),
		string::new_string("func int sdw_main(type rt::object* argc, type rt::object* argv) {"),
		string::new_string("\tstatic bool initialization_check = false;"),
		string::new_string("\tif (initialization_check) return 0;"),
		string::new_string("\tinitialization_check = true;"),
		string::new_string(""),
		NULL as type string::string*
	], main_epilogue = [
		string::new_string("\treturn 0;"),
		string::new_string("}"),
		string::new_string(""),
		string::addc(string::cadd("} } // namespace ", namespace_name), "::internal"),
		string::new_string(""),
		NULL as type string::string*
	];

	type string::string** body_prologue = [
		string::addc(string::cadd("namespace ", namespace_name), " {")
		string::new_string(""),
		NULL as type string::string*
	], body_epilogue = [
		string::cadd("} // namespace ", namespace_name),
		string::new_string(""),
		NULL as type string::string*
	];

	add_all_strings(c, c->cd->header, header_prologue);
	add_all_strings(c, c->cd->main, main_prologue);
	add_all_strings(c, c->cd->body, body_prologue);

	type string::string* imported_namespace_pre = string::new_string("namespace ");
	type string::string* imported_namespace_post = string::new_string(" { namespace internal { "
		"func int sdw_main(type rt::object* argc, type rt::object* argv); } }");
	
	type string::string* init_call_pre = string::new_string("\t");
	type string::string* init_call_post = string::new_string("::internal::sdw_main(argc, argv);");

	if (c->e->mod_ref == c->e->mod_ref->global_module) {
		type string::string** scope_prologue = [
			string::new_string("\ttype util::symtab* scope = rt::init_rt();"),
			string::new_string(""),
			NULL as type string::string*
		];
		add_all_strings(c, c->cd->main, scope_prologue);
	}

	unsigned int num_namespace_decls = 0;
	for (unsigned int i = 0; i < util::symtab_num_entries(c->e->mod_ref->imported_modules); i++) {
		type tck::module* curr_mod = vector::at(c->e->mod_ref->imported_modules->values, i)
			as type tck::module** @;

		num_namespace_decls += vector::size(curr_mod->namespaces);
		for (unsigned int j = 0; j < vector::size(curr_mod->namespaces); j++) {
			type string::string* curr_namespace_name = vector::at(curr_mod->namespaces, j)
				as type string::string** @;
			type string::string* imported_namespace_decl =
				string::add(string::add(imported_namespace_pre, curr_namespace_name),
					imported_namespace_post);

			add_all_strings(c, c->cd->header, [imported_namespace_decl, NULL as type string::string*]);

			type string::string* init_call = string::add(init_call_pre,
				string::add(curr_namespace_name, init_call_post));
			add_all_strings(c, c->cd->main, [init_call, NULL as type string::string*]);
		}
	}

	if (num_namespace_decls > 0) {
		add_all_strings(c, c->cd->header, [
			string::new_string(""),
			NULL as type string::string*
		]);

		add_all_strings(c, c->cd->main, [
			string::new_string(""),
			NULL as type string::string*
		]);
	}

	add_all_strings(c, c->cd->header, [
		string::addc(string::cadd("namespace ", namespace_name), " {")
		string::new_string(""),
		NULL as type string::string*
	]);

	if (c->e->mod_ref != c->e->mod_ref->global_module) {
		type string::string* mod_name = tck::extract_module_name(c->e->mod_ref,
			compile::MOD_FILE_SEP);
		type string::string* to_add = string::new_string(
			"\ttype util::symtab* scope = rt::module_scope(rt::lookup_or_create_module(\"");
		to_add = string::add(to_add, mod_name);
		to_add = string::addc(to_add, "\"));");
		type string::string** scope_prologue = [
			to_add,
			string::new_string(""),
			NULL as type string::string*
		];
		add_all_strings(c, c->cd->main, scope_prologue);
	}

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
		case ast::top_level_kind::IMPORT:
			break;
		default:
			util::report_ice("Unexpected top-level construct kind found!");
		}
	}

	add_all_strings(c, c->cd->header, header_epilogue);
	add_all_strings(c, c->cd->body, body_epilogue);
	add_all_strings(c, c->cd->main, main_epilogue);

	if (add_entry_point) {
		type string::string** entry_point = [
			string::new_string("func int main(int argc, char** argv) {"),
			string::new_string("\ttype rt::object* wrapped_argc = rt::init_int(argc);"),
			string::new_string("\ttype rt::object* wrapped_argv = rt::init_unit();"),
			string::addc(string::cadd("\treturn ", namespace_name), "::internal::sdw_main(wrapped_argc, wrapped_argv);"),
			string::new_string("}"),
			string::new_string(""),
			NULL as type string::string*
		];
		add_all_strings(c, c->cd->main, entry_point);
	}
}

} } // namespace shadow::cgen
