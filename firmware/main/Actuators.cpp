#include "Actuators.h"
#include "Config.h"

void initActuators() {
  // Drive pins HIGH (RELAY_OFF) before enabling OUTPUT mode to prevent startup glitch/clicking
  digitalWrite(PIN_RELAY_SOLENOID, RELAY_OFF);
  pinMode(PIN_RELAY_SOLENOID, OUTPUT);

  digitalWrite(PIN_RELAY_FAN, RELAY_OFF);
  pinMode(PIN_RELAY_FAN, OUTPUT);

  digitalWrite(PIN_RELAY_LED_RED, RELAY_OFF);
  pinMode(PIN_RELAY_LED_RED, OUTPUT);

  digitalWrite(PIN_RELAY_LED_YELLOW, RELAY_OFF);
  pinMode(PIN_RELAY_LED_YELLOW, OUTPUT);

  digitalWrite(PIN_RELAY_LED_GREEN, RELAY_OFF);
  pinMode(PIN_RELAY_LED_GREEN, OUTPUT);
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
