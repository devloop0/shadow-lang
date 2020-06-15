import "tck/env.hsp"

import <"std/io">
import <"std/string">
import <"std/lib">
import <"stdx/vector">

import "ast/ast.hsp"
import "util/symtab.hsp"

using std::io::printf;
using std::string::strcmp;
using std::lib::malloc;
using std::lib::free;
using std::lib::NULL;
using namespace stdx::vector;

namespace shadow { namespace tck {

func[static] bool symtab_str_cmp(const byte* a, const byte* b) {
	const char* f = a as const char** @,
		s = b as const char** @;
	return !strcmp(f, s) as bool;
}

func void init_env(type env* e, type parse::parser* p) {
	e->typ_constraints = vector::new_vector(sizeof{type typ_constraint});
	e->bindings = malloc(sizeof{type util::symtab}) as type util::symtab*;

	e->global_scope.sym_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;
	e->global_scope.typ_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;
	e->global_scope.datatyp_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;
	e->global_scope.datatyp_constructor_2_typ_var = malloc(sizeof{type util::symtab}) as type util::symtab*;
	init_env_symtab(e->global_scope.sym_2_typ_var, NULL as type util::symtab*);
	init_env_symtab(e->global_scope.typ_2_typ_var, NULL as type util::symtab*);
	init_env_symtab(e->global_scope.datatyp_2_typ_var, NULL as type util::symtab*);
	init_env_symtab(e->global_scope.datatyp_constructor_2_typ_var, NULL as type util::symtab*);
	init_binding_symtab(e->bindings);

	e->current_scope = e->global_scope;
	e->id_counter = 0;
	e->par = p;
}

func void destroy_env(type env* e) {
	destroy_env_symtab(e->global_scope.sym_2_typ_var);
	destroy_env_symtab(e->global_scope.typ_2_typ_var);
	destroy_env_symtab(e->global_scope.datatyp_2_typ_var);
	destroy_env_symtab(e->global_scope.datatyp_constructor_2_typ_var);
	destroy_binding_symtab(e->bindings);

	vector::delete_vector(e->typ_constraints);
}

func void init_env_symtab(type util::symtab* s, type util::symtab* parent) {
	util::init_symtab(s, sizeof{char*}, sizeof{type ast::typ*},
		symtab_str_cmp, parent);
}

func void destroy_env_symtab(type util::symtab* s) {
	util::destroy_symtab(s);
}

} } // namespace shadow::tck
