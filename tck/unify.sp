import "tck/unify.hsp"

import <"stdx/vector">
import <"std/lib">
import <"std/io">
import <"std/string">

import "util/error.hsp"
import "tck/util.hsp"
import "tck/debug.hsp"
import "util/symtab.hsp"
import "util/stack.hsp"
import "ast/ast.hsp"

using std::io::printf;
using std::lib::NULL;
using std::string::strcmp;
using namespace stdx::vector;

namespace shadow { namespace tck {

func[static] bool binding_symtab_cmp(const byte* a, const byte* b) {
	unsigned int f = a as unsigned int* @,
		s = b as unsigned int* @;
	return f == s;
}

func void init_binding_symtab(type util::symtab* s) {
	util::init_symtab(s, sizeof{unsigned int}, sizeof{type ast::typ*},
		binding_symtab_cmp, NULL as type util::symtab*);
}

func void destroy_binding_symtab(type util::symtab* s) {
	util::destroy_symtab(s);
}

func bool check_recursive(type env* e, unsigned int tv, type ast::typ* t) {
	util::maybe_report_ice(t->kind != ast::typ_kind::VAR,
		"Expected a substituted, reconstructed type for type equality!");

	switch (t->kind) {
	case ast::typ_kind::INT:
	case ast::typ_kind::CHAR:
	case ast::typ_kind::STRING:
	case ast::typ_kind::BOOL:
	case ast::typ_kind::REAL:
	case ast::typ_kind::UNIT:
		return false;
		break;
	case ast::typ_kind::TCK_VAR:
		return t->which.tck_var == tv;
		break;
	case ast::typ_kind::FUN:
		return check_recursive(e, tv, t->which.tf->arg)
			|| check_recursive(e, tv, t->which.tf->ret);
		break;
	case ast::typ_kind::TUP: {
		for (unsigned int i = 0; i < vector::size(t->which.tup); i++) {
			type ast::typ* curr = vector::at(t->which.tup, i)
				as type ast::typ** @;
			if (check_recursive(e, tv, curr)) return true;
		}
		return false;
	}
		break;
	case ast::typ_kind::ROW: {
		for (unsigned int i = 0; i < vector::size(t->which.rmems); i++) {
			type ast::typ_row_mem* curr = vector::at(t->which.rmems, i)
				as type ast::typ_row_mem** @;
			if (check_recursive(e, tv, curr->t)) return true;
		}
		return false;
	}
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		for (unsigned int i = 0; i < vector::size(t->which.tc->typs); i++) {
			type ast::typ* curr = vector::at(t->which.tc->typs, i)
				as type ast::typ** @;
			if (check_recursive(e, tv, curr)) return true;
		}
		return false;
	}
		break;
	}

	util::report_ice("Unhandled type for recursive check!");
	return false;
}

func bool typ_equal(type env* e, type ast::typ* t1, type ast::typ* t2) {
	util::maybe_report_ice(t1->kind != ast::typ_kind::VAR,
		"Expected a substituted, reconstructed type for type equality!");
	util::maybe_report_ice(t2->kind != ast::typ_kind::VAR,
		"Expected a substituted, reconstructed type for type equality!");

	if (t1->kind != t2->kind) return false;

	switch (t1->kind) {
	case ast::typ_kind::CHAR:
	case ast::typ_kind::STRING:
	case ast::typ_kind::INT:
	case ast::typ_kind::REAL:
	case ast::typ_kind::BOOL:
	case ast::typ_kind::UNIT:
		return true;
		break;
	case ast::typ_kind::TCK_VAR:
		return t1->which.tck_var != t2->which.tck_var;
		break;
	case ast::typ_kind::FUN: {
		type ast::typ_fun* tf1 = t1->which.tf,
			tf2 = t2->which.tf;
		return typ_equal(e, tf1->arg, tf2->arg)
			&& typ_equal(e, tf2->ret, tf2->ret);
	}
		break;
	case ast::typ_kind::TUP: {
		type vector::vector* tup1 = t1->which.tup,
			tup2 = t2->which.tup;
		if (vector::size(tup1) != vector::size(tup2)) return false;

		for (unsigned int i = 0; i < vector::size(tup1); i++) {
			type ast::typ* t1_curr = vector::at(tup1, i) as type ast::typ** @,
				t2_curr = vector::at(tup2, i) as type ast::typ** @;
			if (!typ_equal(e, t1_curr, t2_curr)) return false;
		}
		return true;
	}
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		type ast::typ_constructor* tc1 = t1->which.tc,
			tc2 = t2->which.tc;
		byte* lookup1 = lookup_long_typ_ident(e, tc1->idents),
			lookup2 = lookup_long_typ_ident(e, tc2->idents);
		if (lookup1 == NULL || lookup2 == NULL) return false;
		if (lookup1 != lookup2) return false;

		if (vector::size(tc1->typs) != vector::size(tc2->typs)) return false;

		for (unsigned int i = 0; i < vector::size(tc1->typs); i++) {
			type ast::typ* tc1_curr = vector::at(tc1->typs, i) as type ast::typ** @,
				tc2_curr = vector::at(tc2->typs, i) as type ast::typ** @;

			if (!typ_equal(e, tc1_curr, tc2_curr)) return false;
		}

		return true;
	}
		break;
	}

