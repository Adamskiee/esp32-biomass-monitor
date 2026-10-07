#pragma once
#include <Arduino.h>

struct DigitalSensorReadings {
  float temperature_c;
  float humidity_percent;
  float chamber_temp_c;
  int pm1_ug_m3;
  int pm25_ug_m3;
  int pm10_ug_m3;
};

void initDigitalSensors();
DigitalSensorReadings readDigitalSensors();
