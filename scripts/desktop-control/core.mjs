export const keyCodes = Object.freeze({
  CTRL: 29, SHIFT: 42, ALT: 56, SUPER: 125,
  ENTER: 28, ESC: 1, TAB: 15, SPACE: 57, BACKSPACE: 14,
  DELETE: 111, INSERT: 110, HOME: 102, END: 107,
  PAGEUP: 104, PAGEDOWN: 109, LEFT: 105, RIGHT: 106, UP: 103, DOWN: 108,
  F1: 59, F2: 60, F3: 61, F4: 62, F5: 63, F6: 64,
  F7: 65, F8: 66, F9: 67, F10: 68, F11: 87, F12: 88,
  A: 30, B: 48, C: 46, D: 32, E: 18, F: 33, G: 34, H: 35,
  I: 23, J: 36, K: 37, L: 38, M: 50, N: 49, O: 24, P: 25,
  Q: 16, R: 19, S: 31, T: 20, U: 22, V: 47, W: 17, X: 45,
  Y: 21, Z: 44,
  0: 11, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10,
});

export function keySequence(keys) {
  if (!Array.isArray(keys) || keys.length < 1 || keys.length > 4) {
    throw new Error('keys must contain one to four names');
  }
  const codes = keys.map((key) => {
    const code = keyCodes[String(key).toUpperCase()];
    if (code === undefined) throw new Error(`Unsupported key: ${key}`);
    return code;
  });
  return [...codes.map((code) => `${code}:1`), ...codes.reverse().map((code) => `${code}:0`)];
}

export function outputPoint(output, x, y) {
  const box = output?.logical;
  if (!box || !Number.isInteger(x) || !Number.isInteger(y) ||
      x < 0 || y < 0 || x >= box.width || y >= box.height) {
    throw new Error('Point is outside the selected output');
  }
  return { x: box.x + x, y: box.y + y };
}

export function buttonCode(button, phase = 'click') {
  const index = { left: 0, right: 1, middle: 2 }[button || 'left'];
  if (index === undefined) throw new Error('Unsupported mouse button');
  const mask = { click: 0xc0, down: 0x40, up: 0x80 }[phase];
  if (mask === undefined) throw new Error('Unsupported button phase');
  return `0x${(mask + index).toString(16)}`;
}
