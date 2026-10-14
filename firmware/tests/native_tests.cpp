#include "Actuators.h"
#include "SafetyThresholds.h"
#include "SystemState.h"

#include <cmath>
#include <cstdint>
#include <functional>
#include <iostream>
#include <limits>
#include <string>

namespace {

uint32_t test_millis = 1000;
int failure_count = 0;
int test_count = 0;
uint8_t pin_levels[40] = {};
uint8_t pin_modes[40] = {};

void fail(const char *test_name, const char *expression, int line) {
  std::cerr << "FAIL " << test_name << " at line " << line << ": " << expression
            << '\n';
  ++failure_count;
}

#define EXPECT_TRUE(test_name, expression)                                     \
  do {                                                                         \
    if (!(expression)) {                                                       \
      fail(test_name, #expression, __LINE__);                                  \
    }                                                                          \
  } while (false)

#define EXPECT_FALSE(test_name, expression)                                    \
  EXPECT_TRUE(test_name, !(expression))
#define EXPECT_CONTAINS(test_name, value, expected)                            \
  EXPECT_TRUE(test_name, (value).find(expected) != std::string::npos)

ThresholdPatch patchFor(ThresholdField field, float value) {
  ThresholdPatch patch{defaultSafetyThresholds(), 0};
  const auto index = static_cast<uint8_t>(field);
  patch.values.values[index] = value;
  patch.fields = static_cast<uint16_t>(1u << index);
  return patch;
}

void testThresholdDefaults() {
  const char *name = "threshold defaults";
  const auto defaults = defaultSafetyThresholds();
  EXPECT_TRUE(name, defaults.values[0] == 80.0f);
  EXPECT_TRUE(name, defaults.values[1] == 2.5f);
  for (size_t index = 2; index < defaults.values.size(); ++index) {
    EXPECT_TRUE(name, std::isnan(defaults.values[index]));
  }
  EXPECT_TRUE(name, validateStoredThresholds(defaults));
  const char *expected_names[] = {
      "threshold_chamber_temp_c", "threshold_mq2_v", "threshold_mq135_v",
      "threshold_temperature_c", "threshold_pm1_0_ug_m3",
      "threshold_pm2_5_ug_m3", "threshold_pm10_ug_m3",
      "threshold_humidity_min_percent", "threshold_humidity_max_percent"};
  for (size_t index = 0; index < defaults.values.size(); ++index) {
    EXPECT_TRUE(name, std::string(thresholdFieldName(
                          static_cast<ThresholdField>(index))) ==
                          expected_names[index]);
  }
  EXPECT_TRUE(name, thresholdFieldName(ThresholdField::Count) == nullptr);
  EXPECT_TRUE(name, thresholdFieldName(static_cast<ThresholdField>(255)) ==
                        nullptr);
}

void testThresholdRanges() {
  const char *name = "threshold ranges";
  const auto defaults = defaultSafetyThresholds();
  struct RangeCase {
    ThresholdField field;
    float minimum;
    float maximum;
    float below;
    float above;
  };
  const RangeCase cases[] = {
      {ThresholdField::Chamber, 20.0f, 150.0f, 19.9f, 150.1f},
      {ThresholdField::Mq2, 0.1f, 5.0f, 0.09f, 5.01f},
      {ThresholdField::Mq135, 0.1f, 5.0f, 0.09f, 5.01f},
      {ThresholdField::Ambient, -40.0f, 80.0f, -40.1f, 80.1f},
      {ThresholdField::Pm1, 0.001f, 65535.0f, 0.0f, 65536.0f},
      {ThresholdField::Pm25, 0.001f, 65535.0f, 0.0f, 65536.0f},
      {ThresholdField::Pm10, 0.001f, 65535.0f, 0.0f, 65536.0f}};
  for (const auto &test_case : cases) {
    SafetyThresholds accepted = defaults;
    for (float value : {test_case.minimum, test_case.maximum}) {
      EXPECT_TRUE(name, validateThresholdPatch(
                            defaults, patchFor(test_case.field, value), accepted));
      EXPECT_TRUE(name, accepted.values[static_cast<uint8_t>(test_case.field)] ==
                            value);
      EXPECT_TRUE(name, validateStoredThresholds(accepted));
    }
    for (float value : {test_case.below, test_case.above}) {
      EXPECT_FALSE(name, validateThresholdPatch(
                             defaults, patchFor(test_case.field, value), accepted));
      auto stored = defaults;
      stored.values[static_cast<uint8_t>(test_case.field)] = value;
      EXPECT_FALSE(name, validateStoredThresholds(stored));
    }
  }
  for (size_t index = 0; index < defaults.values.size(); ++index) {
    for (float value : {std::numeric_limits<float>::quiet_NaN(),
                        std::numeric_limits<float>::infinity(),
                        -std::numeric_limits<float>::infinity()}) {
      SafetyThresholds accepted = defaults;
      EXPECT_FALSE(name, validateThresholdPatch(
                             defaults,
                             patchFor(static_cast<ThresholdField>(index), value),
                             accepted));
      auto stored = defaults;
      stored.values[index] = value;
      const bool optional_unset = index >= 2 && std::isnan(value);
      EXPECT_TRUE(name, validateStoredThresholds(stored) == optional_unset);
    }
  }
  for (auto field : {ThresholdField::Pm1, ThresholdField::Pm25,
                     ThresholdField::Pm10}) {
    SafetyThresholds accepted = defaults;
    EXPECT_FALSE(name, validateThresholdPatch(
                           defaults, patchFor(field, -0.001f), accepted));
    EXPECT_TRUE(name, validateThresholdPatch(
                          defaults,
                          patchFor(field, std::numeric_limits<float>::denorm_min()),
                          accepted));
  }
}

void testHumidityPairValidation() {
  const char *name = "humidity pair validation";
  const auto defaults = defaultSafetyThresholds();
  SafetyThresholds accepted = defaults;
  EXPECT_FALSE(name, validateThresholdPatch(
                         defaults, patchFor(ThresholdField::HumidityMin, 30.0f),
                         accepted));
  EXPECT_TRUE(name, accepted.values[0] == 80.0f);
  EXPECT_TRUE(name, std::isnan(accepted.values[7]));
  EXPECT_FALSE(name, validateThresholdPatch(
                         defaults, patchFor(ThresholdField::HumidityMax, 70.0f),
                         accepted));
  auto pair = patchFor(ThresholdField::HumidityMin, 30.0f);
  pair.fields |= 1u << static_cast<uint8_t>(ThresholdField::HumidityMax);
  pair.values.values[8] = 70.0f;
  EXPECT_TRUE(name, validateThresholdPatch(defaults, pair, accepted));
  EXPECT_TRUE(name, accepted.values[7] == 30.0f && accepted.values[8] == 70.0f);
  EXPECT_TRUE(name, validateStoredThresholds(accepted));
  auto configured = accepted;
  EXPECT_TRUE(name, validateThresholdPatch(
                        configured, patchFor(ThresholdField::HumidityMin, 69.9f),
                        accepted));
  EXPECT_FALSE(name, validateThresholdPatch(
                         configured, patchFor(ThresholdField::HumidityMin, 70.0f),
                         accepted));
  EXPECT_TRUE(name, validateThresholdPatch(
                        configured, patchFor(ThresholdField::HumidityMax, 30.1f),
                        accepted));
  EXPECT_FALSE(name, validateThresholdPatch(
                         configured, patchFor(ThresholdField::HumidityMax, 30.0f),
                         accepted));
  for (const auto &boundaries : {std::array<float, 2>{70.0f, 30.0f},
                                 std::array<float, 2>{30.0f, 30.0f},
                                 std::array<float, 2>{100.0f, 100.0f},
                                 std::array<float, 2>{0.0f, 0.0f}}) {
    pair.values.values[7] = boundaries[0];
    pair.values.values[8] = boundaries[1];
    EXPECT_FALSE(name, validateThresholdPatch(defaults, pair, accepted));
    auto stored = defaults;
    stored.values[7] = boundaries[0];
    stored.values[8] = boundaries[1];
    EXPECT_FALSE(name, validateStoredThresholds(stored));
  }
  pair.values.values[7] = 0.0f;
  pair.values.values[8] = 100.0f;
  EXPECT_TRUE(name, validateThresholdPatch(defaults, pair, accepted));
  EXPECT_TRUE(name, validateStoredThresholds(accepted));
  configured = accepted;
  for (auto field : {ThresholdField::HumidityMin, ThresholdField::HumidityMax}) {
    for (float value : {-0.1f, 100.1f}) {
      EXPECT_FALSE(name, validateThresholdPatch(
                             configured, patchFor(field, value), accepted));
      auto stored = configured;
      stored.values[static_cast<uint8_t>(field)] = value;
      EXPECT_FALSE(name, validateStoredThresholds(stored));
    }
    auto stored = configured;
    stored.values[static_cast<uint8_t>(field)] = NAN;
    EXPECT_FALSE(name, validateStoredThresholds(stored));
  }
}

void testPatchRejectionIsAtomic() {
  const char *name = "patch rejection is atomic";
  const auto defaults = defaultSafetyThresholds();
  SafetyThresholds accepted{{90.0f, 3.0f, 1.0f, 40.0f, 10.0f, 20.0f,
                             30.0f, 20.0f, 80.0f}};
  const auto original = accepted;
  ThresholdPatch complete_patch{original, 0x01ff};
  SafetyThresholds complete_result = defaults;
  EXPECT_TRUE(name,
              validateThresholdPatch(defaults, complete_patch, complete_result));
  EXPECT_TRUE(name, complete_result.values == original.values);
  auto patch = patchFor(ThresholdField::Chamber, 100.0f);
  patch.fields |= 1u << static_cast<uint8_t>(ThresholdField::Mq2);
  patch.values.values[1] = 0.0f;
  EXPECT_FALSE(name, validateThresholdPatch(defaults, patch, accepted));
  EXPECT_TRUE(name, accepted.values == original.values);
  patch.fields = 0;
  EXPECT_FALSE(name, validateThresholdPatch(defaults, patch, accepted));
  EXPECT_TRUE(name, accepted.values == original.values);
  patch.fields = 1u << 9;
  EXPECT_FALSE(name, validateThresholdPatch(defaults, patch, accepted));
  EXPECT_TRUE(name, accepted.values == original.values);
  patch.fields |= 1u << static_cast<uint8_t>(ThresholdField::Chamber);
  EXPECT_FALSE(name, validateThresholdPatch(defaults, patch, accepted));
  EXPECT_TRUE(name, accepted.values == original.values);
  patch.fields = 1u << 15;
  EXPECT_FALSE(name, validateThresholdPatch(defaults, patch, accepted));
  EXPECT_TRUE(name, accepted.values == original.values);
  auto aliased = original;
  patch = patchFor(ThresholdField::Chamber, 100.0f);
  EXPECT_TRUE(name, validateThresholdPatch(aliased, patch, aliased));
  EXPECT_TRUE(name, aliased.values[0] == 100.0f);
  EXPECT_TRUE(name, aliased.values[1] == 3.0f && aliased.values[7] == 20.0f);
  patch.values.values[0] = 151.0f;
  const auto before_rejection = aliased;
  EXPECT_FALSE(name, validateThresholdPatch(aliased, patch, aliased));
  EXPECT_TRUE(name, aliased.values == before_rejection.values);
}

void resetSafetyState() {
  test_millis = 1000;
  initActuators();
  threshold_chamber_temp_c = 80.0f;
  threshold_mq2_v = 2.5f;
  current_chamber_c = 25.0f;
  current_mq2_v = 0.5f;
  manual_sprinkler = false;
  catastrophic_latch = false;
  processSensorReadings(25.0f, 25.0f, 0.5f, 0.5f, false);
  initActuators();
}

void testSprinklerStartupOutputsOff() {
  const char *name = "sprinkler startup outputs off";
  pin_modes[PIN_RELAY_PUMP] = INPUT;
  pin_levels[PIN_RELAY_PUMP] = RELAY_ON;
  initActuators();
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_PUMP] == RELAY_OFF);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_BUZZER] == RELAY_OFF);
}

