import "tck/constrain.hsp"

import <"std/lib">
import <"std/io">
import <"stdx/vector">
import <"stdx/string">

import "tck/util.hsp"
import "tck/debug.hsp"
import "tck/env.hsp"
import "ast/ast.hsp"
import "util/error.hsp"
import "src/compile.hsp"

using namespace stdx::string;
using namespace stdx::vector;
using std::io::printf;
using std::lib::malloc;
using std::lib::NULL;

namespace shadow { namespace tck {

func type prog_status* constrain_prog(type module* module_context, type parse::parser* pr, type ast::prog* p,
	bool verbose) {
	type env* curr_env = module_context->e;
	if (curr_env == NULL as type env*) {
		curr_env = malloc(sizeof{type env}) as type env*;
		init_env(curr_env, pr, module_context);
		module_context->e = curr_env;
	}
	else {
		curr_env->par = pr;
	}

	type prog_status* ret = malloc(sizeof{type prog_status}) as type prog_status*;
	ret->e = curr_env;
	ret->valid = true;

	unsigned int i = 0;
	for (; i < vector::size(p->top_level_constructs); i++) {
		type ast::top_level* tlc = vector::at(p->top_level_constructs, i)
			as type ast::top_level** @;
		if (tlc->kind != ast::top_level_kind::IMPORT)
			break;

		type ast::mod_import* mi = tlc->which.top_level_import;
		if (!handle_mod_import(curr_env, mi)) {
			ret->valid = false;
			return ret;
		}
	}

	for (; i < vector::size(p->top_level_constructs); i++) {
		type ast::top_level* tlc = vector::at(p->top_level_constructs, i)
			as type ast::top_level** @;
		switch (tlc->kind) {
		case ast::top_level_kind::DECL: {
			type ast::decl* d = tlc->which.top_level_decl;
			if (!constrain_decl(curr_env, d, true)) {
				ret->valid = false;
				return ret;
			}
		}
			break;
		case ast::top_level_kind::IMPORT: {
			type ast::mod_import* mi = tlc->which.top_level_import;
			util::report_token_error(util::error_kind::ERR, curr_env->par->buf,
				mi->import_token, "Expected all import statements to be at the beginning of a file!");
			ret->valid = false;
			return ret;
		}
			break;
		default:
			util::report_ice("Unknown top_level construct found during typechecking!");
			ret->valid = false;
			return ret;
		}
	}

	if (verbose) {
		printf("================================\n");
		type vector::vector* vec = vector::new_vector(sizeof{type string::string*});
		compile::gen_mod_info(string::new_string(compile::MOD_SYMBOLS_HEADER), curr_env,
			curr_env->global_scope.sym_2_typ_var, vec);
		compile::gen_mod_info(string::new_string(compile::MOD_TYPES_HEADER), curr_env,
			curr_env->global_scope.typ_2_typ_var, vec);
		compile::gen_mod_info(string::new_string(compile::MOD_DATATYPES_HEADER), curr_env,
			curr_env->global_scope.datatyp_2_typ_var, vec);
		compile::gen_mod_info(string::new_string(compile::MOD_DATATYPE_CONSTRUCTORS_HEADER), curr_env,
			curr_env->global_scope.datatyp_constructor_2_typ_var, vec);
		for (unsigned int i = 0; i < vector::size(vec); i++) {
			printf("%s\n", string::data(vector::at(vec, i) as type string::string** @));
		}
		printf("================================\n");
	}

	return ret;
}

} } // namespace shadow::tck
