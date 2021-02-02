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

func[static] bool constrain_datatyp_decls_helper(type env* e, type vector::vector* dataty_decls, bool u,
	type vector::vector* reconstructed_typs, type vector::vector* dataty_scopes) {
	type scope orig_scope = e->current_scope;

	for (unsigned int i = 0; i < vector::size(dataty_decls); i++) {
		type ast::datatyp_decl* dd = vector::at(dataty_decls, i)
			as type ast::datatyp_decl** @;

		e->current_scope = construct_scope(e);
		util::maybe_report_ice(!vector::append(dataty_scopes, e->current_scope$ as byte*) as bool,
			"Could not keep track of datatype scopes!");
		type vector::vector* fresh_typs = vector::new_vector(sizeof{type ast::typ*});
		for (unsigned int j = 0; j < vector::size(dd->vars); j++) {
			type lex::token* var_name = vector::at(dd->vars, j) as type lex::token** @;
			char* var_text = extract_var_text(e, var_name);
			type ast::typ* fresh_typ = fresh_typ_variable(e);

			byte* lookup = util::symtab_lookup(e->current_scope.typ_2_typ_var, var_text$ as byte*, false);
			if (lookup != NULL) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, var_name,
					"Duplicate type variable found for datatype declaration.");
				return false;
			}
			util::symtab_set(e->current_scope.typ_2_typ_var, var_text$ as byte*, fresh_typ$ as byte*);

			util::maybe_report_ice(!vector::append(fresh_typs, fresh_typ$ as byte*) as bool,
				"Could not insert fresh type variable for datatype declaration.");
		}
			
		e->current_scope = orig_scope;
		char* name = extract_token_text(e, dd->ident);
		byte* typ_lookup = util::symtab_lookup(e->current_scope.typ_2_typ_var, name$ as byte*, true),
			datatyp_lookup = util::symtab_lookup(e->current_scope.datatyp_2_typ_var, name$ as byte*, true);
		if (typ_lookup != NULL || datatyp_lookup != NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, dd->ident,
				"Duplicate type name found for this datatype declaration.");
			return false;
		}

		type ast::typ_constructor* tc = malloc(sizeof{type ast::typ_constructor})
			as type ast::typ_constructor*;
		tc->idents = vector::new_vector(sizeof{type lex::token*});
		util::maybe_report_ice(!vector::append(tc->idents, dd->ident$ as byte*) as bool,
			"Could not insert datatype name into identifier list.");

		tc->typs = fresh_typs;
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::CONSTRUCTOR;
		nt->which.tc = tc;
		util::maybe_report_ice(!vector::append(reconstructed_typs, nt$ as byte*) as bool,
			"Could not keep track of reconstructed datatypes!");
		// printf("constructor type: "); print_typ(e, nt), printf("\n");
		util::symtab_set(e->current_scope.datatyp_2_typ_var, name$ as byte*, nt$ as byte*);
		// print_tck_ctx(e);
	}

	return true;
}

func bool constrain_datatyp_decls(type env* e, type vector::vector* dataty_decls, bool u) {
	type scope orig_scope = e->current_scope;
	type vector::vector* reconstructed_typs = vector::new_vector(sizeof{type ast::typ*}),
		dataty_scopes = vector::new_vector(sizeof{type scope});

	if (!constrain_datatyp_decls_helper(e, dataty_decls, u, reconstructed_typs, dataty_scopes))
		return false;

	for (unsigned int i = 0; i < vector::size(dataty_decls); i++) {
		type ast::datatyp_decl* dd = vector::at(dataty_decls, i)
			as type ast::datatyp_decl** @;
		type scope curr_scope = vector::at(dataty_scopes, i)
			as type scope* @;
		type ast::typ* reconstructed_datatyp = vector::at(reconstructed_typs, i)
			as type ast::typ** @;

		for (unsigned int j = 0; j < vector::size(dd->constructors); j++) {
			type ast::datatyp_constructor* dc = vector::at(dd->constructors, j)
				as type ast::datatyp_constructor** @;

			char* constr_name = extract_token_text(e, dc->ident);
			byte* sym_lookup = util::symtab_lookup(e->current_scope.sym_2_typ_var, constr_name$ as byte*, false),
				dty_lookup = util::symtab_lookup(e->current_scope.datatyp_constructor_2_typ_var, constr_name$ as byte*, false);
			if (sym_lookup != NULL || dty_lookup != NULL) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, dd->ident,
					"Duplicate symbol name found for this datatype constructor.");
				return false;
			}

			e->current_scope = curr_scope;
			type ast::typ* nt = NULL as type ast::typ*;
			if (dc->ty != NULL as type ast::typ*) {
				type ast::typ* reconstructed = reconstruct_typ_with_ctx(e, dc->ty);
				if (reconstructed == NULL as type ast::typ*) {
					util::report_token_error(util::error_kind::ERR, e->par->buf, dc->ident,
						"Invalid type for this datatype constructor.");
					return false;
				}

				type ast::typ_fun* tf = malloc(sizeof{type ast::typ_fun}) as type ast::typ_fun*;
				tf->arg = reconstructed;
				tf->ret = reconstructed_datatyp;
				nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
				nt->kind = ast::typ_kind::FUN;
				nt->which.tf = tf;
			}
			else
				nt = reconstructed_datatyp;
			e->current_scope = orig_scope;

			util::symtab_set(e->current_scope.datatyp_constructor_2_typ_var, constr_name$ as byte*,
				nt$ as byte*);
		}

		e->current_scope = orig_scope;
	}

	e->current_scope = orig_scope;

	// print_env_symtab(e, e->global_scope.datatyp_2_typ_var);
	// print_env_symtab(e, e->global_scope.datatyp_constructor_2_typ_var);
	// print_tck_ctx(e);

	return true;
}

