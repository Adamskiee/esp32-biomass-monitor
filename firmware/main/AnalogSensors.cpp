#include "AnalogSensors.h"
#include <BiomassConfig.h>

namespace {
constexpr float MQ_PULLUP_OFFSET_V = 1.32f;   // 3.3V * 10K / (10K + 15K)
constexpr float MQ_DISCONNECT_PIN_V = 3.05f;  // Pin pulled to 3.3V when unplugged
constexpr float MQ_CLEAN_AIR_FLOOR_V = 0.24f; // Baseline reading in clean air
constexpr float MQ_FAULT_REPORT_V = 5.0f;     // Exceeds 4.8V rail-short threshold
} // namespace

void initAnalogSensors() {
  pinMode(PIN_MQ135, INPUT);
  pinMode(PIN_MQ2, INPUT);
  analogReadResolution(12); // 0-4095
  // Use 11dB attenuation (full 0-3.3V range) for the 3.3V pull-up bias divider.
  analogSetPinAttenuation(PIN_MQ135, ADC_11db);
  analogSetPinAttenuation(PIN_MQ2, ADC_11db);
}

static float readTrueVoltage(uint8_t pin) {
  uint32_t mv = analogReadMilliVolts(pin);
  float pinVoltage = mv / 1000.0f;

  // When unplugged, the 15k pull-up to 3.3V pulls the pin above 3.05V.
  if (pinVoltage >= MQ_DISCONNECT_PIN_V) {
    return MQ_FAULT_REPORT_V;
  }

  // Subtract the 1.32V pull-up offset and reverse the 0.6 divider scaling,
  // maintaining the 0.24V clean-air baseline.
  float sensorVoltage = (pinVoltage - MQ_PULLUP_OFFSET_V) / V_DIVIDER_RATIO;
  return sensorVoltage < MQ_CLEAN_AIR_FLOOR_V ? MQ_CLEAN_AIR_FLOOR_V
                                              : sensorVoltage;
}

float readMQ135Voltage() {
  return readTrueVoltage(PIN_MQ135);
}

float readMQ2Voltage() {
  return readTrueVoltage(PIN_MQ2);
}

