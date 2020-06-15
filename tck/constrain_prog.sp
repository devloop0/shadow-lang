import "tck/constrain.hsp"

import <"std/io">
import <"stdx/vector">

import "tck/env.hsp"
import "ast/ast.hsp"

using namespace stdx::vector;
using std::io::printf;

namespace shadow { namespace tck {

func bool constrain_prog(type env* e, type ast::prog* p) {
	for (unsigned int i = 0; i < vector::size(p->top_level_constructs); i++) {
		type ast::top_level* tlc = vector::at(p->top_level_constructs, i)
			as type ast::top_level** @;
		switch (tlc->kind) {
		case ast::top_level_kind::DECL: {
			type ast::decl* d = tlc->which.top_level_decl;
			if (!constrain_decl(e, d, true)) return false;
		}
			break;
		}
	}

	return true;
}

} } // namespace shadow::tck
