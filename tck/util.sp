import "tck/util.hsp"

import <"stdx/vector">
import <"std/string">
import <"std/lib">
import <"std/io">

import "src/compile.hsp"
import "tck/debug.hsp"
import "util/symtab.hsp"
import "util/error.hsp"
import "tck/env.hsp"
import "ast/ast.hsp"

using namespace stdx::vector;
using namespace stdx::string;
using std::string::strncpy;
using std::string::strcmp;
using std::string::strlen;
using std::lib::malloc;
using std::lib::free;
using std::lib::NULL;
using std::io::printf;

namespace shadow { namespace tck {

func type ast::typ* fresh_typ_variable(type env* e) {
	type ast::typ* t = malloc(sizeof{type ast::typ})
		as type ast::typ*;
	t->kind = ast::typ_kind::TCK_VAR;
	t->which.tck_var = e->id_counter++;
	return t;
}

func char* extract_token_text(type env* e, type lex::token* tok) {
	unsigned int tok_length = tok->end_pos - tok->start_pos;
	char* str = malloc(tok_length + 1) as char*;
	strncpy(str, tok->buf_ref->text[tok->start_pos]$, tok_length);
	str[tok_length] = 0;
	return str;
}

func char* extract_var_text(type env* e, type lex::token* tok) {
	unsigned int tok_length = tok->end_pos - tok->start_pos;
	char* str = malloc(tok_length + 2) as char*;
	str[0] = '`';
	strncpy(str[1]$, tok->buf_ref->text[tok->start_pos]$, tok_length);
	str[tok_length + 1] = 0;
	return str;
}

func type scope construct_scope(type env* e) {
	type scope s;
	s.sym_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;
	s.typ_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;
	s.datatyp_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;
	s.datatyp_constructor_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;

	init_env_symtab(s.sym_2_typ_var, e->current_scope.sym_2_typ_var);
	init_env_symtab(s.typ_2_typ_var, e->current_scope.typ_2_typ_var);
	init_env_symtab(s.datatyp_2_typ_var, e->current_scope.datatyp_2_typ_var);
	init_env_symtab(s.datatyp_constructor_2_typ_var, e->current_scope.datatyp_constructor_2_typ_var);
	
	util::symtab_add_child(e->current_scope.sym_2_typ_var, s.sym_2_typ_var);
	util::symtab_add_child(e->current_scope.typ_2_typ_var, s.typ_2_typ_var);
	util::symtab_add_child(e->current_scope.datatyp_2_typ_var, s.datatyp_2_typ_var);
	util::symtab_add_child(e->current_scope.datatyp_constructor_2_typ_var, s.datatyp_constructor_2_typ_var);

	return s;
}

func void destroy_scope(type scope* s) {
	free(s->sym_2_typ_var as byte*);
	free(s->typ_2_typ_var as byte*);
	free(s->datatyp_2_typ_var as byte*);
}

func type ast::typ* generate_fun_typ(type env* e, unsigned int num_args) {
	util::maybe_report_ice(num_args > 0,
		"Expected at least one argument for a function!\n");
	type ast::typ* ret = fresh_typ_variable(e);
		
	for (unsigned int i = 0; i < num_args; i++) {
		type ast::typ* arg = fresh_typ_variable(e);
		type ast::typ_fun* tf = malloc(sizeof{type ast::typ_fun}) as type ast::typ_fun*;
		tf->arg = arg;
		tf->ret = ret;

		ret = malloc(sizeof{type ast::typ}) as type ast::typ*;
		ret->kind = ast::typ_kind::FUN;
		ret->which.tf = tf;
	}

	return ret;
}

namespace name_kind {

static constexpr unsigned int TYP = 0x0,
	DATATYP = 0x1,
	SYM = 0x2,
	DATATYP_CONSTRUCTOR = 0x4;

} // namespace name_kind

func[static] type util::symtab* name_kind_2_symtab(type scope* sc, unsigned int kind) {
	type util::symtab* s = NULL as type util::symtab*;

	switch (kind) {
	case name_kind::TYP:
		return sc->typ_2_typ_var;
	case name_kind::DATATYP:
		return sc->datatyp_2_typ_var;
	case name_kind::SYM:
		return sc->sym_2_typ_var;
	case name_kind::DATATYP_CONSTRUCTOR:
		return sc->datatyp_constructor_2_typ_var;
	default:
		util::report_ice("Unrecognized name_kind found during lookup!");
		return NULL as type util::symtab*;
	}

	return NULL as type util::symtab*;
}

func[static] byte* lookup_long_ident_helper(type env* e, type vector::vector* idents,
	unsigned int kind) {
	util::maybe_report_ice(vector::size(idents) > 0,
		"Expected at least one identifier for a type identifier!");

	if (vector::size(idents) == 1) {
		type lex::token* ident = vector::at(idents, 0) as type lex::token** @;

		char* ident_text = extract_token_text(e, ident);
		return util::symtab_lookup(name_kind_2_symtab(e->current_scope$, kind),
			ident_text$ as byte*, true);
	}

	type vector::vector* module_name = get_name_from_identifier(e, idents);
	type vector::vector* full_module_name = to_fully_qualified_name(e, module_name);
	type string::string* full_module_name_str = string::new_string("");
	for (unsigned int i = 0; i < vector::size(full_module_name) - 1; i++) {
		char* curr = vector::at(full_module_name, i) as char** @;
		if (curr != NULL as char*) {
			full_module_name_str = string::addc(full_module_name_str, compile::MOD_FILE_SEP);
			full_module_name_str = string::addc(full_module_name_str, curr);
		}
	}
	char* full_module_name_pstr = string::data(full_module_name_str);

	type lex::token* name_tok = vector::at(idents, vector::size(idents) - 1) as type lex::token** @;
	char* name_str = extract_token_text(e, name_tok);
	
	if (strlen(full_module_name_pstr) == 0) {
		type util::symtab* s = name_kind_2_symtab(e->global_scope$, kind);
		return util::symtab_lookup(s, name_str$ as byte*, false);
	}
	
	byte* mod_ctx_check = util::symtab_lookup(e->mod_ref->imported_modules,
		full_module_name_pstr$ as byte*, false);
	if (mod_ctx_check == NULL) return NULL;
	type module* mod_ctx = mod_ctx_check as type module** @;

	if (mod_ctx->e == NULL as type env*) return NULL;

	type util::symtab* s = name_kind_2_symtab(mod_ctx->e->global_scope$, kind);
	return util::symtab_lookup(s, name_str$ as byte*, false);
}

func byte* lookup_long_typ_ident(type env* e, type vector::vector* idents) {
	return lookup_long_ident_helper(e, idents, name_kind::TYP);
}

func byte* lookup_long_datatyp_ident(type env* e, type vector::vector* idents) {
	return lookup_long_ident_helper(e, idents, name_kind::DATATYP);
}

func byte* lookup_long_sym_ident(type env* e, type vector::vector* idents) {
	return lookup_long_ident_helper(e, idents, name_kind::SYM);
}

func byte* lookup_long_datatyp_constructor_ident(type env* e, type vector::vector* idents) {
	return lookup_long_ident_helper(e, idents, name_kind::DATATYP_CONSTRUCTOR);
}

func type ast::typ* refresh_typ_variables(type env* e, type ast::typ* t, type util::symtab* subst) {
	util::maybe_report_ice(t->kind != ast::typ_kind::VAR, "Expected a reconstructed type here!\n");
	switch (t->kind) {
	case ast::typ_kind::INT:
	case ast::typ_kind::REAL:
	case ast::typ_kind::STRING:
	case ast::typ_kind::CHAR:
	case ast::typ_kind::UNIT:
	case ast::typ_kind::BOOL:
		return t;
		break;
	case ast::typ_kind::TCK_VAR: {
		unsigned int var_num = t->which.tck_var;
		byte* lookup_check = util::symtab_lookup(subst, var_num$ as byte*, false);
		if (lookup_check == NULL) {
			type ast::typ* nt = fresh_typ_variable(e);
			util::symtab_set(subst, var_num$ as byte*, nt$ as byte*);
			return nt;
		}
		return lookup_check as type ast::typ** @;
	}
		break;
	case ast::typ_kind::FUN: {
		type ast::typ_fun* tf = t->which.tf;

		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::FUN;

		type ast::typ* new_arg = refresh_typ_variables(e, tf->arg, subst),
			new_ret = refresh_typ_variables(e, tf->ret, subst);
		if (new_arg == NULL as type ast::typ* || new_ret == NULL as type ast::typ*)
			return NULL as type ast::typ*;

		type ast::typ_fun* ntf = malloc(sizeof{type ast::typ_fun}) as type ast::typ_fun*;
		ntf->arg = new_arg;
		ntf->ret = new_ret;
		nt->which.tf = ntf;
		return nt;
	}
		break;
	case ast::typ_kind::TUP: {
		type vector::vector* tup = t->which.tup;
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		type vector::vector* new_tup = vector::new_vector(sizeof{type ast::typ*});

		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::typ* curr = vector::at(tup, i) as type ast::typ** @;
			type ast::typ* new_curr = refresh_typ_variables(e, curr, subst);
			if (new_curr == NULL as type ast::typ*)
				return NULL as type ast::typ*;
			util::maybe_report_ice(!vector::append(new_tup, new_curr$ as byte*) as bool,
				"Could not insert substituted type constructor into tuple type!\n");
		}

		nt->kind = ast::typ_kind::TUP;
		nt->which.tup = new_tup;
		return nt;
	}
		break;
	case ast::typ_kind::ROW: {
		type vector::vector* rmems = t->which.rmems;
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		type vector::vector* new_rmems = vector::new_vector(sizeof{type ast::typ_row_mem*});

		for (unsigned int i = 0; i < vector::size(rmems); i++) {
			type ast::typ_row_mem* curr_row_mem = vector::at(rmems, i) as type ast::typ_row_mem** @;
			type ast::typ* new_curr = refresh_typ_variables(e, curr_row_mem->t, subst);
			if (new_curr == NULL as type ast::typ*)
				return NULL as type ast::typ*;

			type ast::typ_row_mem* new_row_mem = malloc(sizeof{type ast::typ_row_mem}) as type ast::typ_row_mem*;
			new_row_mem->ident = curr_row_mem->ident;
			new_row_mem->t = new_curr;

			util::maybe_report_ice(!vector::append(new_rmems, new_row_mem$ as byte*) as bool,
				"Could not insert substituted row member into row type!");
		}

		nt->kind = ast::typ_kind::ROW;
		nt->which.rmems = new_rmems;
		return nt;
	}
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		type ast::typ_constructor* tc = t->which.tc;
		type ast::typ_constructor* ntc = malloc(sizeof{type ast::typ_constructor})
			as type ast::typ_constructor*;
		ntc->idents = tc->idents;

		type vector::vector* ntyps = vector::new_vector(sizeof{type ast::typ*});
		for (unsigned int i = 0; i < vector::size(tc->typs); i++) {
			type ast::typ* curr = vector::at(tc->typs, i) as type ast::typ** @;
			type ast::typ* new_curr = refresh_typ_variables(e, curr, subst);
			if (new_curr == NULL as type ast::typ*)
				return NULL as type ast::typ*;
			util::maybe_report_ice(!vector::append(ntyps, new_curr$ as byte*) as bool,
				"Could not insert substituted type constructor into datatype constructor!\n");
		}
		ntc->typs = ntyps;

		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::CONSTRUCTOR;
		nt->which.tc = ntc;
		return nt;
	}
		break;
	}
	return NULL as type ast::typ*;
}

