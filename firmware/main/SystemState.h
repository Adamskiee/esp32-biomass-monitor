#pragma once
#include <Arduino.h>
#include <Preferences.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

// Thresholds
extern float threshold_chamber_temp_c;
extern float threshold_mq2_v;
// Cached Sensor Readings (API reads these instead of blocking)
extern float current_temp_c;
extern float current_chamber_c;
extern float current_mq135_v;
extern float current_mq2_v;

extern bool state_needs_save;
extern SemaphoreHandle_t stateMutex;

void initSystemState();
void saveSystemState(float chamber_limit, float mq2_limit);
