import "parse/parse.hsp"

import <"stdx/vector">
import <"std/io">
import <"std/lib">
import <"std/string">

import "util/error.hsp"
import "parse/util.hsp"
import "lex/token.hsp"
import "ast/ast.hsp"

using std::string::strncpy;
using std::lib::NULL;
using std::lib::malloc;
using std::io::printf;
using namespace stdx::vector;

namespace shadow { namespace parse {

func[static] type ast::exp* parse_exp_helper1(type parser* p) {
	type ast::exp* e = malloc(sizeof{type ast::exp})
		as type ast::exp*;
	type lex::token* ptok = peek(p);
	switch (ptok->tok_type) {
	case lex::tokens::CHAR_LITERAL:
	case lex::tokens::INT_LITERAL:
	case lex::tokens::REAL_LITERAL:
	case lex::tokens::STRING_LITERAL:
	case lex::tokens::TRUE:
	case lex::tokens::FALSE: {
		pop(p);
		type ast::constant* c = malloc(sizeof{type ast::constant})
			as type ast::constant*;

		c->which = ptok;
		switch (ptok->tok_type) {
		case lex::tokens::CHAR_LITERAL:
			c->kind = ast::constant_kind::CHAR;
			break;
		case lex::tokens::INT_LITERAL:
			c->kind = ast::constant_kind::INT;
			break;
		case lex::tokens::REAL_LITERAL:
			c->kind = ast::constant_kind::REAL;
			break;
		case lex::tokens::STRING_LITERAL:
			c->kind = ast::constant_kind::STRING;
			break;
		case lex::tokens::FALSE:
		case lex::tokens::TRUE:
			c->kind = ast::constant_kind::BOOL;
			break;
		}

		e->kind = ast::exp_kind::CONSTANT;
		e->which.c = c;
	}
		break;
	case lex::tokens::LET: {
		pop(p);

		type ast::decl* d = parse_decl(p);
		if (d == NULL as type ast::decl*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid declaration as part of a let expression.");
			return NULL as type ast::exp*;
		}

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::IN) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected an 'in' after the declaration of a let expression.");
			return NULL as type ast::exp*;
		}
		pop(p);

		type vector::vector* exps = vector::new_vector(sizeof{type ast::exp*});
		type ast::exp* e = parse_exp(p);
		if (e == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid expression after the 'in' of a let expression.");
			return NULL as type ast::exp*;
		}

		util::maybe_report_ice(!vector::append(exps, e$ as byte*) as bool,
			"Could not add the initial expression of a let expression to the expression list!");

		ptok = peek(p);
		while (ptok->tok_type == lex::tokens::SEMICOLON) {
			pop(p);

			type ast::exp* e = parse_exp(p);
			if (e == NULL as type ast::exp*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a valid expression as part of a lex expression.");
				return NULL as type ast::exp*;
			}

			util::maybe_report_ice(!vector::append(exps, e$ as byte*) as bool,
				"Could not add an expression inside of a let expression to the expression list!");
			ptok = peek(p);
		}

		if (ptok->tok_type != lex::tokens::END) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected an 'end' to end a let expression.");
			return NULL as type ast::exp*;
		}
		pop(p);

		type ast::let_exp* le = malloc(sizeof{type ast::let_exp}) as type ast::let_exp*;
		le->dec = d;
		le->exps = exps;

		type ast::exp* ret = malloc(sizeof{type ast::exp}) as type ast::exp*;
		ret->kind = ast::exp_kind::LET;
		ret->which.lexp = le;
		return ret;
	}
		break;
	case lex::tokens::OPEN_PAR: {
		type lex::token* orig_tok = ptok;
		pop(p);

		ptok = peek(p);
		if (ptok->tok_type == lex::tokens::CLOSE_PAR) {
			pop(p);
			e->kind = ast::exp_kind::ZERO_TUPLE;
			return e;
		}

		type ast::exp* e = parse_exp(p);
		if (e == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, orig_tok,
				"Invalid expression starting after this open parenthesis (().");
			return NULL as type ast::exp*;
		}
		
		ptok = peek(p);
		if (ptok->tok_type == lex::tokens::CLOSE_PAR) {
			pop(p);
			return e;
		}