void testPumpRequestsApplyImmediately() {
  const char *name = "pump requests apply immediately";
  resetSafetyState();
  requestSprinkler(true);
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_PUMP] == RELAY_ON);
  requestSprinkler(false);
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_PUMP] == RELAY_OFF);
  requestSprinkler(true);
  EXPECT_TRUE(name, current_pump_state);
}

void testManualPumpFaultDoesNotLatch() {
  const char *name = "manual pump fault does not latch";
  resetSafetyState();
  current_chamber_c = NAN;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, applyManualSprinklerCommand(true) ==
                        ManualSprinklerResult::Accepted);
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_FALSE(name, catastrophic_latch);
  EXPECT_TRUE(name, applyManualSprinklerCommand(false) ==
                        ManualSprinklerResult::Accepted);
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_FALSE(name, catastrophic_latch);
}

void testThresholdUpdateImmediatelyReevaluatesPump() {
  const char *name = "threshold update immediately reevaluates pump";
  resetSafetyState();
  current_chamber_c = 85.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_TRUE(name, applyThresholdUpdate(true, 100.0f, false, 0.0f) ==
                        ThresholdUpdateResult::Accepted);
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_TRUE(name, applyThresholdUpdate(true, 80.0f, false, 0.0f) ==
                        ThresholdUpdateResult::Accepted);
  EXPECT_TRUE(name, current_pump_state);
}

