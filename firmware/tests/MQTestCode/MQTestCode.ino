// --- ESP32 SPECIFIC SETTINGS FOR MQ-2 & MQ-135 ---
#include <BiomassConfig.h>
const float ADC_MAX = 4095.0;     // ESP32 has a 12-bit ADC (0 to 4095)
const float MCU_VOLTAGE = 3.3;    // ESP32 runs at 3.3V
// -------------------------------------------------

void setup() {
  Serial.begin(115200);

  Serial.println("=================================");
  Serial.println("   MQ-2 & MQ-135 Sensor Test     ");
  Serial.println("=================================");
  Serial.println("Note: Allow 1-2 minutes for the sensor heaters to warm up!");
  delay(2000);
}

void loop() {
  // --- MQ-2 Reading ---
  int mq2Raw = analogRead(PIN_MQ2);
  float mq2PinVolts = mq2Raw * (MCU_VOLTAGE / ADC_MAX);
  float mq2RealVolts = mq2PinVolts * 1.5; // Reversing 10k/20k divider

  Serial.print("MQ-2   -> Raw ADC: ");
  Serial.print(mq2Raw);
  Serial.print(" | Junction: ");
  Serial.print(mq2PinVolts);
  Serial.print(" V | REAL Sensor: ");
  Serial.print(mq2RealVolts);
  Serial.println(" V");

  // --- MQ-135 Reading ---
  int mq135Raw = analogRead(PIN_MQ135);
  float mq135PinVolts = mq135Raw * (MCU_VOLTAGE / ADC_MAX);
  float mq135RealVolts = mq135PinVolts * 1.5; // Reversing 10k/20k divider

  Serial.print("MQ-135 -> Raw ADC: ");
  Serial.print(mq135Raw);
  Serial.print(" | Junction: ");
  Serial.print(mq135PinVolts);
  Serial.print(" V | REAL Sensor: ");
  Serial.print(mq135RealVolts);
  Serial.println(" V");

  Serial.println("-------------------------------------------------");

  // Wait 2 seconds before reading again
  delay(2000);
}
