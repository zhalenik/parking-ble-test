# Parking BLE Test — ESP32-C3, Android, iPhone

Тестовый BLE-пропуск на базе **ESP32-C3 SuperMini**. Оба диагностических приложения обнаруживают одну и ту же BLE-службу:

**Service UUID:** c6ec1c8d-e23a-4751-93f8-31d4d4a17b10

## Проекты

- **ESP32-C3**: исходники прошивки в папке [esp32](esp32), открываются в PlatformIO. Advertising интервал 160 мс.
- **Android**: папка [app](app), исходники Java/Gradle. GitHub Actions [Build Android test APK](../../actions/workflows/build-apk.yml) выдаёт устанавливаемый debug APK.
- **iOS / iPhone**: папка [ios](ios). SwiftUI + Core Bluetooth, background mode bluetooth-central, state restoration, RSSI и журнал CSV. GitHub Actions [Build iOS BLE Probe](../../actions/workflows/build-ios.yml) выдаёт сгенерированный Xcode-проект и пакет для iOS Simulator.

## Установка на iPhone

Скачайте артефакт **ParkingBLEProbe-iOS-Xcode-Project** из последнего успешного Actions запуска. Откройте ParkingBLEProbe.xcodeproj на Mac в Xcode, настройте Automatically manage signing, выберите свой Apple Account (Personal Team), подключённый iPhone и нажмите Run. Для личного тестирования достаточно бесплатного Apple Account.

**Примечание:** подписанный IPA для установки на физический iPhone не создаётся на GitHub без сертификата и provisioning profile. Пакет iOS Simulator не устанавливается на настоящий iPhone.

Подробная инструкция: [ios/README.md](ios/README.md).

## Полевые испытания

1. Прошейте ESP32-C3 и подайте питание.
2. На телефоне включите BLE сканирование, проверьте получение сигнала.
3. Заблокируйте экран, отойдите или отъедьте, затем вернитесь.
4. Сопоставьте внешнюю отметку времени с журналом событий.
5. Экспортируйте CSV для оценки задержек и случаев пропуска.

**Ограничения:** RSSI не равно расстоянию; мобильные ОС не гарантируют моментального обнаружения в фоне. Ни одна из тестовых версий не управляет шлагбаумом и не обменивается данными с сервером.
