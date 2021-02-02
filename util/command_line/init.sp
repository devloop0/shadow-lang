import "util/command_line/command_line.hsp"

import <"stdx/vector">
import <"stdx/string">
import <"std/lib">
import <"std/arg">

import "util/error.hsp"

using namespace stdx::vector;
using namespace stdx::string;
using std::lib::malloc;
using std::arg::va_start;
using std::arg::va_end;
using std::arg::va_arg;
using std::arg::va_list;

namespace shadow { namespace util { namespace command_line {

func type argument* create_argument(
	char sn, bool sn_present,
	type string::string* long_name,
	bool repeatable, unsigned int kind) {
	type argument* ret = malloc(sizeof{type argument}) as type argument*;
	ret->short_spec.short_name = sn;
	ret->short_spec.present = sn_present;
	ret->long_name = long_name;
	ret->repeatable = repeatable;
	ret->kind = kind;
	return ret;
}

func type vector::vector* create_arguments(unsigned int num, ...) {
	type vector::vector* ret = vector::new_vector(sizeof{type argument*});

	type va_list* args = va_start(num$ as byte*, sizeof{type argument*});
	for (unsigned int i = 0; i < num; i++) {
		type argument* curr;
		va_arg(args, curr$ as byte*, sizeof(curr), alignof(curr));
		
		util::maybe_report_ice(!vector::append(ret, curr$ as byte*) as bool,
			"Could not create argument list!");
	}
	va_end(args);

	return ret;
}

func type command_metadata* create_command_metadata(
	type string::string* name,
	type string::string* version,
	type string::string* author,
	type string::string* usage) {
	type command_metadata* cm = malloc(sizeof{type command_metadata}) as type command_metadata*;
	cm->name = name;
	cm->version = version;
	cm->author = author;
	cm->usage = usage;
	return cm;
}

func type subcommand* create_subcommand(
	type command_metadata* cm,
	type string::string* name,
	type vector::vector* arguments,
	type vector::vector* subcommands) {
	type subcommand* sc = malloc(sizeof{type subcommand}) as type subcommand*;
	sc->metadata = cm;
	sc->name = name;
	sc->arguments = arguments;
	sc->subcommands = subcommands;
	return sc;
}

func type vector::vector* create_subcommands(unsigned int num, ...) {
	type vector::vector* ret = vector::new_vector(sizeof{type subcommand*});

	type va_list* args = va_start(num$ as byte*, sizeof{type subcommand*});
	for (unsigned int i = 0; i < num; i++) {
		type subcommand* curr;
		va_arg(args, curr$ as byte*, sizeof(curr), alignof(curr));
		
		util::maybe_report_ice(!vector::append(ret, curr$ as byte*) as bool,
			"Could not create argument list!");
	}
	va_end(args);

	return ret;
}

func type command* create_command(
	type command_metadata* cm,
	type vector::vector* arguments,
	type vector::vector* subcommands) {
	type command* c = malloc(sizeof{type command}) as type command*;
	c->metadata = cm;
	c->arguments = arguments;
	c->subcommands = subcommands;
	return c;
}

} } } // namespace shadow::util::command_line
