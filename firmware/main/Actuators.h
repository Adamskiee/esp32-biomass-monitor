#pragma once
#ifdef ARDUINO
#include <Arduino.h>
#else
#include <stdbool.h>
#include <stdint.h>
#define OUTPUT 1
#define INPUT 0
#define HIGH 1
#define LOW 0
uint32_t millis(void);
void pinMode(uint8_t pin, uint8_t mode);
void digitalWrite(uint8_t pin, uint8_t val);
#endif
#include <BiomassConfig.h>

extern bool current_pump_state;

void initActuators();
void requestSprinkler(bool enabled);
void setLedStatus(bool red, bool yellow, bool green);
void setBuzzer(bool state);
