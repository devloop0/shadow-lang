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

	type vector::vector* pat_checks = vector::new_vector(sizeof{type string::string*});
	for (unsigned int i = 0; i < vector::size(matches); i++) {
		type ast::match* m = vector::at(matches, i) as type ast::match** @;

		type cgen_data new_cd;
		new_cd.header = NULL as type vector::vector*;
		new_cd.body = NULL as type vector::vector*;
		new_cd.main = body_vec;
		new_cd.result = NULL as type string::string*;

		unsigned int old_size = vector::size(body_vec);
		type string::string* pat_check = compute_pat_match(c, new_cd$, string::new_string("arg"), m->p);
		unsigned int new_size = vector::size(body_vec);

		for (unsigned int i = old_size; i < new_size; i++) {
			type string::string** elem = vector::at(body_vec, i) as type string::string**;
			elem@ = left_pad_string(c, 1, '\t', elem@);
		}

		util::maybe_report_ice(!vector::append(pat_checks, pat_check$ as byte*) as bool,
			"Could not keep track of pattern check for a 'fun' pattern in codegen!");
	}

	for (unsigned int i = 0; i < vector::size(matches); i++) {
		type string::string* pat_check = vector::at(pat_checks, i) as type string::string** @;

		type string::string* pat_check_header = i == 0
			? string::new_string("\tif (")
			: string::new_string("\telse if (");
		pat_check_header = string::add(pat_check_header, pat_check);
		pat_check_header = string::addc(pat_check_header, "->which.po->which.b) {");

		add_all_strings(c, body_vec, [
			pat_check_header,
			string::new_string("\t\tscope = rt::scope_push(scope);"),
			NULL as type string::string*
		]);

		type ast::match* m = vector::at(matches, i) as type ast::match** @;
		type cgen_data new_cd;
		new_cd.header = cd->header;
		new_cd.body = vector::new_vector(sizeof{type string::string*});
		new_cd.main = main_vec;
		new_cd.result = string::new_string("arg");

		unsigned int old_main_size = vector::size(new_cd.main);
		bind_pat_to_exp(c, new_cd$, m->p);
		cgen_exp(c, new_cd$, m->e);
		unsigned int new_main_size = vector::size(new_cd.main);

		for (unsigned int i = 0; i < vector::size(new_cd.body); i++) {
			type string::string* s = vector::at(new_cd.body, i) as type string::string** @;
			util::maybe_report_ice(!vector::append(cd->body, s$ as byte*) as bool,
				"Could not insert body statements from a function context in codegen!");
		}
		for (unsigned int i = old_main_size; i < new_main_size; i++) {
			type string::string** elem = vector::at(new_cd.main, i) as type string::string**;
			elem@ = left_pad_string(c, 2, '\t', elem@);
			util::maybe_report_ice(!vector::append(body_vec, elem as byte*) as bool,
				"Could not insert function body into current function context in codegen!");
		}

		type string::string* ret_string = string::new_string("\t\treturn ");
		ret_string = string::add(ret_string, new_cd.result);
		ret_string = string::addc(ret_string, ";");
		add_all_strings(c, body_vec, [
			string::new_string("\t\tscope = rt::scope_pop(scope);"),
			ret_string,
			string::new_string("\t}"),
			NULL as type string::string*
		]);
	}

	add_all_strings(c, body_vec, [
		string::new_string("\telse {"),
		string::new_string("\t\trt::runtime_error(\"Could not match any patterns in a 'fn' expression!\");"),
		string::new_string("\t}"),
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

func void cgen_exp_cmp(type cgen_ctx* c, type cgen_data* cd, type ast::exp_cmp* cmp) {
	util::maybe_report_ice(vector::size(cmp->cmps) + 1 == vector::size(cmp->exps),
		"Expected one more operand than the number of comparisons in codegen!");

	type string::string* final_res = gen_temp(c);
	type string::string* initial_value = string::new_string("rt::init_bool(false)");
	type string::string* init_assign_string = gen_assign(c, final_res, initial_value);
	util::maybe_report_ice(!vector::append(cd->main, init_assign_string$ as byte*) as bool,
		"Could not insert initial assignment for result!");

	type ast::exp* lhs = vector::at(cmp->exps, 0) as type ast::exp** @;
	type string::string* lhs_temp = gen_temp(c);
	cgen_exp(c, cd, lhs);
	type string::string* lhs_assign_string = gen_copy(c, lhs_temp, cd->result);
	lhs_assign_string = left_pad_string(c, 0, '\t', lhs_assign_string);
	util::maybe_report_ice(!vector::append(cd->main, lhs_assign_string$ as byte*) as bool,
		"Could not insert lhs assignment of comparison!");
	for (unsigned int i = 0; i < vector::size(cmp->cmps); i++) {
		type ast::exp* rhs = vector::at(cmp->exps, i + 1) as type ast::exp** @;
		type string::string* rhs_temp = gen_temp(c);

		unsigned int old_size = vector::size(cd->main);
		cgen_exp(c, cd, rhs);
		unsigned int new_size = vector::size(cd->main);
		for (unsigned int j = old_size; j < new_size; j++) {
			type string::string** s = vector::at(cd->main, j) as type string::string**;
			s@ = left_pad_string(c, i, '\t', s@);
		}

		type string::string* rhs_assign_string = gen_copy(c, rhs_temp, cd->result);
		rhs_assign_string = left_pad_string(c, i, '\t', rhs_assign_string);
		util::maybe_report_ice(!vector::append(cd->main, rhs_assign_string$ as byte*) as bool,
			"Could not insert rhs assignment of comparison!");

		type string::string* cmp_assign_string = string::new_string("");
		cmp_assign_string = string::add(cmp_assign_string, final_res);
		type string::string* cmp_op_string = string::new_string(" = rt::");
		switch (vector::at(cmp->cmps, i) as unsigned int* @) {
		case ast::exp_cmp_kind::LT:
			cmp_op_string = string::addc(cmp_op_string, "int_lt");
			break;
		case ast::exp_cmp_kind::LE:
			cmp_op_string = string::addc(cmp_op_string, "int_le");
			break;
		case ast::exp_cmp_kind::GT:
			cmp_op_string = string::addc(cmp_op_string, "int_gt");
			break;
		case ast::exp_cmp_kind::GE:
			cmp_op_string = string::addc(cmp_op_string, "int_ge");
			break;
		case ast::exp_cmp_kind::EQ:
			cmp_op_string = string::addc(cmp_op_string, "eq");
			break;
		case ast::exp_cmp_kind::NE:
			cmp_op_string = string::addc(cmp_op_string, "ne");
			break;
		case ast::exp_cmp_kind::LE_REAL:
			cmp_op_string = string::addc(cmp_op_string, "real_le");
			break;
		case ast::exp_cmp_kind::LT_REAL:
			cmp_op_string = string::addc(cmp_op_string, "real_lt");
			break;
		case ast::exp_cmp_kind::GE_REAL:
			cmp_op_string = string::addc(cmp_op_string, "real_ge");
			break;
		case ast::exp_cmp_kind::GT_REAL:
			cmp_op_string = string::addc(cmp_op_string, "real_gt");
			break;
		default:
			util::report_ice("Unknown ast::exp_cmp_kind found in codegen!");
			break;
		}
		cmp_op_string = string::addc(cmp_op_string, "(");
		cmp_op_string = string::add(cmp_op_string, lhs_temp);
		cmp_op_string = string::addc(cmp_op_string, ", ");
		cmp_op_string = string::add(cmp_op_string, rhs_temp);
		cmp_op_string = string::addc(cmp_op_string, ");");
		cmp_assign_string = string::add(cmp_assign_string, cmp_op_string);
		cmp_assign_string = left_pad_string(c, i, '\t', cmp_assign_string);
		util::maybe_report_ice(!vector::append(cd->main, cmp_assign_string$ as byte*) as bool,
			"Could not add comparison computation string in codegen!");

		type string::string* check_string = string::new_string("if (");
		check_string = string::add(check_string, final_res);
		check_string = string::addc(check_string, "->which.po->which.b) {");
		check_string = left_pad_string(c, i, '\t', check_string);
		util::maybe_report_ice(!vector::append(cd->main, check_string$ as byte*) as bool,
			"Could not add comparison check string in codegen!");
		lhs_temp = rhs_temp;
	}

	type string::string* ok_string = string::new_string("");
	ok_string = string::add(ok_string, final_res);
	ok_string = string::addc(ok_string, " = rt::init_bool(true);");
	ok_string = left_pad_string(c, vector::size(cmp->cmps), '\t', ok_string);
	util::maybe_report_ice(!vector::append(cd->main, ok_string$ as byte*) as bool,
		"Could not add final result of comparison string in codegen!");

	for (unsigned int i = vector::size(cmp->cmps); i > 0; i--) {
		type string::string* brace_string = string::new_string("}");
		brace_string = left_pad_string(c, i - 1, '\t', brace_string);
		util::maybe_report_ice(!vector::append(cd->main, brace_string$ as byte*) as bool,
			"Could not add a closing brace for a comparison in codegen!");
	}
	cd->result = final_res;
}

func void cgen_exp_logical(type cgen_ctx* c, type cgen_data* cd, type ast::exp_binary* eb) {
	util::maybe_report_ice(eb->kind == ast::exp_binary_kind::LAND
		|| eb->kind == ast::exp_binary_kind::LOR, "Expected a logical binary expression here in codegen!");
	type string::string* final_res = gen_temp(c);
	type string::string* initial_value = string::new_string(eb->kind == ast::exp_binary_kind::LAND
		? "rt::init_bool(false)" : "rt::init_bool(true)");
	type string::string* initial_string = gen_assign(c, final_res, initial_value);
	util::maybe_report_ice(!vector::append(cd->main, initial_string$ as byte*) as bool,
		"Could not add initial value for a logical short-circuiting binary expression in codegen!");

	type string::string* lhs_temp = gen_temp(c);
	cgen_exp(c, cd, eb->lhs);
	type string::string* lhs_assign_string = gen_copy(c, lhs_temp, cd->result);
	util::maybe_report_ice(!vector::append(cd->main, lhs_assign_string$ as byte*) as bool,
		"Could not add lhs temporary assignment for a short-circuiting binary expression in codegen!");

	type string::string* lhs_check = string::new_string("if (");
	lhs_check = string::addc(lhs_check,
		eb->kind == ast::exp_binary_kind::LAND ? "" : "!");
	lhs_check = string::add(lhs_check, lhs_temp);
	lhs_check = string::addc(lhs_check, "->which.po->which.b) {");
	util::maybe_report_ice(!vector::append(cd->main, lhs_check$ as byte*) as bool,
		"Could not add lhs temporary check for a short-circuiting binary expression in codegen!");
	
	unsigned int old_size = vector::size(cd->main);

	type string::string* rhs_temp = gen_temp(c);
	cgen_exp(c, cd, eb->rhs);
	type string::string* rhs_assign_string = gen_copy(c, rhs_temp, cd->result);
	util::maybe_report_ice(!vector::append(cd->main, rhs_assign_string$ as byte*) as bool,
		"Could not add rhs temporary assignment for a short-circuiting binary expression in codegen!");

	type string::string* rhs_check = string::new_string("if (");
	rhs_check = string::addc(rhs_check,
		eb->kind == ast::exp_binary_kind::LAND ? "" : "!");
	rhs_check = string::add(rhs_check, rhs_temp);
	rhs_check = string::addc(rhs_check, "->which.po->which.b) {");
	util::maybe_report_ice(!vector::append(cd->main, rhs_check$ as byte*) as bool,
		"Could not add rhs temporary check for a short-circuiting binary expression in codegen!");

	type string::string* final_assign_string = string::new_string("\t");
	final_assign_string = string::add(final_assign_string, final_res);
	final_assign_string = string::addc(final_assign_string, " = ");
	final_assign_string = string::addc(final_assign_string,
		eb->kind == ast::exp_binary_kind::LAND ? "rt::init_bool(true);" : "rt::init_bool(false);");
	util::maybe_report_ice(!vector::append(cd->main, final_assign_string$ as byte*) as bool,
		"Could not add final result assignment for a short-circuiting binary expression in codegen!");

	type string::string* closing_brace = string::new_string("}");
	util::maybe_report_ice(!vector::append(cd->main, closing_brace$ as byte*) as bool,
		"Could not add a closing brace for the final result assignment in a short-circuiting binary expression in codegen!");

	unsigned int new_size = vector::size(cd->main);
	for (unsigned int i = old_size; i < new_size; i++) {
		type string::string** elem = vector::at(cd->main, i) as type string::string**;
		elem@ = left_pad_string(c, 1, '\t', elem@);
	}

	closing_brace = string::new_string("}");
	util::maybe_report_ice(!vector::append(cd->main, closing_brace$ as byte*) as bool,
		"Could not add final closing brace for a short-circuiting binary expression in codegen!");
	cd->result = final_res;
}

func void cgen_exp_binary(type cgen_ctx* c, type cgen_data* cd, type ast::exp_binary* eb) {
	if (eb->kind == ast::exp_binary_kind::LAND || eb->kind == ast::exp_binary_kind::LOR)
		return cgen_exp_logical(c, cd, eb);

	type string::string* lhs_temp = gen_temp(c),
		rhs_temp = gen_temp(c);

	cgen_exp(c, cd, eb->lhs);
	type string::string* lhs_assign_string = gen_copy(c, lhs_temp, cd->result);
	cgen_exp(c, cd, eb->rhs);
	type string::string* rhs_assign_string = gen_copy(c, rhs_temp, cd->result);

	cd->result = gen_temp(c);
	type string::string* op_string = string::new_string("rt::");
	switch (eb->kind) {
	case ast::exp_binary_kind::PLUS:
		op_string = string::addc(op_string, "add_int");
		break;
	case ast::exp_binary_kind::MINUS:
		op_string = string::addc(op_string, "sub_int");
		break;
	case ast::exp_binary_kind::MULT:
		op_string = string::addc(op_string, "mul_int");
		break;
	case ast::exp_binary_kind::DIV:
		op_string = string::addc(op_string, "div_int");
		break;
	case ast::exp_binary_kind::MOD:
		op_string = string::addc(op_string, "mod_int");
		break;
	case ast::exp_binary_kind::SHL:
		op_string = string::addc(op_string, "shl_int");
		break;
	case ast::exp_binary_kind::SHR:
		op_string = string::addc(op_string, "shr_int");
		break;
	case ast::exp_binary_kind::BAND:
		op_string = string::addc(op_string, "band_int");
		break;
	case ast::exp_binary_kind::BOR:
		op_string = string::addc(op_string, "bor_int");
		break;
	case ast::exp_binary_kind::XOR:
		op_string = string::addc(op_string, "xor_int");
		break;
	case ast::exp_binary_kind::STRING_CONCAT:
		op_string = string::addc(op_string, "concat_string");
		break;
	case ast::exp_binary_kind::PLUS_REAL:
		op_string = string::addc(op_string, "add_real");
		break;
	case ast::exp_binary_kind::MINUS_REAL:
		op_string = string::addc(op_string, "sub_real");
		break;
	case ast::exp_binary_kind::MULT_REAL:
		op_string = string::addc(op_string, "mul_real");
		break;
	case ast::exp_binary_kind::DIV_REAL:
		op_string = string::addc(op_string, "div_real");
		break;
	default:
		util::report_ice("Unknown ast::exp_binary_kind found in codegen!");
		break;
	}
	op_string = string::addc(op_string, "(");
	op_string = string::add(op_string, lhs_temp);
	op_string = string::addc(op_string, ", ");
	op_string = string::add(op_string, rhs_temp);
	op_string = string::addc(op_string, ")");
	type string::string* op_assign_string = gen_assign(c, cd->result, op_string);

	util::maybe_report_ice(!vector::append(cd->main, lhs_assign_string$ as byte*) as bool,
		"Could not add computation of lhs of a binary expression in codegen!");
	util::maybe_report_ice(!vector::append(cd->main, rhs_assign_string$ as byte*) as bool,
		"Could not add computation of rhs of a binary expression in codegen!");
	util::maybe_report_ice(!vector::append(cd->main, op_assign_string$ as byte*) as bool,
		"Could not add result computation of a binary expression in codegen!");
}

func void cgen_exp_let(type cgen_ctx* c, type cgen_data* cd, type ast::let_exp* lexp) {
	add_scope_st(c, cd, true);
	cgen_decl(c, cd, lexp->dec);

	type string::string* final_res = gen_temp(c);
	type vector::vector* exps = lexp->exps;

	util::maybe_report_ice(vector::size(exps) > 0,
		"Expected at least one sub-expression in a let expression in codegen!");
	for (unsigned int i = 0; i < vector::size(exps); i++) {
		type ast::exp* curr = vector::at(exps, i) as type ast::exp** @;
		cgen_exp(c, cd, curr);
	}

	add_scope_st(c, cd, false);
	type string::string* copy_string = gen_copy(c, final_res, cd->result);
	util::maybe_report_ice(!vector::append(cd->main, copy_string$ as byte*) as bool,
		"Could not add copy of a let expression's result in codegen!");
	cd->result = final_res;
}

func void cgen_exp_case(type cgen_ctx* c, type cgen_data* cd, type ast::case_exp* cexp) {
	add_scope_st(c, cd, true);
	cgen_exp(c, cd, cexp->e);

	type string::string* final_res = gen_temp(c);
	type string::string* e_res = cd->result;

	type string::string* final_res_decl = string::new_string("type rt::object* ");
	final_res_decl = string::add(final_res_decl, final_res);
	final_res_decl = string::addc(final_res_decl, " = NULL as type rt::object*;");
	util::maybe_report_ice(!vector::append(cd->main, final_res_decl$ as byte*) as bool,
		"Could not add declaration for a case expression's result in codegen!");

	type vector::vector* match_results = vector::new_vector(sizeof{type string::string*});
	for (unsigned int i = 0; i < vector::size(cexp->matches); i++) {
		type ast::match* m = vector::at(cexp->matches, i) as type ast::match** @;
		type string::string* is_match = compute_pat_match(c, cd, e_res, m->p);
		
		util::maybe_report_ice(!vector::append(match_results, is_match$ as byte*) as bool,
			"Could not keep track of a match computation for a case expression in codegen!");
	}

	for (unsigned int i = 0; i < vector::size(cexp->matches); i++) {
		type ast::match* m = vector::at(cexp->matches, i) as type ast::match** @;
		type string::string* is_match = vector::at(match_results, i) as type string::string** @;

		type string::string* condition_header = string::new_string(i == 0 ? "if (" : "else if (");
		condition_header = string::add(condition_header, is_match);
		condition_header = string::addc(condition_header, "->which.po->which.b) {");
		add_all_strings(c, cd->main, [condition_header, NULL as type string::string*]);

		unsigned int old_size = vector::size(cd->main);

		add_scope_st(c, cd, true);

		cd->result = e_res;
		bind_pat_to_exp(c, cd, m->p);
		cgen_exp(c, cd, m->e);

		type string::string* res_store = string::new_string("");
		res_store = string::add(res_store, final_res);
		res_store = string::addc(res_store, " = ");
		res_store = string::add(res_store, cd->result);
		res_store = string::addc(res_store, ";");
		util::maybe_report_ice(!vector::append(cd->main, res_store$ as byte*) as bool,
			"Could not add result assignment for a match branch of a case expression in codegen!");

		add_scope_st(c, cd, false);

		unsigned int new_size = vector::size(cd->main);
		for (unsigned int i = old_size; i < new_size; i++) {
			type string::string** elem = vector::at(cd->main, i) as type string::string**;
			elem@ = left_pad_string(c, 1, '\t', elem@);
		}

		type string::string* condition_footer = string::new_string("}");
		add_all_strings(c, cd->main, [condition_footer, NULL as type string::string*]);
	}

	add_scope_st(c, cd, false);
	cd->result = final_res;
}

} } // namespace shadow::cgen
