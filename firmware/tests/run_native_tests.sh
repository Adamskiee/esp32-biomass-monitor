#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

g++ \
  -std=c++17 \
  -Wall \
  -Wextra \
  -Werror \
  -Wno-unused-parameter \
  -DMQ_RESPONSE_CIRCUIT_VERIFIED=1 \
  -I "$repo_dir/firmware/main" \
  -I "$repo_dir/firmware/shared/BiomassConfig/src" \
  "$repo_dir/firmware/main/Actuators.cpp" \
  "$repo_dir/firmware/main/MqResponse.cpp" \
  "$repo_dir/firmware/main/MqConfigStore.cpp" \
  "$repo_dir/firmware/main/MqCalibration.cpp" \
  "$repo_dir/firmware/main/SystemState.cpp" \
  "$script_dir/native_tests.cpp" \
  -o "$build_dir/native_firmware_tests"

"$build_dir/native_firmware_tests"
