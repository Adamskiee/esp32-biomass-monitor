#include "Actuators.h"
#include "SystemState.h"

#include <cmath>
#include <cstdint>
#include <functional>
#include <iostream>
#include <string>

namespace {

uint32_t test_millis = 1000;
int failure_count = 0;

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

void resetSafetyState() {
  test_millis = 1000;
  initSolenoid();
  threshold_chamber_temp_c = 80.0f;
  threshold_mq2_v = 2.5f;
  current_chamber_c = 25.0f;
  current_mq2_v = 0.5f;
  manual_sprinkler = false;
  catastrophic_latch = false;
  evaluateSafetyLoop();
  initSolenoid();
}

void testSolenoidDebounce() {
  const char *name = "solenoid debounce";
  resetSafetyState();
  setSolenoid(true);
  setSolenoid(false);
  EXPECT_TRUE(name, current_solenoid_state);
}

void testSolenoidForceBypassesDebounce() {
  const char *name = "solenoid force bypass";
  resetSafetyState();
  setSolenoid(true);
  setSolenoid(false, true);
  EXPECT_FALSE(name, current_solenoid_state);
}

void testSolenoidTogglesAfterDebounce() {
  const char *name = "solenoid toggles after debounce";
  resetSafetyState();
  setSolenoid(true);
  test_millis += 501;
  setSolenoid(false);
  EXPECT_FALSE(name, current_solenoid_state);
}

void testFanStateTracksOutput() {
  const char *name = "fan state tracks output";
  setFan(true);
  EXPECT_TRUE(name, current_fan_state);
  setFan(false);
  EXPECT_FALSE(name, current_fan_state);
}

void testTemperatureDangerActivatesSolenoid() {
  const char *name = "temperature danger activates solenoid";
  resetSafetyState();
  current_chamber_c = 85.0f;
  manual_sprinkler = true;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_solenoid_state);
  EXPECT_FALSE(name, manual_sprinkler);
  EXPECT_CONTAINS(name, active_triggers_json, "high_chamber_temp");
}

void testProcessingSensorReadingsEvaluatesSafety() {
  const char *name = "processing sensor readings evaluates safety";
  resetSafetyState();
  processSensorReadings(28.0f, 85.0f, 1.2f, 0.5f);
  EXPECT_TRUE(name, current_solenoid_state);
  EXPECT_CONTAINS(name, active_triggers_json, "high_chamber_temp");
}

void testTemperatureDangerBypassesDebounce() {
  const char *name = "temperature danger bypasses debounce";
  resetSafetyState();
  setSolenoid(true, true);
  setSolenoid(false, true);
  current_chamber_c = 85.0f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_solenoid_state);
}

void testTemperatureHysteresis() {
  const char *name = "temperature hysteresis";
  resetSafetyState();
  current_chamber_c = 85.0f;
  evaluateSafetyLoop();
  current_chamber_c = 78.0f;
  test_millis += 501;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_solenoid_state);
  current_chamber_c = 75.0f;
  test_millis += 501;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_solenoid_state);
  EXPECT_TRUE(name, active_triggers_json == "[]");
}

void testMq2DangerDoesNotActivateSolenoid() {
  const char *name = "MQ2 danger does not activate solenoid";
  resetSafetyState();
  current_mq2_v = 3.0f;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_solenoid_state);
  EXPECT_CONTAINS(name, active_triggers_json, "high_mq2_gas");
  current_mq2_v = 2.3f;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, active_triggers_json == "[]");
}

void testMq2DisconnectIsReportedAsFault() {
  const char *name = "MQ2 disconnect is reported as fault";
  resetSafetyState();
  current_mq2_v = 0.05f;
  evaluateSafetyLoop();
  EXPECT_CONTAINS(name, active_triggers_json, "mq2_sensor_fault");
}

void testTemperatureFaultAllowsManualSprinkler() {
  const char *name = "temperature fault allows manual sprinkler";
  resetSafetyState();
  current_chamber_c = NAN;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_solenoid_state);
  EXPECT_CONTAINS(name, active_triggers_json, "temp_sensor_fault");
  manual_sprinkler = true;
  test_millis += 501;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_solenoid_state);
  EXPECT_TRUE(name, manual_sprinkler);
  EXPECT_FALSE(name, catastrophic_latch);
  manual_sprinkler = false;
  test_millis += 501;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_solenoid_state);
}

