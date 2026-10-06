#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <apk-path> <expected-package> <expected-version-name> <expected-version-code>" >&2
  exit 2
fi

apk_path=$1
expected_package=$2
expected_version_name=$3
expected_version_code=$4

for command in apksigner aapt2; do
  command -v "$command" >/dev/null || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

if [ ! -f "$apk_path" ]; then
  echo "APK does not exist: $apk_path" >&2
  exit 1
fi

apksigner verify "$apk_path"
badging=$(aapt2 dump badging "$apk_path")
package_line=$(printf '%s\n' "$badging" | sed -n "s/^package: //p")

actual_package=$(printf '%s\n' "$package_line" | sed -n "s/^name='\([^']*\)'.*/\1/p")
actual_version_code=$(printf '%s\n' "$package_line" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
actual_version_name=$(printf '%s\n' "$package_line" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")

if [ "$actual_package" != "$expected_package" ] || [ "$actual_version_name" != "$expected_version_name" ] || [ "$actual_version_code" != "$expected_version_code" ]; then
  echo "APK metadata did not match expected package, version name, and version code" >&2
  exit 1
fi

printf 'Verified package=%s versionName=%s versionCode=%s\n' "$actual_package" "$actual_version_name" "$actual_version_code"