func type ast::typ* substitute_typ_variables(type env* e, type ast::typ* t,
	type util::symtab* subst) {
	util::maybe_report_ice(t->kind != ast::typ_kind::VAR, "Expected a reconstructed type here!\n");
	switch (t->kind) {
	case ast::typ_kind::INT:
	case ast::typ_kind::REAL:
	case ast::typ_kind::STRING:
	case ast::typ_kind::CHAR:
	case ast::typ_kind::UNIT:
	case ast::typ_kind::BOOL:
		return t;
		break;
	case ast::typ_kind::TCK_VAR: {
		unsigned int var_num = t->which.tck_var;
		byte* lookup_check = util::symtab_lookup(subst, var_num$ as byte*, false);
		if (lookup_check == NULL)
			return t;
		type ast::typ* lookup = lookup_check as type ast::typ** @;
		return substitute_typ_variables(e, lookup, subst);
	}
		break;
	case ast::typ_kind::FUN: {
		type ast::typ_fun* tf = t->which.tf;

		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::FUN;

		type ast::typ* new_arg = substitute_typ_variables(e, tf->arg, subst),
			new_ret = substitute_typ_variables(e, tf->ret, subst);
		if (new_arg == NULL as type ast::typ* || new_ret == NULL as type ast::typ*)
			return NULL as type ast::typ*;

		type ast::typ_fun* ntf = malloc(sizeof{type ast::typ_fun}) as type ast::typ_fun*;
		ntf->arg = new_arg;
		ntf->ret = new_ret;
		nt->which.tf = ntf;
		return nt;
	}
		break;
	case ast::typ_kind::TUP: {
		type vector::vector* tup = t->which.tup;
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		type vector::vector* new_tup = vector::new_vector(sizeof{type ast::typ*});

		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::typ* curr = vector::at(tup, i) as type ast::typ** @;
			type ast::typ* new_curr = substitute_typ_variables(e, curr, subst);
			if (new_curr == NULL as type ast::typ*)
				return NULL as type ast::typ*;
			util::maybe_report_ice(!vector::append(new_tup, new_curr$ as byte*) as bool,
				"Could not insert substituted type constructor into tuple type!");
		}

		nt->kind = ast::typ_kind::TUP;
		nt->which.tup = new_tup;
		return nt;
	}
		break;
	case ast::typ_kind::ROW: {
		type vector::vector* rmems = t->which.rmems;
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		type vector::vector* new_rmems = vector::new_vector(sizeof{type ast::typ_row_mem*});

		for (unsigned int i = 0; i < vector::size(rmems); i++) {
			type ast::typ_row_mem* curr_row_mem = vector::at(rmems, i) as type ast::typ_row_mem** @;
			type ast::typ* new_curr = substitute_typ_variables(e, curr_row_mem->t, subst);
			if (new_curr == NULL as type ast::typ*)
				return NULL as type ast::typ*;

			type ast::typ_row_mem* new_trm = malloc(sizeof{type ast::typ_row_mem}) as type ast::typ_row_mem*;
			new_trm->ident = curr_row_mem->ident;
			new_trm->t = new_curr;
			util::maybe_report_ice(!vector::append(new_rmems, new_trm$ as byte*) as bool,
				"Could not insert substituted row type member into row type!");
		}

		nt->kind = ast::typ_kind::ROW;
		nt->which.rmems = new_rmems;
		return nt;
	}
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		type ast::typ_constructor* tc = t->which.tc;
		byte* dt_lookup = lookup_long_datatyp_ident(e, tc->idents);
		if (dt_lookup != NULL) {
			type ast::typ* dtl_typ = dt_lookup as type ast::typ** @;
			util::maybe_report_ice(dtl_typ->kind == ast::typ_kind::CONSTRUCTOR,
				"Expected a constructor type in the symbol table lookup for a datatype!");
			type ast::typ_constructor* dtl_tc = dtl_typ->which.tc;
			type ast::typ_constructor* ntc = malloc(sizeof{type ast::typ_constructor})
				as type ast::typ_constructor*;
			ntc->idents = dtl_tc->idents;
			type lex::token* err_first = get_non_null_token(tc->idents);

			if (vector::size(tc->typs) != vector::size(dtl_tc->typs)) {
				util::report_token_error(util::error_kind::ERR, e->par->buf, err_first,
					"Incorrect arity for type!");
				return NULL as type ast::typ*;
			}

			type vector::vector* ntyps = vector::new_vector(sizeof{type ast::typ*});
			for (unsigned int i = 0; i < vector::size(tc->typs); i++) {
				type ast::typ* curr = vector::at(tc->typs, i) as type ast::typ** @;
				type ast::typ* new_curr = substitute_typ_variables(e, curr, subst);
				if (new_curr == NULL as type ast::typ*)
					return NULL as type ast::typ*;
				util::maybe_report_ice(!vector::append(ntyps, new_curr$ as byte*) as bool,
					"Could not insert substituted type constructor into datatype constructor!\n");
			}
			ntc->typs = ntyps;

			type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
			nt->kind = ast::typ_kind::CONSTRUCTOR;
			nt->which.tc = ntc;
			return nt;
		}

		byte* t_lookup = lookup_long_typ_ident(e, tc->idents);
		type lex::token* err_first = get_non_null_token(tc->idents);
		if (t_lookup == NULL) {
			// print_tck_ctx(e);
			// print_typ(e, t);
			util::report_token_error(util::error_kind::ERR, e->par->buf, err_first,
				"Type not found.");
			return NULL as type ast::typ*;
		}

		type ast::typ* lookup_constr = t_lookup as type ast::typ** @;
		util::maybe_report_ice(lookup_constr->kind == ast::typ_kind::CONSTRUCTOR,
			"Expected a type constructor from a lookup!\n");
		type ast::typ_constructor* lookup_tc = lookup_constr->which.tc;
		util::maybe_report_ice(vector::size(lookup_tc->typs) > 0, "Expected one type for an alias!\n");
		type ast::typ* c = vector::at(lookup_tc->typs, vector::size(lookup_tc->typs) - 1)
			as type ast::typ** @;

		type util::symtab to_subst;
		init_subst_tab(to_subst$);
		if (vector::size(lookup_tc->typs) - 1 != vector::size(tc->typs)) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, err_first,
				"Incorrect arity for type!");
			return NULL as type ast::typ*;
		}

		for (unsigned int i = 0; i < vector::size(lookup_tc->typs) - 1; i++) {
			type ast::typ* param = vector::at(lookup_tc->typs, i)
				as type ast::typ** @;
			util::maybe_report_ice(param->kind == ast::typ_kind::TCK_VAR,
				"Expected a tck type variable!\n");
			type ast::typ* arg = vector::at(tc->typs, i) as type ast::typ** @;
			type ast::typ* substituted_arg = substitute_typ_variables(e, arg, subst);
			if (substituted_arg == NULL as type ast::typ*)
				return NULL as type ast::typ*;
			util::symtab_set(to_subst$, param->which.tck_var$ as byte*, substituted_arg$ as byte*);
		}
		return substitute_typ_variables(e, c, to_subst$);
	}
		break;
	}
	return NULL as type ast::typ*;
}

