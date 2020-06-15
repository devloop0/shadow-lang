import "util/error.hsp"

import <"std/io">
import <"std/lib">

import "lex/lex.hsp"

using std::io::printf;
using std::lib::abort;
using std::lib::NULL;

namespace shadow { namespace util {

unsigned int ERROR_COUNT = 0;
unsigned int WARN_COUNT = 0;
unsigned int NOTE_COUNT = 0;

func void report_error(unsigned int kind, type lex::buffer* buf, char* msg,
	unsigned int sc, unsigned int ec, unsigned int s, unsigned int e) {

	char* t = kind == error_kind::NOTE ? (NOTE_COUNT++, "NOTE")
		: kind == error_kind::WARN ? (WARN_COUNT++, "WARN")
		: (ERROR_COUNT++, "ERROR");
	printf("%s [%s:%u:%u-%u]: %s\n\t", t, buf->file_name, buf->line_num, sc, ec, msg);
	while (s < e) {
		printf("%c", buf->text[s++]);
	}
	printf("\n\n");
	if (kind == error_kind::ICE)
		abort();
}

func void report_token_error(unsigned int kind, type lex::buffer* buf,
	type lex::token* tok, char* msg) {

	char* t = kind == error_kind::NOTE ? (NOTE_COUNT++, "NOTE")
		: kind == error_kind::WARN ? (WARN_COUNT++, "WARN")
		: (ERROR_COUNT++, "ERROR");
	if (tok->tok_type != lex::tokens::EOF) {
		printf("%s [%s:%u:%u-%u]: %s\n\t", t, buf->file_name, tok->line_num,
			tok->start_col, tok->end_col, msg);
		for (unsigned int i = tok->start_pos; i < tok->end_pos; i++)
			printf("%c", buf->text[i]);
	}
	else
		printf("%s [%s:EOF]: %s", t, buf->file_name, msg);
	printf("\n\n");
	if (kind == error_kind::ICE)
		abort();
}

func void get_error_counts(type error_counts* ec) {
	ec->error_count = ERROR_COUNT;
	ec->warn_count = WARN_COUNT;
	ec->note_count = NOTE_COUNT;
}

func void report_ice(char* msg) {
	printf("ICE: %s\n", msg);
	abort();
}

func void maybe_report_ice(bool c, char* msg) {
	if (!c) report_ice(msg);
}

} } // namespace shadow::util
