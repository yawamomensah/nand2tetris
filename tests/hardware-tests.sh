#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir=${N2T_TOOLS_DIR:-}
projects_dir=${N2T_PROJECTS_DIR:-}

if [[ ! -f "$tools_dir/HardwareSimulator.sh" ]]; then
  printf 'Set N2T_TOOLS_DIR to the native nand2tetris tools directory.\n' >&2
  exit 2
fi

for project in 01 02 03 05; do
  if [[ ! -d "$projects_dir/$project" ]]; then
    printf 'Missing official Project %s fixtures under N2T_PROJECTS_DIR.\n' "$project" >&2
    exit 2
  fi
done

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
hardware_dir="$work_dir/hardware"
mkdir -p "$hardware_dir"

for chapter in 01 02 03 05; do
  while IFS= read -r -d '' hdl_file; do
    cp "$hdl_file" "$hardware_dir/"
  done < <(find "$repo_root/$chapter" -maxdepth 1 -type f -name '*.hdl' -print0)
done

copy_test_files() {
  local test_root=$1
  while IFS= read -r -d '' test_file; do
    local compare_file="${test_file%.tst}.cmp"
    if [[ ! -f "$compare_file" ]]; then
      printf 'Missing expected output for %s\n' "$test_file" >&2
      exit 1
    fi
    cp "$test_file" "$compare_file" "$hardware_dir/"
  done < <(find "$test_root" -type f -name '*.tst' -print0)
}

for project in 01 02 03 05; do
  copy_test_files "$projects_dir/$project"
done

find "$projects_dir/05" -maxdepth 1 -type f -name '*.hack' -exec cp {} "$hardware_dir/" \;

for test_file in "$hardware_dir"/*.tst; do
  printf 'Hardware test: %s\n' "$(basename "$test_file")"
  sh "$tools_dir/HardwareSimulator.sh" "$test_file"
done