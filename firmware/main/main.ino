#include "Actuators.h"
#include "AnalogSensors.h"
#include "ApiServer.h"
#include "DigitalSensors.h"
#include "SystemState.h"
#include <ArduinoJson.h>
#include <BiomassConfig.h>

unsigned long lastRead = 0;

void setup() {
  Serial.begin(115200);
  initSystemState();
  initActuators();
  initAnalogSensors();
  initDigitalSensors();
  setFan(true);
  setLedStatus(false, true, false);
  initApiServer();
  Serial.println("System Ready.");
}

void loop() {
  updateActuatorTransitions();

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

    processSensorReadings(t_temp, t_chamber, t_mq135, t_mq2);

    PmsReading pms_reading{};
    if (readPmsReading(pms_reading)) {
      recordPmsReading(pms_reading, millis());
    }

    // Grab safe copies for persistence without holding the mutex during flash
    // writes
    if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(10))) {
      static unsigned long last_save = 0;
      if (state_needs_save &&
          (last_save == 0 || millis() - last_save > 60000)) {
        do_save = true;
        state_needs_save = false; // Only clear it when we are actually saving
        last_save = millis();     // Optimistically update
      }

      safe_chamber_limit = threshold_chamber_temp_c;
      safe_mq2_limit = threshold_mq2_v;
      xSemaphoreGive(stateMutex);
    }

    if (do_save) {
      saveSystemState(safe_chamber_limit, safe_mq2_limit);
      Serial.println("System state saved to NVS.");
    }
  }
}
