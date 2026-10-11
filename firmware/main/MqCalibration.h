#pragma once

#include "MqConfigStore.h"

#include <cstdint>

enum class MqSensor { Mq2, Mq135 };

enum class MqCalibrationResult {
  Accepted,
  InvalidSamples,
  WarmingUp,
  RelativeModeActive,
  Cooldown,
  PersistenceFailed,
  Busy,
};

void resetMqCalibrationState(MqConfigStore *store = nullptr);
void recordMqCalibrationSamples(float mq2_v, float mq135_v, uint32_t now_ms);
MqCalibrationResult captureMqCalibration(MqSensor sensor, uint32_t now_ms);
const MqConfiguration &currentMqConfiguration();
