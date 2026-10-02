#include "Actuators.h"
#include <BiomassConfig.h>

bool current_solenoid_state = false;
bool current_pump_state = false;
bool current_fan_state = false;

namespace {

enum class SprinklerPhase { Off, StartingPump, On, StoppingValve };

SprinklerPhase sprinkler_phase = SprinklerPhase::Off;
bool sprinkler_requested = false;
uint32_t transition_started_at = 0;

void setSolenoidOutput(bool state) {
  digitalWrite(PIN_RELAY_SOLENOID, state ? RELAY_ON : RELAY_OFF);
  current_solenoid_state = state;
}

void setPumpOutput(bool state) {
  digitalWrite(PIN_RELAY_PUMP, state ? RELAY_ON : RELAY_OFF);
  current_pump_state = state;
}

} // namespace

void initSolenoid() {
  digitalWrite(PIN_RELAY_SOLENOID, RELAY_OFF);
  pinMode(PIN_RELAY_SOLENOID, OUTPUT);
  current_solenoid_state = false;
  digitalWrite(PIN_RELAY_PUMP, RELAY_OFF);
  pinMode(PIN_RELAY_PUMP, OUTPUT);
  current_pump_state = false;
  sprinkler_requested = false;
  sprinkler_phase = SprinklerPhase::Off;
  transition_started_at = 0;
}

void initActuators() {
  // Drive pins HIGH (RELAY_OFF) before enabling OUTPUT mode to prevent startup
  // glitch/clicking
  initSolenoid();

  digitalWrite(PIN_RELAY_FAN, RELAY_OFF);
  pinMode(PIN_RELAY_FAN, OUTPUT);
  current_fan_state = false;

  digitalWrite(PIN_RELAY_LED_RED, RELAY_OFF);
  pinMode(PIN_RELAY_LED_RED, OUTPUT);

  digitalWrite(PIN_RELAY_LED_YELLOW, RELAY_OFF);
  pinMode(PIN_RELAY_LED_YELLOW, OUTPUT);

  digitalWrite(PIN_RELAY_LED_GREEN, RELAY_OFF);
  pinMode(PIN_RELAY_LED_GREEN, OUTPUT);

  digitalWrite(PIN_RELAY_BUZZER, RELAY_OFF);
  pinMode(PIN_RELAY_BUZZER, OUTPUT);
}

void setFan(bool state) {
  digitalWrite(PIN_RELAY_FAN, state ? RELAY_ON : RELAY_OFF);
  current_fan_state = state;
}

void requestSprinkler(bool enabled) {
  sprinkler_requested = enabled;

  if (enabled) {
    if (sprinkler_phase == SprinklerPhase::Off ||
        sprinkler_phase == SprinklerPhase::StoppingValve) {
      setPumpOutput(false);
      setSolenoidOutput(true);
      transition_started_at = millis();
      sprinkler_phase = SprinklerPhase::StartingPump;
    }
    return;
  }

  if (sprinkler_phase == SprinklerPhase::On ||
      sprinkler_phase == SprinklerPhase::StartingPump) {
    setPumpOutput(false);
    transition_started_at = millis();
    sprinkler_phase = SprinklerPhase::StoppingValve;
  }
}

void updateSprinklerActuators() {
  if (sprinkler_phase == SprinklerPhase::StartingPump &&
      millis() - transition_started_at >= SPRINKLER_TRANSITION_MS) {
    if (sprinkler_requested && current_solenoid_state) {
      setPumpOutput(true);
      sprinkler_phase = SprinklerPhase::On;
    }
  } else if (sprinkler_phase == SprinklerPhase::StoppingValve &&
             millis() - transition_started_at >= SPRINKLER_TRANSITION_MS) {
    if (!sprinkler_requested) {
      setSolenoidOutput(false);
      sprinkler_phase = SprinklerPhase::Off;
    }
  }
}

void setLedStatus(bool red, bool yellow, bool green) {
  digitalWrite(PIN_RELAY_LED_RED, red ? RELAY_ON : RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_YELLOW, yellow ? RELAY_ON : RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_GREEN, green ? RELAY_ON : RELAY_OFF);
}

void setBuzzer(bool state) {
  digitalWrite(PIN_RELAY_BUZZER, state ? RELAY_ON : RELAY_OFF);
}