func bool constrain_decl(type env* e, type ast::decl* d, bool u) {
	switch (d->kind) {
	case ast::decl_kind::EFUN:
	case ast::decl_kind::FUN: {
		type scope orig_scope = e->current_scope;
		type ast::fun* fun_decl = d->which.fun_decl;

		type vector::vector* fun_names = vector::new_vector(sizeof{char*});
		for (unsigned int i = 0; i < vector::size(fun_decl->fun_binds); i++) {
			type ast::fun_bind* fb = vector::at(fun_decl->fun_binds, i)
				as type ast::fun_bind** @;
			util::maybe_report_ice(vector::size(fb->fun_matches) > 0,
				"Expected at least one function match for this function binding!");

			type ast::fun_match* first_fm = vector::at(fb->fun_matches, 0)
				as type ast::fun_match** @;
			char* fun_name = extract_token_text(e, first_fm->fun_name);
			unsigned int arity = vector::size(first_fm->args);

			if (arity == 0) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, first_fm->fun_name,
					"Expected at least one function argument for this function (e.g. ()).");
				return false;
			}

			for (unsigned int j = 0; j < vector::size(fb->fun_matches); j++) {
				type ast::fun_match* fm = vector::at(fb->fun_matches, j)
					as type ast::fun_match** @;
				char* temp_fun_name = extract_token_text(e, fm->fun_name);
				if (strcmp(temp_fun_name, fun_name) != 0) {
					util::report_token_error(util::error_kind::ERR, e->par->buf, fm->fun_name,
						"Multiple function names in a function match!\n");
					return false;
				}
				if (arity != vector::size(fm->args)) {
					util::report_token_error(util::error_kind::ERR, e->par->buf, fm->fun_name,
						"Different function arity's in a function match!\n");
					return false;
				}
			}

			type ast::typ* fresh_typ = fresh_typ_variable(e);
			if (util::symtab_lookup(e->current_scope.sym_2_typ_var, fun_name$ as byte*, false) != NULL) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, first_fm->fun_name,
					"Function already defined!\n");
				return false;
			}
			util::symtab_set(e->current_scope.sym_2_typ_var, fun_name$ as byte*,
				fresh_typ$ as byte*);
			util::maybe_report_ice(!vector::append(fun_names, fun_name$ as byte*) as bool,
				"Could not keep track of function names for generating type constraints!");
		}

		e->current_scope = construct_scope(e);
		for (unsigned int i = 0; i < vector::size(fun_decl->typ_vars); i++) {
			type lex::token* tok = vector::at(fun_decl->typ_vars, i) as type lex::token** @;
			char* var_name = extract_var_text(e, tok);
			type ast::typ* new_var = fresh_typ_variable(e);
			if (util::symtab_lookup(e->current_scope.typ_2_typ_var, var_name$ as byte*, false) != NULL) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, tok,
					"Duplicate type variable found for this function.");
				return false;
			}
			util::symtab_set(e->current_scope.typ_2_typ_var, var_name$ as byte*, new_var$ as byte*);
		}

		type scope fun_scope = e->current_scope;
		for (unsigned int i = 0; i < vector::size(fun_decl->fun_binds); i++) {
			type ast::fun_bind* fb = vector::at(fun_decl->fun_binds, i)
				as type ast::fun_bind** @;
			char* fun_name = vector::at(fun_names, i) as char** @;

			byte* lhs_check = util::symtab_lookup(e->current_scope.sym_2_typ_var, fun_name$ as byte*, true);
			util::maybe_report_ice(lhs_check != NULL,
				"Expected to have a function type variable already populated!");

			type ast::typ* fun_typ_var = lhs_check as type ast::typ** @;
			type ast::fun_match* first_fm = vector::at(fb->fun_matches, 0) as type ast::fun_match** @;
			type ast::typ* fun_typ_sig = generate_fun_typ(e, vector::size(first_fm->args)),;
			type typ_constraint fun_sig_tc;
			fun_sig_tc.lhs = fun_typ_var;
			fun_sig_tc.rhs = fun_typ_sig;
			util::maybe_report_ice(!vector::append(e->typ_constraints, fun_sig_tc$ as byte*) as bool,
				"Could not add function signature type constraint!");
			// print_typ(e, fun_typ_var); printf(" = "); print_typ(e, fun_typ_sig); printf("\n");

			type lex::token* fun_name_tok = NULL as type lex::token*;
			for (unsigned int j = 0; j < vector::size(fb->fun_matches); j++) {
				type ast::fun_match* fm = vector::at(fb->fun_matches, j)
					as type ast::fun_match** @;
				fun_name_tok = fm->fun_name;
				type ast::typ* iter_sig = fun_typ_sig;

				for (unsigned int k = 0; k < vector::size(fm->args); k++) {
					e->current_scope = construct_scope(e);
					util::maybe_report_ice(iter_sig->kind == ast::typ_kind::FUN,
						"Expected a function type here to iterate over!");
					type ast::typ* arg_typ = iter_sig->which.tf->arg;
					// print_typ(e, arg_typ); printf("\n");
					type ast::pat* p = vector::at(fm->args, k) as type ast::pat** @;
					if (!constrain_pat(e, p, arg_typ)) {
						util::report_token_error(util::error_kind::ERR, e->par->buf, fm->fun_name,
							"Invalid pattern argument for this function.");
						return false;
					}

					iter_sig = iter_sig->which.tf->ret;
				}

				if (fm->ret != NULL as type ast::typ*) {
					// print_typ(e, fm->ret); printf("\n");
					type ast::typ* ret_reconstructed = reconstruct_typ_with_ctx(e, fm->ret);
					if (ret_reconstructed == NULL as type ast::typ*) {
						util::report_token_error(util::error_kind::ERR, e->par->buf, fm->fun_name,
							"Invalid return type for a function!\n");
						return false;
					}
					if (!check_feasibility(e, iter_sig, ret_reconstructed, true)) {
						util::report_token_error(util::error_kind::ERR, e->par->buf, fm->fun_name,
							"Return type for function provided is infeasible.");
					}
					type typ_constraint tc;
					tc.lhs = ret_reconstructed;
					tc.rhs = iter_sig;
					util::maybe_report_ice(!vector::append(e->typ_constraints, tc$ as byte*) as bool,
						"Could not insert return type constraint!");
				}

				if (d->kind == ast::decl_kind::FUN && !constrain_exp(e, fm->e, iter_sig)) {
					util::report_token_error(util::error_kind::ERR, e->par->buf, fm->fun_name,
						"Invalid expression for this function.");
					return false;
				}

				// print_env_scope(e, e->current_scope$);
				e->current_scope = fun_scope;
			}

			util::maybe_report_ice(fun_name_tok != NULL as type lex::token*,
				"Expected at least one function match in a function binding!");

			char* err1 = "Could not type check the following function.";

			if (u) {
				type util::stack st;
				util::init_stack_from_vector(st$, e->typ_constraints);
				// print_tck_ctx(e);
				if (!tck::unify(e->bindings, e, st$)) {
					util::report_token_error(util::error_kind::ERR, e->par->buf, fun_name_tok,
						err1);
					return false;
				}
				// print_tck_ctx(e);
				vector::clear(e->typ_constraints);
			}
		}

		e->current_scope = orig_scope;
		return true;
	}
		break;
	case ast::decl_kind::TYP: 
		return constrain_typ_decls(e, d->which.ty_decls, u);
		break;
	case ast::decl_kind::DATATYP: 
		return constrain_datatyp_decls(e, d->which.dataty_decls, u);
		break;
	case ast::decl_kind::DATATYP_REPL:
		return constrain_datatyp_repl_decl(e, d->which.dataty_repl_decl, u);
		break;
	case ast::decl_kind::VAL:
		return constrain_val_decl(e, d->which.vd, u);
		break;
	}

	return false;
}

} } // namespace shadow::tck
