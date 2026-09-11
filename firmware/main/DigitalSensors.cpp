#include "DigitalSensors.h"
#include <BiomassConfig.h>
#include <DHT.h>
#include <max6675.h>

static DHT dht(PIN_DHT22, DHT22);
static MAX6675 thermocouple(PIN_MAX6675_SCK, PIN_MAX6675_CS, PIN_MAX6675_SO);

void initDigitalSensors() {
  dht.begin();
  Serial2.begin(9600, SERIAL_8N1, PIN_PM25_RX, PIN_PM25_TX);
}

float readTemperature() {
  return dht.readTemperature();
}

float readHumidity() {
  return dht.readHumidity();
}

float readThermocouple() {
  return thermocouple.readCelsius();
}

int readPM25() {
  // TODO: Implement real PM2.5 serial frame parsing
  // Dummy implementation for PM2.5 frame reading
  if (Serial2.available()) {
    while(Serial2.available()) Serial2.read(); // flush for now
    return 25; // mock value
  }
  return -1;
}
