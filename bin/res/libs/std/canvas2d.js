/*******************************************************************************
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  canvas2d.js

  HTML5 Canvas 2D host shim. All sizes and coordinates are logical (CSS)
  pixels; the backing store is logical * devicePixelRatio with a scale(dpr)
  base transform so drawing is crisp on high-DPI displays. Placement modes
  (flow, center, fill, window) are CSS on the canvas; center/fill/window
  toggle body.wkl-app (app mode, dev console hidden).

  Marshalling contract (research/03):
    geometry/angles/alpha/widths  f64 -> JS Number directly
    counts/handles/bools          i32
    strings in                    ptr to char, read via WKL.readCStr
    strings out                   caller buffer, WKL.writeCStr, returns BigInt
    fonts                         @asset bytes -> FontFace; poll FontsReady()
    JS objects                    int32 handle tables (WKL.handles), 0 = none
    i64 never crosses into a DOM call.
*******************************************************************************/
var canvas2d = (function () {
  var _canvas = null;
  var _ctx = null;
  var G = WKL.handles();   // gradients + patterns
  var P = WKL.handles();   // Path2D
  var D = WKL.handles();   // ImageData

  function _mem() { return WKL_WASM.exports.memory.buffer; }
  function _rgb(r, g, b) { return 'rgb(' + r + ',' + g + ',' + b + ')'; }
  function _bitmap(namePtr) {
    var name = WKL.readCStr(namePtr);
    var bmp = WaskalAssets.getImageBitmap(name);
    if (!bmp) { console.warn('canvas2d: no image asset "' + name + '"'); return null; }
    return bmp;
  }
  function _writeF64(ptr, off, v) {
    new DataView(_mem()).setFloat64(Number(ptr) + off, v, true);
  }
  var _TEXT_PROPS = ['font', 'textAlign', 'textBaseline', 'direction', 'letterSpacing',
    'wordSpacing', 'fontKerning', 'fontStretch', 'fontVariantCaps', 'textRendering'];
  var _fontsPending = 0;
  function _drawLines(lines, x, y, lh, stroke) {
    for (var i = 0; i < lines.length; i++) {
      if (stroke) _ctx.strokeText(lines[i], x, y + i * lh);
      else _ctx.fillText(lines[i], x, y + i * lh);
    }
    return lines.length;
  }
  // Greedy word wrap; '\n' forces a break; a single over-long word gets its own line.
  function _wrap(text, maxWidth) {
    var out = [], paras = text.split('\n');
    for (var p = 0; p < paras.length; p++) {
      var words = paras[p].split(' '), line = '';
      for (var w = 0; w < words.length; w++) {
        var probe = line.length ? line + ' ' + words[w] : words[w];
        if (line.length && _ctx.measureText(probe).width > maxWidth) {
          out.push(line); line = words[w];
        } else { line = probe; }
      }
      out.push(line);
    }
    return out;
  }
  // Logical size (what the user draws in) vs backing store (logical * dpr).
  // The context carries a base transform of scale(dpr) so all user drawing
  // stays in logical pixels and is crisp on high-DPI displays.
  var _w = 0, _h = 0, _dpr = 1;
  var _placement = 'flow';
  function _setSize(w, h) {
    _w = w; _h = h;
    _dpr = window.devicePixelRatio || 1;
    _canvas.width = Math.round(w * _dpr);
    _canvas.height = Math.round(h * _dpr);
    WKL.canvasDpr = _dpr;   // read by input.js to map mouse to logical pixels
    _baseTransform();
    _applyPlacement();
  }
  function _baseTransform() { _ctx.setTransform(_dpr, 0, 0, _dpr, 0, 0); }
  function _ensure() {
    if (!_canvas) {
      _canvas = document.createElement('canvas');
      document.body.appendChild(_canvas);
      _ctx = _canvas.getContext('2d');
      _setSize(640, 480);
    }
  }
  // Applies _placement as CSS on the canvas and toggles body.wkl-app (app mode).
  // flow   = in the body flow (default), CSS size = logical size
  // center = fixed, centred in the viewport, CSS size = logical size
  // fill   = fixed, scaled to the viewport keeping aspect (letterboxed);
  //          logical size unchanged so drawing coords stay in Init() pixels
  // window = fixed at 0,0, logical size follows the viewport (see resize hook)
  function _applyPlacement() {
    var s = _canvas.style, m = _placement;
    document.body.classList.toggle('wkl-app', m !== 'flow');
    s.position = ''; s.left = ''; s.top = ''; s.transform = '';
    s.maxWidth = ''; s.maxHeight = ''; s.objectFit = '';
    s.width = _w + 'px'; s.height = _h + 'px';
    if (m === 'center') {
      s.position = 'fixed'; s.left = '50%'; s.top = '50%';
      s.transform = 'translate(-50%, -50%)';
    } else if (m === 'fill') {
      s.position = 'fixed'; s.left = '50%'; s.top = '50%';
      s.transform = 'translate(-50%, -50%)';
      s.width = '100vw'; s.height = '100vh'; s.objectFit = 'contain';
      s.maxWidth = (100 * _w / _h) + 'vh';
      s.maxHeight = (100 * _h / _w) + 'vw';
    } else if (m === 'window') {
      s.position = 'fixed'; s.left = '0'; s.top = '0';
    }
  }
  // window mode: follow the viewport; also re-reads dpr (monitor/zoom change).
  window.addEventListener('resize', function () {
    if (_canvas && _placement === 'window') _setSize(window.innerWidth, window.innerHeight);
  });
  // On program exit drop back to flow so the console and exit status show
  // with the final frame below them.
  WKL.onExit.push(function () {
    if (_canvas && _placement !== 'flow') { _placement = 'flow'; _applyPlacement(); }
  });

  return {
    // ---- Setup / canvas element ----
    Init: function (w, h) {
      _canvas = document.createElement('canvas');
      document.body.appendChild(_canvas);
      _ctx = _canvas.getContext('2d');
      WKL.canvas = _canvas;
      _setSize(w, h);
    },
    InitOn: function (idPtr, w, h) {
      var el = document.getElementById(WKL.readCStr(idPtr));
      if (!el) { return 0; }
      _canvas = el;
      _ctx = _canvas.getContext('2d');
      WKL.canvas = _canvas;
      _setSize(w, h);
      return 1;
    },
    Resize: function (w, h) { _ensure(); _setSize(w, h); },
    Width: function () { _ensure(); return _w; },
    Height: function () { _ensure(); return _h; },
    ViewportWidth: function () { return window.innerWidth; },
    ViewportHeight: function () { return window.innerHeight; },
    SetBackground: function (cssPtr) { document.body.style.background = WKL.readCStr(cssPtr); },
    // See _applyPlacement for the modes. 'window' also resizes the logical
    // size to the viewport now and on every window resize.
    SetPlacement: function (modePtr) {
      _ensure();
      var m = WKL.readCStr(modePtr);
      if (m !== 'flow' && m !== 'center' && m !== 'fill' && m !== 'window') {
        console.warn('canvas2d: unknown placement "' + m + '"');
        return;
      }
      _placement = m;
      if (m === 'window') _setSize(window.innerWidth, window.innerHeight);
      else _applyPlacement();
    },
    ToDataURL: function (mimePtr, buf, size) {   // returns BigInt
      _ensure();
      return WKL.writeCStr(_canvas.toDataURL(WKL.readCStr(mimePtr)), buf, size);
    },

    // ---- State ----
    Save: function () { _ctx.save(); },
    Restore: function () { _ctx.restore(); },
    Reset: function () { if (_ctx.reset) { _ctx.reset(); } else { _ctx.setTransform(1, 0, 0, 1, 0, 0); _ctx.clearRect(0, 0, _canvas.width, _canvas.height); } _baseTransform(); },

    // ---- Rectangles ----
    ClearRect: function (x, y, w, h) { _ctx.clearRect(x, y, w, h); },
    FillRect: function (x, y, w, h) { _ctx.fillRect(x, y, w, h); },
    StrokeRect: function (x, y, w, h) { _ctx.strokeRect(x, y, w, h); },

    // ---- Path building ----
    BeginPath: function () { _ctx.beginPath(); },
    ClosePath: function () { _ctx.closePath(); },
    MoveTo: function (x, y) { _ctx.moveTo(x, y); },
    LineTo: function (x, y) { _ctx.lineTo(x, y); },
    Arc: function (x, y, r, a0, a1, ccw) { _ctx.arc(x, y, r, a0, a1, !!ccw); },
    ArcTo: function (x1, y1, x2, y2, r) { _ctx.arcTo(x1, y1, x2, y2, r); },
    BezierCurveTo: function (c1x, c1y, c2x, c2y, x, y) { _ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x, y); },
    QuadraticCurveTo: function (cx, cy, x, y) { _ctx.quadraticCurveTo(cx, cy, x, y); },
    Ellipse: function (x, y, rx, ry, rot, a0, a1, ccw) { _ctx.ellipse(x, y, rx, ry, rot, a0, a1, !!ccw); },
    Rect: function (x, y, w, h) { _ctx.rect(x, y, w, h); },
    RoundRect: function (x, y, w, h, r) { _ctx.roundRect(x, y, w, h, r); },
    RoundRect4: function (x, y, w, h, tl, tr, br, bl) { _ctx.roundRect(x, y, w, h, [tl, tr, br, bl]); },

    // ---- Path drawing ----
    Fill: function () { _ctx.fill(); },
    FillRule: function (rulePtr) { _ctx.fill(WKL.readCStr(rulePtr)); },
    Stroke: function () { _ctx.stroke(); },
    Clip: function () { _ctx.clip(); },
    ClipRule: function (rulePtr) { _ctx.clip(WKL.readCStr(rulePtr)); },
    FillPath: function (p) { _ctx.fill(P.get(p)); },
    FillPathRule: function (p, rulePtr) { _ctx.fill(P.get(p), WKL.readCStr(rulePtr)); },
    StrokePath: function (p) { _ctx.stroke(P.get(p)); },
    ClipPath: function (p) { _ctx.clip(P.get(p)); },
    // isPointIn* take the point in raw canvas coords (transform ignored), so
    // scale the logical point by dpr to match the dpr-scaled path.
    IsPointInPath: function (x, y) { return _ctx.isPointInPath(x * _dpr, y * _dpr) ? 1 : 0; },
    IsPointInPathRule: function (x, y, rulePtr) { return _ctx.isPointInPath(x * _dpr, y * _dpr, WKL.readCStr(rulePtr)) ? 1 : 0; },
    IsPointInStroke: function (x, y) { return _ctx.isPointInStroke(x * _dpr, y * _dpr) ? 1 : 0; },
    IsPointInPath2D: function (p, x, y) { return _ctx.isPointInPath(P.get(p), x * _dpr, y * _dpr) ? 1 : 0; },
    IsPointInStroke2D: function (p, x, y) { return _ctx.isPointInStroke(P.get(p), x * _dpr, y * _dpr) ? 1 : 0; },

    // ---- Path2D objects ----
    PathCreate: function () { return P.alloc(new Path2D()); },
    PathCreateSVG: function (dPtr) { return P.alloc(new Path2D(WKL.readCStr(dPtr))); },
    PathRelease: function (p) { P.release(p); },
    PathMoveTo: function (p, x, y) { P.get(p).moveTo(x, y); },
    PathLineTo: function (p, x, y) { P.get(p).lineTo(x, y); },
    PathArc: function (p, x, y, r, a0, a1, ccw) { P.get(p).arc(x, y, r, a0, a1, !!ccw); },
    PathArcTo: function (p, x1, y1, x2, y2, r) { P.get(p).arcTo(x1, y1, x2, y2, r); },
    PathBezierCurveTo: function (p, c1x, c1y, c2x, c2y, x, y) { P.get(p).bezierCurveTo(c1x, c1y, c2x, c2y, x, y); },
    PathQuadraticCurveTo: function (p, cx, cy, x, y) { P.get(p).quadraticCurveTo(cx, cy, x, y); },
    PathEllipse: function (p, x, y, rx, ry, rot, a0, a1, ccw) { P.get(p).ellipse(x, y, rx, ry, rot, a0, a1, !!ccw); },
    PathRect: function (p, x, y, w, h) { P.get(p).rect(x, y, w, h); },
    PathRoundRect: function (p, x, y, w, h, r) { P.get(p).roundRect(x, y, w, h, r); },
    PathClosePath: function (p) { P.get(p).closePath(); },
    PathAddPath: function (dst, src) { P.get(dst).addPath(P.get(src)); },

    // ---- Line styles ----
    SetLineWidth: function (w) { _ctx.lineWidth = w; },
    GetLineWidth: function () { return _ctx.lineWidth; },
    SetLineCap: function (capPtr) { _ctx.lineCap = WKL.readCStr(capPtr); },
    SetLineJoin: function (jPtr) { _ctx.lineJoin = WKL.readCStr(jPtr); },
    SetMiterLimit: function (m) { _ctx.miterLimit = m; },
    SetLineDash: function (segs, count) {
      var view = new Float64Array(_mem(), Number(segs), count);
      _ctx.setLineDash(Array.from(view));
    },
    SetLineDashOffset: function (o) { _ctx.lineDashOffset = o; },

    // ---- Fill / stroke style ----
    SetFillStyle: function (cssPtr) { _ctx.fillStyle = WKL.readCStr(cssPtr); },
    SetStrokeStyle: function (cssPtr) { _ctx.strokeStyle = WKL.readCStr(cssPtr); },
    SetFillRGB: function (r, g, b) { _ctx.fillStyle = _rgb(r, g, b); },
    SetStrokeRGB: function (r, g, b) { _ctx.strokeStyle = _rgb(r, g, b); },
    SetFillGradient: function (g) { _ctx.fillStyle = G.get(g); },
    SetStrokeGradient: function (g) { _ctx.strokeStyle = G.get(g); },
    SetFillPattern: function (p) { _ctx.fillStyle = G.get(p); },
    SetStrokePattern: function (p) { _ctx.strokeStyle = G.get(p); },

    // ---- Gradients / patterns ----
    CreateLinearGradient: function (x0, y0, x1, y1) { return G.alloc(_ctx.createLinearGradient(x0, y0, x1, y1)); },
    CreateRadialGradient: function (x0, y0, r0, x1, y1, r1) { return G.alloc(_ctx.createRadialGradient(x0, y0, r0, x1, y1, r1)); },
    CreateConicGradient: function (a, x, y) { return G.alloc(_ctx.createConicGradient(a, x, y)); },
    AddColorStop: function (g, off, cssPtr) { G.get(g).addColorStop(off, WKL.readCStr(cssPtr)); },
    CreatePattern: function (namePtr, repPtr) {
      var bmp = _bitmap(namePtr);
      if (!bmp) { return 0; }
      return G.alloc(_ctx.createPattern(bmp, WKL.readCStr(repPtr)));
    },
    GradientRelease: function (g) { G.release(g); },
    PatternRelease: function (p) { G.release(p); },

    // ---- Compositing / alpha / filter ----
    SetGlobalAlpha: function (a) { _ctx.globalAlpha = a; },
    GetGlobalAlpha: function () { return _ctx.globalAlpha; },
    SetGlobalCompositeOperation: function (opPtr) { _ctx.globalCompositeOperation = WKL.readCStr(opPtr); },
    SetFilter: function (cssPtr) { _ctx.filter = WKL.readCStr(cssPtr); },

    // ---- Shadows ----
    SetShadowColor: function (cssPtr) { _ctx.shadowColor = WKL.readCStr(cssPtr); },
    // Shadow blur/offset ignore the transform: scale by dpr to stay logical.
    SetShadowBlur: function (b) { _ctx.shadowBlur = b * _dpr; },
    SetShadowOffsetX: function (x) { _ctx.shadowOffsetX = x * _dpr; },
    SetShadowOffsetY: function (y) { _ctx.shadowOffsetY = y * _dpr; },

    // ---- Text ----
    SetFont: function (cssPtr) { _ctx.font = WKL.readCStr(cssPtr); },
    SetTextAlign: function (aPtr) { _ctx.textAlign = WKL.readCStr(aPtr); },
    SetTextBaseline: function (bPtr) { _ctx.textBaseline = WKL.readCStr(bPtr); },
    SetDirection: function (dPtr) { _ctx.direction = WKL.readCStr(dPtr); },
    SetLetterSpacing: function (cssPtr) { _ctx.letterSpacing = WKL.readCStr(cssPtr); },
    SetWordSpacing: function (cssPtr) { _ctx.wordSpacing = WKL.readCStr(cssPtr); },
    SetFontKerning: function (kPtr) { _ctx.fontKerning = WKL.readCStr(kPtr); },
    SetFontStretch: function (sPtr) { _ctx.fontStretch = WKL.readCStr(sPtr); },
    SetTextRendering: function (rPtr) { _ctx.textRendering = WKL.readCStr(rPtr); },
    SetFontVariantCaps: function (vPtr) { _ctx.fontVariantCaps = WKL.readCStr(vPtr); },
    GetTextPropInto: function (id, buf, size) {   // returns BigInt
      return WKL.writeCStr(String(_ctx[_TEXT_PROPS[id]]), buf, size);
    },
    FillTextLines: function (tPtr, x, y, lh) { return _drawLines(WKL.readCStr(tPtr).split('\n'), x, y, lh, false); },
    StrokeTextLines: function (tPtr, x, y, lh) { return _drawLines(WKL.readCStr(tPtr).split('\n'), x, y, lh, true); },
    FillTextWrapped: function (tPtr, x, y, mw, lh) { return _drawLines(_wrap(WKL.readCStr(tPtr), mw), x, y, lh, false); },
    StrokeTextWrapped: function (tPtr, x, y, mw, lh) { return _drawLines(_wrap(WKL.readCStr(tPtr), mw), x, y, lh, true); },
    // Embedded font: FontFace from asset bytes, registered on document.fonts when loaded.
    LoadFont: function (famPtr, assetPtr) {
      var name = WKL.readCStr(assetPtr);
      if (!WaskalAssets.exists(name)) { console.warn('canvas2d: no font asset "' + name + '"'); return 0; }
      var ff = new FontFace(WKL.readCStr(famPtr), WaskalAssets.bytes(name));
      _fontsPending++;
      ff.load().then(function (f) { document.fonts.add(f); })
        .catch(function (e) { console.warn('canvas2d: font load failed "' + name + '": ' + e); })
        .finally(function () { _fontsPending--; });
      return 1;
    },
    FontsReady: function () { return _fontsPending === 0 ? 1 : 0; },
    FillText: function (tPtr, x, y) { _ctx.fillText(WKL.readCStr(tPtr), x, y); },
    FillTextMax: function (tPtr, x, y, mw) { _ctx.fillText(WKL.readCStr(tPtr), x, y, mw); },
    StrokeText: function (tPtr, x, y) { _ctx.strokeText(WKL.readCStr(tPtr), x, y); },
    StrokeTextMax: function (tPtr, x, y, mw) { _ctx.strokeText(WKL.readCStr(tPtr), x, y, mw); },
    MeasureTextWidth: function (tPtr) { return _ctx.measureText(WKL.readCStr(tPtr)).width; },
    MeasureTextInto: function (tPtr, outPtr) {
      // 12 f64 fields, little-endian, same order as TextMetrics in canvas2d.wkl
      var m = _ctx.measureText(WKL.readCStr(tPtr));
      var f = [m.width, m.actualBoundingBoxLeft, m.actualBoundingBoxRight,
               m.actualBoundingBoxAscent, m.actualBoundingBoxDescent,
               m.fontBoundingBoxAscent, m.fontBoundingBoxDescent,
               m.emHeightAscent, m.emHeightDescent,
               m.hangingBaseline, m.alphabeticBaseline, m.ideographicBaseline];
      for (var i = 0; i < 12; i++) { _writeF64(outPtr, i * 8, f[i] || 0); }
    },

    // ---- Transforms ----
    Translate: function (x, y) { _ctx.translate(x, y); },
    Rotate: function (a) { _ctx.rotate(a); },
    Scale: function (x, y) { _ctx.scale(x, y); },
    // User transforms are in logical space and compose on top of the dpr base:
    // ctx = scale(dpr) * M.  GetTransform returns M (base divided out).
    Transform: function (a, b, c, d, e, f) { _ctx.transform(a, b, c, d, e, f); },
    SetTransform: function (a, b, c, d, e, f) { _baseTransform(); _ctx.transform(a, b, c, d, e, f); },
    ResetTransform: function () { _baseTransform(); },
    GetTransform: function (outPtr) {
      var t = _ctx.getTransform();
      var f = [t.a / _dpr, t.b / _dpr, t.c / _dpr, t.d / _dpr, t.e / _dpr, t.f / _dpr];
      for (var i = 0; i < 6; i++) { _writeF64(outPtr, i * 8, f[i]); }
    },

    // ---- Images (embedded assets by name) ----
    DrawImage: function (namePtr, dx, dy) { var b = _bitmap(namePtr); if (b) { _ctx.drawImage(b, dx, dy); } },
    DrawImageSize: function (namePtr, dx, dy, dw, dh) { var b = _bitmap(namePtr); if (b) { _ctx.drawImage(b, dx, dy, dw, dh); } },
    DrawImageRect: function (namePtr, sx, sy, sw, sh, dx, dy, dw, dh) { var b = _bitmap(namePtr); if (b) { _ctx.drawImage(b, sx, sy, sw, sh, dx, dy, dw, dh); } },
    SetImageSmoothingEnabled: function (on) { _ctx.imageSmoothingEnabled = !!on; },
    SetImageSmoothingQuality: function (qPtr) { _ctx.imageSmoothingQuality = WKL.readCStr(qPtr); },
    ImageWidth: function (namePtr) { var b = _bitmap(namePtr); return b ? b.width : 0; },
    ImageHeight: function (namePtr) { var b = _bitmap(namePtr); return b ? b.height : 0; },

    // ---- Pixels (ImageData) ----
    // Positions and sizes are logical pixels (scaled by dpr here); the pixel
    // buffer itself is backing pixels, so ImageDataWidth/Height are dpr-dense.
    CreateImageData: function (w, h) { return D.alloc(_ctx.createImageData(Math.round(w * _dpr), Math.round(h * _dpr))); },
    GetImageData: function (x, y, w, h) {
      return D.alloc(_ctx.getImageData(Math.round(x * _dpr), Math.round(y * _dpr), Math.round(w * _dpr), Math.round(h * _dpr)));
    },
    ImageDataWidth: function (d) { return D.get(d).width; },
    ImageDataHeight: function (d) { return D.get(d).height; },
    ImageDataRead: function (d, buf, size) {   // returns BigInt
      var src = D.get(d).data;
      var n = Math.min(src.length, Number(size));
      new Uint8Array(_mem(), Number(buf), n).set(src.subarray(0, n));
      return BigInt(src.length);
    },
    ImageDataWrite: function (d, buf, size) {
      var dst = D.get(d).data;
      var n = Math.min(dst.length, Number(size));
      dst.set(new Uint8Array(_mem(), Number(buf), n));
    },
    PutImageData: function (d, dx, dy) { _ctx.putImageData(D.get(d), Math.round(dx * _dpr), Math.round(dy * _dpr)); },
    PutImageDataDirty: function (d, dx, dy, x, y, w, h) {
      _ctx.putImageData(D.get(d), Math.round(dx * _dpr), Math.round(dy * _dpr),
        Math.round(x * _dpr), Math.round(y * _dpr), Math.round(w * _dpr), Math.round(h * _dpr));
    },
    ImageDataRelease: function (d) { D.release(d); }
  };
})();
