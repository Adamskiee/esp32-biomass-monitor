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
  if (millis() - lastRead > 2000) {
    lastRead = millis();
    
    float mq135 = readMQ135Voltage();
    float mq2 = readMQ2Voltage();
    float temp = readTemperature();
    float exhaustTemp = readThermocouple();
    
    Serial.printf("MQ135: %.2fV | MQ2: %.2fV | Temp: %.1fC | Exhaust: %.1fC\n", 
                  mq135, mq2, temp, exhaustTemp);

    // Safety logic: if exhaust temp is too high or gas detected
    if (mq2 > 2.5 || exhaustTemp > 80.0) {
      setFan(true);
      setLedStatus(true, false, false); // Red LED
    } else {
      setFan(false);
      setLedStatus(false, false, true); // Green LED
    }
  }
}
