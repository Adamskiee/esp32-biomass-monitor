#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

enum class ThresholdField : uint8_t {
  Chamber,
  Mq2,
  Mq135,
  Ambient,
  Pm1,
  Pm25,
  Pm10,
  HumidityMin,
  HumidityMax,
  Count
};

struct SafetyThresholds {
  std::array<float, 9> values;
};

struct ThresholdPatch {
  SafetyThresholds values;
  uint16_t fields;
};

SafetyThresholds defaultSafetyThresholds();
const char *thresholdFieldName(ThresholdField field);
bool validateThresholdPatch(const SafetyThresholds &current,
                            const ThresholdPatch &patch,
                            SafetyThresholds &accepted);
bool validateStoredThresholds(const SafetyThresholds &values);

constexpr size_t THRESHOLD_RECORD_BYTES = 40;
std::array<uint8_t, THRESHOLD_RECORD_BYTES>
encodeThresholdRecord(const SafetyThresholds &values);
bool decodeThresholdRecord(const uint8_t *bytes, size_t length,
                           SafetyThresholds &accepted);
