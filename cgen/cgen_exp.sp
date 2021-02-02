import "cgen/cgen.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/string">
import <"stdx/vector">

import "tck/util.hsp"
import "cgen/util.hsp"
import "util/error.hsp"
import "ast/ast.hsp"
import "cgen/cgen_exp.hsp"

using std::lib::NULL;
using std::lib::malloc;
using std::io::printf;
using namespace stdx::string;
using namespace stdx::vector;

namespace shadow { namespace cgen {

func void cgen_exp(type cgen_ctx* c, type cgen_data* cd, type ast::exp* e) {
	switch (e->kind) {
	case ast::exp_kind::CONSTANT: {
		type ast::constant* ec = e->which.c;
		
		cd->result = gen_temp(c);

		type string::string* const_string = string::new_string("rt::init_");

		char* tok_text = tck::extract_token_text(c->e, ec->which);
		switch (ec->kind) {
		case ast::constant_kind::INT: 
			const_string = string::addc(const_string, "int");
			break;
		case ast::constant_kind::REAL: 
			const_string = string::addc(const_string, "real");
			break;
		case ast::constant_kind::CHAR: 
			const_string = string::addc(const_string, "char");
			break;
		case ast::constant_kind::STRING:
			const_string = string::addc(const_string, "string");
			break;
		case ast::constant_kind::BOOL:
			const_string = string::addc(const_string, "bool");
			break;
		default:
			util::report_ice("Unknown ast::constant_kind found during codegen!");
			return;
		}
		const_string = string::addc(const_string, "(");
		const_string = string::addc(const_string, tok_text);
		const_string = string::addc(const_string, ")");
		const_string = gen_assign(c, cd->result, const_string);

		util::maybe_report_ice(!vector::append(cd->main, const_string$ as byte*) as bool,
			"Could not add generated code for a constant expression!");
	}
		break;
	case ast::exp_kind::TUPLE: {
		type vector::vector* tup = e->which.tup;
		type string::string* curr_temp = gen_temp(c);

		type string::string* tup_args = string::new_string("");
		for (unsigned int i = 0; i < vector::size(tup); i++) {
			type ast::exp* ec = vector::at(tup, i) as type ast::exp** @;
			cgen_exp(c, cd, ec);

			type string::string* copy_string = gen_temp(c);
			type string::string* assign_string = gen_copy(c, copy_string, cd->result);
			util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
				"Could not add generated code for a tuple-element expression!");

			tup_args = string::add(tup_args, copy_string);
			if (i != vector::size(tup) - 1) {
				tup_args = string::addc(tup_args, ", ");
			}
		}

		type string::string* tup_assign = string::new_string("rt::init_tup(");
		tup_assign = string::addc(tup_assign, itoa(vector::size(tup)));
		tup_assign = string::addc(tup_assign, ", ");
		tup_assign = string::add(tup_assign, tup_args);
		tup_assign = string::addc(tup_assign, ")");

		tup_assign = gen_assign(c, curr_temp, tup_assign);
		util::maybe_report_ice(!vector::append(cd->main, tup_assign$ as byte*) as bool,
			"Could not add generated code for a tuple expression!");
		cd->result = curr_temp;
	}
		break;
	case ast::exp_kind::IDENT: {
		type vector::vector* idents = e->which.ident;

		// TODO: This current just looks things up from the global scope; fix this.
		byte* dtc_lookup = tck::lookup_long_datatyp_constructor_ident(c->e, idents);

		cd->result = gen_temp(c);
		type string::string* helper_string = gen_lookup_string(c, idents);
		type string::string* assign_string = gen_copy(c, cd->result, helper_string);
		util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
			"Could not add generated code for an identifier symbol expression!");

		if (dtc_lookup != NULL) {
			type ast::typ* t = dtc_lookup as type ast::typ** @;
			if (t->kind != ast::typ_kind::FUN) {
				type string::string* rhs = cd->result;
				cd->result = gen_temp(c);
				type string::string* rhs_full = string::new_string("");
				rhs_full = string::add(rhs_full, rhs);
				rhs_full = string::addc(rhs_full, "->which.fo->fun(scope, NULL as type rt::object*)");
				type string::string* final_assign_string = gen_assign(c, cd->result, rhs_full);
				util::maybe_report_ice(!vector::append(cd->main, final_assign_string$ as byte*) as bool,
					"Could not add generated code for a nullary datatype constructor in codegen!");
			}
		}
	}
		break;
	case ast::exp_kind::ZERO_TUPLE: {
		cd->result = gen_temp(c);
		type string::string* zt = string::new_string("rt::init_unit()");

		type string::string* assign_string = gen_assign(c, cd->result, zt);
		util::maybe_report_ice(!vector::append(cd->main, assign_string$ as byte*) as bool,
			"Could not add generated code for a unit expression!");
	}
		break;
	case ast::exp_kind::BINARY: 
		return cgen_exp_binary(c, cd, e->which.bin);
	case ast::exp_kind::UNARY:
		return cgen_exp_unary(c, cd, e->which.un);
	case ast::exp_kind::CMP: 
		return cgen_exp_cmp(c, cd, e->which.cmp);
	case ast::exp_kind::SEQ: {
		for (unsigned int i = 0; i < vector::size(e->which.seq); i++) {
			type ast::exp* curr = vector::at(e->which.seq, i) as type ast::exp** @;
			cgen_exp(c, cd, curr);
		}
	}
		break;
	case ast::exp_kind::TYP_ANNOT: {
		type ast::exp_typ_annot* annot = e->which.typ_annot;
		cgen_exp(c, cd, annot->e);
	}
		break;
	case ast::exp_kind::FN: 
		return cgen_exp_fun(c, cd, e->which.anon_fun);
	case ast::exp_kind::APP: 
		return cgen_exp_app(c, cd, e->which.app);
	case ast::exp_kind::IF:
		return cgen_exp_if(c, cd, e->which.iexp);
	case ast::exp_kind::LET:
		return cgen_exp_let(c, cd, e->which.lexp);
	case ast::exp_kind::CASE:
		return cgen_exp_case(c, cd, e->which.cexp);
	// TODO
	default:
		util::report_ice("Unknown ast::exp_kind found in codegen!");
		break;
	}

	return;
}

} } // namespace shadow::cgen
