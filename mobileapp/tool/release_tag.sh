#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <ref-type> <ref-name> <pubspec-path>" >&2
  exit 2
fi

ref_type=$1
ref_name=$2
pubspec_path=$3

if [[ "$ref_type" != "tag" || ! "$ref_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a tag in vMAJOR.MINOR.PATCH format" >&2
  exit 1
fi

if [ ! -f "$pubspec_path" ]; then
  echo "pubspec.yaml was not found: $pubspec_path" >&2
  exit 1
fi

tag_version=${ref_name#v}
pubspec_version=$(awk '/^[[:space:]]*version:[[:space:]]*/ { print $2; exit }' "$pubspec_path")
pubspec_name=${pubspec_version%%+*}

if [[ ! "$pubspec_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$ ]]; then
  echo "pubspec.yaml must define a numeric version in MAJOR.MINOR.PATCH+BUILD format" >&2
  exit 1
fi

if [ "$pubspec_name" != "$tag_version" ]; then
  echo "Release tag $ref_name does not match pubspec.yaml version $pubspec_version" >&2
  exit 1
fi

printf '%s\n' "$tag_version"
