import "parse/parse.hsp"

import <"std/io">
import <"stdx/vector">
import <"std/lib">
import <"std/string">

import "lex/token.hsp"
import "util/error.hsp"
import "ast/ast.hsp"
import "parse/util.hsp"

using std::io::printf;
using std::lib::malloc;
using std::lib::NULL;
using std::string::strncpy;
using namespace stdx::vector;

namespace shadow { namespace parse {

func type ast::pat* parse_pat_atomic(type parser* p) {
	type ast::pat* pat = malloc(sizeof{type ast::pat})
		as type ast::pat*;

	type lex::token* ptok = peek(p);
	switch (ptok->tok_type) {
	case lex::tokens::INT_LITERAL:
	case lex::tokens::STRING_LITERAL:
	case lex::tokens::REAL_LITERAL:
	case lex::tokens::TRUE:
	case lex::tokens::FALSE:
	case lex::tokens::CHAR_LITERAL: {
		pop(p);
		type ast::constant* c = malloc(sizeof{type ast::constant})
			as type ast::constant*;
		switch (ptok->tok_type) {
		case lex::tokens::INT_LITERAL: c->kind = ast::constant_kind::INT; break;
		case lex::tokens::STRING_LITERAL: c->kind = ast::constant_kind::STRING; break;
		case lex::tokens::REAL_LITERAL: c->kind = ast::constant_kind::REAL; break;
		case lex::tokens::TRUE: c->kind = ast::constant_kind::BOOL; break;
		case lex::tokens::FALSE: c->kind = ast::constant_kind::BOOL; break;
		case lex::tokens::CHAR_LITERAL: c->kind = ast::constant_kind::CHAR; break;
		}

		pat->kind = ast::pat_kind::CONSTANT;
		pat->which.con = c;
		return pat;
	}
		break;
	case lex::tokens::UNDERSCORE:
		pop(p);
		pat->kind = ast::pat_kind::WILDCARD;
		break;
	case lex::tokens::IDENT: {
		type vector::vector* ident = parse_maybe_long_ident(p);
		pat->kind = ast::pat_kind::IDENT;
		pat->which.nested = ident;
	}
		break;
	case lex::tokens::OPEN_PAR: {
		type lex::token* orig = ptok;
		pop(p);

		ptok = peek(p);
		if (ptok->tok_type == lex::tokens::CLOSE_PAR) {
			pop(p);
			pat->kind = ast::pat_kind::ZERO_TUPLE;
			return pat;
		}

		type ast::pat* p1 = parse_pat(p);
		ptok = peek(p);

		if (ptok->tok_type == lex::tokens::CLOSE_PAR) {
			pop(p);
			return p1;
		}

		type ast::pat* tup_pat = malloc(sizeof{type ast::pat}) as type ast::pat*;
		tup_pat->kind = ast::pat_kind::TUPLE;
		tup_pat->which.nested = vector::new_vector(sizeof{type ast::pat*});
		util::maybe_report_ice(!vector::append(tup_pat->which.nested, p1$ as byte*) as bool,
			"Could not insert a pattern into a tuple-pattern list!");
		
		while (ptok->tok_type == lex::tokens::COMMA) {
			type lex::token* comma_tok = ptok;
			pop(p);
			
			type ast::pat* pn = parse_pat(p);
			if (pn == NULL as type ast::pat*) {
				util::report_token_error(util::error_kind::ERR, p->buf, comma_tok,
					"Expected a valid pattern starting here in a tuple pattern.");
				return NULL as type ast::pat*;
			}

			util::maybe_report_ice(!vector::append(tup_pat->which.nested, pn$ as byte*) as bool,
				"Could not insert a pattern into a tuple-pattern list!");
			ptok = peek(p);
		}

		if (ptok->tok_type != lex::tokens::CLOSE_PAR) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a close parenthesis ()) here to finish a tuple pattern.");
			util::report_token_error(util::error_kind::NOTE, p->buf, orig,
				"Need one to match this open parenthesis ()) here.");
			return NULL as type ast::pat*;
		}
		pop(p);

		return tup_pat;
	}
		break;
	case lex::tokens::OPEN_BRACE: {
		pop(p);
	
		type ast::pat* row_pat = malloc(sizeof{type ast::pat}) as type ast::pat*;
		row_pat->kind = ast::pat_kind::ROW;
		row_pat->which.rmems = vector::new_vector(sizeof{type ast::pat_row_mem*});
		
		bool first = true;
		while (true) {
			ptok = peek(p);

			if (first && ptok->tok_type == lex::tokens::CLOSE_BRACE) break;
			first = false;

			if (ptok->tok_type != lex::tokens::IDENT) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an identifier for a row label pattern");
				return NULL as type ast::pat*;
			}
			pop(p);

			type ast::pat_row_mem* ptm = malloc(sizeof{type ast::pat_row_mem}) as type ast::pat_row_mem*;
			ptm->sep = NULL as type lex::token*;
			ptm->t = NULL as type ast::typ*;
			ptm->p = NULL as type ast::pat*;

			ptm->ident = malloc(sizeof{char} * (ptok->end_pos - ptok->start_pos + 1)) as char*;
			strncpy(ptm->ident, p->buf->text[ptok->start_pos]$, ptok->end_pos - ptok->start_pos);
			ptm->ident[ptok->end_pos - ptok->start_pos] = 0;
			ptm->ident_tok = ptok;

			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::COLON) {
				pop(p);
				
				type ast::typ* pat_typ = parse_typ(p);
				if (pat_typ == NULL as type ast::typ*) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Expected a valid type as part of a row member pattern after a colon (':')!");
					return NULL as type ast::pat*;
				}
				ptm->t = pat_typ;

