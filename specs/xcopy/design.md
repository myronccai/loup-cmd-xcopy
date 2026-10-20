# Design: xcopy

## Overview

`main()` passes `runtime.args()` to `cli.app.run`, which parses them
(`cli.args` on top of `win.switches`, with `COPYCMD` as the default for
`/Y`), checks the operand count, handles `/?` and `--version`, and calls
`commands.xcopy.run_xcopy`. The run is planned first (`commands.plan`:
nothing is written), then the questions are asked, then directories are
created and files copied, each checked afterwards.

## Modules

| Module | Contents |
|---|---|
| `source/appinfo.loup` | name, version, ERRORLEVELs 0, 1, 2, 4, 5 |
| `source/cli/args.loup` | `Options`, `xcopy_switches()`, `copycmd_overwrite`, `parse_args`, `operand_error` |
| `source/cli/usage.loup` | `usage()` (a short `/?` summary), `version_line()` |
| `source/cli/app.loup` | `run()`: parse, usage errors, help/version, `run_xcopy` |
| `source/commands/plan.loup` | `resolve_source`, `collect` (the walk, /H, /EXCLUDE), `destination_kind`, `plan_items` |
| `source/commands/xcopy.loup` | messages, `ask`, `make_dir`, `copy_file`, `run_xcopy` / `xcopy_with` |
| `source/commands/answers.loup` | `Answers`: prompt answers read from standard input, a line each |
| `source/commands/fspaths.loup` | `current_dir`, `absolute_path`, `is_within`, `is_hidden_name`, `under` |
| `source/win/` | the shared Windows code: switches, wildcards, paths, messages |

### Planning

`resolve_source` gives a `Source`: the base directory, the pattern (`*` for a
directory source), and whether several files are possible (`/I` applies).
`collect` walks from the base with a stack (sorted subdirectories pushed in
reverse, so the walk is pre-order in name order): each directory's matching
files (`win.wildcard.list_matches`), then its subdirectories. Hidden names
are skipped without `/H`; `/EXCLUDE` strings are upper-cased once and looked
for in the upper-cased absolute display path (`\`), a directory's with a
final `\`. It returns the relative file paths, every walked directory (for
`/E`), the directories that hold files (for `/T`), and how many names
matched before filtering (to tell "no match" from "all filtered").

`destination_kind` decides directory, file or ask; `plan_items` maps each
relative path to its destination and to the name xcopy lists (the source
operand's own spelling plus the relative path, with `\`).

### Running

1. Source errors and unreadable exclusion files are initialization errors
   (status 4, with `0 File(s) copied` on standard output).
2. A missing destination is asked about (`F`/`D`) unless `/I` applies.
3. With `/S`, `/E` or `/T`, a destination inside the source is a cyclic copy;
   a file whose destination is itself stops the run.
4. The destination directory (and with `/E` every walked directory, with
   `/T` the ones that would get files) is created; `/T` stops there.
5. Each file: the overwrite question if needed, the listing line, then
   `copy_file`, which creates the parent directory, refuses a directory in
   the way, copies, and checks that the file exists afterwards.
6. The count line, then the status: 5 after a write error, 1 if nothing was
   found to copy, else 0.

Prompts read standard input whole on first use (Loup 1.26.0 has no
line-at-a-time reader, T2) and take one line per answer; the end of input
stops the run with status 2.

### Native-build notes

- `io.fs` does not report failures natively (`createDir`, `copy` fail
  silently) and throws in Stage0, so both are wrapped in `try` and checked
  with `isDir`/`isFile` afterwards.
- There is no `cwd()` in native builds: `current_dir` runs `pwd` through
  `io.proc.output` (which also works when `PWD` is unset or stale).
- `Answers` and the `missing` list are passed as `edits`; the walk takes
  lists and scalars, not structs that hold lists (those are copied on every
  call natively).

## Differences from the original

- Hidden means a name starting with a dot; there are no system, archive or
  read-only attributes, so `/A`, `/M`, `/K`, `/R`, `/N`, `/O`, `/X`, `/G`,
  `/B`, `/J`, `/Z` and `/COMPRESS` are not supported, nor `/D` (no file times,
  T1), `/P` and `/W` (no key-by-key input, T2) and `/V`.
- Prompt answers come from standard input a line at a time; at a terminal,
  the input must be ended (Ctrl-D) before the first answer is read. The end
  of input stops the run like Ctrl+C (status 2).
- Messages go to standard error and end with LF; the listing and the count
  go to standard output.
- An unreadable source file (permissions) stops the program with the
  toolchain's `IoError` message.
- `/T` prints `0 File(s) copied` and exits 0.
- A destination answered `F` for several files receives each of them in
  turn (asking before each overwrite), as on Windows; there is no
  concatenation.

## Error handling

Initialization errors stop before anything is written. A write error stops
the copy unless `/C`; with `/C` the run continues and the status is still 5.

## Testing

- `tests/args_test.loup`: switches, `/E` implying `/S`, `/Y` vs `/-Y` vs
  COPYCMD, `/EXCLUDE` lists, operand errors.
- `tests/fspaths_test.loup`: absolute paths, `is_within`, hidden names, the
  answer reader.
- `tests/plan_test.loup`: source kinds, the walk order, `/H`, `/EXCLUDE`,
  destination kinds, the copy list.
- `tests/xcopy_test.loup`: whole runs with answers given as text: trees,
  `/E`, `/T`, `/L`, F/D and overwrite answers, every error status.
- `tests/e2e.sh`: the native binary on a fixture tree under `$TMP`: listing
  and count byte for byte, the resulting trees, prompts fed through standard
  input, COPYCMD, and every message and status.
