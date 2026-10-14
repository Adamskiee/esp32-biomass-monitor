#include "SystemState.h"
#include "Actuators.h"
#include <BiomassConfig.h>
#include <math.h>

using std::isfinite;

SafetyThresholds safety_thresholds = defaultSafetyThresholds();

float current_temp_c = NAN;
float current_chamber_c = NAN;
float current_mq135_v = NAN;
float current_mq2_v = NAN;
float current_humidity_percent = NAN;

bool state_needs_save = false;

bool manual_sprinkler = false;
bool catastrophic_latch = false;
String active_triggers_json = "[]";

static std::array<bool, 7> upper_limit_danger{};
static bool low_humidity_danger = false;
static bool high_humidity_danger = false;
static PmsReading latest_pms_reading{};
static uint32_t latest_pms_sampled_at_ms = 0;
static bool has_pms_reading = false;
static uint32_t mq_warmup_started_at_ms = 0;
static bool mq_sensors_are_warming_up = false;

constexpr float MQ2_RAIL_SHORT_V = 4.8f;

namespace {

bool validAmbientTemperature(float value) {
  return isfinite(value) && value >= -40.0f && value <= 80.0f;
}

bool validHumidity(float value) {
  return isfinite(value) && value >= 0.0f && value <= 100.0f;
}

bool validUpperReading(size_t index, float value) {
  if (index == 1) {
    return !mq_sensors_are_warming_up && isfinite(value) &&
           value <= MQ2_RAIL_SHORT_V;
  }
  if (index == 2) {
    return !mq_sensors_are_warming_up && isfinite(value);
  }
  return index == 3 ? validAmbientTemperature(value) : isfinite(value);
}

std::array<float, 7> upperReadings(bool &pms_fresh) {
  PmsReading pms{};
  pms_fresh = copyFreshPmsReadingLocked(millis(), pms);
  return {current_chamber_c, current_mq2_v, current_mq135_v, current_temp_c,
          pms_fresh ? static_cast<float>(pms.pm1_0_ug_m3) : NAN,
          pms_fresh ? static_cast<float>(pms.pm2_5_ug_m3) : NAN,
          pms_fresh ? static_cast<float>(pms.pm10_ug_m3) : NAN};
}

void resetRuntimeState() {
  safety_thresholds = defaultSafetyThresholds();
  upper_limit_danger.fill(false);
  low_humidity_danger = false;
  high_humidity_danger = false;
  current_temp_c = NAN;
  current_chamber_c = NAN;
  current_mq135_v = NAN;
  current_mq2_v = NAN;
  current_humidity_percent = NAN;
  state_needs_save = false;
  manual_sprinkler = false;
  catastrophic_latch = false;
  active_triggers_json = "[]";
  mq_warmup_started_at_ms = 0;
  mq_sensors_are_warming_up = false;
  resetPmsReadingCache();
}

}

#ifdef ARDUINO
SemaphoreHandle_t stateMutex = nullptr;
Preferences preferences;

void initSystemState() {
  if (stateMutex == nullptr) {
    stateMutex = xSemaphoreCreateMutex();
  }
  if (stateMutex == NULL) {
    Serial.println("FATAL: Failed to create stateMutex!");
    ESP.restart(); // Reboot to attempt recovery
  }

  preferences.begin("biomass", false);

  resetRuntimeState();

  safety_thresholds.values[0] = preferences.getFloat("chamber_temp", 80.0);
  safety_thresholds.values[1] = preferences.getFloat("mq2_v", 2.5);
  if (!validateStoredThresholds(safety_thresholds)) {
    safety_thresholds = defaultSafetyThresholds();
  }
}

void saveSystemState(float chamber_limit, float mq2_limit) {
  preferences.putFloat("chamber_temp", chamber_limit);
  preferences.putFloat("mq2_v", mq2_limit);
}
#else
SemaphoreHandle_t stateMutex = nullptr;
void initSystemState() { resetRuntimeState(); }
void saveSystemState(float chamber_limit, float mq2_limit) {}
#endif

ThresholdUpdateResult applyThresholdUpdate(const ThresholdPatch &patch,
                                           SafetyThresholds *accepted) {
#ifdef ARDUINO
  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5)) != pdTRUE) {
    return ThresholdUpdateResult::Busy;
  }
#endif
  SafetyThresholds candidate;
  if (!validateThresholdPatch(safety_thresholds, patch, candidate)) {
#ifdef ARDUINO
    xSemaphoreGive(stateMutex);
#endif
    return ThresholdUpdateResult::Invalid;
  }
  bool pms_fresh;
  const auto readings = upperReadings(pms_fresh);
  bool changed = false;
  bool humidity_changed = false;
  for (size_t i = 0; i < candidate.values.size(); ++i) {
    if ((patch.fields & (1u << i)) != 0 &&
        candidate.values[i] != safety_thresholds.values[i]) {
      changed = true;
      if (i < upper_limit_danger.size() && validUpperReading(i, readings[i])) {
        upper_limit_danger[i] = false;
      }
      if (i >= static_cast<size_t>(ThresholdField::HumidityMin)) {
        humidity_changed = true;
      }
    }
  }
  if (humidity_changed && validHumidity(current_humidity_percent)) {
    low_humidity_danger = false;
    high_humidity_danger = false;
  }
  safety_thresholds = candidate;
  if (accepted != nullptr) {
    *accepted = safety_thresholds;
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

ThresholdUpdateResult applyThresholdUpdate(bool has_chamber_limit,
                                           float chamber_limit,
                                           bool has_mq2_limit,
                                           float mq2_limit) {
  ThresholdPatch patch{defaultSafetyThresholds(), 0};
  if (has_chamber_limit) {
    patch.fields |= 1u << 0;
    patch.values.values[0] = chamber_limit;
  }
  if (has_mq2_limit) {
    patch.fields |= 1u << 1;
    patch.values.values[1] = mq2_limit;
  }
  return applyThresholdUpdate(patch);
}

ManualSprinklerResult applyManualSprinklerCommand(bool enabled) {
#ifdef ARDUINO
  if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5)) != pdTRUE) {
    return ManualSprinklerResult::Busy;
  }
