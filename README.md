# Shadow: A Functional Programming Language
Shadow is a functional programming language that compiles down to [Spectre](https://github.com/devloop0/spectre-lang). Note that this means Shadow currently only runs on a 32-bit ARMV6L Linux system; see the Spectre repository for how to setup Spectre.

# Dependencies
- Spectre (and everything Spectre depends on)

# Setup
After you've got Spectre running (and on your `$PATH`), setting up Shadow should be pretty simple, just:
```
$ git clone https://github.com/devloop0/shadow
$ cd shadow/
$ make -f rt_Makefile compile && make -f rt_Makefile link
$ make compile && make link
$ # The output should be in ./build/shadow
```
Note that the compilation and linking steps are split up because (at least I) cross-compile from my host system onto an emulated Raspberry Pi and then perform the final linking on the emulated system itself. If you're compiling natively, you should just be able to run the commands above.

For some basic information about what's supported, you can run `./build/shadow -h` or `./build/shadow help` to see a list of subcommands (and you can use `-h` on the various subcommands to see what flags/options are supported there as well).

# Prelude
In the `mod/` folder, there is a currently a prelude module with support for some standard, basic functions/types (inspired very heavily from Haskell).
While Shadow itself doesn't require a prelude (currently), you can still have it available to your programs as follows, first, create a `/usr/include/libshadow` directory, and make sure your current user has permissions to it. Then, create `mod`, `lib`, and `src` directories inside of `/usr/include/libshadow`.

`mod` is to store module metadata files for all modules/submodules you create. `lib` is to store the static executable files that you can link with to have access to your modules at runtime, and `src` is to store a copy of the source code corresponding to when the module was compiled (this can be optionally disabled, see the `mod.sdw_cfg` files inside of `prelude`).

Now you can compile the `prelude` to Spectre source code as follows:

```
$ ./build/shadow compile -mv mod/prelude
```

The `-v` option is for verbose output, so you can see the types of all of the generated symbols (you don't need to include this). This will produce a `mod_build/` directory with the all of the Spectre source code as well as a `mod_build.sh` file that contains a build script to compile down the Spectre source code into `.a` static archives. Now you can run:

```
$ ./mod_build.sh
```

As long as you have access to the `/usr/include/libshadow` and all of its subdirectories, this will produce the necessary output libraries. You can now remove the `mod_build/` directory and the `mod_build.sh` build script.

```
$ rm -f mod_build/ mod_build.sh
```

At this point, the `prelude` is available for any Spectre program you compile to use and link against.

Note that while this process was with respect to the `prelude` module, you should be able to apply this same process to any other module that you want to create as well.

# Running
This example will use the `prelude` (if you don't want to use the `prelude`, you can just write a simple test program like:

```
val x = 2
```

instead; the syntax of the Shadow is heavily ML-inspired).

Save the following code to `s.sdw`:

```
import .prelude
import .prelude.datatypes

fun reverse l = let
        fun reverse_ (l, .prelude.datatypes.Cons (x, l_))
                = reverse_ (.prelude.datatypes.Cons (x, l), l_)
        | reverse_ (l, .prelude.datatypes.Nil) = l
in
        reverse_ (.prelude.datatypes.Nil, l)
end

val (Cons_, Nil_) = (.prelude.datatypes.Cons, .prelude.datatypes.Nil)

val orig = Cons_ (1, Cons_ (2, Cons_ (3, Cons_ (4, Nil_))))
val res = reverse orig
```

This is a simple program that reverses a linked list. It uses the pre-defined `list` datatype and associated constructors in the `prelude` module.
Now run the following command:

```
$ ./build/shadow compile -dv s.sdw
```

The `-v` here is optional, but the `-d` is important, since currently, the only way to print something is through this flag. `-d` (debug) will print the value of a variable, every time it is created/stored.

This will generate an `a` output file with the generated Spectre source code, and a `build.sh` build script that you can run to compile the program. You can now run the program with:

```
$ ./build.sh
$ ./a.out
```

The output will show `orig` storing the list `Cons (1, Cons (2, Cons (3, Cons (4, Nil))))` and `res` storing the list `res = Cons (4, Cons (3, Cons (2, Cons (1, Nil))))`. You can remove the generated files now if you wish:

```
$ rm -f a.out a build.sh
```

# Testing
You can test both the runtime and the typechecker independently through the `rt_test.sh` and `tck_test.sh` scripts. The `tck_test.sh` script will output types to a `tck_outputs`, which you can `diff` against `samples/ref_tck.txt`. Similarly, `rt_test.sh` will output a `cgen_outputs` folder with the generated Spectre source code, and will output runtime outputs to a `rt_outputs` file, which you can diff against `samples/ref_rt.txt`. The source code for the tests is in `samples/{tck,rt}`.

# Future Work
The standard library (starting with `prelude`), definitely needs to be built out more, and a `print` function is probably a high priority.

More debugging with modules needs to be done.

There are some constructs like `case` expressions that still need to be implemented in the code generator.

Some data structures are really inefficient; currently, the symbol table is implemented using vectors (since the standard library happened to contain them), so runtime for lookups is `O(n)` instead of `O(1)`. More code-cleanup probably needs to be done to fix this and other potential inefficiencies.

# Far Future Work
The Spectre `malloc`/`free` implementation is currently done with a linked list, so this probably a major bottleneck when the number of allocations is huge. Though it doesn't require any work here, that probably needs to be fixed in the future as well.

# License
It's the Spectre license, but for the Shadow programming language instead.
