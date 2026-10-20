# Requirements: xcopy

## Introduction

`xcopy` is the Windows command that copies files and whole directory trees,
with filters (hidden files, exclusion lists), a list-only mode and a
tree-only mode. This repository recreates it in Loup for Linux, keeping
cmd's switch syntax, the way xcopy lists files and counts them, its prompts,
messages and ERRORLEVELs. It uses the shared Windows code in `source/win/`.

## Requirements

### Requirement 1: What gets copied

**User Story:** As a cmd user, I want `xcopy src dst /S` to copy a tree so
that I get the same files in the same places.

#### Acceptance Criteria

1. WHEN the source is a directory, THE program SHALL copy its files; WHEN it
   has `*` or `?` in its last component, the matching files; WHEN it is a
   file, that file.
2. WHEN `/S` is given, THE program SHALL also copy the matching files of
   every subdirectory, depth first in name order, keeping their relative
   paths, and SHALL not create directories that receive no file.
3. WHEN `/E` is given, THE program SHALL behave as with `/S` and also create
   every subdirectory, empty or not.
4. WHEN `/T` is given, THE program SHALL create only the directory structure:
   the directories that would receive files, or with `/E` all of them.
5. THE program SHALL skip hidden files and directories (names starting with
   a dot) unless `/H` is given.
6. WHEN `/EXCLUDE:f1+f2...` is given, THE program SHALL skip every file
   (and directory, whose path is taken with a final `\`) whose absolute
   path, written with `\`, contains a line of one of the files, ignoring
   case.
7. WHEN `/U` is given, THE program SHALL copy only files that already exist
   in the destination.
8. Files SHALL be copied byte for byte.

### Requirement 2: Where it goes

**User Story:** As a cmd user, I want xcopy to work out whether the
destination is a file or a directory.

#### Acceptance Criteria

1. WHEN the destination is an existing directory or ends with `\` or `/`,
   THE program SHALL treat it as a directory (files keep their relative
   paths below it); a missing destination directory SHALL be created.
2. WHEN the destination is an existing file, THE program SHALL copy onto it.
3. WHEN the destination does not exist, THE program SHALL ask
   `Does NAME specify a file name / or directory name on the target /
   (F = file, D = directory)?`, unless `/I` is given and the source is a
   directory or a wildcard (then it is a directory).
4. WHEN no destination is given, THE program SHALL copy into the current
   directory.

### Requirement 3: Overwriting and prompts

**User Story:** As a cmd user, I want to be asked before a file is
overwritten, unless I say otherwise.

#### Acceptance Criteria

1. WHEN a destination file exists and neither `/Y` nor `COPYCMD=/Y` applies,
   THE program SHALL ask `Overwrite NAME (Yes/No/All)?`; `Y` copies, `N`
   skips, `A` copies this and every later file without asking.
2. `/-Y` SHALL restore the question; the later of `/Y` and `/-Y` wins, and
   the command line overrides `COPYCMD`.
3. Answers SHALL be read from standard input, one line each; the first
   letter counts and is echoed; any other answer repeats the question.
4. WHEN standard input ends before an answer, THE program SHALL stop with
   ERRORLEVEL 2 (as Ctrl+C does on Windows).

### Requirement 4: Output

**User Story:** As a cmd user, I want xcopy's listing and count.

#### Acceptance Criteria

1. THE program SHALL list each file it copies as the source operand's path
   plus the file's relative path, with `\`, and end with `N File(s) copied`.
2. `/F` SHALL list `SOURCE -> DESTINATION` with absolute paths; `/Q` SHALL
   list nothing but the count.
3. `/L` SHALL list the files that would be copied, end with `N File(s)`, and
   change nothing.

### Requirement 5: Errors and exit statuses

**User Story:** As a script author, I want xcopy's ERRORLEVELs.

#### Acceptance Criteria

1. WHEN there is no operand or more than two, THE program SHALL print
   `Invalid number of parameters` (or `Invalid switch - X` for an extra
   argument that looks like a switch) and `0 File(s) copied`, and exit 4.
2. WHEN the source does not exist, THE program SHALL print
   `File not found - NAME`, or `Invalid path` for a missing directory;
   WHEN a wildcard matches nothing, `File not found - PATTERN`; exit 4.
3. WHEN the destination is inside the source and `/S`, `/E` or `/T` is given,
   `Cannot perform a cyclic copy`; WHEN a file would be copied onto itself,
   `File cannot be copied onto itself`; WHEN an exclusion file cannot be
   read, `Can't read file: NAME`; each with exit status 4.
4. WHEN a file or directory cannot be written, THE program SHALL print
   `File creation error - Access is denied.` or
   `Unable to create directory - NAME`, stop (or with `/C` go on), and exit
   5.
5. OTHERWISE THE program SHALL exit 1 when no file was found to copy, and 0
   otherwise.
6. `/?` SHALL print a short help text and exit 0; `--version` alone SHALL
   print `xcopy (loup-cmd-xcopy) 0.1.0`. A `/X` that is not one of xcopy's
   switches SHALL be an operand, as SHALL every argument after `--`.