func[static] type ast::typ* reconstruct_typ_with_ctx_helper(type env* e, type ast::typ* t) {
	switch (t->kind) {
	case ast::typ_kind::INT:
	case ast::typ_kind::REAL:
	case ast::typ_kind::STRING:
	case ast::typ_kind::CHAR:
	case ast::typ_kind::UNIT:
	case ast::typ_kind::BOOL:
	case ast::typ_kind::TCK_VAR:
		return t;
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		type ast::typ_constructor* tc = t->which.tc;
		type vector::vector* idents = tc->idents;
		byte* typ_lookup_check = lookup_long_typ_ident(e, idents),
			datatyp_lookup_check = lookup_long_datatyp_ident(e, idents);
		type lex::token* err_ident = get_non_null_token(idents);
		if (typ_lookup_check == NULL && datatyp_lookup_check == NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, err_ident,
				"This type was not found.");
			return NULL as type ast::typ*;
		}
	
		type vector::vector* typs = vector::new_vector(sizeof{type ast::typ*});
		for (unsigned int i = 0; i < vector::size(tc->typs); i++) {
			type ast::typ* temp = reconstruct_typ_with_ctx_helper(e,
				vector::at(tc->typs, i) as type ast::typ** @);
			if (temp == NULL as type ast::typ*)
				return NULL as type ast::typ*;
			util::maybe_report_ice(!vector::append(typs, temp$ as byte*) as bool,
				"Could not insert reconstructed type into the constructor list.");
		}
		type ast::typ_constructor* new_tc = malloc(sizeof{type ast::typ_constructor}) as
			type ast::typ_constructor*;
		new_tc->typs = typs;
		new_tc->idents = idents;
		
		type ast::typ* ret = malloc(sizeof{type ast::typ}) as type ast::typ*;
		ret->kind = ast::typ_kind::CONSTRUCTOR;
		ret->which.tc = new_tc;
		return ret;
	}
		break;
	case ast::typ_kind::VAR: {
		type lex::token* var = t->which.var;
		char* var_text = extract_var_text(e, var);
		byte* lookup_check = util::symtab_lookup(e->current_scope.typ_2_typ_var, var_text$ as byte*, true);
		if (lookup_check == NULL) {
			util::report_token_error(util::error_kind::ERR, e->par->buf, var,
				"This type variable was not found.");
			return NULL as type ast::typ*;
		}

		return lookup_check as type ast::typ** @;
	}
		break;
	case ast::typ_kind::TUP: {
		type vector::vector* tup = t->which.tup;
		type vector::vector* new_tup = vector::new_vector(sizeof{type ast::typ*});
		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::typ* curr = vector::at(tup, i) as type ast::typ** @;
			type ast::typ* reconstructed = reconstruct_typ_with_ctx_helper(e, curr);
			if (reconstructed == NULL as type ast::typ*)
				return NULL as type ast::typ*;
			util::maybe_report_ice(!vector::append(new_tup, reconstructed$ as byte*) as bool,
				"Could not insert component type into tuple.");
		}
		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::TUP;
		nt->which.tup = new_tup;
		return nt;
	}
		break;
	case ast::typ_kind::ROW: {
		type vector::vector* rmems = t->which.rmems;
		type vector::vector* new_rmems = vector::new_vector(sizeof{type ast::typ_row_mem*});
		for (unsigned int i = 0; i < vector::size(rmems); i++) {
			type ast::typ_row_mem* trm = vector::at(rmems, i) as type ast::typ_row_mem** @;
			type ast::typ* reconstructed = reconstruct_typ_with_ctx_helper(e, trm->t);
			if (reconstructed == NULL as type ast::typ*)
				return NULL as type ast::typ*;

			type ast::typ_row_mem* new_trm = malloc(sizeof{type ast::typ_row_mem*}) as type ast::typ_row_mem*;
			new_trm->ident = trm->ident;
			new_trm->t = reconstructed;
			util::maybe_report_ice(!vector::append(new_rmems, new_trm$ as byte*) as bool,
				"Could not insert component row type member into row.");
		}

		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::ROW;
		nt->which.rmems = new_rmems;
		return nt;
	}
		break;
	case ast::typ_kind::FUN: {
		type ast::typ_fun* tf = t->which.tf;
		type ast::typ* new_arg = reconstruct_typ_with_ctx_helper(e, tf->arg),
			new_ret = reconstruct_typ_with_ctx_helper(e, tf->ret);
		if (new_arg == NULL as type ast::typ* || new_ret == NULL as type ast::typ*)
			return NULL as type ast::typ*;

		type ast::typ_fun* new_tf = malloc(sizeof{type ast::typ_fun}) as type ast::typ_fun*;
		new_tf->arg = new_arg;
		new_tf->ret = new_ret;

		type ast::typ* nt = malloc(sizeof{type ast::typ}) as type ast::typ*;
		nt->kind = ast::typ_kind::FUN;
		nt->which.tf = new_tf;
		return nt;
	}
		break;
	}
	return NULL as type ast::typ*;
}

