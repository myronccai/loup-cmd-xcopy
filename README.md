# loup-cmd-xcopy

The Windows `xcopy` command recreated in [Loup](https://code-craft.ai/references/loup):
copy files and directory trees, with subdirectories, exclusion lists,
hidden-file filtering, a list-only mode and a tree-only mode, using cmd's
switches, listing, prompts, messages and ERRORLEVELs, on Linux.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is `host.dual` Loup built as a native binary. It uses the shared
Windows code in [`source/win/`](source/win/) (switch parser, wildcard
matcher, path helpers, messages), copied from
[loup-cmd-type](https://github.com/myronccai/loup-cmd-type). It shows a tree
walk with filters, a plan-then-copy structure, a dry run (`/L`) and checks
after every write.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, and `clang` 17 or later for the native build.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make build                          # native binary: build/xcopy
make ci                             # check, unit tests, build, end-to-end tests
make run ARGS="src dst /S /I"       # run from source with loup run
```

Quote operands that contain `\`, `*` or `?` so that the Linux shell passes
them through: cmd does not expand wildcards, the command does.

```text
$ build/xcopy project backup /S /I
project\README.md
project\obj\main.o
project\src\main.c
project\src\util\str.c
project\src\util\str.h
5 File(s) copied
$ build/xcopy 'project\src\*.c' 'backup\' /S /L
project\src\main.c
project\src\util\str.c
2 File(s)
$ printf 'n\na\n' | build/xcopy project backup /S
Overwrite backup\README.md (Yes/No/All)? n
Overwrite backup\obj\main.o (Yes/No/All)? a
project\obj\main.o
project\src\main.c
project\src\util\str.c
project\src\util\str.h
4 File(s) copied
$ echo D | build/xcopy 'project\README.md' notes
Does notes specify a file name
or directory name on the target
(F = file, D = directory)? D
project\README.md
1 File(s) copied
$ build/xcopy project tree /T /E /I
0 File(s) copied
$ find tree | sort
tree
tree/docs
tree/obj
tree/src
tree/src/util
$ build/xcopy project 'project\copy' /S /I; echo "ERRORLEVEL $?"
Cannot perform a cyclic copy
0 File(s) copied
ERRORLEVEL 4
$ build/xcopy 'project\*.txt' backup; echo "ERRORLEVEL $?"
File not found - *.txt
0 File(s) copied
ERRORLEVEL 4
```

`project/.git` is skipped in every example: names starting with a dot count
as hidden, and only `/H` copies them.

## Switches

| Switch | Meaning |
|---|---|
| `/S` | Copy subdirectories too, except those that would stay empty |
| `/E` | Copy subdirectories too, including empty ones |
| `/T` | Create the directory structure only (with `/E`, also empty directories) |
| `/I` | A missing destination is a directory when the source is a directory or a wildcard (otherwise xcopy asks `F` or `D`) |
| `/Y`, `/-Y` | Overwrite without asking, or ask (the default); `COPYCMD=/Y` presets `/Y` |
| `/Q` | Do not list the files |
| `/F` | List `SOURCE -> DESTINATION` with absolute paths |
| `/L` | List what would be copied (`N File(s)`); copy nothing |
| `/C` | Continue after an error |
| `/H` | Copy hidden files and directories (names starting with a dot) |
| `/U` | Copy only files that already exist in the destination |
| `/EXCLUDE:f1+f2` | Skip files whose absolute path (with `\`) contains a line of one of these files, ignoring case: `\obj\` skips a directory, `.log` an extension |
| `/?` | Help |

Switches start with `/` or `-`, in any case, and may come anywhere; a `/X`
that is not one of these is an operand, and `--` ends switch parsing. The
source may use `*` and `?` in its last component (Windows rules); with `/S`
the same pattern applies in every subdirectory. Without a destination,
files go to the current directory.

Questions are answered on standard input, one line per answer (the first
letter counts and is echoed). When the input ends before an answer, xcopy
stops with ERRORLEVEL 2, as Ctrl+C does on Windows.

Exit status (ERRORLEVEL): `0` files were copied, `1` no files were found to
copy, `2` stopped at a question, `4` initialization error (syntax, missing
source, cyclic copy, copy onto itself, unreadable exclusion file), `5` a
file or directory could not be written.

## Differences from the original

- Hidden means a name starting with a dot; Linux has no hidden, system,
  archive or read-only attributes. `/A`, `/M`, `/K`, `/R`, `/N`, `/O`, `/X`,
  `/G`, `/B`, `/J`, `/Z` and `/COMPRESS` are not supported, nor `/D` (Loup
  1.26.0 has no file times), `/P` and `/W` (no key-by-key input), `/V` and
  `/-I`.
- Answers are read from standard input a line at a time: at a terminal, end
  the input with Ctrl-D before the first answer is taken.
- Unknown switches are operands under the series' convention; a third
  argument that looks like a switch is reported as `Invalid switch - X`.
- `/T` prints `0 File(s) copied` and exits 0.
- File names are case-sensitive for literal operands; wildcards ignore case.
  Paths are printed with `\`.
- Write failures are reported as `File creation error - Access is denied.`
  or `Unable to create directory - X` whatever the cause, since Loup's
  `io.fs` reports no error details natively. An unreadable source file
  (permissions) stops the program with the toolchain's `IoError` message.
- Messages go to standard error and end with LF; the listing and the count
  go to standard output. `/?` prints a short summary written for this
  project.
- `--help` and `--version` as the only argument are series conventions.

## Layout

```text
source/main.loup                # entry point
source/appinfo.loup             # name, version, ERRORLEVELs
source/cli/args.loup            # xcopy's switches via win.switches, COPYCMD, operand checks
source/cli/usage.loup           # /? and --version text
source/cli/app.loup             # run(): parse, dispatch, exit status
source/commands/plan.loup       # source, walk (/S /E /H /EXCLUDE), destination, copy list
source/commands/xcopy.loup      # questions, directory creation, checked copies, count
source/commands/answers.loup    # answers to questions, read from standard input
source/commands/fspaths.loup    # current directory, absolute paths, hidden names
source/win/                     # shared Windows code: switches, wildcards, paths, messages
tests/*_test.loup               # unit tests (make test)
tests/e2e.sh                    # end-to-end tests of build/xcopy (make e2e)
specs/xcopy/                    # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
