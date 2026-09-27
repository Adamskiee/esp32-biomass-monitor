#pragma once
#ifdef ARDUINO
#include <Arduino.h>
#else
#include <stdint.h>
#include <stdbool.h>
#define OUTPUT 1
#define INPUT 0
#define HIGH 1
#define LOW 0
uint32_t millis(void);
void pinMode(uint8_t pin, uint8_t mode);
void digitalWrite(uint8_t pin, uint8_t val);
#endif
#include <BiomassConfig.h>

#ifndef SOLENOID_PIN
#define SOLENOID_PIN PIN_RELAY_SOLENOID
#endif

extern bool current_solenoid_state;

void initActuators();
void initSolenoid();
void setFan(bool state);
void setSolenoid(bool state, bool force_bypass_debounce = false);
void setLedStatus(bool red, bool yellow, bool green);
void setBuzzer(bool state);

