import "cgen/util.hsp"

import <"std/lib">
import <"stdx/vector">
import <"stdx/string">

import "tck/util.hsp"
import "util/error.hsp"
import "cgen/cgen.hsp"

using std::lib::calloc;
using std::lib::NULL;
using namespace stdx::vector;
using namespace stdx::string;

namespace shadow { namespace cgen {

func type vector::vector* collect_top_level_pat_idents(
	type cgen_ctx* c, type ast::pat* p) {

	type vector::vector* ret = vector::new_vector(sizeof{type string::string*});
	switch (p->kind) {
	case ast::pat_kind::WILDCARD:
		break;
	case ast::pat_kind::IDENT: {
		type vector::vector* idents = p->which.nested;

		byte* dtc_lookup = tck::lookup_long_datatyp_constructor_ident(c->e, idents);
		if (dtc_lookup != NULL)
			return ret;

		util::maybe_report_ice(vector::size(idents) == 1,
			"Did not expect a nested identifier in codegen!");

		type lex::token* ident = vector::at(idents, 0)
			as type lex::token** @;
		type string::string* ident_string = string::new_string(
			tck::extract_token_text(c->e, ident));
		util::maybe_report_ice(!vector::append(ret, ident_string$ as byte*) as bool,
			"Could not collect top-level identifier pattern!");
	}
		break;
	case ast::pat_kind::TUPLE: {
		type vector::vector* tup = p->which.nested;
		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::pat* curr = vector::at(tup, i) as type ast::pat** @;
			
			type vector::vector* sub = collect_top_level_pat_idents(c, curr);
			for (unsigned int j = 0; j < vector::size(sub); j++) {
				type string::string* ident_string = vector::at(sub, j) as type string::string** @;
				util::maybe_report_ice(!vector::append(ret, ident_string$ as byte*) as bool,
					"Could not collect tuple sub-pattern identifiers!");
			}
		}
	}
		break;
	// TODO
	default:
		util::report_ice("Unknown ast::pat_kind found in codegen!");
		return NULL as type vector::vector*;
	}
	return ret;
}

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
	case ast::pat_kind::IDENT: {
		type vector::vector* idents = p->which.nested;

		// TODO: Remove this limitation!
		byte* dtc_lookup = tck::lookup_long_datatyp_constructor_ident(c->e, idents);
		util::maybe_report_ice(dtc_lookup == NULL, "Found a non-symbol pattern identifier here!");

		util::maybe_report_ice(vector::size(idents) == 1,
			"Did not expect a nested identifier in a 'val' declaration's codegen!");

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
	case ast::pat_kind::WILDCARD:
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
	// TODO
	default:
		util::report_ice("Unknown ast::pat_kind found in codegen!");
		return;
	}
}

} } // namespace shadow::cgen
