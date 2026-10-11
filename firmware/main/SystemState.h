#pragma once
#include "PmsReading.h"
#ifdef ARDUINO
#include <Arduino.h>
#include <Preferences.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#else
#include <cmath>
#include <cstdint>
#include <string>
typedef std::string String;
typedef void *SemaphoreHandle_t;
#define portMAX_DELAY 0xFFFF
inline void xSemaphoreTake(SemaphoreHandle_t, uint32_t) {}
inline void xSemaphoreGive(SemaphoreHandle_t) {}
#endif

// Thresholds
extern float threshold_chamber_temp_c;
extern float threshold_mq2_v;
// Cached Sensor Readings (API reads these instead of blocking)
extern float current_temp_c;
extern float current_chamber_c;
extern float current_mq135_v;
extern float current_mq2_v;

extern bool state_needs_save;
extern SemaphoreHandle_t stateMutex;

extern bool manual_sprinkler;
extern bool catastrophic_latch;
extern String active_triggers_json;

enum class ThresholdUpdateResult {
  Accepted,
  Invalid,
  Busy,
};

enum class ManualSprinklerResult {
  Accepted,
  SafetyOverride,
  Busy,
};

ThresholdUpdateResult applyThresholdUpdate(bool has_chamber_limit,
                                           float chamber_limit,
                                           bool has_mq2_limit, float mq2_limit);
ManualSprinklerResult applyManualSprinklerCommand(bool enabled);
void processSensorReadings(float temperature_c, float chamber_c, float mq135_v,
                           float mq2_v);
void processSensorReadings(float temperature_c, float chamber_c, float mq135_v,
                           float mq2_v, uint32_t sampled_at_ms);
void recordPmsReading(const PmsReading &reading, uint32_t sampled_at_ms);
void resetPmsReadingCache();
// The caller holds stateMutex while copying the sample.
bool copyFreshPmsReadingLocked(uint32_t now_ms, PmsReading &out);
// On Arduino, the caller must hold stateMutex while evaluating outputs.
void evaluateSafetyLoop();
void updateActuatorTransitions();

void initSystemState();
void saveSystemState(float chamber_limit, float mq2_limit);
