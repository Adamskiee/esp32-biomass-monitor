#include "MqResponse.h"

#include <cmath>

namespace {

constexpr float MIN_VALID_MQ_V = 0.1f;
constexpr float MAX_VALID_MQ_V = 4.8f;

bool isValidVoltage(float value) {
  return std::isfinite(value) && value > MIN_VALID_MQ_V &&
         value < MAX_VALID_MQ_V;
}

} // namespace

float calculateMqResponseRatio(float output_v, float baseline_v,
                               float supply_v) {
  if (!isValidVoltage(output_v) || !isValidVoltage(baseline_v) ||
      !std::isfinite(supply_v) || supply_v <= output_v ||
      supply_v <= baseline_v) {
    return NAN;
  }

  return (output_v * (supply_v - baseline_v)) /
         (baseline_v * (supply_v - output_v));
}
