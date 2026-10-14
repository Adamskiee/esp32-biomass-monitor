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
  startMqWarmup(millis());
  setLedStatus(false, true, false);
  initApiServer();
  Serial.println("System Ready.");
}

void loop() {
  const unsigned long now = millis();
  const bool mq_warmup_just_finished =
      mqSensorsAreWarmingUp() && mqWarmupRemainingSeconds(now) == 0;
  if (now - lastRead >= POLL_INTERVAL_MS || mq_warmup_just_finished) {
    lastRead = now;

    // Block main loop to read hardware sensors
    float t_mq135 = readMQ135Voltage();
    float t_mq2 = readMQ2Voltage();
    float t_temp = readTemperature();
    float t_humidity = readHumidity();
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

    const bool mq_sensors_warming_up = mqWarmupRemainingSeconds(now) > 0;
    PmsReading pms_reading{};
    if (readPmsReading(pms_reading)) {
      recordPmsReading(pms_reading, millis());
    }
    processSensorReadings(t_temp, t_chamber, t_mq135, t_mq2,
                          mq_sensors_warming_up, t_humidity);

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

      safe_chamber_limit = safety_thresholds.values[0];
      safe_mq2_limit = safety_thresholds.values[1];
      xSemaphoreGive(stateMutex);
    }

    if (do_save) {
      saveSystemState(safe_chamber_limit, safe_mq2_limit);
      Serial.println("System state saved to NVS.");
    }
  }
}
