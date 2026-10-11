#include "SystemState.h"
#include "Actuators.h"
#include "MqCalibration.h"
#include "MqResponse.h"
#include <BiomassConfig.h>
#include <math.h>

using std::isfinite;
using std::isnan;

float threshold_chamber_temp_c = 80.0;
float threshold_mq2_v = 2.5;

float current_temp_c = NAN;
float current_chamber_c = NAN;
float current_mq135_v = NAN;
float current_mq2_v = NAN;
float current_mq2_response_ratio = NAN;
float current_mq135_response_ratio = NAN;
float threshold_mq2_response_ratio = NAN;
Mq2ThresholdMode mq2_threshold_mode = Mq2ThresholdMode::LegacyVoltage;
Mq2ThresholdMode mq2_safety_mode = Mq2ThresholdMode::LegacyVoltage;

bool state_needs_save = false;

bool manual_sprinkler = false;
bool catastrophic_latch = false;
String active_triggers_json = "[]";

static bool temp_latch_danger = false;
static bool mq2_latch_danger = false;
static PmsReading latest_pms_reading{};
static uint32_t latest_pms_sampled_at_ms = 0;
static bool has_pms_reading = false;

constexpr float MQ2_GAS_DANGER_V = 2.5f;
constexpr float MQ2_RAIL_SHORT_V = 4.8f;

#ifdef ARDUINO
SemaphoreHandle_t stateMutex = nullptr;
Preferences preferences;

void initSystemState() {
  stateMutex = xSemaphoreCreateMutex();
  if (stateMutex == NULL) {
    Serial.println("FATAL: Failed to create stateMutex!");
    ESP.restart(); // Reboot to attempt recovery
  }

  preferences.begin("biomass", false);

  initMqConfigStore();
  resetMqCalibrationState();

  resetPmsReadingCache();

  threshold_chamber_temp_c = preferences.getFloat("chamber_temp", 80.0);
  threshold_mq2_v = preferences.getFloat("mq2_v", 2.5);
}

void saveSystemState(float chamber_limit, float mq2_limit) {
  preferences.putFloat("chamber_temp", chamber_limit);
  preferences.putFloat("mq2_v", mq2_limit);
}
#else
SemaphoreHandle_t stateMutex = nullptr;
void initSystemState() {
  initMqConfigStore();
  resetMqCalibrationState();
  resetPmsReadingCache();
}
void saveSystemState(float chamber_limit, float mq2_limit) {}
#endif

ThresholdUpdateResult applyThresholdUpdate(bool has_chamber_limit,
                                           float chamber_limit,
                                           bool has_mq2_limit,
                                           float mq2_limit) {
  if ((!has_chamber_limit && !has_mq2_limit) ||
      (has_chamber_limit &&
       (!isfinite(chamber_limit) || chamber_limit < 20.0f ||
        chamber_limit > 150.0f)) ||
      (has_mq2_limit &&
       (!isfinite(mq2_limit) || mq2_limit < 0.1f || mq2_limit > 5.0f))) {
    return ThresholdUpdateResult::Invalid;
  }

#ifdef ARDUINO
  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5)) != pdTRUE) {
    return ThresholdUpdateResult::Busy;
  }
#endif

  bool changed = false;
  if (has_chamber_limit && threshold_chamber_temp_c != chamber_limit) {
    threshold_chamber_temp_c = chamber_limit;
    changed = true;
  }
  if (has_mq2_limit && threshold_mq2_v != mq2_limit) {
    threshold_mq2_v = mq2_limit;
    changed = true;
  }
  if (changed) {
    state_needs_save = true;
    evaluateSafetyLoop();
  }

#ifdef ARDUINO
  xSemaphoreGive(stateMutex);
#endif
  return ThresholdUpdateResult::Accepted;
}

ManualSprinklerResult applyManualSprinklerCommand(bool enabled) {
#ifdef ARDUINO
  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5)) != pdTRUE) {
    return ManualSprinklerResult::Busy;
  }
#endif

  if (catastrophic_latch || temp_latch_danger) {
#ifdef ARDUINO
    xSemaphoreGive(stateMutex);
#endif
    return ManualSprinklerResult::SafetyOverride;
  }

  manual_sprinkler = enabled;
  requestSprinkler(enabled);

#ifdef ARDUINO
  xSemaphoreGive(stateMutex);
#endif
  return ManualSprinklerResult::Accepted;
}

void processSensorReadings(float temperature_c, float chamber_c, float mq135_v,
                           float mq2_v) {
  processSensorReadings(temperature_c, chamber_c, mq135_v, mq2_v, 0);
}