		type vector::vector* exps = vector::new_vector(sizeof{type ast::exp*});
		util::maybe_report_ice(!vector::append(exps, e$ as byte*) as bool,
			"Could not insert initial expression into tuple!");
		ptok = peek(p);
		unsigned int initial_kind = ptok->tok_type;
		while (ptok->tok_type == lex::tokens::COMMA
			|| ptok->tok_type == lex::tokens::SEMICOLON) {
			if (ptok->tok_type != initial_kind) break;
			pop(p);
			
			e = parse_exp(p);
			if (e == NULL as type ast::exp*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Invalid expression in a tuple after here.");
				return NULL as type ast::exp*;
			}

			util::maybe_report_ice(!vector::append(exps, e$ as byte*) as bool,
				"Could not insert expression into tuple!");
			ptok = peek(p);
		}

		if (ptok->tok_type != lex::tokens::CLOSE_PAR) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a close parenthesis ()) here to finish an expression.");
			util::report_token_error(util::error_kind::NOTE, p->buf, orig_tok,
				"Need one to match this open parenthesis (() here.");
			return NULL as type ast::exp*;
		}
		pop(p);

		type ast::exp* ret = malloc(sizeof{type ast::exp}) as type ast::exp*;
		switch (initial_kind) {
		case lex::tokens::COMMA:
			ret->kind = ast::exp_kind::TUPLE;
			ret->which.tup = exps;
			break;
		case lex::tokens::SEMICOLON:
			ret->kind = ast::exp_kind::SEQ;
			ret->which.seq = exps;
			break;
		}
		return ret;
	}
		break;
	case lex::tokens::OPEN_BRACE: {
		pop(p);

		e->kind = ast::exp_kind::ROW;
		e->which.rmems = vector::new_vector(sizeof{type ast::row_mem_exp*});

		bool first = true;
		while (true) {
			ptok = peek(p);
			if (first && ptok->tok_type == lex::tokens::CLOSE_BRACE) break;
			first = false;

			if (ptok->tok_type != lex::tokens::IDENT) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an identifier to start a row member expression!");
				return NULL as type ast::exp*;
			}
			pop(p);

			type ast::row_mem_exp* rme = malloc(sizeof{type ast::row_mem_exp}) as type ast::row_mem_exp*;
			rme->ident_tok = ptok;
			rme->ident = malloc(sizeof{char} * (ptok->end_pos - ptok->start_pos + 1)) as char*;
			strncpy(rme->ident, p->buf->text[ptok->start_pos]$, ptok->end_pos - ptok->start_pos);
			rme->ident[ptok->end_pos - ptok->start_pos] = 0;

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::EQUALS) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected an equals ('=') to initialize a row member.");
				return NULL as type ast::exp*;
			}
			pop(p);

			rme->e = parse_exp(p);
			if (rme->e == NULL as type ast::exp*) {
				util::report_token_error(util::error_kind::ERR, p->buf, ptok,
					"Expected a valid expression to initialize a row member after an equals ('=')!");
				return NULL as type ast::exp*;
			}

			util::maybe_report_ice(!vector::append(e->which.rmems, rme$ as byte*) as bool,
				"Could not insert row member as part of row expression!");

			ptok = peek(p);
			if (ptok->tok_type == lex::tokens::COMMA) pop(p);
			else break;
		}

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::CLOSE_BRACE) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a close brace ('}') to end a row expression.");
			return NULL as type ast::exp*;
		}
		pop(p);
	}
		break;
	case lex::tokens::DOT:
	case lex::tokens::IDENT: {
		type vector::vector* ident = parse_maybe_long_ident(p);
		e->kind = ast::exp_kind::IDENT;
		e->which.ident = ident;
		return e;
	}
		break;
	default:
		return NULL as type ast::exp*;
	}
	return e;
}

