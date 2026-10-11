#include "MqConfigStore.h"

namespace {

constexpr uint32_t SETTINGS_WRITE_COOLDOWN_MS = 60000;
uint32_t last_settings_write_ms = 0;
bool has_settings_write = false;

} // namespace

bool canWriteSettings(uint32_t now_ms) {
  return !has_settings_write || now_ms - last_settings_write_ms >= SETTINGS_WRITE_COOLDOWN_MS;
}

void recordSettingsWrite(uint32_t now_ms) {
  last_settings_write_ms = now_ms;
  has_settings_write = true;
}

void resetSettingsWriteCoordinator() {
  last_settings_write_ms = 0;
  has_settings_write = false;
}

#ifdef ARDUINO
#include <Preferences.h>

namespace {

constexpr const char *MQ_CONFIG_NAMESPACE = "biomass";
constexpr const char *MQ_CONFIG_KEY = "mq_config";

class PreferencesMqConfigStore final : public MqConfigStore {
public:
  bool load(MqConfiguration &configuration) override {
    Preferences preferences;
    if (!preferences.begin(MQ_CONFIG_NAMESPACE, true)) {
      return false;
    }
    const size_t length = preferences.getBytesLength(MQ_CONFIG_KEY);
    const bool loaded =
        length == sizeof(configuration) &&
        preferences.getBytes(MQ_CONFIG_KEY, &configuration, sizeof(configuration)) ==
            sizeof(configuration) &&
        configuration.version == 1;
    preferences.end();
    return loaded;
  }

  bool save(const MqConfiguration &configuration) override {
    Preferences preferences;
    if (!preferences.begin(MQ_CONFIG_NAMESPACE, false)) {
      return false;
    }
    const bool saved =
        preferences.putBytes(MQ_CONFIG_KEY, &configuration, sizeof(configuration)) ==
        sizeof(configuration);
    preferences.end();
    return saved;
  }
};

PreferencesMqConfigStore store;

} // namespace

void initMqConfigStore() {}
MqConfigStore *defaultMqConfigStore() { return &store; }
#else
void initMqConfigStore() {}
MqConfigStore *defaultMqConfigStore() { return nullptr; }
#endif