func type ast::typ* reconstruct_typ_with_ctx(type env* e, type ast::typ* t) {
	t = reconstruct_typ_with_ctx_helper(e, t);
	if (t == NULL as type ast::typ*)
		return NULL as type ast::typ*;
	type util::symtab subst;
	init_subst_tab(subst$);
	return substitute_typ_variables(e, t, subst$);
}

func type ast::typ* reconstruct_and_refresh_typ_with_ctx(type env* e, type ast::typ* t) {
	t = reconstruct_typ_with_ctx_helper(e, t);
	if (t == NULL as type ast::typ*)
		return NULL as type ast::typ*;
	type util::symtab subst;
	init_subst_tab(subst$);
	t = substitute_typ_variables(e, t, subst$);
	if (t == NULL as type ast::typ*)
		return NULL as type ast::typ*;

	type util::symtab subst2;
	init_subst_tab(subst2$);
	return refresh_typ_variables(e, t, subst2$);
}

func bool check_feasibility(type env* e, type ast::typ* lhs, type ast::typ* rhs, bool rec) {
	type util::symtab subst;
	init_subst_tab(subst$);
	lhs = substitute_typ_variables(e, lhs, subst$);
	rhs = substitute_typ_variables(e, rhs, subst$);
	if (lhs == NULL as type ast::typ* || rhs == NULL as type ast::typ*)
		return false;

	util::maybe_report_ice(lhs->kind != ast::typ_kind::VAR,
		"Expected a reconstructed lhs type here!\n");
	util::maybe_report_ice(rhs->kind != ast::typ_kind::VAR,
		"Expected a reconstructed rhs type here!\n");

	if (lhs->kind == ast::typ_kind::TCK_VAR || rhs->kind == ast::typ_kind::TCK_VAR)
		return true;
	if (lhs->kind != rhs->kind)
		return false;
	if (!rec) return true;
	switch (lhs->kind) {
	case ast::typ_kind::REAL:
	case ast::typ_kind::INT:
	case ast::typ_kind::CHAR:
	case ast::typ_kind::UNIT:
	case ast::typ_kind::BOOL:
	case ast::typ_kind::STRING:
		return true;
	case ast::typ_kind::FUN: {
		util::maybe_report_ice(lhs->kind == ast::typ_kind::FUN && rhs->kind == ast::typ_kind::FUN,
			"At this point, expected both types to be function types.");
		type ast::typ_fun* lhs_tf = lhs->which.tf;
		type ast::typ_fun* rhs_tf = rhs->which.tf;
		bool arg_check = check_feasibility(e, lhs_tf->arg, rhs_tf->arg, rec),
			ret_check = check_feasibility(e, lhs_tf->ret, rhs_tf->ret, rec);
		return arg_check && ret_check;
	}
		break;
	case ast::typ_kind::TUP: {
		util::maybe_report_ice(lhs->kind == ast::typ_kind::TUP && rhs->kind == ast::typ_kind::TUP,
			"At this point, expected both types to be tuple types.");
		type vector::vector* lhs_tup = lhs->which.tup;
		type vector::vector* rhs_tup = rhs->which.tup;
		if (vector::size(lhs_tup) != vector::size(rhs_tup)) return false;
		for (unsigned int i = 0; i < vector::size(lhs_tup); i++) {
			type ast::typ* lhs_curr = vector::at(lhs_tup, i) as type ast::typ** @,
				rhs_curr = vector::at(rhs_tup, i) as type ast::typ** @;
			if (!check_feasibility(e, lhs_curr, rhs_curr, rec)) return false;
		}
		return true;
	}
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		util::maybe_report_ice(lhs->kind == ast::typ_kind::CONSTRUCTOR && rhs->kind == ast::typ_kind::CONSTRUCTOR,
			"At this point, expected both types to be constructor types.");
		type ast::typ_constructor* tc_lhs = lhs->which.tc, tc_rhs = rhs->which.tc;
		if (vector::size(tc_lhs->typs) != vector::size(tc_rhs->typs)) return false;

		for (unsigned int i = 0; i < vector::size(tc_lhs->typs); i++) {
			type ast::typ* lhs_curr = vector::at(tc_lhs->typs, i) as type ast::typ** @,
				rhs_curr = vector::at(tc_rhs->typs, i) as type ast::typ** @;
			
			if (!check_feasibility(e, lhs_curr, rhs_curr, rec)) return false;
		}
		return true;
	}
		break;
	case ast::typ_kind::ROW: {
		util::maybe_report_ice(lhs->kind == ast::typ_kind::ROW && rhs->kind == ast::typ_kind::ROW,
			"At this point, expected both types to be row types.");
		type vector::vector* lhs_row = lhs->which.rmems;
		type vector::vector* rhs_row = rhs->which.rmems;
		if (vector::size(lhs_row) != vector::size(rhs_row)) return false;

		{
			type vector::vector* lhs_mems = vector::new_vector(sizeof{char*});
			for (unsigned int i = 0; i < vector::size(lhs_row); i++) {
				type ast::typ_row_mem* trm = vector::at(lhs_row, i) as type ast::typ_row_mem** @;
				for (unsigned int j = 0; j < vector::size(lhs_mems); j++) {
					char* curr_mem = vector::at(lhs_mems, j) as char** @;
					if (strcmp(curr_mem, trm->ident) == 0) return false;
				}
				util::maybe_report_ice(!vector::append(lhs_mems, trm->ident$ as byte*) as bool,
					"Could not add lhs row member name to row member name list!");
			}
		}

		{
			type vector::vector* rhs_mems = vector::new_vector(sizeof{char*});
			for (unsigned int i = 0; i < vector::size(rhs_row); i++) {
				type ast::typ_row_mem* trm = vector::at(rhs_row, i) as type ast::typ_row_mem** @;
				for (unsigned int j = 0; j < vector::size(rhs_mems); j++) {
					char* curr_mem = vector::at(rhs_mems, j) as char** @;
					if (strcmp(curr_mem, trm->ident) == 0) return false;
				}

				util::maybe_report_ice(!vector::append(rhs_mems, trm->ident$ as byte*) as bool,
					"Could not add rhs row member name to row member name list!");
			}
		}

		for (unsigned int i = 0; i < vector::size(lhs_row); i++) {
			type ast::typ_row_mem* lhs_trm = vector::at(lhs_row, i) as type ast::typ_row_mem** @;

			bool hit = false;
			for (unsigned int j = 0; j < vector::size(rhs_row); j++) {
				type ast::typ_row_mem* rhs_trm = vector::at(rhs_row, j) as type ast::typ_row_mem** @;
				if (strcmp(lhs_trm->ident, rhs_trm->ident) == 0) {
					if (!check_feasibility(e, lhs_trm->t, rhs_trm->t, rec)) return false;
					hit = true;
					break;
				}
			}
			if (!hit) return false;
		}

		return true;
	}
		break;
	default:
		return false;
	}
	return false;
}