void testTemperatureDangerActivatesPump() {
  const char *name = "temperature danger activates pump";
  resetSafetyState();
  current_chamber_c = 85.0f;
  manual_sprinkler = true;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_FALSE(name, manual_sprinkler);
  EXPECT_CONTAINS(name, active_triggers_json, "high_chamber_temp");
}

void testLedFollowsLatchedTemperatureDanger() {
  const char *name = "LED follows latched temperature danger";
  resetSafetyState();
  current_chamber_c = 80.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_LED_RED] == RELAY_ON);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_BUZZER] == RELAY_OFF);

  current_chamber_c = 78.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_LED_RED] == RELAY_ON);

  current_chamber_c = 75.0f;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_LED_GREEN] == RELAY_ON);
}

void testProcessingSensorReadingsEvaluatesSafety() {
  const char *name = "processing sensor readings evaluates safety";
  resetSafetyState();
  processSensorReadings(28.0f, 85.0f, 1.2f, 0.5f);
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_CONTAINS(name, active_triggers_json, "high_chamber_temp");
}

void testTemperatureDangerReassertsSprinklerRequest() {
  const char *name = "temperature danger reasserts sprinkler request";
  resetSafetyState();
  requestSprinkler(true);
  requestSprinkler(false);
  current_chamber_c = 85.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
}

