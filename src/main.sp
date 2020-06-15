import "src/compile.hsp"

using namespace shadow;

func int main(int argc, char** argv) {
	if (argc != 1) {
		for (int i = 1; i < argc; i++)
			compile::compile_file(argv[i], true);
	}
	else {
		constexpr unsigned int NUM_SAMPLES = 67;
		compile::compile_samples(NUM_SAMPLES);
	}

	return 0;
}
