#include <BiomassConfig.h>

void setup() {
  Serial.begin(9600); // Start serial communication
  Serial.println("Starting Sensor Burn-in...");
  Serial.println("Reading values every 1 minute. Leave powered for 24-48 hours.");
  delay(3000); // Give it a few seconds before starting
}

void loop() {
  int mq2Value = analogRead(PIN_MQ2);     // Read the MQ-2 analog value
  int mq135Value = analogRead(PIN_MQ135); // Read the MQ-135 analog value
  
  Serial.print("MQ-2 (Smoke/Combustible): ");
  Serial.print(mq2Value);
  
  Serial.print("  |  MQ-135 (Air Quality/NH3/CO2): ");
  Serial.println(mq135Value);
  
  delay(1000); // Wait 1 minute before the next reading to avoid flooding the Serial Monitor
}
