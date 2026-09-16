/*******************************************************************************
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  dom.js

  DOM standard library host shim. Element handles via WKL.handles(),
  strings in via WKL.readCStr, strings out via caller buffer + WKL.writeCStr.
  Geometry/sizes f64, counts/handles/bools i32. i64 never crosses into DOM.
*******************************************************************************/

var dom = (function () {
  'use strict';

  var E = WKL.handles();     // Element handles
  var _evq = {};             // event queues: key = handle + ':' + type
  var _listeners = {};       // active listeners: same key -> { fn, type, elem }
  var _lastEv = null;        // last popped event object

  function _mem() { return WKL_WASM.exports.memory.buffer; }

  function _release(h) {
    try {
      var key;
      for (key in _listeners) {
        if (key.indexOf(h + ':') === 0) {
          var info = _listeners[key];
          var el = E.get(h);
          if (el) el.removeEventListener(info.type, info.fn);
          delete _listeners[key];
          delete _evq[key];
        }
      }
      E.release(h);
    } catch (e) {}
  }

  // ---- Element Lifecycle ----

  return {

    Create: function (tagPtr) {
      try {
        var el = document.createElement(WKL.readCStr(tagPtr));
        return E.alloc(el);
      } catch (e) { return 0; }
    },

    Query: function (selPtr) {
      try {
        var el = document.querySelector(WKL.readCStr(selPtr));
        return el ? E.alloc(el) : 0;
      } catch (e) { return 0; }
    },

    Body: function () {
      try { return document.body ? E.alloc(document.body) : 0; }
      catch (e) { return 0; }
    },

    Release: function (h) {
      _release(h);
    },

    Remove: function (h) {
      try {
        var el = E.get(h);
        if (el && el.parentNode) el.parentNode.removeChild(el);
      } catch (e) {}
      _release(h);
    },

    // ---- Tree Operations ----

    AppendTo: function (childH, parentH) {
      try {
        var c = E.get(childH), p = E.get(parentH);
        if (p && c) p.appendChild(c);
      } catch (e) {}
    },

    InsertBefore: function (newH, refH) {
      try {
        var n = E.get(newH), r = E.get(refH);
        if (n && r && r.parentNode) r.parentNode.insertBefore(n, r);
      } catch (e) {}
    },

    Clone: function (h) {
      try {
        var el = E.get(h);
        return el ? E.alloc(el.cloneNode(true)) : 0;
      } catch (e) { return 0; }
    },

    Parent: function (h) {
      try {
        var el = E.get(h);
        return (el && el.parentNode && el.parentNode.nodeType === 1)
          ? E.alloc(el.parentNode) : 0;
      } catch (e) { return 0; }
    },

    FirstChild: function (h) {
      try {
        var el = E.get(h);
        if (!el) return 0;
        var c = el.firstElementChild;
        return c ? E.alloc(c) : 0;
      } catch (e) { return 0; }
    },

    NextSibling: function (h) {
      try {
        var el = E.get(h);
        if (!el) return 0;
        var s = el.nextElementSibling;
        return s ? E.alloc(s) : 0;
      } catch (e) { return 0; }
    },

    ChildCount: function (h) {
      try {
        var el = E.get(h);
        return el ? el.children.length : 0;
      } catch (e) { return 0; }
    },

    // ---- Attributes and Content ----

    SetAttr: function (h, namePtr, valPtr) {
      try {
        var el = E.get(h);
        if (el) el.setAttribute(WKL.readCStr(namePtr), WKL.readCStr(valPtr));
      } catch (e) {}
    },

    GetAttr: function (h, namePtr, buf, size) {   // returns BigInt
      try {
        var el = E.get(h);
        if (!el) return WKL.writeCStr('', buf, size);
        var v = el.getAttribute(WKL.readCStr(namePtr));
        return WKL.writeCStr(v || '', buf, size);
      } catch (e) { return WKL.writeCStr('', buf, size); }
    },

    RemoveAttr: function (h, namePtr) {
      try {
        var el = E.get(h);
        if (el) el.removeAttribute(WKL.readCStr(namePtr));
      } catch (e) {}
    },

    HasAttr: function (h, namePtr) {
      try {
        var el = E.get(h);
        return el ? (el.hasAttribute(WKL.readCStr(namePtr)) ? 1 : 0) : 0;
      } catch (e) { return 0; }
    },

    SetText: function (h, textPtr) {
      try {
        var el = E.get(h);
        if (el) el.textContent = WKL.readCStr(textPtr);
      } catch (e) {}
    },

    GetText: function (h, buf, size) {   // returns BigInt
      try {
        var el = E.get(h);
        return WKL.writeCStr(el ? (el.textContent || '') : '', buf, size);
      } catch (e) { return WKL.writeCStr('', buf, size); }
    },

    SetHTML: function (h, htmlPtr) {
      try {
        var el = E.get(h);
        if (el) el.innerHTML = WKL.readCStr(htmlPtr);
      } catch (e) {}
    },

    GetHTML: function (h, buf, size) {   // returns BigInt
      try {
        var el = E.get(h);
        return WKL.writeCStr(el ? (el.innerHTML || '') : '', buf, size);
      } catch (e) { return WKL.writeCStr('', buf, size); }
    },

    SetValue: function (h, valPtr) {
      try {
        var el = E.get(h);
        if (el) el.value = WKL.readCStr(valPtr);
      } catch (e) {}
    },

    GetValue: function (h, buf, size) {   // returns BigInt
      try {
        var el = E.get(h);
        return WKL.writeCStr(el ? (el.value || '') : '', buf, size);
      } catch (e) { return WKL.writeCStr('', buf, size); }
    },

    // ---- CSS / Classes ----

    SetStyle: function (h, propPtr, valPtr) {
      try {
        var el = E.get(h);
        if (el) el.style.setProperty(WKL.readCStr(propPtr), WKL.readCStr(valPtr));
      } catch (e) {}
    },

    GetStyle: function (h, propPtr, buf, size) {   // returns BigInt
      try {
        var el = E.get(h);
        if (!el) return WKL.writeCStr('', buf, size);
        var v = el.style.getPropertyValue(WKL.readCStr(propPtr));
        return WKL.writeCStr(v || '', buf, size);
      } catch (e) { return WKL.writeCStr('', buf, size); }
    },

    AddClass: function (h, clsPtr) {
      try {
        var el = E.get(h);
        if (el) el.classList.add(WKL.readCStr(clsPtr));
      } catch (e) {}
    },

    RemoveClass: function (h, clsPtr) {
      try {
        var el = E.get(h);
        if (el) el.classList.remove(WKL.readCStr(clsPtr));
      } catch (e) {}
    },

    HasClass: function (h, clsPtr) {
      try {
        var el = E.get(h);
        return el ? (el.classList.contains(WKL.readCStr(clsPtr)) ? 1 : 0) : 0;
      } catch (e) { return 0; }
    },

    ToggleClass: function (h, clsPtr) {
      try {
        var el = E.get(h);
        if (el) el.classList.toggle(WKL.readCStr(clsPtr));
      } catch (e) {}
    },

    // ---- Visibility and Focus ----

    Show: function (h) {
      try {
        var el = E.get(h);
        if (el) el.style.display = '';
      } catch (e) {}
    },

    Hide: function (h) {
      try {
        var el = E.get(h);
        if (el) el.style.display = 'none';
      } catch (e) {}
    },

    IsVisible: function (h) {
      try {
        var el = E.get(h);
        if (!el) return 0;
        return (el.style.display !== 'none' && el.offsetParent !== null) ? 1 : 0;
      } catch (e) { return 0; }
    },

    Focus: function (h) {
      try { var el = E.get(h); if (el) el.focus(); } catch (e) {}
    },

    Blur: function (h) {
      try { var el = E.get(h); if (el) el.blur(); } catch (e) {}
    },

    Enable: function (h) {
      try { var el = E.get(h); if (el) el.disabled = false; } catch (e) {}
    },

    Disable: function (h) {
      try { var el = E.get(h); if (el) el.disabled = true; } catch (e) {}
    },

    IsEnabled: function (h) {
      try {
        var el = E.get(h);
        return (el && !el.disabled) ? 1 : 0;
      } catch (e) { return 0; }
    },

    // ---- Geometry (read-only, getBoundingClientRect) ----

    GetX: function (h) {
      try { var el = E.get(h); return el ? el.getBoundingClientRect().left : 0.0; }
      catch (e) { return 0.0; }
    },

    GetY: function (h) {
      try { var el = E.get(h); return el ? el.getBoundingClientRect().top : 0.0; }
      catch (e) { return 0.0; }
    },

    GetWidth: function (h) {
      try { var el = E.get(h); return el ? el.getBoundingClientRect().width : 0.0; }
      catch (e) { return 0.0; }
    },

    GetHeight: function (h) {
      try { var el = E.get(h); return el ? el.getBoundingClientRect().height : 0.0; }
      catch (e) { return 0.0; }
    },

    // ---- Events (poll model) ----

    Listen: function (h, typePtr) {
      try {
        var el = E.get(h);
        if (!el) return;
        var t = WKL.readCStr(typePtr);
        var key = h + ':' + t;
        if (_listeners[key]) return;   // already listening
        var q = [];
        _evq[key] = q;
        var fn = function (ev) {
          q.push({
            clientX: ev.clientX || 0,
            clientY: ev.clientY || 0,
            keyCode: ev.keyCode || 0,
            button:  ev.button  || 0,
            value:   (ev.target && ev.target.value) || ''
          });
        };
        el.addEventListener(t, fn);
        _listeners[key] = { fn: fn, type: t };
      } catch (e) {}
    },

    Unlisten: function (h, typePtr) {
      try {
        var t = WKL.readCStr(typePtr);
        var key = h + ':' + t;
        var info = _listeners[key];
        if (!info) return;
        var el = E.get(h);
        if (el) el.removeEventListener(info.type, info.fn);
        delete _listeners[key];
        delete _evq[key];
      } catch (e) {}
    },

    HasEvent: function (h, typePtr) {
      try {
        var key = h + ':' + WKL.readCStr(typePtr);
        var q = _evq[key];
        return (q && q.length > 0) ? 1 : 0;
      } catch (e) { return 0; }
    },

    NextEvent: function (h, typePtr) {
      try {
        var key = h + ':' + WKL.readCStr(typePtr);
        var q = _evq[key];
        if (!q || q.length === 0) { _lastEv = null; return 0; }
        _lastEv = q.shift();
        return 1;
      } catch (e) { _lastEv = null; return 0; }
    },

    EventX: function () {
      return _lastEv ? _lastEv.clientX : 0.0;
    },

    EventY: function () {
      return _lastEv ? _lastEv.clientY : 0.0;
    },

    EventKeyCode: function () {
      return _lastEv ? _lastEv.keyCode : 0;
    },

    EventButton: function () {
      return _lastEv ? _lastEv.button : 0;
    },

    EventValue: function (buf, size) {   // returns BigInt
      var v = _lastEv ? _lastEv.value : '';
      return WKL.writeCStr(v, buf, size);
    }

  };
})();
