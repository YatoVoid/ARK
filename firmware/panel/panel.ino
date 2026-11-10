// ARK panel for an Arduino UNO: the admin's physical controls.
//
// Wiring (buttons and the switch connect the pin to GND, internal pull-ups):
//   D2   approve button     admits the member whose join code was checked
//   D3   panic button       wipes the station's keys from memory and quits
//   D9   green LED (+220R)  log is intact
//   D10  red LED (+220R)    something is wrong: problem entries or rejected messages
//   D11  passive buzzer     beeps on request (driven with tone(), so it
//                           needs no oscillator of its own)
//
// Serial, 9600 baud, one command per line:
//   panel -> station   "APPROVE", "PANIC"
//   station -> panel   "G" (all good), "R" (problem), "B" (beep)
//
// The panel holds no keys and makes no decisions. Approve only does
// something when the station is showing a join request.

const int PIN_APPROVE = 2;
const int PIN_PANIC = 3;
const int PIN_GREEN = 9;
const int PIN_RED = 10;
const int PIN_BUZZER = 11;
const unsigned long DEBOUNCE_MS = 50;

int lastApprove = HIGH, lastPanic = HIGH;
unsigned long approveChanged = 0, panicChanged = 0;

void setup() {
  pinMode(PIN_APPROVE, INPUT_PULLUP);
  pinMode(PIN_PANIC, INPUT_PULLUP);
  pinMode(PIN_GREEN, OUTPUT);
  pinMode(PIN_RED, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  Serial.begin(9600);
  // Both LEDs on until the station says otherwise, so a dead link shows.
  digitalWrite(PIN_GREEN, HIGH);
  digitalWrite(PIN_RED, HIGH);
}

// Sends `word` once each time the button goes from released to pressed.
void watch(int pin, int &last, unsigned long &changed, const char *word) {
  int now = digitalRead(pin);
  if (now != last && millis() - changed > DEBOUNCE_MS) {
    changed = millis();
    last = now;
    if (now == LOW)
      Serial.println(word);
  }
}

void loop() {
  watch(PIN_APPROVE, lastApprove, approveChanged, "APPROVE");
  watch(PIN_PANIC, lastPanic, panicChanged, "PANIC");

  while (Serial.available()) {
    char c = Serial.read();
    if (c == 'G') {
      digitalWrite(PIN_GREEN, HIGH);
      digitalWrite(PIN_RED, LOW);
    } else if (c == 'R') {
      digitalWrite(PIN_GREEN, LOW);
      digitalWrite(PIN_RED, HIGH);
    } else if (c == 'B') {
      tone(PIN_BUZZER, 2000, 150);
    }
  }
}
