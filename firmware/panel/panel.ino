// ARK panel for an Arduino UNO: the manager's physical controls.
//
// Wiring (buttons connect the pin to GND, internal pull-ups):
//   D2   green button       RESTORE: reconnect this machine to the internet
//   D3   red button         CUT: disconnect this machine from the internet
//   D9   green LED (+220R)  internet connected
//   D10  red LED (+220R)    internet cut; ARK is running on the relay alone
//   D11  passive buzzer     alerts, driven with tone()
//
// Serial, 9600 baud, one command per line:
//   panel -> station   "RESTORE", "CUT"
//   station -> panel   "G" (connected), "R" (cut), "B" (one beep),
//                      "A" (alert: three beeps)
//
// The panel holds no keys and makes no decisions. The station decides
// whether a press is allowed (only the manager's station cuts) and logs it.

const int PIN_RESTORE = 2;
const int PIN_CUT = 3;
const int PIN_GREEN = 9;
const int PIN_RED = 10;
const int PIN_BUZZER = 11;
const unsigned long DEBOUNCE_MS = 50;
const unsigned long BEEP_MS = 150;
const unsigned long BEEP_GAP_MS = 250;

int lastRestore = HIGH, lastCut = HIGH;
unsigned long restoreChanged = 0, cutChanged = 0;
int beepsLeft = 0;
unsigned long nextBeep = 0;

void setup() {
  pinMode(PIN_RESTORE, INPUT_PULLUP);
  pinMode(PIN_CUT, INPUT_PULLUP);
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
  watch(PIN_RESTORE, lastRestore, restoreChanged, "RESTORE");
  watch(PIN_CUT, lastCut, cutChanged, "CUT");

  // Beeps are spaced without delay() so the buttons stay responsive.
  if (beepsLeft > 0 && millis() >= nextBeep) {
    tone(PIN_BUZZER, 2000, BEEP_MS);
    beepsLeft--;
    nextBeep = millis() + BEEP_MS + BEEP_GAP_MS;
  }

  while (Serial.available()) {
    char c = Serial.read();
    if (c == 'G') {
      digitalWrite(PIN_GREEN, HIGH);
      digitalWrite(PIN_RED, LOW);
    } else if (c == 'R') {
      digitalWrite(PIN_GREEN, LOW);
      digitalWrite(PIN_RED, HIGH);
    } else if (c == 'B') {
      beepsLeft = max(beepsLeft, 1);
    } else if (c == 'A') {
      beepsLeft = 3;
    }
  }
}
