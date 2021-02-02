import "cgen/util.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/vector">
import <"stdx/string">

import "src/compile.hsp"
import "tck/util.hsp"
import "util/error.hsp"
import "cgen/cgen.hsp"

using std::io::printf;
using std::lib::calloc;
using std::lib::NULL;
using namespace stdx::vector;
using namespace stdx::string;

namespace shadow { namespace cgen {

func void init_cgen_data(type cgen_data* cd) {
	cd->header = vector::new_vector(sizeof{type string::string*});
	cd->body = vector::new_vector(sizeof{type string::string*});
	cd->main = vector::new_vector(sizeof{type string::string*});
	cd->result = NULL as type string::string*;
}

func void add_cgen_data(type cgen_data* pcd, type cgen_data* cd,
	unsigned int bi, unsigned int mi) {
	for (unsigned int i = 0; i < vector::size(cd->header); i++) {
		type string::string* s = vector::at(cd->header, i) as type string::string** @;
		util::maybe_report_ice(!vector::append(pcd->header, s$ as byte*) as bool,
			"Could not add code to program's header!");
	}

	for (unsigned int i = 0; i < vector::size(cd->body); i++) {
		type string::string* s = vector::at(cd->body, i) as type string::string** @;
		for (unsigned int i = 0; i < bi; i++)
			s = string::cadd("\t", s);

		util::maybe_report_ice(!vector::append(pcd->body, s$ as byte*) as bool,
			"Could not add code to program's body!");
	}

	for (unsigned int i = 0; i < vector::size(cd->main); i++) {
		type string::string* s = vector::at(cd->main, i) as type string::string** @;
		for (unsigned int i = 0; i < mi; i++)
			s = string::cadd("\t", s);

		util::maybe_report_ice(!vector::append(pcd->main, s$ as byte*) as bool,
			"Could not add code program's main!");
	}
}

func char* itoa(int ui) {
	char* tmp = stk char(20), tmp_iter = tmp;
	char* ret = calloc(sizeof{char}, 20) as char*;
	unsigned int end = 0;
	if (ui == 0) {
		ret@ = '0';
		return ret;
	}
	while(ui as bool) {
		tmp_iter@ = (ui % 10) + '0';
		tmp_iter = tmp_iter[1]$;
		end++, ui /= 10;
	}
	for(int i = end - 1; i >= 0; i--, tmp = tmp[1]$)
		ret[i] = tmp@;
	return ret;
}

func type string::string* gen_temp(type cgen_ctx* c) {
	type string::string* curr_temp = string::new_string("t");
	curr_temp = string::addc(curr_temp, itoa(c->label_counter++));
	return curr_temp;
}

func type string::string* gen_assign(type cgen_ctx* c,
	type string::string* lhs, type string::string* rhs) {
	type string::string* curr = string::new_string("type rt::object* ");
	curr = string::add(curr, lhs);
	curr = string::addc(curr, " = ");
	curr = string::add(curr, rhs);
	curr = string::addc(curr, ";");
	return curr;
}

func type string::string* gen_copy(type cgen_ctx* c,
	type string::string* lhs, type string::string* rhs) {
	type string::string* curr = string::new_string("type rt::object* ");
	curr = string::add(curr, lhs);
	curr = string::addc(curr, " = rt::copy_object(");
	curr = string::add(curr, rhs);
	curr = string::addc(curr, ");");
	return curr;
}

func type string::string* gen_debug(type cgen_ctx* c,
	type string::string* exp) {
	type string::string* ret = string::new_string("rtio::debugln(");
	ret = string::add(ret, exp);
	ret = string::addc(ret, ");");
	return ret;
}

func type string::string* left_pad_string(type cgen_ctx* ctx,
	unsigned int num, char c, type string::string* s) {
	for (unsigned int i = 0; i < num; i++)
		s = string::chadd(c, s);
	return s;
}

func void add_scope_st(type cgen_ctx* c, type cgen_data* cd, bool setup) {
	if (setup) {
		type string::string* temp = string::new_string("scope = rt::scope_push(scope);");
		util::maybe_report_ice(!vector::append(cd->main, temp$ as byte*) as bool,
			"Could not push new scope in codegen!");
	}
	else {
		type string::string* temp = string::new_string("scope = rt::scope_pop(scope);");
		util::maybe_report_ice(!vector::append(cd->main, temp$ as byte*) as bool,
			"Could not pop scope in codegen!");
	}
}

func void add_all_strings(type cgen_ctx* c, type vector::vector* vec,
	type string::string** data) {
	for (unsigned int i = 0; data[i] != NULL as type string::string*; i++) {
		util::maybe_report_ice(!vector::append(vec, data[i]$ as byte*) as bool,
			"Could not insert type string::string* into type vector::vector* in codegen!");
	}
}

func void bind_pat_to_exp(type cgen_ctx* c, type cgen_data* cd,
	type ast::pat* p) {
	util::maybe_report_ice(cd->result != NULL as type string::string*,
		"Expected an expression to assign a pattern to!");

	switch (p->kind) {
	case ast::pat_kind::WILDCARD:
	case ast::pat_kind::CONSTANT:
	case ast::pat_kind::ZERO_TUPLE:
		break;
	case ast::pat_kind::IDENT: {
		type vector::vector* idents = p->which.nested;

		// TODO: This current just looks things up from the global scope; fix this.
		byte* dtc_lookup = tck::lookup_long_datatyp_constructor_ident(c->e, idents);
		if (dtc_lookup != NULL as byte*)
			return;

		util::maybe_report_ice(vector::size(idents) == 1,
			"Did not expect a nested identifier while binding a pattern to an expression during codegen!");

		type lex::token* ident = vector::at(idents, 0)
			as type lex::token** @;
		char* ident_text = tck::extract_token_text(c->e, ident);

		type string::string* assign_string = string::new_string("rt::scope_set(scope, \"");
		assign_string = string::addc(assign_string, ident_text);
		assign_string = string::addc(assign_string, "\", ");
		assign_string = string::add(assign_string, cd->result);
		assign_string = string::addc(assign_string, ");");
		util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
			"Could not add identifier pattern assignment code!");

		if (c->debug) {
			type string::string* ident_print_string = string::new_string("stdio::printf(\"");
			ident_print_string = string::addc(ident_print_string, ident_text);
			ident_print_string = string::addc(ident_print_string, " = \"), ");

			type string::string* lookup_string = string::new_string("rt::scope_lookup(scope, \"");
			lookup_string = string::addc(lookup_string, ident_text);
			lookup_string = string::addc(lookup_string, "\")");
			type string::string* debug_string = gen_debug(c, lookup_string);
			debug_string = string::add(ident_print_string, debug_string);
			
			util::maybe_report_ice(!vector::append(cd->main, debug_string$ as byte*) as bool,
				"Could not add debug printing statement on assignment!");
		}
	}
		break;
	case ast::pat_kind::TUPLE: {
		type vector::vector* tup = p->which.nested;
		type string::string* tup_result = cd->result;

		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::pat* curr_pat = vector::at(tup, i) as type ast::pat** @;
			
			if (curr_pat->kind != ast::pat_kind::WILDCARD) {
				type string::string* curr_temp = gen_temp(c),
					curr_temp2 = gen_temp(c);

				type string::string* curr_res = string::new_string("vector::at(");
				curr_res = string::add(curr_res, tup_result);
				curr_res = string::addc(curr_res, "->which.tup, ");
				curr_res = string::addc(curr_res, itoa(i));
				curr_res = string::addc(curr_res, ") as type rt::object** @");

				curr_res = gen_assign(c, curr_temp2, curr_res);
				util::maybe_report_ice(!vector::append(cd->main, curr_res$ as byte*) as bool,
					"Could not add tuple-pattern assignment code!");
				curr_res = gen_copy(c, curr_temp, curr_temp2);
				util::maybe_report_ice(!vector::append(cd->main, curr_res$ as byte*) as bool,
					"Could not add tuple-pattern copy assignment code!");

				cd->result = curr_temp;
				bind_pat_to_exp(c, cd, curr_pat);
			}
		}
	}
		break;
	case ast::pat_kind::TYP_ANNOT: {
		type ast::pat_typ_annot* pta = p->which.typ_annot;
		bind_pat_to_exp(c, cd, pta->p);
	}
		break;
	case ast::pat_kind::CONSTRUCTION: {
		type ast::pat_construction* pc = p->which.pc;

		type string::string* temp = gen_temp(c);
		type string::string* rhs = string::new_string("");
		rhs = string::add(rhs, cd->result);
		rhs = string::addc(rhs, "->which.dto->data");
		type string::string* assign = gen_assign(c, temp, rhs);
		add_all_strings(c, cd->main, [
			assign,
			NULL as type string::string*
		]);

		cd->result = temp;
		bind_pat_to_exp(c, cd, pc->p);
	}
		break;
	// TODO
	default:
		util::report_ice("Unknown ast::pat_kind found in codegen!");
		return;
	}
}

