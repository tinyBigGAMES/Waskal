/*!*****************************************************************************
  Waskal(tm) Programming Language

  Copyright (c) 2026-present tinyBigGAMES(tm) LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  runtime.js - JavaScript Runtime

  The JS-side runtime for Waskal applications. Contains:
    - WASI preview1 shim for memory64 (wasm64), forked from
      @bjorn3/browser_wasi_shim v0.4.2 (MIT OR Apache-2.0)
    - Embedded asset system (decode, preload, accessors, fetch patch,
      wasm import bridge)
 ==============================================================================*/

// ---------------------------------------------------------------------------
// WKL -- shared helpers for every std shim. One copy; shims never redefine.
// ---------------------------------------------------------------------------
var WKL = (function () {
  var enc = new TextEncoder(), dec = new TextDecoder();
  function mem() { return new Uint8Array(WKL_WASM.exports.memory.buffer); }
  return {
    moduleName: "",          // set by index.html from wasi.args[0]
    onLoopEnd: null,         // set by index.html; called by frame.js
    onTick: null,            // set by input.js; called by frame.js at the top of every tick
    canvas: null,            // set by canvas2d.Init/InitOn; read by input.js for mouse mapping
    canvasDpr: 1,            // set by canvas2d (backing px per logical px); read by input.js
    onExit: [],              // callbacks run by index.html after _shutdown; std modules push here (e.g. canvas2d drops app mode)
    // Read a NUL-terminated UTF-8 string at wasm address ptr (BigInt).
    readCStr: function (ptr) {
      var m = mem(), p = Number(ptr), e = p;
      while (m[e] !== 0) e++;
      return dec.decode(m.subarray(p, e));
    },
    // Encode str as UTF-8 into [buf, buf+size). Writes min(len,size-1)
    // bytes + NUL. Returns the FULL byte length as BigInt (size=0 = query).
    writeCStr: function (str, buf, size) {
      var b = enc.encode(str), n = Number(size), p = Number(buf);
      if (n > 0) {
        var k = Math.min(b.length, n - 1), m = mem();
        m.set(b.subarray(0, k), p); m[p + k] = 0;
      }
      return BigInt(b.length);
    },
    // Handle table factory. Index 0 is reserved (= none).
    handles: function () {
      var t = [null], free = [];
      return {
        alloc: function (o) { var h = free.length ? free.pop() : t.length; t[h] = o; return h; },
        get: function (h) { return t[h] || null; },
        release: function (h) { if (h > 0 && t[h]) { t[h] = null; free.push(h); } }
      };
    },
    // Uniform failure path: WASIProcExit is a normal stop, anything else is an error.
    fail: function (e) {
      var exitEl = document.getElementById("exit"), errEl = document.getElementById("err");
      var isExit = !!(e && e.constructor && e.constructor.name === "WASIProcExit");
      if (isExit) {
        if (exitEl) {
          exitEl.textContent = "exit code: " + e.code;
          // Non-zero exit is a failure: surface it even in app mode.
          if (e.code !== 0) exitEl.style.display = "block";
        }
      } else {
        // Always surface a crash, even in app mode where the console is hidden.
        if (errEl) { errEl.style.display = "block"; errEl.textContent += String(e && e.stack ? e.stack : e) + "\n"; }
        if (exitEl) { exitEl.style.display = "block"; exitEl.textContent = "failed"; }
      }
      if (WKL.onLoopEnd) { var f = WKL.onLoopEnd; WKL.onLoopEnd = null; f(!isExit); }
      else WKL.runExit();
    },
    // Fire every onExit callback once (index.html finish, or fail with no loop),
    // then leave app mode so the console and exit status are visible.
    runExit: function () {
      var cbs = WKL.onExit; WKL.onExit = [];
      for (var i = 0; i < cbs.length; i++) { try { cbs[i](); } catch (e) { console.warn("onExit: " + e); } }
      document.body.classList.remove("wkl-app");
    }
  };
})();

// ---------------------------------------------------------------------------
// WASI preview1 shim for memory64
//
// Forked from @bjorn3/browser_wasi_shim v0.4.2 (MIT OR Apache-2.0).
// All pointer and size parameters use BigInt (i64) to match the memory64
// ABI. The fd parameter remains i32 per the WASI spec.
// ---------------------------------------------------------------------------

