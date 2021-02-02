import "cgen/cgen.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/string">
import <"stdx/vector">

import "lex/token.hsp"
import "tck/util.hsp"
import "cgen/util.hsp"
import "util/error.hsp"
import "ast/ast.hsp"

using std::lib::NULL;
using std::io::printf;
using std::lib::malloc;
using namespace stdx::string;
using namespace stdx::vector;

namespace shadow { namespace cgen {

func void cgen_decl(type cgen_ctx* c, type cgen_data* cd, type ast::decl* d) {
	switch (d->kind) {
	case ast::decl_kind::VAL: {
		type ast::val_decl* vd = d->which.vd;

		for (unsigned int i = 0; i < vector::size(vd->val_binds); i++) {
			type ast::val_bind* vb = vector::at(vd->val_binds, i) as type ast::val_bind** @;

			add_scope_st(c, cd, true);
			cgen_exp(c, cd, vb->e);
			add_scope_st(c, cd, false);

			type string::string* pat_check = compute_pat_match(c, cd, cd->result, vb->p);
			type string::string* check_header = string::new_string("if (!");
			check_header = string::add(check_header, pat_check);
			check_header = string::addc(check_header, "->which.po->which.b) {");

			type string::string* check_body = string::new_string("\trt::runtime_error(\"Pattern match for 'val' binding failed!\");");

			type string::string* check_footer = string::new_string("}");
			add_all_strings(c, cd->main, [check_header, check_body, check_footer, NULL as type string::string*]);
			bind_pat_to_exp(c, cd, vb->p);
		}
	}
		return;
	case ast::decl_kind::DATATYP: {
		type vector::vector* dataty_decls = d->which.dataty_decls;
		for (unsigned int i = 0; i < vector::size(dataty_decls); i++) {
			type ast::datatyp_decl* dd = vector::at(dataty_decls, i) as type ast::datatyp_decl** @;
			type vector::vector* constrs = dd->constructors;
			for (unsigned int j = 0; j < vector::size(constrs); j++) {
				type ast::datatyp_constructor* dtc = vector::at(constrs, j) as type ast::datatyp_constructor** @;
				char* ident_text = tck::extract_token_text(c->e, dtc->ident);

				type string::string* func_name = string::new_string("__fn_");
				func_name = string::addc(func_name, itoa(c->label_counter++));
				type string::string* func_header = string::new_string("func type rt::object* ");
				func_header = string::add(func_header, func_name);
				func_header = string::addc(func_header, "(type util::symtab* scope, type rt::object* arg)");

				type string::string* fwd_decl = string::new_string("");
				fwd_decl = string::addc(func_header, ";");
				util::maybe_report_ice(!vector::append(cd->header, fwd_decl$ as byte*) as bool,
					"Could not insert forward declaration for a datatype constructor in codegen!");

				type string::string* func_body_header = string::new_string("");
				func_body_header = string::add(func_body_header, func_header);
				func_body_header = string::addc(func_body_header, " {");

				type string::string* func_body = string::new_string("\treturn rt::init_datatyp(\"");
				func_body = string::addc(func_body, ident_text);
				type string::string* last_arg = string::new_string("");
				bool nullary = dtc->ty == NULL as type ast::typ*;
				if (nullary)
					last_arg = string::addc(last_arg, "NULL as type rt::object*");
				else
					last_arg = string::addc(last_arg, "rt::copy_object(arg)");
				func_body = string::addc(func_body, "\", ");
				func_body = string::add(func_body, last_arg);
				func_body = string::addc(func_body, ");");

				type string::string* func_epilogue = string::new_string("}");
				type string::string* func_epilogue2 = string::new_string("");

				add_all_strings(c, cd->body, [
					func_body_header,
					func_body,
					func_epilogue,
					func_epilogue2
				]);

				type string::string* dta = string::new_string("rt::scope_set(scope, \"");
				dta = string::addc(dta, ident_text);
				dta = string::addc(dta, "\", rt::init_fun(scope, ");
				dta = string::add(dta, func_name);
				dta = string::addc(dta, "));");
				util::maybe_report_ice(!vector::append(cd->main, dta$ as byte*) as bool,
					"Could not add assignment for a datatype constructor in codegen!");
			}
		}
	}
		return;
	case ast::decl_kind::DATATYP_REPL:
	case ast::decl_kind::TYP:
		return;
	case ast::decl_kind::FUN:
		return cgen_decl_fun(c, cd, d->which.fun_decl);
	case ast::decl_kind::EFUN: {
		type ast::fun* f = d->which.fun_decl;

		for (unsigned int i = 0; i < vector::size(f->fun_binds); i++) {
			type ast::fun_bind* fb = vector::at(f->fun_binds, i) as type ast::fun_bind** @;
			util::maybe_report_ice(vector::size(fb->fun_matches) != 0,
				"Expected at least one 'fun' match for an 'efun' decl in codegen!");

			type ast::fun_match* fm = vector::at(fb->fun_matches, 0) as type ast::fun_match** @;
			char* fun_name = tck::extract_token_text(c->e, fm->fun_name);

			type string::string* fwd_decl = string::new_string("func type rt::object* ");
			fwd_decl = string::addc(fwd_decl, fun_name);
			fwd_decl = string::addc(fwd_decl, "(type util::symtab* scope, type rt::object* arg);");
			add_all_strings(c, cd->header, [fwd_decl, NULL as type string::string*]);

			type string::string* assignment = string::new_string("rt::scope_set(scope, \"");
			assignment = string::addc(assignment, fun_name);
			assignment = string::addc(assignment, "\", rt::init_fun(scope, ");
			assignment = string::addc(assignment, fun_name);
			assignment = string::addc(assignment, "));");
			add_all_strings(c, cd->main, [assignment, NULL as type string::string*]);
		}
	}
		return;
	}

	util::report_ice("Unknown ast::decl_kind found in codegen!");
	return;
}

func void cgen_decl_fun_helper(type cgen_ctx* c, type cgen_data* cd, type ast::fun_bind* fb,
	type vector::vector* prev_results, type string::string* prog_fun_name) {
	type string::string* true_func_name = string::new_string("__fn_");
	char* true_func_num = itoa(c->label_counter++);
	true_func_name = string::addc(true_func_name, true_func_num);

	type cgen_data true_cd;
	true_cd.header = cd->header;
	true_cd.body = cd->body;
	true_cd.main = vector::new_vector(sizeof{type string::string*});
	true_cd.result = NULL as type string::string*;

	{
		type string::string* true_func_header = string::new_string("func type rt::object* ");
		true_func_header = string::add(true_func_header, true_func_name);
		true_func_header = string::addc(true_func_header, "(type util::symtab* scope, type rt::object* arg)");

		type string::string* true_func_fwd_decl = string::addc(true_func_header, ";");
		add_all_strings(c, true_cd.header, [true_func_fwd_decl, NULL as type string::string*]);
		
		true_func_header = string::addc(true_func_header, " {");
		add_all_strings(c, true_cd.main, [true_func_header, NULL as type string::string*]);
	}

	unsigned int body_start_size = vector::size(true_cd.main);
	add_scope_st(c, true_cd$, true);

	type vector::vector* match_results = vector::new_vector(sizeof{type string::string*});
	for (unsigned int j = 0; j < vector::size(fb->fun_matches); j++) {
		type ast::fun_match* fm = vector::at(fb->fun_matches, j) as type ast::fun_match** @;
		type string::string** prev_result = vector::at(prev_results, j) as type string::string**;

		util::maybe_report_ice(vector::size(fm->args) == 1 || prev_result@ != NULL as type string::string*,
			"Expected the last n - 1 arguments of each branch of an n-ary 'fun' to already be codegen'd!");

		type ast::pat* first_arg = vector::at(fm->args, 0) as type ast::pat** @;
		type string::string* match_result = compute_pat_match(c, true_cd$, string::new_string("arg"), first_arg);
		util::maybe_report_ice(!vector::append(match_results, match_result$ as byte*) as bool,
			"Could not keep track of match results for the first argument(s) of a 'fun' binding in codegen!");
	}

	for (unsigned int j = 0; j < vector::size(fb->fun_matches); j++) {
		type string::string* match_result = vector::at(match_results, j) as type string::string** @;

		type ast::fun_match* fm = vector::at(fb->fun_matches, j) as type ast::fun_match** @;
		type ast::pat* first_arg = vector::at(fm->args, 0) as type ast::pat** @;

		type string::string* cond_header = string::new_string(j == 0 ? "if (" : "else if (");
		cond_header = string::add(cond_header, match_result);
		cond_header = string::addc(cond_header, "->which.po->which.b) {");
		add_all_strings(c, true_cd.main, [cond_header, NULL as type string::string*]);

		unsigned int bind_start = vector::size(true_cd.main);
		true_cd.result = string::new_string("arg");
		bind_pat_to_exp(c, true_cd$, first_arg);

		if (vector::size(fm->args) != 1) {
			type string::string* next_fun = vector::at(prev_results, j) as type string::string** @;
			type string::string* tmp = gen_temp(c);
			type string::string* fun_save = string::new_string("rt::init_fun(scope, ");
			fun_save = string::add(fun_save, next_fun);
			fun_save = string::addc(fun_save, ")");
			type string::string* fun_assign = gen_assign(c, tmp, fun_save);
			fun_assign = left_pad_string(c, 1, '\t', fun_assign);
			add_all_strings(c, true_cd.main, [fun_assign, NULL as type string::string*]);

			// unsigned int scope_start = vector::size(true_cd.main);
			add_scope_st(c, true_cd$, false);
			// unsigned int scope_end = vector::size(true_cd.main);
			/* for (unsigned int k = scope_start; k < scope_end; k++) {
				type string::string** elem = vector::at(true_cd.main, k) as type string::string**;
				elem@ = left_pad_string(c, 1, '\t', elem@);
			} */

			type string::string* ret_string = string::new_string("return ");
			ret_string = string::add(ret_string, tmp);
			ret_string = string::addc(ret_string, ";");
			add_all_strings(c, true_cd.main, [ret_string, NULL as type string::string*]);
		}
		else {
			cgen_exp(c, true_cd$, fm->e);
			type string::string* ret_string = string::new_string("return ");
			ret_string = string::add(ret_string, true_cd.result);
			ret_string = string::addc(ret_string, ";");
			add_all_strings(c, true_cd.main, [ret_string, NULL as type string::string*]);
		}

		unsigned int bind_end = vector::size(true_cd.main);
		for (unsigned int k = bind_start; k < bind_end; k++) {
			type string::string** elem = vector::at(true_cd.main, k) as type string::string**;
			elem@ = left_pad_string(c, 1, '\t', elem@);
		}

		type string::string* cond_end = string::new_string("}");
		add_all_strings(c, true_cd.main, [cond_end, NULL as type string::string*]);
	}

	add_all_strings(c, true_cd.main, [
		string::new_string("else {"),
		string::new_string("\trt::runtime_error(\"No suitable 'fun' match found!\");"),
		string::new_string("}"),
		NULL as type string::string*
	]);

	unsigned int body_end_size = vector::size(true_cd.main);
	for (unsigned int j = body_start_size; j < body_end_size; j++) {
		type string::string** elem = vector::at(true_cd.main, j) as type string::string**;
		elem@ = left_pad_string(c, 1, '\t', elem@);
	}

	{
		type string::string* true_func_end = string::new_string("}");
		type string::string* nl = string::new_string("");
		add_all_strings(c, true_cd.main, [true_func_end, nl, NULL as type string::string*]);
	}

	for (unsigned int j = 0; j < vector::size(true_cd.main); j++) {
		type string::string* elem = vector::at(true_cd.main, j) as type string::string** @;
		util::maybe_report_ice(!vector::append(cd->body, elem$ as byte*) as bool,
			"Could not transfer true function body from sub-environment during 'fun' codegen!");
	}

	util::maybe_report_ice(prog_fun_name != NULL as type string::string*,
		"Could not detect name of 'fun' in codegen!");
	type string::string* fun_set = string::new_string("rt::scope_set(scope, \"");
	fun_set = string::add(fun_set, prog_fun_name);
	fun_set = string::addc(fun_set, "\", rt::init_fun(scope, ");
	fun_set = string::add(fun_set, true_func_name);
	fun_set = string::addc(fun_set, "));");
	add_all_strings(c, cd->main, [fun_set, NULL as type string::string*]);
}

func void cgen_decl_fun(type cgen_ctx* c, type cgen_data* cd, type ast::fun* f) {
	for (unsigned int i = 0; i < vector::size(f->fun_binds); i++) {
		type ast::fun_bind* fb = vector::at(f->fun_binds, i) as type ast::fun_bind** @;

		type vector::vector* prev_results = vector::new_vector(sizeof{type string::string*});
		for (unsigned int j = 0; j < vector::size(fb->fun_matches); j++) {
			type string::string* tmp = NULL as type string::string*;
			util::maybe_report_ice(!vector::append(prev_results, tmp$ as byte*) as bool,
				"Could not keep track of tail function call results in codegen!");
		}

		type string::string* prog_fun_name = NULL as type string::string*;
		for (unsigned int j = 0; j < vector::size(fb->fun_matches); j++) {
			type ast::fun_match* fm = vector::at(fb->fun_matches, j) as type ast::fun_match** @;
			type string::string** prev_result = vector::at(prev_results, j) as type string::string**;
			prog_fun_name = string::new_string(tck::extract_token_text(c->e, fm->fun_name));

			for (unsigned int k = vector::size(fm->args) - 1; k > 0; k--) {
				type ast::pat* arg_pat = vector::at(fm->args, k) as type ast::pat** @;

				type string::string* function_name = string::new_string("__fn_");
				char* lab = itoa(c->label_counter++);
				function_name = string::addc(function_name, lab);
				
				type vector::vector* body_vec = vector::new_vector(sizeof{type string::string*});
				{
					type string::string* function_header = string::new_string("func type rt::object* ");
					function_header = string::add(function_header, function_name);
					function_header = string::addc(function_header, "(type util::symtab* scope, type rt::object* arg)");

					type string::string* function_decl = string::new_string("");
					function_decl = string::add(function_decl, function_header);
					function_decl = string::addc(function_decl, ";");
					util::maybe_report_ice(!vector::append(cd->header, function_decl$ as byte*) as bool,
						"Could not add a 'fun' declaration's function forward-declaration in codegen!");

					type string::string* function_start = string::new_string("");
					function_start = string::add(function_start, function_header);
					function_start = string::addc(function_start, " {");
					util::maybe_report_ice(!vector::append(body_vec, function_start$ as byte*) as bool,
						"Could not insert function header for a 'fun' binding in codegen!");
				}

				unsigned int body_start_size = vector::size(body_vec);
				type cgen_data new_cd;
				new_cd.header = cd->header;
				new_cd.body = vector::new_vector(sizeof{type string::string*});
				new_cd.main = body_vec;
				new_cd.result = NULL as type string::string*;
				type string::string* match_result = compute_pat_match(c, new_cd$, string::new_string("arg"), arg_pat);

				{
					type string::string* cond_header = string::new_string("if (!");
					cond_header = string::add(cond_header, match_result);
					cond_header = string::addc(cond_header, "->which.po->which.b) {");
					type string::string* rt_match_err = string::new_string("\trt::runtime_error(\"Provided argument does not match pattern!\");");
					type string::string* cond_footer = string::new_string("}");
					add_all_strings(c, body_vec, [
						cond_header,
						rt_match_err,
						cond_footer,
						NULL as type string::string*,
					]);
				}

				add_scope_st(c, new_cd$, true);
				new_cd.result = string::new_string("arg");
				bind_pat_to_exp(c, new_cd$, arg_pat);

				type string::string* curr_res = NULL as type string::string*;
				if (prev_result@ == NULL as type string::string*) {
					cgen_exp(c, new_cd$, fm->e);
					curr_res = new_cd.result;
				}
				else {
					curr_res = gen_temp(c);
					type string::string* fn_rhs = string::new_string("rt::init_fun(scope, ");
					fn_rhs = string::add(fn_rhs, prev_result@);
					fn_rhs = string::addc(fn_rhs, ")");

					type string::string* fn_assign = gen_assign(c, curr_res, fn_rhs);
					add_all_strings(c, body_vec, [fn_assign, NULL as type string::string*]);
				}

				add_scope_st(c, new_cd$, false);
				type string::string* ret_string = string::new_string("return ");
				ret_string = string::add(ret_string, curr_res);
				ret_string = string::addc(ret_string, ";");
				add_all_strings(c, body_vec, [ret_string, NULL as type string::string*]);

				prev_result@ = function_name;

				unsigned int body_end_size = vector::size(body_vec);
				{
					type string::string* function_end = string::new_string("}");
					type string::string* nl = string::new_string("");
					add_all_strings(c, body_vec, [function_end, nl, NULL as type string::string*]);
				}

				for (unsigned int l = body_start_size; l < body_end_size; l++) {
					type string::string** elem = vector::at(body_vec, l) as type string::string**;
					elem@ = left_pad_string(c, 1, '\t', elem@);
				}

				for (unsigned int l = 0; l < vector::size(new_cd.body); l++) {
					type string::string* elem = vector::at(new_cd.body, l) as type string::string** @;
					util::maybe_report_ice(!vector::append(cd->body, elem$ as byte*) as bool,
						"Could not transfer functions generated from 'fun' declaration in codegen!");
				}

				for (unsigned int l = 0; l < vector::size(body_vec); l++) {
					type string::string* elem = vector::at(new_cd.main, l) as type string::string** @;
					util::maybe_report_ice(!vector::append(cd->body, elem$ as byte*) as bool,
						"Could not transfer main function generated from 'fun' declaration in codegen!");
				}
			}
		}

		cgen_decl_fun_helper(c, cd, fb, prev_results, prog_fun_name);
	}
}

} } // namespace shadow::cgen