func type ast::typ* generate_tup_typ(type env* e, unsigned int num_elems) {
	type vector::vector* tup = vector::new_vector(sizeof{type ast::typ*});
	for (unsigned int i = 0; i < num_elems; i++) {
		type ast::typ* temp = fresh_typ_variable(e);
		util::maybe_report_ice(!vector::append(tup, temp$ as byte*) as bool,
			"Could not append type variable to a tuple type!\n");
	}
	type ast::typ* ret = malloc(sizeof{type ast::typ}) as type ast::typ*;
	ret->kind = ast::typ_kind::TUP;
	ret->which.tup = tup;
	return ret;
}

func type ast::typ* generate_base_typ(unsigned int kind) {
	type ast::typ* ret = malloc(sizeof{type ast::typ}) as type ast::typ*;
	ret->kind = kind;
	return ret;
}

func bool subst_tab_cmp(const byte* a, const byte* b) {
	unsigned int f = a as unsigned int* @,
		s = b as unsigned int* @;
	return f == s;
}

func void init_subst_tab(type util::symtab* s) {
	util::init_symtab(s, sizeof{unsigned int}, sizeof{type ast::typ*},
		subst_tab_cmp, NULL as type util::symtab*);
}

func void destroy_subst_tab(type util::symtab* s) {
	util::destroy_symtab(s);
}

