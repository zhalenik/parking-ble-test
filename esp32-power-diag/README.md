# ESP32-C3 power diagnostic (7 x 45 s)

Original production firmware remains on main, commit 58bfa81. This is a standalone Arduino 2.0.17 test. It broadcasts a diagnostic-only nonconnectable payload; it cannot trigger the parking app.

Open esp32-power-diag in PlatformIO and upload. Disconnect USB and power through regulated 3.3 V with a current meter in series (or 5 V separately). Do not power from both simultaneously. Reset to start a run. The blue GPIO8 LED flashes the stage number at the start, then stays off. Each stage lasts 45 seconds including the flashes. Record steady current after 5 seconds, before the next stage.

| Stage | Setting |
|---|---|
| 1 | 160 MHz, radios off |
| 2 | 80 MHz, radios off |
| 3 | BLE 160 ms, 80 MHz, default controller |
| 4 | BLE 500 ms, 80 MHz |
| 5 | BLE 1000 ms, 80 MHz |
| 6 | BLE 1000 ms, request modem sleep |
| 7 | BLE 1000 ms, request automatic light sleep |

At the end stage 7 settings remain active; reset to repeat.

For diagnostics, use a separate USB/UART monitor run at 115200 baud. The serial output prints actual Arduino and IDF versions, compiled configuration flags and ESP-IDF API return codes. Stages 6 and 7 do NOT modify precompiled Arduino libraries; if marked UNSUPPORTED they are unchanged control measurements. A separately configured ESP-IDF build is then required to actually test those modes. Default controller may already have modem sleep enabled.

Commands from repository root: pio pkg list -d esp32-power-diag ; pio run -d esp32-power-diag ; pio run -d esp32-power-diag -t upload.

The USB serial/debug path itself can influence current, so measure without a USB cable. GPIO8 LED is active-low on the tested SuperMini variant.
