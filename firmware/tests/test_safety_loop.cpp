#include <unity.h>
#include "../main/SystemState.h"
#include "../main/Actuators.h"
#include <cmath>

#ifndef ARDUINO
static uint32_t _test_millis = 1000;
uint32_t millis(void) {
    return _test_millis;
}
void pinMode(uint8_t pin, uint8_t mode) {}
void digitalWrite(uint8_t pin, uint8_t val) {}
#endif

void setUp(void) {
    _test_millis = 1000;
    initSolenoid();
    threshold_chamber_temp_c = 80.0f;
    threshold_mq2_v = 2.5f;
    current_chamber_c = 25.0f;
    current_mq2_v = 0.5f;
    manual_sprinkler = false;
    catastrophic_latch = false;
    // Run loop at safe values to clear any internal hysteresis latches
    evaluateSafetyLoop();
    initSolenoid();
}

void tearDown(void) {}

void test_temp_danger_activates_solenoid_and_clears_manual_sprinkler(void) {
    current_chamber_c = 85.0f;
    manual_sprinkler = true;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(current_solenoid_state);
    TEST_ASSERT_FALSE(manual_sprinkler); // Must reset to false on danger
    TEST_ASSERT_NOT_EQUAL(String::npos, active_triggers_json.find("high_chamber_temp"));
}

void test_temp_hysteresis(void) {
    // 1. Enter danger
    current_chamber_c = 85.0f;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(current_solenoid_state);

    // 2. Drop into deadband (80 * 0.95 = 76.0). 78.0 is in deadband.
    _test_millis += 600;
    current_chamber_c = 78.0f;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(current_solenoid_state); // Still in danger due to hysteresis

    // 3. Drop below 5% deadband (<= 76.0)
    _test_millis += 600;
    current_chamber_c = 75.0f;
    evaluateSafetyLoop();
    TEST_ASSERT_FALSE(current_solenoid_state); // Danger cleared
    TEST_ASSERT_EQUAL_STRING("[]", active_triggers_json.c_str());
}

void test_mq2_danger_alert_only_does_not_activate_solenoid(void) {
    current_mq2_v = 3.0f;
    manual_sprinkler = false;
    evaluateSafetyLoop();
    TEST_ASSERT_FALSE(current_solenoid_state); // Gas does NOT turn on sprinkler
    TEST_ASSERT_NOT_EQUAL(String::npos, active_triggers_json.find("high_mq2_gas"));

    // Drops below deadband (2.5 * 0.95 = 2.375)
    current_mq2_v = 2.3f;
    evaluateSafetyLoop();
    TEST_ASSERT_EQUAL_STRING("[]", active_triggers_json.c_str());
}

void test_temp_fault_default_off_allows_blind_fire_manual(void) {
    current_chamber_c = NAN;
    manual_sprinkler = false;
    evaluateSafetyLoop();
    TEST_ASSERT_FALSE(current_solenoid_state);
    TEST_ASSERT_NOT_EQUAL(String::npos, active_triggers_json.find("temp_sensor_fault"));

    // Operator blind-fires during fault (cycle 1)
    _test_millis += 600;
    manual_sprinkler = true;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(current_solenoid_state);
    TEST_ASSERT_TRUE(manual_sprinkler); // Critical ruling: NOT cleared on fault
    TEST_ASSERT_FALSE(catastrophic_latch); // Must NOT trip catastrophic latch

    // Subsequent cycle during fault (cycle 2)
    _test_millis += 600;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(current_solenoid_state);
    TEST_ASSERT_FALSE(catastrophic_latch); // Must NOT conflate blind fire with danger

    // Operator disengages blind-fire (cycle 3)
    _test_millis += 600;
    manual_sprinkler = false;
    evaluateSafetyLoop();
    TEST_ASSERT_FALSE(current_solenoid_state); // Solenoid successfully turns OFF
    TEST_ASSERT_FALSE(catastrophic_latch);
}

void test_catastrophic_fire_latch(void) {
    // 1. Enter danger
    current_chamber_c = 100.0f;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(current_solenoid_state);

    // 2. Sensor fails while system was in temperature danger
    current_chamber_c = NAN;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(catastrophic_latch);
    TEST_ASSERT_TRUE(current_solenoid_state);
    TEST_ASSERT_NOT_EQUAL(String::npos, active_triggers_json.find("catastrophic_latch"));

    // 3. Attempting to clear manual_sprinkler does not deactivate catastrophic latch
    manual_sprinkler = false;
    _test_millis += 600;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(catastrophic_latch);
    TEST_ASSERT_TRUE(current_solenoid_state);
}

void test_safe_state_manual_sprinkler_control(void) {
    current_chamber_c = 25.0f;
    current_mq2_v = 0.5f;
    manual_sprinkler = true;
    evaluateSafetyLoop();
    TEST_ASSERT_TRUE(current_solenoid_state);
    TEST_ASSERT_EQUAL_STRING("[]", active_triggers_json.c_str());

    _test_millis += 600;
    manual_sprinkler = false;
    evaluateSafetyLoop();
    TEST_ASSERT_FALSE(current_solenoid_state);
    TEST_ASSERT_EQUAL_STRING("[]", active_triggers_json.c_str());
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_temp_danger_activates_solenoid_and_clears_manual_sprinkler);
    RUN_TEST(test_temp_hysteresis);
    RUN_TEST(test_mq2_danger_alert_only_does_not_activate_solenoid);
    RUN_TEST(test_temp_fault_default_off_allows_blind_fire_manual);
    RUN_TEST(test_catastrophic_fire_latch);
    RUN_TEST(test_safe_state_manual_sprinkler_control);
    return UNITY_END();
}
