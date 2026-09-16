/*******************************************************************************
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  video.js

  HTMLVideoElement shim. One hidden <video> per handle, created by Load (from
  an @asset via WaskalAssets.url) or LoadURL (external, crossOrigin=anonymous
  so Draw does not taint the canvas when the server sends CORS headers).
  Two ways to see it: Draw/DrawRect blit the current frame onto WKL.canvas
  (the canvas2d canvas; same 2D context, so transform/alpha/clip apply), or
  Show(mode) places the element in the page with the canvas2d placement modes
  (flow/center/fill/window). Hide puts it back out of the page.
  Autoplay: play-with-sound needs a user gesture. A pointerdown/keydown
  listener on window flips _gesture; Play before that tries anyway (muted
  play is allowed) and, if the browser refuses, retries once the gesture
  arrives. Marshalling: seconds/volume/rate/geometry float64; handles and
  bools int32, 0 = none. Every DOM call is try/catch -- nothing unwinds into
  wasm. Couples to nothing but WKL / WaskalAssets.
*******************************************************************************/

var video = (function () {
  var V = WKL.handles();   // Video -> {el, url, isAsset, placement, wantPlay}
  var _gesture = false;
  var _all = [];           // live handles (the table has no iterator)

  function onGesture() {
    if (_gesture) return;
    _gesture = true;
    window.removeEventListener('pointerdown', onGesture);
    window.removeEventListener('keydown', onGesture);
    for (var i = 0; i < _all.length; i++) {
      var v = V.get(_all[i]);
      if (v && v.wantPlay) { v.wantPlay = false; tryPlay(v); }
    }
  }
  window.addEventListener('pointerdown', onGesture);
  window.addEventListener('keydown', onGesture);

  function tryPlay(v) {
    try {
      var p = v.el.play();
      if (p && p.catch) p.catch(function () { if (!_gesture) v.wantPlay = true; });
    } catch (e) { if (!_gesture) v.wantPlay = true; }
  }

  function makeEl(url, isAsset) {
    var el = document.createElement('video');
    if (!isAsset) el.crossOrigin = 'anonymous';
    el.preload = 'auto';
    el.playsInline = true;
    el.style.display = 'none';
    el.src = url;
    document.body.appendChild(el);
    var h = V.alloc({ el: el, url: url, isAsset: isAsset, placement: 'hidden', wantPlay: false });
    _all.push(h);
    return h;
  }

  // Mirrors canvas2d.js _applyPlacement for this element (shims never share code).
  // hidden = display none (default); flow / center / fill / window as canvas2d.
  function applyPlacement(v) {
    var el = v.el, s = el.style, m = v.placement;
    var w = el.videoWidth || 16, h = el.videoHeight || 9;
    s.position = ''; s.left = ''; s.top = ''; s.transform = '';
    s.maxWidth = ''; s.maxHeight = ''; s.objectFit = ''; s.width = ''; s.height = '';
    if (m === 'hidden') { s.display = 'none'; return; }
    s.display = 'block';
    if (m === 'center') {
      s.position = 'fixed'; s.left = '50%'; s.top = '50%';
      s.transform = 'translate(-50%, -50%)';
    } else if (m === 'fill') {
      s.position = 'fixed'; s.left = '50%'; s.top = '50%';
      s.transform = 'translate(-50%, -50%)';
      s.width = '100vw'; s.height = '100vh'; s.objectFit = 'contain';
      s.maxWidth = (100 * w / h) + 'vh';
      s.maxHeight = (100 * h / w) + 'vw';
    } else if (m === 'window') {
      s.position = 'fixed'; s.left = '0'; s.top = '0';
      s.width = '100vw'; s.height = '100vh'; s.objectFit = 'contain';
    }
  }

  // App mode chrome: on while any video is placed outside the flow.
  function updateAppMode() {
    var on = false;
    for (var i = 0; i < _all.length; i++) {
      var v = V.get(_all[i]);
      if (v && v.placement !== 'hidden' && v.placement !== 'flow') on = true;
    }
    document.body.classList.toggle('wkl-app', on);
  }

  // On program exit hide every video so the console and exit status show.
  WKL.onExit.push(function () {
    for (var i = 0; i < _all.length; i++) {
      var v = V.get(_all[i]);
      if (v) { try { v.el.pause(); } catch (e) { } v.placement = 'hidden'; applyPlacement(v); }
    }
    updateAppMode();
  });

  function get(h) { return V.get(h); }

  return {
    // ---- lifetime ----
    Load: function (assetPtr) {
      var name = WKL.readCStr(assetPtr);
      if (!WaskalAssets.exists(name)) { console.warn('video: no asset "' + name + '"'); return 0; }
      try { return makeEl(WaskalAssets.url(name), true); }
      catch (e) { console.warn('video: Load: ' + e); return 0; }
    },
    LoadURL: function (urlPtr) {
      try { return makeEl(WKL.readCStr(urlPtr), false); }
      catch (e) { console.warn('video: LoadURL: ' + e); return 0; }
    },
    Release: function (h) {
      var v = get(h);
      if (!v) return;
      try { v.el.pause(); v.el.removeAttribute('src'); v.el.load(); } catch (e) { }
      try { if (v.el.parentNode) v.el.parentNode.removeChild(v.el); } catch (e) { }
      if (v.isAsset) { try { URL.revokeObjectURL(v.url); } catch (e) { } }
      V.release(h);
      var i = _all.indexOf(h); if (i >= 0) _all.splice(i, 1);
      updateAppMode();
    },

    // ---- transport ----
    Play: function (h) { var v = get(h); if (v) tryPlay(v); },
    Pause: function (h) { var v = get(h); if (v) { v.wantPlay = false; try { v.el.pause(); } catch (e) { } } },
    Stop: function (h) { var v = get(h); if (v) { v.wantPlay = false; try { v.el.pause(); v.el.currentTime = 0; } catch (e) { } } },
    Seek: function (h, sec) { var v = get(h); if (v) { try { v.el.currentTime = sec < 0 ? 0 : sec; } catch (e) { } } },
    SetVolume: function (h, vol) { var v = get(h); if (v) { try { v.el.volume = vol < 0 ? 0 : (vol > 1 ? 1 : vol); } catch (e) { } } },
    SetLoop: function (h, on) { var v = get(h); if (v) { try { v.el.loop = !!on; } catch (e) { } } },
    SetMuted: function (h, on) { var v = get(h); if (v) { try { v.el.muted = !!on; } catch (e) { } } },
    SetPlaybackRate: function (h, r) { var v = get(h); if (v) { try { v.el.playbackRate = r > 0 ? r : 1.0; } catch (e) { } } },

    // ---- state ----
    IsReady: function (h) { var v = get(h); return (v && v.el.readyState >= 3) ? 1 : 0; },
    IsPlaying: function (h) { var v = get(h); return (v && !v.el.paused && !v.el.ended) ? 1 : 0; },
    IsEnded: function (h) { var v = get(h); return (v && v.el.ended) ? 1 : 0; },
    IsMuted: function (h) { var v = get(h); return (v && v.el.muted) ? 1 : 0; },
    Position: function (h) { var v = get(h); return v ? (v.el.currentTime || 0) : 0; },
    Duration: function (h) { var v = get(h); return (v && isFinite(v.el.duration)) ? v.el.duration : 0; },
    Width: function (h) { var v = get(h); return v ? (v.el.videoWidth || 0) : 0; },
    Height: function (h) { var v = get(h); return v ? (v.el.videoHeight || 0) : 0; },

    // ---- draw onto the canvas2d canvas (current frame) ----
    Draw: function (h, dx, dy, dw, dh) {
      var v = get(h), c = WKL.canvas;
      if (!v || !c || v.el.readyState < 2) return;
      try { c.getContext('2d').drawImage(v.el, dx, dy, dw, dh); } catch (e) { }
    },
    DrawRect: function (h, sx, sy, sw, sh, dx, dy, dw, dh) {
      var v = get(h), c = WKL.canvas;
      if (!v || !c || v.el.readyState < 2) return;
      try { c.getContext('2d').drawImage(v.el, sx, sy, sw, sh, dx, dy, dw, dh); } catch (e) { }
    },

    // ---- element in the page ----
    Show: function (h, modePtr) {
      var v = get(h);
      if (!v) return;
      var m = WKL.readCStr(modePtr);
      if (m !== 'flow' && m !== 'center' && m !== 'fill' && m !== 'window') {
        console.warn('video: unknown placement "' + m + '"');
        return;
      }
      v.placement = m;
      applyPlacement(v);
      updateAppMode();
    },
    Hide: function (h) {
      var v = get(h);
      if (!v) return;
      v.placement = 'hidden';
      applyPlacement(v);
      updateAppMode();
    }
  };
})();