func[static] type ast::exp* parse_exp_helper2(type parser* p) {
	type ast::exp* f = parse_exp_helper1(p);
	if (f == NULL as type ast::exp*) return f;
	while (true) {
		unsigned int orig_pos = p->pos;
		type ast::exp* a = parse_exp_helper1(p);
		if (a == NULL as type ast::exp*) {
			p->pos = orig_pos;
			return f;
		}
		type ast::exp* ftemp = malloc(sizeof{type ast::exp}) as type ast::exp*;
		ftemp->kind = ast::exp_kind::APP;

		type ast::exp_app* fapp = malloc(sizeof{type ast::exp_app}) as type ast::exp_app*;
		fapp->f = f;
		fapp->a = a;
		ftemp->which.app = fapp;
		f = ftemp;
	}
	return f;
}

func[static] type ast::exp* parse_exp_unary(type parser* p) {
	type lex::token* ptok = peek(p);
	if (ptok->tok_type == lex::tokens::EXCLAMATION_MARK
		|| ptok->tok_type == lex::tokens::TILDE
		|| ptok->tok_type == lex::tokens::PLUS
		|| ptok->tok_type == lex::tokens::PLUS_DOT
		|| ptok->tok_type == lex::tokens::MINUS
		|| ptok->tok_type == lex::tokens::MINUS_DOT) {
		pop(p);

		type ast::exp_unary* eu = malloc(sizeof{type ast::exp_unary})
			as type ast::exp_unary*;
		eu->e = parse_exp_unary(p);
		switch (ptok->tok_type) {
		case lex::tokens::EXCLAMATION_MARK: eu->kind = ast::exp_unary_kind::NOT; break;
		case lex::tokens::TILDE: eu->kind = ast::exp_unary_kind::CMPL; break;
		case lex::tokens::PLUS: eu->kind = ast::exp_unary_kind::PLUS; break;
		case lex::tokens::PLUS_DOT: eu->kind = ast::exp_unary_kind::PLUS_REAL; break;
		case lex::tokens::MINUS: eu->kind = ast::exp_unary_kind::MINUS; break;
		case lex::tokens::MINUS_DOT: eu->kind = ast::exp_unary_kind::MINUS_REAL; break;
		}

		type ast::exp* e = malloc(sizeof{type ast::exp}) as type ast::exp*;
		e->kind = ast::exp_kind::UNARY;
		e->which.un = eu;
		return e;
	}
	return parse_exp_helper2(p);
}

func[static] type ast::exp* parse_left_associative_binary(type parser* p,
	fn type ast::exp*(type parser*) pfunc, unsigned int** kind_map,
	unsigned int num_kinds) {
	type ast::exp* lhs = pfunc(p);
	if (lhs == NULL as type ast::exp*) return lhs;

	type lex::token* ptok = peek(p);
	while (true) {
		bool hit = false;
		unsigned int i = 0;
		for (; i < num_kinds; i++) {
			unsigned int from = kind_map[i][0];
			if (from == ptok->tok_type) {
				hit = true;
				break;
			}
		}

		if (!hit) break;
		pop(p);
		type ast::exp_binary* b = malloc(sizeof{type ast::exp_binary}) as type ast::exp_binary*;
		b->lhs = lhs;

		type ast::exp* rhs = pfunc(p);
		if (rhs == NULL as type ast::exp*) return rhs;
		b->rhs = rhs;
		b->kind = kind_map[i][1];

		type ast::exp* temp = malloc(sizeof{type ast::exp}) as type ast::exp*;
		temp->kind = ast::exp_kind::BINARY;
		temp->which.bin = b;
		lhs = temp;

		ptok = peek(p);
	}

	return lhs;
}

func[static] type ast::exp* parse_multiplicative(type parser* p) {
	return parse_left_associative_binary(p, parse_exp_unary, 
		[
			[lex::tokens::STAR, ast::exp_binary_kind::MULT],
			[lex::tokens::STAR_DOT, ast::exp_binary_kind::MULT_REAL],
			[lex::tokens::SLASH, ast::exp_binary_kind::DIV],
			[lex::tokens::SLASH_DOT, ast::exp_binary_kind::DIV_REAL],
			[lex::tokens::PERCENT, ast::exp_binary_kind::MOD]
		], 5);
}

