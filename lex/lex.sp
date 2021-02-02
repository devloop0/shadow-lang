import "lex/lex.hsp"

import <"std/lib">
import <"std/string">
import <"std/ctype">

import "util/error.hsp"

namespace shadow { namespace lex {

func void advance_char(type buffer* buf) {
	if (buf->pos >= buf->len)
		return;

	if (buf->text[buf->pos] == '\n')
		buf->line_num++, buf->col_num = 0;
	buf->pos++;
	buf->col_num++;
}

func void init_buffer(type buffer* buf, char* file_name, char* text,
	bool allow_dollar_sign) {
	buf->text = text;
	buf->file_name = file_name;

	buf->pos = 0;
	buf->len = std::string::strlen(text);

	buf->line_num = 1;
	buf->col_num = 1;

	buf->allow_dollar_sign = allow_dollar_sign;
}

func bool skip_whitespace(type buffer* buf) {
	if (buf->pos >= buf->len)
		return false;

	bool ret = false;
	while (buf->pos < buf->len && buf->text[buf->pos] as bool &&
		(buf->text[buf->pos] == ' ' || buf->text[buf->pos] == '\t' || buf->text[buf->pos] == '\n')) {
		advance_char(buf);
		ret = true;
	}

	return ret;
}

func bool skip_comment(type buffer* buf) {
	if (buf->pos >= buf->len)
		return false;

	if (buf->text[buf->pos] == '#') buf->pos++;
	else return false;

	while (buf->pos < buf->len && buf->text[buf->pos] as bool &&
		buf->text[buf->pos] != '\n')
		advance_char(buf);

	advance_char(buf);

	return true;
}

func type token* lex(type buffer* buf) {
	using std::lib::malloc;

	if (buf->pos >= buf->len) {
		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->line_num = buf->line_num;
		tok->start_col = buf->col_num;
		tok->end_col = buf->col_num;
		tok->start_pos = buf->len;
		tok->end_pos = buf->len;
		tok->tok_type = tokens::EOF;
		tok->buf_ref = buf;
		return tok;
	}

	while (true) {
		skip_whitespace(buf);
		bool skipped_comment = skip_comment(buf);

		if (!skipped_comment) break;
	}

	skip_whitespace(buf);

	if (buf->pos >= buf->len) {
		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->line_num = buf->line_num;
		tok->start_col = buf->col_num;
		tok->end_col = buf->col_num;
		tok->start_pos = buf->len;
		tok->end_pos = buf->len;
		tok->tok_type = tokens::EOF;
		tok->buf_ref = buf;
		return tok;
	}

	switch (buf->text[buf->pos]) {
	case '\"':
	case '\'': {
		bool is_char = buf->text[buf->pos] == '\'';
		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->buf_ref = buf;
		tok->tok_type = is_char ? tokens::CHAR_LITERAL : tokens::STRING_LITERAL;

		unsigned int start_pos = buf->pos,
			start_col = buf->col_num;
		char* err_string = is_char
			? "Unclosed character literal."
			: "Unclosed string literal.";
		char delim = is_char ? '\'' : '\"';
		advance_char(buf);
		while (buf->pos < buf->len && buf->text[buf->pos] as bool
			&& buf->text[buf->pos] != delim && buf->text[buf->pos] != '\n') {
			if (buf->text[buf->pos] == '\\')
				advance_char(buf);
			advance_char(buf);
		}

		if (buf->text[buf->pos] != delim)
			util::report_error(util::error_kind::ERR, buf, err_string,
				start_col, buf->col_num, start_pos, buf->pos);
		unsigned int end_col = ++buf->col_num, end_pos = ++buf->pos;

		tok->line_num = buf->line_num;
		tok->start_col = start_col;
		tok->end_col = end_col;
		tok->start_pos = start_pos;
		tok->end_pos = end_pos;
		return tok;
	}
		break;
	case '0':
	case '1':
	case '2':
	case '3':
	case '4':
	case '5':
	case '6':
	case '7':
	case '8':
	case '9': {
		unsigned int start_pos = buf->pos,
			start_col = buf->col_num;

		using std::ctype::isdigit;
		using std::ctype::isxdigit;
		if (buf->text[buf->pos] == '0'
			&& (isdigit(buf->text[buf->pos + 1])
				|| buf->text[buf->pos + 1] == 'x' || buf->text[buf->pos + 1] == 'X'
				|| buf->text[buf->pos + 1] == 'b' || buf->text[buf->pos + 1] == 'B'
				|| buf->text[buf->pos + 1] == 'o' || buf->text[buf->pos + 1] == 'O')) {
			bool is_hex = buf->text[buf->pos + 1] == 'x' || buf->text[buf->pos + 1] == 'X',
				is_bin = buf->text[buf->pos + 1] == 'b' || buf->text[buf->pos + 1] == 'B';
			advance_char(buf);
			advance_char(buf);
			while (buf->pos < buf->len && buf->text[buf->pos] as bool) {
				if (is_hex && isxdigit(buf->text[buf->pos]))
					advance_char(buf);
				else if (is_bin && (buf->text[buf->pos] == '0' || buf->text[buf->pos] == '1'))
					advance_char(buf);
				else if (isdigit(buf->text[buf->pos]) && buf->text[buf->pos] != '8'
						&& buf->text[buf->pos] != '9') {
						advance_char(buf);
				}
				else break;
			}

			type token* tok = malloc(sizeof{type token}) as type token*;
			tok->buf_ref = buf;
			tok->tok_type = tokens::INT_LITERAL;
			tok->line_num = buf->line_num;
			tok->start_col = start_col;
			tok->start_pos = start_pos;
			tok->end_col = buf->col_num;
			tok->end_pos = buf->pos;
			return tok;
		}
		else {
			bool hit_decimal = false, hit_exponent = false;
			while (buf->pos < buf->len && buf->text[buf->pos] as bool) {
				if (isdigit(buf->text[buf->pos]))
					advance_char(buf);
				else if (buf->text[buf->pos] == '.') {
					if (hit_decimal || hit_exponent) break;
					else {
						hit_decimal = true;
						advance_char(buf);
					}
				}
				else if (buf->text[buf->pos] == 'e' || buf->text[buf->pos] == 'E') {
					if (hit_exponent) break;
					else {
						advance_char(buf);
						if (buf->pos < buf->len && buf->text[buf->pos] as bool
							&& (buf->text[buf->pos] == '+' || buf->text[buf->pos] == '-'))
							advance_char(buf);
					}
				}
				else break;
			}
			type token* tok = malloc(sizeof{type token}) as type token*;
			tok->buf_ref = buf;
			tok->tok_type = hit_decimal ? tokens::REAL_LITERAL : tokens::INT_LITERAL;
			tok->line_num = buf->line_num;
			tok->start_col = start_col;
			tok->start_pos = start_pos;
			tok->end_col = buf->col_num;
			tok->end_pos = buf->pos;
			return tok;
		}
	}
		break;
	case '+':
	case '*':
	case '/': {
		char curr = buf->text[buf->pos];
		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->buf_ref = buf;
		tok->line_num = buf->line_num;
		tok->start_col = buf->col_num;
		tok->start_pos = buf->pos;
		
		advance_char(buf);
		if (buf->text[buf->pos] == '.') {
			advance_char(buf);
			switch (curr) {
			case '+': tok->tok_type = tokens::PLUS_DOT; break;
			case '/': tok->tok_type = tokens::SLASH_DOT; break;
			case '*': tok->tok_type = tokens::STAR_DOT; break;
			}
		}
		else if (curr == '+' && buf->text[buf->pos] == '+') {
			advance_char(buf);
			tok->tok_type = tokens::PLUS_PLUS;
		}
		else {
			switch (curr) {
			case '+': tok->tok_type = tokens::PLUS; break;
			case '/': tok->tok_type = tokens::SLASH; break;
			case '*': tok->tok_type = tokens::STAR; break;
			}
		}

		tok->end_col = buf->col_num;
		tok->end_pos = buf->pos;
		return tok;
	}
		break;
	case ',':
	case '^':
	case '.':
	case '(':
	case ')':
	case '{':
	case '}':
	case '$':
	case '`':
	case ';':
	case '[':
	case ']':
	case '~':
	case '%': {
		type token* tok = malloc(sizeof{type token}) as type token*;

		switch (buf->text[buf->pos]) {
		case '$': tok->tok_type = tokens::DOLLAR_SIGN; break;
		case '%': tok->tok_type = tokens::PERCENT; break;
		case '[': tok->tok_type = tokens::OPEN_BRACKET; break;
		case ']': tok->tok_type = tokens::CLOSE_BRACKET; break;
		case '}': tok->tok_type = tokens::CLOSE_BRACE; break;
		case '{': tok->tok_type = tokens::OPEN_BRACE; break;
		case '(': tok->tok_type = tokens::OPEN_PAR; break;
		case ')': tok->tok_type = tokens::CLOSE_PAR; break;
		case '.': tok->tok_type = tokens::DOT; break;
		case '^': tok->tok_type = tokens::CARET; break;
		case ',': tok->tok_type = tokens::COMMA; break;
		case ';': tok->tok_type = tokens::SEMICOLON; break;
		case '`': tok->tok_type = tokens::BACKTICK; break;
		case '~': tok->tok_type = tokens::TILDE; break;
		}

		if (tok->tok_type == tokens::DOLLAR_SIGN && !buf->allow_dollar_sign)
			break;

		tok->buf_ref = buf;
		tok->line_num = buf->line_num;
		tok->start_col = buf->col_num;
		tok->start_pos = buf->pos;

		advance_char(buf);

		tok->end_col = buf->col_num;
		tok->end_pos = buf->pos;
		return tok;
	}
		break;
	case ':':
	case '|':
	case '&': {
		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->buf_ref = buf;
		tok->start_pos = buf->pos;
		tok->start_col = buf->col_num;
		tok->line_num = buf->line_num;
		char curr = buf->text[buf->pos];
		if (buf->text[buf->pos + 1] == curr) {
			advance_char(buf);
			advance_char(buf);

			tok->end_col = buf->col_num;
			tok->end_pos = buf->pos;
			tok->tok_type = curr == '&'
				? tokens::DOUBLE_AMPERSAND
				: curr == '|'
					? tokens::DOUBLE_BAR
					: tokens::DOUBLE_COLON;
		}
		else {
			advance_char(buf);

			tok->end_col = buf->col_num;
			tok->end_pos = buf->pos;
			tok->tok_type = curr == '&'
				? tokens::AMPERSAND
				: curr == '|'
					? tokens::BAR
					: tokens::COLON;
		}
		return tok;
	}
		break;
	case '-':
	case '=': {
		char curr = buf->text[buf->pos];
		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->buf_ref = buf;
		tok->start_pos = buf->pos;
		tok->start_col = buf->col_num;
		tok->line_num = buf->line_num;

		advance_char(buf);
		if (buf->text[buf->pos] == '>') {
			advance_char(buf);
			tok->tok_type = curr == '-' ? tokens::FUN_ARROW : tokens::MATCH_ARROW;
		}
		else if (curr == '-' && buf->text[buf->pos] == '.') {
			advance_char(buf);
			tok->tok_type = tokens::MINUS_DOT;
		}
		else
			tok->tok_type = curr == '-' ? tokens::MINUS : tokens::EQUALS;

		tok->end_pos = buf->pos;
		tok->end_col = buf->col_num;
		return tok;
	}
		break;
	case '!': {
		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->buf_ref = buf;
		tok->start_pos = buf->pos;
		tok->start_col = buf->col_num;
		tok->line_num = buf->line_num;

		advance_char(buf);
		if (buf->text[buf->pos] == '=') {
			advance_char(buf);
			tok->tok_type = tokens::NE;
		}
		else
			tok->tok_type = tokens::EXCLAMATION_MARK;
		
		tok->end_pos = buf->pos;
		tok->end_col = buf->col_num;
		return tok;
	}
		break;
	case '>':
	case '<': {
		char curr = buf->text[buf->pos];

		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->buf_ref = buf;
		tok->start_pos = buf->pos;
		tok->start_col = buf->col_num;
		tok->line_num = buf->line_num;

		advance_char(buf);
		if (buf->text[buf->pos] == curr) {
			advance_char(buf);
			tok->tok_type = curr == '>'
				? tokens::SHR
				: tokens::SHL;
		}
		else if (buf->text[buf->pos] == '=') {
			advance_char(buf);
			if (buf->text[buf->pos] == '.') {
				tok->tok_type = curr == '>'
					? tokens::GE_DOT
					: tokens::LE_DOT;
			}
			else {
				tok->tok_type = curr == '>'
					? tokens::GE
					: tokens::LE;
			}
		}
		else {
			if (buf->text[buf->pos] == '.') {
				advance_char(buf);
				tok->tok_type = curr == '>'
					? tokens::GT_DOT
					: tokens::LT_DOT;
			}
			else {
				tok->tok_type = curr == '>'
					? tokens::GT
					: tokens::LT;
			}
		}

		tok->end_pos = buf->pos;
		tok->end_col = buf->col_num;
		return tok;
	}
		break;
	default: {
		using std::ctype::isalpha;
		using std::ctype::isalnum;

		if (!isalpha(buf->text[buf->pos]) && buf->text[buf->pos] != '_') break;

		type token* tok = malloc(sizeof{type token}) as type token*;
		tok->buf_ref = buf;
		tok->start_pos = buf->pos;
		tok->start_col = buf->col_num;
		tok->line_num = buf->line_num;

		advance_char(buf);

		while (buf->pos < buf->len && buf->text[buf->pos] as bool
			&& (isalnum(buf->text[buf->pos]) || buf->text[buf->pos] == '_'))
			advance_char(buf);

		tok->end_pos = buf->pos;
		tok->end_col = buf->col_num;

		tok->tok_type = tokens::IDENT;

		using std::string::strncmp;
		using std::string::strlen;
		unsigned int tok_length = tok->end_pos - tok->start_pos;
		char* start = buf->text[tok->start_pos]$;
		char** keywords = [
			"let", "in", "if", "then", "else", "while", "do", "rec", "type",
			"fun", "struct", "end", "val", "fn", "case", "of", "import", 
			"sig", "datatype", "unit", "int", "char", "string", "real",
			"_", "bool", "true", "false", "bitwise_or", "andalso", "orelse", "as", "efun",
			""
		];
		unsigned int* ids = [
			tokens::LET, tokens::IN, tokens::IF, tokens::THEN, tokens::ELSE, tokens::WHILE,
			tokens::DO, tokens::REC, tokens::TYPE, tokens::FUN, tokens::STRUCT, tokens::END,
			tokens::VAL, tokens::FN, tokens::CASE, tokens::OF, tokens::IMPORT, tokens::SIG,
			tokens::DATATYPE, tokens::UNIT, tokens::INT, tokens::CHAR, tokens::STRING,
			tokens::REAL, tokens::UNDERSCORE, tokens::BOOL, tokens::TRUE, tokens::FALSE,
			tokens::BITWISE_OR, tokens::ANDALSO, tokens::ORELSE, tokens::AS, tokens::EFUN,
		];
		for (unsigned int i = 0; strlen(keywords[i]) != 0; i++) {
			unsigned int keyword_length = strlen(keywords[i]);
			if (strncmp(start, keywords[i],
				tok_length < keyword_length ? keyword_length : tok_length) == 0) {
				tok->tok_type = ids[i];
				break;
			}
		}

		return tok;
	}
		break;
	}
	util::report_error(util::error_kind::ERR, buf, "Illegal character.",
		buf->col_num, buf->col_num + 1, buf->pos, buf->pos + 1);
	type token* bad = malloc(sizeof{type token*}) as type token*;
	bad->buf_ref = buf;
	bad->line_num = buf->line_num;
	bad->start_pos = buf->pos;
	bad->end_pos = buf->pos + 1;
	bad->start_col = buf->col_num;
	bad->end_col = buf->col_num + 1;
	bad->tok_type = tokens::ERR;
	advance_char(buf);
	return bad;
}

} } // namespace shadow::lex
