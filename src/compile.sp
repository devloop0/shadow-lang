import <"std/io">
import <"std/lib">
import <"stdx/vector">
import <"stdx/string">

import "cgen/cgen.hsp"
import "tck/debug.hsp"
import "tck/util.hsp"
import "tck/constrain.hsp"
import "util/error.hsp"
import "util/symtab.hsp"
import "tck/env.hsp"
import "lex/lex.hsp"
import "lex/token.hsp"
import "util/error.hsp"
import "parse/parse.hsp"
import "ast/ast.hsp"
import "tck/unify.hsp"
import "util/stack.hsp"
import "util/file.hsp"
import "cgen/cgen.hsp"

using namespace shadow;
using namespace stdx::vector;
using namespace stdx::string;
using std::io::printf;
using std::lib::NULL;

namespace shadow { namespace compile {

func int compile_file(char* file_name, bool print) {
	if (print) {
		printf("---------------------------------------------------\n");
		printf("File name: %s\n", file_name);
	}

	unsigned int return_value = 0;

	char* file_text = util::read_file(file_name);

	if (file_text == NULL as char*) return_value = 1;
	else {
		type lex::buffer buf;
		lex::init_buffer(buf$, file_name, file_text);
		type parse::parser p;
		parse::init_parser(p$, buf$);

		type ast::prog* prog = parse::parse_prog(p$);

		type util::error_counts ecs;
		util::get_error_counts(ecs$);
		if (ecs.error_count > 0) return_value = 1;
		else {
			type tck::env e;
			tck::init_env(e$, p$);

			if (!tck::constrain_prog(e$, prog)) return_value = 1;
			else {
				for (unsigned int i = 0;
					i < util::symtab_num_entries(e.global_scope.sym_2_typ_var); i++) {
					type ast::typ* val = vector::at(e.global_scope.sym_2_typ_var->values, i)
						as type ast::typ** @;
					char* name = vector::at(e.global_scope.sym_2_typ_var->keys, i) as char** @;
					if (val->kind == ast::typ_kind::TCK_VAR) {
						unsigned int tck_var = val->which.tck_var;
						byte* lookup = util::symtab_lookup(e.bindings, tck_var$ as byte*, false);
						if (lookup != NULL && print) {
							printf("%s = ", name),
							tck::print_typ(e$, lookup as type ast::typ** @),
							printf("\n");
						}
					}
				}

				type cgen::cgen_ctx ctx;
				cgen::init_cgen_ctx(ctx$, e$);
				ctx.debug = print;

				cgen::cgen_prog(ctx$, prog);
				if (print) {
					printf("\nCodegen:\n");
					for (unsigned int i = 0; i < vector::size(ctx.cd->header); i++) {
						type string::string* line = vector::at(ctx.cd->header, i) as type string::string** @;
						printf("%s\n", string::data(line));
					}
					for (unsigned int i = 0; i < vector::size(ctx.cd->body); i++) {
						type string::string* line = vector::at(ctx.cd->body, i) as type string::string** @;
						printf("%s\n", string::data(line));
					}
					for (unsigned int i = 0; i < vector::size(ctx.cd->main); i++) {
						type string::string* line = vector::at(ctx.cd->main, i) as type string::string** @;
						printf("%s\n", string::data(line));
					}
					printf("<<EOF>>\n");
				}
	
				cgen::destroy_cgen_ctx(ctx$);
				tck::destroy_env(e$);
				parse::destroy_parser(p$);
			}
		}
	}

	if (print) {
		printf("Return Value: %d\n", return_value);
		printf("---------------------------------------------------\n");
	}

	return return_value;
}

func int compile_samples(unsigned int num_files) {
	char* single = "samples/tck/progX.sdw",
		two = "samples/tck/progXX.sdw";

	for (unsigned int i = num_files; i >= 1; i--) {
		char* file_name = NULL as char*;
		if (i < 10) {
			file_name = single;
			file_name[16] = '0' + i;
		}
		else if (i < 100) {
			file_name = two;
			file_name[16] = (i / 10) + '0';
			file_name[17] = (i % 10) + '0';
		}
		util::maybe_report_ice(file_name != NULL as char*,
			"Invalid number of files provided!");

		int tmp = compile_file(file_name, true);
		if (tmp != 0) return tmp;
	}

	return 0;
}

} } // namespace shadow::compile
