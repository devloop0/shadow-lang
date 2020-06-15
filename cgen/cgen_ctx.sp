import "cgen/cgen.hsp"

import <"std/lib">
import <"stdx/vector">
import <"stdx/string">

import "cgen/util.hsp"

using std::lib::malloc;
using std::lib::free;
using namespace stdx::vector;
using namespace stdx::string;

namespace shadow { namespace cgen {

func void init_cgen_ctx(type cgen_ctx* c, type tck::env* e) {
	c->e = e;

	c->cd = malloc(sizeof{type cgen_data}) as type cgen_data*;
	init_cgen_data(c->cd);

	c->label_counter = 0;
	c->debug = false;
}

func void destroy_cgen_ctx(type cgen_ctx* c) {
	for (unsigned int i = 0; i < vector::size(c->cd->header); i++) {
		type string::string* s = vector::at(c->cd->header, i) as type string::string** @;
		string::delete_string(s);
	}
	vector::delete_vector(c->cd->header);

	for (unsigned int i = 0; i < vector::size(c->cd->body); i++) {
		type string::string* s = vector::at(c->cd->body, i) as type string::string** @;
		string::delete_string(s);
	}
	vector::delete_vector(c->cd->body);

	for (unsigned int i = 0; i < vector::size(c->cd->main); i++) {
		type string::string* s = vector::at(c->cd->main, i) as type string::string** @;
		string::delete_string(s);
	}
	vector::delete_vector(c->cd->main);

	free(c->cd as byte*);
}

} } // namespace shadow::cgen
