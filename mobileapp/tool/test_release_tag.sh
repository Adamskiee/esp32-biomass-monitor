#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
script="$root_dir/tool/release_tag.sh"
pubspec="$root_dir/pubspec.yaml"

test "$(bash "$script" tag v1.3.0 "$pubspec")" = "1.3.0"

if bash "$script" tag v1.3.1 "$pubspec"; then
  echo "Expected rejection for a tag that does not match pubspec.yaml" >&2
  exit 1
fi

for invalid_ref in "branch main" "tag v1.2" "tag v1.2.3-rc1" 'tag v1.2.3; touch /tmp/release-tag-injection'; do
  read -r ref_type ref_name <<< "$invalid_ref"
  if bash "$script" "$ref_type" "$ref_name" "$pubspec"; then
    echo "Expected rejection for: $invalid_ref" >&2
    exit 1
  fi
done

test ! -e /tmp/release-tag-injection
