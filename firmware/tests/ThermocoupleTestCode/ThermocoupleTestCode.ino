#include <Arduino.h>
#include <max6675.h>

const int PIN_MAX6675_SCK = 18;
const int PIN_MAX6675_SO = 19;
const int PIN_MAX6675_CS = 5;

// Constructor MUST be in this exact order: (SCK, CS, MISO)
MAX6675 thermocouple(PIN_MAX6675_SCK, PIN_MAX6675_CS, PIN_MAX6675_SO);

void setup() {
  Serial.begin(115200);
  Serial.println("Thermocouple Test Started");
  delay(500);
}

void loop() {
  float tempC = thermocouple.readCelsius();
  
  Serial.print("Temperature: ");
  if (isnan(tempC)) {
    Serial.println("Error reading thermocouple!");
  } else {
    Serial.print(tempC);
    Serial.println(" *C");
  }
  
  // 2s delay matching main firmware polling interval
  delay(2000); 
}
