#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLEAdvertising.h>
#include "config.h"
class RestartAdvertising : public BLEServerCallbacks {
  void onDisconnect(BLEServer* server) override { BLEDevice::startAdvertising(); }
};
void setup() {
  Serial.begin(115200);
  delay(700);
  BLEDevice::init(PARKING_DEVICE_NAME);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new RestartAdvertising());
  BLEService* service = server->createService(PARKING_SERVICE_UUID);
  BLECharacteristic* info = service->createCharacteristic(
      PARKING_INFO_CHAR_UUID, BLECharacteristic::PROPERTY_READ);
  info->setValue("ParkingBLE test beacon v1");
  service->start();
  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(PARKING_SERVICE_UUID);
  advertising->setMinInterval(PARKING_ADV_INTERVAL_UNITS);
  advertising->setMaxInterval(PARKING_ADV_INTERVAL_UNITS);
  advertising->setScanResponse(true);
  advertising->start();
  Serial.println("ParkingBLE advertising started");
  Serial.println(PARKING_SERVICE_UUID);
}
void loop() { delay(1000); }
