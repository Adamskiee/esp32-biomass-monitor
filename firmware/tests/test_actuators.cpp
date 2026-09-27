#include <unity.h>
#include "../main/Actuators.h"

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
}

void tearDown(void) {}

void test_solenoid_debounce() {
    initSolenoid();
    setSolenoid(true, false);
    TEST_ASSERT_TRUE(current_solenoid_state);
    setSolenoid(false, false);
    TEST_ASSERT_TRUE(current_solenoid_state); // Should fail if debounce missing
}

void test_solenoid_force() {
    initSolenoid();
    setSolenoid(true, false);
    setSolenoid(false, true); // Force bypass
    TEST_ASSERT_FALSE(current_solenoid_state);
}

void test_solenoid_allows_toggle_after_500ms() {
    initSolenoid();
    setSolenoid(true, false);
    TEST_ASSERT_TRUE(current_solenoid_state);
    _test_millis += 501;
    setSolenoid(false, false);
    TEST_ASSERT_FALSE(current_solenoid_state);
}

int main(int argc, char **argv) {
    UNITY_BEGIN();
    RUN_TEST(test_solenoid_debounce);
    RUN_TEST(test_solenoid_force);
    RUN_TEST(test_solenoid_allows_toggle_after_500ms);
    return UNITY_END();
}
