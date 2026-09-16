/*******************************************************************************
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  localstorage.js

  Wraps window.localStorage. Every key is prefixed with the module name
  (WKL.moduleName + ":") because file:// pages all share one origin, so two
  Waskal apps opened from disk would otherwise see each other's keys.
  Length/Key/Clear only see this app's prefixed keys. Every storage access
  is wrapped in try/catch -- a DOMException (quota, security) must never
  unwind into wasm. Routines declared int64 in localstorage.wkl return
  BigInt; int32/bool routines return Number.
*******************************************************************************/

var localstorage = (function () {
  var P = null;                                   // prefix, resolved on first use

  function prefix() {
    if (P === null) P = WKL.moduleName + ":";
    return P;
  }

  function ls() {
    try { return window.localStorage; } catch (e) { return null; }
  }

  // This app's keys (prefix stripped), in storage order.
  function mine() {
    var s = ls(), out = [];
    if (!s) return out;
    var p = prefix();
    try {
      for (var i = 0; i < s.length; i++) {
        var k = s.key(i);
        if (k && k.indexOf(p) === 0) out.push(k.substring(p.length));
      }
    } catch (e) { }
    return out;
  }

  function getRaw(k) {
    var s = ls();
    if (!s) return null;
    try { return s.getItem(prefix() + WKL.readCStr(k)); } catch (e) { return null; }
  }

  function setRaw(k, v) {
    var s = ls();
    if (!s) return 0;
    try { s.setItem(prefix() + WKL.readCStr(k), v); return 1; } catch (e) { return 0; }
  }

  return {
    Available: function () {
      var s = ls();
      if (!s) return 0;
      try { s.setItem(prefix() + "__probe", "1"); s.removeItem(prefix() + "__probe"); return 1; }
      catch (e) { return 0; }
    },
    SetItem: function (k, v) { return setRaw(k, WKL.readCStr(v)); },
    GetItemInto: function (k, buf, size) {        // returns BigInt
      var v = getRaw(k);
      if (v === null) return -1n;
      return WKL.writeCStr(v, buf, size);
    },
    RemoveItem: function (k) {
      var s = ls();
      if (!s) return;
      try { s.removeItem(prefix() + WKL.readCStr(k)); } catch (e) { }
    },
    Clear: function () {
      var s = ls();
      if (!s) return;
      var keys = mine();
      try { for (var i = 0; i < keys.length; i++) s.removeItem(prefix() + keys[i]); } catch (e) { }
    },
    Length: function () { return mine().length; },
    KeyInto: function (index, buf, size) {        // returns BigInt
      var keys = mine();
      if (index < 0 || index >= keys.length) return -1n;
      return WKL.writeCStr(keys[index], buf, size);
    },
    HasItem: function (k) { return getRaw(k) === null ? 0 : 1; },

    // Typed helpers. int64 arrives as BigInt; String()/BigInt() are exact.
    SetInt: function (k, v) { return setRaw(k, String(v)); },
    GetInt: function (k, def) {                   // returns BigInt
      var v = getRaw(k);
      if (v === null) return def;
      try { return BigInt(v); } catch (e) { return def; }
    },
    SetFloat: function (k, v) { return setRaw(k, String(v)); },
    GetFloat: function (k, def) {
      var v = getRaw(k);
      if (v === null) return def;
      var f = Number(v);
      return isNaN(f) ? def : f;
    },
    SetBool: function (k, v) { return setRaw(k, v ? "1" : "0"); },
    GetBool: function (k, def) {
      var v = getRaw(k);
      if (v === null) return def;
      return v === "1" ? 1 : 0;
    }
  };
})();
