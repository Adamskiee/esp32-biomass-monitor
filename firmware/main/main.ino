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

    Serial.printf("MQ135: %.2fV | MQ2: %.2fV | Temp: %s | Humidity: %.1f%% | Chamber: %.1fC\n",
                  t_mq135, t_mq2, tempStr, t_humidity, t_chamber);

    bool do_save = false;
    SafetyThresholds snapshot;

    const bool mq_sensors_warming_up = mqWarmupRemainingSeconds(now) > 0;
    PmsReading pms_reading{};
    if (readPmsReading(pms_reading)) {
      recordPmsReading(pms_reading, millis());
    }
    processSensorReadings(t_temp, t_chamber, t_mq135, t_mq2,
                          mq_sensors_warming_up, t_humidity);

    if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(10))) {
      do_save = threshold_persistence.beginSave(millis(), safety_thresholds,
                                                snapshot);
      xSemaphoreGive(stateMutex);
    }

    if (do_save) {
      const bool succeeded = saveSystemState(snapshot);
      // Completion must be acknowledged even if API updates temporarily own the
      // lock.
      xSemaphoreTake(stateMutex, portMAX_DELAY);
      threshold_persistence.finishSave(succeeded);
      xSemaphoreGive(stateMutex);
      Serial.println(succeeded ? "System state saved to NVS."
                               : "System state save failed; retry pending.");
    }
  }
}
