#include <Arduino.h>
#include <WiFi.h>
#include <string>
#include <BLEDevice.h>
#include <BLEAdvertising.h>
#include <BLEUtils.h>

// ESP32-C3 SuperMini fixed iBeacon test advertisement.
// Wi-Fi off, moderate BLE TX power, onboard blue LED heartbeat (GPIO8).
static constexpr uint8_t LED_GPIO = 8;
static const char *DEVICE_NAME = "PARKING-IBEACON-01";
static const uint8_t BEACON_UUID[16] = {
  0xF4,0x7D,0x8F,0x33,0x25,0xFA,0x4D,0xC8,
  0x92,0xCB,0x8B,0xE1,0x19,0x9A,0x64,0x10
};
static const uint16_t MAJOR = 1;
static const uint16_t MINOR = 1;
static const int8_t CALIBRATED_RSSI_AT_1M = -59; // example, not yet calibrated
static const uint16_t ADV_INTERVAL = 256; // 160 ms

void setup() {
  WiFi.mode(WIFI_OFF);
  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setPower(ESP_PWR_LVL_N0); // approx. 0 dBm, not maximum

  // 25-byte manufacturer data:
  // Apple company ID (4C 00), iBeacon marker (02 15), 16-byte UUID,
  // Major (big-endian), Minor (big-endian), reference RSSI.
  uint8_t manufacturer[25] = {
    0x4C,0x00, 0x02,0x15,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0, (uint8_t)CALIBRATED_RSSI_AT_1M
  };
  memcpy(&manufacturer[4], BEACON_UUID, sizeof(BEACON_UUID));
  manufacturer[20] = MAJOR >> 8;
  manufacturer[21] = MAJOR & 0xFF;
  manufacturer[22] = MINOR >> 8;
  manufacturer[23] = MINOR & 0xFF;

  BLEAdvertisementData data;
  data.setFlags(0x06);
  // 3 bytes flags + (2 byte AD header + 25 manufacturer data) = 30 bytes.
  data.setManufacturerData(std::string((const char*)manufacturer, sizeof(manufacturer)));

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->setAdvertisementData(data);
  adv->setScanResponse(false);
  adv->setMinInterval(ADV_INTERVAL);
  adv->setMaxInterval(ADV_INTERVAL);
  adv->start();

  pinMode(LED_GPIO, OUTPUT);
  digitalWrite(LED_GPIO, HIGH);
}

void loop() {
  // Brief heartbeat every 2.2 s indicates firmware continues to run.
  digitalWrite(LED_GPIO, millis() % 2200 < 80 ? LOW : HIGH);
  delay(25);
}
