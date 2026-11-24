#include <Arduino.h>
#include <string>
#include <BLEDevice.h>
#include <BLEAdvertising.h>
#include <BLEUtils.h>

// TEST ONLY. This is a fixed iBeacon identifier, NOT an authorization secret.
// iOS CLBeaconRegion(uuid:..., major:1, minor:1) matches these bytes.
static const char *DEVICE_NAME = "PARKING-IBEACON-01";
static const uint8_t BEACON_UUID[16] = {
  0xF4,0x7D,0x8F,0x33,0x25,0xFA,0x4D,0xC8,
  0x92,0xCB,0x8B,0xE1,0x19,0x9A,0x64,0x10
};
static const uint16_t MAJOR = 1;
static const uint16_t MINOR = 1;
static const int8_t CALIBRATED_RSSI_AT_1M = -59;  // nominal, measure before deployment
static const uint16_t ADV_INTERVAL = 256;       // 256 * 0.625 ms = 160 ms

void setup() {
  delay(400);
  BLEDevice::init(DEVICE_NAME);

  // Manufacturer AD data: Apple (4C 00), type (02 15), UUID (16B),
  // Major (2B BE), Minor (2B BE), Measured power (1B).
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

  BLEAdvertisementData advData;
  advData.setFlags(0x06); // BR/EDR not supported + general discoverable
  // 3 bytes Flags + 2 bytes AD header + 25 bytes payload = 30 bytes, fits 31.
  advData.setManufacturerData(std::string((const char*)manufacturer, sizeof(manufacturer)));

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->setAdvertisementData(advData);
  adv->setScanResponse(false);
  adv->setMinInterval(ADV_INTERVAL);
  adv->setMaxInterval(ADV_INTERVAL);
  adv->start();



}

void loop() { delay(5000); }
