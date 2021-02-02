import <"stdx/string">

import "src/frontend.hsp"
import "util/command_line/command_line.hsp"

using namespace stdx::string;
namespace command_line = shadow::util::command_line;
using namespace shadow;

func int main(int argc, char** argv) {
	type command_line::command* frontend_spec = frontend::create();
	type command_line::command_parse_result* input = command_line::parse(frontend_spec, argc, argv);

	return frontend::process_request(input);
}
