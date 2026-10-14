#include "SafetyThresholds.h"

#include <cmath>
#include <limits>

namespace {

constexpr uint8_t field_count = static_cast<uint8_t>(ThresholdField::Count);
constexpr uint16_t supported_fields = (1u << field_count) - 1u;
constexpr std::array<const char *, field_count> field_names = {
    "threshold_chamber_temp_c", "threshold_mq2_v", "threshold_mq135_v",
    "threshold_temperature_c", "threshold_pm1_0_ug_m3",
    "threshold_pm2_5_ug_m3", "threshold_pm10_ug_m3",
    "threshold_humidity_min_percent", "threshold_humidity_max_percent"};

bool validFieldValue(ThresholdField field, float value) {
  if (!std::isfinite(value)) {
    return false;
  }
  switch (field) {
  case ThresholdField::Chamber:
    return value >= 20.0f && value <= 150.0f;
  case ThresholdField::Mq2:
  case ThresholdField::Mq135:
    return value >= 0.1f && value <= 5.0f;
  case ThresholdField::Ambient:
    return value >= -40.0f && value <= 80.0f;
  case ThresholdField::Pm1:
  case ThresholdField::Pm25:
  case ThresholdField::Pm10:
    return value > 0.0f && value <= 65535.0f;
  case ThresholdField::HumidityMin:
  case ThresholdField::HumidityMax:
    return value >= 0.0f && value <= 100.0f;
  case ThresholdField::Count:
    return false;
  }
  return false;
}

}

SafetyThresholds defaultSafetyThresholds() {
  SafetyThresholds defaults;
  defaults.values.fill(std::numeric_limits<float>::quiet_NaN());
  defaults.values[static_cast<uint8_t>(ThresholdField::Chamber)] = 80.0f;
  defaults.values[static_cast<uint8_t>(ThresholdField::Mq2)] = 2.5f;
  return defaults;
}

const char *thresholdFieldName(ThresholdField field) {
  const auto index = static_cast<uint8_t>(field);
  return index < field_count ? field_names[index] : nullptr;
}

bool validateStoredThresholds(const SafetyThresholds &values) {
  for (uint8_t index = 0; index < field_count; ++index) {
    const float value = values.values[index];
    if (index >= static_cast<uint8_t>(ThresholdField::Mq135) &&
        std::isnan(value)) {
      continue;
    }
    if (!validFieldValue(static_cast<ThresholdField>(index), value)) {
      return false;
    }
  }
  const float minimum =
      values.values[static_cast<uint8_t>(ThresholdField::HumidityMin)];
  const float maximum =
      values.values[static_cast<uint8_t>(ThresholdField::HumidityMax)];
  return (std::isnan(minimum) && std::isnan(maximum)) || minimum < maximum;
}

bool validateThresholdPatch(const SafetyThresholds &current,
                            const ThresholdPatch &patch,
                            SafetyThresholds &accepted) {
  if (patch.fields == 0 || (patch.fields & ~supported_fields) != 0) {
    return false;
  }
  SafetyThresholds candidate = current;
  for (uint8_t index = 0; index < field_count; ++index) {
    if ((patch.fields & (1u << index)) == 0) {
      continue;
    }
    const float value = patch.values.values[index];
    if (!validFieldValue(static_cast<ThresholdField>(index), value)) {
      return false;
    }
    candidate.values[index] = value;
  }
  if (!validateStoredThresholds(candidate)) {
    return false;
  }
  accepted = candidate;
  return true;
}