void processSensorReadings(float temperature_c, float chamber_c, float mq135_v,
                           float mq2_v, uint32_t sampled_at_ms) {
  if (stateMutex != nullptr) {
    xSemaphoreTake(stateMutex, portMAX_DELAY);
  }

  current_temp_c = temperature_c;
  current_chamber_c = chamber_c;
  current_mq135_v = mq135_v;
  current_mq2_v = mq2_v;
  const MqConfiguration &mq_config = currentMqConfiguration();
#if MQ_RESPONSE_CIRCUIT_VERIFIED
  current_mq2_response_ratio = calculateMqResponseRatio(
      mq2_v, mq_config.mq2_baseline_v, mq_config.mq2_supply_v);
  current_mq135_response_ratio = calculateMqResponseRatio(
      mq135_v, mq_config.mq135_baseline_v, mq_config.mq135_supply_v);
#else
  current_mq2_response_ratio = NAN;
  current_mq135_response_ratio = NAN;
#endif
  recordMqCalibrationSamples(mq2_v, mq135_v, sampled_at_ms);

  evaluateSafetyLoop();

  if (stateMutex != nullptr) {
    xSemaphoreGive(stateMutex);
  }
}

void recordPmsReading(const PmsReading &reading, uint32_t sampled_at_ms) {
  if (stateMutex != nullptr) {
    xSemaphoreTake(stateMutex, portMAX_DELAY);
  }

  latest_pms_reading = reading;
  latest_pms_sampled_at_ms = sampled_at_ms;
  has_pms_reading = true;

  if (stateMutex != nullptr) {
    xSemaphoreGive(stateMutex);
  }
}

void resetPmsReadingCache() {
  latest_pms_reading = {};
  latest_pms_sampled_at_ms = 0;
  has_pms_reading = false;
}

bool copyFreshPmsReadingLocked(uint32_t now_ms, PmsReading &out) {
  if (!has_pms_reading ||
      static_cast<uint32_t>(now_ms - latest_pms_sampled_at_ms) >
          PMS_READING_FRESHNESS_MS) {
    return false;
  }

  out = latest_pms_reading;
  return true;
}

void evaluateSafetyLoop() {
  bool is_temp_fault = isnan(current_chamber_c);
  bool is_mq2_fault =
      isnan(current_mq2_v) || current_mq2_v > MQ2_RAIL_SHORT_V;

  bool in_temp_danger =
      !is_temp_fault && (current_chamber_c >= threshold_chamber_temp_c);
  const bool response_is_usable = std::isfinite(current_mq2_response_ratio);
  mq2_safety_mode = mq2_threshold_mode == Mq2ThresholdMode::ResponseRatio &&
                            response_is_usable
                        ? Mq2ThresholdMode::ResponseRatio
                        : Mq2ThresholdMode::LegacyVoltage;
  const float mq2_limit = mq2_safety_mode == Mq2ThresholdMode::ResponseRatio
                              ? threshold_mq2_response_ratio
                              : MQ2_GAS_DANGER_V;
  const float mq2_value = mq2_safety_mode == Mq2ThresholdMode::ResponseRatio
                              ? current_mq2_response_ratio
                              : current_mq2_v;
  bool in_mq2_danger = !is_mq2_fault && (mq2_value >= mq2_limit);

  if (in_temp_danger) {
    temp_latch_danger = true;
  } else if (!is_temp_fault &&
             current_chamber_c <= threshold_chamber_temp_c * 0.95f) {
    temp_latch_danger = false;
  }
  if (in_mq2_danger) {
    mq2_latch_danger = true;
  } else if (!is_mq2_fault && mq2_value <= mq2_limit * 0.95f) {
    mq2_latch_danger = false;
  }

  // Check catastrophic fire latch condition:
  // Only latch if the system was actively in temperature danger when the sensor
  // faulted. Manual blind-fire during a fault must NOT trip the catastrophic
  // latch.
  if (is_temp_fault && temp_latch_danger) {
    catastrophic_latch = true;
  }

  String triggers = "[";
  bool first = true;
  auto add_trigger = [&](const char *name) {
    if (!first)
      triggers += ",";
    triggers += "\"";
    triggers += name;
    triggers += "\"";
    first = false;
  };

  if (catastrophic_latch)
    add_trigger("catastrophic_latch");
  if (temp_latch_danger)
    add_trigger("high_chamber_temp");
  if (mq2_latch_danger)
    add_trigger("high_mq2_gas");
  if (is_temp_fault)
    add_trigger("temp_sensor_fault");
  if (is_mq2_fault)
    add_trigger("mq2_sensor_fault");
  triggers += "]";
  active_triggers_json = triggers;

  if (catastrophic_latch || temp_latch_danger) {
    requestSprinkler(true);
    manual_sprinkler = false;
  } else if (is_temp_fault) {
    // Temp fault defaults to OFF unless manual sprinkler is actively engaged
    // (blind-fire) Critical ruling: Do not clear manual_sprinkler here
    requestSprinkler(manual_sprinkler);
  } else {
    requestSprinkler(manual_sprinkler);
  }

  setFan(true);
  if (is_temp_fault || is_mq2_fault) {
    setLedStatus(false, true, false);
  } else if (temp_latch_danger) {
    setLedStatus(true, false, false);
  } else {
    setLedStatus(false, false, true);
  }
  setBuzzer(!is_temp_fault && current_chamber_c > threshold_chamber_temp_c);
}

void updateActuatorTransitions() {
#ifdef ARDUINO
  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5)) != pdTRUE) {
    return;
  }
#endif

  updateSprinklerActuators();

#ifdef ARDUINO
  xSemaphoreGive(stateMutex);
#endif
}
