/*******************************************************************************
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  input.js

  Keyboard, mouse and gamepad state, snapshotted ONCE PER TICK. Browser
  events are queued as they arrive; WKL.onTick (fired by frame.js before
  any wasm call) clears last tick's edges, drains the queue into
  Down/Pressed/Released, snapshots the mouse, and polls the gamepads. So
  every Update call and the Render of one tick see the same input, and a
  press+release that both land between two ticks reports Pressed AND
  Released in the next tick (Down false). Without frame.js no ticks fire
  and the snapshot never changes.

  Keys are physical (KeyboardEvent.code) and numbered by USB HID usage
  (page 0x07). Mouse coordinates are in canvas pixels when WKL.canvas is
  set (canvas2d.Init/InitOn), otherwise page client pixels. Gamepads use
  the W3C standard mapping; axes get a radial deadzone (default 0.15).
  Booleans cross to wasm as i32 1/0; no strings cross at all.
*******************************************************************************/

var input = (function () {
  var N_KEYS = 256, N_MOUSE = 8, N_PADS = 4, N_PADBTN = 32, N_AXES = 8;

  // snapshot (what wasm reads during a tick)
  var kDown = new Uint8Array(N_KEYS), kPressed = new Uint8Array(N_KEYS), kReleased = new Uint8Array(N_KEYS);
  var mDown = new Uint8Array(N_MOUSE), mPressed = new Uint8Array(N_MOUSE), mReleased = new Uint8Array(N_MOUSE);
  var mx = 0, my = 0, mdx = 0, mdy = 0, wheel = 0, anyPressed = 0;
  var padOn = new Uint8Array(N_PADS);
  var pDown = new Uint8Array(N_PADS * N_PADBTN), pPressed = new Uint8Array(N_PADS * N_PADBTN), pReleased = new Uint8Array(N_PADS * N_PADBTN);
  var pValue = new Float64Array(N_PADS * N_PADBTN), pAxis = new Float64Array(N_PADS * N_AXES);
  var deadzone = 0.15;

  // live (mutated by browser events between ticks)
  var queue = [];                              // pairs: kind, code  (kind 0 keydown 1 keyup 2 mousedown 3 mouseup 4 release-all)
  var rawX = 0, rawY = 0, lastX = 0, lastY = 0, rawWheel = 0;

  // KeyboardEvent.code -> USB HID usage id (page 0x07)
  var CODES = {
    KeyA: 4, KeyB: 5, KeyC: 6, KeyD: 7, KeyE: 8, KeyF: 9, KeyG: 10, KeyH: 11, KeyI: 12, KeyJ: 13,
    KeyK: 14, KeyL: 15, KeyM: 16, KeyN: 17, KeyO: 18, KeyP: 19, KeyQ: 20, KeyR: 21, KeyS: 22,
    KeyT: 23, KeyU: 24, KeyV: 25, KeyW: 26, KeyX: 27, KeyY: 28, KeyZ: 29,
    Digit1: 30, Digit2: 31, Digit3: 32, Digit4: 33, Digit5: 34, Digit6: 35, Digit7: 36, Digit8: 37, Digit9: 38, Digit0: 39,
    Enter: 40, Escape: 41, Backspace: 42, Tab: 43, Space: 44, Minus: 45, Equal: 46,
    BracketLeft: 47, BracketRight: 48, Backslash: 49, Semicolon: 51, Quote: 52, Backquote: 53,
    Comma: 54, Period: 55, Slash: 56, CapsLock: 57,
    F1: 58, F2: 59, F3: 60, F4: 61, F5: 62, F6: 63, F7: 64, F8: 65, F9: 66, F10: 67, F11: 68, F12: 69,
    PrintScreen: 70, ScrollLock: 71, Pause: 72, Insert: 73, Home: 74, PageUp: 75, Delete: 76, End: 77, PageDown: 78,
    ArrowRight: 79, ArrowLeft: 80, ArrowDown: 81, ArrowUp: 82,
    NumLock: 83, NumpadDivide: 84, NumpadMultiply: 85, NumpadSubtract: 86, NumpadAdd: 87, NumpadEnter: 88,
    Numpad1: 89, Numpad2: 90, Numpad3: 91, Numpad4: 92, Numpad5: 93, Numpad6: 94, Numpad7: 95, Numpad8: 96, Numpad9: 97,
    Numpad0: 98, NumpadDecimal: 99,
    ControlLeft: 224, ShiftLeft: 225, AltLeft: 226, MetaLeft: 227,
    ControlRight: 228, ShiftRight: 229, AltRight: 230, MetaRight: 231
  };
  // keys whose browser default (scrolling, focus change) must not fire in a game page
  var PREVENT = { ArrowUp: 1, ArrowDown: 1, ArrowLeft: 1, ArrowRight: 1, Space: 1, Tab: 1 };

  function toCanvas(e) {
    var c = WKL.canvas;
    if (!c) { rawX = e.clientX; rawY = e.clientY; return; }
    var r = c.getBoundingClientRect();
    rawX = (e.clientX - r.left) * c.width / r.width / WKL.canvasDpr;
    rawY = (e.clientY - r.top) * c.height / r.height / WKL.canvasDpr;
  }

  window.addEventListener('keydown', function (e) {
    var k = CODES[e.code];
    if (k === undefined) return;
    if (PREVENT[e.code]) e.preventDefault();
    if (e.repeat) return;                      // OS auto-repeat is not a new press
    queue.push(0, k);
  });
  window.addEventListener('keyup', function (e) {
    var k = CODES[e.code];
    if (k !== undefined) queue.push(1, k);
  });
  window.addEventListener('mousedown', function (e) { toCanvas(e); if (e.button < N_MOUSE) queue.push(2, e.button); });
  window.addEventListener('mouseup', function (e) { toCanvas(e); if (e.button < N_MOUSE) queue.push(3, e.button); });
  window.addEventListener('mousemove', function (e) { toCanvas(e); });
  window.addEventListener('wheel', function (e) { rawWheel += e.deltaY; }, { passive: true });
  window.addEventListener('contextmenu', function (e) { if (WKL.canvas && e.target === WKL.canvas) e.preventDefault(); });
  window.addEventListener('blur', function () { queue.push(4, 0); });   // alt-tab: nothing stays stuck down

  function pollPads() {
    var pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (var p = 0; p < N_PADS; p++) {
      var g = pads[p];
      padOn[p] = (g && g.connected) ? 1 : 0;
      for (var b = 0; b < N_PADBTN; b++) {
        var i = p * N_PADBTN + b;
        var btn = (g && b < g.buttons.length) ? g.buttons[b] : null;
        var was = pDown[i], now = (btn && btn.pressed) ? 1 : 0;
        pDown[i] = now;
        pPressed[i] = (now && !was) ? 1 : 0;
        pReleased[i] = (!now && was) ? 1 : 0;
        pValue[i] = btn ? btn.value : 0;
      }
      for (var a = 0; a < N_AXES; a++)
        pAxis[p * N_AXES + a] = (g && a < g.axes.length) ? g.axes[a] : 0;
    }
  }

  function tick() {
    var i, k;
    kPressed.fill(0); kReleased.fill(0); mPressed.fill(0); mReleased.fill(0); anyPressed = 0;
    for (i = 0; i < queue.length; i += 2) {
      var kind = queue[i], code = queue[i + 1];
      if (kind === 0) { kDown[code] = 1; kPressed[code] = 1; anyPressed = 1; }
      else if (kind === 1) { kDown[code] = 0; kReleased[code] = 1; }
      else if (kind === 2) { mDown[code] = 1; mPressed[code] = 1; }
      else if (kind === 3) { mDown[code] = 0; mReleased[code] = 1; }
      else {                                   // release-all
        for (k = 0; k < N_KEYS; k++) if (kDown[k]) { kDown[k] = 0; kReleased[k] = 1; }
        for (k = 0; k < N_MOUSE; k++) if (mDown[k]) { mDown[k] = 0; mReleased[k] = 1; }
      }
    }
    queue.length = 0;
    mdx = rawX - lastX; mdy = rawY - lastY;
    mx = lastX = rawX; my = lastY = rawY;
    wheel = rawWheel; rawWheel = 0;
    pollPads();
  }
  WKL.onTick = tick;

  // radial deadzone over a stick pair; axes >= 4 are returned raw
  function axisDz(p, a) {
    if (a >= 4) return pAxis[p * N_AXES + a];
    var base = p * N_AXES + (a < 2 ? 0 : 2);
    var x = pAxis[base], y = pAxis[base + 1];
    var m = Math.sqrt(x * x + y * y);
    if (m <= deadzone) return 0;
    var s = Math.min(1, (m - deadzone) / (1 - deadzone)) / m;
    var v = ((a & 1) === 0 ? x : y) * s;
    return v < -1 ? -1 : (v > 1 ? 1 : v);
  }

  function padIdx(p, b) { return (p >= 0 && p < N_PADS && b >= 0 && b < N_PADBTN) ? p * N_PADBTN + b : -1; }

  return {
    KeyDown: function (k) { return kDown[k & 255]; },
    KeyPressed: function (k) { return kPressed[k & 255]; },
    KeyReleased: function (k) { return kReleased[k & 255]; },
    AnyKeyPressed: function () { return anyPressed; },

    MouseDown: function (b) { return mDown[b & 7]; },
    MousePressed: function (b) { return mPressed[b & 7]; },
    MouseReleased: function (b) { return mReleased[b & 7]; },
    MouseX: function () { return mx; },
    MouseY: function () { return my; },
    MouseDeltaX: function () { return mdx; },
    MouseDeltaY: function () { return mdy; },
    MouseWheel: function () { return wheel; },

    GamepadConnected: function (p) { return (p >= 0 && p < N_PADS) ? padOn[p] : 0; },
    GamepadDown: function (p, b) { var i = padIdx(p, b); return i < 0 ? 0 : pDown[i]; },
    GamepadPressed: function (p, b) { var i = padIdx(p, b); return i < 0 ? 0 : pPressed[i]; },
    GamepadReleased: function (p, b) { var i = padIdx(p, b); return i < 0 ? 0 : pReleased[i]; },
    GamepadButtonValue: function (p, b) { var i = padIdx(p, b); return i < 0 ? 0 : pValue[i]; },
    GamepadAxis: function (p, a) { return (p >= 0 && p < N_PADS && a >= 0 && a < N_AXES) ? axisDz(p, a) : 0; },
    GamepadAxisRaw: function (p, a) { return (p >= 0 && p < N_PADS && a >= 0 && a < N_AXES) ? pAxis[p * N_AXES + a] : 0; },
    SetDeadzone: function (dz) { deadzone = dz < 0 ? 0 : (dz > 0.99 ? 0.99 : dz); }
  };
})();
