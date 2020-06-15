import "tck/constrain.hsp"

import <"stdx/vector">
import <"std/io">
import <"std/lib">
import <"std/string">

import "util/symtab.hsp"
import "tck/util.hsp"
import "tck/debug.hsp"
import "util/error.hsp"
import "tck/util.hsp"
import "tck/env.hsp"
import "ast/ast.hsp"

using std::io::printf;
using std::string::strcmp;
using std::lib::NULL;
using std::lib::malloc;
using namespace stdx::vector;

namespace shadow { namespace tck {

func bool constrain_pat(type env* e, type ast::pat* p, type ast::typ* s) {
	type ast::typ* s_reconstructed = reconstruct_typ_with_ctx(e, s);
	if (s_reconstructed == NULL as type ast::typ*)
		return false;
	switch (p->kind) {
	case ast::pat_kind::IDENT: {
		type vector::vector* idents = p->which.nested;
		util::maybe_report_ice(vector::size(idents) != 0,
			"Expected at least one identifier for an identifier pattern!");

		byte* datatyp_constructor_lookup = lookup_long_datatyp_constructor_ident(e, idents);
		type lex::token* ident = vector::at(idents, 0) as type lex::token** @;
		if (datatyp_constructor_lookup != NULL) {
			type ast::typ* t_dtc = datatyp_constructor_lookup as type ast::typ** @;
			util::maybe_report_ice(t_dtc->kind == ast::typ_kind::CONSTRUCTOR
				|| t_dtc->kind == ast::typ_kind::FUN,
				"Expected a constructor or function for a datatype constructor symbol!");

			if (t_dtc->kind != ast::typ_kind::CONSTRUCTOR) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, ident,
					"Expected a nullary constructor to match this pattern.");
				return false;
			}

			type ast::typ* reconstructed = reconstruct_and_refresh_typ_with_ctx(e, t_dtc);
			type typ_constraint tc;
			tc.lhs = reconstructed;
			tc.rhs = s_reconstructed;
			util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
				"Could not insert type constraint for a nullary datatype constructor pattern!");
		}
		else {
			type lex::token* ident = vector::at(idents, 0) as type lex::token** @;
			if (vector::size(idents) != 1) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, 
					ident, "Cannot have a nested identifier here.");
				return false;
			}

