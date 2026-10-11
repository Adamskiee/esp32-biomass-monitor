#include "ApiServer.h"
#include "Actuators.h"
#include "MqCalibration.h"
#include "Secrets.h"
#include "SystemState.h"
#include <ArduinoJson.h>
#include <AsyncJson.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <WiFi.h>

AsyncWebServer server(80);

namespace {

const char *modeName(Mq2ThresholdMode mode) {
  return mode == Mq2ThresholdMode::ResponseRatio ? "response_ratio"
                                                  : "legacy_voltage";
}

const char *calibrationStatus(MqSensor sensor, float response) {
  if (!hasMqCalibration(sensor)) {
    return "uncalibrated";
  }
  return isfinite(response) ? "ready" : "invalid";
}

void writeResponse(JsonDocument &doc, const char *field, float value) {
  if (isfinite(value)) {
    doc[field] = value;
  } else {
    doc[field] = nullptr;
  }
}

} // namespace

void initApiServer() {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  WiFi.onEvent(
      [](WiFiEvent_t event, WiFiEventInfo_t info) {
        Serial.print("WiFi connected! API IP address: ");
        Serial.println(WiFi.localIP());
      },
      WiFiEvent_t::ARDUINO_EVENT_WIFI_STA_GOT_IP);

  auto send401 = [](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response =
        request->beginResponse(401, "text/plain", "Unauthorized");
    response->addHeader("WWW-Authenticate", "Basic realm=\"Login Required\"");
    request->send(response);
  };

  server.on("/api/state", HTTP_GET, [send401](AsyncWebServerRequest *request) {
    if (!request->authenticate(API_USER, API_PASS))
      return send401(request);

    if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5)) != pdTRUE) {
      AsyncWebServerResponse *response = request->beginResponse(
          503, "application/json",
          "{\"status\":\"error\",\"message\":\"Server busy\"}");
      return request->send(response);
    }

    JsonDocument doc;
    if (isnan(current_temp_c))
      doc["temperature_c"] = nullptr;
    else
      doc["temperature_c"] = current_temp_c;
    if (isnan(current_chamber_c))
      doc["chamber_temp_c"] = nullptr;
    else
      doc["chamber_temp_c"] = current_chamber_c;
    if (isnan(current_mq135_v))
      doc["mq135_v"] = nullptr;
    else
      doc["mq135_v"] = current_mq135_v;
    if (isnan(current_mq2_v))
      doc["mq2_v"] = nullptr;
    else
      doc["mq2_v"] = current_mq2_v;
    writeResponse(doc, "mq2_response_ratio", current_mq2_response_ratio);
    writeResponse(doc, "mq135_response_ratio", current_mq135_response_ratio);
    const MqConfiguration &mq_config = currentMqConfiguration();
    if (mq_config.mq2_calibration_id == 0)
      doc["mq2_calibration_id"] = nullptr;
    else
      doc["mq2_calibration_id"] = mq_config.mq2_calibration_id;
    if (mq_config.mq135_calibration_id == 0)
      doc["mq135_calibration_id"] = nullptr;
    else
      doc["mq135_calibration_id"] = mq_config.mq135_calibration_id;
    doc["mq2_calibration_status"] =
        calibrationStatus(MqSensor::Mq2, current_mq2_response_ratio);
    doc["mq135_calibration_status"] =
        calibrationStatus(MqSensor::Mq135, current_mq135_response_ratio);
    doc["mq2_threshold_mode"] = modeName(mq2_threshold_mode);
    doc["mq2_safety_mode"] = modeName(mq2_safety_mode);
    writeResponse(doc, "threshold_mq2_response_ratio",
                  threshold_mq2_response_ratio);
    PmsReading pms_reading{};
    if (copyFreshPmsReadingLocked(millis(), pms_reading)) {
      doc["pm1_0_ug_m3"] = pms_reading.pm1_0_ug_m3;
      doc["pm2_5_ug_m3"] = pms_reading.pm2_5_ug_m3;
      doc["pm10_ug_m3"] = pms_reading.pm10_ug_m3;
    } else {
      doc["pm1_0_ug_m3"] = nullptr;
      doc["pm2_5_ug_m3"] = nullptr;
      doc["pm10_ug_m3"] = nullptr;
    }
    doc["threshold_chamber_temp_c"] = threshold_chamber_temp_c;
    doc["threshold_mq2_v"] = threshold_mq2_v;
    doc["fan_on"] = current_fan_state;
    doc["sprinkler_on"] = current_solenoid_state;
    doc["pump_on"] = current_pump_state;
    doc["manual_sprinkler"] = manual_sprinkler;
    deserializeJson(doc["active_triggers"], active_triggers_json);
    xSemaphoreGive(stateMutex);

    AsyncResponseStream *response =
        request->beginResponseStream("application/json");
    serializeJson(doc, *response);
    request->send(response);
  });

  AsyncCallbackJsonWebHandler *controlHandler = new AsyncCallbackJsonWebHandler(
      "/api/control",
      [send401](AsyncWebServerRequest *request, JsonVariant &json) {
        if (!request->authenticate(API_USER, API_PASS))
          return send401(request);
        if (!json.is<JsonObject>() || !json["sprinkler"].is<bool>()) {
          AsyncWebServerResponse *response =
              request->beginResponse(400, "application/json",
                                     "{\"status\":\"error\",\"message\":"
                                     "\"sprinkler must be a boolean\"}");
          return request->send(response);
        }

        const ManualSprinklerResult result =
            applyManualSprinklerCommand(json["sprinkler"].as<bool>());
        if (result == ManualSprinklerResult::Busy) {
          AsyncWebServerResponse *response = request->beginResponse(
              503, "application/json",
              "{\"status\":\"error\",\"message\":\"Server busy\"}");
          return request->send(response);
        }
        if (result == ManualSprinklerResult::SafetyOverride) {
          AsyncWebServerResponse *response =
              request->beginResponse(409, "application/json",
                                     "{\"status\":\"error\",\"message\":"
                                     "\"Automatic safety control is active\"}");
          return request->send(response);
        }

        AsyncWebServerResponse *response = request->beginResponse(
            200, "application/json", "{\"status\":\"ok\"}");
        request->send(response);
      });
  controlHandler->setMethod(HTTP_POST);
  controlHandler->setMaxContentLength(256);
  server.addHandler(controlHandler);

  auto handleThresholdUpdate = [send401](AsyncWebServerRequest *request,
                                         JsonVariant &json) {
    if (!request->authenticate(API_USER, API_PASS))
      return send401(request);
    if (!json.is<JsonObject>()) {
      AsyncWebServerResponse *response =
          request->beginResponse(400, "application/json",
                                 "{\"status\":\"error\",\"message\":"
                                 "\"Expected a JSON object\"}");
      return request->send(response);
    }

    JsonObject jsonObj = json.as<JsonObject>();
    JsonVariant chamberValue = jsonObj["threshold_chamber_temp_c"];
    JsonVariant mq2Value = jsonObj["threshold_mq2_v"];
    JsonVariant responseValue = jsonObj["threshold_mq2_response_ratio"];
    JsonVariant modeValue = jsonObj["mq2_threshold_mode"];
    const bool hasChamber = !chamberValue.isUnbound();
    const bool hasMq2 = !mq2Value.isUnbound();
    const bool hasResponse = !responseValue.isUnbound();
    const bool hasMode = !modeValue.isUnbound();
    auto isNumber = [](JsonVariant value) {
      return value.is<float>() || value.is<int>() || value.is<int64_t>();
    };
    if ((hasChamber && !isNumber(chamberValue)) ||
        (hasMq2 && !isNumber(mq2Value)) ||
        (hasResponse && !isNumber(responseValue)) ||
        (hasMode && (!modeValue.is<const char *>() ||
                     strcmp(modeValue.as<const char *>(), "legacy_voltage") != 0))) {
      AsyncWebServerResponse *response =
          request->beginResponse(400, "application/json",
                                 "{\"status\":\"error\",\"message\":"
                                 "\"Thresholds must be numbers\"}");
      return request->send(response);
    }

    const ThresholdUpdateResult result = applyThresholdUpdate(
        hasChamber, chamberValue.as<float>(), hasMq2, mq2Value.as<float>(),
        hasResponse, responseValue.as<float>(), hasMode);
    if (result == ThresholdUpdateResult::Invalid) {
      AsyncWebServerResponse *response = request->beginResponse(
          400, "application/json",
          "{\"status\":\"error\",\"message\":\"Threshold values are "
          "out of range\"}");
      return request->send(response);
    }
    if (result == ThresholdUpdateResult::Busy) {
      AsyncWebServerResponse *response = request->beginResponse(
          503, "application/json",
          "{\"status\":\"error\",\"message\":\"Server busy\"}");
      return request->send(response);
    }
    if (result == ThresholdUpdateResult::MissingCalibration) {
      return request->send(request->beginResponse(
          409, "application/json", "{\"status\":\"error\",\"message\":\"MQ-2 calibration required\"}"));
    }
    if (result == ThresholdUpdateResult::Cooldown) {
      AsyncWebServerResponse *response = request->beginResponse(
          429, "application/json", "{\"status\":\"error\",\"message\":\"Settings write cooldown\"}");
      response->addHeader("Retry-After", "60");
      return request->send(response);
    }
    if (result == ThresholdUpdateResult::PersistenceFailed) {
      return request->send(request->beginResponse(
          503, "application/json", "{\"status\":\"error\",\"message\":\"Settings persistence failed\"}"));
    }

    AsyncWebServerResponse *response =
        request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
    request->send(response);
  };
  AsyncCallbackJsonWebHandler *thresholdHandler =
      new AsyncCallbackJsonWebHandler("/api/thresholds", handleThresholdUpdate);
  thresholdHandler->setMethod(HTTP_POST);
  thresholdHandler->setMaxContentLength(256);
  server.addHandler(thresholdHandler);

  AsyncCallbackJsonWebHandler *settingsHandler =
      new AsyncCallbackJsonWebHandler("/api/settings", handleThresholdUpdate);
  settingsHandler->setMethod(HTTP_POST);
  settingsHandler->setMaxContentLength(256);
  server.addHandler(settingsHandler);

  server.on("/api/settings", HTTP_GET,
            [send401](AsyncWebServerRequest *request) {
              if (!request->authenticate(API_USER, API_PASS))
                return send401(request);

              JsonDocument doc;
              if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5))) {
                doc["threshold_chamber_temp_c"] = threshold_chamber_temp_c;
                doc["threshold_mq2_v"] = threshold_mq2_v;
                doc["mq2_threshold_mode"] = modeName(mq2_threshold_mode);
                writeResponse(doc, "threshold_mq2_response_ratio",
                              threshold_mq2_response_ratio);
                xSemaphoreGive(stateMutex);

                AsyncResponseStream *response =
                    request->beginResponseStream("application/json");
                serializeJson(doc, *response);
                request->send(response);
              } else {
                AsyncWebServerResponse *response = request->beginResponse(
                    503, "application/json",
                    "{\"status\":\"error\",\"message\":\"Server busy\"}");
                request->send(response);
              }
            });

  AsyncCallbackJsonWebHandler *calibrationHandler = new AsyncCallbackJsonWebHandler(
      "/api/mq/calibration", [send401](AsyncWebServerRequest *request,
                                         JsonVariant &json) {
        if (!request->authenticate(API_USER, API_PASS))
          return send401(request);
        if (!json.is<JsonObject>() || !json["sensor"].is<const char *>()) {
          return request->send(request->beginResponse(
              400, "application/json", "{\"status\":\"error\",\"message\":\"sensor must be mq2 or mq135\"}"));
        }
        const char *sensor_name = json["sensor"].as<const char *>();
        const MqSensor sensor = strcmp(sensor_name, "mq2") == 0
                                    ? MqSensor::Mq2
                                    : strcmp(sensor_name, "mq135") == 0
                                          ? MqSensor::Mq135
                                          : static_cast<MqSensor>(-1);
        if (sensor_name[0] == '\0' || (strcmp(sensor_name, "mq2") != 0 && strcmp(sensor_name, "mq135") != 0)) {
          return request->send(request->beginResponse(
              400, "application/json", "{\"status\":\"error\",\"message\":\"sensor must be mq2 or mq135\"}"));
        }
        const MqCalibrationResult result = captureMqCalibration(sensor, millis());
        if (result != MqCalibrationResult::Accepted) {
          const int code = result == MqCalibrationResult::Cooldown ? 429 : 409;
          AsyncWebServerResponse *response = request->beginResponse(
              code, "application/json", "{\"status\":\"error\",\"message\":\"Calibration unavailable\"}");
          if (code == 429) response->addHeader("Retry-After", "60");
          return request->send(response);
        }
        const MqConfiguration &config = currentMqConfiguration();
        JsonDocument doc;
        doc["calibration_id"] = sensor == MqSensor::Mq2 ? config.mq2_calibration_id : config.mq135_calibration_id;
        doc["baseline_v"] = sensor == MqSensor::Mq2 ? config.mq2_baseline_v : config.mq135_baseline_v;
        doc["circuit_supply_v"] = sensor == MqSensor::Mq2 ? config.mq2_supply_v : config.mq135_supply_v;
        AsyncResponseStream *response = request->beginResponseStream("application/json");
        serializeJson(doc, *response);
        request->send(response);
      });
  calibrationHandler->setMethod(HTTP_POST);
  calibrationHandler->setMaxContentLength(64);
  server.addHandler(calibrationHandler);

  server.onNotFound([](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response =
        request->beginResponse(404, "text/plain", "Not Found");
    request->send(response);
  });

  server.begin();
}