func[static] type ast::exp* parse_additive(type parser* p) {
	return parse_left_associative_binary(p, parse_multiplicative,
		[
			[lex::tokens::PLUS, ast::exp_binary_kind::PLUS],
			[lex::tokens::PLUS_DOT, ast::exp_binary_kind::PLUS_REAL],
			[lex::tokens::MINUS, ast::exp_binary_kind::MINUS],
			[lex::tokens::MINUS_DOT, ast::exp_binary_kind::MINUS_REAL],
			[lex::tokens::PLUS_PLUS, ast::exp_binary_kind::STRING_CONCAT]
		], 5);
}

func[static] type ast::exp* parse_shift(type parser* p) {
	return parse_left_associative_binary(p, parse_additive,
		[
			[lex::tokens::SHL, ast::exp_binary_kind::SHL],
			[lex::tokens::SHR, ast::exp_binary_kind::SHR]
		], 2);
}

func[static] type ast::exp* parse_left_associative_chain(type parser* p,
	fn type ast::exp*(type parser*) pfunc,
	unsigned int** kind_map, unsigned int num_kinds) {
	type vector::vector* exps = vector::new_vector(sizeof{type ast::exp*});
	type vector::vector* cmps = vector::new_vector(sizeof{unsigned int});
	type ast::exp* lhs = pfunc(p);
	if (lhs == NULL as type ast::exp*) return lhs;
	util::maybe_report_ice(!vector::append(exps, lhs$ as byte*) as bool,
		"Could not insert initial expression of potential comparison!");

	type lex::token* ptok = peek(p);
	while (true) {
		bool hit = false;
		unsigned int i = 0;
		for (; i < num_kinds; i++) {
			if (kind_map[i][0] == ptok->tok_type) {
				hit = true;
				break;
			}
		}

		if (!hit) break;
		pop(p);
		unsigned int k = kind_map[i][1];
		
		type ast::exp* rhs = pfunc(p);
		if (rhs == NULL as type ast::exp*) return rhs;

		util::maybe_report_ice(!vector::append(exps, rhs$ as byte*) as bool,
			"Could not insert a subsequent expression of a comparison!");
		util::maybe_report_ice(!vector::append(cmps, k$ as byte*) as bool,
			"Could not insert comparison into comparison list!");

		ptok = peek(p);
	}

	if (vector::size(cmps) > 0) {
		type ast::exp_cmp* ec = malloc(sizeof{type ast::exp_cmp}) as type ast::exp_cmp*;
		ec->exps = exps;
		ec->cmps = cmps;
		lhs = malloc(sizeof{type ast::exp}) as type ast::exp*;
		lhs->kind = ast::exp_kind::CMP;
		lhs->which.cmp = ec;
	}

	return lhs;
}

func[static] type ast::exp* parse_inequality(type parser* p) {
	return parse_left_associative_chain(p, parse_shift,
		[
			[lex::tokens::LE, ast::exp_cmp_kind::LE],
			[lex::tokens::LE_DOT, ast::exp_cmp_kind::LE_REAL],
			[lex::tokens::GE, ast::exp_cmp_kind::GE],
			[lex::tokens::GE_DOT, ast::exp_cmp_kind::GE_REAL],
			[lex::tokens::LT, ast::exp_cmp_kind::LT],
			[lex::tokens::LT_DOT, ast::exp_cmp_kind::LT_REAL],
			[lex::tokens::GT, ast::exp_cmp_kind::GT],
			[lex::tokens::GT_DOT, ast::exp_cmp_kind::GT_REAL]
		], 8);
}

func[static] type ast::exp* parse_equality(type parser* p) {
	return parse_left_associative_chain(p, parse_inequality,
		[
			[lex::tokens::EQUALS, ast::exp_cmp_kind::EQ],
			[lex::tokens::NE, ast::exp_cmp_kind::NE],
		], 2);
}

func[static] type ast::exp* parse_bitwise_and(type parser* p) {
	return parse_left_associative_binary(p, parse_equality,
		[
			[lex::tokens::AMPERSAND, ast::exp_binary_kind::BAND]
		], 1);
}

func[static] type ast::exp* parse_exclusive_or(type parser* p) {
	return parse_left_associative_binary(p, parse_bitwise_and,
		[
			[lex::tokens::CARET, ast::exp_binary_kind::XOR]
		], 1);
}

