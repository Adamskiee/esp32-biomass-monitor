#include <Arduino.h>

#include <BiomassConfig.h>

void setup() {
  Serial.begin(115200);
  Serial.println("Actuators Test Started");

  digitalWrite(PIN_RELAY_PUMP, RELAY_OFF);
  digitalWrite(PIN_RELAY_BUZZER, RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_RED, RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_YELLOW, RELAY_OFF);
  digitalWrite(PIN_RELAY_LED_GREEN, RELAY_OFF);

  pinMode(PIN_RELAY_PUMP, OUTPUT);
  pinMode(PIN_RELAY_BUZZER, OUTPUT);
  pinMode(PIN_RELAY_LED_RED, OUTPUT);
  pinMode(PIN_RELAY_LED_YELLOW, OUTPUT);
  pinMode(PIN_RELAY_LED_GREEN, OUTPUT);
}

void loop() {
  Serial.println("Turning ON: Pump");
  digitalWrite(PIN_RELAY_PUMP, RELAY_ON);
  delay(1000);
  digitalWrite(PIN_RELAY_PUMP, RELAY_OFF);
  delay(1000);

  Serial.println("Turning ON: Buzzer");
  digitalWrite(PIN_RELAY_BUZZER, RELAY_ON);
  delay(1000);
  digitalWrite(PIN_RELAY_BUZZER, RELAY_OFF);
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
