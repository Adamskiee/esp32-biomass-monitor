#include "Config.h"
#include "Actuators.h"
#include "AnalogSensors.h"

void setup() {
  Serial.begin(115200);
  initActuators();
  initAnalogSensors();
}

void loop() {
  Serial.println(readMQ135Voltage());
  delay(1000);
}


