#include "Actuators.h"
#include <BiomassConfig.h>
#ifdef ARDUINO
#include <driver/gpio.h>
#endif

bool current_pump_state = false;

namespace {

void initRelayOutput(uint8_t pin) {
#ifdef ARDUINO
  // Arduino-ESP32 ignores digitalWrite until pinMode registers the GPIO.
  gpio_set_level(static_cast<gpio_num_t>(pin), RELAY_OFF);
#endif
  pinMode(pin, OUTPUT);
  digitalWrite(pin, RELAY_OFF);
}

void setPumpOutput(bool state) {
  digitalWrite(PIN_RELAY_PUMP, state ? RELAY_ON : RELAY_OFF);
  current_pump_state = state;
}

} // namespace

void initActuators() {
  initRelayOutput(PIN_RELAY_PUMP);
  current_pump_state = false;
  initRelayOutput(PIN_RELAY_LED_RED);
  initRelayOutput(PIN_RELAY_LED_YELLOW);
  initRelayOutput(PIN_RELAY_LED_GREEN);
  initRelayOutput(PIN_RELAY_BUZZER);
}

void requestSprinkler(bool enabled) {
  setPumpOutput(enabled);
}

void setLedStatus(bool red, bool yellow, bool green) {
  digitalWrite(PIN_RELAY_LED_RED, red ? RELAY_ON : RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_YELLOW, yellow ? RELAY_ON : RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_GREEN, green ? RELAY_ON : RELAY_OFF);
}

void setBuzzer(bool state) {
  digitalWrite(PIN_RELAY_BUZZER, state ? RELAY_ON : RELAY_OFF);
}
