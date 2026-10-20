#!/usr/bin/env bash
# End-to-end tests: run the built binary and compare its standard output
# (byte for byte), and where given its standard error, and exit status with
# the expected ones. The cases run inside a fixture tree built under $TMP.
#
# usage: tests/e2e.sh BINARY

set -u
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# check_file NAME STATUS EXPECTED_FILE [ARGS...]
# Runs BINARY ARGS... with standard input from the file named by $IN
# (default: /dev/null) and compares standard output with EXPECTED_FILE.
# If $WANT_ERR is set, standard error must equal it too.
check_file() {
    local name=$1 want_status=$2 want_file=$3
    shift 3
    "$BIN" "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
    local status=$?
    local err_ok=1
    if [ -n "${WANT_ERR+set}" ]; then
        printf '%s' "$WANT_ERR" > "$TMP/want_err"
        cmp -s "$TMP/want_err" "$TMP/err" || err_ok=0
    fi
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$TMP/out" && [ "$err_ok" -eq 1 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff <(od -c "$want_file") <(od -c "$TMP/out") | sed 's/^/    /' | head -20
        if [ "$err_ok" -eq 0 ]; then
            diff <(od -c "$TMP/want_err") <(od -c "$TMP/err") | sed 's/^/    stderr /' | head -20
        fi
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]
# As check_file, with the expected output given as a string. Bash strings
# cannot hold NUL bytes; use check_file for output that contains them.
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    check_file "$name" "$want_status" "$TMP/want" "$@"
}

# check_both NAME STATUS EXPECTED_STDOUT EXPECTED_STDERR [ARGS...]
check_both() {
    local name=$1 want_status=$2 want_out=$3
    local WANT_ERR=$4
    shift 4
    check "$name" "$want_status" "$want_out" "$@"
}

# check_tree NAME DIR EXPECTED: the files and directories under DIR (sorted,
# one per line, relative) must equal EXPECTED.
check_tree() {
    local name=$1 dir=$2 want=$3
    local got
    got=$(cd "$dir" 2>/dev/null && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort)
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (tree of $dir)"
        diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/    /' | head -20
    fi
}

# The fixture tree, under $TMP only. W is the physical path, as `pwd` and
# /F show it.
mkdir -p "$TMP/w"
W=$(cd "$TMP/w" && pwd -P)
WB=$(printf '%s' "$W" | tr '/' '\\')
mkdir -p "$W/src/sub/deep" "$W/src/empty" "$W/src/.hid" "$W/here"
printf 'alpha\n' > "$W/src/a.txt"
printf 'bravo\n' > "$W/src/b.log"
printf 'charlie\n' > "$W/src/sub/c.txt"
printf 'delta\n' > "$W/src/sub/deep/d.txt"
printf 'hidden\n' > "$W/src/.hidden"
printf 'x\n' > "$W/src/.hid/x.txt"
printf 'x\xff\x00y\n' > "$W/src/bin.dat"
printf '\\deep\\\n.log\n' > "$W/skip.txt"
cd "$W"

none=$'0 File(s) copied\n'

# Help, version and usage errors (ERRORLEVEL 4).
help=$(printf '%s\n' \
'Copies files and directory trees.' \
'' \
'XCOPY source [destination] [/S [/E]] [/T] [/I] [/Y | /-Y] [/Q | /F] [/L]' \
'      [/C] [/H] [/U] [/EXCLUDE:file1[+file2]...]' \
'' \
'  /S         Copy subdirectories too, except empty ones.' \
'  /E         Copy subdirectories too, including empty ones.' \
'  /T         Create the directory structure only, without files.' \
'  /I         Treat a missing destination as a directory when copying' \
'             a directory or a wildcard.' \
'  /Y, /-Y    Overwrite without asking, or ask (the default; COPYCMD may' \
'             preset /Y).' \
'  /Q         Do not list the files.' \
'  /F         List full source and destination names.' \
'  /L         List the files that would be copied; copy nothing.' \
'  /C         Continue after errors.' \
'  /H         Copy hidden files (names starting with a dot) too.' \
'  /U         Copy only files that already exist in the destination.' \
'  /EXCLUDE   Skip files whose full path contains a line of the files listed.')$'\n'
check_both "/? help"                 0 "$help" ''               '/?'
check      "-? among operands"       0 "$help"                  src '-?'
check      "--help"                  0 "$help"                  --help
check      "--version"               0 $'xcopy (loup-cmd-xcopy) 0.1.0\n' --version
check_both "no operand"              4 "$none" $'Invalid number of parameters\n'
check_both "three operands"          4 "$none" $'Invalid number of parameters\n' src d1 d2
check_both "unknown switch"          4 "$none" $'Invalid switch - /Z\n' src d1 /Z
check_both "/EXCLUDE without a file" 4 "$none" $'Invalid switch - /EXCLUDE\n' src d1 /EXCLUDE

