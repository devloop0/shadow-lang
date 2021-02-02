import "parse/parse.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/vector">

import "ast/ast.hsp"
import "lex/token.hsp"
import "util/error.hsp"
import "parse/util.hsp"

using std::io::printf;
using std::lib::malloc;
using std::lib::free;
using std::lib::NULL;
using namespace stdx::vector;

namespace shadow { namespace parse {

func type ast::decl* parse_decl(type parser* p) {
	type lex::token* ptok = peek(p);

	if (ptok->tok_type != lex::tokens::FUN
		&& ptok->tok_type != lex::tokens::EFUN
		&& ptok->tok_type != lex::tokens::TYPE
		&& ptok->tok_type != lex::tokens::DATATYPE
		&& ptok->tok_type != lex::tokens::VAL
		&& ptok->tok_type != lex::tokens::IMPORT) {
		util::report_token_error(util::error_kind::ERR, p->buf,
			ptok, "Invalid start to a declaration.");
		return NULL as type ast::decl*;
	}
	pop(p);

	type ast::decl* d = malloc(sizeof{type ast::decl})
		as type ast::decl*;
	if (ptok->tok_type == lex::tokens::FUN || ptok->tok_type == lex::tokens::EFUN) {
		type ast::fun* f = malloc(sizeof{type ast::fun})
			as type ast::fun*;
		d->kind = ptok->tok_type == lex::tokens::EFUN
			? ast::decl_kind::EFUN
			: ast::decl_kind::FUN;
		d->which.fun_decl = f;

		type vector::vector* vars = parse_var_list(p);
		f->typ_vars = vars;

		type vector::vector* fun_binds = vector::new_vector(
			sizeof{type ast::fun_bind*});
		f->fun_binds = fun_binds;

		type ast::fun_bind* curr_bind = malloc(sizeof{type ast::fun_bind})
			as type ast::fun_bind*;
		type vector::vector* curr_fun_matches = vector::new_vector(
			sizeof{type ast::fun_match*});
		curr_bind->fun_matches = curr_fun_matches;
		while (true) {
			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::IDENT) {
				util::report_token_error(util::error_kind::ERR, p->buf,
					ptok, "Expected a function name here.");
				return NULL as type ast::decl*;
			}
			pop(p);

			type ast::fun_match* fun_match = malloc(sizeof{type ast::fun_match})
				as type ast::fun_match*;
			util::maybe_report_ice(!vector::append(curr_fun_matches, fun_match$ as byte*) as bool,
				"Could not insert a funmatch into the fun AST!");
			fun_match->fun_name = ptok;

			fun_match->args = vector::new_vector(sizeof{type ast::pat*});
			ptok = peek(p);
			while (ptok->tok_type != lex::tokens::EQUALS && ptok->tok_type != lex::tokens::COLON) {
				type ast::pat* pat = parse_pat_atomic(p);
				if (pat == NULL as type ast::pat*) break;

				util::maybe_report_ice(!vector::append(fun_match->args, pat$ as byte*) as bool,
					"Could not insert an argument pattern into the fun AST!");
				ptok = peek(p);
			}

			if (ptok->tok_type == lex::tokens::COLON) {
				pop(p);
				type ast::typ* t = parse_typ(p);
				if (t == NULL as type ast::typ*) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Expected a colon (:) to start a function return type "
						"annotation. (Or had an invalid pattern for a formal parameter).");
					return NULL as type ast::decl*;
				}
				fun_match->ret = t;
			}
			else fun_match->ret = NULL as type ast::typ*;