void testCatastrophicFireLatch() {
  const char *name = "catastrophic fire latch";
  resetSafetyState();
  current_chamber_c = 100.0f;
  evaluateSafetyLoop();
  current_chamber_c = NAN;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, catastrophic_latch);
  EXPECT_TRUE(name, current_solenoid_state);
  EXPECT_CONTAINS(name, active_triggers_json, "catastrophic_latch");
  manual_sprinkler = false;
  test_millis += 501;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, catastrophic_latch);
  EXPECT_TRUE(name, current_solenoid_state);
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
  EXPECT_TRUE(name, current_solenoid_state);
}

void testManualSprinklerInSafeState() {
  const char *name = "manual sprinkler in safe state";
  resetSafetyState();
  manual_sprinkler = true;
  evaluateSafetyLoop();
  EXPECT_TRUE(name, current_solenoid_state);
  manual_sprinkler = false;
  test_millis += 501;
  evaluateSafetyLoop();
  EXPECT_FALSE(name, current_solenoid_state);
}

void testManualCommandControlsSprinklerInSafeState() {
  const char *name = "manual command controls sprinkler in safe state";
  resetSafetyState();
  const auto enabled = applyManualSprinklerCommand(true);
  EXPECT_TRUE(name, enabled == ManualSprinklerResult::Accepted);
  EXPECT_TRUE(name, manual_sprinkler);
  EXPECT_TRUE(name, current_solenoid_state);
  const auto disabled = applyManualSprinklerCommand(false);
  EXPECT_TRUE(name, disabled == ManualSprinklerResult::Accepted);
  EXPECT_FALSE(name, manual_sprinkler);
  EXPECT_FALSE(name, current_solenoid_state);
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

void run(const char *name, const std::function<void()> &test) {
  const int failures_before = failure_count;
  test();
  if (failure_count == failures_before) {
    std::cout << "PASS " << name << '\n';
  }
}

} // namespace

uint32_t millis() { return test_millis; }

void pinMode(uint8_t, uint8_t) {}

void digitalWrite(uint8_t, uint8_t) {}

int main() {
  run("solenoid debounce", testSolenoidDebounce);
  run("solenoid force bypass", testSolenoidForceBypassesDebounce);
  run("solenoid toggles after debounce", testSolenoidTogglesAfterDebounce);
  run("fan state tracks output", testFanStateTracksOutput);
  run("temperature danger activates solenoid",
      testTemperatureDangerActivatesSolenoid);
  run("processing sensor readings evaluates safety",
      testProcessingSensorReadingsEvaluatesSafety);
  run("temperature danger bypasses debounce",
      testTemperatureDangerBypassesDebounce);
  run("temperature hysteresis", testTemperatureHysteresis);
  run("MQ2 danger does not activate solenoid",
      testMq2DangerDoesNotActivateSolenoid);
  run("MQ2 disconnect is reported as fault",
      testMq2DisconnectIsReportedAsFault);
  run("temperature fault allows manual sprinkler",
      testTemperatureFaultAllowsManualSprinkler);
  run("catastrophic fire latch", testCatastrophicFireLatch);
  run("manual off cannot override catastrophic latch",
      testManualOffCannotOverrideCatastrophicLatch);
  run("manual sprinkler in safe state", testManualSprinklerInSafeState);
  run("manual command controls sprinkler in safe state",
      testManualCommandControlsSprinklerInSafeState);
  run("invalid threshold update is transactional",
      testInvalidThresholdUpdateIsTransactional);
  run("valid threshold update changes requested fields",
      testValidThresholdUpdateChangesRequestedFields);

  if (failure_count != 0) {
    std::cerr << failure_count << " native firmware test assertion(s) failed\n";
    return 1;
  }

  std::cout << "All 17 native firmware tests passed\n";
  return 0;
}