void testTemperatureHysteresis() {
  const char *name = "temperature hysteresis";
  resetSafetyState();
  current_chamber_c = 85.0f;
  evaluateSafetyLoop();
  current_chamber_c = 78.0f;
  test_millis += 501;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
  current_chamber_c = 75.0f;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_TRUE(name, active_triggers_json == "[]");
}

void testMq2DangerDoesNotActivatePump() {
  const char *name = "MQ2 danger does not activate pump";
  resetSafetyState();
  current_mq2_v = 3.0f;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_CONTAINS(name, active_triggers_json, "high_mq2_gas");
  current_mq2_v = 2.3f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, active_triggers_json == "[]");
}

void testMqWarmupCountsDownForFiveMinutes() {
  const char *name = "MQ warmup counts down for five minutes";
  startMqWarmup(1000);
  EXPECT_TRUE(name, mqWarmupRemainingSeconds(1000) == 300);
  EXPECT_TRUE(name, mqWarmupRemainingSeconds(300000) == 1);
  EXPECT_TRUE(name, mqWarmupRemainingSeconds(301000) == 0);
}

void testMq2DangerIsIgnoredWhileSensorsWarmUp() {
  const char *name = "MQ2 danger is ignored while sensors warm up";
  resetSafetyState();
  processSensorReadings(28.0f, 25.0f, 1.2f, 3.0f, true);
  EXPECT_TRUE(name, mqSensorsAreWarmingUp());
  EXPECT_TRUE(name, std::isnan(current_mq2_v));
  EXPECT_TRUE(name, active_triggers_json == "[]");

  processSensorReadings(28.0f, 25.0f, 1.2f, NAN, true);
  EXPECT_TRUE(name, active_triggers_json == "[]");

  processSensorReadings(28.0f, 25.0f, 1.2f, 3.0f, false);
  EXPECT_FALSE(name, mqSensorsAreWarmingUp());
  EXPECT_CONTAINS(name, active_triggers_json, "high_mq2_gas");
}

