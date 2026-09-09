#include "Actuators.h"
#include "Config.h"

void initActuators() {
  pinMode(PIN_RELAY_SOLENOID, OUTPUT);
  pinMode(PIN_RELAY_FAN, OUTPUT);
  pinMode(PIN_RELAY_LED_RED, OUTPUT);
  pinMode(PIN_RELAY_LED_YELLOW, OUTPUT);
  pinMode(PIN_RELAY_LED_GREEN, OUTPUT);

  // Turn all OFF by default
  setSolenoid(false);
  setFan(false);
  setLedStatus(false, false, false);
}

void setFan(bool state) {
  digitalWrite(PIN_RELAY_FAN, state ? RELAY_ON : RELAY_OFF);
}

void setSolenoid(bool state) {
  digitalWrite(PIN_RELAY_SOLENOID, state ? RELAY_ON : RELAY_OFF);
}

void setLedStatus(bool red, bool yellow, bool green) {
  digitalWrite(PIN_RELAY_LED_RED, red ? RELAY_ON : RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_YELLOW, yellow ? RELAY_ON : RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_GREEN, green ? RELAY_ON : RELAY_OFF);
}
