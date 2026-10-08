#include "DigitalSensors.h"
#include <Adafruit_PM25AQI.h>
#include <BiomassConfig.h>
#include <DHT.h>
#include <max6675.h>

static DHT dht(PIN_DHT22, DHT22);
static MAX6675 thermocouple(PIN_MAX6675_SCK, PIN_MAX6675_CS, PIN_MAX6675_SO);
static Adafruit_PM25AQI *pms_sensor = nullptr;

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

bool readPmsReading(PmsReading &out) {
  if (pms_sensor == nullptr) {
    pms_sensor = new Adafruit_PM25AQI();
    if (pms_sensor == nullptr || !pms_sensor->begin_UART(&Serial2)) {
      delete pms_sensor;
      pms_sensor = nullptr;
      return false;
    }
  }

  PM25_AQI_Data data{};
  if (!pms_sensor->read(&data)) {
    return false;
  }

  out = {data.pm10_env, data.pm25_env, data.pm100_env};
  return true;
}