void testMq2DangerKeepsLedGreen() {
  const char *name = "MQ2 danger keeps LED green";
  resetSafetyState();
  current_mq2_v = 3.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_LED_GREEN] == RELAY_ON);
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_LED_RED] == RELAY_OFF);
}

void testMq2DangerPreservesManualSprinkler() {
  const char *name = "MQ2 danger preserves manual sprinkler";
  resetSafetyState();
  EXPECT_TRUE(name, applyManualSprinklerCommand(true) ==
                        ManualSprinklerResult::Accepted);
  current_mq2_v = 3.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_TRUE(name, manual_sprinkler);
}

void testMq2ZeroVoltsIsNormal() {
  const char *name = "MQ2 zero volts is normal";
  resetSafetyState();
  current_mq2_v = 0.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, active_triggers_json == "[]");
}

void testMq2SafeRangeDoesNotTriggerGasDanger() {
  const char *name = "MQ2 safe range does not trigger gas danger";
  resetSafetyState();
  current_mq2_v = 2.4f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, active_triggers_json == "[]");
}

void testMq2DangerStartsAtFixedThreshold() {
  const char *name = "MQ2 danger starts at fixed threshold";
  resetSafetyState();
  threshold_mq2_v = 3.0f;
  current_mq2_v = 2.5f;
  evaluateSafetyLoop();
  EXPECT_CONTAINS(name, active_triggers_json, "high_mq2_gas");
}

void testMq2RailShortIsReportedAsFault() {
  const char *name = "MQ2 rail short is reported as fault";
  resetSafetyState();
  current_mq2_v = 4.8f;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, active_triggers_json.find("mq2_sensor_fault") !=
                         std::string::npos);
  current_mq2_v = 4.81f;
  evaluateSafetyLoop();
  EXPECT_CONTAINS(name, active_triggers_json, "mq2_sensor_fault");
}

void testMq2NanIsReportedAsFault() {
  const char *name = "MQ2 NaN is reported as fault";
  resetSafetyState();
  current_mq2_v = NAN;
  evaluateSafetyLoop();
  EXPECT_CONTAINS(name, active_triggers_json, "mq2_sensor_fault");
}

