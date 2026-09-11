#include "AnalogSensors.h"
#include <BiomassConfig.h>

void initAnalogSensors() {
  pinMode(PIN_MQ135, INPUT);
  pinMode(PIN_MQ2, INPUT);
  analogReadResolution(12); // 0-4095
}

static float readTrueVoltage(uint8_t pin) {
  int raw = analogRead(pin);
  // ESP32 ADC is roughly 0-3.3V for 0-4095. 
  // Reverse the voltage divider scaling (0.6) to get true 5V sensor output.
  float pinVoltage = (raw / 4095.0f) * 3.3f;
  return pinVoltage / V_DIVIDER_RATIO; 
}

float readMQ135Voltage() {
  return readTrueVoltage(PIN_MQ135);
}

float readMQ2Voltage() {
  return readTrueVoltage(PIN_MQ2);
}
