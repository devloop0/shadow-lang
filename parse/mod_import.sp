import "parse/parse.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/vector">

import "ast/ast.hsp"
import "lex/token.hsp"
import "util/error.hsp"
import "parse/util.hsp"

using namespace stdx::vector;
using std::io::printf;
using std::lib::malloc;
using std::lib::NULL;

namespace shadow { namespace parse {

func type ast::mod_import* parse_mod_import(type parser* p) {
	type lex::token* ptok = peek(p);
	if (ptok->tok_type != lex::tokens::IMPORT) {
		util::report_token_error(util::error_kind::ERR, p->buf,
			ptok, "Invalid start to an import declaration.");
		return NULL as type ast::mod_import*;
	}
	pop(p);
		
	type ast::mod_import* mi = malloc(sizeof{type ast::mod_import*}) as type ast::mod_import*;
	mi->import_token = ptok;
	ptok = peek(p);
	if (ptok->tok_type != lex::tokens::IDENT && ptok->tok_type != lex::tokens::DOT) {
		util::report_token_error(util::error_kind::ERR, p->buf, ptok,
			"Expected the name of a module to 'import' here.");
		return NULL as type ast::mod_import*;
	}

	mi->module_ref = parse_maybe_long_ident(p);
	return mi;
}

} } // namespace shadow::parse
