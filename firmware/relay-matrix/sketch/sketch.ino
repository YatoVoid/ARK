// ARK animation for the Arduino UNO Q's 13x8 LED matrix: the word ARK
// rises from the flood and sinks, the ark rises, its windows light up,
// and a dove crosses once the rain stops. Frames come from frames.py.

#include <Arduino_LED_Matrix.h>
#include "frames.h"

Arduino_LED_Matrix matrix;

void setup() {
  matrix.begin();
  matrix.setGrayscaleBits(3);
}

void loop() {
  for (int i = 0; i < FRAME_COUNT; i++) {
    matrix.draw((uint8_t *)FRAMES[i]);
    delay(FRAME_MS[i]);
  }
}
