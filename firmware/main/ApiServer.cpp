#include "ApiServer.h"
#include <WiFi.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>
#include "SystemState.h"
#include "Actuators.h"
#include "Secrets.h"

AsyncWebServer server(80);

void initApiServer() {
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    
    WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info){
        Serial.print("WiFi connected! API IP address: ");
        Serial.println(WiFi.localIP());
    }, WiFiEvent_t::ARDUINO_EVENT_WIFI_STA_GOT_IP);
    
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, X-ESP32-Biomass");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Credentials", "true");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");

    auto addCorsOrigin = [](AsyncWebServerRequest *request, AsyncWebServerResponse *response) {
        String origin = request->hasHeader("Origin") ? request->header("Origin") : "*";
        response->addHeader("Access-Control-Allow-Origin", origin);
        return response;
    };
    
    auto send401 = [addCorsOrigin](AsyncWebServerRequest *request) {
        AsyncWebServerResponse *response = request->beginResponse(401, "text/plain", "Unauthorized");
        response->addHeader("WWW-Authenticate", "Basic realm=\"Login Required\"");
        request->send(addCorsOrigin(request, response));
    };
    
    server.on("/api/state", HTTP_GET, [addCorsOrigin](AsyncWebServerRequest *request){
        xSemaphoreTake(stateMutex, portMAX_DELAY);
        String json = "{";
        json += "\"chamber_temp\":" + (isnan(current_chamber_c) ? String("null") : String(current_chamber_c)) + ",";
        json += "\"mq2_v\":" + (isnan(current_mq2_v) ? String("null") : String(current_mq2_v)) + ",";
        json += "\"safe_chamber_limit\":" + String(threshold_chamber_temp_c) + ",";
        json += "\"safe_mq2_limit\":" + String(threshold_mq2_v) + ",";
        json += "\"fan_on\":true,";
        json += "\"sprinkler_on\":" + String(current_solenoid_state ? "true" : "false") + ",";
        json += "\"manual_sprinkler\":" + String(manual_sprinkler ? "true" : "false") + ",";
        json += "\"active_triggers\":" + active_triggers_json;
        json += "}";
        xSemaphoreGive(stateMutex);
        AsyncWebServerResponse *response = request->beginResponse(200, "application/json", json);
        request->send(addCorsOrigin(request, response));
    });

    AsyncCallbackJsonWebHandler* controlHandler = new AsyncCallbackJsonWebHandler("/api/control", [addCorsOrigin](AsyncWebServerRequest *request, JsonVariant &json) {
        if (!request->hasHeader("X-ESP32-Biomass")) {
            AsyncWebServerResponse *response = request->beginResponse(403);
            request->send(addCorsOrigin(request, response));
            return;
        }
        JsonObject jsonObj = json.as<JsonObject>();
        if (jsonObj.containsKey("sprinkler")) {
            xSemaphoreTake(stateMutex, portMAX_DELAY);
            manual_sprinkler = jsonObj["sprinkler"];
            catastrophic_latch = false;
            setSolenoid(manual_sprinkler, true); // Force bypass debounce on API command
            xSemaphoreGive(stateMutex);
        }
        AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
        request->send(addCorsOrigin(request, response));
    });
    controlHandler->setMethod(HTTP_POST);
    server.addHandler(controlHandler);

    AsyncCallbackJsonWebHandler* thresholdHandler = new AsyncCallbackJsonWebHandler("/api/thresholds", [addCorsOrigin](AsyncWebServerRequest *request, JsonVariant &json) {
        if (!request->hasHeader("X-ESP32-Biomass")) {
            AsyncWebServerResponse *response = request->beginResponse(403);
            request->send(addCorsOrigin(request, response));
            return;
        }
        JsonObject jsonObj = json.as<JsonObject>();
        xSemaphoreTake(stateMutex, portMAX_DELAY);
        bool changed = false;
        if (jsonObj.containsKey("safe_chamber_limit")) {
            float val = jsonObj["safe_chamber_limit"];
            if (val >= 0 && val <= 1000 && threshold_chamber_temp_c != val) {
                threshold_chamber_temp_c = val;
                changed = true;
            }
        }
        if (jsonObj.containsKey("safe_mq2_limit")) {
            float val = jsonObj["safe_mq2_limit"];
            if (val >= 0 && val <= 5.0 && threshold_mq2_v != val) {
                threshold_mq2_v = val;
                changed = true;
            }
        }
        if (changed) state_needs_save = true;
        xSemaphoreGive(stateMutex);
        AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"ok\"}");
        request->send(addCorsOrigin(request, response));
    });
    thresholdHandler->setMethod(HTTP_POST);
    server.addHandler(thresholdHandler);

    server.on("/api/settings", HTTP_GET, [addCorsOrigin, send401](AsyncWebServerRequest *request){
        if(!request->authenticate(API_USER, API_PASS)) return send401(request);
        
        JsonDocument doc;
        if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5))) {
            doc["threshold_chamber_temp_c"] = threshold_chamber_temp_c;
            doc["threshold_mq2_v"] = threshold_mq2_v;
            xSemaphoreGive(stateMutex);
            
            AsyncResponseStream *response = request->beginResponseStream("application/json");
            serializeJson(doc, *response);
            request->send(addCorsOrigin(request, response));
        } else {
            AsyncWebServerResponse *response = request->beginResponse(503, "application/json", "{\"status\":\"error\",\"message\":\"Server busy\"}");
            request->send(addCorsOrigin(request, response));
        }
    });

    // Use raw body callback to handle JSON POST safely with ArduinoJson v7
    server.on("/api/settings", HTTP_POST, 
        [addCorsOrigin, send401](AsyncWebServerRequest *request) {
            if(!request->authenticate(API_USER, API_PASS)) return send401(request);
            
            if (request->contentLength() == 0) {
                AsyncWebServerResponse *response = request->beginResponse(400, "application/json", "{\"status\":\"error\",\"message\":\"Empty payload\"}");
                return request->send(addCorsOrigin(request, response));
            }
            
            int status = (int)(intptr_t)request->_tempObject;
            if (status == 1) {
                AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"success\"}");
                request->send(addCorsOrigin(request, response));
            } else if (status == 3) {
                AsyncWebServerResponse *response = request->beginResponse(503, "application/json", "{\"status\":\"error\",\"message\":\"Server busy\"}");
                request->send(addCorsOrigin(request, response));
            } else {
                AsyncWebServerResponse *response = request->beginResponse(400, "application/json", "{\"status\":\"error\",\"message\":\"Invalid JSON, Payload Exceeds 256 bytes, or Invalid Values\"}");
                request->send(addCorsOrigin(request, response));
            }
        }, 
        NULL, 
        [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
            // PREVENT AUTHENTICATION BYPASS:
            if(!request->authenticate(API_USER, API_PASS)) return;
            
            // Limit payload size to prevent DoS
            if (total > 256) return;
            
            // Reject fragmented payloads for simplicity
            if (index != 0 || len != total) {
                return;
            }
            
            JsonDocument doc;
            DeserializationError error = deserializeJson(doc, (const char*)data, len);
            
            request->_tempObject = (void*)(intptr_t)(!error ? 1 : 2);

            if (!error) {
                if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(5))) {
                    bool invalid_value = false;
                    bool has_chamber_temp = doc.containsKey("threshold_chamber_temp_c");
                    float new_chamber_temp = threshold_chamber_temp_c;
                    
                    if (has_chamber_temp) {
                        float val = doc["threshold_chamber_temp_c"].as<float>();
                        if (val >= 20.0 && val <= 150.0) {
                            new_chamber_temp = val;
                        } else {
                            invalid_value = true;
                        }
                    }
                    
                    bool has_mq2 = doc.containsKey("threshold_mq2_v");
                    float new_mq2 = threshold_mq2_v;
                    
                    if (has_mq2) {
                        float val = doc["threshold_mq2_v"].as<float>();
                        if (val >= 0.1 && val <= 5.0) {
                            new_mq2 = val;
                        } else {
                            invalid_value = true;
                        }
                    }
                    
                    if (!invalid_value) {
                        bool changed = false;
                        if (has_chamber_temp && threshold_chamber_temp_c != new_chamber_temp) {
                            threshold_chamber_temp_c = new_chamber_temp;
                            changed = true;
                        }
                        if (has_mq2 && threshold_mq2_v != new_mq2) {
                            threshold_mq2_v = new_mq2;
                            changed = true;
                        }
                        if (changed) state_needs_save = true;
                    }
                    
                    xSemaphoreGive(stateMutex);
                    request->_tempObject = (void*)(intptr_t)(invalid_value ? 2 : 1);
                } else {
                    request->_tempObject = (void*)(intptr_t)3; // Flag as failure if we couldn't get the lock
                }
            }
        }
    );

    server.onNotFound([addCorsOrigin](AsyncWebServerRequest *request){
        if (request->method() == HTTP_OPTIONS) {
            AsyncWebServerResponse *response = request->beginResponse(200);
            request->send(addCorsOrigin(request, response));
        } else {
            AsyncWebServerResponse *response = request->beginResponse(404, "text/plain", "Not Found");
            request->send(addCorsOrigin(request, response));
        }
    });

    server.begin();
}
