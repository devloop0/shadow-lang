import "util/symtab.hsp"

import <"std/lib">
import <"std/string">
import <"std/assert">
import <"stdx/vector">

using std::lib::NULL;
using std::string::memcpy;
using std::assert::assert;
using namespace stdx::vector;

namespace shadow { namespace util {

func void init_symtab(type symtab* s, unsigned int ks, unsigned int vs,
	fn bool(const byte*, const byte*) c,
	type symtab* p) {
	s->key_size = ks;
	s->value_size = vs;
	s->keys = vector::new_vector(s->key_size);
	s->values = vector::new_vector(s->value_size);
	s->cmp = c;
	s->parent = p;
	s->children = vector::new_vector(sizeof{type symtab*});
}

func void destroy_symtab(type symtab* s) {
	vector::delete_vector(s->keys);
	vector::delete_vector(s->values);
	vector::delete_vector(s->children);
}

func void symtab_add_child(type symtab* s, type symtab* c) {
	assert(!vector::append(s->children, c$ as byte*) as bool,
		"Could not add child symbol table to parent!\n");
}

func void symtab_set(type symtab* s, const byte* k, const byte* v) {
	for (unsigned int i = 0; i < vector::size(s->keys); i++) {
		const byte* curr_key = vector::at(s->keys, i);
		if (s->cmp(curr_key, k)) {
			byte* curr_value = vector::at(s->values, i);
			memcpy(curr_value, v, s->value_size);
			return;
		}
	}
	assert(!vector::append(s->keys, k) as bool,
		"Could not add new key to symbol table!\n");
	assert(!vector::append(s->values, v) as bool,
		"Could not add new value to symbol table!\n");
}

func byte* symtab_lookup(type symtab* s, const byte* k, bool rec) {
	for (unsigned int i = 0; i < vector::size(s->keys); i++) {
		const byte* curr_key = vector::at(s->keys, i);
		if (s->cmp(curr_key, k))
			return vector::at(s->values, i);
	}
	if (rec) {
		if (s->parent == NULL as type symtab*)
			return NULL;
		else
			return symtab_lookup(s->parent, k, true);
	}
	return NULL;
}

func unsigned int symtab_num_entries(type symtab* s) {
	return vector::size(s->keys);
}

func void symtab_clear(type symtab* s) {
	vector::clear(s->keys);
	vector::clear(s->values);
}

} } // namespace shadow::util