# Copying trees.
all5=$'src\\a.txt\nsrc\\b.log\nsrc\\bin.dat\nsrc\\sub\\c.txt\nsrc\\sub\\deep\\d.txt\n'
check_both "/S /I"                   0 "$all5"$'5 File(s) copied\n' '' src t1 /S /I
check_tree "/S /I tree"              t1 $'a.txt\nb.log\nbin.dat\nsub\nsub/c.txt\nsub/deep\nsub/deep/d.txt'
cmp -s src/bin.dat t1/bin.dat && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: binary copy"; }
check      "/E keeps empty dirs"     0 $'5 File(s) copied\n'    'src\' t2 /E /I /Q
check_tree "/E tree"                 t2 $'a.txt\nb.log\nbin.dat\nempty\nsub\nsub/c.txt\nsub/deep\nsub/deep/d.txt'
check      "top level only"          0 $'src\\a.txt\nsrc\\b.log\nsrc\\bin.dat\n3 File(s) copied\n' src t3 /I
check_tree "top level tree"          t3 $'a.txt\nb.log\nbin.dat'
mkdir t4
check      "file into a directory"   0 $'src\\sub\\c.txt\n1 File(s) copied\n' 'src\sub\c.txt' t4
check_tree "file tree"               t4 'c.txt'
check      "wildcard with /S"        0 $'src\\a.txt\nsrc\\sub\\c.txt\nsrc\\sub\\deep\\d.txt\n3 File(s) copied\n' 'src\*.TXT' 't5\' /S
check_tree "wildcard tree"           t5 $'a.txt\nsub\nsub/c.txt\nsub/deep\nsub/deep/d.txt'
check      "/F full names"           0 "$WB\\src\\a.txt -> $WB\\t6\\a.txt"$'\n'"$WB\\src\\sub\\c.txt -> $WB\\t6\\sub\\c.txt"$'\n'"$WB\\src\\sub\\deep\\d.txt -> $WB\\t6\\sub\\deep\\d.txt"$'\n3 File(s) copied\n' \
    'src/*.txt' t6 /S /I /F
check      "/L lists only"           0 "$all5"$'5 File(s)\n'    src t7 /L /S /I
[ ! -e t7 ] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: /L created t7"; }
check      "/T structure"            0 "$none"                  src t8 /T /I
check_tree "/T tree"                 t8 $'sub\nsub/deep'
check      "/T /E structure"         0 "$none"                  src t9 /T /E /I
check_tree "/T /E tree"              t9 $'empty\nsub\nsub/deep'
check      "/H hidden files"         0 $'src\\.hidden\nsrc\\a.txt\nsrc\\b.log\nsrc\\bin.dat\nsrc\\.hid\\x.txt\nsrc\\sub\\c.txt\nsrc\\sub\\deep\\d.txt\n7 File(s) copied\n' \
    src t10 /S /I /H
check      "/EXCLUDE"                0 $'src\\a.txt\nsrc\\bin.dat\nsrc\\sub\\c.txt\n3 File(s) copied\n' src t11 /S /I /EXCLUDE:skip.txt
check_tree "/EXCLUDE tree"           t11 $'a.txt\nbin.dat\nsub\nsub/c.txt'
printf 'old\n' > t3/a.txt
check      "/U only existing"        0 $'src\\a.txt\nsrc\\b.log\nsrc\\bin.dat\n3 File(s) copied\n' src t3 /U /Y
check      "/U nothing there"        1 "$none"                  src t12 /U /I
cd here
check      "no destination"          0 $'..\\src\\a.txt\n1 File(s) copied\n' '..\src\a.txt'
cd ..
check_tree "copied here"             here 'a.txt'