			if (d->kind == ast::decl_kind::EFUN) break;

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::EQUALS) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an equals (=) to start a function body's expression.");
				return NULL as type ast::decl*;
			}
			pop(p);

			type ast::exp* e = parse_exp(p);
			if (e == NULL as type ast::exp*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Invalid function body expression starting here.");
				return NULL as type ast::decl*;
			}

			fun_match->e = e;
			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::BAR)
				pop(p);
			else if (ptok->tok_type == lex::tokens::DOUBLE_AMPERSAND) {
				util::maybe_report_ice(!vector::append(f->fun_binds, curr_bind$ as byte*) as bool,
					"Could not insert function binding!");
				curr_bind = malloc(sizeof{type ast::fun_bind}) as type ast::fun_bind*;
				curr_fun_matches = vector::new_vector(sizeof{type ast::fun_match*});
				curr_bind->fun_matches = curr_fun_matches;
				pop(p);
			}
			else break;
			ptok = peek(p);
		}
		util::maybe_report_ice(!vector::append(f->fun_binds, curr_bind$ as byte*) as bool,
			"Could not insert function binding!");

		return d;
	}
	else if (ptok->tok_type == lex::tokens::TYPE) {
		d->kind = ast::decl_kind::TYP;
		d->which.ty_decls = vector::new_vector(sizeof{type ast::typ_decl*});
		while (true) {
			type ast::typ_decl* td = malloc(sizeof{type ast::typ_decl})
				as type ast::typ_decl*;
			util::maybe_report_ice(!vector::append(d->which.ty_decls, td$ as byte*) as bool,
				"Could not append type declaration to declaration!");

			type vector::vector* vars = parse_var_list(p);
			td->vars = vars;

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::IDENT) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an identifier to name a type.");
				return NULL as type ast::decl*;
			}
			pop(p);

			td->ident = ptok;

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::EQUALS) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an equals (=) to start a type definition.");
				return NULL as type ast::decl*;
			}
			pop(p);

			type ast::typ* t = parse_typ(p);
			if (t == NULL as type ast::typ*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a valid type for a type declaration starting here.");
				return NULL as type ast::decl*;
			}
			td->ty = t;

			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::DOUBLE_AMPERSAND)
				pop(p);
			else break;
			ptok = peek(p);
		}
		return d;
	}
	else if (ptok->tok_type == lex::tokens::DATATYPE) {
		d->kind = ast::decl_kind::DATATYP;
		d->which.dataty_decls = vector::new_vector(sizeof{type ast::datatyp_decl*});

		unsigned int counter = 0;
		do {
			type vector::vector* var_list = parse_var_list(p);
			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::IDENT) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an identifier for a datatype declaration.");
				return NULL as type ast::decl*;
			}
			pop(p);

			type lex::token* name = ptok;
			type vector::vector* constructors = vector::new_vector(sizeof{type ast::datatyp_constructor*});

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::EQUALS) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an '=' to bind a datatype.");
				return NULL as type ast::decl*;
			}
			pop(p);

			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::DATATYPE) {
				pop(p);

				if (vector::size(var_list) != 0) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Expected an empty type variable list for a datatype replication declaration.");
					return NULL as type ast::decl*;
				}

				if (counter != 0) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Cannot replicate and define multiple datatypes in a single declaration.");
					return NULL as type ast::decl*;
				}

				ptok = peek(p);
				if (ptok->tok_type != lex::tokens::IDENT && ptok->tok_type != lex::tokens::DOT) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Expected the name of the datatype to replicate here.");
					return NULL as type ast::decl*;
				}

				type vector::vector* ident = parse_maybe_long_ident(p);

				type ast::datatyp_repl_decl* drd = malloc(sizeof{type ast::datatyp_repl_decl})
					as type ast::datatyp_repl_decl*;
				drd->name = name;
				drd->ident = ident;

				d->kind = ast::decl_kind::DATATYP_REPL;
				d->which.dataty_repl_decl = drd;
				return d;
			}
			
			do {
				type ast::datatyp_constructor* dc = malloc(sizeof{type ast::datatyp_constructor})
					as type ast::datatyp_constructor*;

				ptok = peek(p);
				if (ptok->tok_type != lex::tokens::IDENT) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Expected an identifier to name a datatype constructor.");
					return NULL as type ast::decl*;
				}
				pop(p);
				type lex::token* constr_name = ptok;

				ptok = peek(p);
				if (ptok->tok_type != lex::tokens::OF) {
					dc->ident = constr_name;
					dc->ty = NULL as type ast::typ*;
				}
				else {
					pop(p);

					type ast::typ* constr_t = parse_typ(p);
					if (constr_t == NULL as type ast::typ*) {
						util::report_token_error(util::error_kind::ERR, p->buf, ptok,
							"Expected a valid type for a datatype constructor.");
						return NULL as type ast::decl*;
					}

					dc->ident = constr_name;
					dc->ty = constr_t;
				}

				util::maybe_report_ice(!vector::append(constructors, dc$ as byte*) as bool,
					"Could not add constructor a datatype declaration constructor list!");

				ptok = peek(p);
				if (ptok->tok_type == lex::tokens::BAR) pop(p);
				else break;

				ptok = peek(p);
			} while (true);

			type ast::datatyp_decl* dd = malloc(sizeof{type ast::datatyp_decl})
				as type ast::datatyp_decl*;
			dd->vars = var_list;
			dd->ident = name;
			dd->constructors = constructors;

			util::maybe_report_ice(!vector::append(d->which.dataty_decls, dd$ as byte*) as bool,
				"Could not add datatype declaration to datatype declaration list.");
			
			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::DOUBLE_AMPERSAND) pop(p);
			else break;

			ptok = peek(p);
			counter++;
		} while (true);

		return d;
	}
	else if (ptok->tok_type == lex::tokens::VAL) {
		d->kind = ast::decl_kind::VAL;
			
		type ast::val_decl* vd = malloc(sizeof{type ast::val_decl}) as type ast::val_decl*;
		d->which.vd = vd;

		vd->val_start = ptok;

		vd->rec_present = NULL as type lex::token*;
		ptok = peek(p);
		if (ptok->tok_type == lex::tokens::REC) {
			pop(p);
			vd->rec_present = ptok;
		}

		vd->var_list = parse_var_list(p);

		vd->val_binds = vector::new_vector(sizeof{type ast::val_bind*});
		do {
			type ast::val_bind* vb = malloc(sizeof{type ast::val_bind}) as type ast::val_bind*;

			vb->p = parse_pat(p);
			if (vb->p == NULL as type ast::pat*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a valid pattern for a 'val' declaration.");
				return NULL as type ast::decl*;
			}

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::EQUALS) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an '=' after the pattern for a val declaration.");
				return NULL as type ast::decl*;
			}
			pop(p);

			vb->e = parse_exp(p);
			if (vb->e == NULL as type ast::exp*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a valid expression to assign to a pattern for a 'val' declaration.");
				return NULL as type ast::decl*;
			}

			util::maybe_report_ice(!vector::append(vd->val_binds, vb$ as byte*) as bool,
				"Could not insert val binding into val binding list!");

			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::DOUBLE_AMPERSAND) pop(p);
			else break;

			ptok = peek(p);
		} while (true);

		return d;
	}

	free(d as byte*);
	util::report_token_error(util::error_kind::ICE, p->buf,
		ptok, "Could not handle this declaration!\n");
	return NULL as type ast::decl*;
}

} } // namespace shadow::parse
