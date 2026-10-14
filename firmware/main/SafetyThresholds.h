#pragma once

#include <array>
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
