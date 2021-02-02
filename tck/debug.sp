import "tck/debug.hsp"

import <"std/lib">
import <"std/io">
import <"stdx/vector">

import "util/error.hsp"
import "tck/util.hsp"
import "ast/ast.hsp"
import "tck/env.hsp"

using namespace stdx::string;
using namespace stdx::vector;
using std::io::printf;
using std::lib::NULL;

namespace shadow { namespace cgen {

func char* itoa(int i);

} } // namespace shadow::cgen

namespace shadow { namespace tck {

func type string::string* typ_2_string(type env* e, type ast::typ* t, bool fully_qualified) {
	switch (t->kind) {
	case ast::typ_kind::CHAR: return string::new_string("char");
	case ast::typ_kind::REAL: return string::new_string("real");
	case ast::typ_kind::BOOL: return string::new_string("bool"); 
	case ast::typ_kind::STRING: return string::new_string("string");
	case ast::typ_kind::INT: return string::new_string("int");
	case ast::typ_kind::UNIT: return string::new_string("unit");
	case ast::typ_kind::VAR: {
		type string::string* ret = string::new_string("`");
		for (unsigned int i = t->which.var->start_pos; i < t->which.var->end_pos; i++) {
			ret = string::addch(ret, e->par->buf->text[i]);
		}
		return ret;
	}
		break;
	case ast::typ_kind::TCK_VAR: {
		type string::string* ret = string::new_string("`$");
		ret = string::addc(ret, cgen::itoa(t->which.tck_var));
		return ret;
	}
		break;
	case ast::typ_kind::FUN: {
		type string::string* ret = string::new_string("(");
		ret = string::add(ret, typ_2_string(e, t->which.tf->arg, fully_qualified));
		ret = string::addc(ret, " -> ");
		ret = string::add(ret, typ_2_string(e, t->which.tf->ret, fully_qualified));
		ret = string::addc(ret, ")");
		return ret;
	}
		break;
	case ast::typ_kind::TUP: {
		type string::string* ret = string::new_string("(");
		unsigned int tup_len = vector::size(t->which.tup);
		for (unsigned int i = 0; i < tup_len; i++) {
			ret = string::add(ret, typ_2_string(e, vector::at(t->which.tup, i) as type ast::typ** @, fully_qualified));
			if (i != tup_len - 1) ret = string::addc(ret, " * ");
		}
		ret = string::addc(ret, ")");
		return ret;
	}
		break;
	case ast::typ_kind::ROW: {
		type string::string* ret = string::new_string("{");
		unsigned int row_len = vector::size(t->which.rmems);
		for (unsigned int i = 0; i < row_len; i++) {
			type ast::typ_row_mem* trm = vector::at(t->which.rmems, i) as type ast::typ_row_mem** @;
			ret = string::addc(ret, trm->ident);
			ret = string::addc(ret, " : ");
			ret = string::add(ret, typ_2_string(e, trm->t, fully_qualified));
			if (i != row_len - 1) ret = string::addc(ret, ", ");
		}
		ret = string::addc(ret, "}");
		return ret;
	}
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		type ast::typ_constructor* tc = t->which.tc;
		type string::string* ret = string::new_string("");

		if (vector::size(tc->typs) != 0)
			ret = string::addc(ret, "(");

		if (vector::size(tc->typs) > 1)
			ret = string::addc(ret, "(");
		for (unsigned int i = 0; i < vector::size(tc->typs); i++) {
			ret = string::add(ret, typ_2_string(e, vector::at(tc->typs, i) as type ast::typ** @, fully_qualified));
			if (i != vector::size(tc->typs) - 1) ret = string::addc(ret, ", ");
		}
		if (vector::size(tc->typs) > 1)
			ret = string::addc(ret, ")");

		if (vector::size(tc->typs) != 0)
			ret = string::addc(ret, " ");
		if (fully_qualified) {
			type vector::vector* ident_name = get_name_from_identifier(e, tc->idents);
			type vector::vector* full_ident_name = to_fully_qualified_name(e, ident_name);
			for (unsigned int i = 0; i < vector::size(full_ident_name); i++) {
				char* curr = vector::at(full_ident_name, i) as char** @;
				if (curr != NULL as char*) ret = string::addc(ret, curr);
				if (i != vector::size(full_ident_name) - 1) ret = string::addc(ret, ".");
			}
		}
		else {
			for (unsigned int i = 0; i < vector::size(tc->idents); i++) {
				type lex::token* tok = vector::at(tc->idents, i) as type lex::token** @;
				if (tok != NULL as type lex::token*) ret = string::addc(ret, extract_token_text(e, tok));
				if (i != vector::size(tc->idents) - 1) ret = string::addc(ret, ".");
			}
		}

		if (vector::size(tc->typs) != 0)
			ret = string::addc(ret, ")");
		return ret;
	}
		break;
	}
}

func void gen_tck_symbols(type env* e, type util::symtab* st,
	type vector::vector* outputs, bool fully_qualified) {
	for (unsigned int i = 0; 
		i < util::symtab_num_entries(st); i++) {
		type ast::typ* val = vector::at(st->values, i)
			as type ast::typ** @;
		char* name = vector::at(st->keys, i) as char** @;

		type string::string* out = string::new_string(name);
		out = string::addc(out, " = ");
		if (val->kind == ast::typ_kind::TCK_VAR) {
			unsigned int tck_var = val->which.tck_var;
			byte* lookup = util::symtab_lookup(e->bindings, tck_var$ as byte*, false);
			if (lookup != NULL) {
				out = string::add(out, tck::typ_2_string(e, lookup as type ast::typ** @,
					fully_qualified));
			}
		}
		else {
			out = string::add(out, tck::typ_2_string(e, val,
				fully_qualified));
		}

		util::maybe_report_ice(!vector::append(outputs, out$ as byte*) as bool,
			"Could not keep track of tck outputs while compiling!");
	}
}

func void print_typ(type env* e, type ast::typ* t) {
	switch (t->kind) {
	case ast::typ_kind::CHAR: printf("char"); break;
	case ast::typ_kind::REAL: printf("real"); break;
	case ast::typ_kind::BOOL: printf("bool"); break;
	case ast::typ_kind::STRING: printf("string"); break;
	case ast::typ_kind::INT: printf("int"); break;
	case ast::typ_kind::UNIT: printf("unit"); break;
	case ast::typ_kind::VAR: {
		printf("`");
		for (unsigned int i = t->which.var->start_pos; i < t->which.var->end_pos; i++) {
			printf("%c", e->par->buf->text[i]);
		}
	}
		break;
	case ast::typ_kind::TCK_VAR: {
		printf("`$%u", t->which.tck_var);
	}
		break;
	case ast::typ_kind::FUN: {
		printf("(");
		print_typ(e, t->which.tf->arg);
		printf(" -> ");
		print_typ(e, t->which.tf->ret);
		printf(")");
	}
		break;
	case ast::typ_kind::TUP: {
		printf("(");
		unsigned int tup_len = vector::size(t->which.tup);
		for (unsigned int i = 0; i < tup_len; i++) {
			print_typ(e, vector::at(t->which.tup, i) as type ast::typ** @);
			if (i != tup_len - 1) printf(" * ");
		}
		printf(")");
	}
		break;
	case ast::typ_kind::ROW: {
		printf("{");
		unsigned int row_len = vector::size(t->which.rmems);
		for (unsigned int i = 0; i < row_len; i++) {
			type ast::typ_row_mem* trm = vector::at(t->which.rmems, i) as type ast::typ_row_mem** @;
			printf("%s : ", trm->ident);
			print_typ(e, trm->t);
			if (i != row_len - 1) printf(", ");
		}
		printf("}");
	}
		break;
	case ast::typ_kind::CONSTRUCTOR: {
		type ast::typ_constructor* tc = t->which.tc;
		if (vector::size(tc->typs) != 0)
			printf("(");

		if (vector::size(tc->typs) > 1)
			printf("(");
		for (unsigned int i = 0; i < vector::size(tc->typs); i++) {
			print_typ(e, vector::at(tc->typs, i) as type ast::typ** @);
			if (i != vector::size(tc->typs) - 1) printf(", ");
		}
		if (vector::size(tc->typs) > 1)
			printf(")");

		if (vector::size(tc->typs) != 0)
			printf(" ");
		for (unsigned int i = 0; i < vector::size(tc->idents); i++) {
			type lex::token* tok = vector::at(tc->idents, i) as type lex::token** @;
			if (tok != NULL as type lex::token*) printf("%s", extract_token_text(e, tok));
			if (i != vector::size(tc->idents) - 1) printf(".");
		}

		if (vector::size(tc->typs) != 0)
			printf(")");
	}
		break;
	}
}

func void print_env_symtab(type env* e, type util::symtab* s) {
	for (unsigned int i = 0; i < vector::size(s->keys); i++) {
		char* k = vector::at(s->keys, i) as char** @;
		type ast::typ* t = vector::at(s->values, i) as type ast::typ** @;
		printf("%s = ", k);
		print_typ(e, t);
		printf("\n");
	}
	printf("--------------------------------\n");
	if (s->parent == NULL as type util::symtab*) return;
	print_env_symtab(e, s->parent);
}

func void print_env_scope(type env* e, type scope* s) {
	printf("================================\n");
	printf("Symbols:\n");
	print_env_symtab(e, s->sym_2_typ_var);
	printf("Types:\n");
	print_env_symtab(e, s->typ_2_typ_var);
	printf("================================\n");
}

func void print_tck_ctx(type env* e) {
	printf("\n================================\n");
	printf("Type constraints:\n");
	for (unsigned int i = 0; i < vector::size(e->typ_constraints); i++) {
		type tck::typ_constraint tc = vector::at(e->typ_constraints, i) as type tck::typ_constraint* @;
		printf("%u: ", i); tck::print_typ(e, tc.lhs); printf(" = "); tck::print_typ(e, tc.rhs); printf("\n");
	}
	printf("================================\n");
	printf("\n================================\n");
	printf("Type solutions:\n");
	for (unsigned int i = 0; i < vector::size(e->bindings->keys); i++) {
		unsigned int tv = vector::at(e->bindings->keys, i) as unsigned int* @;
		type ast::typ* t = vector::at(e->bindings->values, i) as type ast::typ** @;
		printf("`$%u = ", tv), tck::print_typ(e, t), printf("\n");
	}
	printf("================================\n");
}

} } // namespace shadow::tck
