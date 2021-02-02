import "src/frontend.hsp"

import <"stdx/string">
import <"stdx/vector">
import <"std/string">
import <"std/lib">
import <"std/io">
import <"std/syscall">

import "util/symtab.hsp"
import "util/file.hsp"
import "util/command_line/command_line.hsp"
import "src/compile.hsp"
import "util/error.hsp"
import "cgen/util.hsp"
import "tck/debug.hsp"
import "tck/util.hsp"

namespace command_line = shadow::util::command_line;

using namespace stdx::string;
using namespace stdx::vector;
using std::lib::NULL;
using std::io::printf;
using std::string::strcmp;
using std::lib::qsort;
using std::syscall::direct_truncate;
using std::syscall::direct_chmod;
using std::syscall::S_IRUSR;
using std::syscall::S_IWUSR;
using std::syscall::S_IXUSR;
using std::syscall::S_IRGRP;
using std::syscall::S_IXGRP;
using std::syscall::S_IROTH;
using std::syscall::S_IXOTH;
using std::syscall::direct_mkdir;

namespace shadow { namespace frontend {

static const char* DEFAULT_NAMESPACE_NAME = "myprog";

static const char* VERSION = "alpha 0.1",
	AUTHOR = "Nikhil Athreya <nathreya@stanford.edu>";

static const char* COMPILE_NAME = "shadow compile";
static const char* COMPILE_USAGE =
	"Compiles an input file.\n"
	"\n"
	"USAGE:\n"
	"\tshadow compile [OPTIONS] <INPUT>\n"
	"\n"
	"FLAGS:\n"
	"\t-h, --help:\tPrints this message.\n"
	"\t-d, --debug:\tGenerate code that prints an execution trace while running (defaults to false).\n"
	"\t-m, --module:\tCompiles a module (defaults to false).\n"
	"\t-v, --verbose:\tVerbose output while compiling (mainly for debugging purposes).\n"
	"\n"
	"OPTIONS:\n"
	"\t-o, --output <FILE>:\tSets the name of the output file (defaults to 'a.sp' or 'mod').\n"
	"\t-b, --build_script <FILE>:\tSets the name of the output build script (defaults to 'build.sh' or 'mod_build.sh').\n"
	"\n"
	"ARGS:\n"
	"\tINPUT:\tThe input file to compile.\n";
func[static] type command_line::subcommand* create_compile_subcommand() {
	type command_line::command_metadata* compile_subcommand_metadata = command_line::create_command_metadata(
		string::new_string(COMPILE_NAME),
		string::new_string(VERSION),
		string::new_string(AUTHOR),
		string::new_string(COMPILE_USAGE)
	);

	type vector::vector* compile_subcommand_arguments = command_line::create_arguments(
		7,
		command_line::create_argument(
			'h', true,
			string::new_string("help"),
			false, command_line::argument_kind::FLAG
		),
		command_line::create_argument(
			'd', true,
			string::new_string("debug"),
			false, command_line::argument_kind::FLAG
		),
		command_line::create_argument(
			'o', true,
			string::new_string("output"),
			false, command_line::argument_kind::NAMED
		),
		command_line::create_argument(
			'm', true,
			string::new_string("module"),
			false, command_line::argument_kind::FLAG
		),
		command_line::create_argument(
			'v', true,
			string::new_string("verbose"),
			false, command_line::argument_kind::FLAG
		),
		command_line::create_argument(
			'b', true,
			string::new_string("build_script"),
			false, command_line::argument_kind::NAMED
		),
		command_line::create_argument(
			'-', false,
			string::new_string("INPUT"),
			true, command_line::argument_kind::POSITIONAL
		)
	);

	return command_line::create_subcommand(
		compile_subcommand_metadata,
		string::new_string("compile"),
		compile_subcommand_arguments,
		command_line::create_subcommands(0)
	);
}

static const char* TEST_NAME = "shadow test";
static const char* TEST_USAGE =
	"Tests the shadow compiler.\n"
	"\n"
	"USAGE:\n"
	"\tshadow test [OPTIONS] <DIR>\n"
	"\n"
	"FLAGS:\n"
	"\t-h, --help:\tPrints this message.\n"
	"\t-r, --reverse:\tTests files in reverse sorted order (defaults to sorted order).\n"
	"\n"
	"OPTIONS:\n"
	"\t-s, --stage <STAGE>:\tOne of 'tck' (typechecker) or 'rt' (runtime); defaults to 'rt'.\n"
	"\t-o, --output <FILE>:\tSpecifies the output file/directory (defaults to `<STAGE>_outputs`).\n"
	"\n"
	"ARGS:\n"
	"\tDIR:\tThe directory with all the test inputs.\n";
func[static] type command_line::subcommand* create_test_subcommand() {
	type command_line::command_metadata* test_subcommand_metadata = command_line::create_command_metadata(
		string::new_string(TEST_NAME),
		string::new_string(VERSION),
		string::new_string(AUTHOR),
		string::new_string(TEST_USAGE)
	);

	type vector::vector* test_subcommand_arguments = command_line::create_arguments(
		5,
		command_line::create_argument(
			'h', true,
			string::new_string("help"),
			false, command_line::argument_kind::FLAG
		),
		command_line::create_argument(
			'r', true,
			string::new_string("reverse"),
			false, command_line::argument_kind::FLAG
		),
		command_line::create_argument(
			's', true,
			string::new_string("stage"),
			false, command_line::argument_kind::NAMED
		),
		command_line::create_argument(
			'o', true,
			string::new_string("output"),
			false, command_line::argument_kind::NAMED
		),
		command_line::create_argument(
			'-', false,
			string::new_string("DIR"),
			false, command_line::argument_kind::POSITIONAL
		)
	);

	return command_line::create_subcommand(
		test_subcommand_metadata,
		string::new_string("test"),
		test_subcommand_arguments,
		command_line::create_subcommands(0)
	);
}

static const char* HELP_NAME = "shadow help";
static const char* HELP_USAGE = 
	"Prints help information.\n"
	"\n"
	"USAGE:\n"
	"\tshadow help [OPTIONS]\n"
	"\n"
	"FLAGS:\n"
	"\t-h, --help:\tPrints this message.\n";
func[static] type command_line::subcommand* create_help_subcommand() {
	type command_line::command_metadata* help_subcommand_metadata = command_line::create_command_metadata(
		string::new_string(HELP_NAME),
		string::new_string(VERSION),
		string::new_string(AUTHOR),
		string::new_string(HELP_USAGE)
	);

	type vector::vector* help_subcommand_arguments = command_line::create_arguments(
		1,
		command_line::create_argument(
			'h', true,
			string::new_string("help"),
			false, command_line::argument_kind::FLAG
		)
	);

	return command_line::create_subcommand(
		help_subcommand_metadata,
		string::new_string("help"),
		help_subcommand_arguments,
		command_line::create_subcommands(0)
	);
}

static const char* VERSION_NAME = "shadow version";
static const char* VERSION_USAGE = 
	"Prints version information.\n"
	"\n"
	"USAGE:\n"
	"\tshadow version [OPTIONS]\n"
	"\n"
	"FLAGS:\n"
	"\t-h, --help:\tPrints this message.\n";
func[static] type command_line::subcommand* create_version_subcommand() {
	type command_line::command_metadata* version_subcommand_metadata = command_line::create_command_metadata(
		string::new_string(VERSION_NAME),
		string::new_string(VERSION),
		string::new_string(AUTHOR),
		string::new_string(VERSION_USAGE)
	);

	type vector::vector* version_subcommand_arguments = command_line::create_arguments(
		1,
		command_line::create_argument(
			'h', true,
			string::new_string("help"),
			false, command_line::argument_kind::FLAG
		)
	);

	return command_line::create_subcommand(
		version_subcommand_metadata,
		string::new_string("version"),
		version_subcommand_arguments,
		command_line::create_subcommands(0)
	);
}

static const char* GLOBAL_NAME = "shadow";
static const char* GLOBAL_USAGE =
	"A compiler for the shadow programming language.\n"
	"\n"
	"USAGE:\n"
	"\tshadow [OPTIONS] [SUBCOMMAND]\n"
	"\n"
	"FLAGS:\n"
	"\t-h, --help:\tPrints this message.\n"
	"\t-v, --version:\tPrints version information.\n"
	"\n"
	"SUBCOMMANDS:\n"
	"\tcompile\t\tCompiles an input file.\n"
	"\thelp\t\tPrints help information.\n"
	"\ttest\t\tTests the shadow compiler.\n"
	"\tversion\t\tPrints version information.\n";
func type command_line::command* create() {
	type command_line::command_metadata* global_command_metadata = command_line::create_command_metadata(
		string::new_string(GLOBAL_NAME),
		string::new_string(VERSION),
		string::new_string(AUTHOR),
		string::new_string(GLOBAL_USAGE)
	);

	type vector::vector* global_command_arguments = command_line::create_arguments(
		2,
		command_line::create_argument(
			'h', true,
			string::new_string("help"),
			false, command_line::argument_kind::FLAG
		),
		command_line::create_argument(
			'v', true,
			string::new_string("version"),
			false, command_line::argument_kind::FLAG
		)
	);

	type vector::vector* global_command_subcommands = command_line::create_subcommands(
		4,
		create_compile_subcommand(),
		create_help_subcommand(),
		create_test_subcommand(),
		create_version_subcommand()
	);

	return command_line::create_command(
		global_command_metadata,
		global_command_arguments,
		global_command_subcommands
	);
}

func[static] type command_line::argument_parse_result* lookup_argument(type vector::vector* aprs, char* lookup) {
	type command_line::argument_parse_result* apr = NULL as type command_line::argument_parse_result*;
	for (unsigned int i = 0; i < vector::size(aprs); i++) {
		type command_line::argument_parse_result* curr_apr = vector::at(aprs, i) as type command_line::argument_parse_result** @;
		if (string::ceq(lookup, curr_apr->long_name)) {
			apr = curr_apr;
			break;
		}
	}
	return apr;
}

func[static] int files_sort_cmp(const byte* f1, const byte* f2) {
	type string::string* sf1 = f1 as type string::string** @,
		sf2 = f2 as type string::string** @;
	if (string::lt(sf1, sf2)) return -1;
	else if (string::gt(sf1, sf2)) return 1;
	else return 0;
}

func[static] int files_rev_sort_cmp(const byte* f1, const byte* f2) {
	type string::string* sf1 = f1 as type string::string** @,
		sf2 = f2 as type string::string** @;
	if (string::lt(sf1, sf2)) return 1;
	else if (string::gt(sf1, sf2)) return -1;
	else return 0;
}

static char* DEFAULT_FILE_OUT = "a";
static char* DEFAULT_MOD_OUT = "mod_build";
static char* DEFAULT_FILE_BUILD_SCRIPT = "build.sh";
static char* DEFAULT_MOD_BUILD_SCRIPT = "mod_build.sh";
func int process_request(type command_line::command_parse_result* cpr) {
	if (!cpr->valid) return 1;

	type command_line::argument_parse_result* global_help_check = lookup_argument(cpr->argument_results, "help");
	if (global_help_check != NULL as type command_line::argument_parse_result*) {
		command_line::print_usage(cpr->metadata);
		return 0;
	}

	type command_line::argument_parse_result* global_version_check = lookup_argument(cpr->argument_results, "version");
	if (global_version_check != NULL as type command_line::argument_parse_result*) {
		command_line::print_version(cpr->metadata);
		return 0;
	}

	if (cpr->subcommand_result == NULL as type command_line::subcommand_parse_result*) {
		type string::string* error = string::new_string("Expected a subcommand or an option!");
		command_line::maybe_print_error_and_usage(cpr->metadata, error);
		return 1;
	}

	type command_line::subcommand_parse_result* spr = cpr->subcommand_result;
	if (string::ceq("compile", spr->name)) {
		type command_line::argument_parse_result* compile_help_check = lookup_argument(spr->argument_results, "help");
		if (compile_help_check != NULL as type command_line::argument_parse_result*) {
			command_line::print_usage(spr->metadata);
			return 0;
		}

		type command_line::argument_parse_result* compile_input_check = lookup_argument(spr->argument_results, "INPUT");
		if (compile_input_check == NULL as type command_line::argument_parse_result*
			|| compile_input_check->num != 1) {
			type string::string* error = string::new_string("Expected one input file to compile!");
			command_line::maybe_print_error_and_usage(spr->metadata, error);
			return 1;
		}
		char* input_file_name = string::data(vector::at(compile_input_check->data, 0) as type string::string** @);

		type command_line::argument_parse_result* compile_module_check = lookup_argument(spr->argument_results, "module");
		bool module;
		if (compile_module_check == NULL as type command_line::argument_parse_result*)
			module = false;
		else
			module = true;

		type command_line::argument_parse_result* compile_build_script_check = lookup_argument(spr->argument_results, "build_script");
		char* build_script_name;
		if (compile_build_script_check == NULL as type command_line::argument_parse_result*) {
			if (module)
				build_script_name = DEFAULT_MOD_BUILD_SCRIPT;
			else
				build_script_name = DEFAULT_FILE_BUILD_SCRIPT;
		}
		else {
			util::maybe_report_ice(compile_build_script_check->num == 1,
				"Expected just a single build script file specified!");
			type string::string* bsn_str = vector::at(compile_build_script_check->data, 0) as type string::string** @;
			build_script_name = string::data(bsn_str);
		}

		type command_line::argument_parse_result* compile_output_check = lookup_argument(spr->argument_results, "output");
		char* output_file_name;
		if (compile_output_check == NULL as type command_line::argument_parse_result*) {
			if (module)
				output_file_name = DEFAULT_MOD_OUT;
			else
				output_file_name = DEFAULT_FILE_OUT;
		}
		else {
			util::maybe_report_ice(compile_output_check->num == 1,
				"Expected just a single output file specified!");
			type string::string* ofn_str = vector::at(compile_output_check->data, 0) as type string::string** @;
			output_file_name = string::data(ofn_str);
		}

		type command_line::argument_parse_result* compile_debug_check = lookup_argument(spr->argument_results, "debug");
		bool debug;
		if (compile_debug_check == NULL as type command_line::argument_parse_result*)
			debug = false;
		else
			debug = true;

		type command_line::argument_parse_result* compile_verbose_check = lookup_argument(spr->argument_results, "verbose");
		bool verbose;
		if (compile_verbose_check == NULL as type command_line::argument_parse_result*)
			verbose = false;
		else
			verbose = true;

		printf("Building (%s -> %s|%s) [%s] (%s%s)...\n", input_file_name, output_file_name, build_script_name,
			module ? "module" : "standalone", debug ? "debug" : "non-debug",
			verbose ? ",verbose" : "");

		type tck::module global_module;
		tck::init_module(global_module$, "", NULL as type tck::module*, global_module$, true);

		type compile::compile_options copts;
		copts.rt_debug = debug;
		copts.stop_stage = compile::stage_kind::CGEN;
		copts.module_context = global_module$;
		copts.add_entry_point = !module;
		copts.namespace_name = string::new_string(DEFAULT_NAMESPACE_NAME);
		copts.to_stdout = strcmp(output_file_name, ">") == 0;
		copts.verbose = verbose;

		if (!module) {
			type compile::compile_output* cout = compile::compile_file(input_file_name, copts$);
			if (!cout->success) return 1;

			if (copts.to_stdout) {
				for (unsigned int i = 0; i < vector::size(cout->output); i++) {
					type string::string* line = vector::at(cout->output, i) as type string::string** @;
					printf("%s\n", string::data(line));
				}
			}
			else {
				direct_truncate(output_file_name, 0);
				if (!util::append_lines(output_file_name, cout->output)) {
					type string::string* error = string::new_string("Could not write compilation output to output file!");
					command_line::maybe_print_error_and_usage(spr->metadata, error);
					return 1;
				}
			}

			type vector::vector* file_compile_script = compile::gen_file_compile_script(
				output_file_name, global_module$);

			direct_truncate(build_script_name, 0);
			if (!util::append_lines(build_script_name, file_compile_script)) {
				printf("Could not write file compile script!");
				return 1;
			}

			if (direct_chmod(build_script_name, S_IRUSR | S_IWUSR | S_IXUSR
				| S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) < 0) {
				printf("Could not set file compile script as executable!");
				return 1;
			}
		}
		else {
			if (copts.to_stdout) {
				printf("Warning: compiling a module while outputting to stdout will not work for "
					"modules with submodule-to-parent-module dependencies!\n");
			}

			type vector::vector* outputs = compile::compile_module(input_file_name, copts$);
			bool success_check = true;
			for (unsigned int i = 0; i < vector::size(outputs); i++) {
				type compile::compile_module_output* cout = vector::at(outputs, i)
					as type compile::compile_module_output** @;
				if (!cout->success) {
					success_check = false;
					break;
				}
			}

			if (!success_check) {
				compile::cleanup_module_outputs(outputs);
				return 1;
			}

			if (copts.to_stdout) return 0;

			success_check = compile::write_module_output(output_file_name, outputs);
			if (!success_check) {
				printf("Could not write all output files successfully.");
				return 1;
			}

			type vector::vector* mod_compile_script = compile::gen_mod_compile_script(
				output_file_name, outputs);

			
			direct_truncate(build_script_name, 0);
			if (!util::append_lines(build_script_name, mod_compile_script)) {
				printf("Could not write module compile script!");
				return 1;
			}

			if (direct_chmod(build_script_name, S_IRUSR | S_IWUSR | S_IXUSR
				| S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) < 0) {
				printf("Could not set module compile script as executable!");
				return 1;
			}
		}
	}
	else if (string::ceq("help", spr->name)) {
		type command_line::argument_parse_result* help_help_check = lookup_argument(spr->argument_results, "help");
		if (help_help_check != NULL as type command_line::argument_parse_result*)
			command_line::print_usage(spr->metadata);
		else
			command_line::print_usage(cpr->metadata);
	}
	else if (string::ceq("test", spr->name)) {
		type command_line::argument_parse_result* test_help_check = lookup_argument(spr->argument_results, "help");
		if (test_help_check != NULL as type command_line::argument_parse_result*) {
			command_line::print_usage(spr->metadata);
			return 0;
		}

		type command_line::argument_parse_result* test_dir_check = lookup_argument(spr->argument_results, "DIR");
		if (test_dir_check == NULL as type command_line::argument_parse_result*
			|| test_dir_check->num != 1) {
			type string::string* error = string::new_string("Expected one input directory to be specified!");
			command_line::maybe_print_error_and_usage(spr->metadata, error);
			return 0;
		}
		char* input_dir_name = string::data(vector::at(test_dir_check->data, 0) as type string::string** @);

		char* input_stage_name = "rt";
		unsigned int stage_kind = compile::stage_kind::CGEN;
		type command_line::argument_parse_result* test_stage_check = lookup_argument(spr->argument_results, "stage");
		if (test_stage_check != NULL as type command_line::argument_parse_result*) {
			if (test_stage_check->num != 1) {
				type string::string* error = string::new_string("Expected one stage to test!");
				command_line::maybe_print_error_and_usage(spr->metadata, error);
				return 1;
			}

			input_stage_name = string::data(vector::at(test_stage_check->data, 0) as type string::string** @);
			if (strcmp(input_stage_name, "rt") == 0)
				stage_kind = compile::stage_kind::CGEN;
			else if (strcmp(input_stage_name, "tck") == 0)
				stage_kind = compile::stage_kind::TCK;
			else {
				type string::string* error = string::new_string("Unrecognized stage name: '");
				error = string::addc(error, input_stage_name);
				error = string::addc(error, "'; expected one of 'tck' or 'rt'.");
				command_line::maybe_print_error_and_usage(spr->metadata, error);
				return 1;
			}
		}

		type string::string* str_input_output_name = string::new_string(input_stage_name);
		str_input_output_name = string::addc(str_input_output_name, "_outputs");
		char* input_output_name = string::data(str_input_output_name);
		type command_line::argument_parse_result* test_output_check = lookup_argument(spr->argument_results, "output");
		if (test_output_check != NULL as type command_line::argument_parse_result*) {
			if (test_output_check->num != 1) {
				type string::string* error = string::new_string("Expected one file to be outputted to!");
				command_line::maybe_print_error_and_usage(spr->metadata, error);
				return 1;
			}

			input_output_name = string::data(vector::at(test_output_check->data, 0) as type string::string** @);
		}

		type command_line::argument_parse_result* test_reverse_check = lookup_argument(spr->argument_results, "reverse");
		bool reverse = false;
		if (test_reverse_check != NULL as type command_line::argument_parse_result*)
			reverse = true;

		type util::dir_entries* dents = util::list_dir(input_dir_name);
		if (dents == NULL as type util::dir_entries*) {
			type string::string* error = string::new_string("Could not list test directory!");
			command_line::maybe_print_error_and_usage(spr->metadata, error);
			return 1;
		}
		type vector::vector* files = dents->files;

		printf("Testing '%s' [%u files] (%s -> %s) (%s order)...\n", input_stage_name, vector::size(files), input_dir_name, input_output_name, reverse ? "reverse" : "normal");

		qsort(vector::data(files), vector::size(files), vector::unit(files), reverse ? files_rev_sort_cmp : files_sort_cmp);

		type tck::module global_module;
		tck::init_module(global_module$, "", NULL as type tck::module*, global_module$, true);

		type compile::compile_options copts;
		copts.add_entry_point = true;
		copts.stop_stage = stage_kind;
		copts.rt_debug = true;
		copts.module_context = global_module$;
		copts.namespace_name = string::new_string(DEFAULT_NAMESPACE_NAME);
		copts.verbose = false;
		type string::string* sep = string::new_string("---------------------------------------------------");

		if (stage_kind == compile::stage_kind::CGEN) {
			direct_mkdir(input_output_name, 0o777);
		}

		for (unsigned int i = 0; i < vector::size(files); i++) {
			type string::string* file = vector::at(files, i) as type string::string** @;

			printf("%s [%u/%u]\n", string::data(file), i + 1, vector::size(files));

			copts.module_context->e = NULL as type tck::env*;

			type string::string* full_file_name = string::new_string(input_dir_name);
			if (string::data(full_file_name)[string::length(full_file_name) - 1] != '/')
				full_file_name = string::addch(full_file_name, '/');
			full_file_name = string::add(full_file_name, file);

			type vector::vector* curr_output = vector::new_vector(sizeof{type string::string*});
			type string::string* header = string::new_string("File name: ");
			header = string::add(header, file);

			if (stage_kind == compile::stage_kind::TCK) {
				util::maybe_report_ice(!vector::append(curr_output, sep$ as byte*) as bool,
					"Could not add initial separator for a 'tck' test case output!");
				util::maybe_report_ice(!vector::append(curr_output, header$ as byte*) as bool,
					"Could not add file name for a 'tck' test case output!");
			}

			type compile::compile_output* cout = compile::compile_file(string::data(full_file_name), copts$);
			unsigned int return_value = cout->success ? 0 : 1;

			if (cout->success) {
				for (unsigned int j = 0; j < vector::size(cout->output); j++) {
					type string::string* tmp = vector::at(cout->output, j) as type string::string** @;
					util::maybe_report_ice(!vector::append(curr_output, tmp$ as byte*) as bool,
						"Could not add compilation output ");
				}
			}

			if (stage_kind == compile::stage_kind::TCK) {
				type string::string* footer = string::new_string("Return value: ");
				footer = string::addc(footer, cgen::itoa(return_value));
				util::maybe_report_ice(!vector::append(curr_output, footer$ as byte*) as bool,
					"Could not add 'tck' return value for a test case output!");

				util::maybe_report_ice(!vector::append(curr_output, sep$ as byte*) as bool,
					"Could not add final separator for a 'tck' test case output!");
			}

			type string::string* output_file_name = string::new_string(input_output_name);
			if (stage_kind == compile::stage_kind::CGEN) {
				output_file_name = string::addch(output_file_name, '/');
				output_file_name = string::add(output_file_name, file);
				output_file_name = string::addc(output_file_name, ".sp");
			}

			util::append_lines(string::data(output_file_name), curr_output);
		}
	}
	else if (string::ceq("version", spr->name)) {
		type command_line::argument_parse_result* version_help_check = lookup_argument(spr->argument_results, "help");
		if (version_help_check != NULL as type command_line::argument_parse_result*)
			command_line::print_usage(spr->metadata);
		else
			command_line::print_version(cpr->metadata);
	}
	else
		util::report_ice("Unrecognized subcommand found in the frontend!");

	return 0;
}

} } // namespace shadow::frontend
