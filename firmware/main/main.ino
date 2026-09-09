#include "Config.h"
#include "Actuators.h"
#include "AnalogSensors.h"
#include "DigitalSensors.h"

void setup() {
  Serial.begin(115200);
  initActuators();
  initAnalogSensors();
  initDigitalSensors();
}

void loop() {
  Serial.println(readTemperature());
  delay(1000);
}
