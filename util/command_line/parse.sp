import "util/command_line/command_line.hsp"

import <"std/string">
import <"stdx/vector">
import <"stdx/string">
import <"std/lib">
import <"std/io">

import "util/error.hsp"
import "util/command_line/internal.hsp"

using namespace stdx::vector;
using namespace stdx::string;
using std::lib::malloc;
using std::lib::NULL;
using std::io::printf;
using std::string::strlen;
using std::string::strncpy;

namespace shadow { namespace util { namespace command_line {

struct parse_env {
	type vector::vector* argument_results;
	type vector::vector* arguments;

	type command_metadata* metadata;
}

func[static] type argument* find_positional_arg(type vector::vector* arguments) {
	type argument* positional_arg = NULL as type argument*;
	for (unsigned int i = 0; i < vector::size(arguments); i++) {
		type argument* curr_arg = vector::at(arguments, i) as type argument** @;
		if (curr_arg->kind == argument_kind::POSITIONAL) {
			positional_arg = curr_arg;
			break;
		}
	}
	return positional_arg;
}

func void print_version(type command_metadata* c) {
	if (c->name != NULL as type string::string*) {
		printf("%s", string::data(c->name));
		if (c->version != NULL as type string::string*)
			printf(" -- %s", string::data(c->version));
		printf("\n");
	}
}

func void print_usage(type command_metadata* c) {
	print_version(c);

	if (c->author != NULL as type string::string*)
		printf("%s\n", string::data(c->author));

	if (c->usage != NULL as type string::string*)
		printf("%s", string::data(c->usage));
}

func void maybe_print_error_and_usage(type command_metadata* c, type string::string* error) {
	if (error != NULL as type string::string*)
		printf("%s\n", string::data(error));

	print_usage(c);
}

func[static] bool check_argument_validity(int argc, char** argv, unsigned int* pos, type parse_env* pe,
	type argument* ref_argument, int env_num, char* maybe_cmd_line_arg_value) {
	char* cmd_line_arg = argv[pos@];

	if (env_num == -1) {
		type string::string* error = string::new_string("Unrecognized argument '");
		error = string::addc(error, cmd_line_arg);
		error = string::addc(error, "'.");
		maybe_print_error_and_usage(pe->metadata, error);
		return false;
	}

	type argument_parse_result* apr = NULL as type argument_parse_result*;

	bool prev_result = false;
	type vector::vector* selected_argument_results = vector::at(pe->argument_results, env_num) as type vector::vector** @;
	for (unsigned int i = 0; i < vector::size(selected_argument_results); i++) {
		type argument_parse_result* curr_res = vector::at(selected_argument_results, i) as type argument_parse_result** @;
		if (string::eq(curr_res->long_name, ref_argument->long_name)) {
			apr = curr_res;
			prev_result = true;
			break;
		}
	}

	if (apr == NULL as type argument_parse_result*) {
		apr = malloc(sizeof{type argument_parse_result}) as type argument_parse_result*;
		apr->long_name = ref_argument->long_name;
		apr->short_spec = ref_argument->short_spec;
		apr->data = vector::new_vector(sizeof{type string::string*});
		apr->num = 0;

		util::maybe_report_ice(!vector::append(selected_argument_results, apr$ as byte*) as bool,
			"Could not keep track of argument results while parsing command line arguments!");
	}

	if (prev_result && !ref_argument->repeatable) {
		type string::string* error = string::new_string("Argument '");
		error = string::addc(error, cmd_line_arg);
		error = string::addc(error, "' was only expected once.");
		maybe_print_error_and_usage(pe->metadata, error);
		return false;
	}
	apr->num++;

	if (ref_argument->kind == argument_kind::NAMED) {
		char* named_value = maybe_cmd_line_arg_value;
		if (named_value == NULL as char*) {
			pos@++;
			if (pos@ >= argc) {
				type string::string* error = string::new_string("Expected a value after the named argument '");
				error = string::addc(error, cmd_line_arg);
				error = string::addc(error, "'.");
				maybe_print_error_and_usage(pe->metadata, error);
				return false;
			}

			named_value = argv[pos@];
			if (named_value[0] == '-') {
				type string::string* error = string::new_string("Expected a value after the named argument '");
				error = string::addc(error, cmd_line_arg);
				error = string::addc(error, "'; instead found '");
				error = string::addc(error, named_value);
				error = string::addc(error, "'.");
				maybe_print_error_and_usage(pe->metadata, error);
				return false;
			}
		}

		type string::string* str_named_value = string::new_string(named_value);
		util::maybe_report_ice(!vector::append(apr->data, str_named_value$ as byte*) as bool,
			"Could not keep track of value(s) for a named argument while parsing command line arguments!");
	}

	return true;
}

func[static] bool handle_argument(int argc, char** argv, unsigned int* pos, type parse_env* pe) {
	util::maybe_report_ice(pos@ < argc,
		"Invalid command line parse position passed in while trying to handle arguments!");

	char* cmd_line_arg = argv[pos@], orig_cmd_line_arg = cmd_line_arg;

	util::maybe_report_ice(cmd_line_arg[0] == '-',
		"Expected an argument to handle here!");

	unsigned int cmd_line_arg_len = strlen(cmd_line_arg);
	char* maybe_cmd_line_arg_value = NULL as char*;

	char* eq_check = cmd_line_arg;
	for (; eq_check@ != '\0' && eq_check@ != '='; eq_check = eq_check[1]$) {}
	if (eq_check@ == '=') {
		cmd_line_arg_len = eq_check as unsigned int - cmd_line_arg as unsigned int;
		char* cmd_line_arg_tmp = malloc(sizeof{char} * (cmd_line_arg_len + 1)) as char*;
		strncpy(cmd_line_arg_tmp, cmd_line_arg, cmd_line_arg_len);
		cmd_line_arg_tmp[cmd_line_arg_len] = '\0';
		cmd_line_arg = cmd_line_arg_tmp;

		maybe_cmd_line_arg_value = eq_check[1]$;
	}

	if (cmd_line_arg_len > 1 && cmd_line_arg[1] == '-') {
		type argument* ref_argument = NULL as type argument*;
		int env_num = -1;

		char* given_long_name = cmd_line_arg[2]$;
		for (int i = vector::size(pe->arguments) - 1; i >= 0; i--) {
			type vector::vector* curr_arguments = vector::at(pe->arguments, i) as type vector::vector** @;
			for (unsigned int j = 0; j < vector::size(curr_arguments); j++) {
				type argument* curr_arg = vector::at(curr_arguments, j) as type argument** @;
				if (string::eqc(curr_arg->long_name, given_long_name)) {
					ref_argument = curr_arg;
					env_num = i;
					break;
				}
			}
			if (env_num != -1) break;
		}

		if (!check_argument_validity(argc, argv, pos, pe, ref_argument, env_num, maybe_cmd_line_arg_value))
			return false;
	}
	else {
		if (maybe_cmd_line_arg_value != NULL as char* && cmd_line_arg_len != 2) {
			type string::string* error = string::new_string("Cannot pass a value in the same argument as multiple shorthand argument: '");
			error = string::addc(error, orig_cmd_line_arg);
			error = string::addc(error, "'.");
			maybe_print_error_and_usage(pe->metadata, error);
			return false;
		}

		for (unsigned int i = 1; i < cmd_line_arg_len; i++) {
			char given_name = cmd_line_arg[i];

			type argument* ref_argument = NULL as type argument*;
			int env_num = -1;
			for (int j = vector::size(pe->arguments) - 1; j >= 0; j--) {
				type vector::vector* curr_arguments = vector::at(pe->arguments, j) as type vector::vector** @;
				for (unsigned int k = 0; k < vector::size(curr_arguments); k++) {
					type argument* curr_arg = vector::at(curr_arguments, k) as type argument** @;
					if (curr_arg->short_spec.present && curr_arg->short_spec.short_name == given_name) {
						env_num = j;
						ref_argument = curr_arg;
						break;
					}
				}
				if (env_num != -1) break;
			}

			if (env_num == -1) {
				type string::string* error = string::new_string("Unrecognized argument '");
				error = string::addch(error, given_name);
				error = string::addc(error, "'.");
				maybe_print_error_and_usage(pe->metadata, error);
				return false;
			}

			if (ref_argument->kind != argument_kind::FLAG && cmd_line_arg_len != 2) {
				type string::string* error = string::new_string("Cannot specify multiple shorthand, non-flag arguments: '");
				error = string::addch(error, given_name);
				error = string::addc(error, "'.");
				maybe_print_error_and_usage(pe->metadata, error);
				return false;
			}

			if (!check_argument_validity(argc, argv, pos, pe, ref_argument, env_num, maybe_cmd_line_arg_value))
				return false;
		}
	}

	return true;
}

func bool parse_helper(int argc, char** argv, unsigned int* pos, type parse_env* pe, type vector::vector* subcommands, type subcommand_parse_result** scr) {
	type vector::vector* curr_argument_results = vector::at(pe->argument_results, vector::size(pe->argument_results) - 1)
		as type vector::vector** @,
		curr_arguments = vector::at(pe->arguments, vector::size(pe->arguments) - 1) as type vector::vector** @;
	type argument* positional_arg = find_positional_arg(curr_arguments);

	type argument_parse_result* positional_apr = NULL as type argument_parse_result*;
	if (positional_arg != NULL as type argument*) {
		positional_apr = malloc(sizeof{type argument_parse_result}) as type argument_parse_result*;

		positional_apr->long_name = positional_arg->long_name;
		positional_apr->short_spec = positional_arg->short_spec;
		positional_apr->data = vector::new_vector(sizeof{type string::string*});
		positional_apr->num = 0;

		util::maybe_report_ice(!vector::append(curr_argument_results, positional_apr$ as byte*) as bool,
			"Could not keep track of positional argument!");
	}

	while (pos@ < argc) {
		char* arg = argv[pos@];
		if (arg[0] == '-') {
			if (!handle_argument(argc, argv, pos, pe))
				return false;
		}
		else {
			if (positional_arg != NULL as type argument*) {
				type string::string* str_arg = string::new_string(arg);
				util::maybe_report_ice(!vector::append(positional_apr->data, str_arg$ as byte*) as bool,
					"Could not keep track of positional arguments while parsing a command line input!");
				positional_apr->num++;
			}
			else {
				bool found = false;
				for (unsigned int i = 0; i < vector::size(subcommands); i++) {
					type subcommand* sc = vector::at(subcommands, i) as type subcommand** @;
					if (string::eqc(sc->name, arg)) {
						pos@++;
						found = true;
						scr@ = malloc(sizeof{type subcommand_parse_result}) as type subcommand_parse_result*;
						scr@->metadata = sc->metadata;
						scr@->name = sc->name;

						scr@->argument_results = vector::new_vector(sizeof{type argument_parse_result*});
						scr@->next = NULL as type subcommand_parse_result*;
						util::maybe_report_ice(!vector::append(pe->arguments, sc->arguments$ as byte*) as bool,
							"Could not keep track of subcommand arguments while parsing command line input!");
						util::maybe_report_ice(!vector::append(pe->argument_results, scr@->argument_results$ as byte*) as bool,
							"Could not keep track of subcommand argument results while parsing command line input!");

						type command_metadata* old = pe->metadata;
						pe->metadata = sc->metadata;
						bool res = parse_helper(argc, argv, pos, pe, sc->subcommands, scr@->next$);
						pe->metadata = old;
						if (!res) return false;

						break;
					}
				}

				if (!found) {
					type string::string* error = string::new_string("Unrecognized subcommand: '");
					error = string::addc(error, arg);
					error = string::addc(error, "' found.");
					maybe_print_error_and_usage(pe->metadata, error);
					return false;
				}
			}
		}
		pos@++;
	}

	return true;
}

func type command_parse_result* parse(type command* c, int argc, char** argv) {
	type command_parse_result* cpr = malloc(sizeof{type command_parse_result}) as type command_parse_result*;
	cpr->metadata = c->metadata;
	cpr->subcommand_result = NULL as type subcommand_parse_result*;
	cpr->argument_results = vector::new_vector(sizeof{type argument_parse_result*});
	cpr->valid = true;

	if (!validate_command(c)) {
		maybe_print_error_and_usage(c->metadata, string::new_string("Invalid command spec passed in!"));
		cpr->valid = false;
		return cpr;
	}

	type parse_env pe;
	pe.argument_results = vector::new_vector(sizeof{type vector::vector*});
	pe.arguments = vector::new_vector(sizeof{type vector::vector*});
	pe.metadata = c->metadata;

	util::maybe_report_ice(!vector::append(pe.arguments, c->arguments$ as byte*) as bool,
		"Could not keep track of parent argument environments while parsing command line arguments!");
	util::maybe_report_ice(!vector::append(pe.argument_results, cpr->argument_results$ as byte*) as bool,
		"Could not keep track of parent argument results while parsing command line arguments!");

	unsigned int pos = 1;
	cpr->valid = parse_helper(argc, argv, pos$, pe$, c->subcommands, cpr->subcommand_result$);
	return cpr;
}

} } } // namespace shadow::util::command_line