	return false;
}

func bool unify(type util::symtab* s, type env* e, type util::stack* st) {
	while (util::stack_size(st) > 0) {
		type typ_constraint* tc = util::stack_top(st) as type typ_constraint*;
		util::maybe_report_ice(tc->lhs->kind != ast::typ_kind::VAR,
			"Expected a substituted, reconstructed type to unify!");
		util::maybe_report_ice(tc->rhs->kind != ast::typ_kind::VAR,
			"Expected a substituted, reconstructed type to unify!");
		/* print_typ(e, tc->lhs), printf(" = "), print_typ(e, tc->rhs), printf("\n"); */

		if (tc->lhs->kind == ast::typ_kind::TCK_VAR || tc->rhs->kind == ast::typ_kind::TCK_VAR) {
			type ast::typ* lhs = NULL as type ast::typ*,
				rhs = NULL as type ast::typ*;
			if (tc->lhs->kind == ast::typ_kind::TCK_VAR) {
				lhs = tc->lhs;
				rhs = tc->rhs;
			}
			else if (tc->rhs->kind == ast::typ_kind::TCK_VAR) {
				lhs = tc->rhs;
				rhs = tc->lhs;
			}
			else util::report_ice("Expected at least one TCK_VAR type here!");

			if (tc->lhs->kind == tc->rhs->kind && tc->lhs->kind == ast::typ_kind::TCK_VAR
				&& tc->lhs->which.tck_var == tc->rhs->which.tck_var) {
				util::stack_pop(st);
			}
			else {

				if (check_recursive(e, lhs->which.tck_var, rhs)) {
					printf("Cannot unify the following recursive type constraint: "),
						print_typ(e, lhs), printf(" = "), print_typ(e, rhs), printf("\n");
					return false;
				}
				unsigned int tv = lhs->which.tck_var;
				byte* lookup_check = util::symtab_lookup(s, tv$ as byte*, false);
				if (lookup_check != NULL) {
					type ast::typ* lt = lookup_check as type ast::typ** @;
					if (!typ_equal(e, lt, rhs)) return false;
				}
				util::symtab_set(s, tv$ as byte*, rhs$ as byte*);
				/* print_typ(e, lhs), printf(" = "), print_typ(e, rhs),
					printf(" %u\n", util::symtab_num_entries(s)); */

				util::maybe_report_ice(util::stack_size(st) > 0,
					"Expected at least one element in the type constraint stack at this point!");
				for (unsigned int i = 0; i < util::stack_size(st) - 1; i++) {
					type typ_constraint* tc = util::stack_at(st, i) as type typ_constraint*;
					type ast::typ* substituted_lhs = substitute_typ_variables(e, tc->lhs, s),
						substituted_rhs = substitute_typ_variables(e, tc->rhs, s);
					if (substituted_lhs == NULL as type ast::typ*
						|| substituted_rhs == NULL as type ast::typ*) {
						return false;
					}
					tc->lhs = substituted_lhs;
					tc->rhs = substituted_rhs;
				}
				for (unsigned int i = 0; i < util::symtab_num_entries(s); i++) {
					type ast::typ** t = vector::at(s->values, i) as type ast::typ**;
					type ast::typ* substituted = substitute_typ_variables(e, t@, s);
					if (substituted == NULL as type ast::typ*) return false;
					t@ = substituted;
				}

				util::stack_pop(st);
			}
		}
		else {
			if (tc->lhs->kind != tc->rhs->kind) return false;

			util::maybe_report_ice(tc->lhs->kind != ast::typ_kind::VAR
				&& tc->rhs->kind != ast::typ_kind::VAR,
				"Expected substituted, reconstructed type(s) at this point!");
			util::maybe_report_ice(tc->lhs->kind != ast::typ_kind::TCK_VAR
				&& tc->rhs->kind != ast::typ_kind::TCK_VAR,
				"Expected non-type variable(s) at this point!");
			switch (tc->lhs->kind) {
			case ast::typ_kind::BOOL:
			case ast::typ_kind::CHAR:
			case ast::typ_kind::REAL:
			case ast::typ_kind::STRING:
			case ast::typ_kind::INT:
			case ast::typ_kind::UNIT: {
				util::stack_pop(st);
			}
				break;
			case ast::typ_kind::FUN: {
				type ast::typ_fun* tf_lhs = tc->lhs->which.tf,
					tf_rhs = tc->rhs->which.tf;
				type typ_constraint tc_arg, tc_ret;
				tc_arg.lhs = tf_lhs->arg;
				tc_arg.rhs = tf_rhs->arg;

				tc_ret.lhs = tf_lhs->ret;
				tc_ret.rhs = tf_rhs->ret;
				util::stack_pop(st);

				util::stack_push(st, tc_arg$ as byte*);
				util::stack_push(st, tc_ret$ as byte*);
			}
				break;
			case ast::typ_kind::TUP: {
				type vector::vector* lhs_tup = tc->lhs->which.tup,
					rhs_tup = tc->rhs->which.tup;
				if (vector::size(lhs_tup) != vector::size(rhs_tup)) return false;

				util::stack_pop(st);
				for (unsigned int i = 0; i < vector::size(lhs_tup); i++) {
					type ast::typ* lhs_curr = vector::at(lhs_tup, i) as type ast::typ** @,
						rhs_curr = vector::at(rhs_tup, i) as type ast::typ** @;

					type typ_constraint tc;
					tc.lhs = lhs_curr;
					tc.rhs = rhs_curr;
					util::stack_push(st, tc$ as byte*);
				}
			}
				break;
			case ast::typ_kind::ROW: {
				type vector::vector* lhs_rmems = tc->lhs->which.rmems,
					rhs_rmems = tc->rhs->which.rmems;
				if (!check_feasibility(e, tc->lhs, tc->rhs, true)) return false;

				util::stack_pop(st);
				for (unsigned int i = 0; i < vector::size(lhs_rmems); i++) {
					type ast::typ_row_mem* lhs_trm = vector::at(lhs_rmems, i) as type ast::typ_row_mem** @;
					for (unsigned int j = 0; j < vector::size(rhs_rmems); j++) {
						type ast::typ_row_mem* rhs_trm = vector::at(rhs_rmems, j) as type ast::typ_row_mem** @;
						if (strcmp(lhs_trm->ident, rhs_trm->ident) == 0) {
							type typ_constraint tc;
							tc.lhs = lhs_trm->t;
							tc.rhs = rhs_trm->t;
							util::stack_push(st, tc$ as byte*);
							break;
						}
					}
				}
			}
				break;
			case ast::typ_kind::CONSTRUCTOR: {
				type ast::typ_constructor* tc_lhs = tc->lhs->which.tc,
					tc_rhs = tc->rhs->which.tc;

				byte* lhs_lookup = lookup_long_datatyp_ident(e, tc_lhs->idents),
					rhs_lookup = lookup_long_datatyp_ident(e, tc_rhs->idents);

				util::stack_pop(st);
				if (lhs_lookup != rhs_lookup) return false;
				if (vector::size(tc_lhs->typs) != vector::size(tc_rhs->typs)) return false;

				for (unsigned int i = 0; i < vector::size(tc_lhs->typs); i++) {
					type ast::typ* lhs_curr = vector::at(tc_lhs->typs, i) as type ast::typ** @,
						rhs_curr = vector::at(tc_rhs->typs, i) as type ast::typ** @;

					type typ_constraint tc;
					tc.lhs = lhs_curr;
					tc.rhs = rhs_curr;
					util::stack_push(st, tc$ as byte*);
				}
			}
				break;
			}
		}
	}

	return true;
}

} } // namespace shadow::tck
