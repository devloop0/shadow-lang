import "tck/constrain.hsp"

import <"stdx/vector">
import <"std/lib">
import <"std/io">
import <"std/string">

import "util/stack.hsp"
import "util/symtab.hsp"
import "tck/debug.hsp"
import "lex/token.hsp"
import "ast/ast.hsp"
import "tck/env.hsp"
import "tck/util.hsp"
import "util/error.hsp"

using std::string::strcmp;
using std::lib::malloc;
using std::io::printf;
using std::lib::NULL;
using namespace stdx::vector;

namespace shadow { namespace tck {

func bool constrain_val_decl(type env* e, type ast::val_decl* vd, bool u) {
	type scope orig_scope = e->current_scope;
	e->current_scope = construct_scope(e);

	for (unsigned int i = 0; i < vector::size(vd->var_list); i++) {
		type lex::token* var = vector::at(vd->var_list, i) as type lex::token** @;
		char* var_text = extract_var_text(e, var);
	
		type ast::typ* nt = fresh_typ_variable(e);
		if (util::symtab_lookup(e->current_scope.typ_2_typ_var, var_text$ as byte*, false) != NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, var,
				"Duplicate type variable found for this val declaration.");
			return false;
		}
		util::symtab_set(e->current_scope.typ_2_typ_var, var_text$ as byte*, nt$ as byte*);
	}

	type vector::vector* fresh_typs = vector::new_vector(sizeof{type ast::typ*});
	for (unsigned int i = 0; i < vector::size(vd->val_binds); i++) {
		type ast::typ* t = fresh_typ_variable(e);
		util::maybe_report_ice(!vector::append(fresh_typs, t$ as byte*) as bool,
			"Could not keep track of types for a val declaration's pattern(s).");
	}

	if (vd->rec_present != NULL as type lex::token*) {
		for (unsigned int i = 0; i < vector::size(vd->val_binds); i++) {
			type ast::val_bind* vb = vector::at(vd->val_binds, i)
				as type ast::val_bind** @;
			type ast::typ* curr_typ = vector::at(fresh_typs, i)
				as type ast::typ** @;

			if (!constrain_pat(e, vb->p, curr_typ)) return false;
		}
	}

	for (unsigned int i = 0; i < vector::size(vd->val_binds); i++) {
		type ast::val_bind* vb = vector::at(vd->val_binds, i)
			as type ast::val_bind** @;
		type ast::typ* curr_typ = vector::at(fresh_typs, i)
			as type ast::typ** @;

		if (!constrain_exp(e, vb->e, curr_typ)) return false;
	}
	
	if (vd->rec_present == NULL as type lex::token*) {
		for (unsigned int i = 0; i < vector::size(vd->val_binds); i++) {
			type ast::val_bind* vb = vector::at(vd->val_binds, i)
				as type ast::val_bind** @;
			type ast::typ* curr_typ = vector::at(fresh_typs, i)
				as type ast::typ** @;

			if (!constrain_pat(e, vb->p, curr_typ)) return false;
		}
	}
	
	for (unsigned int i = 0; i < util::symtab_num_entries(e->current_scope.sym_2_typ_var); i++) {
		char* name = vector::at(e->current_scope.sym_2_typ_var->keys, i) as char** @;
		type ast::typ* curr_typ = vector::at(e->current_scope.sym_2_typ_var->values, i) as type ast::typ** @;

		byte* lookup = util::symtab_lookup(orig_scope.sym_2_typ_var, name$ as byte*, false);
		if (lookup != NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, vd->val_start,
				"Duplicate symbol found for this val declaration.");
			return false;
		}

		util::symtab_set(orig_scope.sym_2_typ_var, name$ as byte*, curr_typ$ as byte*);
	}

	e->current_scope = orig_scope;

	if (u) {
		type util::stack st;
		util::init_stack_from_vector(st$, e->typ_constraints);
		// print_tck_ctx(e);
		if (!tck::unify(e->bindings, e, st$)) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, vd->val_start,
				"Could not typecheck this val declaration.");
			return false;
		}
		// print_tck_ctx(e);

		// print_env_symtab(e, e->global_scope.sym_2_typ_var);
		vector::clear(e->typ_constraints);
	}

	return true;
}

