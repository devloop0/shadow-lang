import "tck/debug.hsp"

import <"std/lib">
import <"std/io">
import <"stdx/vector">

import "tck/util.hsp"
import "ast/ast.hsp"
import "tck/env.hsp"

using namespace stdx::vector;
using std::io::printf;
using std::lib::NULL;

namespace shadow { namespace tck {

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
			printf("%s", extract_token_text(e, tok));
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
