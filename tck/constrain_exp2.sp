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

using std::string::strcmp;
using std::io::printf;
using std::lib::malloc;
using std::lib::NULL;
using namespace stdx::vector;

namespace shadow { namespace tck {

func bool constrain_ident_exp(type env* e, type vector::vector* ident, type ast::typ* s_reconstructed) {
	byte* lookup_sym = lookup_long_sym_ident(e, ident);
	byte* lookup_datatyp_constructor = lookup_long_datatyp_constructor_ident(e, ident);
	type lex::token* err_tok = get_non_null_token(ident);
	if (lookup_sym == NULL && lookup_datatyp_constructor == NULL) {
		util::report_token_error(util::error_kind::ERR, e->par->buf, err_tok,
			"Symbol not found.");
		return false;
	}

	if (lookup_sym != NULL) {
		type ast::typ* t_tck_var = lookup_sym as type ast::typ** @;
		type ast::typ* t_reconstructed = reconstruct_typ_with_ctx(e, t_tck_var);
		if (t_tck_var->kind == ast::typ_kind::TCK_VAR) {
			byte* binding_lookup = util::symtab_lookup(e->bindings, t_tck_var->which.tck_var$ as byte*, false);
			if (binding_lookup != NULL) {
				type ast::typ* t = binding_lookup as type ast::typ** @;
				t_reconstructed = reconstruct_and_refresh_typ_with_ctx(e, t);
			}
		}

		if (t_reconstructed == NULL as type ast::typ*) return false;
		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = t_reconstructed;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert symbol expression identifier type constraint!");
	}
	else if (lookup_datatyp_constructor != NULL) {
		type ast::typ* t_dtc = lookup_datatyp_constructor as type ast::typ** @;
		util::maybe_report_ice(t_dtc->kind == ast::typ_kind::CONSTRUCTOR
			|| t_dtc->kind == ast::typ_kind::FUN,
			"Expected a function or constructor type for a datatype constructor symbol!");

		type ast::typ* refreshed = reconstruct_and_refresh_typ_with_ctx(e, t_dtc);
		type typ_constraint tc;
		tc.lhs = s_reconstructed;
		tc.rhs = refreshed;
		util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
			"Could not insert datatype constructor expression identifier type constraint!");
	}
	return true;
}

} } // namespace shadow::tck
