#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <ref-type> <ref-name>" >&2
  exit 2
fi

ref_type=$1
ref_name=$2

if [[ "$ref_type" != "tag" || ! "$ref_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a tag in vMAJOR.MINOR.PATCH format" >&2
  exit 1
fi

printf '%s\n' "${ref_name#v}"