void testTemperatureFaultAllowsManualSprinkler() {
  const char *name = "temperature fault allows manual sprinkler";
  resetSafetyState();
  current_chamber_c = NAN;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_pump_state);
  EXPECT_CONTAINS(name, active_triggers_json, "temp_sensor_fault");
  EXPECT_TRUE(name, applyManualSprinklerCommand(true) ==
                        ManualSprinklerResult::Accepted);
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_TRUE(name, manual_sprinkler);
  EXPECT_FALSE(name, catastrophic_latch);
  EXPECT_TRUE(name, applyManualSprinklerCommand(false) ==
                        ManualSprinklerResult::Accepted);
  EXPECT_FALSE(name, current_pump_state);
}

void testCatastrophicFireLatch() {
  const char *name = "catastrophic fire latch";
  resetSafetyState();
  current_chamber_c = 100.0f;
  evaluateSafetyLoop();
  current_chamber_c = NAN;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, catastrophic_latch);
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_CONTAINS(name, active_triggers_json, "catastrophic_latch");
  manual_sprinkler = false;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, catastrophic_latch);
  EXPECT_TRUE(name, current_pump_state);
}

void testManualOffCannotOverrideCatastrophicLatch() {
  const char *name = "manual off cannot override catastrophic latch";
  resetSafetyState();
  current_chamber_c = 100.0f;
  evaluateSafetyLoop();
  current_chamber_c = NAN;
  evaluateSafetyLoop();
  const auto result = applyManualSprinklerCommand(false);
  EXPECT_TRUE(name, result == ManualSprinklerResult::SafetyOverride);
  EXPECT_TRUE(name, catastrophic_latch);
  EXPECT_TRUE(name, current_pump_state);
}

void testManualSprinklerInSafeState() {
  const char *name = "manual sprinkler in safe state";
  resetSafetyState();
  manual_sprinkler = true;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
  manual_sprinkler = false;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_pump_state);
}

void testManualCommandControlsSprinklerInSafeState() {
  const char *name = "manual command controls sprinkler in safe state";
  resetSafetyState();
  const auto enabled = applyManualSprinklerCommand(true);
  EXPECT_TRUE(name, enabled == ManualSprinklerResult::Accepted);
  EXPECT_TRUE(name, manual_sprinkler);
  EXPECT_TRUE(name, current_pump_state);
  const auto disabled = applyManualSprinklerCommand(false);
  EXPECT_TRUE(name, disabled == ManualSprinklerResult::Accepted);
  EXPECT_FALSE(name, manual_sprinkler);
  EXPECT_FALSE(name, current_pump_state);
}

void testManualSprinklerUsesCoordinator() {
  const char *name = "manual sprinkler uses coordinator";
  resetSafetyState();
  EXPECT_TRUE(name, applyManualSprinklerCommand(true) ==
                        ManualSprinklerResult::Accepted);
  EXPECT_TRUE(name, current_pump_state);
}

void testTemperatureDangerUsesCoordinator() {
  const char *name = "temperature danger uses coordinator";
  resetSafetyState();
  current_chamber_c = threshold_chamber_temp_c;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_pump_state);
}

void testCatastrophicLatchKeepsPumpRequested() {
  const char *name = "catastrophic latch keeps pump requested";
  resetSafetyState();
  current_chamber_c = 100.0f;
  evaluateSafetyLoop();
  current_chamber_c = NAN;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, catastrophic_latch);
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_TRUE(name, applyManualSprinklerCommand(false) ==
                        ManualSprinklerResult::SafetyOverride);
  EXPECT_TRUE(name, current_pump_state);
}

void testBuzzerUsesActiveLowRelay() {
  const char *name = "buzzer uses active-low relay";
  resetSafetyState();
  current_chamber_c = threshold_chamber_temp_c;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_BUZZER] == RELAY_OFF);
  current_chamber_c = threshold_chamber_temp_c + 0.1f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, pin_levels[PIN_RELAY_BUZZER] == RELAY_ON);
}

