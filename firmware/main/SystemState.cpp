#include "SystemState.h"
#include "Actuators.h"
#include <math.h>

using std::isnan;

float threshold_chamber_temp_c = 80.0;
float threshold_mq2_v = 2.5;

float current_temp_c = 0.0;
float current_chamber_c = 0.0;
float current_mq135_v = 0.0;
float current_mq2_v = 0.0;

bool state_needs_save = false;

bool manual_sprinkler = false;
bool catastrophic_latch = false;
String active_triggers_json = "[]";

static bool temp_latch_danger = false;
static bool mq2_latch_danger = false;

#ifdef ARDUINO
SemaphoreHandle_t stateMutex = nullptr;
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
#else
SemaphoreHandle_t stateMutex = nullptr;
void initSystemState() {}
void saveSystemState(float chamber_limit, float mq2_limit) {}
#endif

void evaluateSafetyLoop() {
    if (stateMutex != nullptr) {
        xSemaphoreTake(stateMutex, portMAX_DELAY);
    }

    bool is_temp_fault = isnan(current_chamber_c);
    bool is_mq2_fault = isnan(current_mq2_v);

    // Hysteresis states
    bool in_temp_danger = !is_temp_fault && (current_chamber_c >= threshold_chamber_temp_c);
    bool in_mq2_danger = !is_mq2_fault && (current_mq2_v >= threshold_mq2_v);

    if (in_temp_danger) {
        temp_latch_danger = true;
    } else if (!is_temp_fault && current_chamber_c <= threshold_chamber_temp_c * 0.95f) {
        temp_latch_danger = false;
    }
    bool prev_mq2_latch = mq2_latch_danger;
    if (in_mq2_danger) {
        mq2_latch_danger = true;
    } else if (!is_mq2_fault && current_mq2_v <= threshold_mq2_v * 0.95f) {
        mq2_latch_danger = false;
    }
    
    if (mq2_latch_danger && !prev_mq2_latch) {
        manual_sprinkler = false;
    }


    // Check catastrophic fire latch condition:
    // Only latch if the system was actively in temperature danger when the sensor faulted.
    // Manual blind-fire during a fault must NOT trip the catastrophic latch.
    if (is_temp_fault && temp_latch_danger) {
        catastrophic_latch = true;
    }

    // Build active triggers JSON
    String triggers = "[";
    bool first = true;
    auto add_trigger = [&](const char* name) {
        if (!first) triggers += ",";
        triggers += "\"";
        triggers += name;
        triggers += "\"";
        first = false;
    };

    if (catastrophic_latch) add_trigger("catastrophic_latch");
    if (temp_latch_danger) add_trigger("high_chamber_temp");
    if (mq2_latch_danger) add_trigger("high_mq2_gas");
    if (is_temp_fault) add_trigger("temp_sensor_fault");
    if (is_mq2_fault) add_trigger("mq2_sensor_fault");
    triggers += "]";
    active_triggers_json = triggers;

    // Actuator Control
    if (catastrophic_latch || temp_latch_danger) {
        setSolenoid(true, false);
        manual_sprinkler = false; // Danger resets manual sprinkler
    } else if (is_temp_fault) {
        // Temp fault defaults to OFF unless manual sprinkler is actively engaged (blind-fire)
        // Critical ruling: Do not clear manual_sprinkler here
        setSolenoid(manual_sprinkler, false);
    } else {
        // Safe or Gas-only danger: follow manual sprinkler
        setSolenoid(manual_sprinkler, false);
    }

    if (stateMutex != nullptr) {
        xSemaphoreGive(stateMutex);
    }
}
