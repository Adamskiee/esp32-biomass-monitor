#pragma once
#include <Arduino.h>
#include "PmsReading.h"

void initDigitalSensors();
float readTemperature();
float readHumidity();
float readThermocouple();
bool readPmsReading(PmsReading &out);
