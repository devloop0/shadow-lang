import "tck/constrain.hsp"

import <"std/lib">
import <"stdx/vector">
import <"std/io">
import <"std/string">

import "tck/debug.hsp"
import "lex/token.hsp"
import "util/error.hsp"
import "tck/util.hsp"
import "ast/ast.hsp"
import "tck/env.hsp"
import "tck/constrain_exp.hsp"

using std::string::strcmp;
using std::io::printf;
using std::lib::malloc;
using std::lib::NULL;
using namespace stdx::vector;

namespace shadow { namespace tck {

func bool constrain_binary_exp(type env* e, type ast::exp_binary* eb, type ast::typ* s) {
	type typ_constraint tc;
	tc.lhs = s;
	tc.rhs = NULL as type ast::typ*;

	switch (eb->kind) {
	case ast::exp_binary_kind::MULT: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::MULT_REAL: tc.rhs = generate_base_typ(ast::typ_kind::REAL); break;
	case ast::exp_binary_kind::DIV: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::DIV_REAL: tc.rhs = generate_base_typ(ast::typ_kind::REAL); break;
	case ast::exp_binary_kind::MOD: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::PLUS: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::PLUS_REAL: tc.rhs = generate_base_typ(ast::typ_kind::REAL); break;
	case ast::exp_binary_kind::MINUS: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::MINUS_REAL: tc.rhs = generate_base_typ(ast::typ_kind::REAL); break;
	case ast::exp_binary_kind::SHL: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::SHR: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::BAND: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::XOR: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::BOR: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
	case ast::exp_binary_kind::LAND: tc.rhs = generate_base_typ(ast::typ_kind::BOOL); break;
	case ast::exp_binary_kind::LOR: tc.rhs = generate_base_typ(ast::typ_kind::BOOL); break;
	case ast::exp_binary_kind::STRING_CONCAT: tc.rhs = generate_base_typ(ast::typ_kind::STRING); break;
	}

	util::maybe_report_ice(tc.rhs != NULL as type ast::typ*,
		"Unknown binary expression found!");
	if (!constrain_exp(e, eb->lhs, tc.rhs)) return false;
	if (!constrain_exp(e, eb->rhs, tc.rhs)) return false;

	util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
		"Could not insert binary expression type constraint!");
	return true;
}

func bool constrain_exp(type env* e, type ast::exp* x, type ast::typ* s) {
	type ast::typ* s_reconstructed = reconstruct_typ_with_ctx(e, s);
	if (s_reconstructed == NULL as type ast::typ*)
		return false;
	switch (x->kind) {
	case ast::exp_kind::ROW: {
		type vector::vector* exp_rmems = x->which.rmems;
		{
			type vector::vector* mems = vector::new_vector(sizeof{char*});
			for (unsigned int i = 0; i < vector::size(exp_rmems); i++) {
				type ast::row_mem_exp* rme = vector::at(exp_rmems, i) as type ast::row_mem_exp** @;
				for (unsigned int j = 0; j < vector::size(mems); j++) {
					char* mem_ident = vector::at(mems, j) as char** @;
					if (strcmp(mem_ident, rme->ident) == 0) {
						util::report_token_error(util::error_kind::ERR, e->par->buf, rme->ident_tok,
							"Duplicate row member found for this row expression!");
						return false;
					}
				}
				util::maybe_report_ice(!vector::append(mems, rme->ident$ as byte*) as bool,
					"Could not insert row member label into row expression label list!");
			}
		}
		
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::ROW;
		nt->which.rmems = vector::new_vector(sizeof{type ast::typ_row_mem*});
		for (unsigned int i = 0; i < vector::size(exp_rmems); i++) {
			type ast::row_mem_exp* rme = vector::at(exp_rmems, i) as type ast::row_mem_exp** @;
	
			type ast::typ* mem_typ = fresh_typ_variable(e);
			if (!constrain_exp(e, rme->e, mem_typ)) return false;

			type ast::typ_row_mem* trm = malloc(sizeof{type ast::typ_row_mem}) as type ast::typ_row_mem*;
			trm->ident = rme->ident;
			trm->t = mem_typ;

			util::maybe_report_ice(!vector::append(nt->which.rmems, trm$ as byte*) as bool,
				"Could not insert fresh row member expression type into row type!");
		}

		type typ_constraint tc;
		tc.lhs = nt;
		tc.rhs = s;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert row expression type constraint!");
	}
		break;
	case ast::exp_kind::CONSTANT: {
		type ast::constant* c = x->which.c;
		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		switch (c->kind) {
		case ast::constant_kind::INT: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
		case ast::constant_kind::CHAR: tc.rhs = generate_base_typ(ast::typ_kind::CHAR); break;
		case ast::constant_kind::REAL: tc.rhs = generate_base_typ(ast::typ_kind::REAL); break;
		case ast::constant_kind::STRING: tc.rhs = generate_base_typ(ast::typ_kind::STRING); break;
		case ast::constant_kind::BOOL: tc.rhs = generate_base_typ(ast::typ_kind::BOOL); break;
		}

		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert constant expression type constraint!");
	}
		break;
	case ast::exp_kind::ZERO_TUPLE: {
		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = generate_base_typ(ast::typ_kind::UNIT);
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert zero tuple type constraint!");
	}
		break;
	case ast::exp_kind::IDENT:
		return constrain_ident_exp(e, x->which.ident, s_reconstructed);
		break;
	case ast::exp_kind::APP: {
		type ast::exp_app* ea = x->which.app;
		type ast::typ* a_typ = fresh_typ_variable(e),
			r_typ = fresh_typ_variable(e);

		type ast::typ_fun* tf = malloc(sizeof{type ast::typ_fun}) as type ast::typ_fun*;
		tf->arg = a_typ;
		tf->ret = r_typ;
		type ast::typ* ntf = malloc(sizeof{type ast::typ}) as type ast::typ*;
		ntf->kind = ast::typ_kind::FUN;
		ntf->which.tf = tf;

		if (!constrain_exp(e, ea->f, ntf)) return false;
		if (!constrain_exp(e, ea->a, a_typ)) return false;

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = r_typ;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert return type, type constraint!");
	}
		break;
	case ast::exp_kind::TYP_ANNOT: {
		type ast::exp_typ_annot* eta = x->which.typ_annot;
		if (!constrain_exp(e, eta->e, s)) return false;

		type ast::typ* ty_reconstructed = reconstruct_typ_with_ctx(e, eta->ty);
		if (ty_reconstructed == NULL as type ast::typ*) return false;

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = ty_reconstructed;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert expression type annotation type constraint!");
	}
		break;
	case ast::exp_kind::UNARY: {
		type ast::exp_unary* eu = x->which.un;

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = NULL as type ast::typ*;

		switch (eu->kind) {
		case ast::exp_unary_kind::NOT: tc.rhs = generate_base_typ(ast::typ_kind::BOOL); break;
		case ast::exp_unary_kind::CMPL: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
		case ast::exp_unary_kind::PLUS: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
		case ast::exp_unary_kind::PLUS_REAL: tc.rhs = generate_base_typ(ast::typ_kind::REAL); break;
		case ast::exp_unary_kind::MINUS: tc.rhs = generate_base_typ(ast::typ_kind::INT); break;
		case ast::exp_unary_kind::MINUS_REAL: tc.rhs = generate_base_typ(ast::typ_kind::REAL); break;
		}
		
		util::maybe_report_ice(tc.rhs != NULL as type ast::typ*,
			"Unknown unary expression kind found!");
		if (!constrain_exp(e, eu->e, tc.rhs)) return false;

		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert unary expression type constraint!");
	}
		break;
	case ast::exp_kind::BINARY: 
		return constrain_binary_exp(e, x->which.bin, s_reconstructed);
		break;
	case ast::exp_kind::CMP: {
		type vector::vector* exps = x->which.cmp->exps;
		type vector::vector* cmps = x->which.cmp->cmps;

		char* err1 = "Expected at least one comparison here!",
			err2 = "Expected at least two expressions for a comparison!",
			err3 = "For n operands in a comparison chain, expected n - 1 operations!",
			err4 = "Could not insert comparison type constraint!";

		util::maybe_report_ice(vector::size(cmps) > 0, err1);
		util::maybe_report_ice(vector::size(exps) > 1, err2);
		util::maybe_report_ice(vector::size(cmps) + 1 == vector::size(exps), err3);
		type ast::typ* integral = generate_base_typ(ast::typ_kind::INT),
			real = generate_base_typ(ast::typ_kind::REAL),
			boolean = generate_base_typ(ast::typ_kind::BOOL);
		
		for (unsigned int i = 0; i < vector::size(cmps); i++) {
			type ast::exp* lhs = vector::at(exps, i) as type ast::exp** @,
				rhs = vector::at(exps, i + 1) as type ast::exp** @;
			unsigned int op = vector::at(cmps, i) as unsigned int* @;

			switch (op) {
			case ast::exp_cmp_kind::LE:
			case ast::exp_cmp_kind::LT:
			case ast::exp_cmp_kind::GT:
			case ast::exp_cmp_kind::GE: {
				if (!constrain_exp(e, lhs, integral)) return false;
				if (!constrain_exp(e, rhs, integral)) return false;
			}
				break;
			case ast::exp_cmp_kind::LE_REAL:
			case ast::exp_cmp_kind::LT_REAL:
			case ast::exp_cmp_kind::GT_REAL:
			case ast::exp_cmp_kind::GE_REAL: {
				if (!constrain_exp(e, lhs, real)) return false;
				if (!constrain_exp(e, rhs, real)) return false;
			}
				break;
			case ast::exp_cmp_kind::EQ:
			case ast::exp_cmp_kind::NE: {
				type ast::typ* fresh = fresh_typ_variable(e);
				if (!constrain_exp(e, lhs, fresh)) return false;
				if (!constrain_exp(e, rhs, fresh)) return false;
			}
				break;
			}
		}

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = generate_base_typ(ast::typ_kind::BOOL);
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool, err4);
	}
		break;
	case ast::exp_kind::TUPLE: {
		type vector::vector* tup = x->which.tup;

		type ast::typ* tup_typ = generate_tup_typ(e, vector::size(tup));
		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::typ* ref_typ = vector::at(tup_typ->which.tup, i) as type ast::typ** @;
			type ast::exp* curr_exp = vector::at(tup, i) as type ast::exp** @;

			if (!constrain_exp(e, curr_exp, ref_typ)) return false;
		}

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = tup_typ;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert tuple expression type constraint!");
	}
		break;
	case ast::exp_kind::SEQ: {
		type vector::vector* seq = x->which.seq;

		type ast::typ* last_typ = NULL as type ast::typ*;
		for (unsigned int i = 0; i < vector::size(seq); i++) {
			last_typ = fresh_typ_variable(e);
			type ast::exp* curr_exp = vector::at(seq, i) as type ast::exp** @;
			
			if (!constrain_exp(e, curr_exp, last_typ)) return false;
		}
		util::maybe_report_ice(last_typ != NULL as type ast::typ*,
			"Expected at least one expression in a sequence!");

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = last_typ;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert expression sequence type constraint!");
	}
		break;
	case ast::exp_kind::IF: {
		type ast::if_exp* iexp = x->which.iexp;

		type ast::typ* branch_typ = fresh_typ_variable(e),
			boolean = generate_base_typ(ast::typ_kind::BOOL);

		if (!constrain_exp(e, iexp->cond, boolean)) return false;
		if (!constrain_exp(e, iexp->true_path, branch_typ)) return false;
		if (!constrain_exp(e, iexp->false_path, branch_typ)) return false;

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = branch_typ;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert if expression type constraint!");
	}
		break;
	case ast::exp_kind::LET: {
		type ast::let_exp* lexp = x->which.lexp;
		type scope orig_scope = e->current_scope;
		type vector::vector* old_typ_constraints = e->typ_constraints;

		e->current_scope = construct_scope(e);
		
		if (!constrain_decl(e, lexp->dec, false)) return false;

		type ast::typ* last_typ = NULL as type ast::typ*;
		for (unsigned int i = 0; i < vector::size(lexp->exps); i++) {
			last_typ = fresh_typ_variable(e);
			type ast::exp* curr_exp = vector::at(lexp->exps, i) as type ast::exp** @;

			if (!constrain_exp(e, curr_exp, last_typ)) return false;
		}

		// print_tck_ctx(e);
		util::maybe_report_ice(last_typ != NULL as type ast::typ*,
			"Expected at least one expression in a let expression!");

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = last_typ;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert let expression type constraint!");

		e->current_scope = orig_scope;
	}
		break;
	case ast::exp_kind::WHILE: {
		type ast::while_exp* wexp = x->which.wexp;
		
		type ast::typ* boolean = generate_base_typ(ast::typ_kind::BOOL),
			unit = generate_base_typ(ast::typ_kind::UNIT),
			fresh = fresh_typ_variable(e);

		if (!constrain_exp(e, wexp->cond, boolean)) return false;
		if (!constrain_exp(e, wexp->body, fresh)) return false;

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = unit;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert while expression type constraint!");
	}
		break;
	case ast::exp_kind::CASE: {
		type ast::case_exp* cexp = x->which.cexp;

		type ast::exp* ce = cexp->e;
		type ast::typ* exp_typ = fresh_typ_variable(e),
			m_typ = fresh_typ_variable(e);
		if (!constrain_exp(e, ce, exp_typ)) return false;

		type scope orig_scope = e->current_scope;
		for (unsigned int i = 0; i < vector::size(cexp->matches); i++) {
			e->current_scope = construct_scope(e);

			type ast::match* m = vector::at(cexp->matches, i) as type ast::match** @;
			
			if (!constrain_pat(e, m->p, exp_typ)) return false;
			if (!constrain_exp(e, m->e, m_typ)) return false;

			e->current_scope = orig_scope;
		}

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = m_typ;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert case expression type constraint!");
	}
		break;
	case ast::exp_kind::FN: {
		type ast::typ* arg_typ = fresh_typ_variable(e),
			ret_typ = fresh_typ_variable(e);

		type scope orig_scope = e->current_scope;
		for (unsigned int i = 0; i < vector::size(x->which.anon_fun); i++) {
			e->current_scope = construct_scope(e);

			type ast::match* m = vector::at(x->which.anon_fun, i) as type ast::match** @;
			if (!constrain_pat(e, m->p, arg_typ)) return false;
			if (!constrain_exp(e, m->e, ret_typ)) return false;

			e->current_scope = orig_scope;
		}

		type ast::typ_fun* tf = malloc(sizeof{type ast::typ_fun}) as type ast::typ_fun*;
		tf->arg = arg_typ;
		tf->ret = ret_typ;
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::FUN;
		nt->which.tf = tf;
		
		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = nt;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert lambda expression type constraint!");
	}
		break;
	}
	return true;
}

} } // namespace shadow::tck
