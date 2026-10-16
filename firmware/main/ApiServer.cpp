#include "ApiServer.h"
#include "Actuators.h"
#include "Secrets.h"
#include "SystemState.h"
#include <ArduinoJson.h>
#include <AsyncJson.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <WiFi.h>
#include <cmath>
#include <cstring>

AsyncWebServer server(80);

namespace {

void serializeThresholds(JsonObject object, const SafetyThresholds &thresholds) {
  for (size_t index = 0; index < thresholds.values.size(); ++index) {
    const char *name = thresholdFieldName(static_cast<ThresholdField>(index));
    if (std::isfinite(thresholds.values[index]))
      object[name] = thresholds.values[index];
    else
      object[name] = nullptr;
  }
}

bool parseThresholdPatch(JsonObject object, ThresholdPatch &patch) {
  for (JsonPair entry : object) {
    size_t index = 0;
    for (; index < patch.values.values.size(); ++index) {
      if (strcmp(entry.key().c_str(),
                 thresholdFieldName(static_cast<ThresholdField>(index))) == 0)
        break;
    }
    if (index == patch.values.values.size())
      return false;
    JsonVariant value = entry.value();
    // Iterating supplied keys keeps an explicit null distinct from an absent key.
    if (value.is<bool>() || !value.is<double>())
      return false;
    patch.fields |= 1u << index;
    patch.values.values[index] = value.as<float>();
  }
  return true;
}

}

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
    if (!std::isfinite(current_temp_c) || current_temp_c < -40.0f ||
        current_temp_c > 80.0f)
      doc["temperature_c"] = nullptr;
    else
      doc["temperature_c"] = current_temp_c;
    if (!std::isfinite(current_humidity_percent) ||
        current_humidity_percent < 0.0f || current_humidity_percent > 100.0f)
      doc["humidity_percent"] = nullptr;
    else
      doc["humidity_percent"] = current_humidity_percent;
    if (!std::isfinite(current_chamber_c))
      doc["chamber_temp_c"] = nullptr;
    else
      doc["chamber_temp_c"] = current_chamber_c;
    if (!std::isfinite(current_mq135_v))
      doc["mq135_v"] = nullptr;
    else
      doc["mq135_v"] = current_mq135_v;
    if (!std::isfinite(current_mq2_v) || current_mq2_v > 4.8f)
      doc["mq2_v"] = nullptr;
    else
      doc["mq2_v"] = current_mq2_v;
    const uint32_t mq_warmup_remaining_seconds =
        mqWarmupRemainingSeconds(millis());
    doc["mq_warming_up"] = mqSensorsAreWarmingUp();
    doc["mq_warmup_remaining_seconds"] = mq_warmup_remaining_seconds;
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
    serializeThresholds(doc.as<JsonObject>(), safety_thresholds);
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

    ThresholdPatch patch{};
    if (!parseThresholdPatch(json.as<JsonObject>(), patch)) {
      AsyncWebServerResponse *response =
          request->beginResponse(400, "application/json",
                                 "{\"status\":\"error\",\"message\":"
                                 "\"Expected supported numeric thresholds\"}");
      return request->send(response);
    }

    SafetyThresholds accepted;
    const ThresholdUpdateResult result = applyThresholdUpdate(patch, &accepted);
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

    JsonDocument doc;
    doc["status"] = "ok";
    serializeThresholds(doc["thresholds"].to<JsonObject>(), accepted);
    AsyncResponseStream *response =
        request->beginResponseStream("application/json");
    serializeJson(doc, *response);
    request->send(response);
  };
  AsyncCallbackJsonWebHandler *thresholdHandler =
      new AsyncCallbackJsonWebHandler("/api/thresholds", handleThresholdUpdate);
  thresholdHandler->setMethod(HTTP_POST);
  thresholdHandler->setMaxContentLength(1024);
  server.addHandler(thresholdHandler);

  AsyncCallbackJsonWebHandler *settingsHandler =
      new AsyncCallbackJsonWebHandler("/api/settings", handleThresholdUpdate);
  settingsHandler->setMethod(HTTP_POST);
  settingsHandler->setMaxContentLength(1024);
  server.addHandler(settingsHandler);

  server.on("/api/settings", HTTP_GET,
            [send401](AsyncWebServerRequest *request) {
              if (!request->authenticate(API_USER, API_PASS))
                return send401(request);

              JsonDocument doc;
              if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5))) {
                serializeThresholds(doc.to<JsonObject>(), safety_thresholds);
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
