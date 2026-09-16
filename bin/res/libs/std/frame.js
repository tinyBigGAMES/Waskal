/*******************************************************************************
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  frame.js

  requestAnimationFrame loop with a fixed-step update and a variable-rate
  render. Run() only schedules and returns; _start finishes normally. Each
  tick drains an accumulator, calling _frame(updateIdx, step) zero or more
  times, then calls _call0(renderIdx) once (skipped while the tab is
  hidden). When the loop ends (Stop, trap, or exception) the shim fires
  WKL.onLoopEnd exactly once from a tick -- never from inside a wasm call --
  so index.html can run _shutdown with nothing on the wasm stack. Run's third
  argument is the shutdown handler, exposed via shutdownHandler() for
  _shutdown; any of the three may be nil (0) and is then skipped.
  Fires WKL.onTick once per tick before any wasm call; input.js uses it.
*******************************************************************************/

var frame = (function () {
  var updateIdx = 0, renderIdx = 0, shutdownIdx = 0;   // 0 = nil = no routine (table slot 0 is reserved)
  var running = 0, last = 0, t0 = 0, fps = 0, fpsAcc = 0, fpsN = 0;
  var step = 1 / 60, acc = 0;
  var MAX_STEPS = 8;                              // spiral-of-death guard

  function loopEnd() {
    if (WKL.onLoopEnd) { var f = WKL.onLoopEnd; WKL.onLoopEnd = null; f(); }
  }

  function tick(now) {
    if (!running) { loopEnd(); return; }        // Stop() was called: end here
    var dt = (now - last) / 1000; last = now;
    if (WKL.onTick) WKL.onTick();               // input snapshot for this whole tick
    if (dt > 0.1) dt = 0.1;                     // tab switch / debugger: clamp
    fpsAcc += dt; fpsN++;
    if (fpsAcc >= 0.5) { fps = fpsN / fpsAcc; fpsAcc = 0; fpsN = 0; }
    acc += dt;
    var n = 0;
    try {
      while (updateIdx && acc >= step && n < MAX_STEPS) {
        WKL_WASM.exports._frame(updateIdx, step);
        acc -= step; n++;
        if (!running) break;                    // Stop() inside Update
      }
      if (!updateIdx || n === MAX_STEPS) acc = 0; // no update, or fell too far behind: drop time
      if (running && renderIdx && !document.hidden)
        WKL_WASM.exports._call0(renderIdx);
    }
    catch (e) { running = 0; WKL.fail(e); return; }   // trap/exception ends loop
    requestAnimationFrame(tick);                // Stop() inside a handler is seen next tick
  }

  return {
    Run: function (u, r, s) {
      updateIdx = u; renderIdx = r; shutdownIdx = s; running = 1; acc = 0;
      t0 = last = performance.now();
      requestAnimationFrame(tick);
    },
    SetTargetFPS: function (fps) { if (fps > 0) step = 1 / fps; },
    Stop: function () { running = 0; },
    IsRunning: function () { return running; },
    Time: function () { return (performance.now() - t0) / 1000; },
    FPS: function () { return fps; },
    shutdownHandler: function () { return shutdownIdx; }
  };
})();
