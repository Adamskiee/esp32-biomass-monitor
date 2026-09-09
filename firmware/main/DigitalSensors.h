#pragma once
#include <Arduino.h>

void initDigitalSensors();
float readTemperature();
float readHumidity();
float readThermocouple();
int readPM25();
