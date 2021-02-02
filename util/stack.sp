import "util/stack.hsp"

import <"stdx/vector">
import <"std/assert">

using namespace stdx::vector;
using std::assert::assert;

namespace shadow { namespace util {

func void init_stack(type stack* s, unsigned int vs) {
	s->data = vector::new_vector(vs);
	s->size = 0;
}

func void init_stack_from_vector(type stack* s, type vector::vector* v) {
	s->data = v;
	s->size = vector::size(v);
}

func void destroy_stack(type stack* s) {
	vector::delete_vector(s->data);
}

func void stack_push(type stack* s, const byte* b) {
	assert(!vector::uint_insert(s->data, s->size++, b) as bool,
		"Could not insert element into stack!\n");
}

func void stack_pop(type stack* s) {
	s->size--;
}

func byte* stack_top(type stack* s) {
	return vector::at(s->data, s->size - 1);
}

func unsigned int stack_size(type stack* s) {
	return s->size;
}

func byte* stack_at(type stack* s, unsigned int i) {
	assert (0 <= i && i < s->size,
		"Stack index out of bounds!\n");
	return vector::at(s->data, i);
}

} } // namespace shadow::util
