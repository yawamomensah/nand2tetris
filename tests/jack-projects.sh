#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir=${N2T_TOOLS_DIR:-}
projects_dir=${N2T_PROJECTS_DIR:-}

resolve_project_dir() {
  local base_dir=$1
  local project_number=$2
  local candidate

  for candidate in \
    "$base_dir/$project_number" \
    "$base_dir/$(printf '%02d' "$project_number")"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

if [[ ! -f "$tools_dir/TextComparer.sh" || ! -f "$tools_dir/VMEmulator.sh" ]]; then
  printf 'Set N2T_TOOLS_DIR to the native nand2tetris tools directory.\n' >&2
  exit 2
fi

project11_dir=$(resolve_project_dir "$projects_dir" 11) || {
  printf 'Set N2T_PROJECTS_DIR to the official projects checkout.\n' >&2
  exit 2
}

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
}

for fixture in \
  "$repo_root/09/10/ArrayTest" \
  "$repo_root/09/10/ExpressionLessSquare" \
  "$repo_root/09/10/Square"; do
  run_parser_fixture "$fixture"
done

for fixture in \
  "$project11_dir/Average" \
  "$project11_dir/ComplexArrays" \
  "$project11_dir/ConvertToBin" \
  "$project11_dir/Pong" \
  "$project11_dir/Seven" \
  "$project11_dir/Square"; do
  run_compiler_fixture "$fixture"
done

runtime_dir="$work_dir/compiler/Seven"
cp "$tools_dir"/OS/*.vm "$runtime_dir/"
cp "$repo_root/tests/fixtures/Project11Seven/Seven."{cmp,tst} "$runtime_dir/"
sh "$tools_dir/VMEmulator.sh" "$runtime_dir/Seven.tst"