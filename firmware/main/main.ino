#include <ArduinoJson.h>
#include "Config.h"
#include "SystemState.h"
#include "Actuators.h"
#include "AnalogSensors.h"
#include "DigitalSensors.h"
#include "ApiServer.h"

unsigned long lastRead = 0;

void setup() {
  Serial.begin(115200);
  initSystemState();
  initActuators();
  initAnalogSensors();
  initDigitalSensors();
  setLedStatus(false, false, true); // Green = system ready
  initApiServer();
  Serial.println("System Ready.");
}

void loop() {
  if (millis() - lastRead >= POLL_INTERVAL_MS) {
    lastRead = millis();
    
    // Block main loop to read hardware sensors
    float t_mq135 = readMQ135Voltage();
    float t_mq2 = readMQ2Voltage();
    float t_temp = readTemperature();
    float t_chamber = readThermocouple();
    
    char tempStr[16];
    if (isnan(t_temp)) {
      snprintf(tempStr, sizeof(tempStr), "ERR");
    } else {
      snprintf(tempStr, sizeof(tempStr), "%.1fC", t_temp);
    }

    Serial.printf("MQ135: %.2fV | MQ2: %.2fV | Temp: %s | Chamber: %.1fC\n", 
                  t_mq135, t_mq2, tempStr, t_chamber);

    bool do_save = false;
    static float safe_chamber_limit = 80.0;
    static float safe_mq2_limit = 2.5;
    
    // Grab safe copies and update API cache rapidly
    if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(10))) {
        // Update sensor cache for API
        current_mq135_v = t_mq135;
        current_mq2_v = t_mq2;
        current_temp_c = t_temp;
        current_chamber_c = t_chamber;
        
        // Check NVS save flag and rate limit
        static unsigned long last_save = 0;
        if (state_needs_save && (last_save == 0 || millis() - last_save > 60000)) {
            do_save = true;
            state_needs_save = false; // Only clear it when we are actually saving
            last_save = millis();     // Optimistically update
        }
        
        // Read limits
        safe_chamber_limit = threshold_chamber_temp_c;
        safe_mq2_limit = threshold_mq2_v;
        xSemaphoreGive(stateMutex);
    }

    // Save safely outside the mutex using local copies
    if (do_save) {
        saveSystemState(safe_chamber_limit, safe_mq2_limit);
        Serial.println("System state saved to NVS.");
    }
    
    // Safety logic (unchanged visually but using local limits)
    if (isnan(t_chamber) || isnan(t_mq2) || t_mq2 < 0.1 || t_mq2 > safe_mq2_limit || t_chamber > safe_chamber_limit) {
        setFan(true);
        setLedStatus(true, false, false); // Red LED
    } else {
        setFan(false);
        setLedStatus(false, false, true); // Green LED
    }
  }
}
