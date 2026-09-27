#include "Actuators.h"
#include <BiomassConfig.h>

void initActuators() {
  // Drive pins HIGH (RELAY_OFF) before enabling OUTPUT mode to prevent startup
  // glitch/clicking
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

  digitalWrite(PIN_BUZZER, LOW);
  pinMode(PIN_BUZZER, OUTPUT);
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

void setBuzzer(bool state) {
  // Assuming an active buzzer. If it's a passive buzzer, use tone(PIN_BUZZER,
  // 2000) for ON and noTone(PIN_BUZZER) for OFF.
  digitalWrite(PIN_BUZZER, state ? HIGH : LOW);
}
