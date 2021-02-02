import "parse/parse.hsp"

import <"stdx/vector">
import <"std/lib">

import "util/error.hsp"
import "lex/lex.hsp"
import "lex/token.hsp"

using namespace stdx::vector;
using std::lib::NULL;
using std::lib::free;
using std::lib::malloc;

namespace shadow { namespace parse {

namespace internal {

func type lex::token* maybe_lex(type parser* p) {
	util::maybe_report_ice(0 <= p->pos && p->pos <= vector::size(p->tokens),
		"Invalid token position in the parser!");

	if (p->pos < vector::size(p->tokens))
		return vector::at(p->tokens, p->pos) as type lex::token** @;

	type lex::token* lexed = lex::lex(p->buf);
	util::maybe_report_ice(!vector::append(p->tokens, lexed$ as byte*) as bool,
		"Unable to store lexed token!");

	util::maybe_report_ice(p->pos != vector::size(p->tokens), "Parser token position out of range!");

	return vector::at(p->tokens, p->pos) as type lex::token** @;
}

} // namespace internal

func void init_parser(type parser* p, type lex::buffer* b) {
	p->buf = b;
	p->pos = 0;
	p->tokens = vector::new_vector(sizeof{type lex::token*});
}

func void destroy_parser(type parser* p) {
	for (unsigned int i = 0; i < vector::size(p->tokens); i++) {
		type lex::token* tok = vector::at(p->tokens, i) as type lex::token** @;
		free(tok as byte*);
	}

	vector::delete_vector(p->tokens);
}

func void pop(type parser* p) {
	type lex::token* tok = internal::maybe_lex(p);
	p->pos++;
}

func type lex::token* peek(type parser* p) {
	return internal::maybe_lex(p);
}

} } // namespace shadow::parse
