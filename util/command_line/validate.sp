import "util/command_line/command_line.hsp"
import "util/command_line/internal.hsp"

import <"std/string">
import <"stdx/vector">
import <"stdx/string">
import <"std/lib">
import <"std/io">

import "util/error.hsp"

using namespace stdx::vector;
using namespace stdx::string;
using std::lib::malloc;
using std::lib::NULL;
using std::io::printf;
using std::string::strlen;

namespace shadow { namespace util { namespace command_line {

func bool argument_list_has_positional(type vector::vector* arguments) {
	for (unsigned int i = 0; i < vector::size(arguments); i++) {
		type argument* arg = vector::at(arguments, i) as type argument** @;
		if (arg->kind == argument_kind::POSITIONAL)
			return true;
	}

	return false;
}

func[static] bool validate_arguments(type vector::vector* arguments) {
	if (arguments == NULL as type vector::vector*)
		return true;

	// TODO: These should be hashsets
	type vector::vector* long_names = vector::new_vector(sizeof{type string::string*}),
		short_names = vector::new_vector(sizeof{char});

	bool found_positional = false;
	for (unsigned int i = 0; i < vector::size(arguments); i++) {
		type argument* arg = vector::at(arguments, i) as type argument** @;

		if (arg->kind == argument_kind::POSITIONAL) {
			if (found_positional) return false;
			found_positional = true;
		}

		for (unsigned int j = 0; j < vector::size(long_names); j++) {
			type string::string* curr = vector::at(long_names, j) as type string::string** @;
			if (string::eq(curr, arg->long_name))
				return false;
		}
		util::maybe_report_ice(!vector::append(long_names, arg->long_name$ as byte*) as bool,
			"Could not keep track of long argument names while validating a command line argument parser!");

		if (arg->short_spec.present) {
			for (unsigned int j = 0; j < vector::size(short_names); j++) {
				char curr = vector::at(short_names, j) as char* @;
				if (curr == arg->short_spec.short_name)
					return false;
			}
			util::maybe_report_ice(!vector::append(short_names, arg->short_spec.short_name$ as byte*) as bool,
				"Could not keep track of short argument names while validating a command line argument parser!");
		}
	}

	return true;
}

func[static] bool validate_subcommands(type vector::vector* subcommands) {
	if (subcommands == NULL as type vector::vector*)
		return true;

	// TODO: This should be a hashset
	type vector::vector* names = vector::new_vector(sizeof{type string::string*});

	for (unsigned int i = 0; i < vector::size(subcommands); i++) {
		type subcommand* sc = vector::at(subcommands, i) as type subcommand** @;

		if (!validate_arguments(sc->arguments)) return false;

		if (sc->subcommands != NULL as type vector::vector*) {
			if (argument_list_has_positional(sc->arguments) && vector::size(sc->subcommands) > 0)
				return false;
		}

		if (!validate_subcommands(sc->subcommands)) return false;

		for (unsigned int j = 0; j < vector::size(names); j++) {
			type string::string* curr = vector::at(names, j) as type string::string** @;
			if (string::eq(curr, sc->name))
				return false;
		}

		util::maybe_report_ice(!vector::append(names, sc->name$ as byte*) as bool,
			"Could not keep track of subcommand names while validating a command line argument parser!");
	}

	return true;
}

func bool validate_command(type command* c) {
	if (!validate_arguments(c->arguments)) return false;

	if (c->subcommands != NULL as type vector::vector*) {
		if (argument_list_has_positional(c->arguments) && vector::size(c->subcommands) > 0)
			return false;
	}

	return validate_subcommands(c->subcommands);
}

} } } // namespace shadow::util::command_line
