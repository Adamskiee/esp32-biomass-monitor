#include "Config.h"
#include "Actuators.h"

void setup() {
  Serial.begin(115200);
  initActuators();
  setLedStatus(false, true, false); // Test yellow
}

void loop() {}