# Prompts: answers are read from standard input, one per line.
ask_fd() { printf 'Does %s specify a file name\nor directory name on the target\n(F = file, D = directory)? ' "$1"; }
printf 'd\n' > "$TMP/answers"
IN="$TMP/answers" check "answer D"    0 "$(ask_fd p1)"$'d\nsrc\\a.txt\n1 File(s) copied\n' 'src\a.txt' p1
check_tree "D tree"                  p1 'a.txt'
printf 'x\nF\n' > "$TMP/answers"
IN="$TMP/answers" check "answer F after a bad one" 0 "$(ask_fd p2.txt)"$'x\n'"$(ask_fd p2.txt)"$'F\nsrc\\a.txt\n1 File(s) copied\n' 'src\a.txt' p2.txt
cmp -s src/a.txt p2.txt && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: F copy"; }
check      "no answer"               2 "$(ask_fd p3)"$'\n'      'src\a.txt' p3
[ ! -e p3 ] && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: p3 created"; }
printf 'stale\n' > p1/a.txt
printf 'n\n' > "$TMP/answers"
IN="$TMP/answers" check "overwrite No" 0 $'Overwrite p1\\a.txt (Yes/No/All)? n\n0 File(s) copied\n' 'src\a.txt' p1
grep -q stale p1/a.txt && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: overwritten after No"; }
printf 'y\n' > "$TMP/answers"
IN="$TMP/answers" check "overwrite Yes" 0 $'Overwrite p1\\a.txt (Yes/No/All)? y\nsrc\\a.txt\n1 File(s) copied\n' 'src\a.txt' p1
printf 'a\n' > "$TMP/answers"
IN="$TMP/answers" check "overwrite All" 0 $'Overwrite t3\\a.txt (Yes/No/All)? a\nsrc\\a.txt\nsrc\\b.log\nsrc\\bin.dat\n3 File(s) copied\n' src t3
check      "overwrite, no answer"    2 $'Overwrite t3\\a.txt (Yes/No/All)? \n' src t3
COPYCMD=/Y check "COPYCMD=/Y"        0 $'3 File(s) copied\n'      src t3 /Q
COPYCMD=/Y check "/-Y beats COPYCMD" 2 $'Overwrite t3\\a.txt (Yes/No/All)? \n' src t3 /Q /-Y

# Errors.
check_both "missing file"            4 "$none" $'File not found - nope.txt\n' 'src\nope.txt' d
check_both "missing directory"       4 "$none" $'Invalid path\n'  'nodir\a.txt' d
check_both "no match"                4 "$none" $'File not found - *.none\n' 'src\*.none' d /I
check_both "cyclic copy"             4 "$none" $'Cannot perform a cyclic copy\n' src 'src\sub\new' /S /I
check_both "onto itself"             4 "$none" $'File cannot be copied onto itself\n' src src
check_both "unreadable exclusions"   4 "$none" $"Can't read file: nope.txt"$'\n' src d /I /EXCLUDE:skip.txt+nope.txt
check_both "empty source"            1 "$none" ''                 'src\empty' d1 /I
mkdir -p blocked/b.log
check_both "a directory in the way"  5 $'src\\a.txt\nsrc\\b.log\n1 File(s) copied\n' \
    $'File creation error - Access is denied.\n' src blocked /Y
check_both "/C continues"            5 $'src\\a.txt\nsrc\\b.log\nsrc\\bin.dat\n2 File(s) copied\n' \
    $'File creation error - Access is denied.\n' src blocked /Y /C
printf 'file\n' > blockfile
check_both "cannot create a directory" 5 "$none" $'Unable to create directory - blockfile\\x\n' src 'blockfile\x' /I

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