func type vector::vector* get_name_from_identifier(
	type env* e, type vector::vector* ident) {
	type vector::vector* ret = vector::new_vector(sizeof{char*});
	char* null_str = NULL as char*;

	for (unsigned int i = 0; i < vector::size(ident); i++) {
		type lex::token* tok = vector::at(ident, i) as type lex::token** @;
		char* ins;
		if (tok == NULL as type lex::token*)
			ins = null_str;
		else
			ins = extract_token_text(e, tok);

		util::maybe_report_ice(!vector::append(ret, ins$ as byte*) as bool,
			"Could not keep track of extracted name from identifier!");
	}
	return ret;
}

func type vector::vector* to_fully_qualified_name(type env* e,
	type vector::vector* name) {
	if (vector::size(name) == 0)
		return name;

	char* initial = vector::at(name, 0) as char** @;
	if (initial == NULL as char*)
		return name;

	type vector::vector* ret = vector::new_vector(sizeof{char*});
	type module* iter = e->mod_ref;
	while (iter != e->mod_ref->global_module) {
		util::maybe_report_ice(!vector::uint_insert(ret, 0, iter->module_name$ as byte*) as bool,
			"Could not keep track of the module hierarchy while constructing a fully qualified name!");
		iter = iter->parent_module;
	}
	char* null_str = NULL as char*;
	util::maybe_report_ice(!vector::uint_insert(ret, 0, null_str$ as byte*) as bool,
		"Could not insert NULL sentinel while constructing a fully qualified name!");

	for (unsigned int i = 0; i < vector::size(name); i++) {
		char* curr = vector::at(name, i) as char** @;
		util::maybe_report_ice(!vector::append(ret, curr$ as byte*) as bool,
			"Could not keep track of the original name while constructing a fully qualified name!");
	}

	return ret;
}

