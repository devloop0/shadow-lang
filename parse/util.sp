import "parse/util.hsp"

import <"std/lib">
import <"std/io">
import <"stdx/vector">

import "util/error.hsp"
import "parse/parse.hsp"
import "lex/token.hsp"

using std::lib::NULL;
using std::io::printf;
using namespace stdx::vector;

namespace shadow { namespace parse {

func type vector::vector* parse_var_list(type parser* p) {
	type vector::vector* vars = vector::new_vector(
		sizeof{type lex::token*});
	type lex::token* ptok = peek(p);

	if (ptok->tok_type == lex::tokens::BACKTICK) {
		pop(p);

		ptok = peek(p);
		if (ptok->tok_type != lex::tokens::IDENT) {
			util::report_token_error(util::error_kind::ERR, p->buf,
				ptok, "Expected an identifier here after a backtick (`) for a type variable.");
			return vars;
		}
		util::maybe_report_ice(!vector::append(vars, ptok$ as byte*) as bool,
			"Could not append variable to a var-list!");

		pop(p);
	}
	else if (ptok->tok_type == lex::tokens::OPEN_PAR) {
		unsigned int orig_pos = p->pos;
		pop(p);

		ptok = peek(p);
		while (ptok->tok_type == lex::tokens::BACKTICK) {
			pop(p);

			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::IDENT) {
				util::report_token_error(util::error_kind::ERR, p->buf,
					ptok, "Expected an identifier here after a backtick (`) for a type variable.");
				break;
			}
			util::maybe_report_ice(!vector::append(vars, ptok$ as byte*) as bool,
				"Could not append variable to a var-list!");

			pop(p);
			ptok = peek(p);
			if (ptok->tok_type != lex::tokens::COMMA)
				break;

			pop(p);
			ptok = peek(p);
		}

		if (vector::size(vars) == 0) {
			p->pos = orig_pos;
			return vars;
		}

		if (ptok->tok_type != lex::tokens::CLOSE_PAR) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected a close parenthesis ()) to end a type variable list.");
			return vars;
		}
		pop(p);

		if (vector::size(vars) == 0) {
			util::report_token_error(util::error_kind::ERR, p->buf, ptok,
				"Expected at least one type variable in a parenthesized type variable list.");
			return vars;
		}
	}


	return vars;
}

func type vector::vector* parse_maybe_long_ident(type parser* p) {
	type vector::vector* idents = vector::new_vector(
		sizeof{type lex::token*});

	type lex::token* ptok = peek(p);
	if (ptok->tok_type == lex::tokens::DOT) {
		type lex::token* global = NULL as type lex::token*;
		util::maybe_report_ice(!vector::append(idents, global$ as byte*) as bool,
			"Could not append the 'global' identifier to the identifier-list!");
		pop(p);
		ptok = peek(p);
	}

	if (ptok->tok_type != lex::tokens::IDENT) {
		util::report_token_error(util::error_kind::ERR, p->buf, ptok,
			"Expected at least on identifier here!");
		return idents;
	}
		
	while (ptok->tok_type == lex::tokens::IDENT) {
		pop(p);

		util::maybe_report_ice(!vector::append(idents, ptok$ as byte*) as bool,
			"Could not append identifier to identifier-list!");
		
		ptok = peek(p);
		if (ptok->tok_type == lex::tokens::DOT)
			pop(p);
		else break;
		ptok = peek(p);
	}

	return idents;
}

} } // namespace shadow::parse
