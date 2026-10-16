#pragma once

#include "SafetyThresholds.h"

// Callers hold stateMutex for every scheduler operation, including completion.
class ThresholdPersistence {
public:
  void markChanged();
  bool beginSave(uint32_t now_ms, const SafetyThresholds &current,
                 SafetyThresholds &snapshot);
  void finishSave(bool succeeded);

private:
  uint64_t generation_ = 0;
  uint64_t saved_generation_ = 0;
  uint64_t saving_generation_ = 0;
  uint32_t last_attempt_ms_ = 0;
  bool has_attempted_ = false;
  bool saving_ = false;
};
