#include <Arduino.h>
#include <WiFi.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLEAdvertising.h>

// ESP32-C3 SuperMini: blue built-in LED is GPIO8, active LOW.
// Test firmware: fixed IDs, no pairing, Wi-Fi off, moderate BLE TX power.
static constexpr uint8_t LED_GPIO = 8;
static constexpr uint16_t ADV_INTERVAL = 256; // 160 ms
static const char *DEVICE_NAME = "PARKING-GATT-01";
static const char *SERVICE_UUID = "c6ec1c8d-e23a-4751-93f8-31d4d4a17b10";
static const char *INFO_UUID = "c6ec1c8d-e23a-4751-93f8-31d4d4a17b11";
static const char *BEACON_ID = "gatt:parking-01";
static volatile bool connected = false;

class Callbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    connected = true;
  }
  void onDisconnect(BLEServer *) override {
    connected = false;
    BLEDevice::startAdvertising();
  }
};

void setup() {
  WiFi.mode(WIFI_OFF);
  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setPower(ESP_PWR_LVL_P0); // approx. 0 dBm, not maximum

  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new Callbacks());

  BLEService *svc = server->createService(SERVICE_UUID);
  BLECharacteristic *info = svc->createCharacteristic(INFO_UUID, BLECharacteristic::PROPERTY_READ);
  info->setValue(BEACON_ID);
  svc->start();

  BLEAdvertisementData data;
  data.setFlags(0x06);
  // 3 bytes flags + 18 bytes complete 128-bit service UUID = 21 bytes.
  // No device name or TX power in ADV. Mandatory for foreground/background
  // iOS scanning with [SERVICE_UUID] filter.
  data.setCompleteServices(BLEUUID(SERVICE_UUID));

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->setAdvertisementData(data);
  adv->setScanResponse(false);
  adv->setMinInterval(ADV_INTERVAL);
  adv->setMaxInterval(ADV_INTERVAL);
  adv->start();

  // Set strapping GPIO8 only after initializing BLE.
  pinMode(LED_GPIO, OUTPUT);
  digitalWrite(LED_GPIO, HIGH);
}

void loop() {
  // Slow heartbeat = searching, faster heartbeat = connected.
  // GPIO8 is active LOW on most ESP32-C3 SuperMini boards.
  const unsigned long now = millis();
  const unsigned long period = connected ? 650 : 2200;
  const unsigned long pulse = connected ? 110 : 80;
  digitalWrite(LED_GPIO, (now % period < pulse) ? LOW : HIGH);
  delay(25);
}
