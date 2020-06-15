import "parse/parse.hsp"

import <"stdx/vector">
import <"std/lib">
import <"std/io">
import <"std/string">

import "parse/util.hsp"
import "util/error.hsp"
import "lex/token.hsp"
import "ast/ast.hsp"

using std::io::printf;
using std::lib::NULL;
using std::lib::malloc;
using std::string::strncpy;
using namespace stdx::vector;

namespace shadow { namespace parse {

func[static] type ast::typ* parse_typ_helper1(type parser* p) {
	type ast::typ* t = malloc(sizeof{type ast::typ}) as type ast::typ*;

	type lex::token* ptok = peek(p);
	switch (ptok->tok_type) {
	case lex::tokens::CHAR:
		pop(p);
		t->kind = ast::typ_kind::CHAR;
		break;
	case lex::tokens::INT:
		pop(p);
		t->kind = ast::typ_kind::INT;
		break;
	case lex::tokens::STRING:
		pop(p);
		t->kind = ast::typ_kind::STRING;
		break;
	case lex::tokens::REAL:
		pop(p);
		t->kind = ast::typ_kind::REAL;
		break;
	case lex::tokens::BOOL:
		pop(p);
		t->kind = ast::typ_kind::BOOL;
		break;
	case lex::tokens::UNIT:
		pop(p);
		t->kind = ast::typ_kind::UNIT;
		break;
	case lex::tokens::BACKTICK: {
		pop(p);
		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::IDENT) {
			util::report_token_error(util::error_kind::ERR, p->buf,
				ptok, "Expected an identifier after a backtick (`) declaring "
				"a type variable.");
			return NULL as type ast::typ*;
		}
		pop(p);
		t->kind = ast::typ_kind::VAR;
		t->which.var = ptok;
	}
		break;
	case lex::tokens::IDENT: {
		type vector::vector* idents = parse_maybe_long_ident(p);
		type ast::typ_constructor* tc = malloc(sizeof{type ast::typ_constructor})
			as type ast::typ_constructor*;
		type vector::vector* typs = vector::new_vector(sizeof{type ast::typ*});

		tc->idents = idents;
		tc->typs = typs;
		t->kind = ast::typ_kind::CONSTRUCTOR;
		t->which.tc = tc;
	}
		break;
	case lex::tokens::OPEN_PAR: {
		unsigned int orig_pos = p->pos;
		type lex::token* orig = ptok;
		pop(p);

		type ast::typ* ret = parse_typ(p);

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::CLOSE_PAR) {
			p->pos = orig_pos;
			return NULL as type ast::typ*;
		}
		pop(p);
		return ret;
	}
		break;
	case lex::tokens::OPEN_BRACE: {
		pop(p);

		type vector::vector* rmems = vector::new_vector(sizeof{type ast::typ_row_mem*});
		bool first = true;
		while (true) {
			type ast::typ_row_mem* trm = malloc(sizeof{type ast::typ_row_mem})
				as type ast::typ_row_mem*;
			ptok = peek(p);
			if (first && ptok->tok_type == lex::tokens::CLOSE_BRACE) break;
			first = false;

			if (ptok->tok_type != lex::tokens::IDENT) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an identifier for a row member name.");
				return NULL as type ast::typ*;
			}
			pop(p);

			trm->ident = malloc(sizeof{char} * (ptok->end_pos - ptok->start_pos + 1)) as char*;
			strncpy(trm->ident, p->buf->text[ptok->start_pos]$, ptok->end_pos - ptok->start_pos);
			trm->ident[ptok->end_pos - ptok->start_pos] = 0;

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::COLON) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a colon between a row member name and row type.");
				return NULL as type ast::typ*;
			}
			pop(p);

			trm->t = parse_typ(p);
			if (trm->t == NULL as type ast::typ*) {
				return NULL as type ast::typ*;
			}
			
			util::maybe_report_ice(!vector::append(rmems, trm$ as byte*) as bool,
				"Could not add row member type to row type!");

			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::COMMA) pop(p);
			else break;
		} 

		if (ptok->tok_type != lex::tokens::CLOSE_BRACE) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a close brace to end a row type.");
			return NULL as type ast::typ*;
		}
		pop(p);

		t->kind = ast::typ_kind::ROW;
		t->which.rmems = rmems;
	}
		break;
	default:
		return NULL as type ast::typ*;
	}

	return t;
}

