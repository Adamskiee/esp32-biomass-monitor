#include "AnalogSensors.h"
#include <BiomassConfig.h>
#include <cmath>

namespace {
constexpr float MQ_PULLUP_OFFSET_V = 1.32f;   // 3.3V * 10K / (10K + 15K)
constexpr float MQ_DISCONNECT_PIN_V = 3.05f;  // Pin pulled to 3.3V when unplugged
constexpr float MQ_CLEAN_AIR_FLOOR_V = 0.24f; // Baseline reading in clean air
constexpr float MQ_FAULT_REPORT_V = 5.0f;     // Exceeds 4.8V rail-short threshold
constexpr float MQ_SATURATED_GAS_V = 2.85f;   // Clamped ceiling during gas ramp
constexpr float MQ_GAS_RAMP_MIN_V = 2.55f;    // Pre-saturation ramp window (2.55V-2.88V)

float prev_mq135_v = NAN;
float prev_mq2_v = NAN;

float readTrueVoltage(uint8_t pin, float &prev_reading) {
  uint32_t mv = analogReadMilliVolts(pin);
  float pinVoltage = mv / 1000.0f;

  // When pin reaches >= 3.05V (2.88V+ sensor voltage):
  // - If the previous reading was in Clean Air or normal High Gas (< 2.55V),
  //   jumping straight to >= 3.05V is an unplugged wire -> report 5.0V fault.
  // - If the previous reading had already ramped into the pre-saturation buffer
  //   (2.55V - 2.88V), clamp and hold at 2.85V (High Gas) so continuous > 2.88V
  //   real smoke never triggers a false fault.
  if (pinVoltage >= MQ_DISCONNECT_PIN_V) {
    if (std::isfinite(prev_reading) && prev_reading >= MQ_GAS_RAMP_MIN_V &&
        prev_reading <= 4.8f) {
      prev_reading = MQ_SATURATED_GAS_V;
      return MQ_SATURATED_GAS_V;
    }
    prev_reading = MQ_FAULT_REPORT_V;
    return MQ_FAULT_REPORT_V;
  }

  // Subtract the 1.32V pull-up offset and reverse the 0.6 divider scaling,
  // maintaining the 0.24V clean-air baseline.
  float sensorVoltage = (pinVoltage - MQ_PULLUP_OFFSET_V) / V_DIVIDER_RATIO;
  float result = sensorVoltage < MQ_CLEAN_AIR_FLOOR_V ? MQ_CLEAN_AIR_FLOOR_V
                                                      : sensorVoltage;
  prev_reading = result;
  return result;
}
} // namespace

void initAnalogSensors() {
  prev_mq135_v = NAN;
  prev_mq2_v = NAN;
  pinMode(PIN_MQ135, INPUT);
  pinMode(PIN_MQ2, INPUT);
  analogReadResolution(12); // 0-4095
  // Use 11dB attenuation (full 0-3.3V range) for the 3.3V pull-up bias divider.
  analogSetPinAttenuation(PIN_MQ135, ADC_11db);
  analogSetPinAttenuation(PIN_MQ2, ADC_11db);
}

float readMQ135Voltage() {
  return readTrueVoltage(PIN_MQ135, prev_mq135_v);
}

float readMQ2Voltage() {
  return readTrueVoltage(PIN_MQ2, prev_mq2_v);
}

