#include "Config.h"
#include "Actuators.h"
#include "AnalogSensors.h"
#include "DigitalSensors.h"

unsigned long lastRead = 0;

void setup() {
  Serial.begin(115200);
  initActuators();
  initAnalogSensors();
  initDigitalSensors();
  setLedStatus(false, false, true); // Green = system ready
  Serial.println("System Ready.");
}

void loop() {
  if (millis() - lastRead >= POLL_INTERVAL_MS) {
    lastRead = millis();
    
    float mq135 = readMQ135Voltage();
    float mq2 = readMQ2Voltage();
    float temp = readTemperature();
    float chamberTemp = readThermocouple();
    
    char tempStr[16];
    if (isnan(temp)) {
      snprintf(tempStr, sizeof(tempStr), "ERR");
    } else {
      snprintf(tempStr, sizeof(tempStr), "%.1fC", temp);
    }

    Serial.printf("MQ135: %.2fV | MQ2: %.2fV | Temp: %s | Chamber: %.1fC\n", 
                  mq135, mq2, tempStr, chamberTemp);

    // Safety logic: if chamber temp is too high, gas detected, or sensor fault (fail-safe)
    if (isnan(chamberTemp) || mq2 < 0.1 || mq2 > MQ2_ALARM_VOLTAGE || chamberTemp > CHAMBER_TEMP_ALARM_C) {
      setFan(true);
      setLedStatus(true, false, false); // Red LED
    } else {
      setFan(false);
      setLedStatus(false, false, true); // Green LED
    }
  }
}
