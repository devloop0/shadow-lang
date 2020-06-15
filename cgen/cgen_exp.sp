import "cgen/cgen.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/string">
import <"stdx/vector">

import "tck/util.hsp"
import "cgen/util.hsp"
import "util/error.hsp"
import "ast/ast.hsp"
import "cgen/cgen_exp.hsp"

using std::lib::NULL;
using std::lib::malloc;
using std::io::printf;
using namespace stdx::string;
using namespace stdx::vector;

namespace shadow { namespace cgen {

func void cgen_exp(type cgen_ctx* c, type cgen_data* cd, type ast::exp* e) {
	switch (e->kind) {
	case ast::exp_kind::CONSTANT: {
		type ast::constant* ec = e->which.c;
		
		cd->result = gen_temp(c);

		type string::string* const_string = string::new_string("rt::init_");

		char* tok_text = tck::extract_token_text(c->e, ec->which);
		switch (ec->kind) {
		case ast::constant_kind::INT: 
			const_string = string::addc(const_string, "int");
			break;
		case ast::constant_kind::REAL: 
			const_string = string::addc(const_string, "real");
			break;
		case ast::constant_kind::CHAR: 
			const_string = string::addc(const_string, "char");
			break;
		case ast::constant_kind::STRING:
			const_string = string::addc(const_string, "string");
			break;
		case ast::constant_kind::BOOL:
			const_string = string::addc(const_string, "bool");
			break;
		default:
			util::report_ice("Unknown ast::constant_kind found during codegen!");
			return;
		}
		const_string = string::addc(const_string, "(");
		const_string = string::addc(const_string, tok_text);
		const_string = string::addc(const_string, ")");
		const_string = gen_assign(c, cd->result, const_string);

		util::maybe_report_ice(!vector::append(cd->main, const_string$ as byte*) as bool,
			"Could not add generated code for a constant expression!");
	}
		break;
	case ast::exp_kind::TUPLE: {
		type vector::vector* tup = e->which.tup;
		type string::string* curr_temp = gen_temp(c);

		type string::string* tup_args = string::new_string("");
		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::exp* ec = vector::at(tup, i) as type ast::exp** @;
			cgen_exp(c, cd, ec);

			type string::string* copy_string = gen_temp(c);
			type string::string* assign_string = gen_copy(c, copy_string, cd->result);
			util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
				"Could not add generated code for a tuple-element expression!");

			tup_args = string::add(tup_args, copy_string);
			if (i != vector::size(tup) - 1) {
				tup_args = string::addc(tup_args, ", ");
			}
		}

		type string::string* tup_assign = string::new_string("rt::init_tup(");
		tup_assign = string::addc(tup_assign, itoa(vector::size(tup)));
		tup_assign = string::addc(tup_assign, ", ");
		tup_assign = string::add(tup_assign, tup_args);
		tup_assign = string::addc(tup_assign, ")");

		tup_assign = gen_assign(c, curr_temp, tup_assign);
		util::maybe_report_ice(!vector::append(cd->main, tup_assign$ as byte*) as bool,
			"Could not add generated code for a tuple expression!");
		cd->result = curr_temp;
	}
		break;
	case ast::exp_kind::IDENT: {
		type vector::vector* idents = e->which.ident;

		// TODO: Remove this limitation!
		byte* dtc_lookup = tck::lookup_long_datatyp_constructor_ident(c->e, idents);
		util::maybe_report_ice(dtc_lookup == NULL, "Found a non-symbol expression identifier here!");

		util::maybe_report_ice(vector::size(idents) == 1,
			"Did not expect a nested identifier in a 'val' declaration's codegen!");

		type lex::token* ident = vector::at(idents, 0)
			as type lex::token** @;
		char* ident_text = tck::extract_token_text(c->e, ident);

		cd->result = gen_temp(c);
		type string::string* helper_string = string::new_string("rt::scope_lookup(scope, \"");
		helper_string = string::addc(helper_string, ident_text);
		helper_string = string::addc(helper_string, "\")");
		type string::string* assign_string = gen_copy(c, cd->result, helper_string);
		util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
			"Could not add generated code for an identifier symbol expression!");
	}
		break;
	case ast::exp_kind::ZERO_TUPLE: {
		cd->result = gen_temp(c);
		type string::string* zt = string::new_string("rt::init_unit()");

		type string::string* assign_string = gen_assign(c, cd->result, zt);
		util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
			"Could not add generated code for a unit expression!");
	}
		break;
	case ast::exp_kind::BINARY: {
		type ast::exp_binary* eb = e->which.bin;
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
		case ast::exp_binary_kind::LAND:
			op_string = string::addc(op_string, "and_bool");
			break;
		case ast::exp_binary_kind::LOR:
			op_string = string::addc(op_string, "or_bool");
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
		break;
	case ast::exp_kind::UNARY:
		return cgen_exp_unary(c, cd, e->which.un);
	case ast::exp_kind::CMP: {
		type ast::exp_cmp* cmp = e->which.cmp;

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
		break;
	case ast::exp_kind::SEQ: {
		for (unsigned int i = 0; i < vector::size(e->which.seq); i++) {
			type ast::exp* curr = vector::at(e->which.seq, i) as type ast::exp** @;
			cgen_exp(c, cd, curr);
		}
	}
		break;
	case ast::exp_kind::TYP_ANNOT: {
		type ast::exp_typ_annot* annot = e->which.typ_annot;
		cgen_exp(c, cd, annot->e);
	}
		break;
	case ast::exp_kind::FN: 
		return cgen_exp_fun(c, cd, e->which.anon_fun);
	case ast::exp_kind::APP: 
		return cgen_exp_app(c, cd, e->which.app);
	case ast::exp_kind::IF:
		return cgen_exp_if(c, cd, e->which.iexp);
	// TODO
	default:
		util::report_ice("Unknown ast::exp_kind found in codegen!");
		break;
	}

	return;
}

} } // namespace shadow::cgen