void testInvalidThresholdUpdateIsTransactional() {
  const char *name = "invalid threshold update is transactional";
  resetSafetyState();
  state_needs_save = false;
  const auto result = applyThresholdUpdate(true, 1000.0f, true, 1.5f);
  EXPECT_TRUE(name, result == ThresholdUpdateResult::Invalid);
  EXPECT_TRUE(name, threshold_chamber_temp_c == 80.0f);
  EXPECT_TRUE(name, threshold_mq2_v == 2.5f);
  EXPECT_FALSE(name, state_needs_save);
}

void testValidThresholdUpdateChangesRequestedFields() {
  const char *name = "valid threshold update changes requested fields";
  resetSafetyState();
  state_needs_save = false;
  const auto result = applyThresholdUpdate(true, 120.0f, false, 0.0f);
  EXPECT_TRUE(name, result == ThresholdUpdateResult::Accepted);
  EXPECT_TRUE(name, threshold_chamber_temp_c == 120.0f);
  EXPECT_TRUE(name, threshold_mq2_v == 2.5f);
  EXPECT_TRUE(name, state_needs_save);
}

void testLowerThresholdImmediatelyReevaluatesSafety() {
  const char *name = "lower threshold immediately reevaluates safety";
  resetSafetyState();
  current_chamber_c = 70.0f;
  const auto result = applyThresholdUpdate(true, 60.0f, false, 0.0f);
  EXPECT_TRUE(name, result == ThresholdUpdateResult::Accepted);
  EXPECT_TRUE(name, current_pump_state);
  EXPECT_CONTAINS(name, active_triggers_json, "high_chamber_temp");
}

void testPmsReadingFreshness() {
  const char *name = "PMS reading freshness";
  resetPmsReadingCache();
  PmsReading reading{};
  EXPECT_FALSE(name, copyFreshPmsReadingLocked(1000, reading));

  const PmsReading expected{0, 12, 18};
  recordPmsReading(expected, 5000);
  EXPECT_TRUE(name, copyFreshPmsReadingLocked(15000, reading));
  EXPECT_TRUE(name, reading.pm1_0_ug_m3 == 0);
  EXPECT_TRUE(name, reading.pm2_5_ug_m3 == 12);
  EXPECT_TRUE(name, reading.pm10_ug_m3 == 18);
  EXPECT_FALSE(name, copyFreshPmsReadingLocked(15001, reading));
}

void testPmsFreshnessAcrossClockWrap() {
  const char *name = "PMS freshness across clock wrap";
  resetPmsReadingCache();
  const uint32_t sampled_at_ms = UINT32_MAX - 5000;
  const PmsReading expected{0, 12, 18};
  PmsReading reading{};

  recordPmsReading(expected, sampled_at_ms);
  EXPECT_TRUE(name,
              copyFreshPmsReadingLocked(sampled_at_ms + 10000, reading));
  EXPECT_TRUE(name, reading.pm1_0_ug_m3 == 0);
  EXPECT_FALSE(name,
               copyFreshPmsReadingLocked(sampled_at_ms + 10001, reading));
}

void testPmsDoesNotAffectSafety() {
  const char *name = "PMS does not affect safety";
  resetSafetyState();
  const std::string triggers_before = active_triggers_json;
  const bool pump_before = current_pump_state;
  const PmsReading reading{8, 12, 18};

  recordPmsReading(reading, 1000);

  EXPECT_TRUE(name, active_triggers_json == triggers_before);
  EXPECT_TRUE(name, current_pump_state == pump_before);
  current_mq2_v = 3.0f;
  evaluateSafetyLoop();
  EXPECT_CONTAINS(name, active_triggers_json, "high_mq2_gas");
  EXPECT_FALSE(name, current_pump_state);
}

void run(const char *name, const std::function<void()> &test) {
  ++test_count;
  const int failures_before = failure_count;
  test();
  if (failure_count == failures_before) {
    std::cout << "PASS " << name << '\n';
  }
}

} // namespace

uint32_t millis() { return test_millis; }