var WasiShim = (function () {
"use strict";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
var CLOCKID_REALTIME = 0, CLOCKID_MONOTONIC = 1;
var ERRNO_SUCCESS = 0, ERRNO_BADF = 8, ERRNO_INVAL = 28, ERRNO_NOENT = 44,
    ERRNO_NOSYS = 52, ERRNO_NOTSUP = 58, ERRNO_NOTDIR = 54,
    ERRNO_NOTEMPTY = 55, ERRNO_EXIST = 20, ERRNO_NAMETOOLONG = 37,
    ERRNO_ISDIR = 31, ERRNO_PERM = 63, ERRNO_NOTCAPABLE = 76;
var WHENCE_SET = 0, WHENCE_CUR = 1, WHENCE_END = 2;
var FILETYPE_CHARACTER_DEVICE = 2, FILETYPE_DIRECTORY = 3,
    FILETYPE_REGULAR_FILE = 4;
var OFLAGS_CREAT = 1, OFLAGS_DIRECTORY = 2, OFLAGS_EXCL = 4, OFLAGS_TRUNC = 8;
var FDFLAGS_APPEND = 1;
var RIGHTS_FD_WRITE = 64;
var SUBCLOCKFLAGS_SUBSCRIPTION_CLOCK_ABSTIME = 1;
var EVENTTYPE_CLOCK = 0;
var PREOPENTYPE_DIR = 0;

// ---------------------------------------------------------------------------
// Helpers -- read memory64 iovec/ciovec structs (16 bytes each: u64 buf, u64 len)
// ---------------------------------------------------------------------------
function readIovecs(view, ptr, len) {
  var out = [];
  for (var i = 0; i < len; i++) {
    var base = Number(ptr) + i * 16;
    out.push({
      buf: Number(view.getBigUint64(base, true)),
      buf_len: Number(view.getBigUint64(base + 8, true))
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Inode base
// ---------------------------------------------------------------------------
var nextIno = 1n;
function issueIno() { return nextIno++; }

// ---------------------------------------------------------------------------
// File (in-memory)
// ---------------------------------------------------------------------------
function File(data, opts) {
  this.ino = issueIno();
  this.data = new Uint8Array(data);
  this.readonly = !!(opts && opts.readonly);
}
File.prototype.stat = function () {
  return { dev: 0n, ino: this.ino, filetype: FILETYPE_REGULAR_FILE,
           nlink: 0n, size: BigInt(this.data.byteLength),
           atim: 0n, mtim: 0n, ctim: 0n };
};
File.prototype.path_open = function (oflags, fs_rights_base, fd_flags) {
  if (this.readonly && (fs_rights_base & BigInt(RIGHTS_FD_WRITE)) === BigInt(RIGHTS_FD_WRITE))
    return { ret: ERRNO_PERM, fd_obj: null };
  if ((oflags & OFLAGS_TRUNC) === OFLAGS_TRUNC) {
    if (this.readonly) return { ret: ERRNO_PERM, fd_obj: null };
    this.data = new Uint8Array([]);
  }
  var f = new OpenFile(this);
  if (fd_flags & FDFLAGS_APPEND) f.fd_seek(0n, WHENCE_END);
  return { ret: ERRNO_SUCCESS, fd_obj: f };
};
Object.defineProperty(File.prototype, "size", {
  get: function () { return BigInt(this.data.byteLength); }
});

// ---------------------------------------------------------------------------
// OpenFile
// ---------------------------------------------------------------------------
function OpenFile(file) { this.file = file; this.file_pos = 0n; }
OpenFile.prototype.fd_fdstat_get = function () {
  return { ret: 0, fdstat: { fs_filetype: FILETYPE_REGULAR_FILE, fs_flags: 0,
           fs_rights_base: 0n, fs_rights_inherited: 0n } };
};
OpenFile.prototype.fd_filestat_get = function () {
  return { ret: 0, filestat: this.file.stat() };
};
OpenFile.prototype.fd_read = function (size) {
  var s = this.file.data.slice(Number(this.file_pos), Number(this.file_pos + BigInt(size)));
  this.file_pos += BigInt(s.length);
  return { ret: 0, data: s };
};
OpenFile.prototype.fd_pread = function (size, offset) {
  return { ret: 0, data: this.file.data.slice(Number(offset), Number(offset + BigInt(size))) };
};
OpenFile.prototype.fd_seek = function (offset, whence) {
  var c;
  switch (whence) {
    case WHENCE_SET: c = offset; break;
    case WHENCE_CUR: c = this.file_pos + offset; break;
    case WHENCE_END: c = BigInt(this.file.data.byteLength) + offset; break;
    default: return { ret: ERRNO_INVAL, offset: 0n };
  }
  if (c < 0n) return { ret: ERRNO_INVAL, offset: 0n };
  this.file_pos = c;
  return { ret: 0, offset: this.file_pos };
};
OpenFile.prototype.fd_tell = function () {
  return { ret: 0, offset: this.file_pos };
};
OpenFile.prototype.fd_write = function (data) {
  if (this.file.readonly) return { ret: ERRNO_BADF, nwritten: 0 };
  if (this.file_pos + BigInt(data.byteLength) > this.file.size) {
    var old = this.file.data;
    this.file.data = new Uint8Array(Number(this.file_pos + BigInt(data.byteLength)));
    this.file.data.set(old);
  }
  this.file.data.set(data, Number(this.file_pos));
  this.file_pos += BigInt(data.byteLength);
  return { ret: 0, nwritten: data.byteLength };
};
OpenFile.prototype.fd_pwrite = function (data, offset) {
  if (this.file.readonly) return { ret: ERRNO_BADF, nwritten: 0 };
  if (offset + BigInt(data.byteLength) > this.file.size) {
    var old = this.file.data;
    this.file.data = new Uint8Array(Number(offset + BigInt(data.byteLength)));
    this.file.data.set(old);
  }
  this.file.data.set(data, Number(offset));
  return { ret: 0, nwritten: data.byteLength };
};
OpenFile.prototype.fd_allocate = function (offset, len) {
  if (!(this.file.size > offset + len)) {
    var old = this.file.data;
    this.file.data = new Uint8Array(Number(offset + len));
    this.file.data.set(old);
  }
  return ERRNO_SUCCESS;
};
OpenFile.prototype.fd_filestat_set_size = function (size) {
  if (this.file.size > size)
    this.file.data = new Uint8Array(this.file.data.buffer.slice(0, Number(size)));
  else {
    var n = new Uint8Array(Number(size));
    n.set(this.file.data);
    this.file.data = n;
  }
  return ERRNO_SUCCESS;
};
OpenFile.prototype.fd_close = function () { return 0; };
OpenFile.prototype.fd_sync = function () { return 0; };
OpenFile.prototype.fd_prestat_get = function () { return { ret: ERRNO_NOTSUP, prestat: null }; };

// ---------------------------------------------------------------------------
// Directory (in-memory)
// ---------------------------------------------------------------------------
function Directory(contents) {
  this.ino = issueIno();
  this.parent = null;
  this.contents = (contents instanceof Map) ? contents : new Map(contents);
  var self = this;
  this.contents.forEach(function (v) { if (v instanceof Directory) v.parent = self; });
}
Directory.prototype.stat = function () {
  return { dev: 0n, ino: this.ino, filetype: FILETYPE_DIRECTORY,
           nlink: 0n, size: 0n, atim: 0n, mtim: 0n, ctim: 0n };
};
Directory.prototype.parent_ino = function () {
  return this.parent == null ? 0n : this.parent.ino;
};
Directory.prototype.path_open = function () {
  return { ret: ERRNO_SUCCESS, fd_obj: new OpenDirectory(this) };
};
Directory.prototype.get_entry_for_path = function (parts, is_dir) {
  var entry = this;
  for (var i = 0; i < parts.length; i++) {
    if (!(entry instanceof Directory)) return { ret: ERRNO_NOTDIR, entry: null };
    var child = entry.contents.get(parts[i]);
    if (child === undefined) return { ret: ERRNO_NOENT, entry: null };
    entry = child;
  }
  if (is_dir && entry.stat && entry.stat().filetype !== FILETYPE_DIRECTORY)
    return { ret: ERRNO_NOTDIR, entry: null };
  return { ret: ERRNO_SUCCESS, entry: entry };
};
Directory.prototype.create_entry_for_path = function (path_str, is_dir) {
  var parsed = parsePath(path_str);
  if (parsed == null) return { ret: ERRNO_INVAL, entry: null };
  var parts = parsed.parts.slice();
  var filename = parts.pop();
  if (!filename) return { ret: ERRNO_INVAL, entry: null };
  var r = this.get_entry_for_path(parts, true);
  if (r.entry == null) return { ret: r.ret, entry: null };
  if (!(r.entry instanceof Directory)) return { ret: ERRNO_NOTDIR, entry: null };
  if (r.entry.contents.has(filename)) return { ret: ERRNO_EXIST, entry: null };
  var ne;
  if (is_dir) { ne = new Directory(new Map()); ne.parent = r.entry; }
  else ne = new File(new ArrayBuffer(0));
  r.entry.contents.set(filename, ne);
  return { ret: ERRNO_SUCCESS, entry: ne };
};

// ---------------------------------------------------------------------------
// OpenDirectory
// ---------------------------------------------------------------------------
function OpenDirectory(dir) { this.dir = dir; }
OpenDirectory.prototype.fd_fdstat_get = function () {
  return { ret: 0, fdstat: { fs_filetype: FILETYPE_DIRECTORY, fs_flags: 0,
           fs_rights_base: 0n, fs_rights_inherited: 0n } };
};
OpenDirectory.prototype.fd_filestat_get = function () {
  return { ret: 0, filestat: this.dir.stat() };
};
OpenDirectory.prototype.fd_readdir_single = function (cookie) {
  if (cookie === 0n) return { ret: 0, dirent: { d_next: 1n, d_ino: this.dir.ino, d_type: FILETYPE_DIRECTORY, dir_name: new TextEncoder().encode(".") } };
  if (cookie === 1n) return { ret: 0, dirent: { d_next: 2n, d_ino: this.dir.parent_ino(), d_type: FILETYPE_DIRECTORY, dir_name: new TextEncoder().encode("..") } };
  if (cookie >= BigInt(this.dir.contents.size) + 2n) return { ret: 0, dirent: null };
  var arr = Array.from(this.dir.contents.entries());
  var idx = Number(cookie - 2n);
  var name = arr[idx][0], entry = arr[idx][1];
  return { ret: 0, dirent: { d_next: cookie + 1n, d_ino: entry.ino, d_type: entry.stat().filetype, dir_name: new TextEncoder().encode(name) } };
};
OpenDirectory.prototype.path_filestat_get = function (flags, path_str) {
  var p = parsePath(path_str);
  if (p == null) return { ret: ERRNO_INVAL, filestat: null };
  var r = this.dir.get_entry_for_path(p.parts, p.is_dir);
  if (r.entry == null) return { ret: r.ret, filestat: null };
  return { ret: 0, filestat: r.entry.stat() };
};
OpenDirectory.prototype.path_open = function (dirflags, path_str, oflags, fs_rights_base, fs_rights_inheriting, fd_flags) {
  var p = parsePath(path_str);
  if (p == null) return { ret: ERRNO_INVAL, fd_obj: null };
  var r = this.dir.get_entry_for_path(p.parts, p.is_dir);
  if (r.entry == null) {
    if (r.ret !== ERRNO_NOENT) return { ret: r.ret, fd_obj: null };
    if ((oflags & OFLAGS_CREAT) === OFLAGS_CREAT) {
      var cr = this.dir.create_entry_for_path(path_str, (oflags & OFLAGS_DIRECTORY) === OFLAGS_DIRECTORY);
      if (cr.entry == null) return { ret: cr.ret, fd_obj: null };
      r.entry = cr.entry;
    } else return { ret: ERRNO_NOENT, fd_obj: null };
  } else if ((oflags & OFLAGS_EXCL) === OFLAGS_EXCL) return { ret: ERRNO_EXIST, fd_obj: null };
  if ((oflags & OFLAGS_DIRECTORY) === OFLAGS_DIRECTORY && r.entry.stat().filetype !== FILETYPE_DIRECTORY)
    return { ret: ERRNO_NOTDIR, fd_obj: null };
  return r.entry.path_open(oflags, fs_rights_base, fd_flags);
};
OpenDirectory.prototype.path_create_directory = function (path) {
  return this.path_open(0, path, OFLAGS_CREAT | OFLAGS_DIRECTORY, 0n, 0n, 0).ret;
};
OpenDirectory.prototype.path_unlink_file = function (path_str) {
  var p = parsePath(path_str);
  if (p == null) return ERRNO_INVAL;
  var parts = p.parts.slice(); var fn = parts.pop();
  if (!fn) return ERRNO_INVAL;
  var r = this.dir.get_entry_for_path(parts, true);
  if (r.entry == null || !(r.entry instanceof Directory)) return ERRNO_NOTDIR;
  var e = r.entry.contents.get(fn);
  if (e === undefined) return ERRNO_NOENT;
  if (e.stat().filetype === FILETYPE_DIRECTORY) return ERRNO_ISDIR;
  r.entry.contents.delete(fn);
  return ERRNO_SUCCESS;
};
OpenDirectory.prototype.path_remove_directory = function (path_str) {
  var p = parsePath(path_str);
  if (p == null) return ERRNO_INVAL;
  var parts = p.parts.slice(); var fn = parts.pop();
  if (!fn) return ERRNO_INVAL;
  var r = this.dir.get_entry_for_path(parts, true);
  if (r.entry == null || !(r.entry instanceof Directory)) return ERRNO_NOTDIR;
  var e = r.entry.contents.get(fn);
  if (e === undefined) return ERRNO_NOENT;
  if (!(e instanceof Directory)) return ERRNO_NOTDIR;
  if (e.contents.size !== 0) return ERRNO_NOTEMPTY;
  r.entry.contents.delete(fn);
  return ERRNO_SUCCESS;
};
OpenDirectory.prototype.path_lookup = function (path_str) {
  var p = parsePath(path_str);
  if (p == null) return { ret: ERRNO_INVAL, inode_obj: null };
  var r = this.dir.get_entry_for_path(p.parts, p.is_dir);
  return r.entry == null ? { ret: r.ret, inode_obj: null } : { ret: 0, inode_obj: r.entry };
};
OpenDirectory.prototype.path_link = function (path_str, inode, allow_dir) {
  var p = parsePath(path_str);
  if (p == null) return ERRNO_INVAL;
  var parts = p.parts.slice(); var fn = parts.pop();
  if (!fn) return ERRNO_INVAL;
  var r = this.dir.get_entry_for_path(parts, true);
  if (r.entry == null || !(r.entry instanceof Directory)) return ERRNO_NOTDIR;
  r.entry.contents.set(fn, inode);
  return ERRNO_SUCCESS;
};
OpenDirectory.prototype.path_unlink = function (path_str) {
  var p = parsePath(path_str);
  if (p == null) return { ret: ERRNO_INVAL, inode_obj: null };
  var parts = p.parts.slice(); var fn = parts.pop();
  if (!fn) return { ret: ERRNO_INVAL, inode_obj: null };
  var r = this.dir.get_entry_for_path(parts, true);
  if (r.entry == null || !(r.entry instanceof Directory)) return { ret: ERRNO_NOTDIR, inode_obj: null };
  var e = r.entry.contents.get(fn);
  if (e === undefined) return { ret: ERRNO_NOENT, inode_obj: null };
  r.entry.contents.delete(fn);
  return { ret: ERRNO_SUCCESS, inode_obj: e };
};
// Stubs for unsupported operations
OpenDirectory.prototype.fd_close = function () { return 0; };
OpenDirectory.prototype.fd_sync = function () { return 0; };
OpenDirectory.prototype.fd_prestat_get = function () { return { ret: ERRNO_NOTSUP, prestat: null }; };
OpenDirectory.prototype.fd_read = function () { return { ret: ERRNO_BADF, data: new Uint8Array() }; };
OpenDirectory.prototype.fd_write = function () { return { ret: ERRNO_BADF, nwritten: 0 }; };
OpenDirectory.prototype.fd_seek = function () { return { ret: ERRNO_BADF, offset: 0n }; };
OpenDirectory.prototype.fd_tell = function () { return { ret: ERRNO_BADF, offset: 0n }; };

// ---------------------------------------------------------------------------
// PreopenDirectory
// ---------------------------------------------------------------------------
function PreopenDirectory(name, contents) {
  this.dir = new Directory(contents);
  this.prestat_name = name;
  OpenDirectory.call(this, this.dir);
}
PreopenDirectory.prototype = Object.create(OpenDirectory.prototype);
PreopenDirectory.prototype.fd_prestat_get = function () {
  return { ret: 0, prestat: { tag: PREOPENTYPE_DIR, pr_name: new TextEncoder().encode(this.prestat_name) } };
};

// ---------------------------------------------------------------------------
// ConsoleStdout
// ---------------------------------------------------------------------------
function ConsoleStdout(writeFn) {
  this._ino = issueIno();
  this._write = writeFn;
}
ConsoleStdout.prototype.fd_fdstat_get = function () {
  return { ret: 0, fdstat: { fs_filetype: FILETYPE_CHARACTER_DEVICE, fs_flags: 0,
           fs_rights_base: BigInt(RIGHTS_FD_WRITE), fs_rights_inherited: 0n } };
};
ConsoleStdout.prototype.fd_filestat_get = function () {
  return { ret: 0, filestat: { dev: 0n, ino: this._ino, filetype: FILETYPE_CHARACTER_DEVICE,
           nlink: 0n, size: 0n, atim: 0n, mtim: 0n, ctim: 0n } };
};
ConsoleStdout.prototype.fd_write = function (data) {
  this._write(data);
  return { ret: 0, nwritten: data.byteLength };
};
ConsoleStdout.prototype.fd_close = function () { return 0; };
ConsoleStdout.prototype.fd_sync = function () { return 0; };
ConsoleStdout.prototype.fd_prestat_get = function () { return { ret: ERRNO_NOTSUP, prestat: null }; };
ConsoleStdout.lineBuffered = function (writeLine) {
  var dec = new TextDecoder("utf-8", { fatal: false });
  var buf = "";
  return new ConsoleStdout(function (data) {
    buf += dec.decode(data, { stream: true });
    var lines = buf.split("\n");
    for (var i = 0; i < lines.length - 1; i++) writeLine(lines[i]);
    buf = lines[lines.length - 1];
  });
};

// ---------------------------------------------------------------------------
// Path parser
// ---------------------------------------------------------------------------
function parsePath(str) {
  if (str.startsWith("/")) return null;
  if (str.indexOf("\0") >= 0) return null;
  var is_dir = str.endsWith("/");
  var parts = [];
  var segs = str.split("/");
  for (var i = 0; i < segs.length; i++) {
    var s = segs[i];
    if (s === "" || s === ".") continue;
    if (s === "..") { if (parts.length === 0) return null; parts.pop(); continue; }
    parts.push(s);
  }
  return { parts: parts, is_dir: is_dir };
}

// ---------------------------------------------------------------------------
// Filestat writer -- writes a filestat struct to memory
// Filestat layout (64 bytes):
//   0: dev(u64) 8: ino(u64) 16: filetype(u8) 24: nlink(u64)
//  32: size(u64) 40: atim(u64) 48: mtim(u64) 56: ctim(u64)
// ---------------------------------------------------------------------------
function writeFilestat(view, ptr, st) {
  view.setBigUint64(ptr, st.dev, true);
  view.setBigUint64(ptr + 8, st.ino, true);
  view.setUint8(ptr + 16, st.filetype);
  view.setBigUint64(ptr + 24, st.nlink, true);
  view.setBigUint64(ptr + 32, st.size, true);
  view.setBigUint64(ptr + 40, st.atim, true);
  view.setBigUint64(ptr + 48, st.mtim, true);
  view.setBigUint64(ptr + 56, st.ctim, true);
}

// ---------------------------------------------------------------------------
// Fdstat writer -- writes fdstat struct to memory
// Fdstat layout (24 bytes):
//   0: fs_filetype(u8) 2: fs_flags(u16) 8: fs_rights_base(u64)
//  16: fs_rights_inherited(u64)
// ---------------------------------------------------------------------------
function writeFdstat(view, ptr, st) {
  view.setUint8(ptr, st.fs_filetype);
  view.setUint16(ptr + 2, st.fs_flags, true);
  view.setBigUint64(ptr + 8, st.fs_rights_base, true);
  view.setBigUint64(ptr + 16, st.fs_rights_inherited, true);
}

// ---------------------------------------------------------------------------
// Prestat writer
// Prestat layout: 0: tag(u32) 4: pr_name_len(u32)
// ---------------------------------------------------------------------------
function writePrestat(view, ptr, ps) {
  view.setUint32(ptr, ps.tag, true);
  view.setUint32(ptr + 4, ps.pr_name.byteLength, true);
}

// ---------------------------------------------------------------------------
// WASIProcExit
// ---------------------------------------------------------------------------
function WASIProcExit(code) {
  this.code = code;
  this.message = "exit with exit code " + code;
}
WASIProcExit.prototype = Object.create(Error.prototype);

// ---------------------------------------------------------------------------
// WASI class -- memory64 version
// All pointer parameters are BigInt (i64). fd parameters remain i32.
// ---------------------------------------------------------------------------
function WASI(args, env, fds, options) {
  this.args = args || [];
  this.env = env || [];
  this.fds = fds || [];
  this.inst = null;
  var self = this;

  this.wasiImport = {
    // ---- args ----
    args_sizes_get: function (argc_ptr, argv_buf_size_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      v.setUint32(Number(argc_ptr), self.args.length, true);
      var sz = 0;
      for (var i = 0; i < self.args.length; i++) sz += self.args[i].length + 1;
      v.setUint32(Number(argv_buf_size_ptr), sz, true);
      return 0;
    },
    args_get: function (argv, argv_buf) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var aptr = Number(argv), bptr = Number(argv_buf);
      for (var i = 0; i < self.args.length; i++) {
        v.setBigUint64(aptr, BigInt(bptr), true);
        aptr += 8; // 64-bit pointer entries
        var enc = new TextEncoder().encode(self.args[i]);
        b8.set(enc, bptr);
        b8[bptr + enc.length] = 0;
        bptr += enc.length + 1;
      }
      return 0;
    },

    // ---- environ ----
    environ_sizes_get: function (count_ptr, size_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      v.setUint32(Number(count_ptr), self.env.length, true);
      var sz = 0;
      for (var i = 0; i < self.env.length; i++) sz += new TextEncoder().encode(self.env[i]).length + 1;
      v.setUint32(Number(size_ptr), sz, true);
      return 0;
    },
    environ_get: function (environ, environ_buf) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var eptr = Number(environ), bptr = Number(environ_buf);
      for (var i = 0; i < self.env.length; i++) {
        v.setBigUint64(eptr, BigInt(bptr), true);
        eptr += 8; // 64-bit pointer entries
        var enc = new TextEncoder().encode(self.env[i]);
        b8.set(enc, bptr);
        b8[bptr + enc.length] = 0;
        bptr += enc.length + 1;
      }
      return 0;
    },

    // ---- clock ----
    clock_res_get: function (id, res_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var val;
      if (id === CLOCKID_MONOTONIC) val = 5000n;
      else if (id === CLOCKID_REALTIME) val = 1000000n;
      else return ERRNO_NOSYS;
      v.setBigUint64(Number(res_ptr), val, true);
      return 0;
    },
    clock_time_get: function (id, precision, time_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      if (id === CLOCKID_REALTIME)
        v.setBigUint64(Number(time_ptr), BigInt(new Date().getTime()) * 1000000n, true);
      else if (id === CLOCKID_MONOTONIC) {
        var t; try { t = BigInt(Math.round(performance.now() * 1000000)); } catch(e) { t = 0n; }
        v.setBigUint64(Number(time_ptr), t, true);
      } else v.setBigUint64(Number(time_ptr), 0n, true);
      return 0;
    },

    // ---- fd operations ----
    fd_advise: function (fd) { return self.fds[fd] != null ? 0 : ERRNO_BADF; },
    fd_allocate: function (fd, offset, len) { return self.fds[fd] != null ? (self.fds[fd].fd_allocate ? self.fds[fd].fd_allocate(offset, len) : ERRNO_NOTSUP) : ERRNO_BADF; },
    fd_close: function (fd) {
      if (self.fds[fd] != null) { var r = self.fds[fd].fd_close(); self.fds[fd] = undefined; return r; }
      return ERRNO_BADF;
    },
    fd_datasync: function (fd) { return self.fds[fd] != null ? (self.fds[fd].fd_sync ? self.fds[fd].fd_sync() : 0) : ERRNO_BADF; },
    fd_fdstat_get: function (fd, ptr) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var r = self.fds[fd].fd_fdstat_get();
      if (r.fdstat != null) writeFdstat(new DataView(self.inst.exports.memory.buffer), Number(ptr), r.fdstat);
      return r.ret;
    },
    fd_fdstat_set_flags: function (fd, flags) { return self.fds[fd] != null ? ERRNO_NOTSUP : ERRNO_BADF; },
    fd_fdstat_set_rights: function (fd, base, inh) { return self.fds[fd] != null ? ERRNO_NOTSUP : ERRNO_BADF; },
    fd_filestat_get: function (fd, ptr) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var r = self.fds[fd].fd_filestat_get();
      if (r.filestat != null) writeFilestat(new DataView(self.inst.exports.memory.buffer), Number(ptr), r.filestat);
      return r.ret;
    },
    fd_filestat_set_size: function (fd, size) { return self.fds[fd] != null ? (self.fds[fd].fd_filestat_set_size ? self.fds[fd].fd_filestat_set_size(size) : ERRNO_NOTSUP) : ERRNO_BADF; },
    fd_filestat_set_times: function (fd, atim, mtim, flags) { return self.fds[fd] != null ? ERRNO_NOTSUP : ERRNO_BADF; },

    // ---- fd_read (memory64: iovs_ptr and nread_ptr are i64) ----
    fd_read: function (fd, iovs_ptr, iovs_len, nread_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      if (self.fds[fd] == null) return ERRNO_BADF;
      var iovecs = readIovecs(v, iovs_ptr, Number(iovs_len));
      var nread = 0;
      for (var i = 0; i < iovecs.length; i++) {
        var r = self.fds[fd].fd_read(iovecs[i].buf_len);
        if (r.ret !== 0) { v.setBigUint64(Number(nread_ptr), BigInt(nread), true); return r.ret; }
        b8.set(r.data, iovecs[i].buf);
        nread += r.data.length;
        if (r.data.length !== iovecs[i].buf_len) break;
      }
      v.setBigUint64(Number(nread_ptr), BigInt(nread), true);
      return 0;
    },

    // ---- fd_write (memory64: iovs_ptr and nwritten_ptr are i64) ----
    fd_write: function (fd, iovs_ptr, iovs_len, nwritten_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      if (self.fds[fd] == null) return ERRNO_BADF;
      var iovecs = readIovecs(v, iovs_ptr, Number(iovs_len));
      var nwritten = 0;
      for (var i = 0; i < iovecs.length; i++) {
        var data = b8.slice(iovecs[i].buf, iovecs[i].buf + iovecs[i].buf_len);
        var r = self.fds[fd].fd_write(data);
        if (r.ret !== 0) { v.setBigUint64(Number(nwritten_ptr), BigInt(nwritten), true); return r.ret; }
        nwritten += r.nwritten;
        if (r.nwritten !== data.byteLength) break;
      }
      v.setBigUint64(Number(nwritten_ptr), BigInt(nwritten), true);
      return 0;
    },

    // ---- fd_pread / fd_pwrite ----
    fd_pread: function (fd, iovs_ptr, iovs_len, offset, nread_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      if (self.fds[fd] == null) return ERRNO_BADF;
      var iovecs = readIovecs(v, iovs_ptr, Number(iovs_len));
      var nread = 0;
      for (var i = 0; i < iovecs.length; i++) {
        var r = self.fds[fd].fd_pread(iovecs[i].buf_len, offset);
        if (r.ret !== 0) { v.setBigUint64(Number(nread_ptr), BigInt(nread), true); return r.ret; }
        b8.set(r.data, iovecs[i].buf);
        nread += r.data.length;
        offset += BigInt(r.data.length);
        if (r.data.length !== iovecs[i].buf_len) break;
      }
      v.setBigUint64(Number(nread_ptr), BigInt(nread), true);
      return 0;
    },
    fd_pwrite: function (fd, iovs_ptr, iovs_len, offset, nwritten_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      if (self.fds[fd] == null) return ERRNO_BADF;
      var iovecs = readIovecs(v, iovs_ptr, Number(iovs_len));
      var nwritten = 0;
      for (var i = 0; i < iovecs.length; i++) {
        var data = b8.slice(iovecs[i].buf, iovecs[i].buf + iovecs[i].buf_len);
        var r = self.fds[fd].fd_pwrite(data, offset);
        if (r.ret !== 0) { v.setBigUint64(Number(nwritten_ptr), BigInt(nwritten), true); return r.ret; }
        nwritten += r.nwritten;
        offset += BigInt(r.nwritten);
        if (r.nwritten !== data.byteLength) break;
      }
      v.setBigUint64(Number(nwritten_ptr), BigInt(nwritten), true);
      return 0;
    },

    // ---- fd_seek / fd_tell ----
    fd_seek: function (fd, offset, whence, newoffset_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      if (self.fds[fd] == null) return ERRNO_BADF;
      var r = self.fds[fd].fd_seek(offset, whence);
      v.setBigInt64(Number(newoffset_ptr), r.offset, true);
      return r.ret;
    },
    fd_sync: function (fd) { return self.fds[fd] != null ? (self.fds[fd].fd_sync ? self.fds[fd].fd_sync() : 0) : ERRNO_BADF; },
    fd_tell: function (fd, offset_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      if (self.fds[fd] == null) return ERRNO_BADF;
      var r = self.fds[fd].fd_tell();
      v.setBigUint64(Number(offset_ptr), r.offset, true);
      return r.ret;
    },

    // ---- fd_readdir ----
    fd_readdir: function (fd, buf, buf_len, cookie, bufused_ptr) {
      var v = new DataView(self.inst.exports.memory.buffer);
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      if (self.fds[fd] == null) return ERRNO_BADF;
      var bptr = Number(buf), blen = Number(buf_len), used = 0;
      while (true) {
        var r = self.fds[fd].fd_readdir_single(cookie);
        if (r.ret !== 0) { v.setBigUint64(Number(bufused_ptr), BigInt(used), true); return r.ret; }
        if (r.dirent == null) break;
        // dirent head: 24 bytes (d_next:u64, d_ino:u64, d_namlen:u32, d_type:u8)
        if (blen - used < 24) { used = blen; break; }
        v.setBigUint64(bptr, r.dirent.d_next, true);
        v.setBigUint64(bptr + 8, r.dirent.d_ino, true);
        v.setUint32(bptr + 16, r.dirent.dir_name.length, true);
        v.setUint8(bptr + 20, r.dirent.d_type);
        bptr += 24; used += 24;
        if (blen - used < r.dirent.dir_name.length) { used = blen; break; }
        b8.set(r.dirent.dir_name.slice(0, Math.min(r.dirent.dir_name.length, blen - used)), bptr);
        bptr += r.dirent.dir_name.length; used += r.dirent.dir_name.length;
        cookie = r.dirent.d_next;
      }
      v.setBigUint64(Number(bufused_ptr), BigInt(used), true);
      return 0;
    },

    // ---- fd_renumber ----
    fd_renumber: function (fd, to) {
      if (self.fds[fd] != null && self.fds[to] != null) {
        var r = self.fds[to].fd_close(); if (r !== 0) return r;
        self.fds[to] = self.fds[fd]; self.fds[fd] = undefined; return 0;
      }
      return ERRNO_BADF;
    },

    // ---- fd_prestat_get / fd_prestat_dir_name ----
    fd_prestat_get: function (fd, buf_ptr) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var r = self.fds[fd].fd_prestat_get();
      if (r.prestat != null) writePrestat(new DataView(self.inst.exports.memory.buffer), Number(buf_ptr), r.prestat);
      return r.ret;
    },
    fd_prestat_dir_name: function (fd, path_ptr, path_len) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var r = self.fds[fd].fd_prestat_get();
      if (r.ret !== 0 || r.prestat == null) return r.ret;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var plen = Number(path_len);
      b8.set(r.prestat.pr_name.slice(0, plen), Number(path_ptr));
      return r.prestat.pr_name.byteLength > plen ? ERRNO_NAMETOOLONG : 0;
    },

    // ---- path operations (all pointer args are i64 in memory64) ----
    path_create_directory: function (fd, path_ptr, path_len) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var path = new TextDecoder("utf-8").decode(b8.slice(Number(path_ptr), Number(path_ptr) + Number(path_len)));
      return self.fds[fd].path_create_directory(path);
    },
    path_filestat_get: function (fd, flags, path_ptr, path_len, filestat_ptr) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var path = new TextDecoder("utf-8").decode(b8.slice(Number(path_ptr), Number(path_ptr) + Number(path_len)));
      var r = self.fds[fd].path_filestat_get(flags, path);
      if (r.filestat != null) writeFilestat(new DataView(self.inst.exports.memory.buffer), Number(filestat_ptr), r.filestat);
      return r.ret;
    },
    path_filestat_set_times: function (fd, flags, path_ptr, path_len, atim, mtim, fst_flags) {
      return self.fds[fd] != null ? ERRNO_NOTSUP : ERRNO_BADF;
    },
    path_link: function (old_fd, old_flags, old_path_ptr, old_path_len, new_fd, new_path_ptr, new_path_len) {
      if (self.fds[old_fd] == null || self.fds[new_fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var old_path = new TextDecoder("utf-8").decode(b8.slice(Number(old_path_ptr), Number(old_path_ptr) + Number(old_path_len)));
      var new_path = new TextDecoder("utf-8").decode(b8.slice(Number(new_path_ptr), Number(new_path_ptr) + Number(new_path_len)));
      var r = self.fds[old_fd].path_lookup(old_path, old_flags);
      if (r.inode_obj == null) return r.ret;
      return self.fds[new_fd].path_link(new_path, r.inode_obj, false);
    },
    path_open: function (fd, dirflags, path_ptr, path_len, oflags, fs_rights_base, fs_rights_inheriting, fd_flags, opened_fd_ptr) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var path = new TextDecoder("utf-8").decode(b8.slice(Number(path_ptr), Number(path_ptr) + Number(path_len)));
      var r = self.fds[fd].path_open(dirflags, path, oflags, fs_rights_base, fs_rights_inheriting, fd_flags);
      if (r.ret !== 0) return r.ret;
      self.fds.push(r.fd_obj);
      var v = new DataView(self.inst.exports.memory.buffer);
      v.setUint32(Number(opened_fd_ptr), self.fds.length - 1, true); // fd is always i32
      return 0;
    },
    path_readlink: function (fd, path_ptr, path_len, buf_ptr, buf_len, nread_ptr) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var path = new TextDecoder("utf-8").decode(b8.slice(Number(path_ptr), Number(path_ptr) + Number(path_len)));
      var r = self.fds[fd].path_readlink ? self.fds[fd].path_readlink(path) : { ret: ERRNO_NOTSUP, data: null };
      if (r.data != null) {
        var enc = new TextEncoder().encode(r.data);
        if (enc.length > Number(buf_len)) { new DataView(self.inst.exports.memory.buffer).setBigUint64(Number(nread_ptr), 0n, true); return ERRNO_BADF; }
        b8.set(enc, Number(buf_ptr));
        new DataView(self.inst.exports.memory.buffer).setBigUint64(Number(nread_ptr), BigInt(enc.length), true);
      }
      return r.ret;
    },
    path_remove_directory: function (fd, path_ptr, path_len) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var path = new TextDecoder("utf-8").decode(b8.slice(Number(path_ptr), Number(path_ptr) + Number(path_len)));
      return self.fds[fd].path_remove_directory(path);
    },
    path_rename: function (fd, old_path_ptr, old_path_len, new_fd, new_path_ptr, new_path_len) {
      if (self.fds[fd] == null || self.fds[new_fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var old_path = new TextDecoder("utf-8").decode(b8.slice(Number(old_path_ptr), Number(old_path_ptr) + Number(old_path_len)));
      var new_path = new TextDecoder("utf-8").decode(b8.slice(Number(new_path_ptr), Number(new_path_ptr) + Number(new_path_len)));
      var r = self.fds[fd].path_unlink(old_path);
      if (r.inode_obj == null) return r.ret;
      var ret = self.fds[new_fd].path_link(new_path, r.inode_obj, true);
      if (ret !== ERRNO_SUCCESS) self.fds[fd].path_link(old_path, r.inode_obj, true);
      return ret;
    },
    path_symlink: function () { return ERRNO_NOTSUP; },
    path_unlink_file: function (fd, path_ptr, path_len) {
      if (self.fds[fd] == null) return ERRNO_BADF;
      var b8 = new Uint8Array(self.inst.exports.memory.buffer);
      var path = new TextDecoder("utf-8").decode(b8.slice(Number(path_ptr), Number(path_ptr) + Number(path_len)));
      return self.fds[fd].path_unlink_file(path);
    },

    // ---- poll_oneoff ----
    poll_oneoff: function (in_ptr, out_ptr, nsubs) {
      if (nsubs === 0) return ERRNO_INVAL;
      if (nsubs > 1) return ERRNO_NOTSUP;
      var v = new DataView(self.inst.exports.memory.buffer);
      var p = Number(in_ptr);
      var userdata = v.getBigUint64(p, true);
      var eventtype = v.getUint8(p + 8);
      var clockid = v.getUint32(p + 16, true);
      var timeout = v.getBigUint64(p + 24, true);
      var flags = v.getUint16(p + 36, true);
      if (eventtype !== EVENTTYPE_CLOCK) return ERRNO_NOTSUP;
      var getNow;
      if (clockid === CLOCKID_MONOTONIC) getNow = function () { return BigInt(Math.round(performance.now() * 1000000)); };
      else if (clockid === CLOCKID_REALTIME) getNow = function () { return BigInt(new Date().getTime()) * 1000000n; };
      else return ERRNO_INVAL;
      var endTime = (flags & SUBCLOCKFLAGS_SUBSCRIPTION_CLOCK_ABSTIME) !== 0 ? timeout : getNow() + timeout;
      while (endTime > getNow()) { /* block */ }
      var op = Number(out_ptr);
      v.setBigUint64(op, userdata, true);
      v.setUint16(op + 8, 0, true);
      v.setUint8(op + 10, eventtype);
      return 0;
    },

    // ---- proc / sched / random ----
    proc_exit: function (code) { throw new WASIProcExit(code); },
    proc_raise: function (sig) { throw "raised signal " + sig; },
    sched_yield: function () {},
    random_get: function (buf, buf_len) {
      var b8 = new Uint8Array(self.inst.exports.memory.buffer).subarray(Number(buf), Number(buf) + Number(buf_len));
      for (var i = 0; i < Number(buf_len); i += 65536)
        crypto.getRandomValues(b8.subarray(i, i + 65536));
    },

    // ---- sockets (unsupported) ----
    sock_recv: function () { throw "sockets not supported"; },
    sock_send: function () { throw "sockets not supported"; },
    sock_shutdown: function () { throw "sockets not supported"; },
    sock_accept: function () { throw "sockets not supported"; }
  };
}

