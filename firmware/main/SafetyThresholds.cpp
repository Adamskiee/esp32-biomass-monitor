#include "SafetyThresholds.h"

#include <cmath>
#include <cstring>
#include <limits>

namespace {

static_assert(sizeof(float) == sizeof(uint32_t) &&
                  std::numeric_limits<float>::is_iec559,
              "Threshold records require IEEE-754 32-bit floats");
constexpr uint32_t record_version = 1;

void writeLittleEndian(uint8_t *bytes, uint32_t value) {
  for (size_t i = 0; i < 4; ++i) {
    bytes[i] = static_cast<uint8_t>(value >> (8 * i));
  }
}

uint32_t readLittleEndian(const uint8_t *bytes) {
  uint32_t value = 0;
  for (size_t i = 0; i < 4; ++i) {
    value |= static_cast<uint32_t>(bytes[i]) << (8 * i);
  }
  return value;
}

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
  return SafetyThresholds{{80.0f, 2.5f, 2.0f, 35.0f, 15.0f, 15.0f, 45.0f,
                           30.0f, 60.0f}};
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

std::array<uint8_t, THRESHOLD_RECORD_BYTES>
encodeThresholdRecord(const SafetyThresholds &values) {
  std::array<uint8_t, THRESHOLD_RECORD_BYTES> bytes{};
  writeLittleEndian(bytes.data(), record_version);
  for (size_t i = 0; i < values.values.size(); ++i) {
    uint32_t bits;
    std::memcpy(&bits, &values.values[i], sizeof(bits));
    writeLittleEndian(bytes.data() + 4 + i * 4, bits);
  }
  return bytes;
}

bool decodeThresholdRecord(const uint8_t *bytes, size_t length,
                           SafetyThresholds &accepted) {
  if (bytes == nullptr || length != THRESHOLD_RECORD_BYTES ||
      readLittleEndian(bytes) != record_version) {
    return false;
  }
  SafetyThresholds candidate;
  for (size_t i = 0; i < candidate.values.size(); ++i) {
    const uint32_t bits = readLittleEndian(bytes + 4 + i * 4);
    std::memcpy(&candidate.values[i], &bits, sizeof(bits));
  }
  if (!validateStoredThresholds(candidate)) {
    return false;
  }
  const auto defaults = defaultSafetyThresholds();
  for (size_t i = 0; i < candidate.values.size(); ++i) {
    if (std::isnan(candidate.values[i])) {
      candidate.values[i] = defaults.values[i];
    }
  }
  accepted = candidate;
  return true;
}