func[static] type ast::exp* parse_bitwise_or(type parser* p) {
	return parse_left_associative_binary(p, parse_exclusive_or,
		[
			[lex::tokens::BITWISE_OR, ast::exp_binary_kind::BOR]
		], 1);
}

func[static] type ast::exp* parse_exp_helper3(type parser* p) {
	return parse_bitwise_or(p);
}

func[static] type ast::exp* parse_exp_helper4(type parser* p) {
	type ast::exp* e = parse_exp_helper3(p);
	if (e == NULL as type ast::exp*) return e;
	type lex::token* tok = peek(p);
	if (tok->tok_type == lex::tokens::COLON) {
		pop(p);
		type ast::typ* t = parse_typ(p);
		if (t == NULL as type ast::typ*) {
			util::report_token_error(util::error_kind::ERR, p->buf, tok,
				"Expected a valid type for an expression type annotation here.");
			return NULL as type ast::exp*;
		}

		type ast::exp_typ_annot* eta = malloc(sizeof{type ast::exp_typ_annot})
			as type ast::exp_typ_annot*;
		eta->e = e;
		eta->ty = t;

		type ast::exp* ret = malloc(sizeof{type ast::exp}) as type ast::exp*;
		ret->kind = ast::exp_kind::TYP_ANNOT;
		ret->which.typ_annot = eta;
		return ret;
	}
	return e;
}

func[static] type ast::exp* parse_logical_and(type parser* p) {
	return parse_left_associative_binary(p, parse_exp_helper4,
		[
			[lex::tokens::ANDALSO, ast::exp_binary_kind::LAND]
		], 1);
}

func[static] type ast::exp* parse_logical_or(type parser* p) {
	return parse_left_associative_binary(p, parse_logical_and,
		[
			[lex::tokens::DOUBLE_BAR, ast::exp_binary_kind::LOR],
			[lex::tokens::ORELSE, ast::exp_binary_kind::LOR]
		], 2);
}

func[static] type ast::exp* parse_exp_helper5(type parser* p) {
	type lex::token* ptok = peek(p);
	if (ptok->tok_type == lex::tokens::IF) {
		pop(p);

		type ast::exp* cond = parse_exp(p);
		if (cond == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid conditional for this if expression.");
			return NULL as type ast::exp*;
		}

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::THEN) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a 'then' after a conditional of an if expression here.");
			return NULL as type ast::exp*;
		}
		pop(p);

		type ast::exp* true_path = parse_exp(p);
		if (true_path == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid expression in the true branch of the if expression here.");
			return NULL as type ast::exp*;
		}

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::ELSE) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected an 'else' after the true path of an if expression here.");
			return NULL as type ast::exp*;
		}
		pop(p);

		type ast::exp* false_path = parse_exp(p);
		if (false_path == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid expression in the false branch of the if expression here.");
			return NULL as type ast::exp*;
		}

		type ast::if_exp* iexp = malloc(sizeof{type ast::if_exp}) as type ast::if_exp*;
		iexp->cond = cond;
		iexp->true_path = true_path;
		iexp->false_path = false_path;
		
		type ast::exp* ret = malloc(sizeof{type ast::exp}) as type ast::exp*;
		ret->kind = ast::exp_kind::IF;
		ret->which.iexp = iexp;
		return ret;
	}
	return parse_logical_or(p);
}

func[static] type ast::exp* parse_exp_helper6(type parser* p) {
	type lex::token* ptok = peek(p);
	if (ptok->tok_type == lex::tokens::WHILE) {
		pop(p);

		type ast::exp* cond = parse_exp(p);
		if (cond == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid condition for a while expression.");
			return NULL as type ast::exp*;
		}

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::DO) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a 'do' after the condition of a while expression.");
			return NULL as type ast::exp*;
		}
		pop(p);

		type ast::exp* body = parse_exp(p);
		if (body == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid expression for the body of a while expression.");
		}

		type ast::while_exp* wexp = malloc(sizeof{type ast::while_exp}) as type ast::while_exp*;
		wexp->cond = cond;
		wexp->body = body;

		type ast::exp* ret = malloc(sizeof{type ast::exp}) as type ast::exp*;
		ret->kind = ast::exp_kind::WHILE;
		ret->which.wexp = wexp;
		return ret;
	}
	return parse_exp_helper5(p);
}

