/*******************************************************************************
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  audio.js

  Web Audio shim. Three handle kinds:
    Sound  decoded AudioBuffer from @asset bytes (decodeAudioData, async;
           poll IsReady())
    Voice  one playback of a Sound: BufferSource -> gain -> StereoPanner ->
           sfx bus. Self-releases on 'ended'. No voice cap.
    Music  HTMLAudioElement streamed from WaskalAssets.url, routed through
           createMediaElementSource onto the music bus. One track at a time.
  Buses: master <- sfx, music (three GainNodes).
  Autoplay: the context is created suspended before a user gesture. A
  pointerdown/keydown listener on window resumes it. Before unlock, sfx
  Play is dropped (returns 0) and PlayMusic is queued and starts on unlock.
  Marshalling: volume 0..1, pan -1..1, pitch = playbackRate, all float64;
  handles/bools int32, 0 = none. Every DOM/WebAudio call is try/catch --
  nothing unwinds into wasm. Couples to nothing but WKL / WaskalAssets.
*******************************************************************************/

var audio = (function () {
  var ctx = null, master = null, sfxBus = null, musicBus = null;
  var S = WKL.handles();   // Sound  -> {buffer: AudioBuffer|null}
  var V = WKL.handles();   // Voice  -> {src, gain, pan}
  var M = WKL.handles();   // Music  -> {el, node}
  var _pending = 0;        // decodes in flight
  var _unlocked = false;
  var _cur = 0;            // current music handle, 0 = none
  var _queued = null;      // {m, loop} waiting for unlock
  var _live = [];          // live voice handles (the table has no iterator)

  function ensureCtx() {
    if (ctx) return true;
    try {
      var AC = window.AudioContext || window.webkitAudioContext;
      ctx = new AC();
      master = ctx.createGain();
      sfxBus = ctx.createGain();
      musicBus = ctx.createGain();
      sfxBus.connect(master);
      musicBus.connect(master);
      master.connect(ctx.destination);
      return true;
    } catch (e) { console.warn('audio: no AudioContext: ' + e); ctx = null; return false; }
  }

  function onUnlocked() {
    if (_unlocked) return;
    _unlocked = true;
    window.removeEventListener('pointerdown', tryUnlock);
    window.removeEventListener('keydown', tryUnlock);
    if (_queued) { var q = _queued; _queued = null; startMusic(q.m, q.loop); }
  }

  function tryUnlock() {
    if (!ensureCtx()) return;
    if (ctx.state === 'running') { onUnlocked(); return; }
    try { ctx.resume().then(function () { if (ctx.state === 'running') onUnlocked(); }).catch(function () { }); }
    catch (e) { }
  }

  window.addEventListener('pointerdown', tryUnlock);
  window.addEventListener('keydown', tryUnlock);

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  function setGain(g, v) {
    try { g.gain.cancelScheduledValues(ctx.currentTime); g.gain.setValueAtTime(clamp(v, 0, 1), ctx.currentTime); } catch (e) { }
  }

  function stopVoice(h) {
    var v = V.get(h);
    if (!v) return;
    try { v.src.onended = null; v.src.stop(); } catch (e) { }
    try { v.src.disconnect(); v.gain.disconnect(); v.pan.disconnect(); } catch (e) { }
    V.release(h);
    var i = _live.indexOf(h);
    if (i >= 0) _live.splice(i, 1);
  }

  function startMusic(h, loop) {
    var m = M.get(h);
    if (!m) return;
    if (_cur && _cur !== h) stopMusic();
    _cur = h;
    try { m.el.loop = !!loop; m.el.currentTime = 0; m.el.play().catch(function (e) { console.warn('audio: music play: ' + e); }); }
    catch (e) { }
  }

  function stopMusic() {
    var m = M.get(_cur);
    _cur = 0;
    if (!m) return;
    try { m.el.pause(); m.el.currentTime = 0; } catch (e) { }
  }

  return {
    // ---- context ----
    Unlock: function () { tryUnlock(); return (ctx && ctx.state === 'running') ? 1 : 0; },
    IsReady: function () { return _pending === 0 ? 1 : 0; },

    // ---- sounds (sfx) ----
    LoadSound: function (assetPtr) {
      var name = WKL.readCStr(assetPtr);
      if (!WaskalAssets.exists(name)) { console.warn('audio: no sound asset "' + name + '"'); return 0; }
      if (!ensureCtx()) return 0;
      var h = S.alloc({ buffer: null });   // handle is live during decode; buffer lands later
      _pending++;
      try {
        // copy: decodeAudioData detaches its input, and bytes() is a view on the shared asset buffer
        var buf = WaskalAssets.bytes(name).slice().buffer;
        ctx.decodeAudioData(buf)
          .then(function (ab) { var e = S.get(h); if (e) e.buffer = ab; })
          .catch(function (e) { console.warn('audio: decode failed "' + name + '": ' + e); })
          .finally(function () { _pending--; });
      } catch (e) { _pending--; }
      return h;
    },
    ReleaseSound: function (h) { S.release(h); },
    Play: function (s) { return audio.PlayEx(s, 1.0, 1.0, 0.0, 0); },
    PlayEx: function (s, volume, pitch, pan, loop) {
      var e = S.get(s);
      var ab = e ? e.buffer : null;
      if (!ab || !_unlocked) return 0;
      try {
        var src = ctx.createBufferSource();
        var g = ctx.createGain();
        var p = ctx.createStereoPanner();
        src.buffer = ab;
        src.loop = !!loop;
        src.playbackRate.value = pitch > 0 ? pitch : 1.0;
        g.gain.value = clamp(volume, 0, 1);
        p.pan.value = clamp(pan, -1, 1);
        src.connect(g); g.connect(p); p.connect(sfxBus);
        var h = V.alloc({ src: src, gain: g, pan: p });
        _live.push(h);
        src.onended = function () { stopVoice(h); };
        src.start();
        return h;
      } catch (err) { console.warn('audio: PlayEx: ' + err); return 0; }
    },
    StopVoice: function (h) { stopVoice(h); },
    SetVoiceVolume: function (h, v) { var x = V.get(h); if (x) setGain(x.gain, v); },
    SetVoicePan: function (h, p) { var x = V.get(h); if (x) { try { x.pan.pan.setValueAtTime(clamp(p, -1, 1), ctx.currentTime); } catch (e) { } } },
    SetVoicePitch: function (h, r) { var x = V.get(h); if (x) { try { x.src.playbackRate.setValueAtTime(r > 0 ? r : 1.0, ctx.currentTime); } catch (e) { } } },
    IsVoicePlaying: function (h) { return V.get(h) ? 1 : 0; },
    StopAllSounds: function () {
      for (var i = _live.length - 1; i >= 0; i--) stopVoice(_live[i]);
    },

    // ---- music ----
    LoadMusic: function (assetPtr) {
      var name = WKL.readCStr(assetPtr);
      if (!WaskalAssets.exists(name)) { console.warn('audio: no music asset "' + name + '"'); return 0; }
      if (!ensureCtx()) return 0;
      try {
        var el = new Audio(WaskalAssets.url(name));
        el.preload = 'auto';
        var node = ctx.createMediaElementSource(el);
        node.connect(musicBus);
        return M.alloc({ el: el, node: node });
      } catch (e) { console.warn('audio: LoadMusic: ' + e); return 0; }
    },
    ReleaseMusic: function (h) {
      if (h === _cur) stopMusic();
      var m = M.get(h);
      if (!m) return;
      try { m.node.disconnect(); m.el.src = ''; } catch (e) { }
      M.release(h);
    },
    PlayMusic: function (h, loop) {
      if (!M.get(h)) return;
      if (!_unlocked) { _queued = { m: h, loop: loop }; return; }
      startMusic(h, loop);
    },
    StopMusic: function () { _queued = null; stopMusic(); },
    PauseMusic: function () { var m = M.get(_cur); if (m) { try { m.el.pause(); } catch (e) { } } },
    ResumeMusic: function () { var m = M.get(_cur); if (m && _unlocked) { try { m.el.play().catch(function () { }); } catch (e) { } } },
    IsMusicPlaying: function () { var m = M.get(_cur); return (m && !m.el.paused && !m.el.ended) ? 1 : 0; },
    MusicPosition: function () { var m = M.get(_cur); return m ? (m.el.currentTime || 0) : 0; },
    MusicDuration: function () { var m = M.get(_cur); return (m && isFinite(m.el.duration)) ? m.el.duration : 0; },
    SeekMusic: function (sec) { var m = M.get(_cur); if (m) { try { m.el.currentTime = sec < 0 ? 0 : sec; } catch (e) { } } },
    FadeMusic: function (toVolume, seconds) {
      if (!ctx) return;
      try {
        var t = ctx.currentTime;
        musicBus.gain.cancelScheduledValues(t);
        musicBus.gain.setValueAtTime(musicBus.gain.value, t);
        musicBus.gain.linearRampToValueAtTime(clamp(toVolume, 0, 1), t + (seconds > 0 ? seconds : 0));
      } catch (e) { }
    },

    // ---- buses ----
    SetMasterVolume: function (v) { if (ensureCtx()) setGain(master, v); },
    SetSfxVolume: function (v) { if (ensureCtx()) setGain(sfxBus, v); },
    SetMusicVolume: function (v) { if (ensureCtx()) setGain(musicBus, v); },
    GetMasterVolume: function () { return master ? master.gain.value : 1.0; },
    GetSfxVolume: function () { return sfxBus ? sfxBus.gain.value : 1.0; },
    GetMusicVolume: function () { return musicBus ? musicBus.gain.value : 1.0; }
  };
})();