func bool constrain_datatyp_repl_decl(type env* e, type ast::datatyp_repl_decl* drd, bool u) {
	char* text = extract_token_text(e, drd->name);
	byte* new_lookup_typ = util::symtab_lookup(e->current_scope.typ_2_typ_var, text$ as byte*, true),
		new_lookup_datatyp = util::symtab_lookup(e->current_scope.datatyp_2_typ_var, text$ as byte*, true);
	if (new_lookup_typ != NULL || new_lookup_datatyp != NULL) {
		util::report_token_error(util::error_kind::ERR, e->par->buf, drd->name,
			"Trying to define a duplicate datatype here.");
		return false;
	}

	byte* old_lookup = lookup_long_datatyp_ident(e, drd->ident);
	if (old_lookup == NULL) {
		type lex::token* first = get_non_null_token(drd->ident);
		util::report_token_error(util::error_kind::ERR, e->par->buf, first,
			"This datatype to replicate was not found.");
		return false;
	}

	type ast::typ* t = old_lookup as type ast::typ** @;
	
	type util::symtab subst;
	init_subst_tab(subst$);
	t = refresh_typ_variables(e, t, subst$);
	// print_typ(e, t), printf("\n");

	util::symtab_set(e->current_scope.datatyp_2_typ_var, text$ as byte*, t$ as byte*);
	return true;
}

func bool constrain_typ_decls(type env* e, type vector::vector* typ_decls, bool u) {
	type scope orig_scope = e->current_scope;

	for (unsigned int i = 0; i < vector::size(typ_decls); i++) {
		e->current_scope = construct_scope(e);
		type ast::typ_decl* td = vector::at(typ_decls, i) as type ast::typ_decl** @;

		type vector::vector* fresh_typs = vector::new_vector(sizeof{type ast::typ*});
		for (unsigned int j = 0; j < vector::size(td->vars); j++) {
			type lex::token* var = vector::at(td->vars, j) as type lex::token** @;
			char* var_name = extract_var_text(e, var);
			type ast::typ* new_typ = fresh_typ_variable(e);

			if (util::symtab_lookup(e->current_scope.typ_2_typ_var, var_name$ as byte*, false) != NULL) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, var,
					"Duplicate type variable found.");
				return false;
			}
			util::symtab_set(e->current_scope.typ_2_typ_var, var_name$ as byte*, new_typ$ as byte*);
			util::maybe_report_ice(!vector::append(fresh_typs, new_typ$ as byte*) as bool,
				"Could not insert type variables into tck type variable list!");
		}
		// print_typ(e, td->ty), printf("\n");
		type ast::typ* reconstructed = reconstruct_typ_with_ctx(e, td->ty);
		// print_typ(e, reconstructed), printf("\n");
		if (reconstructed == NULL as type ast::typ*) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, td->ident,
				"Expected a valid type for this type alias.");
			return false;
		}
		e->current_scope = orig_scope;

		type ast::typ_constructor* tc = malloc(sizeof{type ast::typ_constructor})
			as type ast::typ_constructor*;

		tc->idents = vector::new_vector(sizeof{type lex::token*});
		util::maybe_report_ice(!vector::append(tc->idents, td->ident$ as byte*) as bool,
			"Could not insert identifier for type symbol!");
		tc->typs = fresh_typs;
		util::maybe_report_ice(!vector::append(tc->typs, reconstructed$ as byte*) as bool,
			"Could not insert substituted type!");

		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::CONSTRUCTOR;
		nt->which.tc = tc;

		char* typ_name = extract_token_text(e, td->ident);
		if (util::symtab_lookup(e->current_scope.typ_2_typ_var, typ_name$ as byte*, false) != NULL
			|| util::symtab_lookup(e->current_scope.datatyp_2_typ_var, typ_name$ as byte*, false) != NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, td->ident,
				"Duplicate type name found for this alias.");
			return false;
		}
		util::symtab_set(e->current_scope.typ_2_typ_var, typ_name$ as byte*, nt$ as byte*);
		// print_env_scope(e, e->current_scope$);
	}
	return true;
}

} } // namespace shadow::tck
