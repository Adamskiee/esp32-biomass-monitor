#include "Actuators.h"
#include <BiomassConfig.h>
#ifdef ARDUINO
#include <driver/gpio.h>
#endif

bool current_solenoid_state = false;
bool current_pump_state = false;
bool current_fan_state = false;

namespace {

enum class SprinklerPhase { Off, StartingPump, On, StoppingValve };

SprinklerPhase sprinkler_phase = SprinklerPhase::Off;
bool sprinkler_requested = false;
uint32_t transition_started_at = 0;

void initRelayOutput(uint8_t pin) {
#ifdef ARDUINO
  // Arduino-ESP32 ignores digitalWrite until pinMode registers the GPIO.
  gpio_set_level(static_cast<gpio_num_t>(pin), RELAY_OFF);
#endif
  pinMode(pin, OUTPUT);
  digitalWrite(pin, RELAY_OFF);
}

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
  initRelayOutput(PIN_RELAY_SOLENOID);
  current_solenoid_state = false;
  initRelayOutput(PIN_RELAY_PUMP);
  current_pump_state = false;
  sprinkler_requested = false;
  sprinkler_phase = SprinklerPhase::Off;
  transition_started_at = 0;
}

void initActuators() {
  initSolenoid();

  initRelayOutput(PIN_RELAY_FAN);
  current_fan_state = false;

  initRelayOutput(PIN_RELAY_LED_RED);

  initRelayOutput(PIN_RELAY_LED_YELLOW);

  initRelayOutput(PIN_RELAY_LED_GREEN);

  initRelayOutput(PIN_RELAY_BUZZER);
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
