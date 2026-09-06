const int mq2Pin = A0;   // The analog pin the MQ-2 is connected to
const int mq135Pin = A1; // The analog pin the MQ-135 is connected to

void setup() {
  Serial.begin(9600); // Start serial communication
  Serial.println("Sensors Warming Up...");
  delay(3000); // Give it a few seconds before starting
}

void loop() {
  int mq2Value = analogRead(mq2Pin);     // Read the MQ-2 analog value
  int mq135Value = analogRead(mq135Pin); // Read the MQ-135 analog value
  
  Serial.print("MQ-2 (Smoke/Combustible): ");
  Serial.print(mq2Value);
  
  Serial.print("  |  MQ-135 (Air Quality/NH3/CO2): ");
  Serial.println(mq135Value);
  
  delay(1000); // Wait 1 second before the next reading
}
