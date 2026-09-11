#include <ArduinoJson.h>
#include <Arduino.h>
#include <WiFi.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>

// Include the actual secrets file from the main firmware directory
// (This ensures your real passwords are used for the test, but never committed since Secrets.h is gitignored)
#include "../../main/Secrets.h"

AsyncWebServer server(80);

void setup() {
  Serial.begin(115200);
  
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("WiFi connected! API IP address: ");
  Serial.println(WiFi.localIP());

  // Global CORS Headers correctly applied to ALL responses via DefaultHeaders
  DefaultHeaders::Instance().addHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
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
      // IMPORTANT: send401 must include the Origin reflection header
      request->send(addCorsOrigin(request, response));
  };

  server.on("/api/state", HTTP_GET, [addCorsOrigin, send401](AsyncWebServerRequest *request){
      Serial.println("GET /api/state requested");
      
      if(!request->authenticate(API_USER, API_PASS)) return send401(request);
      
      JsonDocument doc;
      doc["temperature_c"] = 25.4;
      doc["chamber_temp_c"] = nullptr; // Mocking disconnected sensor behavior
      doc["mq135_v"] = 1.25;
      doc["mq2_v"] = 0.85;
      
      AsyncResponseStream *response = request->beginResponseStream("application/json");
      serializeJson(doc, *response);
      request->send(addCorsOrigin(request, response));
  });

  server.on("/api/settings", HTTP_GET, [addCorsOrigin, send401](AsyncWebServerRequest *request){
      Serial.println("GET /api/settings requested");
      if(!request->authenticate(API_USER, API_PASS)) return send401(request);
      
      JsonDocument doc;
      doc["threshold_chamber_temp_c"] = 60.0;
      doc["threshold_mq2_v"] = 1.5;
      
      AsyncResponseStream *response = request->beginResponseStream("application/json");
      serializeJson(doc, *response);
      request->send(addCorsOrigin(request, response));
  });

  server.on("/api/settings", HTTP_POST, 
      [addCorsOrigin, send401](AsyncWebServerRequest *request) {
          Serial.println("POST /api/settings request received");
          if(!request->authenticate(API_USER, API_PASS)) return send401(request);
          
          if (request->contentLength() == 0) {
              AsyncWebServerResponse *response = request->beginResponse(400, "application/json", "{\"status\":\"error\",\"message\":\"Empty payload\"}");
              return request->send(addCorsOrigin(request, response));
          }
          
          int status = (int)(intptr_t)request->_tempObject;
          if (status == 1) {
              AsyncWebServerResponse *response = request->beginResponse(200, "application/json", "{\"status\":\"success\"}");
              request->send(addCorsOrigin(request, response));
          } else {
              AsyncWebServerResponse *response = request->beginResponse(400, "application/json", "{\"status\":\"error\",\"message\":\"Invalid JSON or Values\"}");
              request->send(addCorsOrigin(request, response));
          }
      }, 
      NULL, 
      [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
          if(!request->authenticate(API_USER, API_PASS)) return;
          if (total > 256 || index != 0 || len != total) return;
          
          JsonDocument doc;
          DeserializationError error = deserializeJson(doc, (const char*)data, len);
          request->_tempObject = (void*)(intptr_t)(!error ? 1 : 2);
          
          if (!error) {
              bool invalid = false;
              if (doc.containsKey("threshold_chamber_temp_c")) {
                  float val = doc["threshold_chamber_temp_c"].as<float>();
                  if (val < 20.0 || val > 150.0) invalid = true;
              }
              if (doc.containsKey("threshold_mq2_v")) {
                  float val = doc["threshold_mq2_v"].as<float>();
                  if (val < 0.1 || val > 5.0) invalid = true;
              }
              request->_tempObject = (void*)(intptr_t)(invalid ? 2 : 1);
          }
      }
  );

  // Preflight handler
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

void loop() {
  // AsyncWebServer handles requests asynchronously
  delay(10);
}
