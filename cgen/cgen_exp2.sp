import "cgen/cgen.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/string">
import <"stdx/vector">

import "tck/util.hsp"
import "cgen/util.hsp"
import "util/error.hsp"
import "ast/ast.hsp"

using std::lib::NULL;
using std::lib::malloc;
using std::io::printf;
using namespace stdx::string;
using namespace stdx::vector;

namespace shadow { namespace cgen {

func void cgen_exp_fun(type cgen_ctx* c, type cgen_data* cd, type vector::vector* matches) {
	type string::string* fn_name = string::new_string("__fn_");
	char* lab = itoa(c->label_counter++);
	fn_name = string::addc(fn_name, lab);

	type string::string* fn_header = string::new_string("func type rt::object* ");
	fn_header = string::add(fn_header, fn_name);
	fn_header = string::addc(fn_header, "(type util::symtab* scope, type rt::object* arg);");
	util::maybe_report_ice(!vector::append(cd->header, fn_header$ as byte*) as bool,
		"Could not add lambda expression function header in codegen!");

	type string::string* fn_header_prologue = string::new_string("func type rt::object* ");
	fn_header_prologue = string::add(fn_header_prologue, fn_name);
	fn_header_prologue = string::addc(fn_header_prologue, "(type util::symtab* scope, type rt::object* arg) {");

	type vector::vector* body_vec = vector::new_vector(sizeof{type string::string*}),
		main_vec = vector::new_vector(sizeof{type string::string*});
	add_all_strings(c, body_vec, [
		fn_header_prologue,
		NULL as type string::string*
	]);

	// TODO: Remove this limitation!
	util::maybe_report_ice(vector::size(matches) == 1,
		"Expected only one match for this anonymous function!");
	for (unsigned int i = 0; i < vector::size(matches); i++) {
		add_all_strings(c, body_vec, [
			string::new_string("\tscope = rt::scope_push(scope);"),
			NULL as type string::string*
		]);

		type ast::match* m = vector::at(matches, i) as type ast::match** @;
		type cgen_data new_cd;
		new_cd.header = cd->header;
		new_cd.body = vector::new_vector(sizeof{type string::string*});
		new_cd.main = main_vec;
		new_cd.result = string::new_string("arg");

		bind_pat_to_exp(c, new_cd$, m->p);
		cgen_exp(c, new_cd$, m->e);
		for (unsigned int i = 0; i < vector::size(new_cd.body); i++) {
			type string::string* s = vector::at(new_cd.body, i) as type string::string** @;
			util::maybe_report_ice(!vector::append(cd->body, s$ as byte*) as bool,
				"Could not insert body statements from a function context in codegen!");
		}
		for (unsigned int i = 0; i < vector::size(new_cd.main); i++) {
			type string::string** elem = vector::at(new_cd.main, i) as type string::string**;
			elem@ = left_pad_string(c, 1, '\t', elem@);
			util::maybe_report_ice(!vector::append(body_vec, elem as byte*) as bool,
				"Could not insert function body into current function context in codegen!");
		}

		type string::string* ret_string = string::new_string("\treturn ");
		ret_string = string::add(ret_string, new_cd.result);
		ret_string = string::addc(ret_string, ";");
		add_all_strings(c, body_vec, [
			string::new_string("\tscope = rt::scope_push(scope);"),
			ret_string,
			NULL as type string::string*
		]);
	}

	add_all_strings(c, body_vec, [
		string::new_string("}"),
		string::new_string(""),
		NULL as type string::string*
	]);
	for (unsigned int i = 0; i < vector::size(body_vec); i++) {
		type string::string* s = vector::at(body_vec, i) as type string::string** @;
		util::maybe_report_ice(!vector::append(cd->body, s$ as byte*) as bool,
			"Could not insert lambda function body in codegen!");
	}

	cd->result = gen_temp(c);
	type string::string* fun_string = string::new_string("rt::init_fun(scope, ");
	fun_string = string::add(fun_string, fn_name);
	fun_string = string::addc(fun_string, ")");
	type string::string* fun_assign_string = gen_assign(c, cd->result, fun_string);
	util::maybe_report_ice(!vector::append(cd->main, fun_assign_string$ as byte*) as bool,
		"Could not assign lambda expression function to a temporary in codegen!");
}

func void cgen_exp_unary(type cgen_ctx* c, type cgen_data* cd, type ast::exp_unary* un) {
	type string::string* temp_res = gen_temp(c);

	cgen_exp(c, cd, un->e);
	type string::string* base_result = cd->result;
	type string::string* base_string = gen_copy(c, temp_res, base_result);

	cd->result = gen_temp(c);
	type string::string* op_string = string::new_string("rt::");
	switch (un->kind) {
	case ast::exp_unary_kind::PLUS:
		op_string = string::addc(op_string, "plus_int");
		break;
	case ast::exp_unary_kind::MINUS:
		op_string = string::addc(op_string, "minus_int");
		break;
	case ast::exp_unary_kind::CMPL:
		op_string = string::addc(op_string, "cmpl_int");
		break;
	case ast::exp_unary_kind::NOT:
		op_string = string::addc(op_string, "not_bool");
		break;
	case ast::exp_unary_kind::PLUS_REAL:
		op_string = string::addc(op_string, "plus_real");
		break;
	case ast::exp_unary_kind::MINUS_REAL:
		op_string = string::addc(op_string, "minus_real");
		break;
	default:
		util::report_ice("Unknown ast::exp_unary_kind found in codegen!");
		break;
	}
	op_string = string::addc(op_string, "(");
	op_string = string::add(op_string, base_result);
	op_string = string::addc(op_string, ")");
	type string::string* assign_string = gen_assign(c, cd->result, op_string);

	util::maybe_report_ice(!vector::append(cd->main, base_string$ as byte*) as bool,
		"Could not add computation of unary expression operand in codegen!");
	util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
		"Could not add computation of unary expression in codegen!");
}

func void cgen_exp_if(type cgen_ctx* c, type cgen_data* cd, type ast::if_exp* iexp) {
	type string::string* final_res = gen_temp(c);
	type string::string* final_res_decl_string = string::new_string("type rt::object* ");
	final_res_decl_string = string::add(final_res_decl_string, final_res);
	final_res_decl_string = string::addc(final_res_decl_string, ";");
	util::maybe_report_ice(!vector::append(cd->main, final_res_decl_string$ as byte*) as bool,
		"Could not add declaration of final result for an if expression in codegen!");

	cgen_exp(c, cd, iexp->cond);
	type string::string* cond_temp = gen_temp(c);
	type string::string* cond_assign_string = gen_copy(c, cond_temp, cd->result);
	util::maybe_report_ice(!vector::append(cd->main, cond_assign_string$ as byte*) as bool,
		"Could not add temporary copy of if expression condition in codegen!");

	type string::string* if_header_string = string::new_string("if (");
	if_header_string = string::add(if_header_string, cond_temp);
	if_header_string = string::addc(if_header_string, "->which.po->which.b) {");
	util::maybe_report_ice(!vector::append(cd->main, if_header_string$ as byte*) as bool,
		"Could not insert if header for if expression condition in codegen!");
	unsigned int old_size = vector::size(cd->main);

	add_scope_st(c, cd, true);
	cgen_exp(c, cd, iexp->true_path);
	add_scope_st(c, cd, false);

	type string::string* res_assign_string = string::new_string("");
	res_assign_string = string::add(res_assign_string, final_res);
	res_assign_string = string::addc(res_assign_string, " = ");
	res_assign_string = string::add(res_assign_string, cd->result);
	res_assign_string = string::addc(res_assign_string, ";");
	util::maybe_report_ice(!vector::append(cd->main, res_assign_string$ as byte*) as bool,
		"Could not add result assignment in if expression true path in codegen!");
	
	unsigned int new_size = vector::size(cd->main);
	for (unsigned int i = old_size; i < new_size; i++) {
		type string::string** elem = vector::at(cd->main, i) as type string::string**;
		elem@ = left_pad_string(c, 1, '\t', elem@);
	}
	
	type string::string* brace = string::new_string("}");
	util::maybe_report_ice(!vector::append(cd->main, brace$ as byte*) as bool,
		"Could not add brace to end the true path of an if expression in codegen!");

	type string::string* else_string = string::new_string("else {");
	util::maybe_report_ice(!vector::append(cd->main, else_string$ as byte*) as bool,
		"Could not add else header string for if expression in codegen!");

	old_size = vector::size(cd->main);

	add_scope_st(c, cd, true);
	cgen_exp(c, cd, iexp->false_path);
	add_scope_st(c, cd, false);

	res_assign_string = string::new_string("");
	res_assign_string = string::add(res_assign_string, final_res);
	res_assign_string = string::addc(res_assign_string, " = ");
	res_assign_string = string::add(res_assign_string, cd->result);
	res_assign_string = string::addc(res_assign_string, ";");
	util::maybe_report_ice(!vector::append(cd->main, res_assign_string$ as byte*) as bool,
		"Could not add result assignment in if expression false path in codegen!");

	new_size = vector::size(cd->main);
	for (unsigned int i = old_size; i < new_size; i++) {
		type string::string** elem = vector::at(cd->main, i) as type string::string**;
		elem@ = left_pad_string(c, 1, '\t', elem@);
	}
	
	brace = string::new_string("}");
	util::maybe_report_ice(!vector::append(cd->main, brace$ as byte*) as bool,
		"Could not add brace to end the false path of an expression in codegen!");
	cd->result = final_res;
}

func void cgen_exp_app(type cgen_ctx* c, type cgen_data* cd, type ast::exp_app* app) {
	cgen_exp(c, cd, app->f);
	type string::string* f = cd->result;
	cgen_exp(c, cd, app->a);
	type string::string* a = cd->result;
	type string::string* a_string = gen_temp(c);
	type string::string* a_assign_string = gen_copy(c, a_string, a);
	util::maybe_report_ice(!vector::append(cd->main, a_assign_string$ as byte*) as bool,
		"Could not add function argument copy for a function application in codegen!");

	cd->result = gen_temp(c);
	type string::string* call_string = string::new_string("");
	call_string = string::add(call_string, f);
	call_string = string::addc(call_string, "->which.fo->fun(");
	call_string = string::add(call_string, f);
	call_string = string::addc(call_string, "->which.fo->scope, ");
	call_string = string::add(call_string, a_string);
	call_string = string::addc(call_string, ")");
	type string::string* call_assign_string = gen_assign(c, cd->result, call_string);
	util::maybe_report_ice(!vector::append(cd->main, call_assign_string$ as byte*) as bool,
		"Could not add function call computation in codegen!");
}

} } // namespace shadow::cgen
