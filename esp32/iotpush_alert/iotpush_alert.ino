// iotPush alert for ESP32 (Arduino-ESP32 core, no third-party libraries).
//
// Sends a push to your iotPush topic when a GPIO input goes HIGH
// (debounced, and at most one push per MIN_INTERVAL_MS).
// TLS is verified against the ISRG Root X1 certificate below (setCACert).
//
// Docs: https://www.iotpush.com/docs

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

// ============================ CONFIG ============================
const char* WIFI_SSID         = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD     = "YOUR_WIFI_PASSWORD";
const char* IOTPUSH_TOPIC     = "YOUR_TOPIC";
// The topic's API key (private topics). Leave "" for a public topic.
// Use a per-topic key here, never your account key: anything flashed
// onto a device can be read back out of it.
const char* IOTPUSH_TOPIC_KEY = "";

const int   INPUT_PIN         = 4;        // trigger when this pin goes HIGH
const char* ALERT_TITLE       = "Sensor alert";
const char* ALERT_MESSAGE     = "Input went HIGH";
const char* ALERT_PRIORITY    = "high";   // low | normal | high | urgent
const unsigned long DEBOUNCE_MS     = 50;
const unsigned long MIN_INTERVAL_MS = 60UL * 1000UL;  // rate limit: one push per 60 s
// ================================================================

const char* IOTPUSH_HOST = "https://www.iotpush.com";

// ISRG Root X1 (Let's Encrypt), which www.iotpush.com currently chains to.
// SHA-256 fingerprint:
// 96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6
// Valid until 2035-06-04. If the site ever changes CA, update this certificate.
static const char ISRG_ROOT_X1[] PROGMEM = R"PEM(
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
)PEM";

int lastReading = LOW;
int stableState = LOW;
unsigned long lastChangeMs = 0;
unsigned long lastSendMs = 0;
bool hasSent = false;

String jsonEscape(const char* s) {
  String out;
  for (; *s; s++) {
    char c = *s;
    if (c == '"' || c == '\\') { out += '\\'; out += c; }
    else if (c == '\n') out += "\\n";
    else if ((unsigned char)c < 0x20) out += ' ';
    else out += c;
  }
  return out;
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  Serial.printf("Connecting to %s", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(250);
    Serial.print('.');
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? " connected" : " failed (will retry)");
}

bool sendPush() {
  connectWiFi();
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClientSecure client;
  client.setCACert(ISRG_ROOT_X1);  // verify the server; do not use setInsecure()

  HTTPClient http;
  String url = String(IOTPUSH_HOST) + "/api/push/" + IOTPUSH_TOPIC;
  if (!http.begin(client, url)) {
    Serial.println("http.begin failed");
    return false;
  }
  http.setTimeout(15000);
  http.addHeader("Content-Type", "application/json");
  if (strlen(IOTPUSH_TOPIC_KEY) > 0) {
    http.addHeader("Authorization", String("Bearer ") + IOTPUSH_TOPIC_KEY);
  }

  String body = String("{\"message\":\"") + jsonEscape(ALERT_MESSAGE) +
                " (uptime " + String(millis() / 1000) + " s)\"," +
                "\"title\":\"" + jsonEscape(ALERT_TITLE) + "\"," +
                "\"priority\":\"" + jsonEscape(ALERT_PRIORITY) + "\"}";

  int code = http.POST(body);
  String resp = http.getString();  // JSON with receipt_id on success
  http.end();
  Serial.printf("iotPush HTTP %d %s\n", code, resp.c_str());
  return code >= 200 && code < 300;  // 429 = over the Free plan's monthly push limit
}

void setup() {
  Serial.begin(115200);
  // Internal pull-down keeps the pin LOW when nothing drives it.
  // For long wires, add an external pull-down resistor (e.g. 10k to GND).
  pinMode(INPUT_PIN, INPUT_PULLDOWN);
  connectWiFi();
}

void loop() {
  int reading = digitalRead(INPUT_PIN);
  unsigned long now = millis();

  if (reading != lastReading) {
    lastChangeMs = now;
    lastReading = reading;
  }

  if (now - lastChangeMs >= DEBOUNCE_MS && reading != stableState) {
    stableState = reading;
    if (stableState == HIGH) {
      if (!hasSent || now - lastSendMs >= MIN_INTERVAL_MS) {
        hasSent = true;
        lastSendMs = now;  // rate-limit attempts, successful or not
        Serial.println(sendPush() ? "push sent" : "push failed");
      } else {
        Serial.println("input HIGH, but rate-limited; skipping");
      }
    }
  }
  delay(5);
}
