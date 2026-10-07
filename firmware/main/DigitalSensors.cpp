#include "DigitalSensors.h"
#include <Adafruit_PM25AQI.h>
#include <BiomassConfig.h>
#include <DHT.h>
#include <max6675.h>

static DHT dht(PIN_DHT22, DHT22);
static MAX6675 thermocouple(PIN_MAX6675_SCK, PIN_MAX6675_CS, PIN_MAX6675_SO);
static Adafruit_PM25AQI pms;
static bool pms_initialized = false;

void initDigitalSensors() {
  dht.begin();
  Serial2.begin(9600, SERIAL_8N1, PIN_PM25_RX, PIN_PM25_TX);
  pms_initialized = pms.begin_UART(&Serial2);
}

DigitalSensorReadings readDigitalSensors() {
  const float temperature_c = dht.readTemperature();
  const float humidity_percent = dht.readHumidity();
  DigitalSensorReadings readings = {NAN, NAN, thermocouple.readCelsius(), -1,
                                    -1, -1};

  if (isfinite(temperature_c) && isfinite(humidity_percent)) {
    readings.temperature_c = temperature_c;
    readings.humidity_percent = humidity_percent;
  }

  PM25_AQI_Data data;
  if (pms_initialized && pms.read(&data)) {
    readings.pm1_ug_m3 = data.pm10_env;
    readings.pm25_ug_m3 = data.pm25_env;
    readings.pm10_ug_m3 = data.pm100_env;
  }

  return readings;
}
