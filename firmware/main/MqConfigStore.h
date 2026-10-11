#pragma once

#include <cstdint>

struct MqConfiguration {
  uint32_t version = 1;
  float mq2_baseline_v = 0.0f;
  float mq135_baseline_v = 0.0f;
  float mq2_supply_v = 0.0f;
  float mq135_supply_v = 0.0f;
  uint32_t mq2_calibration_id = 0;
  uint32_t mq135_calibration_id = 0;
  float mq2_response_threshold = 0.0f;
  bool mq2_relative_mode = false;
};

class MqConfigStore {
public:
  virtual ~MqConfigStore() = default;
  virtual bool load(MqConfiguration &configuration) = 0;
  virtual bool save(const MqConfiguration &configuration) = 0;
};

void initMqConfigStore();
MqConfigStore *defaultMqConfigStore();
bool canWriteSettings(uint32_t now_ms);
void recordSettingsWrite(uint32_t now_ms);
void resetSettingsWriteCoordinator();