func[static] type ast::match* parse_match_rule_helper(type parser* p) {
	type lex::token* ptok = peek(p);
	type ast::pat* pat = parse_pat(p);
	if (pat == NULL as type ast::pat*) {
		util::report_token_error(util::error_kind::ERR, p->buf, ptok,
			"Expected a valid pattern here for a match expression.");
		return NULL as type ast::match*;
	}

	ptok = peek(p);
	if (ptok->tok_type != lex::tokens::MATCH_ARROW) {
		util::report_token_error(util::error_kind::ERR, p->buf, ptok,
			"Expected a '=>' following the pattern of a match expression.");
		return NULL as type ast::match*;
	}
	pop(p);

	type ast::exp* e = parse_exp(p);
	if (e == NULL as type ast::exp*) {
		util::report_token_error(util::error_kind::ERR, p->buf, ptok,
			"Expected a valid expression following the '=>' of a match expression.");
		return NULL as type ast::match*;
	}

	type ast::match* m = malloc(sizeof{type ast::match}) as type ast::match*;
	m->p = pat;
	m->e = e;
	return m;
}

func[static] type vector::vector* parse_match_helper(type parser* p) {
	type lex::token* ptok = peek(p);
	type ast::match* m = parse_match_rule_helper(p);
	if (m == NULL as type ast::match*) {
		util::report_token_error(util::error_kind::ERR, p->buf, ptok,
			"Expected at least one valid match for a case expression.");
		return NULL as type vector::vector*;
	}

	type vector::vector* matches = vector::new_vector(sizeof{type ast::match*});
	util::maybe_report_ice(!vector::append(matches, m$ as byte*) as bool,
		"Could not insert initial match expression into the case expression match list.");

	ptok = peek(p);
	while (ptok->tok_type == lex::tokens::BAR) {
		pop(p);

		type ast::match* m = parse_match_rule_helper(p);
		if (m == NULL as type ast::match*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid match after a '|' in a case expression.");
			return NULL as type vector::vector*;
		}

		util::maybe_report_ice(!vector::append(matches, m$ as byte*) as bool,
			"Could not insert subsequent match expression into the case expression match list.");
		ptok = peek(p);
	}

	return matches;
}

func[static] type ast::exp* parse_exp_helper7(type parser* p) {
	type lex::token* ptok = peek(p);

	if (ptok->tok_type == lex::tokens::CASE) {
		pop(p);

		type ast::exp* e = parse_exp(p);
		if (e == NULL as type ast::exp*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid expression for a case expression.");
			return NULL as type ast::exp*;
		}

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::OF) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected an 'of' after the expression to case on.");
			return NULL as type ast::exp*;
		}
		pop(p);

		type vector::vector* matches = parse_match_helper(p);
		if (matches == NULL as type vector::vector*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid series of match rules for a case expression.");
		}

		type ast::case_exp* cexp = malloc(sizeof{type ast::case_exp}) as type ast::case_exp*;
		cexp->e = e;
		cexp->matches = matches;

		type ast::exp* ret = malloc(sizeof{type ast::exp}) as type ast::exp*;
		ret->kind = ast::exp_kind::CASE;
		ret->which.cexp = cexp;
		return ret;
	}
	return parse_exp_helper6(p);
}

func type ast::exp* parse_exp_helper8(type parser* p) {
	type lex::token* ptok = peek(p);
	if (ptok->tok_type == lex::tokens::FN) {
		pop(p);

		type vector::vector* matches = parse_match_helper(p);
		if (matches == NULL as type vector::vector*) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a valid match as part of an anonymous function.");
		}

		type ast::exp* ret = malloc(sizeof{type ast::exp}) as type ast::exp*;
		ret->kind = ast::exp_kind::FN;
		ret->which.anon_fun = matches;
		return ret;
	}
	return parse_exp_helper7(p);
}

func type ast::exp* parse_exp(type parser* p) {
	return parse_exp_helper8(p);
}

} } // namespace shadow::parse
