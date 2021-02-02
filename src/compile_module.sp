import "src/compile.hsp"

import <"std/io">
import <"std/lib">
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
using std::syscall::direct_mkdir;
using std::syscall::direct_truncate;
using std::syscall::O_RDONLY;

namespace shadow { namespace compile {

func void gen_mod_info(
	type string::string* header_name,
	type tck::env* e, type util::symtab* st,
	type vector::vector* ret) {
	util::maybe_report_ice(!vector::append(ret, header_name$ as byte*) as bool,
		"Could not add module header to the .mod file's output!");
	if (e == NULL as type tck::env*) return;

	type vector::vector* curr_ctx = vector::new_vector(sizeof{type string::string*});
	tck::gen_tck_symbols(e, st, curr_ctx, true);
	for (unsigned int i = 0; i < vector::size(curr_ctx); i++) {
		type string::string* s = vector::at(curr_ctx, i) as type string::string** @;
		type string::string* to_add = string::new_string("\t");
		to_add = string::add(to_add, s);
		to_add = string::addc(to_add, " ");
		to_add = string::addc(to_add, MOD_DATA_SEP);
		util::maybe_report_ice(!vector::append(ret, to_add$ as byte*) as bool,
			"Could not insert definition to the .mod file's output!");
	}
}

func void write_module_metadata(type compile_module_output* cout,
	type compile_options* copts) {
	type tck::module* module_context = cout->module_context;
	type module_config* mod_conf = cout->module_cfg;
	type vector::vector* ret = vector::new_vector(sizeof{type string::string*});

	type string::string* module_name_header = string::new_string(MOD_NAME_HEADER);
	util::maybe_report_ice(!vector::append(ret, module_name_header$ as byte*) as bool,
		"Could not add the module name header to the .mod file's output!");
	type string::string* module_name = string::new_string("\t");
	module_name = string::add(module_name, cout->module_name);
	util::maybe_report_ice(!vector::append(ret, module_name$ as byte*) as bool,
		"Could not add module name to the .mod file's output!");

	type string::string* visibility_header = string::new_string(MOD_VISIBILITY_HEADER);
	type string::string* visibility_value = string::new_string("\t");
	visibility_value = string::addc(visibility_value, mod_conf->visibility ? "true" : "false");
	util::maybe_report_ice(!vector::append(ret, visibility_header$ as byte*) as bool,
		"Could not add the visibility header to the .mod file's output!");
	util::maybe_report_ice(!vector::append(ret, visibility_value$ as byte*) as bool,
		"Could not add the visibility value to the .mod file's output!");

	type string::string* namespace_header = string::new_string(MOD_NAMESPACES_HEADER);
	util::maybe_report_ice(!vector::append(ret, namespace_header$ as byte*) as bool,
		"Could not add module namespaces header to the .mod file's output!");
	for (unsigned int i = 0; i < vector::size(cout->output); i++) {
		type module_file_output* mfo = vector::at(cout->output, i)
			as type module_file_output** @;
		type string::string* namespace_list_elem = string::new_string("\t");
		namespace_list_elem = string::add(namespace_list_elem, mfo->namespace_name);
		util::maybe_report_ice(!vector::append(ret, namespace_list_elem$ as byte*) as bool,
			"Could not insert namespace name to the .mod file's output!");
		
		/* for (unsigned int j = 0; j < vector::size(mfo->output); j++) {
			type string::string* line = vector::at(mfo->output, j) as type string::string** @;
			printf("%s\n", string::data(line));
		}
		printf("\n"); */
	}

	type tck::env* mod_env = module_context->e;
	bool is_empty_module = mod_env == NULL as type tck::env*;
	type util::symtab* no_symtab = NULL as type util::symtab*;

	gen_mod_info(string::new_string(MOD_SYMBOLS_HEADER), mod_env,
		is_empty_module ? no_symtab : mod_env->global_scope.sym_2_typ_var, ret);
	gen_mod_info(string::new_string(MOD_TYPES_HEADER), mod_env,
		is_empty_module ? no_symtab : mod_env->global_scope.typ_2_typ_var, ret);
	gen_mod_info(string::new_string(MOD_DATATYPES_HEADER), mod_env,
		is_empty_module ? no_symtab : mod_env->global_scope.datatyp_2_typ_var, ret);
	gen_mod_info(string::new_string(MOD_DATATYPE_CONSTRUCTORS_HEADER), mod_env,
		is_empty_module ? no_symtab : mod_env->global_scope.datatyp_constructor_2_typ_var, ret);

	type string::string* submodules_header = string::new_string(MOD_SUBMODULES_HEADER);
	util::maybe_report_ice(!vector::append(ret, submodules_header$ as byte*) as bool,
		"Could not add module submodules header to the .mod file's output!");
	for (unsigned int i = 0; i < util::symtab_num_entries(module_context->submodules); i++) {
		type tck::module* submodule = vector::at(module_context->submodules->values, i)
			as type tck::module** @;
		type string::string* submodule_member = string::new_string("\t");
		submodule_member = string::addc(submodule_member, submodule->module_name);
		util::maybe_report_ice(!vector::append(ret, submodule_member$ as byte*) as bool,
			"Could not add name of submodule to the .mod file's output!");
	}

	type string::string* imported_modules_header = string::new_string(MOD_IMPORTED_MODULES_HEADER);
	util::maybe_report_ice(!vector::append(ret, imported_modules_header$ as byte*) as bool,
		"Could not add module imported modules header to the .mod file's output!");
	for (unsigned int i = 0; i < util::symtab_num_entries(module_context->imported_modules); i++) {
		char* name = vector::at(module_context->imported_modules->keys, i) as char** @;
		type string::string* imported_module_name = string::new_string("\t");
		imported_module_name = string::addc(imported_module_name, name);
		util::maybe_report_ice(!vector::append(ret, imported_module_name$ as byte*) as bool,
			"Could not add name of imported module to the .mod file's output!");
	}

	type string::string* mod_file_name = tck::extract_module_name(module_context, MOD_FILE_SEP);
	mod_file_name = string::addc(mod_file_name, ".mod");

	if (copts->to_stdout) {
		printf("%s\n", string::data(mod_file_name));
		for (unsigned int i = 0; i < vector::size(ret); i++) {
			type string::string* s = vector::at(ret, i) as type string::string** @;
			printf("%s\n", string::data(s));
		}
		printf("\n");
	}
	else {
		type string::string* output_path = util::path_cat(GLOBAL_MOD_DIR,
			string::data(mod_file_name));
		direct_truncate(string::data(output_path), 0);
		util::append_lines(string::data(output_path), ret);
	}
}

func[static] bool is_valid_module_name(type string::string* module_name) {
	if (string::length(module_name) == 0)
		return false;
	else {
		char first = string::at(module_name, 0);
		if (!isalpha(first) && first != '_')
			return false;
		for (unsigned int i = 1; i < string::length(module_name); i++) {
			char curr = string::at(module_name, i);
			if (!isalnum(first) && first != '_')
				return false;
		}
	}
	return true;
}

func type vector::vector* compile_module(char* module_root, type compile_options* copts) {
	type vector::vector* outputs = vector::new_vector(sizeof{type compile_module_output*});

	type compile_module_output* cout = malloc(sizeof{type compile_module_output}) as type compile_module_output*;
	cout->output = vector::new_vector(sizeof{type module_file_output*});
	cout->module_root = string::new_string(module_root);
	cout->success = true;

	util::maybe_report_ice(!vector::append(outputs, cout$ as byte*) as bool,
		"Could not add module metadata to output list!");

	type util::dir_entries* dents = util::list_dir(module_root);
	if (dents == NULL as type util::dir_entries*) {
		printf("Could not read module directory!\n");
		cout->success = false;
		return outputs;
	}

	cout->module_name = util::basename(module_root);
	if (!(cout->success = is_valid_module_name(cout->module_name))) {
		printf("The name of the module should be a valid identifier; found '%s'.",
			string::data(cout->module_name));
		return outputs;
	}

	type module_config* mod_conf = parse_module_config(module_root, string::data(cout->module_name));
	if (mod_conf == NULL as type module_config*) {
		printf("Could not parse module config (if one was provided)!\n");
		cout->success = false;
		return outputs;
	}
	cout->module_cfg = mod_conf;

	type tck::module* curr_module = malloc(sizeof{type tck::module}) as type tck::module*;
	tck::init_module(curr_module, string::data(cout->module_name),
		copts->module_context, copts->module_context->global_module,
		cout->module_cfg->visibility);
	cout->module_context = curr_module;

	type compile_options tmp_copts;
	tmp_copts.rt_debug = copts->rt_debug;
	tmp_copts.stop_stage = copts->stop_stage;
	tmp_copts.module_context = curr_module;
	tmp_copts.add_entry_point = copts->add_entry_point;
	tmp_copts.to_stdout = copts->to_stdout;
	tmp_copts.verbose = copts->verbose;

	// "randomize" the namespace names (should be good enough)
	type timeval tv;
	direct_gettimeofday(tv$, NULL as type timezone*);
	srand(tv.tv_sec ^ tv.tv_usec);

	type string::string* src_file_path = string::new_string(GLOBAL_SRC_DIR);
	{
		type tck::module* iter = curr_module;
		type string::string* module_hierarchy = string::new_string("");
		while (iter != curr_module->global_module) {
			module_hierarchy = util::path_cat(iter->module_name,
				string::data(module_hierarchy));
			iter = iter->parent_module;
		}
		src_file_path = util::path_cat(string::data(src_file_path),
			string::data(module_hierarchy));
	}

	if (!copts->to_stdout)
		direct_mkdir(string::data(src_file_path), 0o777);

	for (unsigned int i = 0; i < vector::size(dents->dirs); i++) {
		type string::string* dir = vector::at(dents->dirs, i) as type string::string** @;
		if (string::eqc(dir, ".") || string::eqc(dir, ".."))
			continue;

		type compile_options* sub_copts = malloc(sizeof{type compile_options})
			as type compile_options*;
		sub_copts->rt_debug = copts->rt_debug;
		sub_copts->stop_stage = copts->stop_stage;
		sub_copts->module_context = curr_module;
		sub_copts->add_entry_point = copts->add_entry_point;
		sub_copts->namespace_name = copts->namespace_name;
		sub_copts->to_stdout = copts->to_stdout;
		sub_copts->verbose = copts->verbose;

		type string::string* subdir = util::path_cat(module_root, string::data(dir));
		type vector::vector* tmp = compile_module(string::data(subdir), sub_copts);
		for (unsigned int j = 0; j < vector::size(tmp); j++) {
			type compile_module_output* tmp_cout = vector::at(tmp, j)
				as type compile_module_output** @;
			util::maybe_report_ice(!vector::append(outputs, tmp_cout$ as byte*) as bool,
				"Could not add submodule metadata to output list!");

			if (tmp_cout->success) {
				util::symtab_set(curr_module->submodules,
					tmp_cout->module_context->module_name$ as byte*,
					tmp_cout->module_context$ as byte*);
			}
		}
	}

	for (unsigned int i = 0; i < vector::size(dents->files); i++) {
		type string::string* file = vector::at(dents->files, i) as type string::string** @;

		bool is_sp_resource = false;
		for (unsigned int i = 0; i < vector::size(mod_conf->sp_resources); i++) {
			type string::string* curr_sp_resource = vector::at(mod_conf->sp_resources, i) as type string::string** @;
			if (string::eq(curr_sp_resource, file)) {
				is_sp_resource = true;
				break;
			}
		}

		type string::string* module_file_path = util::path_cat(module_root,
			string::data(file));

		if (mod_conf->src_visibility && !copts->to_stdout) {
			type string::string* curr_file_path = util::path_cat(
				string::data(src_file_path), string::data(file));
			direct_truncate(string::data(curr_file_path), 0);
			util::append_lines(string::data(curr_file_path),
				util::read_lines(string::data(module_file_path)));
		}

		if (string::ceq(MOD_SDW_CFG, file)) continue;
		if (is_sp_resource) continue;

		tmp_copts.namespace_name = string::addc(copts->namespace_name, cgen::itoa(rand()));
		type compile_output* tmp_cout = compile_file(string::data(module_file_path), tmp_copts$);
		// tck::print_tck_ctx(tmp_copts.module_context->e);
		if (!tmp_cout->success) {
			cout->success = false;
			break;
		}
		else {
			type module_file_output* mfo = malloc(sizeof{type module_file_output}) as type module_file_output*;
			mfo->file_name = module_file_path;
			mfo->output = tmp_cout->output;
			mfo->namespace_name = tmp_copts.namespace_name;
			util::maybe_report_ice(!vector::append(cout->output, mfo$ as byte*) as bool,
				"Could not keep track of a file output in a module!");
		}

		/* tck::print_env_symtab(copts->module_context->e, copts->module_context->e->global_scope.datatyp_2_typ_var);
		tck::print_env_symtab(copts->module_context->e, copts->module_context->e->global_scope.datatyp_constructor_2_typ_var);

		type vector::vector* tests = vector::new_vector(sizeof{type string::string*});
		tck::gen_tck_symbols(tmp_copts.module_context->e, tests, true);
		for (unsigned int j = 0; j < vector::size(tests); j++) {
			type string::string* s = vector::at(tests, j) as type string::string** @;
			printf("%s\n", string::data(s));
		} */
	}

	write_module_metadata(cout, copts);

	return outputs;
}

func bool cleanup_module_outputs(type vector::vector* outputs) {
	if (vector::size(outputs) == 0) return true;

	bool success_check = true;
	for (unsigned int index = vector::size(outputs); index > 0; index--) {
		unsigned int i = index - 1;
		type compile_module_output* cout = vector::at(outputs, i)
			as type compile_module_output** @;

		type string::string* full_mod_name = tck::extract_module_name(
			cout->module_context, MOD_FILE_SEP);
		type string::string* mod_file_name = util::path_cat(
			GLOBAL_MOD_DIR, string::data(full_mod_name));
		mod_file_name = string::addc(mod_file_name, ".");
		mod_file_name = string::addc(mod_file_name, MOD_FILE_EXT);

		success_check = util::delete_file(string::data(mod_file_name))
			&& success_check;

		type string::string* mod_src_root = tck::extract_module_name(
			cout->module_context, util::PATH_SEP);
		type string::string* full_mod_src_path = util::path_cat(
			GLOBAL_SRC_DIR, string::data(mod_src_root));

		success_check = util::delete_dir(string::data(full_mod_src_path), true)
			&& success_check;
	}

	return success_check;
}

func bool write_module_output(const char* output_dir,
	type stdx::vector::vector::vector* outputs) {
	bool success_check = direct_mkdir(output_dir, 0o777) == 0;
	for (unsigned int i = 0; i < vector::size(outputs); i++) {
		type compile_module_output* cout = vector::at(outputs, i)
			as type compile_module_output** @;
		type string::string* full_mod_name = tck::extract_module_name(
			cout->module_context, MOD_FILE_SEP);
		type string::string* curr_mod_path = util::path_cat(
			output_dir, string::data(full_mod_name));

		success_check = direct_mkdir(string::data(curr_mod_path), 0o777) == 0
			&& success_check;

		for (unsigned int j = 0; j < vector::size(cout->output); j++) {
			type module_file_output* mfo = vector::at(cout->output, j)
				as type module_file_output** @;
			type string::string* file_name = util::basename(
				string::data(mfo->file_name));

			type string::string* new_file_name = util::path_cat(
				string::data(curr_mod_path), string::data(file_name));
			new_file_name = string::addc(new_file_name, ".sp");

			success_check = util::append_lines(
					string::data(new_file_name), mfo->output)
				&& success_check;
		}

		for (unsigned int j = 0; j < vector::size(cout->module_cfg->sp_resources); j++) {
			type string::string* sp = vector::at(cout->module_cfg->sp_resources, j)
				as type string::string** @;
			type string::string* old_file_name = util::path_cat(
				string::data(cout->module_root), string::data(sp));
			type string::string* new_file_name = util::path_cat(
				string::data(curr_mod_path), string::data(sp));
			new_file_name = string::addc(new_file_name, ".sp");

			char* sp_read = util::read_file(string::data(old_file_name));
			success_check = sp_read != NULL as char* && success_check;
			if (sp_read != NULL as char*) {
				success_check = util::write_file(string::data(new_file_name),
						sp_read) && success_check;
			}
		}
	}
	return success_check;
}

func[static] void gen_mod_compilation_commands(type vector::vector* outputs,
	type string::string* src, type string::string* asm,
	type string::string* o) {
	type string::string* to_asm = string::new_string("spectre ");
	to_asm = string::add(to_asm, src);

	type string::string* to_o = string::new_string(
		"as -mfloat-abi=hard -mfpu=vfp ");
	to_o = string::add(to_o, asm);
	to_o = string::addc(to_o, " -o ");
	to_o = string::add(to_o, o);

	util::maybe_report_ice(!vector::append(outputs, to_asm$ as byte*) as bool,
		"Could not keep track of module file compilation command!");
	util::maybe_report_ice(!vector::append(outputs, to_o$ as byte*) as bool,
		"Could not keep track of module file assembler command!");
}

func type vector::vector* gen_mod_compile_script(
	const char* output_dir, type vector::vector* outputs) {
	type vector::vector* ret = vector::new_vector(sizeof{type string::string*});

	type string::string* shebang = string::new_string("#!/bin/bash");
	util::maybe_report_ice(!vector::append(ret, shebang$ as byte*) as bool,
		"Cannot add shebang for a module compilation script!");
	type string::string* echo_on = string::new_string("set -x");
	util::maybe_report_ice(!vector::append(ret, echo_on$ as byte*) as bool,
		"Cannot enable echo'ing for a module compilation script!");

	for (unsigned int i = 0; i < vector::size(outputs); i++) {
		type compile_module_output* cout = vector::at(outputs, i)
			as type compile_module_output** @;
		type string::string* full_mod_name = tck::extract_module_name(
			cout->module_context, MOD_FILE_SEP);
		type string::string* curr_mod_path = util::path_cat(
			output_dir, string::data(full_mod_name));
		type string::string* static_lib = string::addc(full_mod_name, ".a");
		static_lib = util::path_cat(GLOBAL_LIB_DIR, string::data(static_lib));

		type string::string* ar_command = string::new_string("ar rcs ");
		ar_command = string::add(ar_command, static_lib);
		
		for (unsigned int j = 0; j < vector::size(cout->output); j++) {
			type module_file_output* mfo = vector::at(cout->output, j)
				as type module_file_output** @;
			type string::string* file_name = util::basename(
				string::data(mfo->file_name));

			type string::string* full_file_name = util::path_cat(
				string::data(curr_mod_path), string::data(file_name));
			type string::string* full_src_file_name =
				string::addc(full_file_name, ".sp"),
				full_asm_file_name = 
					string::addc(full_file_name, ".s"),
				full_o_file_name =
					string::addc(full_file_name, ".o");
			
			/* printf("---\nsrc: %s\nasm: %s\no: %s\n---\n",
				string::data(full_src_file_name),
				string::data(full_asm_file_name),
				string::data(full_o_file_name)); */
			gen_mod_compilation_commands(ret, full_src_file_name,
				full_asm_file_name, full_o_file_name);
			ar_command = string::addc(ar_command, " ");
			ar_command = string::add(ar_command, full_o_file_name);
		}

		for (unsigned int j = 0; j < vector::size(cout->module_cfg->sp_resources); j++) {
			type string::string* sp = vector::at(cout->module_cfg->sp_resources, j)
				as type string::string** @;
			
			type string::string* full_file_name = util::path_cat(
				string::data(curr_mod_path), string::data(sp));
			type string::string* full_src_file_name = full_file_name,
				full_asm_file_name =
					string::addc(full_file_name, ".s"),
				full_o_file_name =
					string::addc(full_file_name, ".o");
			full_src_file_name = string::addc(full_src_file_name, ".sp");

			/* printf("---\nsrc: %s\nasm: %s\no: %s\n---\n",
				string::data(full_src_file_name),
				string::data(full_asm_file_name),
				string::data(full_o_file_name)); */
			gen_mod_compilation_commands(ret, full_src_file_name,
				full_asm_file_name, full_o_file_name);
			ar_command = string::addc(ar_command, " ");
			ar_command = string::add(ar_command, full_o_file_name);
		}

		util::maybe_report_ice(!vector::append(ret, ar_command$ as byte*) as bool,
			"Could not add ar command to create static library for module!");
	}
	return ret;
}

} } // namespace shadow::compile
