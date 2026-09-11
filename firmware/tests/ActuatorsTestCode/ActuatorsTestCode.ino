#include <Arduino.h>

#include <BiomassConfig.h>

void setup() {
  Serial.begin(115200);
  Serial.println("Actuators Test Started");

  // Write HIGH *before* pinMode to prevent relay chattering/glitching on startup
  digitalWrite(PIN_RELAY_SOLENOID, RELAY_OFF);
  digitalWrite(PIN_RELAY_FAN, RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_RED, RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_YELLOW, RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_GREEN, RELAY_OFF);

  pinMode(PIN_RELAY_SOLENOID, OUTPUT);
  pinMode(PIN_RELAY_FAN, OUTPUT);
  pinMode(PIN_RELAY_LED_RED, OUTPUT);
  pinMode(PIN_RELAY_LED_YELLOW, OUTPUT);
  pinMode(PIN_RELAY_LED_GREEN, OUTPUT);
}

void loop() {
  Serial.println("Turning ON: Solenoid");
  digitalWrite(PIN_RELAY_SOLENOID, RELAY_ON);
  delay(1000);
  digitalWrite(PIN_RELAY_SOLENOID, RELAY_OFF);
  delay(1000);

  Serial.println("Turning ON: Fan");
  digitalWrite(PIN_RELAY_FAN, RELAY_ON);
  delay(1000);
  digitalWrite(PIN_RELAY_FAN, RELAY_OFF);
  delay(1000);

  Serial.println("Turning ON: Red LED");
  digitalWrite(PIN_RELAY_LED_RED, RELAY_ON);
  delay(1000);
  digitalWrite(PIN_RELAY_LED_RED, RELAY_OFF);
  delay(1000);

  Serial.println("Turning ON: Yellow LED");
  digitalWrite(PIN_RELAY_LED_YELLOW, RELAY_ON);
  delay(1000);
  digitalWrite(PIN_RELAY_LED_YELLOW, RELAY_OFF);
  delay(1000);

  Serial.println("Turning ON: Green LED");
  digitalWrite(PIN_RELAY_LED_GREEN, RELAY_ON);
  delay(1000);
  digitalWrite(PIN_RELAY_LED_GREEN, RELAY_OFF);
  delay(1000);
  
  Serial.println("Cycle Complete. Restarting...\n");
}
