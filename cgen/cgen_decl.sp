import "cgen/cgen.hsp"

import <"std/io">
import <"std/lib">
import <"stdx/string">
import <"stdx/vector">

import "tck/util.hsp"
import "cgen/util.hsp"
import "util/error.hsp"
import "ast/ast.hsp"

using std::lib::NULL;
using std::io::printf;
using std::lib::malloc;
using namespace stdx::string;
using namespace stdx::vector;

namespace shadow { namespace cgen {

func void cgen_decl(type cgen_ctx* c, type cgen_data* cd, type ast::decl* d) {
	if (d->kind == ast::decl_kind::TYP || d->kind == ast::decl_kind::DATATYP
		|| d->kind == ast::decl_kind::DATATYP_REPL) {
		return;
	}

	switch (d->kind) {
	case ast::decl_kind::VAL: {
		type ast::val_decl* vd = d->which.vd;

		for (unsigned int i = 0; i < vector::size(vd->val_binds); i++) {
			type ast::val_bind* vb = vector::at(vd->val_binds, i) as type ast::val_bind** @;

			add_scope_st(c, cd, true);
			cgen_exp(c, cd, vb->e);
			add_scope_st(c, cd, false);

			bind_pat_to_exp(c, cd, vb->p);
		}
	}
		return;
	case ast::decl_kind::FUN: {
		// TODO
	}
		break;
	}

	util::report_ice("Unknown ast::decl_kind found in codegen!");
	return;
}

} } // namespace shadow::cgen