				ptok = peek(p);
				if (ptok->tok_type == lex::tokens::AS) {
					pop(p);
					ptm->sep = ptok;

					ptm->p = parse_pat(p);
					if (ptm->p == NULL as type ast::pat*) {
						util::report_token_error(util::error_kind::ERR, p->buf, ptok,
							"Expected a valid pattern as part of a row member pattern after the 'as'!");
						return NULL as type ast::pat*;
					}
				}
			}
			else if (ptok->tok_type == lex::tokens::AS) {
				pop(p);
				ptm->sep = ptok;

				ptm->p = parse_pat(p);
				if (ptm->p == NULL as type ast::pat*) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Expected a valid pattern as part of a row member pattern after the 'as'!");
					return NULL as type ast::pat*;
				}
			}
			else if (ptok->tok_type == lex::tokens::EQUALS) {
				pop(p);
				ptm->sep = ptok;

				type ast::pat* mem_pat = parse_pat(p);
				if (mem_pat == NULL as type ast::pat*) {
					util::report_token_error(util::error_kind::ERR, p->buf, ptok,
						"Expected a valid pattern to match a row member after the '='.");
					return NULL as type ast::pat*;
				}
				ptm->p = mem_pat;
			}

			util::maybe_report_ice(!vector::append(row_pat->which.rmems, ptm$ as byte*) as bool,
				"Could not insert row member pattern into row pattern list!");

			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::COMMA) pop(p);
			else break;
		}

		if (ptok->tok_type != lex::tokens::CLOSE_BRACE) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a closing brace ('}') to end a row pattern.");
			return NULL as type ast::pat*;
		}
		pop(p);

		return row_pat;
	}
		break;
	default:
		return NULL as type ast::pat*;
	}

	return pat;
}

func[static] type ast::pat* parse_pat_helper1(type parser* p) {
	type lex::token* ptok = peek(p);
	if (ptok->tok_type == lex::tokens::IDENT) {
		unsigned int orig_pos = p->pos;
		type vector::vector* idents = parse_maybe_long_ident(p);
		
		type ast::pat* ap = parse_pat_atomic(p);
		if (ap == NULL as type ast::pat*) p->pos = orig_pos;
		else {
			type ast::pat_construction* pc = malloc(sizeof{type ast::pat_construction})
				as type ast::pat_construction*;
			pc->idents = idents;
			pc->p = ap;

			type ast::pat* pat = malloc(sizeof{type ast::pat}) as type ast::pat*;
			pat->kind = ast::pat_kind::CONSTRUCTION;
			pat->which.pc = pc;
			return pat;
		}
	}
	return parse_pat_atomic(p);
}

func type ast::pat* parse_pat_helper2(type parser* p) {
	type ast::pat* p1 = parse_pat_helper1(p);
	type lex::token* ptok = peek(p);
	switch (ptok->tok_type) {
	case lex::tokens::COLON: {
		pop(p);
		type ast::typ* t = parse_typ(p);
		if (t == NULL as type ast::typ*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid type for a pattern's type annotation starting here.");
			return NULL as type ast::pat*;
		}

		type ast::pat_typ_annot* pta = malloc(sizeof{type ast::pat_typ_annot})
			as type ast::pat_typ_annot*;
		pta->p = p1;
		pta->t = t;
		
		type ast::pat* pat = malloc(sizeof{type ast::pat}) as type ast::pat*;
		pat->kind = ast::pat_kind::TYP_ANNOT;
		pat->which.typ_annot = pta;
		return pat;
	}
		break;
	}
	return p1;
}

func type ast::pat* parse_pat(type parser* p) {
	unsigned int orig_pos = p->pos;
	type lex::token* ptok = peek(p);
	if (ptok->tok_type == lex::tokens::IDENT) {
		type lex::token* ident = ptok;
		pop(p);

		type ast::typ* layered_typ = NULL as type ast::typ*;

		ptok = peek(p);
		if (ptok->tok_type == lex::tokens::COLON) {
			pop(p);
			layered_typ = parse_typ(p);
			if (layered_typ == NULL as type ast::typ*) {
				p->pos = orig_pos;
				return parse_pat_helper2(p);
			}
		}

		ptok = peek(p);
		if (ptok->tok_type == lex::tokens::AS) {
			pop(p);
			
			type ast::pat* nested = parse_pat(p);
			if (nested == NULL as type ast::pat*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a valid pattern after the 'as' of a layered pattern!");
				return NULL as type ast::pat*;
			}

			type ast::pat* ret = malloc(sizeof{type ast::pat}) as type ast::pat*;
			ret->kind = ast::pat_kind::LAYERED;
			ret->which.layered = malloc(sizeof{type ast::pat_layered}) as type ast::pat_layered*;
			ret->which.layered->ident = ident;
			ret->which.layered->t = layered_typ;
			ret->which.layered->p = nested;
			return ret;
		}
		else {
			p->pos = orig_pos;
			return parse_pat_helper2(p);
		}
	}
	return parse_pat_helper2(p);
}

} } // namespace shadow::parse