#endif

  if (catastrophic_latch || upper_limit_danger[0]) {
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

void startMqWarmup(uint32_t now_ms) { mq_warmup_started_at_ms = now_ms; }

uint32_t mqWarmupRemainingSeconds(uint32_t now_ms) {
  const uint32_t elapsed_ms = now_ms - mq_warmup_started_at_ms;
  if (elapsed_ms >= MQ_WARMUP_DURATION_MS) {
    return 0;
  }
  return (MQ_WARMUP_DURATION_MS - elapsed_ms + 999) / 1000;
}

bool mqSensorsAreWarmingUp() { return mq_sensors_are_warming_up; }

void processSensorReadings(float temperature_c, float chamber_c, float mq135_v,
                           float mq2_v, bool mq_sensors_warming_up,
                           float humidity_percent) {
  if (stateMutex != nullptr) {
    xSemaphoreTake(stateMutex, portMAX_DELAY);
  }

  current_humidity_percent = humidity_percent;
  current_temp_c = temperature_c;
  current_chamber_c = chamber_c;
  mq_sensors_are_warming_up = mq_sensors_warming_up;
  current_mq135_v = mq_sensors_warming_up ? NAN : mq135_v;
  current_mq2_v = mq_sensors_warming_up ? NAN : mq2_v;

  if (mq_sensors_warming_up) {
    upper_limit_danger[1] = false;
    upper_limit_danger[2] = false;
  }
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
  bool pms_fresh;
  const auto readings = upperReadings(pms_fresh);
  std::array<bool, 7> faults{};
  for (size_t i = 0; i < readings.size(); ++i) {
    faults[i] = !validUpperReading(i, readings[i]);
    const bool mq_warming_up = (i == 1 || i == 2) && mq_sensors_are_warming_up;
    const float limit = safety_thresholds.values[i];
    if (mq_warming_up || !isfinite(limit)) {
      upper_limit_danger[i] = false;
    } else if (faults[i]) {
      if (i >= 2) {
        upper_limit_danger[i] = false;
      }
    } else {
      const float recovery = i == 3
                                 ? limit - fmaxf(0.5f, 0.05f * fabsf(limit))
                                 : limit * 0.95f;
      if (readings[i] >= limit) {
        upper_limit_danger[i] = true;
      } else if (readings[i] <= recovery) {
        upper_limit_danger[i] = false;
      }
    }
  }

  const bool humidity_fault = !validHumidity(current_humidity_percent);
  const float humidity_min = safety_thresholds.values[7];
  const float humidity_max = safety_thresholds.values[8];
  if (humidity_fault || !isfinite(humidity_min) || !isfinite(humidity_max)) {
    low_humidity_danger = false;
    high_humidity_danger = false;
  } else {
    const float margin = fminf(2.0f, (humidity_max - humidity_min) / 4.0f);
    if (current_humidity_percent < humidity_min) {
      low_humidity_danger = true;
    } else if (current_humidity_percent >= humidity_min + margin) {
      low_humidity_danger = false;
    }
    if (current_humidity_percent > humidity_max) {
      high_humidity_danger = true;
    } else if (current_humidity_percent <= humidity_max - margin) {
      high_humidity_danger = false;
    }
  }

  // A failed chamber reading preserves protection only after temperature danger.
  if (faults[0] && upper_limit_danger[0]) {
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
  constexpr const char *upper_triggers[] = {
      "high_chamber_temp", "high_mq2_gas", "high_mq135_gas",
      "high_ambient_temp", "high_pm1_0", "high_pm2_5", "high_pm10"};
  for (size_t i = 0; i < upper_limit_danger.size(); ++i) {
    if (upper_limit_danger[i]) {
      add_trigger(upper_triggers[i]);
    }
  }
  if (low_humidity_danger)
    add_trigger("low_humidity");
  if (high_humidity_danger)
    add_trigger("high_humidity");
  if (faults[0])
    add_trigger("temp_sensor_fault");
  if (faults[1] && !mq_sensors_are_warming_up)
    add_trigger("mq2_sensor_fault");
  if (faults[2] && !mq_sensors_are_warming_up)
    add_trigger("mq135_sensor_fault");
  if (faults[3])
    add_trigger("ambient_temp_sensor_fault");
  if (humidity_fault)
    add_trigger("humidity_sensor_fault");
  if (!pms_fresh)
    add_trigger("pms_sensor_fault");
  triggers += "]";
  active_triggers_json = triggers;

  if (catastrophic_latch || upper_limit_danger[0]) {
    requestSprinkler(true);
    manual_sprinkler = false;
  } else {
    requestSprinkler(manual_sprinkler);
  }

  if (faults[0] || (faults[1] && !mq_sensors_are_warming_up)) {
    setLedStatus(false, true, false);
  } else if (upper_limit_danger[0]) {
    setLedStatus(true, false, false);
  } else {
    setLedStatus(false, false, true);
  }
  setBuzzer(!faults[0] && current_chamber_c > safety_thresholds.values[0]);
}