func type string::string* compute_pat_match(
	type cgen_ctx* c, type cgen_data* cd,
	type string::string* base_exp, type ast::pat* p) {
	type string::string* res = gen_temp(c);
	type string::string* init_value = string::new_string("rt::init_bool(true)");
	type string::string* init_assign = gen_assign(c, res, init_value);
	util::maybe_report_ice(!vector::append(cd->main, init_assign$ as byte*) as bool,
		"Could not declare pattern assign computation result");

	switch (p->kind) {
	case ast::pat_kind::WILDCARD:
		break;
	case ast::pat_kind::IDENT: {
		type vector::vector* idents = p->which.nested;

		// TODO: This current just looks things up from the global scope; fix this.
		byte* dtc_lookup = tck::lookup_long_datatyp_constructor_ident(c->e, idents);
		if (dtc_lookup != NULL) {
			type ast::typ* t = dtc_lookup as type ast::typ** @;
			if (t->kind != ast::typ_kind::FUN) {
				type string::string* temp = gen_temp(c);
				type string::string* nullary_dt_lookup = gen_lookup_string(c, idents);
				type string::string* nullary_assign_string = gen_assign(c, temp, nullary_dt_lookup);

				type string::string* rhs = string::new_string("rt::eq(");
				rhs = string::add(rhs, temp);
				rhs = string::addc(rhs, "->which.fo->fun(scope, NULL as type rt::object*), ");
				rhs = string::add(rhs, base_exp);
				rhs = string::addc(rhs, ")");
				type string::string* check = string::new_string("");
				check = string::add(check, res);
				check = string::addc(check, " = ");
				check = string::add(check, rhs);
				check = string::addc(check, ";");
				add_all_strings(c, cd->main, [
					nullary_assign_string,
					check,
					NULL as type string::string*
				]);
			}
		}
	}
		break;
	case ast::pat_kind::ZERO_TUPLE:
	case ast::pat_kind::CONSTANT: {
		type string::string* con_cmp = string::new_string("rt::eq(");
		con_cmp = string::add(con_cmp, base_exp);
		con_cmp = string::addc(con_cmp, ", ");

		type string::string* con_value = string::new_string("rt::init_");
		type string::string* con_temp = gen_temp(c);

		if (p->kind == ast::pat_kind::CONSTANT) {
			type ast::constant* con = p->which.con;
			switch (con->kind) {
			case ast::constant_kind::INT:
				con_value = string::addc(con_value, "int");
				break;
			case ast::constant_kind::REAL:
				con_value = string::addc(con_value, "real");
				break;
			case ast::constant_kind::STRING:
				con_value = string::addc(con_value, "string");
				break;
			case ast::constant_kind::CHAR:
				con_value = string::addc(con_value, "char");
				break;
			case ast::constant_kind::BOOL:
				con_value = string::addc(con_value, "bool");
				break;
			default:
				util::report_ice("Unknown ast::constant_kind found in pattern match in codegen!");
				break;
			}
			con_value = string::addc(con_value, "(");
			con_value = string::addc(con_value, tck::extract_token_text(c->e, con->which));
			con_value = string::addc(con_value, ")");
		}
		else
			con_value = string::addc(con_value, "unit()");

		type string::string* con_assign = gen_assign(c, con_temp, con_value);
		util::maybe_report_ice(!vector::append(cd->main, con_assign$ as byte*) as bool,
			"Could not store assignment to constant for pattern matching in codegen!");

		con_cmp = string::add(con_cmp, con_temp);
		con_cmp = string::addc(con_cmp, ")");

		type string::string* res_assign = string::new_string("");
		res_assign = string::add(res_assign, res);
		res_assign = string::addc(res_assign, " = ");
		res_assign = string::add(res_assign, con_cmp);
		res_assign = string::addc(res_assign, ";");
		util::maybe_report_ice(!vector::append(cd->main, res_assign$ as byte*) as bool,
			"Could not add constant check in pattern matching in codegen!");
	}
		break;
	case ast::pat_kind::TUPLE: {
		type vector::vector* tup = p->which.nested;

		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::pat* curr = vector::at(tup, i) as type ast::pat** @;

			type string::string* curr_temp = gen_temp(c);
			type string::string* curr_exp = string::new_string("vector::at(");
			curr_exp = string::add(curr_exp, base_exp);
			curr_exp = string::addc(curr_exp, "->which.tup, ");
			curr_exp = string::addc(curr_exp, itoa(i));
			curr_exp = string::addc(curr_exp, ") as type rt::object** @");
			type string::string* curr_assign = gen_assign(c, curr_temp, curr_exp);
			util::maybe_report_ice(!vector::append(cd->main, curr_assign$ as byte*) as bool,
				"Could not add tuple element selection for pattern matching in codegen!");
			type string::string* curr_res = compute_pat_match(c, cd, curr_temp, curr);

			type string::string* res_check = string::new_string("");
			res_check = string::add(res_check, res);
			res_check = string::addc(res_check, " = rt::and_bool(");
			res_check = string::add(res_check, res);
			res_check = string::addc(res_check, ", ");
			res_check = string::add(res_check, curr_res);
			res_check = string::addc(res_check, ");");
			util::maybe_report_ice(!vector::append(cd->main, res_check$ as byte*) as bool,
				"Could not add tuple element pattern matching check in codegen!");
		}
	}
		break;
	case ast::pat_kind::TYP_ANNOT: {
		type ast::pat_typ_annot* pta = p->which.typ_annot;
		type string::string* curr_res = compute_pat_match(c, cd, base_exp, pta->p);

		type string::string* res_assign = string::new_string("");
		res_assign = string::add(res_assign, res);
		res_assign = string::addc(res_assign, " = ");
		res_assign = string::add(res_assign, curr_res);
		res_assign = string::addc(res_assign, ";");
		util::maybe_report_ice(!vector::append(cd->main, res_assign$ as byte*) as bool,
			"Could not add type annotation pattern matching check in codegen!");
	}
		break;
	case ast::pat_kind::CONSTRUCTION: {
		type ast::pat_construction* pc = p->which.pc;

		type vector::vector* idents = pc->idents;
		type lex::token* ident = vector::at(idents, vector::size(idents) - 1)
			as type lex::token** @;
		char* ident_text = tck::extract_token_text(c->e, ident);

		type string::string* assign = string::new_string("");
		assign = string::add(assign, res);
		assign = string::addc(assign, " = rt::init_bool(strcmp(");
		assign = string::add(assign, base_exp);
		assign = string::addc(assign, "->which.dto->name, \"");
		assign = string::addc(assign, ident_text);
		assign = string::addc(assign, "\") == 0);");
		add_all_strings(c, cd->main, [
			assign,
			NULL as type string::string*
		]);

		type string::string* if_header = string::new_string("if (");
		if_header = string::add(if_header, res);
		if_header = string::addc(if_header, "->which.po->which.b) {");
		add_all_strings(c, cd->main, [
			if_header,
			NULL as type string::string*
		]);

		unsigned int old_size = vector::size(cd->main);
		type string::string* new_base_exp = gen_temp(c);
		type string::string* rhs_new_base_exp = string::new_string("");
		rhs_new_base_exp = string::add(rhs_new_base_exp, base_exp);
		rhs_new_base_exp = string::addc(rhs_new_base_exp, "->which.dto->data");
		type string::string* new_base_exp_assign = gen_assign(c, new_base_exp, rhs_new_base_exp);
		add_all_strings(c, cd->main, [
			new_base_exp_assign,
			NULL as type string::string*
		]);

		type string::string* res2 = compute_pat_match(c, cd, new_base_exp, pc->p);
		type string::string* assign2 = string::new_string("");
		assign2 = string::add(assign2, res);
		assign2 = string::addc(assign2, " = rt::and_bool(");
		assign2 = string::add(assign2, res);
		assign2 = string::addc(assign2, ", ");
		assign2 = string::add(assign2, res2);
		assign2 = string::addc(assign2, ");");
		add_all_strings(c, cd->main, [
			assign2,
			NULL as type string::string*
		]);
		unsigned int new_size = vector::size(cd->main);
		for (unsigned int i = old_size; i < new_size; i++) {
			type string::string** elem = vector::at(cd->main, i) as type string::string**;
			elem@ = left_pad_string(c, 1, '\t', elem@);
		}

		type string::string* if_footer = string::new_string("}");
		add_all_strings(c, cd->main, [if_footer, NULL as type string::string*]);
	}
		break;
	// TODO
	default:
		util::report_ice("Unknown ast::pat_kind found for pattern matching in codegen!");
		break;
	}
	return res;
}

