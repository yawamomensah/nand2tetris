#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir=${N2T_TOOLS_DIR:-}
projects_dir=${N2T_PROJECTS_DIR:-}

if [[ ! -f "$tools_dir/Assembler.sh" || ! -f "$tools_dir/CPUEmulator.sh" || ! -f "$tools_dir/TextComparer.sh" ]]; then
  printf 'Set N2T_TOOLS_DIR to the native nand2tetris tools directory.\n' >&2
  exit 2
fi

if [[ ! -d "$projects_dir/04" || ! -d "$projects_dir/07" || ! -d "$projects_dir/08" ]]; then
  printf 'Set N2T_PROJECTS_DIR to the official projects checkout.\n' >&2
  exit 2
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/bin"
cc -std=gnu11 "$repo_root"/06/*.c -o "$work_dir/bin/assembler"
cc -std=gnu11 "$repo_root"/07/*.c -o "$work_dir/bin/vmtranslator07"
cc -std=gnu11 "$repo_root"/08/*.c -o "$work_dir/bin/vmtranslator08"

compare_files() {
  sh "$tools_dir/TextComparer.sh" "$1" "$2"
}

assembler_test_dir="$work_dir/assembler/Mult"
mkdir -p "$assembler_test_dir"
cp "$repo_root/04/mult/Mult.asm" "$assembler_test_dir/"
cp "$projects_dir/04/mult/Mult.tst" "$projects_dir/04/mult/Mult.cmp" \
  "$assembler_test_dir/"
"$work_dir/bin/assembler" "$assembler_test_dir/Mult.asm"
sed 's/load Mult\.asm,/load Mult.hack,/' \
  "$assembler_test_dir/Mult.tst" > "$assembler_test_dir/Mult.generated.tst"
sh "$tools_dir/CPUEmulator.sh" "$assembler_test_dir/Mult.generated.tst"

run_cpu_test() {
  local test_dir=$1
  sh "$tools_dir/CPUEmulator.sh" "$test_dir/$(basename "$test_dir").tst"
}

for fixture in \
  "$projects_dir/07/MemoryAccess/BasicTest" \
  "$projects_dir/07/MemoryAccess/PointerTest" \
  "$projects_dir/07/MemoryAccess/StaticTest" \
  "$projects_dir/07/StackArithmetic/SimpleAdd" \
  "$projects_dir/07/StackArithmetic/StackTest"; do
  test_dir="$work_dir/project07/$(basename "$fixture")"
  mkdir -p "$test_dir"
  cp "$fixture"/*.vm "$fixture"/*.tst "$fixture"/*.cmp "$test_dir/"
  "$work_dir/bin/vmtranslator07" "$test_dir/$(basename "$fixture").vm"
  run_cpu_test "$test_dir"
done

run_project08_test() {
  local fixture=$1
  local mode=$2
  local source_dir="$projects_dir/08/$fixture"
  local test_dir="$work_dir/project08/$(basename "$fixture")"

  mkdir -p "$test_dir"
  cp "$source_dir"/*.vm "$source_dir"/*.tst "$source_dir"/*.cmp "$test_dir/"

  if [[ "$mode" == directory ]]; then
    "$work_dir/bin/vmtranslator08" "$test_dir"
  else
    local vm_file
    vm_file=$(find "$test_dir" -maxdepth 1 -type f -name '*.vm' -print -quit)
    "$work_dir/bin/vmtranslator08" "$vm_file"
  fi

  run_cpu_test "$test_dir"
}

run_project08_test ProgramFlow/BasicLoop single
run_project08_test ProgramFlow/FibonacciSeries single
run_project08_test FunctionCalls/SimpleFunction single
run_project08_test FunctionCalls/NestedCall directory
run_project08_test FunctionCalls/StaticsTest directory
run_project08_test FunctionCalls/FibonacciElement directory