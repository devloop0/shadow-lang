import "parse/parse.hsp"

import <"std/lib">
import <"stdx/vector">

import "ast/ast.hsp"
import "util/error.hsp"
import "lex/token.hsp"

using std::lib::malloc;
using std::lib::free;
using std::lib::NULL;
using namespace stdx::vector;

namespace shadow { namespace parse {

func type ast::prog* parse_prog(type parser* p) {
	type ast::prog* prog = malloc(sizeof{type ast::prog})
		as type ast::prog*;

	prog->top_level_constructs = vector::new_vector(sizeof{type ast::top_level*});

	type lex::token* ptok = peek(p);
	while (ptok->tok_type != lex::tokens::EOF) {
		type ast::top_level* tl = malloc(sizeof{type ast::top_level})
			as type ast::top_level*;

		if (ptok->tok_type == lex::tokens::FUN
			|| ptok->tok_type == lex::tokens::EFUN
			|| ptok->tok_type == lex::tokens::TYPE
			|| ptok->tok_type == lex::tokens::DATATYPE
			|| ptok->tok_type == lex::tokens::VAL) {
			type ast::decl* d = parse_decl(p);
			if (d == NULL as type ast::decl*) {
				util::report_token_error(util::error_kind::ERR, p->buf,
					ptok, "Invalid declaration starting here.");
				break;
			}

			tl->which.top_level_decl = d;
			tl->kind = ast::top_level_kind::DECL;
		}
		else if (ptok->tok_type == lex::tokens::IMPORT) {
			type ast::mod_import* mi = parse_mod_import(p);
			if (mi == NULL as type ast::mod_import*) {
				util::report_token_error(util::error_kind::ERR, p->buf,
					ptok, "Invalid module import starting here.");
				break;
			}

			tl->which.top_level_import = mi;
			tl->kind = ast::top_level_kind::IMPORT;
		}
		else {
			util::report_token_error(util::error_kind::ERR, p->buf,
				ptok, "Invalid top-level construct starting here.");
			break;
		}

		util::maybe_report_ice(!vector::append(prog->top_level_constructs, tl$ as byte*) as bool,
			"Could not append top-level construct.");

		ptok = peek(p);
	}

	return prog;
}

} } // namespace shadow::ast
