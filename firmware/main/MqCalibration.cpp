#include "MqCalibration.h"

#include <BiomassConfig.h>

#include <algorithm>
#include <cmath>

namespace {

constexpr size_t SAMPLE_COUNT = 30;

struct SampleWindow {
  float values[SAMPLE_COUNT]{};
  uint32_t timestamps[SAMPLE_COUNT]{};
  size_t count = 0;
  size_t next = 0;

  void add(float value, uint32_t timestamp) {
    values[next] = value;
    timestamps[next] = timestamp;
    next = (next + 1) % SAMPLE_COUNT;
    if (count < SAMPLE_COUNT) {
      ++count;
    }
  }
};

MqConfiguration configuration{};
MqConfigStore *config_store = nullptr;
SampleWindow mq2_samples;
SampleWindow mq135_samples;
uint32_t next_calibration_id = 1;

bool isValidCaptureValue(float value) {
  return std::isfinite(value) && value > 0.1f && value < 4.5f;
}

bool isStableWindow(const SampleWindow &window, float &median) {
  if (window.count != SAMPLE_COUNT) {
    return false;
  }

  float sorted[SAMPLE_COUNT];
  for (size_t i = 0; i < SAMPLE_COUNT; ++i) {
    if (!isValidCaptureValue(window.values[i])) {
      return false;
    }
    sorted[i] = window.values[i];
  }
  std::sort(sorted, sorted + SAMPLE_COUNT);
  median = (sorted[14] + sorted[15]) / 2.0f;
  if (!isValidCaptureValue(median) ||
      sorted[26] - sorted[3] > median * 0.05f) {
    return false;
  }

  uint32_t oldest = window.timestamps[0];
  uint32_t newest = window.timestamps[0];
  for (size_t i = 1; i < SAMPLE_COUNT; ++i) {
    if (static_cast<int32_t>(window.timestamps[i] - newest) > 0) {
      newest = window.timestamps[i];
    }
    if (static_cast<int32_t>(window.timestamps[i] - oldest) < 0) {
      oldest = window.timestamps[i];
    }
  }
  return static_cast<uint32_t>(newest - oldest) >= 58000;
}

} // namespace

void resetMqCalibrationState(MqConfigStore *store) {
  resetSettingsWriteCoordinator();
  configuration = {};
  configuration.version = 1;
  config_store = store ? store : defaultMqConfigStore();
  if (config_store) {
    MqConfiguration loaded{};
    if (config_store->load(loaded)) {
      configuration = loaded;
    }
  }
  mq2_samples = {};
  mq135_samples = {};
  next_calibration_id = std::max(configuration.mq2_calibration_id,
                                 configuration.mq135_calibration_id) +
                        1;
}

void recordMqCalibrationSamples(float mq2_v, float mq135_v, uint32_t now_ms) {
  mq2_samples.add(mq2_v, now_ms);
  mq135_samples.add(mq135_v, now_ms);
}

MqCalibrationResult captureMqCalibration(MqSensor sensor, uint32_t now_ms) {
#if !MQ_RESPONSE_CIRCUIT_VERIFIED
  return MqCalibrationResult::InvalidSamples;
#else
  if (now_ms < MQ_STARTUP_WARMUP_MS) {
    return MqCalibrationResult::WarmingUp;
  }
  if (sensor == MqSensor::Mq2 && configuration.mq2_relative_mode) {
    return MqCalibrationResult::RelativeModeActive;
  }
  if (!canWriteSettings(now_ms)) {
    return MqCalibrationResult::Cooldown;
  }

  const SampleWindow &window = sensor == MqSensor::Mq2 ? mq2_samples : mq135_samples;
  float baseline = 0.0f;
  if (!isStableWindow(window, baseline)) {
    return MqCalibrationResult::InvalidSamples;
  }
  if (sensor == MqSensor::Mq2) {
    for (float value : window.values) {
      if (value >= 2.5f) {
        return MqCalibrationResult::InvalidSamples;
      }
    }
  }

  MqConfiguration updated = configuration;
  if (sensor == MqSensor::Mq2) {
    updated.mq2_baseline_v = baseline;
    updated.mq2_supply_v = MQ_CIRCUIT_SUPPLY_V;
    updated.mq2_calibration_id = next_calibration_id;
  } else {
    updated.mq135_baseline_v = baseline;
    updated.mq135_supply_v = MQ_CIRCUIT_SUPPLY_V;
    updated.mq135_calibration_id = next_calibration_id;
  }
  if (!config_store || !config_store->save(updated)) {
    return MqCalibrationResult::PersistenceFailed;
  }

  configuration = updated;
  ++next_calibration_id;
  recordSettingsWrite(now_ms);
  return MqCalibrationResult::Accepted;
#endif
}

const MqConfiguration &currentMqConfiguration() { return configuration; }
