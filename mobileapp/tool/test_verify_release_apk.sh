#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <signed-apk> <package> <version-name> <version-code>" >&2
  exit 2
fi

root_dir=$(cd "$(dirname "$0")/.." && pwd)
script="$root_dir/tool/verify_release_apk.sh"
apk=$1
package_name=$2
version_name=$3
version_code=$4

bash "$script" "$apk" "$package_name" "$version_name" "$version_code"

for expected in "com.example.wrong $version_name $version_code" "$package_name 9.9.9 $version_code" "$package_name $version_name 999"; do
  read -r test_package test_name test_code <<< "$expected"
  if bash "$script" "$apk" "$test_package" "$test_name" "$test_code"; then
    echo "Expected metadata mismatch rejection" >&2
    exit 1
  fi
done

empty_apk=$(mktemp --suffix=.apk)
trap 'rm -f "$empty_apk"' EXIT
if bash "$script" "$empty_apk" "$package_name" "$version_name" "$version_code"; then
  echo "Expected invalid APK rejection" >&2
  exit 1
fi
