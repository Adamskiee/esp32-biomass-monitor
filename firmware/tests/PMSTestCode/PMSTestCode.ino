#include "Adafruit_PM25AQI.h"

// We use HardwareSerial2 for the ESP32
HardwareSerial pmsSerial(2); 

// Create the sensor object
Adafruit_PM25AQI aqi = Adafruit_PM25AQI();

void setup() {
  // Start the serial monitor for output
  Serial.begin(115200);
  while (!Serial) delay(10);
  
  Serial.println("ESP32 + PMS5003 Test");

  // Start Serial2 for PMS5003 communication.
  // PMS5003 baud rate is exactly 9600.
  // RX pin = 16, TX pin = 17
  pmsSerial.begin(9600, SERIAL_8N1, 16, 17);
  
  // Initialize the sensor
  if (!aqi.begin_UART(&pmsSerial)) {
    Serial.println("Could not find PMS5003 sensor! Check wiring.");
    while (1) {
      delay(10); // Halt execution if sensor is not found
    }
  }

  Serial.println("PMS5003 found!");
}

void loop() {
  PM25_AQI_Data data;
  
  // Attempt to read data from the sensor
  if (!aqi.read(&data)) {
    Serial.println("Could not read from PMS5003. Trying again...");
    delay(500);
    return;
  }
  
  // Print the results to the Serial Monitor
  Serial.println("\n---------------------------------------");
  Serial.println("Concentration Units (Standard)");
  Serial.println("---------------------------------------");
  Serial.printf("PM 1.0: %d \t PM 2.5: %d \t PM 10: %d \n", 
                data.pm10_standard, data.pm25_standard, data.pm100_standard);
                
  Serial.println("---------------------------------------");
  Serial.println("Concentration Units (Environmental)");
  Serial.println("---------------------------------------");
  Serial.printf("PM 1.0: %d \t PM 2.5: %d \t PM 10: %d \n", 
                data.pm10_env, data.pm25_env, data.pm100_env);
                
  Serial.println("---------------------------------------");
  Serial.printf("Particles > 0.3um / 0.1L air: %d\n", data.particles_03um);
  Serial.printf("Particles > 0.5um / 0.1L air: %d\n", data.particles_05um);
  Serial.printf("Particles > 1.0um / 0.1L air: %d\n", data.particles_10um);
  Serial.printf("Particles > 2.5um / 0.1L air: %d\n", data.particles_25um);
  Serial.printf("Particles > 5.0um / 0.1L air: %d\n", data.particles_50um);
  Serial.printf("Particles > 10 um / 0.1L air: %d\n", data.particles_100um);
  Serial.println("---------------------------------------");
  
  delay(2000); // Wait 2 seconds before the next reading
}
