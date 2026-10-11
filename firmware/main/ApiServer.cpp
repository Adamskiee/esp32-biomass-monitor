#include "ApiServer.h"
#include "Actuators.h"
#include "Secrets.h"
#include "SystemState.h"
#include <ArduinoJson.h>
#include <AsyncJson.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <WiFi.h>

AsyncWebServer server(80);

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
    const bool hasChamber = !chamberValue.isUnbound();
    const bool hasMq2 = !mq2Value.isUnbound();
    auto isNumber = [](JsonVariant value) {
      return value.is<float>() || value.is<int>() || value.is<int64_t>();
    };
    if ((hasChamber && !isNumber(chamberValue)) ||
        (hasMq2 && !isNumber(mq2Value))) {
      AsyncWebServerResponse *response =
          request->beginResponse(400, "application/json",
                                 "{\"status\":\"error\",\"message\":"
                                 "\"Thresholds must be numbers\"}");
      return request->send(response);
    }

    const ThresholdUpdateResult result = applyThresholdUpdate(
        hasChamber, chamberValue.as<float>(), hasMq2, mq2Value.as<float>());
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

  server.onNotFound([](AsyncWebServerRequest *request) {
    AsyncWebServerResponse *response =
        request->beginResponse(404, "text/plain", "Not Found");
    request->send(response);
  });

  server.begin();
}
