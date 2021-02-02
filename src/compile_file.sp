import "src/compile.hsp"

import <"std/io">
import <"std/lib">
import <"std/string">
import <"std/ctype">
import <"stdx/vector">
import <"stdx/string">
import <"std/syscall">

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
import "cgen/util.hsp"

using namespace shadow;
using namespace stdx::vector;
using namespace stdx::string;
using std::io::printf;
using std::lib::NULL;
using std::lib::malloc;
using std::ctype::isalpha;
using std::ctype::isalnum;
using std::lib::rand;
using std::lib::srand;
using std::syscall::direct_gettimeofday;
using std::syscall::timeval;
using std::syscall::timezone;
using std::syscall::direct_open;
using std::syscall::O_RDONLY;
using std::string::strcmp;

namespace shadow { namespace compile {

func type compile_output* compile_file(char* file_name, type compile_options* copts) {
	type compile_output* cout = malloc(sizeof{type compile_output}) as type compile_output*;
	cout->output = vector::new_vector(sizeof{type string::string*});
	cout->success = true;

	char* file_text = util::read_file(file_name);

	if (file_text == NULL as char*) {
		printf("Could not read input file: %s\n", file_name);
		cout->success = false;
	}
	else {
		type lex::buffer* buf = malloc(sizeof{type lex::buffer}) as type lex::buffer*;
		lex::init_buffer(buf, file_name, file_text, false);
		type parse::parser* p = malloc(sizeof{type parse::parser}) as type parse::parser*;
		parse::init_parser(p, buf);

		type ast::prog* prog = parse::parse_prog(p);

		type util::error_counts ecs;
		util::get_error_counts(ecs$);
		if (ecs.error_count > 0) cout->success = false;
		else if (copts->stop_stage == stage_kind::PARSE) {}
		else {
			type tck::prog_status* ps = tck::constrain_prog(copts->module_context, p, prog,
				copts->verbose);
			type tck::env* e = ps->e;

			if (!ps->valid) cout->success = false;
			else {
				if (copts->stop_stage == stage_kind::TCK) {
					tck::gen_tck_symbols(e, e->global_scope.sym_2_typ_var, cout->output, false);
				}
				else {
					type cgen::cgen_ctx* ctx = malloc(sizeof{type cgen::cgen_ctx}) as type cgen::cgen_ctx*;
					cgen::init_cgen_ctx(ctx, e);
					ctx->debug = copts->rt_debug;

					cgen::cgen_prog(ctx, prog, copts->add_entry_point, copts->namespace_name);
					for (unsigned int i = 0; i < vector::size(ctx->cd->header); i++) {
						type string::string* line = vector::at(ctx->cd->header, i) as type string::string** @;
						util::maybe_report_ice(!vector::append(cout->output, line$ as byte*) as bool,
							"Could not keep track of cgen header while compiling!");
					}
					for (unsigned int i = 0; i < vector::size(ctx->cd->body); i++) {
						type string::string* line = vector::at(ctx->cd->body, i) as type string::string** @;
						util::maybe_report_ice(!vector::append(cout->output, line$ as byte*) as bool,
							"Could not keep track of cgen body while compiling!");
					}
					for (unsigned int i = 0; i < vector::size(ctx->cd->main); i++) {
						type string::string* line = vector::at(ctx->cd->main, i) as type string::string** @;
						util::maybe_report_ice(!vector::append(cout->output, line$ as byte*) as bool,
							"Could not keep track of cgen main while compiling!");
					}
	
					// tck::print_tck_ctx(copts->module_context->e);
					// cgen::destroy_cgen_ctx(ctx);
				}

				// tck::destroy_env(e);
				// parse::destroy_parser(p);
			}
		}
	}

	// tck::print_tck_ctx(copts->module_context->e);

	return cout;
}

func[static] void unique_add_lib(type vector::vector* v, char* s) {
	bool hit = false;
	for (unsigned int i = 0; i < vector::size(v); i++) {
		char* vs = vector::at(v, i) as char** @;
		if (strcmp(vs, s) == 0) {
			hit = true;
			break;
		}
	}

	if (hit) return;
	util::maybe_report_ice(!vector::append(v, s$ as byte*) as bool,
		"Could not uniquely add a library while generating a file compilation script!");
}

func[static] void collect_all_dependencies(type vector::vector* libs, type tck::module* m) {
	for (unsigned int i = 0; i < util::symtab_num_entries(m->imported_modules); i++) {
		char* k = vector::at(m->imported_modules->keys, i) as char** @;

		type tck::module* c = vector::at(m->imported_modules->values, i) as type tck::module** @;
		collect_all_dependencies(libs, c);

		unique_add_lib(libs, k);
	}

	for (unsigned int i = 0; i < util::symtab_num_entries(m->submodules); i++) {
		char* k = vector::at(m->submodules->keys, i) as char** @;
		type string::string* full_mod_name = tck::extract_module_name(m, MOD_FILE_SEP);
		if (m != m->global_module)
			full_mod_name = string::addc(full_mod_name, MOD_FILE_SEP);
		full_mod_name = string::addc(full_mod_name, k);

		type tck::module* c = vector::at(m->submodules->values, i) as type tck::module** @;
		collect_all_dependencies(libs, c);

		unique_add_lib(libs, string::data(full_mod_name));
	}
}

func type vector::vector* gen_file_compile_script(const char* output_file, type tck::module* m) {
	type vector::vector* ret = vector::new_vector(sizeof{type string::string*});
	type vector::vector* libs = vector::new_vector(sizeof{char*});

	type string::string* shebang = string::new_string("#!/bin/bash");
	util::maybe_report_ice(!vector::append(ret, shebang$ as byte*) as bool,
		"Could not add the shebang for a compilation script!");
	type string::string* echo_on = string::new_string("set -x");
	util::maybe_report_ice(!vector::append(ret, echo_on$ as byte*) as bool,
		"Could not enable echo'ing for a file compilation script!");

	type string::string* full_file_name = string::new_string(output_file);
	type string::string* full_asm_name = string::addc(full_file_name, ".s"),
		full_o_name = string::addc(full_file_name, ".o"),
		full_exec_name = string::addc(full_file_name, ".out");

	type string::string* sp_command = string::new_string("spectre ");
	sp_command = string::add(sp_command, full_file_name);
	util::maybe_report_ice(!vector::append(ret, sp_command$ as byte*) as bool,
		"Could not keep track of the 'spectre' command when generating a file compilation script!");

	type string::string* as_command = string::new_string("as -mfpu=vfp -mfloat-abi=hard ");
	as_command = string::add(as_command, full_asm_name);
	as_command = string::addc(as_command, " -o ");
	as_command = string::add(as_command, full_o_name);
	util::maybe_report_ice(!vector::append(ret, as_command$ as byte*) as bool,
		"Could not keep track of the 'as' command when generating a file compilation script!");

	collect_all_dependencies(libs, m);

	type string::string* ld_command = string::new_string("ld ");
	ld_command = string::add(ld_command, full_o_name);
	ld_command = string::addc(ld_command, " -o ");
	ld_command = string::add(ld_command, full_exec_name);

	ld_command = string::addc(string::addc(ld_command, " -L"), GLOBAL_SPECTRE_DIR);
	ld_command = string::addc(ld_command, " --whole-archive -l:libspectre.a");
	ld_command = string::addc(string::addc(ld_command, " -L"), GLOBAL_SHADOW_RT_DIR);
	ld_command = string::addc(ld_command, " --whole-archive -l:shadow_rt.a");

	ld_command = string::addc(string::addc(ld_command, " -L"), GLOBAL_LIB_DIR);

	type string::string* lib_prefix = string::new_string(" --whole-archive -l:");
	type string::string* lib_suffix = string::new_string(".a");
	for (unsigned int i = 0; i < vector::size(libs); i++) {
		char* curr = vector::at(libs, i) as char** @;
		
		ld_command = string::add(ld_command, lib_prefix);
		ld_command = string::addc(ld_command, curr);
		ld_command = string::add(ld_command, lib_suffix);
	}

	util::maybe_report_ice(!vector::append(ret, ld_command$ as byte*) as bool,
		"Could not keep track of the 'ld' command when generating a file compilation script!");

	type string::string* cleanup_command = string::new_string("rm -f ");
	cleanup_command = string::addc(string::add(cleanup_command, full_asm_name), " ");
	cleanup_command = string::addc(string::add(cleanup_command, full_o_name), " ");
	util::maybe_report_ice(!vector::append(ret, cleanup_command$ as byte*) as bool,
		"Could not keep track of the cleanup command when generating a file compilation script!");
	return ret;
}

} } // namespace shadow::compile