void pinMode(uint8_t pin, uint8_t mode) { pin_modes[pin] = mode; }

void digitalWrite(uint8_t pin, uint8_t level) {
  if (pin_modes[pin] == OUTPUT) {
    pin_levels[pin] = level;
  }
}

int main() {
  run("threshold defaults", testThresholdDefaults);
  run("threshold ranges", testThresholdRanges);
  run("humidity pair validation", testHumidityPairValidation);
  run("patch rejection is atomic", testPatchRejectionIsAtomic);
  run("sprinkler startup outputs off", testSprinklerStartupOutputsOff);
  run("pump requests apply immediately", testPumpRequestsApplyImmediately);
  run("manual pump fault does not latch", testManualPumpFaultDoesNotLatch);
  run("threshold update immediately reevaluates pump",
      testThresholdUpdateImmediatelyReevaluatesPump);
  run("temperature danger activates pump", testTemperatureDangerActivatesPump);
  run("LED follows latched temperature danger",
      testLedFollowsLatchedTemperatureDanger);
  run("processing sensor readings evaluates safety",
      testProcessingSensorReadingsEvaluatesSafety);
  run("temperature danger reasserts sprinkler request",
      testTemperatureDangerReassertsSprinklerRequest);
  run("temperature hysteresis", testTemperatureHysteresis);
  run("MQ2 danger does not activate pump", testMq2DangerDoesNotActivatePump);
  run("MQ warmup counts down for five minutes", testMqWarmupCountsDownForFiveMinutes);
  run("MQ2 danger is ignored while sensors warm up",
      testMq2DangerIsIgnoredWhileSensorsWarmUp);
  run("MQ2 danger keeps LED green", testMq2DangerKeepsLedGreen);
  run("MQ2 danger preserves manual sprinkler",
      testMq2DangerPreservesManualSprinkler);
  run("MQ2 zero volts is normal", testMq2ZeroVoltsIsNormal);
  run("MQ2 safe range does not trigger gas danger",
      testMq2SafeRangeDoesNotTriggerGasDanger);
  run("MQ2 danger starts at fixed threshold",
      testMq2DangerStartsAtFixedThreshold);
  run("MQ2 rail short is reported as fault", testMq2RailShortIsReportedAsFault);
  run("MQ2 NaN is reported as fault", testMq2NanIsReportedAsFault);
  run("temperature fault allows manual sprinkler",
      testTemperatureFaultAllowsManualSprinkler);
  run("catastrophic fire latch", testCatastrophicFireLatch);
  run("manual off cannot override catastrophic latch",
      testManualOffCannotOverrideCatastrophicLatch);
  run("manual sprinkler in safe state", testManualSprinklerInSafeState);
  run("manual command controls sprinkler in safe state",
      testManualCommandControlsSprinklerInSafeState);
  run("manual sprinkler uses coordinator", testManualSprinklerUsesCoordinator);
  run("temperature danger uses coordinator", testTemperatureDangerUsesCoordinator);
  run("catastrophic latch keeps pump requested",
      testCatastrophicLatchKeepsPumpRequested);
  run("buzzer uses active-low relay", testBuzzerUsesActiveLowRelay);
  run("invalid threshold update is transactional",
      testInvalidThresholdUpdateIsTransactional);
  run("valid threshold update changes requested fields",
      testValidThresholdUpdateChangesRequestedFields);
  run("lower threshold immediately reevaluates safety",
      testLowerThresholdImmediatelyReevaluatesSafety);
  run("PMS reading freshness", testPmsReadingFreshness);
  run("PMS freshness across clock wrap", testPmsFreshnessAcrossClockWrap);
  run("PMS does not affect safety", testPmsDoesNotAffectSafety);

  if (failure_count != 0) {
    std::cerr << failure_count << " native firmware test assertion(s) failed\n";
    return 1;
  }

  std::cout << "All " << test_count << " native firmware tests passed\n";
  return 0;
}
