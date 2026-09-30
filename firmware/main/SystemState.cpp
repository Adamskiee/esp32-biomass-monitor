#include "SystemState.h"
#include "Actuators.h"
#include <math.h>

using std::isfinite;
using std::isnan;

float threshold_chamber_temp_c = 80.0;
float threshold_mq2_v = 2.5;

float current_temp_c = NAN;
float current_chamber_c = NAN;
float current_mq135_v = NAN;
float current_mq2_v = NAN;

bool state_needs_save = false;

bool manual_sprinkler = false;
bool catastrophic_latch = false;
String active_triggers_json = "[]";

static bool temp_latch_danger = false;
static bool mq2_latch_danger = false;

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

  threshold_chamber_temp_c = preferences.getFloat("chamber_temp", 80.0);
  threshold_mq2_v = preferences.getFloat("mq2_v", 2.5);
}

void saveSystemState(float chamber_limit, float mq2_limit) {
  preferences.putFloat("chamber_temp", chamber_limit);
  preferences.putFloat("mq2_v", mq2_limit);
}
#else
SemaphoreHandle_t stateMutex = nullptr;
void initSystemState() {}
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
  setSolenoid(enabled, true);

#ifdef ARDUINO
  xSemaphoreGive(stateMutex);
#endif
  return ManualSprinklerResult::Accepted;
}

void processSensorReadings(float temperature_c, float chamber_c, float mq135_v,
                           float mq2_v) {
  if (stateMutex != nullptr) {
    xSemaphoreTake(stateMutex, portMAX_DELAY);
  }

  current_temp_c = temperature_c;
  current_chamber_c = chamber_c;
  current_mq135_v = mq135_v;
  current_mq2_v = mq2_v;

  evaluateSafetyLoop();

  if (stateMutex != nullptr) {
    xSemaphoreGive(stateMutex);
  }
}

void evaluateSafetyLoop() {
  bool is_temp_fault = isnan(current_chamber_c);
  bool is_mq2_fault =
      isnan(current_mq2_v) || current_mq2_v > MQ2_RAIL_SHORT_V;

  bool in_temp_danger =
      !is_temp_fault && (current_chamber_c >= threshold_chamber_temp_c);
  bool in_mq2_danger =
      !is_mq2_fault && (current_mq2_v >= MQ2_GAS_DANGER_V);

  if (in_temp_danger) {
    temp_latch_danger = true;
  } else if (!is_temp_fault &&
             current_chamber_c <= threshold_chamber_temp_c * 0.95f) {
    temp_latch_danger = false;
  }
  if (in_mq2_danger) {
    mq2_latch_danger = true;
  } else if (!is_mq2_fault &&
             current_mq2_v <= MQ2_GAS_DANGER_V * 0.95f) {
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
    setSolenoid(true, true);
    manual_sprinkler = false;
  } else if (is_temp_fault) {
    // Temp fault defaults to OFF unless manual sprinkler is actively engaged
    // (blind-fire) Critical ruling: Do not clear manual_sprinkler here
    setSolenoid(manual_sprinkler, false);
  } else {
    setSolenoid(manual_sprinkler, false);
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
