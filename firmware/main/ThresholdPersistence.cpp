#include "ThresholdPersistence.h"

void ThresholdPersistence::markChanged() { ++generation_; }

bool ThresholdPersistence::beginSave(uint32_t now_ms,
                                     const SafetyThresholds &current,
                                     SafetyThresholds &snapshot) {
  if (saving_ || generation_ == saved_generation_ ||
      (has_attempted_ &&
       static_cast<uint32_t>(now_ms - last_attempt_ms_) < 60000)) {
    return false;
  }
  snapshot = current;
  saving_generation_ = generation_;
  saving_ = true;
  has_attempted_ = true;
  last_attempt_ms_ = now_ms;
  return true;
}

void ThresholdPersistence::finishSave(bool succeeded) {
  if (!saving_) {
    return;
  }
  if (succeeded) {
    saved_generation_ = saving_generation_;
  }
  saving_ = false;
}