WASI.prototype.start = function (instance) {
  this.inst = instance;
  try { instance.exports._start(); return 0; }
  catch (e) { if (e instanceof WASIProcExit) return e.code; throw e; }
};

WASI.prototype.initialize = function (instance) {
  this.inst = instance;
  if (instance.exports._initialize) instance.exports._initialize();
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
return {
  WASI: WASI,
  WASIProcExit: WASIProcExit,
  File: File,
  OpenFile: OpenFile,
  Directory: Directory,
  OpenDirectory: OpenDirectory,
  PreopenDirectory: PreopenDirectory,
  ConsoleStdout: ConsoleStdout
};

})();


// ---------------------------------------------------------------------------
// Embedded Asset System
// ---------------------------------------------------------------------------

var WaskalAssets = (function () {
  "use strict";

  var manifest = (typeof WKL_ASSETS !== "undefined") ? WKL_ASSETS.manifest : {};
  var dataB64 = (typeof WKL_ASSETS !== "undefined") ? WKL_ASSETS.data : "";
  var decodedBytes = null;
  var imageBitmaps = {};

  var IMAGE_MIMES = {
    "image/png": true,
    "image/jpeg": true,
    "image/gif": true,
    "image/webp": true,
    "image/bmp": true
  };

  // One-time async decode: base64 -> gunzip -> Uint8Array
  function decode() {
    if (decodedBytes) return Promise.resolve(decodedBytes);
    if (!dataB64 || dataB64.length === 0) {
      decodedBytes = new Uint8Array(0);
      return Promise.resolve(decodedBytes);
    }
    var bin = atob(dataB64);
    var compressed = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++)
      compressed[i] = bin.charCodeAt(i);
    var ds = new DecompressionStream("deflate");
    var stream = new Blob([compressed]).stream().pipeThrough(ds);
    return new Response(stream).arrayBuffer().then(function (buf) {
      decodedBytes = new Uint8Array(buf);
      dataB64 = null; // free the base64 string
      return preloadImages();
    }).then(function () {
      return decodedBytes;
    });
  }

  // Preload all image assets into ImageBitmaps for sync drawing
  function preloadImages() {
    var promises = [];
    var keys = Object.keys(manifest);
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      var entry = manifest[key];
      if (IMAGE_MIMES[entry.mime]) {
        (function (k, e) {
          var bytes = decodedBytes.subarray(e.offset, e.offset + e.size);
          var blob = new Blob([bytes], { type: e.mime });
          promises.push(
            createImageBitmap(blob).then(function (bmp) {
              imageBitmaps[k] = bmp;
            })
          );
        })(key, entry);
      }
    }
    return Promise.all(promises);
  }

  function getImageBitmap(name) {
    return imageBitmaps[name] || null;
  }

  function assetBytes(name) {
    if (!decodedBytes) throw new Error("WaskalAssets not initialized");
    var entry = manifest[name];
    if (!entry) throw new Error("Asset not found: " + name);
    return decodedBytes.subarray(entry.offset, entry.offset + entry.size);
  }

  function assetBlob(name) {
    var entry = manifest[name];
    if (!entry) throw new Error("Asset not found: " + name);
    return new Blob([assetBytes(name)], { type: entry.mime });
  }

  function assetURL(name) {
    return URL.createObjectURL(assetBlob(name));
  }

  function assetText(name) {
    return new TextDecoder().decode(assetBytes(name));
  }

  function assetExists(name) {
    return name in manifest;
  }

  function assetSize(name) {
    var entry = manifest[name];
    return entry ? entry.size : 0;
  }

  // Patch fetch() to intercept embedded asset paths
  var originalFetch = globalThis.fetch;
  globalThis.fetch = function (resource, options) {
    var name;
    if (typeof resource === "string")
      name = resource;
    else if (resource instanceof Request)
      name = resource.url;
    if (name) {
      name = name.replace(/^\.?\//, "");
      if (name in manifest) {
        return Promise.resolve(new Response(assetBytes(name), {
          status: 200,
          headers: {
            "Content-Type": manifest[name].mime,
            "Content-Length": String(manifest[name].size)
          }
        }));
      }
    }
    return originalFetch(resource, options);
  };

  // WASM bridge: reads cstring from linear memory, calls asset functions
  function createWasmBridge(getInstance) {
    return {
      asset_exists: function (namePtr) {
        return assetExists(WKL.readCStr(namePtr)) ? 1 : 0;
      },
      asset_size: function (namePtr) {
        return BigInt(assetSize(WKL.readCStr(namePtr)));
      },
      asset_load: function (namePtr, bufPtr, bufSize) {
        var name = WKL.readCStr(namePtr);
        if (!assetExists(name)) return BigInt(0);
        var data = assetBytes(name);
        var len = Math.min(data.length, Number(bufSize));
        var mem = new Uint8Array(getInstance().exports.memory.buffer);
        mem.set(data.subarray(0, len), Number(bufPtr));
        return BigInt(len);
      },
      asset_text: function (namePtr, bufPtr, bufSize) {
        var name = WKL.readCStr(namePtr);
        if (!assetExists(name)) return BigInt(0);
        var text = new TextEncoder().encode(assetText(name));
        var len = Math.min(text.length, Number(bufSize));
        var mem = new Uint8Array(getInstance().exports.memory.buffer);
        mem.set(text.subarray(0, len), Number(bufPtr));
        return BigInt(len);
      }
    };
  }

  return {
    decode: decode,
    bytes: assetBytes,
    blob: assetBlob,
    url: assetURL,
    text: assetText,
    exists: assetExists,
    size: assetSize,
    createWasmBridge: createWasmBridge,
    getImageBitmap: getImageBitmap
  };
})();

