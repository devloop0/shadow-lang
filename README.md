# Shadow: A Functional Programming Language
Shadow is a functional programming language that compiles down to [Spectre](https://github.com/devloop0/spectre-lang). Note that this means Shadow currently only runs on a 32-bit ARMV6L Linux system; see the Spectre repository for how to setup Spectre.
Note that this repository is in a pretty rough state; if you have any specific questions, feel free to just message me instead.

# Dependencies
- Spectre (and everything Spectre depends on)

# Setup
After you've got Spectre running (and on your path), setting up Shadow should be pretty simple, just:
```
$ git clone https://github.com/devloop0/shadow
$ cd shadow/
$ make -f rt_Makefile compile && make -f rt_Makefile link
$ make compile && make link
$ # The output should be in ./build/shadow
```
Note that the compilation and linking steps are split up because (at least I) cross-compile from my host system onto an emulated Raspberry Pi and then perform the final linking on the emulated system itself. If you're compiling natively, you should just be able to run the commands above.

# Running
Running a program should be as simple as:
```
$ ./build_sdw_debug.sh <file name>
```
Only a subset of features are currently supported at runtime (although the typechecker is pretty complete).

*I'll probably add some more information here when I'm less tired.*

# License
It's the Spectre license, but for the Shadow programming language instead.
