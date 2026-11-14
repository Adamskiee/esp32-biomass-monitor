#pragma once
#ifdef ARDUINO
#include <Arduino.h>
#else
#include <stdint.h>
#ifndef INPUT
#define INPUT 0
#endif
typedef enum {
  ADC_0db = 0,
  ADC_2_5db = 1,
  ADC_6db = 2,
  ADC_11db = 3,
} adc_attenuation_t;
void pinMode(uint8_t pin, uint8_t mode);
void analogReadResolution(uint8_t bits);
void analogSetPinAttenuation(uint8_t pin, adc_attenuation_t attenuation);
uint32_t analogReadMilliVolts(uint8_t pin);
#endif

void initAnalogSensors();
float readMQ135Voltage();
float readMQ2Voltage();
