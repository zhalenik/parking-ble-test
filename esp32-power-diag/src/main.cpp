#include <Arduino.h>
#include <WiFi.h>
#include <BLEDevice.h>
#include <BLEAdvertising.h>
#include <BLEUtils.h>
#include <esp_bt.h>
#include <esp_gap_ble_api.h>
#include <esp_pm.h>
#include <esp_system.h>
#include <esp_arduino_version.h>
#include <sdkconfig.h>

static constexpr uint8_t LED = 8;
static constexpr uint32_t STAGE_MS = 45000;
static constexpr uint8_t STAGE_COUNT = 7;
static BLEAdvertising *adv = nullptr;
static bool bleStarted = false;
static bool advertising = false;
static uint8_t stage = 0;
static uint32_t stageStart = 0;
static const char *labels[] = {
  "CPU 160 MHz, radios off",
  "CPU 80 MHz, radios off",
  "BLE 160 ms, 80 MHz, default controller",
  "BLE 500 ms, 80 MHz, default controller",
  "BLE 1000 ms, 80 MHz, default controller",
  "BLE 1000 ms, request modem sleep",
  "BLE 1000 ms, request automatic light sleep"
};

static void printResult(const char *what, esp_err_t err) {
  Serial.printf("%s: %s (0x%x)\n", what, esp_err_to_name(err), (unsigned)err);
}
static void startAdv(uint16_t interval) {
  if (!bleStarted) {
    BLEDevice::init("POWER-DIAG");
    bleStarted = true;
    printResult("TX advertising 0 dBm", esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_ADV, ESP_PWR_LVL_N0));
    adv = BLEDevice::getAdvertising();
    BLEAdvertisementData data;
    data.setFlags(0x06);
    // Unique diagnostic payload; no parking service or iBeacon UUID.
    data.setManufacturerData(std::string("\xff\xffPOWERDIAG", 11));
    adv->setAdvertisementData(data);
    adv->setScanResponse(false);
    adv->setAdvertisementType(ADV_TYPE_NONCONN_IND);
  }
  if (advertising) {
    adv->stop();
    delay(250);
  }
  adv->setMinInterval(interval);
  adv->setMaxInterval(interval);
  adv->start();
  advertising = true;
}
static void beginStage(uint8_t n) {
  stage = n;
  stageStart = millis();
  Serial.printf("\nSTAGE %u/%u: %s | t=%lu ms\n", n, STAGE_COUNT, labels[n-1], (unsigned long)stageStart);
  switch (n) {
    case 1: setCpuFrequencyMhz(160); break;
    case 2: setCpuFrequencyMhz(80); break;
    case 3: startAdv(256); break;
    case 4: startAdv(800); break;
    case 5: startAdv(1600); break;
    case 6:
#if defined(CONFIG_BT_CTRL_MODEM_SLEEP) && CONFIG_BT_CTRL_MODEM_SLEEP
      printResult("esp_bt_sleep_enable", esp_bt_sleep_enable());
#else
      Serial.println("UNSUPPORTED: controller modem sleep not compiled; unchanged from stage 5");
#endif
      break;
    case 7:
#if defined(CONFIG_PM_ENABLE) && CONFIG_PM_ENABLE && defined(CONFIG_FREERTOS_USE_TICKLESS_IDLE) && CONFIG_FREERTOS_USE_TICKLESS_IDLE
      {
        esp_pm_config_esp32c3_t cfg = {};
        cfg.max_freq_mhz = 80;
        cfg.min_freq_mhz = 40;
        cfg.light_sleep_enable = true;
        printResult("esp_pm_configure", esp_pm_configure(&cfg));
      }
#else
      Serial.println("UNSUPPORTED: PM or tickless idle not compiled; unchanged from stage 6");
#endif
      break;
  }
  Serial.printf("CPU=%u MHz, heap=%u bytes\n", getCpuFrequencyMhz(), ESP.getFreeHeap());
  // Stage number in short flashes. LED off for the remaining measurement window.
  for (uint8_t i=0; i<n; ++i) {
    digitalWrite(LED, LOW); delay(100);
    digitalWrite(LED, HIGH); delay(200);
  }
  Serial.println("Measure now; no further logging during this stage.");
  Serial.flush();
}
void setup() {
  pinMode(LED, OUTPUT);
  digitalWrite(LED, HIGH);
  Serial.begin(115200);
  delay(1000);
  WiFi.mode(WIFI_OFF);
  Serial.printf("Arduino=%d.%d.%d IDF=%s\n", ESP_ARDUINO_VERSION_MAJOR, ESP_ARDUINO_VERSION_MINOR, ESP_ARDUINO_VERSION_PATCH, esp_get_idf_version());
#if defined(CONFIG_BT_CTRL_MODEM_SLEEP) && CONFIG_BT_CTRL_MODEM_SLEEP
  Serial.println("CONFIG_BT_CTRL_MODEM_SLEEP=1");
#else
  Serial.println("CONFIG_BT_CTRL_MODEM_SLEEP=0");
#endif
#if defined(CONFIG_PM_ENABLE) && CONFIG_PM_ENABLE
  Serial.println("CONFIG_PM_ENABLE=1");
#else
  Serial.println("CONFIG_PM_ENABLE=0");
#endif
#if defined(CONFIG_FREERTOS_USE_TICKLESS_IDLE) && CONFIG_FREERTOS_USE_TICKLESS_IDLE
  Serial.println("CONFIG_FREERTOS_USE_TICKLESS_IDLE=1");
#else
  Serial.println("CONFIG_FREERTOS_USE_TICKLESS_IDLE=0");
#endif
  Serial.println("Power diagnostic: 7 x 45 s; reset to repeat.");
  beginStage(1);
}
void loop() {
  if (stage <= STAGE_COUNT && millis() - stageStart >= STAGE_MS) {
    if (stage < STAGE_COUNT) {
      beginStage(stage + 1);
    } else {
      Serial.println("DONE. Last settings remain active. Reset to repeat.");
      Serial.flush();
      stage = STAGE_COUNT + 1;
    }
  }
  // Long blocking delay, no heartbeat or USB log traffic in the measurement window.
  delay(250);
}
