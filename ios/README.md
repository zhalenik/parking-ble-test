# Parking BLE Probe — iOS

Нативное диагностическое приложение на SwiftUI и Core Bluetooth для iPhone (iOS 16+).
Использует тот же BLE Service UUID, что ESP32-C3: c6ec1c8d-e23a-4751-93f8-31d4d4a17b10.

## Возможности

- Фоновое сканирование по BLE Service UUID с режимом bluetooth-central
- Core Bluetooth State Preservation and Restoration
- RSSI в активном приложении и события фонового обнаружения
- Журнал CSV с системным временем, uptime, состоянием приложения, RSSI
- Экспорт CSV через «Поделиться»
- Ручная временная отметка для полевых тестов

iOS может задерживать обнаружение, не отдавать дубликаты, а после принудительного закрытия приложения не возобновлять его. iOS не предоставляет аппаратную метку времени BLE-пакета в didDiscover. Этот прототип не отправляет данные на сервер и не открывает шлагбаум.

## Установка на iPhone через Xcode

1. Установите Xcode на Mac. Для генерации проекта из исходников: brew install xcodegen.
2. В папке ios выполните xcodegen generate и откройте ParkingBLEProbe.xcodeproj. Альтернатива: скачайте артефакт ParkingBLEProbe-iOS-Xcode-Project из GitHub Actions — там уже готов .xcodeproj.
3. Подключите iPhone к Mac. В Xcode Settings → Accounts добавьте Apple Account.
4. В Signing & Capabilities выберите Personal Team и включите Automatically manage signing.
5. Если потребуется, измените Bundle Identifier на уникальный.
6. Выберите iPhone в списке устройств Xcode и нажмите Run.
7. Если iPhone запросит Developer Mode, включите его и разрешите Bluetooth.
8. Запустите BLE-сканирование в приложении.

Бесплатный Apple Account подходит для личного тестирования (подпись обычно 7 дней). Для TestFlight необходим Apple Developer Program и настроенная подпись.

## GitHub Actions

Workflow Build iOS BLE Probe создаёт два артефакта:
- ParkingBLEProbe-iOS-Xcode-Project — исходники вместе со сгенерированным Xcode-проектом.
- ParkingBLEProbe-iOS-Simulator — неподписанная сборка только для iOS Simulator, не подходит для физического iPhone.

GitHub Actions не создаёт установочный IPA для физического iPhone без сертификата Apple и provisioning profile.

## Полевое испытание

1. Включите маяк ESP32-C3 и убедитесь, что приложение видит DISCOVER_FIRST.
2. Начните сканирование, отъедьте, заблокируйте телефон, вернитесь к маяку.
3. Ведите независимую запись момента пересечения расстояния 5 м, затем экспортируйте CSV.
4. Сопоставьте внешнее время подъезда с временем событий в CSV.
5. Повторяйте опыт многократно, отдельно испытывайте повторные въезды.

CSV: timestamp_utc,uptime_s,app_state,event,rssi_dbm,peripheral_id,details.

Важно: APP_BACKGROUND отмечает переход в фон, не периодический опрос BLE. IOS_STATE_RESTORED отмечает состояние CoreBluetooth, не гарантирует успешное обнаружение.
