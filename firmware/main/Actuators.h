#pragma once
#include <Arduino.h>

void initActuators();
void setFan(bool state);
void setSolenoid(bool state);
void setLedStatus(bool red, bool yellow, bool green);
