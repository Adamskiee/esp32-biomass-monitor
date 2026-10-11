#pragma once

#include <stdint.h>

constexpr uint32_t PMS_READING_FRESHNESS_MS = 10000;

struct PmsReading {
  uint16_t pm1_0_ug_m3;
  uint16_t pm2_5_ug_m3;
  uint16_t pm10_ug_m3;
};