func[static] type ast::typ* parse_typ_helper2(type parser* p) {
	type lex::token* ptok = peek(p);
	type vector::vector* typs = vector::new_vector(sizeof{type ast::typ*});
	type ast::typ* default_ret = NULL as type ast::typ*;
	bool valid_list = false;
	unsigned int orig_pos = p->pos;
	if (ptok->tok_type == lex::tokens::OPEN_PAR) {
		pop(p);

		type ast::typ* t1 = parse_typ(p);
		if (t1 == NULL as type ast::typ*)
			return NULL as type ast::typ*;
		util::maybe_report_ice(!vector::append(typs, t1$ as byte*) as bool,
			"Could not append type to type constructor list!");

		ptok = peek(p);
		while (ptok->tok_type == lex::tokens::COMMA) {
			pop(p);

			type ast::typ* t = parse_typ(p);
			if (t == NULL as type ast::typ*) {
				valid_list = false;
				break;
			}

			util::maybe_report_ice(!vector::append(typs, t$ as byte*) as bool,
				"Could not append type to type constructor list!");
			ptok = peek(p);
		}

		if (ptok->tok_type == lex::tokens::CLOSE_PAR) {
			pop(p);
			if (vector::size(typs) > 1) valid_list = true;
			else valid_list = false;
		}
		else p->pos = orig_pos, valid_list = false;
	}
	if (!valid_list) {
		vector::clear(typs);
		p->pos = orig_pos;
		type ast::typ* t1 = parse_typ_helper1(p);
		if (t1 == NULL as type ast::typ*)
			return NULL as type ast::typ*;
		util::maybe_report_ice(!vector::append(typs, t1$ as byte*) as bool,
			"Could not append type to type constructor list!");
		default_ret = t1;
	}
	else default_ret = NULL as type ast::typ*;

	ptok = peek(p);
	if (ptok->tok_type != lex::tokens::IDENT)
		return default_ret;

	type vector::vector* ident = parse_maybe_long_ident(p);
	type ast::typ_constructor* tc = malloc(sizeof{type ast::typ_constructor})
		as type ast::typ_constructor*;
	tc->typs = typs;
	tc->idents = ident;

	type ast::typ* ret = malloc(sizeof{type ast::typ}) as type ast::typ*;
	ret->kind = ast::typ_kind::CONSTRUCTOR;
	ret->which.tc = tc;

	ptok = peek(p);
	while (ptok->tok_type == lex::tokens::IDENT) {
		type vector::vector* typs = vector::new_vector(sizeof{type ast::typ*});
		util::maybe_report_ice(!vector::append(typs, ret$ as byte*) as bool,
			"Could not append type to type constructor list!");

		type vector::vector* ident = parse_maybe_long_ident(p);
		type ast::typ_constructor* tc = malloc(sizeof{type ast::typ_constructor})
			as type ast::typ_constructor*;
		tc->typs = typs;
		tc->idents = ident;

		ret = malloc(sizeof{type ast::typ}) as type ast::typ*;
		ret->kind = ast::typ_kind::CONSTRUCTOR;
		ret->which.tc = tc;
		ptok = peek(p);
	}

	return ret;
}

func[static] type ast::typ* parse_typ_helper3(type parser* p) {
	type lex::token* orig_tok = peek(p);
	type ast::typ* t1 = parse_typ_helper2(p);
	type lex::token* ptok = peek(p);
	switch (ptok->tok_type) {
	case lex::tokens::STAR: {
		if (t1 == NULL as type ast::typ*) {
			util::report_token_error(util::error_kind::ERR, p->buf, orig_tok,
				"Invalid type as part of a tuple type starting here.");
			return NULL as type ast::typ*;
		}
		type vector::vector* tup = vector::new_vector(sizeof{type ast::typ*});
		util::maybe_report_ice(!vector::append(tup, t1$ as byte*) as bool,
			"Could not insert type into a tuple type!");

		while (ptok->tok_type == lex::tokens::STAR) {
			pop(p);
			
			type ast::typ* t = parse_typ_helper2(p);
			if (t == NULL as type ast::typ*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a valid type as part of a type tuple starting here.");
				return NULL as type ast::typ*;
			}

			util::maybe_report_ice(!vector::append(tup, t$ as byte*) as bool,
				"Could not insert type into a tuple type!");
			ptok = peek(p);
		}

		type ast::typ* ret = malloc(sizeof{type ast::typ}) as type ast::typ*;
		ret->kind = ast::typ_kind::TUP;
		ret->which.tup = tup;
		return ret;
	}
		break;
	}
	return t1;
}

func type ast::typ* parse_typ(type parser* p) {
	type lex::token* orig_tok = peek(p);
	type ast::typ* t1 = parse_typ_helper3(p);
	type lex::token* ptok = peek(p);
	switch (ptok->tok_type) {
	case lex::tokens::FUN_ARROW: {
		if (t1 == NULL as type ast::typ*) {
			util::report_token_error(util::error_kind::ERR, p->buf, orig_tok,
				"Invalid function parameter type starting here.");
			return NULL as type ast::typ*;
		}
		pop(p);
		type ast::typ* t2 = parse_typ(p);
		if (t2 == NULL as type ast::typ*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid return type for a function type from here.");
			return NULL as type ast::typ*;
		}

		type ast::typ_fun* tf = malloc(sizeof{type ast::typ_fun})
			as type ast::typ_fun*;
		tf->arg = t1;
		tf->ret = t2;

		type ast::typ* t = malloc(sizeof{type ast::typ}) as type ast::typ*;
		t->kind = ast::typ_kind::FUN;
		t->which.tf = tf;
		return t;
	}
		break;
	}
	return t1;
}

} } // namespace shadow::parse
