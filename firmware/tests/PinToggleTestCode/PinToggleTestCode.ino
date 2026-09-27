#include <Arduino.h>

// Include the project config to keep pins in sync
#include "../../main/Config.h"

// Note on Hardware Safety: Software fixes in setup() cannot prevent relays
// from floating during the ESP32's bootloader phase. Ensure physical pull-up
// resistors are installed on relay control lines to prevent boot chattering.

// Relays (Controlled via RELAY_ON / RELAY_OFF logic)
const int relayPins[] = {PIN_RELAY_SOLENOID, PIN_RELAY_FAN, PIN_RELAY_LED_RED,
                         PIN_RELAY_LED_YELLOW, PIN_RELAY_LED_GREEN};
const int numRelayPins = sizeof(relayPins) / sizeof(relayPins[0]);

// Standard Logic Pins (Input/bidirectional pins removed for safety)
const int logicPins[] = {PIN_MAX6675_SCK, PIN_MAX6675_CS, PIN_PM25_TX};
const int numLogicPins = sizeof(logicPins) / sizeof(logicPins[0]);

void setup() {
  // 1. Initialize Relays to safe OFF state IMMEDIATELY (before Serial)
  for (int i = 0; i < numRelayPins; i++) {
    digitalWrite(relayPins[i], RELAY_OFF);
    pinMode(relayPins[i], OUTPUT);
  }

  // 2. Initialize standard logic pins to LOW
  for (int i = 0; i < numLogicPins; i++) {
    digitalWrite(logicPins[i], LOW);
    pinMode(logicPins[i], OUTPUT);
  }

  // 3. Initialize Serial after critical hardware is safe
  Serial.begin(115200);
  delay(1000);

  Serial.println("=========================================");
  Serial.println("      ESP32 GPIO TOGGLE TESTER           ");
  Serial.println("=========================================");
  Serial.println("This script tests pins sequentially.");
  Serial.println("It will activate each pin for 10s,");
  Serial.println("deactivate it, and move to the next.");
  Serial.println("=========================================\n");
}

void loop() {
  // Test Relays
  Serial.println("\n--- Testing Relay Pins ---");
  for (int i = 0; i < numRelayPins; i++) {
    int currentPin = relayPins[i];
    Serial.print("\n>>> Testing Relay Pin ");
    Serial.print(currentPin);
    Serial.println(" (Setting to RELAY_ON for 10s) <<<");

    digitalWrite(currentPin, RELAY_ON);
    delay(10000);

    Serial.print("    Relay Pin ");
    Serial.print(currentPin);
    Serial.println(" is now RELAY_OFF.");
    digitalWrite(currentPin, RELAY_OFF);
    delay(2000);
  }

  // Test Logic Pins
  Serial.println("\n--- Testing Logic Pins ---");
  for (int i = 0; i < numLogicPins; i++) {
    int currentPin = logicPins[i];
    Serial.print("\n>>> Testing Logic Pin ");
    Serial.print(currentPin);
    Serial.println(" (Setting HIGH (3.3V) for 10s) <<<");

    digitalWrite(currentPin, HIGH);
    delay(10000);

    Serial.print("    Logic Pin ");
    Serial.print(currentPin);
    Serial.println(" is now LOW (0V).");
    digitalWrite(currentPin, LOW);
    delay(2000);
  }

  Serial.println("\n--- All pins tested. Restarting cycle... ---");
  delay(3000);
}
