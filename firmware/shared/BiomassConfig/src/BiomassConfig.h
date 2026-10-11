#pragma once

// Relay Pins (Active LOW)
#define PIN_RELAY_SOLENOID 27
#define PIN_RELAY_PUMP 13
#define PIN_RELAY_BUZZER 4
#define PIN_RELAY_FAN 26
#define PIN_RELAY_LED_RED 25
#define PIN_RELAY_LED_YELLOW 33
#define PIN_RELAY_LED_GREEN 14

#define RELAY_ON LOW
#define RELAY_OFF HIGH

// Digital Sensors
#define PIN_DHT22 32
#define PIN_MAX6675_SCK 18
#define PIN_MAX6675_SO 19
#define PIN_MAX6675_CS 5

// PM2.5 Serial (Hardware Serial 2)
#define PIN_PM25_RX 16
#define PIN_PM25_TX 17

// Analog Sensors
#define PIN_MQ135 34
#define PIN_MQ2 35
#define V_DIVIDER_RATIO 0.6 // 15K / (10K + 15K)

// Timing and Safety Thresholds
#define POLL_INTERVAL_MS 2000
#define SPRINKLER_TRANSITION_MS 500UL

constexpr uint32_t MQ_STARTUP_WARMUP_MS = 300000;
constexpr float MQ_CIRCUIT_SUPPLY_V = 5.0f;

#ifndef MQ_RESPONSE_CIRCUIT_VERIFIED
#define MQ_RESPONSE_CIRCUIT_VERIFIED 0
#endif