func type string::string* extract_module_name(type module* module_context, const char* sep) {
	type vector::vector* mod_hierarchy = vector::new_vector(sizeof{char*});
	util::maybe_report_ice(!vector::append(mod_hierarchy, module_context->module_name$ as byte*) as bool,
		"Could not keep track of the module name!");
	type module* iter = module_context->parent_module;
	while (iter != NULL as type module*) {
		if (iter != module_context->global_module) {
			util::maybe_report_ice(!vector::append(mod_hierarchy, iter->module_name$ as byte*) as bool,
				"Could not keep track of module names in a module's hierarchy!");
		}
		iter = iter->parent_module;
	}

	type string::string* ret = string::new_string("");
	for (unsigned int i = vector::size(mod_hierarchy); i > 0; i--) {
		char* c = vector::at(mod_hierarchy, i - 1) as char** @;
		ret = string::addc(string::addc(ret, sep), c);
	}

	return ret;
}

func type lex::token* get_non_null_token(type vector::vector* ident) {
	util::maybe_report_ice(vector::size(ident) > 0,
		"Expected an identifier to extract a token from");

	type lex::token* tok = vector::at(ident, 0) as type lex::token**@;
	if (tok != NULL as type lex::token*) return tok;

	return vector::at(ident, 1) as type lex::token** @;
}

} } // namespace shadow::tck
