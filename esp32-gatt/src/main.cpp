#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLEAdvertising.h>

// BLE GATT test peripheral: no pairing, no user credentials.
static const char *DEVICE_NAME = "PARKING-GATT-01";
static const char *SERVICE_UUID = "c6ec1c8d-e23a-4751-93f8-31d4d4a17b10";
static const char *INFO_UUID = "c6ec1c8d-e23a-4751-93f8-31d4d4a17b11";
static const char *BEACON_ID = "gatt:parking-01"; // stable ID sent to API
static const uint16_t ADV_INTERVAL = 256; // 160 ms

class Callbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {

  }
  void onDisconnect(BLEServer*) override {
    BLEDevice::startAdvertising();
  }
};

void setup() {
  delay(500);
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new Callbacks());

  BLEService *svc = server->createService(SERVICE_UUID);
  BLECharacteristic *info = svc->createCharacteristic(INFO_UUID, BLECharacteristic::PROPERTY_READ);
  info->setValue(BEACON_ID);
  svc->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  // Keep Service UUID in the primary ADV, not only in SCAN_RSP.
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(false);
  adv->setMinInterval(ADV_INTERVAL);
  adv->setMaxInterval(ADV_INTERVAL);
  adv->start();


}
void loop() { delay(3000); }