func type string::string* gen_lookup_string(type cgen_ctx* c,
	type vector::vector* idents) {
	type string::string* curr_mod_ctx;
	if (c->e->mod_ref == c->e->mod_ref->global_module)
		curr_mod_ctx = string::new_string("");
	else {
		curr_mod_ctx = tck::extract_module_name(c->e->mod_ref,
			compile::MOD_FILE_SEP);
	}

	type string::string* ret = string::new_string("rt::lookup_name(\"");
	ret = string::add(ret, curr_mod_ctx);
	ret = string::addc(ret, "\", scope, ");
	ret = string::addc(ret, itoa(vector::size(idents)));
	ret = string::addc(ret, ", ");
	for (unsigned int i = 0; i < vector::size(idents); i++) {
		type lex::token* ident = vector::at(idents, i) as type lex::token** @;
		if (ident == NULL as type lex::token*)
			ret = string::addc(ret, "NULL as char*");
		else {
			char* ident_text = tck::extract_token_text(c->e, ident);
			ret = string::addc(ret, "\"");
			ret = string::addc(ret, ident_text);
			ret = string::addc(ret, "\"");
		}

		if (i != vector::size(idents) - 1)
			ret = string::addc(ret, ", ");
	}
	ret = string::addc(ret, ")");

	return ret;
}

} } // namespace shadow::cgen
