#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir=${N2T_TOOLS_DIR:-}

if [[ ! -f "$tools_dir/TextComparer.sh" ]]; then
  printf 'Set N2T_TOOLS_DIR to the native nand2tetris tools directory.\n' >&2
  exit 2
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/bin"

cc -std=c11 -Wall -Wextra -Wpedantic "$repo_root"/09/*.c -o "$work_dir/bin/jack-parser"
cc -std=c11 -Wall -Wextra -Wpedantic -I"$repo_root/09" \
  "$repo_root/09/tokenizer.c" "$repo_root/tests/tokenizer_xml.c" \
  -o "$work_dir/bin/jack-tokenizer"
cc -std=c11 -Wall -Wextra -Wpedantic "$repo_root"/10/*.c -o "$work_dir/bin/jack-compiler"

compare_files() {
  sh "$tools_dir/TextComparer.sh" "$1" "$2"
}

copy_jack_sources() {
  local source_dir=$1
  local output_dir=$2
  mkdir -p "$output_dir"
  while IFS= read -r -d '' source_file; do
    cp "$source_file" "$output_dir/"
  done < <(find "$source_dir" -maxdepth 1 -type f -name '*.jack' -print0)
}

run_parser_fixture() {
  local fixture_dir=$1
  local output_dir="$work_dir/parser/$(basename "$fixture_dir")"
  copy_jack_sources "$fixture_dir" "$output_dir"
  "$work_dir/bin/jack-parser" "$output_dir"

  while IFS= read -r -d '' source_file; do
    local base_name
    base_name=$(basename "$source_file" .jack)
    compare_files "$fixture_dir/$base_name.xml" "$output_dir/$base_name.xml"

    if [[ -f "$fixture_dir/${base_name}T.xml" ]]; then
      "$work_dir/bin/jack-tokenizer" "$source_file" > "$output_dir/${base_name}T.xml"
      compare_files "$fixture_dir/${base_name}T.xml" "$output_dir/${base_name}T.xml"
    fi
  done < <(find "$fixture_dir" -maxdepth 1 -type f -name '*.jack' -print0)
}

run_compiler_fixture() {
  local fixture_dir=$1
  local output_dir="$work_dir/compiler/$(basename "$fixture_dir")"
  copy_jack_sources "$fixture_dir" "$output_dir"
  "$work_dir/bin/jack-compiler" "$output_dir"

  while IFS= read -r -d '' source_file; do
    local base_name
    base_name=$(basename "$source_file" .jack)
    compare_files "$fixture_dir/$base_name.vm" "$output_dir/$base_name.vm"
  done < <(find "$fixture_dir" -maxdepth 1 -type f -name '*.jack' -print0)
}

for fixture in \
  "$repo_root/09/10/ArrayTest" \
  "$repo_root/09/10/ExpressionLessSquare" \
  "$repo_root/09/10/Square"; do
  run_parser_fixture "$fixture"
done

for fixture in \
  "$repo_root/10/11/Average" \
  "$repo_root/10/11/ComplexArrays" \
  "$repo_root/10/11/ConvertToBin" \
  "$repo_root/10/11/Pong" \
  "$repo_root/10/11/Seven" \
  "$repo_root/10/11/Square"; do
  run_compiler_fixture "$fixture"
done

runtime_dir="$work_dir/compiler-runtime"
mkdir -p "$runtime_dir"
cp "$repo_root/tests/fixtures/JackRuntime/"* "$runtime_dir/"
cp "$tools_dir"/OS/*.vm "$runtime_dir/"
"$work_dir/bin/jack-compiler" "$runtime_dir"
sh "$tools_dir/VMEmulator.sh" "$runtime_dir/Runtime.tst"