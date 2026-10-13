# ESP32: push when a pin goes HIGH

`iotpush_alert/iotpush_alert.ino` connects to Wi-Fi and sends a JSON push to your
iotPush topic when a GPIO input goes HIGH: a door contact, a float switch, a PIR
sensor output, a button.

- Debounced (50 ms) and rate-limited to one push per 60 s (both configurable).
- HTTPS is verified against the ISRG Root X1 certificate embedded in the sketch
  via `WiFiClientSecure::setCACert`. It does not call `setInsecure()`.

## Requirements

- An ESP32 board and the [Arduino-ESP32 core](https://github.com/espressif/arduino-esp32)
  (Boards Manager: "esp32 by Espressif Systems").
- No third-party libraries. Only `WiFi.h`, `WiFiClientSecure.h` and `HTTPClient.h`,
  which ship with the core.

## Setup

1. Open `iotpush_alert/iotpush_alert.ino` in the Arduino IDE (or `arduino-cli`).
2. Edit the clearly marked `CONFIG` block: Wi-Fi SSID/password, topic name, and the
   topic's API key (leave it `""` for a public topic).
3. Pick `INPUT_PIN` for your board. The default, GPIO 4, uses the internal pull-down;
   add an external pull-down (e.g. 10k to GND) for long wires.
4. Upload and open the Serial Monitor at 115200 baud.

Use a per-topic key on devices, not your account (`iop_live_...`) key: anything you
flash onto a device can be read back out of it.

## Certificate

The sketch pins **ISRG Root X1** (Let's Encrypt), which `www.iotpush.com` currently
chains to:

```
SHA-256 96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6
valid until 2035-06-04
```

If the site ever moves to a different CA, replace the PEM in the sketch.

## Compile from the command line

```bash
arduino-cli core install esp32:esp32
arduino-cli compile --fqbn esp32:esp32:esp32 esp32/iotpush_alert
```
