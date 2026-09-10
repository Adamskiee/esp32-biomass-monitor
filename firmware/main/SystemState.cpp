#include "SystemState.h"

float threshold_chamber_temp_c = 80.0;
float threshold_mq2_v = 2.5;

float current_temp_c = 0.0;
float current_chamber_c = 0.0;
float current_mq135_v = 0.0;
float current_mq2_v = 0.0;

bool state_needs_save = false;
SemaphoreHandle_t stateMutex;
Preferences preferences;

void initSystemState() {
    stateMutex = xSemaphoreCreateMutex();
    if (stateMutex == NULL) {
        Serial.println("FATAL: Failed to create stateMutex!");
        ESP.restart(); // Reboot to attempt recovery
    }

    preferences.begin("biomass", false);
    
    threshold_chamber_temp_c = preferences.getFloat("chamber_temp", 80.0);
    threshold_mq2_v = preferences.getFloat("mq2_v", 2.5);
}

void saveSystemState(float chamber_limit, float mq2_limit) {
    preferences.putFloat("chamber_temp", chamber_limit);
    preferences.putFloat("mq2_v", mq2_limit);
}