			char* ident_text = extract_token_text(e, ident);
			type ast::typ* ident_typ = fresh_typ_variable(e);
			if (util::symtab_lookup(e->current_scope.sym_2_typ_var, ident_text$ as byte*, false) != NULL) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, ident,
					"Duplicate symbol found here.");
				return false;
			}
			util::symtab_set(e->current_scope.sym_2_typ_var, ident_text$ as byte*,
				ident_typ$ as byte*);
			type typ_constraint tc;
			tc.lhs = ident_typ;
			tc.rhs = s_reconstructed;
			util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
				"Could not insert an identifier pattern type constraint!");
		}
	}
		break;
	case ast::pat_kind::WILDCARD: break;
	case ast::pat_kind::TYP_ANNOT: {
		type ast::pat_typ_annot* pta = p->which.typ_annot;
		type ast::typ* pta_t_reconstructed = reconstruct_typ_with_ctx(e, pta->t);
		if (pta_t_reconstructed == NULL as type ast::typ*)
			return false;
		if (!check_feasibility(e, pta_t_reconstructed, s_reconstructed, true))
			return false;
		type typ_constraint tc;
		tc.lhs = pta_t_reconstructed;
		tc.rhs = s_reconstructed;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert type annotation pattern type constraint!");
		return constrain_pat(e, pta->p, pta_t_reconstructed);
	}
		break;
	case ast::pat_kind::LAYERED: {
		type ast::pat_layered* layered = p->which.layered;

		char* ident_text = extract_token_text(e, layered->ident);
		type ast::typ* ident_typ = fresh_typ_variable(e);
		if (util::symtab_lookup(e->current_scope.sym_2_typ_var, ident_text$ as byte*, false) != NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, layered->ident,
				"Duplicate symbol found here.");
			return false;
		}
		util::symtab_set(e->current_scope.sym_2_typ_var, ident_text$ as byte*,
			ident_typ$ as byte*);

		if (layered->t != NULL as type ast::typ*) {
			type ast::typ* t_reconstructed = reconstruct_typ_with_ctx(e, layered->t);
			if (t_reconstructed == NULL as type ast::typ*)
				return false;

			type typ_constraint tc;
			tc.lhs = t_reconstructed;
			tc.rhs = ident_typ;
			util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
				"Could not insert layered pattern type annotation type constraint!");
		}

		if (!constrain_pat(e, layered->p, ident_typ)) return false;

		type typ_constraint tc;
		tc.lhs = ident_typ;
		tc.rhs = s_reconstructed;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert layered pattern type constraint!");
		return true;
	}
		break;
	case ast::pat_kind::TUPLE: {
		type vector::vector* tup = p->which.nested;
		util::maybe_report_ice(vector::size(tup) > 0,
			"Expected a tuple to have more than one element at this point.");
		type ast::typ* new_tup_typ = generate_tup_typ(e, vector::size(tup));
		
		if (!check_feasibility(e, s_reconstructed, new_tup_typ, true))
			return false;
		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::typ* curr_typ = vector::at(new_tup_typ->which.tup, i) as type ast::typ** @;
			type ast::pat* curr_p = vector::at(tup, i) as type ast::pat** @;
			if (!constrain_pat(e, curr_p, curr_typ))
				return false;
		}
		type typ_constraint tc;
		tc.lhs = new_tup_typ;
		tc.rhs = s_reconstructed;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert tuple type pattern type constraint!");
		return true;
	}
		break;
	case ast::pat_kind::ROW: {
		type vector::vector* pat_rmems = p->which.rmems;

		{ 
			type vector::vector* pat_mems = vector::new_vector(sizeof{char*});
			for (unsigned int i = 0; i < vector::size(pat_rmems); i++) {
				type ast::pat_row_mem* ptm = vector::at(pat_rmems, i) as type ast::pat_row_mem** @;
				for (unsigned int j = 0; j < vector::size(pat_mems); j++) {
					char* lab = vector::at(pat_mems, j) as char** @;
					if (strcmp(lab, ptm->ident) == 0) {
						util::report_token_error(util::error_kind::ERR, e->par->buf, ptm->ident_tok,
							"Duplicate label found in row pattern!");
						return false;
					}

					util::maybe_report_ice(!vector::append(pat_mems, lab$ as byte*) as bool,
						"Could not insert row pattern label into label list!");
				}
			}
		}

		type vector::vector* typ_rmems = vector::new_vector(sizeof{type ast::typ_row_mem*});
		for (unsigned int i = 0; i < vector::size(pat_rmems); i++) {
			type ast::pat_row_mem* curr_pat = vector::at(pat_rmems, i) as type ast::pat_row_mem** @;
			type ast::typ_row_mem* trm = malloc(sizeof{type ast::typ_row_mem}) as type ast::typ_row_mem*;

			type ast::typ* pat_typ = fresh_typ_variable(e);
			if (curr_pat->sep == NULL as type lex::token* || curr_pat->sep->tok_type == lex::tokens::EQUALS) {
				if (util::symtab_lookup(e->current_scope.sym_2_typ_var, curr_pat->ident$ as byte*, false) != NULL) {
					util::report_token_error(util::error_kind::ERR, e->par->buf, curr_pat->ident_tok,
						"Duplicate symbol found here.");
					return false;
				}
				util::symtab_set(e->current_scope.sym_2_typ_var, curr_pat->ident$ as byte*,
					pat_typ$ as byte*);
			}

			if (curr_pat->p != NULL as type ast::pat*) {
				if (!constrain_pat(e, curr_pat->p, pat_typ))
					return false;
			}

			if (curr_pat->t != NULL as type ast::typ*) {
				type ast::typ* curr_pat_t_reconstructed = reconstruct_typ_with_ctx(e, curr_pat->t);
				if (curr_pat_t_reconstructed == NULL as type ast::typ*)
					return false;

				type typ_constraint tc;
				tc.lhs = pat_typ;
				tc.rhs = curr_pat_t_reconstructed;
				util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
					"Could not insert annotated row member pattern type constraint!");
			}

			trm->ident = curr_pat->ident;
			trm->t = pat_typ;

			util::maybe_report_ice(!vector::append(typ_rmems, trm$ as byte*) as bool,
				"Could not insert constructed row member type into row type!");
		}
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::ROW;
		nt->which.rmems = typ_rmems;

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = nt;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert an identifier pattern type constraint!");
		return true;
	}
		break;
	case ast::pat_kind::ZERO_TUPLE: {
		type ast::typ* n_unit = generate_base_typ(ast::typ_kind::UNIT);
		if (!check_feasibility(e, s_reconstructed, n_unit, true))
			return false;
		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = n_unit;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert zero-tuple type pattern type constraint!");
		return true;
	}
		break;
	case ast::pat_kind::CONSTANT: {
		unsigned int nt_kind;
		switch (p->which.con->kind) {
		case ast::constant_kind::INT: nt_kind = ast::typ_kind::INT; break;
		case ast::constant_kind::REAL: nt_kind = ast::typ_kind::REAL; break;
		case ast::constant_kind::CHAR: nt_kind = ast::typ_kind::CHAR; break;
		case ast::constant_kind::STRING: nt_kind = ast::typ_kind::STRING; break;
		case ast::constant_kind::BOOL: nt_kind = ast::typ_kind::BOOL; break;
		}
		type ast::typ* nt = generate_base_typ(nt_kind);
		if (!check_feasibility(e, s_reconstructed, nt, true))
			return false;
		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = nt;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert constant type pattern type constraint!");
		return true;
	}
		break;
	case ast::pat_kind::CONSTRUCTION: {
		type ast::pat_construction* pc = p->which.pc;

		byte* datatyp_constructor_lookup = lookup_long_datatyp_constructor_ident(e, pc->idents);
		type lex::token* first = vector::at(pc->idents, 0) as type lex::token** @;
		if (datatyp_constructor_lookup == NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, first,
				"The symbol given was either not found or was not a datatype constructor.");
			return false;
		}

		type ast::typ* t_dtc = datatyp_constructor_lookup as type ast::typ** @;
		util::maybe_report_ice(t_dtc->kind == ast::typ_kind::CONSTRUCTOR
			|| t_dtc->kind == ast::typ_kind::FUN,
			"Expected a constructor or a function from a datatype constructor symbol!");

		if (t_dtc->kind != ast::typ_kind::FUN) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, first,
				"Expected a non-nullary datatype constructor for a construction pattern.");
			return false;
		}

		type ast::typ* tf = reconstruct_and_refresh_typ_with_ctx(e, t_dtc);
		util::maybe_report_ice(tf->kind == ast::typ_kind::FUN,
			"Expected a function datatype constructor here.");
		type ast::typ_fun* t_fun = tf->which.tf;
		
		if (!constrain_pat(e, pc->p, t_fun->arg)) return false;

		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = t_fun->ret;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert a construction pattern type constraint!");
	}
		break;
	}
	return true;
}

} } // namespace shadow::tck
