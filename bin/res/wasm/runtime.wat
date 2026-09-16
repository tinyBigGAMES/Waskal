;;==============================================================================
;; Panther Runtime Library
;;
;; Copyright (c) 2026-present tinyBigGAMES(tm) LLC
;; All Rights Reserved.
;;
;; Hand-written WAT runtime for wasm64 (memory64). Included verbatim by
;; Panther.Emitter into the output module. All functions here are real wasm
;; functions in the same module as user code -- not JS imports.
;;
;; Dependencies flow down:
;;   heap -> memutils -> strings -> intrinsics -> lifecycle -> test runner
;;
;; Every function uses memory64 (i64 pointers). Linear memory is the only
;; storage. No OS heap, no external allocator.
;;==============================================================================

;;------------------------------------------------------------------------------
;; WASI Imports (must precede all function definitions)
;;------------------------------------------------------------------------------

  (import "wasi_snapshot_preview1" "fd_write"
    (func $wasi_fd_write (param i32 i64 i32 i64) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $wasi_proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $wasi_args_sizes_get (param i64 i64) (result i32)))
  (import "wasi_snapshot_preview1" "args_get"
    (func $wasi_args_get (param i64 i64) (result i32)))

;;------------------------------------------------------------------------------
;; Heap Allocator (Atom R1)
;;
;; Free-list allocator over linear memory.
;;
;; Block layout (all blocks, allocated or free):
;;   offset 0: block_size (i64) -- total size including this 8-byte header
;;
;; When a block is FREE, the first 8 bytes of user data hold the next-free
;; pointer (0 = end of list). Minimum block size is therefore 16 bytes
;; (8 header + 8 next pointer).
;;
;; All block sizes are rounded up to a multiple of 16 for alignment.
;;
;; Globals:
;;   $rt_heap_ptr  -- bump pointer: next address for fresh allocations
;;   $rt_free_list -- head of the free-list (0 = empty)
;;
;; The emitter sets $rt_heap_ptr's initial value to the first address past
;; all static data segments. Until then, 65536 (one page past zero) is a
;; safe default.
;;------------------------------------------------------------------------------

  ;; Heap globals
  (global $rt_heap_ptr (mut i64) (i64.const 65536))
  (global $rt_free_list (mut i64) (i64.const 0))

  ;; RT_GetMem(ASize: i64) -> i64
  ;; Allocates ASize bytes. Returns pointer to usable memory (past header).
  ;; Scans free list first (first-fit), falls back to bump allocation.
  (func $RT_GetMem_Impl (param $ASize i64) (result i64)
    (local $LBlockSize i64)
    (local $LPrev i64)
    (local $LCurr i64)
    (local $LCurrSize i64)
    (local $LBlock i64)
    (local $LNeeded i64)
    (local $LPages i64)

    ;; Calculate block size: align_up(ASize + 8, 16), minimum 16
    ;; block_size = (ASize + 8 + 15) & ~15
    (local.set $LBlockSize
      (i64.and
        (i64.add (i64.add (local.get $ASize) (i64.const 8)) (i64.const 15))
        (i64.const -16)))
    ;; Enforce minimum of 16
    (if (i64.lt_u (local.get $LBlockSize) (i64.const 16))
      (then (local.set $LBlockSize (i64.const 16))))

    ;; -- Scan free list (first-fit) --
    (local.set $LPrev (i64.const 0))
    (local.set $LCurr (global.get $rt_free_list))
    (block $found
      (block $not_found
        (loop $scan
          ;; End of list?
          (br_if $not_found (i64.eqz (local.get $LCurr)))

          ;; Read block size at LCurr
          (local.set $LCurrSize (i64.load (local.get $LCurr)))

          ;; Big enough?
          (if (i64.ge_u (local.get $LCurrSize) (local.get $LBlockSize))
            (then
              ;; Unlink from free list
              ;; next = i64.load(LCurr + 8)
              (if (i64.eqz (local.get $LPrev))
                (then
                  ;; Head of list
                  (global.set $rt_free_list
                    (i64.load (i64.add (local.get $LCurr) (i64.const 8)))))
                (else
                  ;; Middle of list: prev->next = curr->next
                  (i64.store
                    (i64.add (local.get $LPrev) (i64.const 8))
                    (i64.load (i64.add (local.get $LCurr) (i64.const 8))))))
              ;; Return user pointer (past header)
              (local.set $LBlock (local.get $LCurr))
              (br $found)))

          ;; Advance: prev = curr, curr = curr->next
          (local.set $LPrev (local.get $LCurr))
          (local.set $LCurr (i64.load (i64.add (local.get $LCurr) (i64.const 8))))
          (br $scan)))

      ;; -- Not found in free list: bump allocate --
      (local.set $LBlock (global.get $rt_heap_ptr))
      (local.set $LNeeded
        (i64.add (local.get $LBlock) (local.get $LBlockSize)))

      ;; Grow memory if needed
      ;; Current memory size in bytes = memory.size * 65536
      (if (i64.gt_u (local.get $LNeeded)
                     (i64.mul (memory.size) (i64.const 65536)))
        (then
          ;; Pages needed: ceil((LNeeded - current_bytes) / 65536)
          (local.set $LPages
            (i64.div_u
              (i64.add
                (i64.sub (local.get $LNeeded)
                         (i64.mul (memory.size) (i64.const 65536)))
                (i64.const 65535))
              (i64.const 65536)))
          ;; Grow; if fails (-1), trap
          (if (i64.eq (memory.grow (local.get $LPages)) (i64.const -1))
            (then (unreachable)))))

      ;; Store block size in header
      (i64.store (local.get $LBlock) (local.get $LBlockSize))
      ;; Advance bump pointer
      (global.set $rt_heap_ptr
        (i64.add (local.get $LBlock) (local.get $LBlockSize))))

    ;; $found: LBlock is set, return user pointer
    (i64.add (local.get $LBlock) (i64.const 8)))

  ;; RT_FreeMem(APtr: i64)
  ;; Returns a block to the free list. Nil-safe.
  (func $RT_FreeMem_Impl (param $APtr i64)
    (local $LBlock i64)

    ;; Nil guard
    (if (i64.eqz (local.get $APtr)) (then (return)))

    ;; Block starts 8 bytes before user pointer
    (local.set $LBlock (i64.sub (local.get $APtr) (i64.const 8)))

    ;; Prepend to free list: block->next = old head
    (i64.store
      (i64.add (local.get $LBlock) (i64.const 8))
      (global.get $rt_free_list))
    ;; New head = this block
    (global.set $rt_free_list (local.get $LBlock)))

  ;; RT_ReAllocMem(APtr: i64, ANewSize: i64) -> i64
  ;; Reallocates a block. Alloc new, copy old data, free old.
  ;; If APtr is nil, behaves like RT_GetMem.
  (func $RT_ReAllocMem (param $APtr i64) (param $ANewSize i64) (result i64)
    (local $LOldSize i64)
    (local $LCopySize i64)
    (local $LNew i64)

    ;; Nil -> just allocate
    (if (i64.eqz (local.get $APtr))
      (then (return (call $RT_GetMem (local.get $ANewSize)))))

    ;; Old usable size = block_size - 8 (header)
    (local.set $LOldSize
      (i64.sub
        (i64.load (i64.sub (local.get $APtr) (i64.const 8)))
        (i64.const 8)))

    ;; Allocate new block
    (local.set $LNew (call $RT_GetMem (local.get $ANewSize)))

    ;; Copy min(old, new) bytes
    (local.set $LCopySize (local.get $LOldSize))
    (if (i64.lt_u (local.get $ANewSize) (local.get $LOldSize))
      (then (local.set $LCopySize (local.get $ANewSize))))
    (memory.copy
      (local.get $LNew)
      (local.get $APtr)
      (local.get $LCopySize))

    ;; Free old block
    (call $RT_FreeMem (local.get $APtr))

    ;; Return new pointer
    (local.get $LNew))

  ;; RT_AllocMem(ASize: i64) -> i64
  ;; Allocates and zero-fills ASize bytes.
  (func $RT_AllocMem (param $ASize i64) (result i64)
    (local $LPtr i64)
    (local.set $LPtr (call $RT_GetMem (local.get $ASize)))
    (memory.fill (local.get $LPtr) (i32.const 0) (local.get $ASize))
    (local.get $LPtr))

;;------------------------------------------------------------------------------
;; Memory Utilities (Atom R2)
;;
;; Thin wrappers and helpers used by the string runtime and emitter.
;;------------------------------------------------------------------------------

  ;; rt_memcmp(a: i64, b: i64, n: i64) -> i32
  ;; Byte-by-byte comparison. Returns -1, 0, or 1.
  (func $rt_memcmp (param $a i64) (param $b i64) (param $n i64) (result i32)
    (local $i i64)
    (local $va i32)
    (local $vb i32)
    (local.set $i (i64.const 0))
    (block $done
      (loop $cmp
        (br_if $done (i64.ge_u (local.get $i) (local.get $n)))
        (local.set $va (i32.load8_u (i64.add (local.get $a) (local.get $i))))
        (local.set $vb (i32.load8_u (i64.add (local.get $b) (local.get $i))))
        (if (i32.lt_u (local.get $va) (local.get $vb))
          (then (return (i32.const -1))))
        (if (i32.gt_u (local.get $va) (local.get $vb))
          (then (return (i32.const 1))))
        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $cmp)))
    (i32.const 0))


;;------------------------------------------------------------------------------
;; String Core (Atom R3)
;;
;; TStringRec layout in linear memory (40 bytes):
;;   offset  0: RefCount  (i64) -- -1 = immortal, 0 = dead, 1+ = live
;;   offset  8: Length    (i64) -- string length in bytes (excl. null)
;;   offset 16: Capacity  (i64) -- allocated buffer size (excl. null)
;;   offset 24: Data      (i64) -- pointer to UTF-8 byte buffer
;;   offset 32: Data16    (i64) -- pointer to cached UTF-16 (0 until needed)
;;
;; A "string" value is an i64 pointer to a TStringRec on the heap.
;; Nil (0) is a valid string value meaning empty.
;;------------------------------------------------------------------------------

  ;; RT_StrAlloc(ACapacity: i64) -> i64
  ;; Allocates a new TStringRec with a data buffer of ACapacity+1 bytes.
  ;; RefCount = 1, Length = 0, Data null-terminated, Data16 = nil.
  (func $RT_StrAlloc (param $ACapacity i64) (result i64)
    (local $LRec i64)
    (local $LData i64)

    ;; Allocate the TStringRec struct (40 bytes)
    (local.set $LRec (call $RT_GetMem (i64.const 40)))

    ;; Allocate data buffer (capacity + 1 for null terminator)
    (local.set $LData
      (call $RT_GetMem (i64.add (local.get $ACapacity) (i64.const 1))))

    ;; Initialize fields
    ;; RefCount = 1
    (i64.store (local.get $LRec) (i64.const 1))
    ;; Length = 0
    (i64.store offset=8 (local.get $LRec) (i64.const 0))
    ;; Capacity
    (i64.store offset=16 (local.get $LRec) (local.get $ACapacity))
    ;; Data pointer
    (i64.store offset=24 (local.get $LRec) (local.get $LData))
    ;; Data16 = nil
    (i64.store offset=32 (local.get $LRec) (i64.const 0))

    ;; Null-terminate empty buffer
    (i32.store8 (local.get $LData) (i32.const 0))

    ;; Return pointer to TStringRec
    (local.get $LRec))

  ;; RT_StrFree(AStr: i64)
  ;; Frees the data buffer(s) and the TStringRec. Nil-safe.
  (func $RT_StrFree (param $AStr i64)
    (local $LData i64)
    (local $LData16 i64)

    ;; Nil guard
    (if (i64.eqz (local.get $AStr)) (then (return)))

    ;; Free Data16 if present
    (local.set $LData16 (i64.load offset=32 (local.get $AStr)))
    (if (i64.ne (local.get $LData16) (i64.const 0))
      (then (call $RT_FreeMem (local.get $LData16))))

    ;; Free Data buffer
    (local.set $LData (i64.load offset=24 (local.get $AStr)))
    (if (i64.ne (local.get $LData) (i64.const 0))
      (then (call $RT_FreeMem (local.get $LData))))

    ;; Free the TStringRec itself
    (call $RT_FreeMem (local.get $AStr)))

  ;; RT_StrAddRef(AStr: i64)
  ;; Increments refcount. Nil-safe. Skips immortal strings (refcount = -1).
  (func $RT_StrAddRef (param $AStr i64)
    (local $LRefCount i64)

    ;; Nil guard
    (if (i64.eqz (local.get $AStr)) (then (return)))

    ;; Read refcount
    (local.set $LRefCount (i64.load (local.get $AStr)))

    ;; Immortal guard (refcount = -1)
    (if (i64.eq (local.get $LRefCount) (i64.const -1)) (then (return)))

    ;; Increment
    (i64.store (local.get $AStr)
      (i64.add (local.get $LRefCount) (i64.const 1))))

  ;; RT_StrRelease(AStr: i64)
  ;; Decrements refcount. Frees when it reaches 0. Nil-safe. Immortal-safe.
  (func $RT_StrRelease (param $AStr i64)
    (local $LRefCount i64)

    ;; Nil guard
    (if (i64.eqz (local.get $AStr)) (then (return)))

    ;; Read refcount
    (local.set $LRefCount (i64.load (local.get $AStr)))

    ;; Immortal guard
    (if (i64.eq (local.get $LRefCount) (i64.const -1)) (then (return)))

    ;; Decrement
    (local.set $LRefCount (i64.sub (local.get $LRefCount) (i64.const 1)))
    (i64.store (local.get $AStr) (local.get $LRefCount))

    ;; Free if zero
    (if (i64.eqz (local.get $LRefCount))
      (then (call $RT_StrFree (local.get $AStr)))))

  ;; RT_StrLen(AStr: i64) -> i64
  ;; Returns string length in bytes. 0 if nil.
  (func $RT_StrLen (param $AStr i64) (result i64)
    (if (i64.eqz (local.get $AStr))
      (then (return (i64.const 0))))
    (i64.load offset=8 (local.get $AStr)))

  ;; RT_StrData(AStr: i64) -> i64
  ;; Returns pointer to UTF-8 data buffer. 0 if nil.
  (func $RT_StrData (param $AStr i64) (result i64)
    (if (i64.eqz (local.get $AStr))
      (then (return (i64.const 0))))
    (i64.load offset=24 (local.get $AStr)))

  ;; RT_WStrData(AStr: i64) -> i64
  ;; Returns pointer to a null-terminated UTF-16 copy of the string, converting
  ;; from UTF-8 on first call and caching the result in Data16 (offset 32).
  ;; The buffer is owned by the string and freed by RT_StrFree. 0 if nil.
  (func $RT_WStrData (param $AStr i64) (result i64)
    (local $LData16 i64)
    (local $LData i64)
    (local $LLen i64)
    (local $LBuf i64)
    (local $LI i64)
    (local $LO i64)
    (local $LB i64)
    (local $LCp i64)
    (local $LN i64)
    (local $LK i64)

    (if (i64.eqz (local.get $AStr)) (then (return (i64.const 0))))

    ;; Cached?
    (local.set $LData16 (i64.load offset=32 (local.get $AStr)))
    (if (i64.ne (local.get $LData16) (i64.const 0))
      (then (return (local.get $LData16))))

    (local.set $LLen (i64.load offset=8 (local.get $AStr)))
    (local.set $LData (i64.load offset=24 (local.get $AStr)))

    ;; Worst case one 16-bit unit per UTF-8 byte, plus terminator
    (local.set $LBuf (call $RT_GetMem
      (i64.mul (i64.add (local.get $LLen) (i64.const 1)) (i64.const 2))))

    (local.set $LI (i64.const 0))
    (local.set $LO (i64.const 0))
    (block $done
      (loop $next
        (br_if $done (i64.ge_u (local.get $LI) (local.get $LLen)))
        (local.set $LB (i64.load8_u (i64.add (local.get $LData) (local.get $LI))))

        ;; Decode lead byte -> initial code point bits and sequence length
        (if (i64.lt_u (local.get $LB) (i64.const 0x80))
          (then
            (local.set $LCp (local.get $LB))
            (local.set $LN (i64.const 1)))
          (else (if (i64.eq (i64.and (local.get $LB) (i64.const 0xE0)) (i64.const 0xC0))
            (then
              (local.set $LCp (i64.and (local.get $LB) (i64.const 0x1F)))
              (local.set $LN (i64.const 2)))
            (else (if (i64.eq (i64.and (local.get $LB) (i64.const 0xF0)) (i64.const 0xE0))
              (then
                (local.set $LCp (i64.and (local.get $LB) (i64.const 0x0F)))
                (local.set $LN (i64.const 3)))
              (else (if (i64.eq (i64.and (local.get $LB) (i64.const 0xF8)) (i64.const 0xF0))
                (then
                  (local.set $LCp (i64.and (local.get $LB) (i64.const 0x07)))
                  (local.set $LN (i64.const 4)))
                (else
                  ;; Invalid lead byte -> U+FFFD, consume one byte
                  (local.set $LCp (i64.const 0xFFFD))
                  (local.set $LN (i64.const 1))))))))))

        ;; Accumulate continuation bytes (bounds-checked)
        (local.set $LK (i64.const 1))
        (block $cont_done
          (loop $cont
            (br_if $cont_done (i64.ge_u (local.get $LK) (local.get $LN)))
            (br_if $cont_done (i64.ge_u
              (i64.add (local.get $LI) (local.get $LK)) (local.get $LLen)))
            (local.set $LCp (i64.or
              (i64.shl (local.get $LCp) (i64.const 6))
              (i64.and (i64.load8_u (i64.add (local.get $LData)
                (i64.add (local.get $LI) (local.get $LK)))) (i64.const 0x3F))))
            (local.set $LK (i64.add (local.get $LK) (i64.const 1)))
            (br $cont)))
        (local.set $LI (i64.add (local.get $LI) (local.get $LN)))

        ;; Emit UTF-16 (surrogate pair above BMP)
        (if (i64.ge_u (local.get $LCp) (i64.const 0x10000))
          (then
            (local.set $LCp (i64.sub (local.get $LCp) (i64.const 0x10000)))
            (i64.store16 (i64.add (local.get $LBuf) (i64.shl (local.get $LO) (i64.const 1)))
              (i64.or (i64.const 0xD800) (i64.shr_u (local.get $LCp) (i64.const 10))))
            (local.set $LO (i64.add (local.get $LO) (i64.const 1)))
            (i64.store16 (i64.add (local.get $LBuf) (i64.shl (local.get $LO) (i64.const 1)))
              (i64.or (i64.const 0xDC00) (i64.and (local.get $LCp) (i64.const 0x3FF))))
            (local.set $LO (i64.add (local.get $LO) (i64.const 1))))
          (else
            (i64.store16 (i64.add (local.get $LBuf) (i64.shl (local.get $LO) (i64.const 1)))
              (local.get $LCp))
            (local.set $LO (i64.add (local.get $LO) (i64.const 1)))))
        (br $next)))

    ;; Null terminator, cache, return
    (i64.store16 (i64.add (local.get $LBuf) (i64.shl (local.get $LO) (i64.const 1))) (i64.const 0))
    (i64.store offset=32 (local.get $AStr) (local.get $LBuf))
    (local.get $LBuf))


;;------------------------------------------------------------------------------
;; String Operations (Atom R4)
;;
;; Construction, mutation, and comparison of refcounted strings.
;;------------------------------------------------------------------------------

  ;; RT_StrFromLiteral(AData: i64, ALen: i64) -> i64
  ;; Creates a new managed string from static literal data.
  ;; Copies ALen bytes from AData into a fresh TStringRec.
  (func $RT_StrFromLiteral (param $AData i64) (param $ALen i64) (result i64)
    (local $LRec i64)
    (local $LData i64)

    ;; Allocate string with capacity = length
    (local.set $LRec (call $RT_StrAlloc (local.get $ALen)))

    ;; Get data pointer from the new record
    (local.set $LData (i64.load offset=24 (local.get $LRec)))

    ;; Copy literal bytes
    (memory.copy (local.get $LData) (local.get $AData) (local.get $ALen))

    ;; Set length
    (i64.store offset=8 (local.get $LRec) (local.get $ALen))

    ;; Null-terminate
    (i32.store8 (i64.add (local.get $LData) (local.get $ALen)) (i32.const 0))

    (local.get $LRec))

  ;; RT_StrFromCStr(APtr: i64) -> i64
  ;; Creates a managed string (refcount 1) from a NUL-terminated UTF-8 buffer.
  ;; Backs the implicit ptr to char -> string assignment (ikCStrToStr).
  (func $RT_StrFromCStr (param $APtr i64) (result i64)
    (local $LLen i64)
    (local.set $LLen (i64.const 0))
    (block $done
      (loop $scan
        (br_if $done (i32.eqz (i32.load8_u (i64.add (local.get $APtr) (local.get $LLen)))))
        (local.set $LLen (i64.add (local.get $LLen) (i64.const 1)))
        (br $scan)))
    (call $RT_StrFromLiteral (local.get $APtr) (local.get $LLen)))

  ;; RT_Utf8(AStr: i64) -> i64
  ;; utf8(s): copies the string's UTF-8 bytes into a NEW caller-owned,
  ;; NUL-terminated buffer (BNF.md:627-629). Caller must freemem it.
  (func $RT_Utf8 (param $AStr i64) (result i64)
    (local $LLen i64)
    (local $LBuf i64)
    (local.set $LLen (call $RT_StrLen (local.get $AStr)))
    (local.set $LBuf (call $RT_GetMem (i64.add (local.get $LLen) (i64.const 1))))
    (if (i64.ne (local.get $LLen) (i64.const 0))
      (then (memory.copy (local.get $LBuf) (call $RT_StrData (local.get $AStr)) (local.get $LLen))))
    (i32.store8 (i64.add (local.get $LBuf) (local.get $LLen)) (i32.const 0))
    (local.get $LBuf))

  ;; RT_StrFromChar(AChar: i64) -> i64
  ;; Creates a new managed string from a single byte character.
  (func $RT_StrFromChar (param $AChar i64) (result i64)
    (local $LRec i64)
    (local $LData i64)

    ;; Allocate string with capacity = 1
    (local.set $LRec (call $RT_StrAlloc (i64.const 1)))

    ;; Get data pointer
    (local.set $LData (i64.load offset=24 (local.get $LRec)))

    ;; Store the character byte
    (i32.store8 (local.get $LData) (i32.wrap_i64 (local.get $AChar)))

    ;; Set length = 1
    (i64.store offset=8 (local.get $LRec) (i64.const 1))

    ;; Null-terminate
    (i32.store8 (i64.add (local.get $LData) (i64.const 1)) (i32.const 0))

    (local.get $LRec))

  ;; RT_StrConcat(AStr1: i64, AStr2: i64) -> i64
  ;; Creates a new string that is the concatenation of AStr1 and AStr2.
  ;; Handles nil strings as empty. Returns a new string with refcount 1.
  (func $RT_StrConcat (param $AStr1 i64) (param $AStr2 i64) (result i64)
    (local $LLen1 i64)
    (local $LLen2 i64)
    (local $LTotal i64)
    (local $LRec i64)
    (local $LData i64)
    (local $LData1 i64)
    (local $LData2 i64)

    ;; Get length of first string (0 if nil)
    (if (i64.eqz (local.get $AStr1))
      (then (local.set $LLen1 (i64.const 0)))
      (else (local.set $LLen1 (i64.load offset=8 (local.get $AStr1)))))

    ;; Get length of second string (0 if nil)
    (if (i64.eqz (local.get $AStr2))
      (then (local.set $LLen2 (i64.const 0)))
      (else (local.set $LLen2 (i64.load offset=8 (local.get $AStr2)))))

    ;; Total length
    (local.set $LTotal (i64.add (local.get $LLen1) (local.get $LLen2)))

    ;; Allocate result
    (local.set $LRec (call $RT_StrAlloc (local.get $LTotal)))
    (local.set $LData (i64.load offset=24 (local.get $LRec)))

    ;; Copy first string if non-empty
    (if (i64.gt_u (local.get $LLen1) (i64.const 0))
      (then
        (local.set $LData1 (i64.load offset=24 (local.get $AStr1)))
        (memory.copy (local.get $LData) (local.get $LData1) (local.get $LLen1))))

    ;; Copy second string after first
    (if (i64.gt_u (local.get $LLen2) (i64.const 0))
      (then
        (local.set $LData2 (i64.load offset=24 (local.get $AStr2)))
        (memory.copy
          (i64.add (local.get $LData) (local.get $LLen1))
          (local.get $LData2)
          (local.get $LLen2))))

    ;; Set length and null-terminate
    (i64.store offset=8 (local.get $LRec) (local.get $LTotal))
    (i32.store8 (i64.add (local.get $LData) (local.get $LTotal)) (i32.const 0))

    (local.get $LRec))

  ;; RT_StrAssign(ADest: i64, ASrc: i64)
  ;; Assignment with reference counting.
  ;; ADest is pointer to a string variable (pointer to pointer to TStringRec).
  ;; AddRefs source FIRST (self-assignment safe), then stores, then releases old.
  (func $RT_StrAssign (param $ADest i64) (param $ASrc i64)
    (local $LOld i64)

    ;; Read old value from destination slot
    (local.set $LOld (i64.load (local.get $ADest)))

    ;; AddRef source first (self-assignment safe: 1 -> 2)
    (call $RT_StrAddRef (local.get $ASrc))

    ;; Store new value in slot
    (i64.store (local.get $ADest) (local.get $ASrc))

    ;; Release old value last (self-assignment safe: 2 -> 1)
    (call $RT_StrRelease (local.get $LOld)))

  ;; RT_StrSetLength(ADest: i64, ANewLen: i64)
  ;; Resizes the string in the variable slot to ANewLen bytes.
  ;; Allocates new, copies min(old,new), zero-fills tail, releases old.
  (func $RT_StrSetLength (param $ADest i64) (param $ANewLen i64)
    (local $LOld i64)
    (local $LNew i64)
    (local $LOldLen i64)
    (local $LCopyLen i64)
    (local $LOldData i64)
    (local $LNewData i64)

    ;; Read old string from slot
    (local.set $LOld (i64.load (local.get $ADest)))

    ;; Allocate new string
    (local.set $LNew (call $RT_StrAlloc (local.get $ANewLen)))

    ;; Get old length (0 if nil)
    (local.set $LOldLen (call $RT_StrLen (local.get $LOld)))

    ;; CopyLen = min(OldLen, NewLen)
    (if (i64.lt_u (local.get $LOldLen) (local.get $ANewLen))
      (then (local.set $LCopyLen (local.get $LOldLen)))
      (else (local.set $LCopyLen (local.get $ANewLen))))

    ;; Get new data pointer
    (local.set $LNewData (i64.load offset=24 (local.get $LNew)))

    ;; Copy surviving prefix
    (if (i64.gt_u (local.get $LCopyLen) (i64.const 0))
      (then
        (local.set $LOldData (i64.load offset=24 (local.get $LOld)))
        (memory.copy (local.get $LNewData) (local.get $LOldData) (local.get $LCopyLen))))

    ;; Zero-fill grown tail + null terminator
    (memory.fill
      (i64.add (local.get $LNewData) (local.get $LCopyLen))
      (i32.const 0)
      (i64.add
        (i64.sub (local.get $ANewLen) (local.get $LCopyLen))
        (i64.const 1)))

    ;; Set new length
    (i64.store offset=8 (local.get $LNew) (local.get $ANewLen))

    ;; Release old, store new in slot
    (call $RT_StrRelease (local.get $LOld))
    (i64.store (local.get $ADest) (local.get $LNew)))

  ;; RT_StrCompare(AStr1: i64, AStr2: i64) -> i64
  ;; Lexicographic comparison. Returns -1, 0, or 1. Nil-safe.
  (func $RT_StrCompare (param $AStr1 i64) (param $AStr2 i64) (result i64)
    (local $LLen1 i64)
    (local $LLen2 i64)
    (local $LMinLen i64)
    (local $LData1 i64)
    (local $LData2 i64)
    (local $LResult i32)

    ;; Both nil -> equal
    (if (i64.eqz (local.get $AStr1))
      (then
        (if (i64.eqz (local.get $AStr2))
          (then (return (i64.const 0))))
        (return (i64.const -1))))  ;; str1=nil, str2!=nil -> less

    ;; str1!=nil, str2=nil -> greater
    (if (i64.eqz (local.get $AStr2))
      (then (return (i64.const 1))))

    ;; Get lengths
    (local.set $LLen1 (i64.load offset=8 (local.get $AStr1)))
    (local.set $LLen2 (i64.load offset=8 (local.get $AStr2)))

    ;; Get data pointers
    (local.set $LData1 (i64.load offset=24 (local.get $AStr1)))
    (local.set $LData2 (i64.load offset=24 (local.get $AStr2)))

    ;; MinLen = min(Len1, Len2)
    (if (i64.lt_u (local.get $LLen1) (local.get $LLen2))
      (then (local.set $LMinLen (local.get $LLen1)))
      (else (local.set $LMinLen (local.get $LLen2))))

    ;; memcmp
    (local.set $LResult
      (call $rt_memcmp (local.get $LData1) (local.get $LData2) (local.get $LMinLen)))

    (if (i32.lt_s (local.get $LResult) (i32.const 0))
      (then (return (i64.const -1))))
    (if (i32.gt_s (local.get $LResult) (i32.const 0))
      (then (return (i64.const 1))))

    ;; Bytes equal -- compare by length
    (if (i64.lt_u (local.get $LLen1) (local.get $LLen2))
      (then (return (i64.const -1))))
    (if (i64.gt_u (local.get $LLen1) (local.get $LLen2))
      (then (return (i64.const 1))))

    (i64.const 0))


;;------------------------------------------------------------------------------
;; I/O Primitives (Atom R5)
;;
;; The runtime does NOT implement printf. Instead it provides typed write
;; functions. The emitter decomposes print statements at compile time (the
;; format string is always a literal) and emits a sequence of these calls.
;;
;; WASI fd_write is the only external I/O call. Everything else builds on it.
;;
;; Fixed low-memory layout (page 0, reserved for runtime):
;;   256-271: iovec struct {buf_ptr: i64, buf_len: i64}
;;   272-279: nwritten output (i64)
;;   280-407: number conversion scratch buffer (128 bytes)
;;------------------------------------------------------------------------------

  ;; Write ALen bytes from ABuf to file descriptor AFd via WASI fd_write.
  (func $rt_fd_write (param $AFd i32) (param $ABuf i64) (param $ALen i64)
    ;; Build iovec at fixed address 256
    (i64.store (i64.const 256) (local.get $ABuf))     ;; iovec.buf_ptr
    (i64.store (i64.const 264) (local.get $ALen))     ;; iovec.buf_len
    ;; Call fd_write: fd, iovs_ptr, iovs_count=1, nwritten_ptr
    (drop (call $wasi_fd_write
      (local.get $AFd)
      (i64.const 256)     ;; iovs ptr
      (i32.const 1)       ;; iovs count
      (i64.const 272))))  ;; nwritten ptr

  ;; rt_write_bytes(ABuf: i64, ALen: i64)
  ;; Write raw bytes to stdout (fd=1).
  (func $rt_write_bytes (param $ABuf i64) (param $ALen i64)
    (call $rt_fd_write (i32.const 1) (local.get $ABuf) (local.get $ALen)))

  ;; rt_write_cstr(APtr: i64)
  ;; Write a null-terminated C string to stdout.
  (func $rt_write_cstr (param $APtr i64)
    (local $LLen i64)
    ;; Find length by scanning for null
    (local.set $LLen (i64.const 0))
    (if (i64.eqz (local.get $APtr)) (then (return)))
    (block $done
      (loop $scan
        (br_if $done
          (i32.eqz (i32.load8_u (i64.add (local.get $APtr) (local.get $LLen)))))
        (local.set $LLen (i64.add (local.get $LLen) (i64.const 1)))
        (br $scan)))
    (if (i64.gt_u (local.get $LLen) (i64.const 0))
      (then (call $rt_write_bytes (local.get $APtr) (local.get $LLen)))))

  ;; rt_write_managed_str(AStr: i64)
  ;; Write a managed string (TStringRec pointer) to stdout.
  ;; Writes the Data buffer with Length bytes. Nil = no output.
  (func $rt_write_managed_str (param $AStr i64)
    (if (i64.eqz (local.get $AStr)) (then (return)))
    (call $rt_write_bytes
      (i64.load offset=24 (local.get $AStr))   ;; Data pointer
      (i64.load offset=8  (local.get $AStr))))  ;; Length

  ;; rt_write_char(AChar: i32)
  ;; Write a single byte character to stdout.
  (func $rt_write_char (param $AChar i32)
    ;; Store byte at scratch address 280, write 1 byte
    (i32.store8 (i64.const 280) (local.get $AChar))
    (call $rt_write_bytes (i64.const 280) (i64.const 1)))

  ;; rt_write_newline()
  ;; Write a newline to stdout.
  (func $rt_write_newline
    (i32.store8 (i64.const 280) (i32.const 10))
    (call $rt_write_bytes (i64.const 280) (i64.const 1)))

  ;;----------------------------------------------------------------------------
  ;; format() append family
  ;; Builds a managed string (TStringRec) held by the caller. Every routine
  ;; takes the handle first and returns it so the emitter can chain calls as
  ;; one expression. Number conversion reuses the converters below via the
  ;; 280 scratch buffer, copied out immediately. No global state.
  ;;----------------------------------------------------------------------------

  ;; rt_fmt_new() -> i64  new empty string, capacity 64, refcount 1 (caller owns)
  (func $rt_fmt_new (result i64)
    (call $RT_StrAlloc (i64.const 64)))

  ;; rt_fmt_append(AStr, ASrc, ALen) -> AStr   the single growth point
  (func $rt_fmt_append (param $AStr i64) (param $ASrc i64) (param $ALen i64) (result i64)
    (local $LLen i64)
    (local $LNeed i64)
    (local $LCap i64)
    (local $LNewCap i64)
    (local $LData i64)
    (if (i64.eqz (local.get $ALen)) (then (return (local.get $AStr))))
    (local.set $LLen (i64.load offset=8 (local.get $AStr)))
    (local.set $LCap (i64.load offset=16 (local.get $AStr)))
    (local.set $LNeed (i64.add (local.get $LLen) (local.get $ALen)))
    (if (i64.gt_u (local.get $LNeed) (local.get $LCap))
      (then
        (local.set $LNewCap (i64.shl (local.get $LCap) (i64.const 1)))
        (if (i64.lt_u (local.get $LNewCap) (local.get $LNeed))
          (then (local.set $LNewCap (local.get $LNeed))))
        ;; Data block is cap+1 bytes (NUL); RT_ReAllocMem copies the old prefix
        (i64.store offset=24 (local.get $AStr)
          (call $RT_ReAllocMem
            (i64.load offset=24 (local.get $AStr))
            (i64.add (local.get $LNewCap) (i64.const 1))))
        (i64.store offset=16 (local.get $AStr) (local.get $LNewCap))))
    (local.set $LData (i64.load offset=24 (local.get $AStr)))
    (memory.copy
      (i64.add (local.get $LData) (local.get $LLen))
      (local.get $ASrc)
      (local.get $ALen))
    (i64.store offset=8 (local.get $AStr) (local.get $LNeed))
    (i32.store8 (i64.add (local.get $LData) (local.get $LNeed)) (i32.const 0))
    (local.get $AStr))

  ;; rt_fmt_cstr(AStr, APtr) -> AStr   append a NUL-terminated C string (nil-safe)
  (func $rt_fmt_cstr (param $AStr i64) (param $APtr i64) (result i64)
    (local $LLen i64)
    (if (i64.eqz (local.get $APtr)) (then (return (local.get $AStr))))
    (local.set $LLen (i64.const 0))
    (block $done
      (loop $scan
        (br_if $done
          (i32.eqz (i32.load8_u (i64.add (local.get $APtr) (local.get $LLen)))))
        (local.set $LLen (i64.add (local.get $LLen) (i64.const 1)))
        (br $scan)))
    (call $rt_fmt_append (local.get $AStr) (local.get $APtr) (local.get $LLen)))

  ;; rt_fmt_str(AStr, ASrc) -> AStr   append a managed string (nil = nothing)
  (func $rt_fmt_str (param $AStr i64) (param $ASrc i64) (result i64)
    (if (i64.eqz (local.get $ASrc)) (then (return (local.get $AStr))))
    (call $rt_fmt_append (local.get $AStr)
      (i64.load offset=24 (local.get $ASrc))
      (i64.load offset=8  (local.get $ASrc))))

  ;; rt_fmt_char(AStr, AChar) -> AStr
  (func $rt_fmt_char (param $AStr i64) (param $AChar i32) (result i64)
    (i32.store8 (i64.const 280) (local.get $AChar))
    (call $rt_fmt_append (local.get $AStr) (i64.const 280) (i64.const 1)))

  ;; rt_fmt_i64(AStr, AVal) -> AStr   signed decimal
  (func $rt_fmt_i64 (param $AStr i64) (param $AVal i64) (result i64)
    (call $rt_fmt_append (local.get $AStr) (i64.const 280)
      (call $rt_i64_to_dec (local.get $AVal) (i64.const 280))))

  ;; rt_fmt_u64(AStr, AVal) -> AStr   unsigned decimal
  (func $rt_fmt_u64 (param $AStr i64) (param $AVal i64) (result i64)
    (call $rt_fmt_append (local.get $AStr) (i64.const 280)
      (call $rt_u64_to_dec (local.get $AVal) (i64.const 280))))

  ;; rt_fmt_hex(AStr, AVal) -> AStr
  (func $rt_fmt_hex (param $AStr i64) (param $AVal i64) (result i64)
    (call $rt_fmt_append (local.get $AStr) (i64.const 280)
      (call $rt_i64_to_hex (local.get $AVal) (i64.const 280))))

  ;; rt_fmt_hex_upper(AStr, AVal) -> AStr
  (func $rt_fmt_hex_upper (param $AStr i64) (param $AVal i64) (result i64)
    (call $rt_fmt_append (local.get $AStr) (i64.const 280)
      (call $rt_i64_to_hex_upper (local.get $AVal) (i64.const 280))))

  ;; rt_fmt_f64(AStr, AVal) -> AStr
  (func $rt_fmt_f64 (param $AStr i64) (param $AVal f64) (result i64)
    (call $rt_fmt_append (local.get $AStr) (i64.const 280)
      (call $rt_f64_to_str (local.get $AVal) (i64.const 280))))

  ;; rt_fmt_f64_prec(AStr, AVal, APrec) -> AStr
  (func $rt_fmt_f64_prec (param $AStr i64) (param $AVal f64) (param $APrec i32) (result i64)
    (call $rt_fmt_append (local.get $AStr) (i64.const 280)
      (call $rt_f64_to_str_prec (local.get $AVal) (i64.const 280) (local.get $APrec))))

  ;; rt_fmt_ptr(AStr, AVal) -> AStr   "0x" + hex
  (func $rt_fmt_ptr (param $AStr i64) (param $AVal i64) (result i64)
    (i32.store8 (i64.const 280) (i32.const 48))  ;; '0'
    (i32.store8 (i64.const 281) (i32.const 120)) ;; 'x'
    (call $rt_fmt_hex
      (call $rt_fmt_append (local.get $AStr) (i64.const 280) (i64.const 2))
      (local.get $AVal)))

  ;;-- Number-to-string conversion --
  ;; All converters write into the scratch buffer at 280 and return the
  ;; length written. The caller can then rt_write_bytes(280, len).

  ;; rt_i64_to_dec(AVal: i64, ABuf: i64) -> i64
  ;; Converts signed i64 to decimal ASCII at ABuf. Returns length.
  (func $rt_i64_to_dec (param $AVal i64) (param $ABuf i64) (result i64)
    (local $LNeg i32)
    (local $LPos i64)
    (local $LDigit i64)
    (local $LStart i64)
    (local $LEnd i64)
    (local $LTmp i32)

    (local.set $LNeg (i32.const 0))
    (local.set $LPos (i64.const 0))

    ;; Handle negative
    (if (i64.lt_s (local.get $AVal) (i64.const 0))
      (then
        (local.set $LNeg (i32.const 1))
        (local.set $AVal (i64.sub (i64.const 0) (local.get $AVal)))))

    ;; Handle zero
    (if (i64.eqz (local.get $AVal))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 48)) ;; '0'
        (return (i64.const 1))))

    ;; Extract digits in reverse order
    (block $done
      (loop $digits
        (br_if $done (i64.eqz (local.get $AVal)))
        (local.set $LDigit (i64.rem_u (local.get $AVal) (i64.const 10)))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LPos))
          (i32.add (i32.const 48) (i32.wrap_i64 (local.get $LDigit))))
        (local.set $AVal (i64.div_u (local.get $AVal) (i64.const 10)))
        (local.set $LPos (i64.add (local.get $LPos) (i64.const 1)))
        (br $digits)))

    ;; Append '-' for negative
    (if (local.get $LNeg)
      (then
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LPos))
          (i32.const 45)) ;; '-'
        (local.set $LPos (i64.add (local.get $LPos) (i64.const 1)))))

    ;; Reverse the string in-place
    (local.set $LStart (i64.const 0))
    (local.set $LEnd (i64.sub (local.get $LPos) (i64.const 1)))
    (block $rev_done
      (loop $rev
        (br_if $rev_done (i64.ge_u (local.get $LStart) (local.get $LEnd)))
        ;; Swap buf[start] and buf[end]
        (local.set $LTmp
          (i32.load8_u (i64.add (local.get $ABuf) (local.get $LStart))))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LStart))
          (i32.load8_u (i64.add (local.get $ABuf) (local.get $LEnd))))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LEnd))
          (local.get $LTmp))
        (local.set $LStart (i64.add (local.get $LStart) (i64.const 1)))
        (local.set $LEnd (i64.sub (local.get $LEnd) (i64.const 1)))
        (br $rev)))

    (local.get $LPos))

  ;; rt_u64_to_dec(AVal: i64, ABuf: i64) -> i64
  ;; Converts unsigned i64 to decimal ASCII at ABuf. Returns length.
  (func $rt_u64_to_dec (param $AVal i64) (param $ABuf i64) (result i64)
    (local $LPos i64)
    (local $LDigit i64)
    (local $LStart i64)
    (local $LEnd i64)
    (local $LTmp i32)

    (local.set $LPos (i64.const 0))

    ;; Handle zero
    (if (i64.eqz (local.get $AVal))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 48))
        (return (i64.const 1))))

    ;; Extract digits in reverse
    (block $done
      (loop $digits
        (br_if $done (i64.eqz (local.get $AVal)))
        (local.set $LDigit (i64.rem_u (local.get $AVal) (i64.const 10)))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LPos))
          (i32.add (i32.const 48) (i32.wrap_i64 (local.get $LDigit))))
        (local.set $AVal (i64.div_u (local.get $AVal) (i64.const 10)))
        (local.set $LPos (i64.add (local.get $LPos) (i64.const 1)))
        (br $digits)))

    ;; Reverse
    (local.set $LStart (i64.const 0))
    (local.set $LEnd (i64.sub (local.get $LPos) (i64.const 1)))
    (block $rev_done
      (loop $rev
        (br_if $rev_done (i64.ge_u (local.get $LStart) (local.get $LEnd)))
        (local.set $LTmp
          (i32.load8_u (i64.add (local.get $ABuf) (local.get $LStart))))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LStart))
          (i32.load8_u (i64.add (local.get $ABuf) (local.get $LEnd))))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LEnd))
          (local.get $LTmp))
        (local.set $LStart (i64.add (local.get $LStart) (i64.const 1)))
        (local.set $LEnd (i64.sub (local.get $LEnd) (i64.const 1)))
        (br $rev)))

    (local.get $LPos))

  ;; rt_i64_to_hex(AVal: i64, ABuf: i64) -> i64
  ;; Converts i64 to lowercase hex ASCII at ABuf. Returns length.
  (func $rt_i64_to_hex (param $AVal i64) (param $ABuf i64) (result i64)
    (call $rt_i64_to_hex_base (local.get $AVal) (local.get $ABuf) (i32.const 87)))  ;; 'a'-10

  ;; rt_i64_to_hex_upper(AVal: i64, ABuf: i64) -> i64
  ;; Converts i64 to uppercase hex ASCII at ABuf. Returns length.
  (func $rt_i64_to_hex_upper (param $AVal i64) (param $ABuf i64) (result i64)
    (call $rt_i64_to_hex_base (local.get $AVal) (local.get $ABuf) (i32.const 55)))  ;; 'A'-10

  ;; rt_i64_to_hex_base(AVal: i64, ABuf: i64, ALetterBase: i32) -> i64
  ;; Shared hex converter. ALetterBase is the byte value of the letter for
  ;; nibble 10 minus 10 (87 = lowercase, 55 = uppercase).
  (func $rt_i64_to_hex_base (param $AVal i64) (param $ABuf i64) (param $ALetterBase i32) (result i64)
    (local $LPos i64)
    (local $LNibble i32)
    (local $LStart i64)
    (local $LEnd i64)
    (local $LTmp i32)

    (local.set $LPos (i64.const 0))

    ;; Handle zero
    (if (i64.eqz (local.get $AVal))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 48))
        (return (i64.const 1))))

    ;; Extract hex digits in reverse
    (block $done
      (loop $digits
        (br_if $done (i64.eqz (local.get $AVal)))
        (local.set $LNibble (i32.and (i32.wrap_i64 (local.get $AVal)) (i32.const 15)))
        (if (i32.lt_u (local.get $LNibble) (i32.const 10))
          (then
            (i32.store8
              (i64.add (local.get $ABuf) (local.get $LPos))
              (i32.add (i32.const 48) (local.get $LNibble))))
          (else
            (i32.store8
              (i64.add (local.get $ABuf) (local.get $LPos))
              (i32.add (local.get $ALetterBase) (local.get $LNibble)))))
        (local.set $AVal (i64.shr_u (local.get $AVal) (i64.const 4)))
        (local.set $LPos (i64.add (local.get $LPos) (i64.const 1)))
        (br $digits)))

    ;; Reverse
    (local.set $LStart (i64.const 0))
    (local.set $LEnd (i64.sub (local.get $LPos) (i64.const 1)))
    (block $rev_done
      (loop $rev
        (br_if $rev_done (i64.ge_u (local.get $LStart) (local.get $LEnd)))
        (local.set $LTmp
          (i32.load8_u (i64.add (local.get $ABuf) (local.get $LStart))))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LStart))
          (i32.load8_u (i64.add (local.get $ABuf) (local.get $LEnd))))
        (i32.store8
          (i64.add (local.get $ABuf) (local.get $LEnd))
          (local.get $LTmp))
        (local.set $LStart (i64.add (local.get $LStart) (i64.const 1)))
        (local.set $LEnd (i64.sub (local.get $LEnd) (i64.const 1)))
        (br $rev)))

    (local.get $LPos))

  ;; rt_f64_to_str(AVal: f64, ABuf: i64) -> i64
  ;; Converts f64 to decimal ASCII at ABuf with 6 decimal places.
  ;; Handles negative, zero, NaN, infinity. Returns length.
  (func $rt_f64_to_str (param $AVal f64) (param $ABuf i64) (result i64)
    (local $LPos i64)
    (local $LIntPart i64)
    (local $LFracPart i64)
    (local $LFrac f64)
    (local $LAbs f64)
    (local $LDigitLen i64)
    (local $LI i32)

    (local.set $LPos (i64.const 0))

    ;; NaN check
    (if (f64.ne (local.get $AVal) (local.get $AVal))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 110))             ;; 'n'
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 1)) (i32.const 97))  ;; 'a'
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 2)) (i32.const 110)) ;; 'n'
        (return (i64.const 3))))

    ;; Infinity check
    (if (f64.eq (local.get $AVal) (f64.const inf))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 105))             ;; 'i'
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 1)) (i32.const 110)) ;; 'n'
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 2)) (i32.const 102)) ;; 'f'
        (return (i64.const 3))))
    (if (f64.eq (local.get $AVal) (f64.const -inf))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 45))              ;; '-'
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 1)) (i32.const 105)) ;; 'i'
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 2)) (i32.const 110)) ;; 'n'
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 3)) (i32.const 102)) ;; 'f'
        (return (i64.const 4))))

    ;; Handle negative
    (local.set $LAbs (local.get $AVal))
    (if (f64.lt (local.get $AVal) (f64.const 0))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 45)) ;; '-'
        (local.set $LPos (i64.const 1))
        (local.set $LAbs (f64.neg (local.get $AVal)))))

    ;; Integer part
    (local.set $LIntPart (i64.trunc_sat_f64_u (f64.floor (local.get $LAbs))))

    ;; Write integer part
    (local.set $LDigitLen
      (call $rt_u64_to_dec (local.get $LIntPart)
        (i64.add (local.get $ABuf) (local.get $LPos))))
    (local.set $LPos (i64.add (local.get $LPos) (local.get $LDigitLen)))

    ;; Decimal point
    (i32.store8 (i64.add (local.get $ABuf) (local.get $LPos)) (i32.const 46)) ;; '.'
    (local.set $LPos (i64.add (local.get $LPos) (i64.const 1)))

    ;; Fractional part: multiply by 10^6, truncate, write with leading zeros
    (local.set $LFrac
      (f64.sub (local.get $LAbs) (f64.floor (local.get $LAbs))))
    (local.set $LFracPart
      (i64.trunc_sat_f64_u
        (f64.add (f64.mul (local.get $LFrac) (f64.const 1000000)) (f64.const 0.5))))

    ;; Clamp to 6 digits (rounding can push to 1000000)
    (if (i64.ge_u (local.get $LFracPart) (i64.const 1000000))
      (then (local.set $LFracPart (i64.const 999999))))

    ;; Write 6 digits with leading zeros
    (local.set $LI (i32.const 5))
    (block $frac_done
      (loop $frac
        (br_if $frac_done (i32.lt_s (local.get $LI) (i32.const 0)))
        (i32.store8
          (i64.add (local.get $ABuf)
            (i64.add (local.get $LPos) (i64.extend_i32_u (local.get $LI))))
          (i32.add (i32.const 48)
            (i32.wrap_i64 (i64.rem_u (local.get $LFracPart) (i64.const 10)))))
        (local.set $LFracPart (i64.div_u (local.get $LFracPart) (i64.const 10)))
        (local.set $LI (i32.sub (local.get $LI) (i32.const 1)))
        (br $frac)))

    (local.set $LPos (i64.add (local.get $LPos) (i64.const 6)))

    (local.get $LPos))

  ;; -- Typed write-to-stdout functions --
  ;; The emitter decomposes print format strings at compile time and emits
  ;; a sequence of these calls.

  ;; rt_write_i64(AVal: i64)
  ;; Write signed i64 as decimal to stdout.
  (func $rt_write_i64 (param $AVal i64)
    (call $rt_write_bytes (i64.const 280)
      (call $rt_i64_to_dec (local.get $AVal) (i64.const 280))))

  ;; rt_write_u64(AVal: i64)
  ;; Write unsigned i64 as decimal to stdout.
  (func $rt_write_u64 (param $AVal i64)
    (call $rt_write_bytes (i64.const 280)
      (call $rt_u64_to_dec (local.get $AVal) (i64.const 280))))

  ;; rt_write_hex(AVal: i64)
  ;; Write i64 as hex to stdout.
  (func $rt_write_hex (param $AVal i64)
    (call $rt_write_bytes (i64.const 280)
      (call $rt_i64_to_hex (local.get $AVal) (i64.const 280))))

  ;; rt_write_hex_upper(AVal: i64)
  ;; Write i64 as uppercase hex to stdout.
  (func $rt_write_hex_upper (param $AVal i64)
    (call $rt_write_bytes (i64.const 280)
      (call $rt_i64_to_hex_upper (local.get $AVal) (i64.const 280))))

  ;; rt_write_f64(AVal: f64)
  ;; Write f64 as decimal to stdout.
  (func $rt_write_f64 (param $AVal f64)
    (call $rt_write_bytes (i64.const 280)
      (call $rt_f64_to_str (local.get $AVal) (i64.const 280))))

  ;; rt_f64_to_str_prec(AVal: f64, ABuf: i64, APrec: i32) -> i64
  ;; Like rt_f64_to_str but with caller-specified decimal places.
  ;; APrec=0 writes integer only (no dot). APrec<0 treated as 6.
  (func $rt_f64_to_str_prec (param $AVal f64) (param $ABuf i64)
    (param $APrec i32) (result i64)
    (local $LPos i64)
    (local $LIntPart i64)
    (local $LFracPart i64)
    (local $LFrac f64)
    (local $LAbs f64)
    (local $LDigitLen i64)
    (local $LI i32)
    (local $LScale f64)
    (local $LScaleI64 i64)

    (local.set $LPos (i64.const 0))

    ;; Default to 6 if negative
    (if (i32.lt_s (local.get $APrec) (i32.const 0))
      (then (local.set $APrec (i32.const 6))))

    ;; NaN check
    (if (f64.ne (local.get $AVal) (local.get $AVal))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 110))
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 1)) (i32.const 97))
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 2)) (i32.const 110))
        (return (i64.const 3))))

    ;; Infinity check
    (if (f64.eq (local.get $AVal) (f64.const inf))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 105))
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 1)) (i32.const 110))
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 2)) (i32.const 102))
        (return (i64.const 3))))
    (if (f64.eq (local.get $AVal) (f64.const -inf))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 45))
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 1)) (i32.const 105))
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 2)) (i32.const 110))
        (i32.store8 (i64.add (local.get $ABuf) (i64.const 3)) (i32.const 102))
        (return (i64.const 4))))

    ;; Handle negative
    (local.set $LAbs (local.get $AVal))
    (if (f64.lt (local.get $AVal) (f64.const 0))
      (then
        (i32.store8 (local.get $ABuf) (i32.const 45))
        (local.set $LPos (i64.const 1))
        (local.set $LAbs (f64.neg (local.get $AVal)))))

    ;; Integer part
    (local.set $LIntPart (i64.trunc_sat_f64_u (f64.floor (local.get $LAbs))))

    ;; Write integer part
    (local.set $LDigitLen
      (call $rt_u64_to_dec (local.get $LIntPart)
        (i64.add (local.get $ABuf) (local.get $LPos))))
    (local.set $LPos (i64.add (local.get $LPos) (local.get $LDigitLen)))

    ;; If precision is 0, no decimal point or fractional digits
    (if (i32.eqz (local.get $APrec))
      (then (return (local.get $LPos))))

    ;; Decimal point
    (i32.store8 (i64.add (local.get $ABuf) (local.get $LPos)) (i32.const 46))
    (local.set $LPos (i64.add (local.get $LPos) (i64.const 1)))

    ;; Compute scale = 10^APrec
    (local.set $LScale (f64.const 1))
    (local.set $LI (local.get $APrec))
    (block $scale_done
      (loop $scale_loop
        (br_if $scale_done (i32.le_s (local.get $LI) (i32.const 0)))
        (local.set $LScale (f64.mul (local.get $LScale) (f64.const 10)))
        (local.set $LI (i32.sub (local.get $LI) (i32.const 1)))
        (br $scale_loop)))

    ;; Fractional part: multiply by scale, round, truncate
    (local.set $LFrac
      (f64.sub (local.get $LAbs) (f64.floor (local.get $LAbs))))
    (local.set $LFracPart
      (i64.trunc_sat_f64_u
        (f64.add (f64.mul (local.get $LFrac) (local.get $LScale)) (f64.const 0.5))))

    ;; Clamp (rounding can push over)
    (local.set $LScaleI64 (i64.trunc_sat_f64_u (local.get $LScale)))
    (if (i64.ge_u (local.get $LFracPart) (local.get $LScaleI64))
      (then (local.set $LFracPart (i64.sub (local.get $LScaleI64) (i64.const 1)))))

    ;; Write APrec digits with leading zeros (right to left)
    (local.set $LI (i32.sub (local.get $APrec) (i32.const 1)))
    (block $frac_done
      (loop $frac
        (br_if $frac_done (i32.lt_s (local.get $LI) (i32.const 0)))
        (i32.store8
          (i64.add (local.get $ABuf)
            (i64.add (local.get $LPos) (i64.extend_i32_u (local.get $LI))))
          (i32.add (i32.const 48)
            (i32.wrap_i64 (i64.rem_u (local.get $LFracPart) (i64.const 10)))))
        (local.set $LFracPart (i64.div_u (local.get $LFracPart) (i64.const 10)))
        (local.set $LI (i32.sub (local.get $LI) (i32.const 1)))
        (br $frac)))

    (local.set $LPos (i64.add (local.get $LPos) (i64.extend_i32_u (local.get $APrec))))

    (local.get $LPos))

  ;; rt_write_f64_prec(AVal: f64, APrec: i32)
  ;; Write f64 with specified decimal places to stdout.
  (func $rt_write_f64_prec (param $AVal f64) (param $APrec i32)
    (call $rt_write_bytes (i64.const 280)
      (call $rt_f64_to_str_prec (local.get $AVal) (i64.const 280) (local.get $APrec))))

  ;; rt_write_ptr(AVal: i64)
  ;; Write pointer as "0x" + hex to stdout.
  (func $rt_write_ptr (param $AVal i64)
    ;; Write "0x" prefix
    (i32.store8 (i64.const 280) (i32.const 48))  ;; '0'
    (i32.store8 (i64.const 281) (i32.const 120)) ;; 'x'
    (call $rt_write_bytes (i64.const 280) (i64.const 2))
    ;; Write hex value
    (call $rt_write_hex (local.get $AVal)))


;;------------------------------------------------------------------------------
;; Intrinsics + Dynamic Arrays (Atom R6)
;;
;; Dynamic array layout in linear memory:
;;   [count: i64 (8 bytes)] [element 0] [element 1] ...
;;   The pointer returned to user code points to element 0.
;;   count lives at ptr - 8.
;;------------------------------------------------------------------------------

  ;; RT_DynLen(APtr: i64) -> i64
  ;; Returns element count of a dynamic array. 0 if nil.
  ;; Count is stored at ptr - 8.
  (func $RT_DynLen (param $APtr i64) (result i64)
    (if (i64.eqz (local.get $APtr))
      (then (return (i64.const 0))))
    (i64.load (i64.sub (local.get $APtr) (i64.const 8))))

  ;; RT_Len(ATag: i64, AVal: i64) -> i64
  ;; Dispatches by tag: 0=string, 1=wstring, 2=dynarray.
  (func $RT_Len (param $ATag i64) (param $AVal i64) (result i64)
    ;; Tag 0: managed string
    (if (i64.eqz (local.get $ATag))
      (then (return (call $RT_StrLen (local.get $AVal)))))
    ;; Tag 1: wide string
    (if (i64.eq (local.get $ATag) (i64.const 1))
      (then (return (call $RT_WStrLen (local.get $AVal)))))
    ;; Tag 2: dynamic array
    (if (i64.eq (local.get $ATag) (i64.const 2))
      (then (return (call $RT_DynLen (local.get $AVal)))))
    (i64.const 0))

  ;; RT_SetLength(AVar: i64, ANewLen: i64, AElemSize: i64)
  ;; Resize a dynamic array. AVar is pointer to the array variable.
  ;; Layout: [count:i64][elements...]. Pointer in *AVar points to elements.
  (func $RT_SetLength (param $AVar i64) (param $ANewLen i64) (param $AElemSize i64)
    (local $LOldPtr i64)
    (local $LOldCount i64)
    (local $LBlockSize i64)
    (local $LBlock i64)
    (local $LNewPtr i64)
    (local $LCopyBytes i64)
    (local $LCopyCount i64)

    (local.set $LOldPtr (i64.load (local.get $AVar)))

    ;; Old count
    (if (i64.eqz (local.get $LOldPtr))
      (then (local.set $LOldCount (i64.const 0)))
      (else (local.set $LOldCount
        (i64.load (i64.sub (local.get $LOldPtr) (i64.const 8))))))

    ;; New length = 0: free and nil
    (if (i64.eqz (local.get $ANewLen))
      (then
        (if (i64.ne (local.get $LOldPtr) (i64.const 0))
          (then
            (call $RT_FreeMem (i64.sub (local.get $LOldPtr) (i64.const 8)))))
        (i64.store (local.get $AVar) (i64.const 0))
        (return)))

    ;; Block size = 8 (count header) + newlen * elemsize
    (local.set $LBlockSize
      (i64.add (i64.const 8) (i64.mul (local.get $ANewLen) (local.get $AElemSize))))

    ;; First allocation or resize
    (if (i64.eqz (local.get $LOldPtr))
      (then
        ;; Fresh allocation, zero-filled
        (local.set $LBlock (call $RT_AllocMem (local.get $LBlockSize)))
        (i64.store (local.get $LBlock) (local.get $ANewLen))
        (i64.store (local.get $AVar) (i64.add (local.get $LBlock) (i64.const 8))))
      (else
        ;; Realloc existing block
        (local.set $LBlock
          (call $RT_ReAllocMem
            (i64.sub (local.get $LOldPtr) (i64.const 8))
            (local.get $LBlockSize)))
        ;; Update count
        (i64.store (local.get $LBlock) (local.get $ANewLen))
        (local.set $LNewPtr (i64.add (local.get $LBlock) (i64.const 8)))
        ;; Zero-fill grown tail if larger
        (if (i64.gt_u (local.get $ANewLen) (local.get $LOldCount))
          (then
            (memory.fill
              (i64.add (local.get $LNewPtr)
                (i64.mul (local.get $LOldCount) (local.get $AElemSize)))
              (i32.const 0)
              (i64.mul
                (i64.sub (local.get $ANewLen) (local.get $LOldCount))
                (local.get $AElemSize)))))
        (i64.store (local.get $AVar) (local.get $LNewPtr)))))

  ;; RT_DynResize(AOldPtr: i64, ANewLen: i64, AElemSize: i64) -> i64
  ;; Functional version of RT_SetLength. Returns new array pointer.
  (func $RT_DynResize (param $AOldPtr i64) (param $ANewLen i64)
    (param $AElemSize i64) (result i64)
    (local $LOldCount i64)
    (local $LBlockSize i64)
    (local $LBlock i64)
    (local $LNewPtr i64)

    ;; Old count
    (if (i64.eqz (local.get $AOldPtr))
      (then (local.set $LOldCount (i64.const 0)))
      (else (local.set $LOldCount
        (i64.load (i64.sub (local.get $AOldPtr) (i64.const 8))))))

    ;; New length = 0: free and return nil
    (if (i64.eqz (local.get $ANewLen))
      (then
        (if (i64.ne (local.get $AOldPtr) (i64.const 0))
          (then
            (call $RT_FreeMem (i64.sub (local.get $AOldPtr) (i64.const 8)))))
        (return (i64.const 0))))

    ;; Block size = 8 (count header) + newlen * elemsize
    (local.set $LBlockSize
      (i64.add (i64.const 8) (i64.mul (local.get $ANewLen) (local.get $AElemSize))))

    (if (i64.eqz (local.get $AOldPtr))
      (then
        (local.set $LBlock (call $RT_AllocMem (local.get $LBlockSize)))
        (i64.store (local.get $LBlock) (local.get $ANewLen))
        (return (i64.add (local.get $LBlock) (i64.const 8))))
      (else
        (local.set $LBlock
          (call $RT_ReAllocMem
            (i64.sub (local.get $AOldPtr) (i64.const 8))
            (local.get $LBlockSize)))
        (i64.store (local.get $LBlock) (local.get $ANewLen))
        (local.set $LNewPtr (i64.add (local.get $LBlock) (i64.const 8)))
        (if (i64.gt_u (local.get $ANewLen) (local.get $LOldCount))
          (then
            (memory.fill
              (i64.add (local.get $LNewPtr)
                (i64.mul (local.get $LOldCount) (local.get $AElemSize)))
              (i32.const 0)
              (i64.mul
                (i64.sub (local.get $ANewLen) (local.get $LOldCount))
                (local.get $AElemSize)))))
        (return (local.get $LNewPtr))))

    (unreachable))

  ;; RT_DynFree(APtr: i64)
  ;; Frees a dynamic array block. Nil-safe.
  (func $RT_DynFree (param $APtr i64)
    (if (i64.eqz (local.get $APtr)) (then (return)))
    (call $RT_FreeMem (i64.sub (local.get $APtr) (i64.const 8))))

  ;; RT_ArrayRelease(APtr: i64, ACount: i64, AStride: i64, AKind: i32)
  ;; Release managed elements in a fixed array.
  ;; AKind: 0=string (RT_StrRelease), 1=heap ptr (RT_FreeMem), 2=dynarray (RT_DynFree)
  (func $RT_ArrayRelease (param $APtr i64) (param $ACount i64)
    (param $AStride i64) (param $AKind i32)
    (local $LI i64)
    (local $LElem i64)

    (local.set $LI (i64.const 0))
    (block $done
      (loop $each
        (br_if $done (i64.ge_u (local.get $LI) (local.get $ACount)))
        ;; Load element pointer at ptr + i * stride
        (local.set $LElem
          (i64.load (i64.add (local.get $APtr)
            (i64.mul (local.get $LI) (local.get $AStride)))))
        ;; Dispatch by kind
        (if (i32.eqz (local.get $AKind))
          (then (call $RT_StrRelease (local.get $LElem)))
          (else (if (i32.eq (local.get $AKind) (i32.const 1))
            (then (call $RT_FreeMem (local.get $LElem)))
            (else (if (i32.eq (local.get $AKind) (i32.const 2))
              (then (call $RT_DynFree (local.get $LElem))))))))
        (local.set $LI (i64.add (local.get $LI) (i64.const 1)))
        (br $each))))

  ;; RT_ArrayReleaseComposite(APtr: i64, ACount: i64, AStride: i64, AThunk: i64)
  ;; Release composite elements via a per-type thunk function.
  ;; AThunk is a function reference (table index) called with element address.
  (func $RT_ArrayReleaseComposite (param $APtr i64) (param $ACount i64)
    (param $AStride i64) (param $AThunk i64)
    (local $LI i64)

    (local.set $LI (i64.const 0))
    (block $done
      (loop $each
        (br_if $done (i64.ge_u (local.get $LI) (local.get $ACount)))
        ;; Call thunk with address of element at ptr + i * stride
        (call_indirect (type $rt_thunk_type)
          (i64.add (local.get $APtr)
            (i64.mul (local.get $LI) (local.get $AStride)))
          (i32.wrap_i64 (local.get $AThunk)))
        (local.set $LI (i64.add (local.get $LI) (i64.const 1)))
        (br $each))))


;;------------------------------------------------------------------------------
;; Wide Strings (Atom R7)
;;
;; Wide strings are TStringRecs (see layout above): the same refcounted,
;; UTF-8-backed record as "string", with the UTF-16 view produced on demand
;; by RT_WStrData and cached in Data16. The RT_WStr* routines only differ
;; in measuring and comparing in 16-bit units. Nil (0) is empty.
;;------------------------------------------------------------------------------

  ;; RT_WStrLen(AStr: i64) -> i64
  ;; Returns length in 16-bit units (excl. terminator). 0 if nil.
  (func $RT_WStrLen (param $AStr i64) (result i64)
    (local $LBuf i64)
    (local $LLen i64)
    (if (i64.eqz (local.get $AStr)) (then (return (i64.const 0))))
    (local.set $LBuf (call $RT_WStrData (local.get $AStr)))
    (local.set $LLen (i64.const 0))
    (block $done
      (loop $scan
        (br_if $done
          (i32.eqz
            (i32.load16_u
              (i64.add (local.get $LBuf)
                (i64.mul (local.get $LLen) (i64.const 2))))))
        (local.set $LLen (i64.add (local.get $LLen) (i64.const 1)))
        (br $scan)))
    (local.get $LLen))

  ;; RT_WStrConcat(AStr1: i64, AStr2: i64) -> i64
  ;; Concatenates two wide strings. Same record model as RT_StrConcat.
  (func $RT_WStrConcat (param $AStr1 i64) (param $AStr2 i64) (result i64)
    (call $RT_StrConcat (local.get $AStr1) (local.get $AStr2)))

  ;; RT_WStrCompare(AStr1: i64, AStr2: i64) -> i64
  ;; Lexicographic comparison in 16-bit units. Returns -1, 0, or 1. Nil-safe.
  (func $RT_WStrCompare (param $AStr1 i64) (param $AStr2 i64) (result i64)
    (local $LLen1 i64)
    (local $LLen2 i64)
    (local $LMinLen i64)
    (local $LResult i32)

    ;; Nil checks
    (if (i64.eqz (local.get $AStr1))
      (then
        (if (i64.eqz (local.get $AStr2))
          (then (return (i64.const 0))))
        (return (i64.const -1))))
    (if (i64.eqz (local.get $AStr2))
      (then (return (i64.const 1))))

    (local.set $LLen1 (call $RT_WStrLen (local.get $AStr1)))
    (local.set $LLen2 (call $RT_WStrLen (local.get $AStr2)))

    ;; Min length
    (if (i64.lt_u (local.get $LLen1) (local.get $LLen2))
      (then (local.set $LMinLen (local.get $LLen1)))
      (else (local.set $LMinLen (local.get $LLen2))))

    ;; Compare the UTF-16 views (len * 2 bytes)
    (local.set $LResult
      (call $rt_memcmp
        (call $RT_WStrData (local.get $AStr1))
        (call $RT_WStrData (local.get $AStr2))
        (i64.mul (local.get $LMinLen) (i64.const 2))))

    (if (i32.lt_s (local.get $LResult) (i32.const 0))
      (then (return (i64.const -1))))
    (if (i32.gt_s (local.get $LResult) (i32.const 0))
      (then (return (i64.const 1))))

    ;; Equal prefix, compare lengths
    (if (i64.lt_u (local.get $LLen1) (local.get $LLen2))
      (then (return (i64.const -1))))
    (if (i64.gt_u (local.get $LLen1) (local.get $LLen2))
      (then (return (i64.const 1))))

    (i64.const 0))

  ;; RT_WStrFromLiteral(AData: i64, ALen: i64) -> i64
  ;; Creates a new wide string from ALen UTF-8 literal bytes. Same record
  ;; model as RT_StrFromLiteral; the UTF-16 view is built on first use.
  (func $RT_WStrFromLiteral (param $AData i64) (param $ALen i64) (result i64)
    (call $RT_StrFromLiteral (local.get $AData) (local.get $ALen)))


;;------------------------------------------------------------------------------
;; Exceptions (Atom R8)
;;
;; Runtime-raised exception codes (RT_RaiseCode):
;;   1  RT_EXC_SET_RANGE   set element outside 0..63     (Atom R11)
;;   2  RT_EXC_DIV_ZERO    integer div/mod by zero       (this file)
;;
;; Wasm native exception handling via tags + try_table/catch/throw.
;; Much simpler than native SEH or signal-based EH.
;;------------------------------------------------------------------------------

  ;; Exception tag: carries error code (i32) and message pointer (i64)
  (tag $myr_exn (param i32 i64))

  ;; Exception state globals
  (global $rt_exc_code (mut i32) (i32.const 0))
  (global $rt_exc_msg (mut i64) (i64.const 0))

  ;; RT_Raise(ACode: i32, AMsg: i64)
  ;; Throws an exception with code and message.
  (func $RT_Raise (param $ACode i32) (param $AMsg i64)
    (throw $myr_exn (local.get $ACode) (local.get $AMsg)))

  ;; RT_RaiseCode(ACode: i32)
  ;; Throws an exception with code only (nil message).
  (func $RT_RaiseCode (param $ACode i32)
    (throw $myr_exn (local.get $ACode) (i64.const 0)))

  ;; RT_GetExceptionCode() -> i32
  ;; Returns the current exception code (set by catch handler).
  (func $RT_GetExceptionCode (result i32)
    (global.get $rt_exc_code))

  ;; RT_GetExceptionMsg() -> i64
  ;; Returns the current exception message pointer (set by catch handler).
  (func $RT_GetExceptionMsg (result i64)
    (global.get $rt_exc_msg))

  ;; RT_SetException(ACode: i32, AMsg: i64)
  ;; Called by catch handlers to store exception data in globals.
  ;; The runtime owns the message: the previous one is released here,
  ;; the last one by RT_ClearException at shutdown.
  (func $RT_SetException (param $ACode i32) (param $AMsg i64)
    (call $RT_StrRelease (global.get $rt_exc_msg))
    (global.set $rt_exc_code (local.get $ACode))
    (global.set $rt_exc_msg (local.get $AMsg)))

  ;; RT_ClearException()
  ;; Releases the last stored exception message. Called at shutdown.
  (func $RT_ClearException
    (call $RT_StrRelease (global.get $rt_exc_msg))
    (global.set $rt_exc_msg (i64.const 0))
    (global.set $rt_exc_code (i32.const 0)))

  ;; RT_CheckDivI32(ADiv: i32) -> i32
  ;; Returns ADiv, or raises RT_EXC_DIV_ZERO (2) when it is zero.
  (func $RT_CheckDivI32 (param $ADiv i32) (result i32)
    (if (i32.eqz (local.get $ADiv))
      (then (call $RT_RaiseCode (i32.const 2))))
    (local.get $ADiv))

  ;; RT_CheckDivI64(ADiv: i64) -> i64
  ;; Returns ADiv, or raises RT_EXC_DIV_ZERO (2) when it is zero.
  (func $RT_CheckDivI64 (param $ADiv i64) (result i64)
    (if (i64.eqz (local.get $ADiv))
      (then (call $RT_RaiseCode (i32.const 2))))
    (local.get $ADiv))

;;------------------------------------------------------------------------------
;; Sets (Atom R11)
;;
;; A set is a raw i64 bitmask: bit N set <=> element N is a member.
;; Element range is 0..63. No heap allocation, nothing to free.
;; Out-of-range elements raise exception code RT_EXC_SET_RANGE (1).
;;------------------------------------------------------------------------------

  ;; RT_SetCreate() -> i64
  ;; Returns the empty set.
  (func $RT_SetCreate (result i64)
    (i64.const 0))

  ;; RT_SetCheckElem(AElem: i64)
  ;; Raises RT_EXC_SET_RANGE if AElem is outside 0..63.
  (func $RT_SetCheckElem (param $AElem i64)
    (if (i64.gt_u (local.get $AElem) (i64.const 63))
      (then
        (call $RT_RaiseCode (i32.const 1)))))

  ;; RT_SetAdd(ASet: i64, AElem: i64) -> i64
  ;; Returns ASet with AElem included.
  (func $RT_SetAdd (param $ASet i64) (param $AElem i64) (result i64)
    (call $RT_SetCheckElem (local.get $AElem))
    (i64.or (local.get $ASet)
      (i64.shl (i64.const 1) (local.get $AElem))))

  ;; RT_SetAddRange(ASet: i64, ALo: i64, AHi: i64) -> i64
  ;; Returns ASet with every element ALo..AHi included. Unchanged if ALo > AHi.
  (func $RT_SetAddRange (param $ASet i64) (param $ALo i64) (param $AHi i64) (result i64)
    (local $LElem i64)
    (if (i64.gt_s (local.get $ALo) (local.get $AHi))
      (then
        (return (local.get $ASet))))
    (call $RT_SetCheckElem (local.get $ALo))
    (call $RT_SetCheckElem (local.get $AHi))
    (local.set $LElem (local.get $ALo))
    (block $done
      (loop $next
        (local.set $ASet (i64.or (local.get $ASet)
          (i64.shl (i64.const 1) (local.get $LElem))))
        (br_if $done (i64.eq (local.get $LElem) (local.get $AHi)))
        (local.set $LElem (i64.add (local.get $LElem) (i64.const 1)))
        (br $next)))
    (local.get $ASet))

  ;; RT_SetIn(AElem: i64, ASet: i64) -> i32
  ;; Returns 1 if AElem is a member of ASet. Out-of-range elements are never members.
  (func $RT_SetIn (param $AElem i64) (param $ASet i64) (result i32)
    (if (i64.gt_u (local.get $AElem) (i64.const 63))
      (then
        (return (i32.const 0))))
    (i32.wrap_i64
      (i64.and
        (i64.shr_u (local.get $ASet) (local.get $AElem))
        (i64.const 1))))

  ;; RT_SetUnion(A: i64, B: i64) -> i64
  (func $RT_SetUnion (param $A i64) (param $B i64) (result i64)
    (i64.or (local.get $A) (local.get $B)))

  ;; RT_SetInter(A: i64, B: i64) -> i64
  (func $RT_SetInter (param $A i64) (param $B i64) (result i64)
    (i64.and (local.get $A) (local.get $B)))

  ;; RT_SetDiff(A: i64, B: i64) -> i64
  ;; Elements of A that are not in B.
  (func $RT_SetDiff (param $A i64) (param $B i64) (result i64)
    (i64.and (local.get $A) (i64.xor (local.get $B) (i64.const -1))))

  ;; RT_SetEq(A: i64, B: i64) -> i32
  (func $RT_SetEq (param $A i64) (param $B i64) (result i32)
    (i64.eq (local.get $A) (local.get $B)))

  ;; RT_SetNe(A: i64, B: i64) -> i32
  (func $RT_SetNe (param $A i64) (param $B i64) (result i32)
    (i64.ne (local.get $A) (local.get $B)))

  ;; RT_SetSubset(A: i64, B: i64) -> i32
  ;; Returns 1 if every element of A is in B (A <= B).
  (func $RT_SetSubset (param $A i64) (param $B i64) (result i32)
    (i64.eqz (i64.and (local.get $A)
      (i64.xor (local.get $B) (i64.const -1)))))

  ;; RT_SetSuperset(A: i64, B: i64) -> i32
  ;; Returns 1 if every element of B is in A (A >= B).
  (func $RT_SetSuperset (param $A i64) (param $B i64) (result i32)
    (i64.eqz (i64.and (local.get $B)
      (i64.xor (local.get $A) (i64.const -1)))))


;;------------------------------------------------------------------------------
;; Lifecycle (Atom R9)
;;
;; Module finalizer registry and program shutdown.
;;------------------------------------------------------------------------------

  ;; Finalizer globals
  (global $rt_fin_count (mut i64) (i64.const 0))
  (global $rt_fin_slots (mut i64) (i64.const 0))

  ;; RT_RegisterFinalizer(AFuncPtr: i64)
  ;; Stores a finalize function pointer for LIFO execution at shutdown.
  ;; Lazy-allocates slot array. Max 256 finalizers.
  (func $RT_RegisterFinalizer (param $AFuncPtr i64)
    ;; Lazy-allocate (256 slots * 8 bytes = 2048)
    (if (i64.eqz (global.get $rt_fin_slots))
      (then
        (global.set $rt_fin_slots (call $RT_AllocMem (i64.const 2048)))))

    ;; Bounds check
    (if (i64.ge_u (global.get $rt_fin_count) (i64.const 256))
      (then (return)))

    ;; Store at slots[count]
    (i64.store
      (i64.add (global.get $rt_fin_slots)
        (i64.mul (global.get $rt_fin_count) (i64.const 8)))
      (local.get $AFuncPtr))

    (global.set $rt_fin_count
      (i64.add (global.get $rt_fin_count) (i64.const 1))))

  ;; RT_RunFinalizers()
  ;; Runs all registered finalizers in LIFO order, then frees the slot array.
  (func $RT_RunFinalizers
    (local $LI i64)
    (local $LIdx i64)
    (local $LCount i64)

    (if (i64.eqz (global.get $rt_fin_slots)) (then (return)))

    (local.set $LCount (global.get $rt_fin_count))
    (local.set $LI (i64.const 0))
    (block $done
      (loop $each
        (br_if $done (i64.ge_u (local.get $LI) (local.get $LCount)))
        ;; Reverse index for LIFO
        (local.set $LIdx
          (i64.sub (i64.sub (local.get $LCount) (i64.const 1)) (local.get $LI)))
        ;; Load function pointer and call_indirect
        (call_indirect (type $rt_void_func)
          (i32.wrap_i64
            (i64.load
              (i64.add (global.get $rt_fin_slots)
                (i64.mul (local.get $LIdx) (i64.const 8))))))
        (local.set $LI (i64.add (local.get $LI) (i64.const 1)))
        (br $each)))

    ;; Free slot array
    (call $RT_FreeMem (global.get $rt_fin_slots))
    (global.set $rt_fin_slots (i64.const 0))
    (global.set $rt_fin_count (i64.const 0)))

  ;; RT_Halt(AExitCode: i32)
  ;; Runs finalizers, then exits via WASI proc_exit.
  (func $RT_Halt (param $AExitCode i32)
    (call $RT_RunFinalizers)
    (call $RT_DebugOnExit)
    (call $wasi_proc_exit (local.get $AExitCode)))

;;------------------------------------------------------------------------------
;; Command Line (Atom R9 continued)
;;
;; WASI args_sizes_get + args_get for argc/argv.
;;------------------------------------------------------------------------------

  ;; Command line globals
  (global $rt_argc (mut i64) (i64.const 0))
  (global $rt_argv (mut i64) (i64.const 0))  ;; pointer to array of string pointers
  (global $rt_argv_buf (mut i64) (i64.const 0))  ;; raw argv buffer

  ;; RT_InitCommandLine()
  ;; Calls WASI args_sizes_get + args_get to populate rt_argc/rt_argv/rt_argv_buf.
  ;; Must be called once at startup before any ParamCount/ParamStr use.
  ;; Uses scratch area at offset 0 for the two i64 output values (16 bytes).
  (func $RT_InitCommandLine
    (local $LArgc i64)
    (local $LBufSize i64)

    ;; args_sizes_get writes argc at offset 0, buf_size at offset 8
    (if (i32.ne
          (call $wasi_args_sizes_get (i64.const 0) (i64.const 8))
          (i32.const 0))
      (then (return)))

    ;; Read argc and buf_size from scratch area
    (local.set $LArgc (i64.load (i64.const 0)))
    (local.set $LBufSize (i64.load (i64.const 8)))

    ;; Nothing to do if no args
    (if (i64.eqz (local.get $LArgc))
      (then (return)))

    (global.set $rt_argc (local.get $LArgc))

    ;; Allocate argv pointer array (argc * 8 bytes for i64 pointers)
    (global.set $rt_argv
      (call $RT_AllocMem
        (i64.mul (local.get $LArgc) (i64.const 8))))

    ;; Allocate argv string buffer
    (global.set $rt_argv_buf
      (call $RT_AllocMem (local.get $LBufSize)))

    ;; args_get fills argv array and buffer
    (drop
      (call $wasi_args_get
        (global.get $rt_argv)
        (global.get $rt_argv_buf))))

  ;; RT_FreeCommandLine()
  ;; Frees the argv array and buffer. Called at shutdown.
  (func $RT_FreeCommandLine
    (if (i64.ne (global.get $rt_argv) (i64.const 0))
      (then
        (call $RT_FreeMem (global.get $rt_argv))
        (global.set $rt_argv (i64.const 0))))
    (if (i64.ne (global.get $rt_argv_buf) (i64.const 0))
      (then
        (call $RT_FreeMem (global.get $rt_argv_buf))
        (global.set $rt_argv_buf (i64.const 0))))
    (global.set $rt_argc (i64.const 0)))

  ;; RT_ParamCount() -> i64
  ;; Returns argc - 1 (number of arguments excluding program name).
  (func $RT_ParamCount (result i64)
    (if (i64.eqz (global.get $rt_argc))
      (then (return (i64.const 0))))
    (i64.sub (global.get $rt_argc) (i64.const 1)))

  ;; RT_ParamStr(AIndex: i64) -> i64
  ;; Returns argv[AIndex] as a managed string. 0-based: 0 = program name.
  ;; Returns nil if out of range or not initialized.
  (func $RT_ParamStr (param $AIndex i64) (result i64)
    (local $LCStr i64)
    (local $LLen i64)

    ;; Range check
    (if (i64.ge_u (local.get $AIndex) (global.get $rt_argc))
      (then (return (i64.const 0))))
    (if (i64.eqz (global.get $rt_argv))
      (then (return (i64.const 0))))

    ;; Get C string pointer from argv array
    (local.set $LCStr
      (i64.load
        (i64.add (global.get $rt_argv)
          (i64.mul (local.get $AIndex) (i64.const 8)))))

    ;; Find length
    (local.set $LLen (i64.const 0))
    (block $done
      (loop $scan
        (br_if $done
          (i32.eqz (i32.load8_u (i64.add (local.get $LCStr) (local.get $LLen)))))
        (local.set $LLen (i64.add (local.get $LLen) (i64.const 1)))
        (br $scan)))

    ;; Create managed string from C string data
    (call $RT_StrFromLiteral (local.get $LCStr) (local.get $LLen)))


;;------------------------------------------------------------------------------
;; Test Runner (Atom R10)
;;
;; Unit test registration, execution, and assertion framework.
;; Mirrors the native backend's RT_Test* functions.
;;------------------------------------------------------------------------------

  ;; Test runner globals
  (global $rt_test_count (mut i64) (i64.const 0))
  (global $rt_test_names (mut i64) (i64.const 0))   ;; array of name pointers
  (global $rt_test_funcs (mut i64) (i64.const 0))   ;; array of func pointers
  (global $rt_test_files (mut i64) (i64.const 0))   ;; array of file pointers
  (global $rt_test_lines (mut i64) (i64.const 0))   ;; array of line numbers
  (global $rt_test_failed (mut i64) (i64.const 0))  ;; failure flag per test
  (global $rt_test_errbuf (mut i64) (i64.const 0))  ;; error message buffer
  (global $rt_test_errpos (mut i64) (i64.const 0))  ;; write position in errbuf

  ;; RT_IsUnitTestMode() -> i64
  ;; Returns 1 if test buffer is allocated (tests were registered), 0 otherwise.
  (func $RT_IsUnitTestMode (result i64)
    (if (i64.ne (global.get $rt_test_errbuf) (i64.const 0))
      (then (return (i64.const 1))))
    (i64.const 0))

  ;; RT_TestRegister(AName: i64, AFunc: i64, AFile: i64, ALine: i64) -> i32
  ;; Registers a test block for execution. Max 256 tests.
  (func $RT_TestRegister (param $AName i64) (param $AFunc i64)
    (param $AFile i64) (param $ALine i64) (result i32)

    ;; Bounds check
    (if (i64.ge_u (global.get $rt_test_count) (i64.const 256))
      (then (return (i32.const 0))))

    ;; Lazy-allocate arrays on first registration
    (if (i64.eqz (global.get $rt_test_names))
      (then
        (global.set $rt_test_names (call $RT_AllocMem (i64.const 2048)))
        (global.set $rt_test_funcs (call $RT_AllocMem (i64.const 2048)))
        (global.set $rt_test_files (call $RT_AllocMem (i64.const 2048)))
        (global.set $rt_test_lines (call $RT_AllocMem (i64.const 2048)))
        (global.set $rt_test_errbuf (call $RT_AllocMem (i64.const 4096)))))

    ;; Store at arrays[count]
    (i64.store
      (i64.add (global.get $rt_test_names)
        (i64.mul (global.get $rt_test_count) (i64.const 8)))
      (local.get $AName))
    (i64.store
      (i64.add (global.get $rt_test_funcs)
        (i64.mul (global.get $rt_test_count) (i64.const 8)))
      (local.get $AFunc))
    (i64.store
      (i64.add (global.get $rt_test_files)
        (i64.mul (global.get $rt_test_count) (i64.const 8)))
      (local.get $AFile))
    (i64.store
      (i64.add (global.get $rt_test_lines)
        (i64.mul (global.get $rt_test_count) (i64.const 8)))
      (local.get $ALine))

    (global.set $rt_test_count
      (i64.add (global.get $rt_test_count) (i64.const 1)))
    (i32.const 1))

  ;; ---- Output sink: the ONE mode branch. In unittest mode (errbuf allocated)
  ;; bytes accumulate into $rt_test_errbuf; RT_TestRunAll prints them after
  ;; the [FAIL] line. Standalone, bytes go straight to stdout.
  (func $rt_test_out (param $ABuf i64) (param $ALen i64)
    (if (i64.ne (global.get $rt_test_errbuf) (i64.const 0))
      (then
        (if (i64.gt_u (i64.add (global.get $rt_test_errpos) (local.get $ALen)) (i64.const 4095))
          (then (local.set $ALen (i64.sub (i64.const 4095) (global.get $rt_test_errpos)))))
        (memory.copy
          (i64.add (global.get $rt_test_errbuf) (global.get $rt_test_errpos))
          (local.get $ABuf) (local.get $ALen))
        (global.set $rt_test_errpos (i64.add (global.get $rt_test_errpos) (local.get $ALen))))
      (else (call $rt_write_bytes (local.get $ABuf) (local.get $ALen)))))

  (func $rt_test_cstr_len (param $APtr i64) (result i64)
    (local $LLen i64)
    (if (i64.eqz (local.get $APtr)) (then (return (i64.const 0))))
    (block $done (loop $scan
      (br_if $done (i32.eqz (i32.load8_u (i64.add (local.get $APtr) (local.get $LLen)))))
      (local.set $LLen (i64.add (local.get $LLen) (i64.const 1)))
      (br $scan)))
    (local.get $LLen))

  (func $rt_test_out_cstr (param $APtr i64)
    (call $rt_test_out (local.get $APtr) (call $rt_test_cstr_len (local.get $APtr))))
  (func $rt_test_out_char (param $AChar i32)
    (i32.store8 (i64.const 280) (local.get $AChar))
    (call $rt_test_out (i64.const 280) (i64.const 1)))
  (func $rt_test_out_i64 (param $AVal i64)
    (call $rt_test_out (i64.const 280) (call $rt_i64_to_dec (local.get $AVal) (i64.const 280))))
  (func $rt_test_out_u64 (param $AVal i64)
    (call $rt_test_out (i64.const 280) (call $rt_u64_to_dec (local.get $AVal) (i64.const 280))))
  (func $rt_test_out_hex (param $AVal i64)
    (call $rt_test_out (i64.const 280) (call $rt_i64_to_hex (local.get $AVal) (i64.const 280))))
  (func $rt_test_out_f64 (param $AVal f64)
    (call $rt_test_out (i64.const 280) (call $rt_f64_to_str (local.get $AVal) (i64.const 280))))
  (func $rt_test_out_mstr (param $AStr i64)
    (if (i64.eqz (local.get $AStr)) (then (return)))
    (call $rt_test_out (i64.load offset=24 (local.get $AStr)) (i64.load offset=8 (local.get $AStr))))
  (func $rt_test_out_qstr (param $AStr i64)
    (call $rt_test_out_char (i32.const 34))
    (call $rt_test_out_mstr (local.get $AStr))
    (call $rt_test_out_char (i32.const 34)))
  (func $rt_test_out_bool (param $AVal i64)
    (if (i64.ne (local.get $AVal) (i64.const 0))
      (then (call $rt_test_out_cstr (i64.const 992)))
      (else (call $rt_test_out_cstr (i64.const 1000)))))

  ;; Basename of a NUL-terminated path: pointer past the last '/' or '\'.
  (func $rt_test_basename (param $APath i64) (result i64)
    (local $LP i64) (local $LBase i64) (local $LC i32)
    (local.set $LP (local.get $APath))
    (local.set $LBase (local.get $APath))
    (block $done (loop $scan
      (local.set $LC (i32.load8_u (local.get $LP)))
      (br_if $done (i32.eqz (local.get $LC)))
      (if (i32.or (i32.eq (local.get $LC) (i32.const 47)) (i32.eq (local.get $LC) (i32.const 92)))
        (then (local.set $LBase (i64.add (local.get $LP) (i64.const 1)))))
      (local.set $LP (i64.add (local.get $LP) (i64.const 1)))
      (br $scan)))
    (local.get $LBase))

  ;; Failure line head: "  <keyword> failed at <file>:<line>"
  (func $rt_test_fail_at (param $AKeyword i64) (param $AFile i64) (param $ALine i64)
    (global.set $rt_test_failed (i64.const 1))
    (call $rt_test_out_cstr (i64.const 704))
    (call $rt_test_out_cstr (local.get $AKeyword))
    (call $rt_test_out_cstr (i64.const 720))
    (call $rt_test_out_cstr (call $rt_test_basename (local.get $AFile)))
    (call $rt_test_out_char (i32.const 58))
    (call $rt_test_out_u64 (local.get $ALine)))

  ;; Failure line tail: optional " (msg)", newline, then the standalone halt.
  ;; Outside the runner there is no harness to record the failure, so halt.
  (func $rt_test_fail_end (param $AMsg i64)
    (if (i64.ne (local.get $AMsg) (i64.const 0))
      (then
        (call $rt_test_out_cstr (i64.const 952))
        (call $rt_test_out_mstr (local.get $AMsg))
        (call $rt_test_out_cstr (i64.const 960))))
    (call $rt_test_out_cstr (i64.const 1008))
    (if (i64.eqz (call $RT_IsUnitTestMode))
      (then (call $RT_Halt (i32.const 1)))))

  ;; ": expected " [not ]
  (func $rt_test_expected (param $ARelation i64)
    (call $rt_test_out_cstr (i64.const 744))
    (if (i64.ne (local.get $ARelation) (i64.const 0))
      (then (call $rt_test_out_cstr (i64.const 768)))))

  ;; eq fails when values differ; neq fails when they do not.
  (func $rt_test_cmp_failed (param $ARelation i64) (param $ADiffer i32) (result i32)
    (if (i64.eqz (local.get $ARelation))
      (then (return (local.get $ADiffer))))
    (i32.eqz (local.get $ADiffer)))

  (func $rt_test_cmp_keyword (param $ARelation i64) (result i64)
    (if (i64.ne (local.get $ARelation) (i64.const 0))
      (then (return (i64.const 880))))
    (i64.const 864))

  ;; RT_TestRunAll() -> i32
  ;; Runs all registered tests, prints [PASS]/[FAIL] per test plus any
  ;; buffered assert messages, prints a summary, returns 0=pass 1=fail.
  (func $RT_TestRunAll (result i32)
    (local $LI i64) (local $LPassed i64) (local $LFailed i64)
    (local $LName i64) (local $LFunc i64)

    (if (i64.eqz (global.get $rt_test_count))
      (then
        (call $rt_write_cstr (i64.const 928))
        (return (i32.const 0))))

    (call $rt_write_cstr (i64.const 488))
    (call $rt_write_cstr (i64.const 520))
    (call $rt_write_u64 (global.get $rt_test_count))
    (call $rt_write_cstr (i64.const 536))

    (block $done (loop $each
      (br_if $done (i64.ge_u (local.get $LI) (global.get $rt_test_count)))
      (global.set $rt_test_failed (i64.const 0))
      (global.set $rt_test_errpos (i64.const 0))
      (local.set $LName (i64.load (i64.add (global.get $rt_test_names) (i64.mul (local.get $LI) (i64.const 8)))))
      (local.set $LFunc (i64.load (i64.add (global.get $rt_test_funcs) (i64.mul (local.get $LI) (i64.const 8)))))
      (call_indirect (type $rt_void_func) (i32.wrap_i64 (local.get $LFunc)))
      (if (i64.ne (global.get $rt_test_failed) (i64.const 0))
        (then
          (call $rt_write_cstr (i64.const 576))
          (call $rt_write_cstr (local.get $LName))
          (call $rt_write_newline)
          (if (i64.gt_u (global.get $rt_test_errpos) (i64.const 0))
            (then (call $rt_write_bytes (global.get $rt_test_errbuf) (global.get $rt_test_errpos))))
          (local.set $LFailed (i64.add (local.get $LFailed) (i64.const 1))))
        (else
          (call $rt_write_cstr (i64.const 552))
          (call $rt_write_cstr (local.get $LName))
          (call $rt_write_newline)
          (local.set $LPassed (i64.add (local.get $LPassed) (i64.const 1)))))
      (local.set $LI (i64.add (local.get $LI) (i64.const 1)))
      (br $each)))

    (call $rt_write_cstr (i64.const 600))
    (call $rt_write_u64 (local.get $LPassed))
    (call $rt_write_cstr (i64.const 632))
    (call $rt_write_u64 (local.get $LFailed))
    (call $rt_write_cstr (i64.const 664))
    (call $rt_write_u64 (global.get $rt_test_count))
    (call $rt_write_cstr (i64.const 688))

    (call $RT_FreeMem (global.get $rt_test_names))
    (call $RT_FreeMem (global.get $rt_test_funcs))
    (call $RT_FreeMem (global.get $rt_test_files))
    (call $RT_FreeMem (global.get $rt_test_lines))
    (call $RT_FreeMem (global.get $rt_test_errbuf))
    (global.set $rt_test_names (i64.const 0))
    (global.set $rt_test_funcs (i64.const 0))
    (global.set $rt_test_files (i64.const 0))
    (global.set $rt_test_lines (i64.const 0))
    (global.set $rt_test_errbuf (i64.const 0))

    (if (i64.gt_u (local.get $LFailed) (i64.const 0))
      (then (return (i32.const 1))))
    (i32.const 0))

  ;; RT_TestAssert(ACond: i64, AFile: i64, ALine: i64)
  (func $RT_TestAssert (param $ACond i64) (param $AFile i64) (param $ALine i64)
    (if (i64.ne (local.get $ACond) (i64.const 0)) (then (return)))
    (call $rt_test_fail_at (i64.const 776) (local.get $AFile) (local.get $ALine))
    (call $rt_test_fail_end (i64.const 0)))

  (func $RT_TestAssertTrue (param $ACond i64) (param $AFile i64) (param $ALine i64)
    (if (i64.ne (local.get $ACond) (i64.const 0)) (then (return)))
    (call $rt_test_fail_at (i64.const 784) (local.get $AFile) (local.get $ALine))
    (call $rt_test_fail_end (i64.const 0)))

  (func $RT_TestAssertFalse (param $ACond i64) (param $AFile i64) (param $ALine i64)
    (if (i64.eqz (local.get $ACond)) (then (return)))
    (call $rt_test_fail_at (i64.const 800) (local.get $AFile) (local.get $ALine))
    (call $rt_test_fail_end (i64.const 0)))

  (func $RT_TestAssertNil (param $APtr i64) (param $AFile i64) (param $ALine i64)
    (if (i64.eqz (local.get $APtr)) (then (return)))
    (call $rt_test_fail_at (i64.const 816) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (i64.const 0))
    (call $rt_test_out_cstr (i64.const 968))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_hex (local.get $APtr))
    (call $rt_test_fail_end (i64.const 0)))

  (func $RT_TestAssertNotNil (param $APtr i64) (param $AFile i64) (param $ALine i64)
    (if (i64.ne (local.get $APtr) (i64.const 0)) (then (return)))
    (call $rt_test_fail_at (i64.const 832) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (i64.const 1))
    (call $rt_test_out_cstr (i64.const 968))
    (call $rt_test_fail_end (i64.const 0)))

  ;; RT_TestFail(AMsg: i64, AFile: i64, ALine: i64) -- unconditional failure
  (func $RT_TestFail (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (call $rt_test_fail_at (i64.const 848) (local.get $AFile) (local.get $ALine))
    (call $rt_test_fail_end (local.get $AMsg)))

  ;; Typed comparisons: (Expected, Actual, Relation, Msg, File, Line); 0=eq 1=neq
  (func $RT_TestAssertCmpInt (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (i64.ne (local.get $AExpected) (local.get $AActual)))) (then (return)))
    (call $rt_test_fail_at (call $rt_test_cmp_keyword (local.get $ARelation)) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (local.get $ARelation))
    (call $rt_test_out_i64 (local.get $AExpected))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_i64 (local.get $AActual))
    (call $rt_test_fail_end (local.get $AMsg)))

  (func $RT_TestAssertCmpUInt (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (i64.ne (local.get $AExpected) (local.get $AActual)))) (then (return)))
    (call $rt_test_fail_at (call $rt_test_cmp_keyword (local.get $ARelation)) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (local.get $ARelation))
    (call $rt_test_out_u64 (local.get $AExpected))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_u64 (local.get $AActual))
    (call $rt_test_fail_end (local.get $AMsg)))

  (func $RT_TestAssertCmpBool (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (i32.ne (i64.ne (local.get $AExpected) (i64.const 0))
                  (i64.ne (local.get $AActual) (i64.const 0))))) (then (return)))
    (call $rt_test_fail_at (call $rt_test_cmp_keyword (local.get $ARelation)) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (local.get $ARelation))
    (call $rt_test_out_bool (local.get $AExpected))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_bool (local.get $AActual))
    (call $rt_test_fail_end (local.get $AMsg)))

  (func $RT_TestAssertCmpChar (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (call $RT_TestAssertCmpUInt (local.get $AExpected) (local.get $AActual)
      (local.get $ARelation) (local.get $AMsg) (local.get $AFile) (local.get $ALine)))

  (func $RT_TestAssertCmpWChar (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (call $RT_TestAssertCmpUInt (local.get $AExpected) (local.get $AActual)
      (local.get $ARelation) (local.get $AMsg) (local.get $AFile) (local.get $ALine)))

  (func $RT_TestAssertCmpPtr (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (i64.ne (local.get $AExpected) (local.get $AActual)))) (then (return)))
    (call $rt_test_fail_at (call $rt_test_cmp_keyword (local.get $ARelation)) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (local.get $ARelation))
    (call $rt_test_out_hex (local.get $AExpected))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_hex (local.get $AActual))
    (call $rt_test_fail_end (local.get $AMsg)))

  (func $RT_TestAssertCmpFloat (param $AExpected f64) (param $AActual f64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (f64.ne (local.get $AExpected) (local.get $AActual)))) (then (return)))
    (call $rt_test_fail_at (call $rt_test_cmp_keyword (local.get $ARelation)) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (local.get $ARelation))
    (call $rt_test_out_f64 (local.get $AExpected))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_f64 (local.get $AActual))
    (call $rt_test_fail_end (local.get $AMsg)))

  ;; Tolerance: (Expected, Actual, Epsilon, Relation, Msg, File, Line)
  (func $RT_TestAssertCmpFloatTol (param $AExpected f64) (param $AActual f64)
    (param $AEpsilon f64) (param $ARelation i64)
    (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (f64.gt (f64.abs (f64.sub (local.get $AExpected) (local.get $AActual))) (local.get $AEpsilon))))
      (then (return)))
    (if (i64.ne (local.get $ARelation) (i64.const 0))
      (then (call $rt_test_fail_at (i64.const 912) (local.get $AFile) (local.get $ALine)))
      (else (call $rt_test_fail_at (i64.const 896) (local.get $AFile) (local.get $ALine))))
    (call $rt_test_expected (local.get $ARelation))
    (call $rt_test_out_f64 (local.get $AExpected))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_f64 (local.get $AActual))
    (call $rt_test_out_cstr (i64.const 976))
    (call $rt_test_out_f64 (local.get $AEpsilon))
    (call $rt_test_fail_end (local.get $AMsg)))

  (func $RT_TestAssertCmpStr (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (i64.ne (call $RT_StrCompare (local.get $AExpected) (local.get $AActual)) (i64.const 0))))
      (then (return)))
    (call $rt_test_fail_at (call $rt_test_cmp_keyword (local.get $ARelation)) (local.get $AFile) (local.get $ALine))
    (call $rt_test_expected (local.get $ARelation))
    (call $rt_test_out_qstr (local.get $AExpected))
    (call $rt_test_out_cstr (i64.const 760))
    (call $rt_test_out_qstr (local.get $AActual))
    (call $rt_test_fail_end (local.get $AMsg)))

  ;; Wide strings: values are UTF-16 and have no byte writer here, so the
  ;; failure line carries keyword and location only.
  (func $RT_TestAssertCmpWStr (param $AExpected i64) (param $AActual i64)
    (param $ARelation i64) (param $AMsg i64) (param $AFile i64) (param $ALine i64)
    (if (i32.eqz (call $rt_test_cmp_failed (local.get $ARelation)
          (i64.ne (call $RT_WStrCompare (local.get $AExpected) (local.get $AActual)) (i64.const 0))))
      (then (return)))
    (call $rt_test_fail_at (call $rt_test_cmp_keyword (local.get $ARelation)) (local.get $AFile) (local.get $ALine))
    (call $rt_test_fail_end (local.get $AMsg)))

;;------------------------------------------------------------------------------
;; Function types and table for indirect calls
;;------------------------------------------------------------------------------

  ;; Type for void() callbacks (finalizers, test functions)
  (type $rt_void_func (func))

  ;; Type for thunk(ptr) callbacks (array release composite)
  (type $rt_thunk_type (func (param i64)))

  ;; Function table -- the emitter populates this with elem declarations
  (table $rt_functable 256 funcref)

;;------------------------------------------------------------------------------
;; Variadic argument packs
;;------------------------------------------------------------------------------
;; Layout (heap block, user pointer):
;;   @0  count  i64
;;   @8  cursor i64
;;   @16 slot 0: (TypeId i64 @16)(value i64 @24)
;;   @32 slot 1 ...
;; TypeId is the compile-time type identity lowered to an integer. Primitive
;; ids are fixed by table order in Waskal.AST.pas WKL_PRIMITIVE_NAMES:
;; string = 14, wstring = 15. String slots hold a refcounted TStringRec and
;; are AddRef'd on store / Release'd on free.

  ;; rt_pack_is_str(ATypeId: i64) -> i32
  (func $rt_pack_is_str (param $ATypeId i64) (result i32)
    (i32.or
      (i64.eq (local.get $ATypeId) (i64.const 14))
      (i64.eq (local.get $ATypeId) (i64.const 15))))

  ;; rt_pack_fail_type(AExpected, AGot: i64) -- raises, never returns
  (func $rt_pack_fail_type (param $AExpected i64) (param $AGot i64)
    (local $LMsg i64)
    (local.set $LMsg (call $rt_fmt_new))
    (local.set $LMsg (call $rt_fmt_cstr (local.get $LMsg) (i64.const 426)))
    (local.set $LMsg (call $rt_fmt_i64 (local.get $LMsg) (local.get $AExpected)))
    (local.set $LMsg (call $rt_fmt_cstr (local.get $LMsg) (i64.const 460)))
    (local.set $LMsg (call $rt_fmt_i64 (local.get $LMsg) (local.get $AGot)))
    (call $RT_Raise (i32.const 900) (local.get $LMsg))
    (unreachable))

  ;; rt_pack_fail_index(AIndex, ACount: i64) -- raises, never returns
  (func $rt_pack_fail_index (param $AIndex i64) (param $ACount i64)
    (local $LMsg i64)
    (local.set $LMsg (call $rt_fmt_new))
    (local.set $LMsg (call $rt_fmt_cstr (local.get $LMsg) (i64.const 467)))
    (local.set $LMsg (call $rt_fmt_i64 (local.get $LMsg) (local.get $AIndex)))
    (local.set $LMsg (call $rt_fmt_cstr (local.get $LMsg) (i64.const 460)))
    (local.set $LMsg (call $rt_fmt_i64 (local.get $LMsg) (local.get $ACount)))
    (call $RT_Raise (i32.const 901) (local.get $LMsg))
    (unreachable))

  ;; RT_PackNew(ACount: i64) -> i64
  ;; Zeroed block with count set, cursor 0.
  (func $RT_PackNew (param $ACount i64) (result i64)
    (local $LPack i64)
    (local.set $LPack (call $RT_AllocMem
      (i64.add (i64.const 16) (i64.mul (local.get $ACount) (i64.const 16)))))
    (i64.store (local.get $LPack) (local.get $ACount))
    (local.get $LPack))

  ;; RT_PackSet(APack, AIndex, ATypeId, AValue: i64)
  ;; Caller-side store of one slot. String values are AddRef'd.
  (func $RT_PackSet (param $APack i64) (param $AIndex i64)
    (param $ATypeId i64) (param $AValue i64)
    (local $LSlot i64)
    (local.set $LSlot (i64.add (local.get $APack)
      (i64.add (i64.const 16) (i64.mul (local.get $AIndex) (i64.const 16)))))
    (i64.store (local.get $LSlot) (local.get $ATypeId))
    (i64.store offset=8 (local.get $LSlot) (local.get $AValue))
    (if (call $rt_pack_is_str (local.get $ATypeId))
      (then (call $RT_StrAddRef (local.get $AValue)))))

  ;; RT_PackCount(APack: i64) -> i32
  (func $RT_PackCount (param $APack i64) (result i32)
    (i32.wrap_i64 (i64.load (local.get $APack))))

  ;; RT_PackGet(APack, AIndex, ATypeId: i64) -> i64
  ;; Bounds- and tag-checked read of slot AIndex. Raises on mismatch.
  (func $RT_PackGet (param $APack i64) (param $AIndex i64)
    (param $ATypeId i64) (result i64)
    (local $LSlot i64)
    (local $LTag i64)
    (if (i64.ge_u (local.get $AIndex) (i64.load (local.get $APack)))
      (then (call $rt_pack_fail_index (local.get $AIndex)
        (i64.load (local.get $APack)))))
    (local.set $LSlot (i64.add (local.get $APack)
      (i64.add (i64.const 16) (i64.mul (local.get $AIndex) (i64.const 16)))))
    (local.set $LTag (i64.load (local.get $LSlot)))
    (if (i64.ne (local.get $LTag) (local.get $ATypeId))
      (then (call $rt_pack_fail_type (local.get $ATypeId) (local.get $LTag))))
    (i64.load offset=8 (local.get $LSlot)))

  ;; RT_PackNext(APack, ATypeId: i64) -> i64
  ;; Reads the slot at the cursor, then advances it.
  (func $RT_PackNext (param $APack i64) (param $ATypeId i64) (result i64)
    (local $LCursor i64)
    (local $LValue i64)
    (local.set $LCursor (i64.load offset=8 (local.get $APack)))
    (local.set $LValue (call $RT_PackGet (local.get $APack)
      (local.get $LCursor) (local.get $ATypeId)))
    (i64.store offset=8 (local.get $APack)
      (i64.add (local.get $LCursor) (i64.const 1)))
    (local.get $LValue))

  ;; RT_PackReset(APack: i64)
  (func $RT_PackReset (param $APack i64)
    (i64.store offset=8 (local.get $APack) (i64.const 0)))

  ;; RT_PackCopy(APack: i64) -> i64
  ;; Duplicates the block including cursor; string slots are AddRef'd.
  (func $RT_PackCopy (param $APack i64) (result i64)
    (local $LSize i64)
    (local $LNew i64)
    (local $LI i64)
    (local $LSlot i64)
    (local.set $LSize (i64.add (i64.const 16)
      (i64.mul (i64.load (local.get $APack)) (i64.const 16))))
    (local.set $LNew (call $RT_GetMem (local.get $LSize)))
    (memory.copy (local.get $LNew) (local.get $APack) (local.get $LSize))
    (local.set $LI (i64.const 0))
    (block $done
      (loop $next
        (br_if $done (i64.ge_u (local.get $LI) (i64.load (local.get $APack))))
        (local.set $LSlot (i64.add (local.get $LNew)
          (i64.add (i64.const 16) (i64.mul (local.get $LI) (i64.const 16)))))
        (if (call $rt_pack_is_str (i64.load (local.get $LSlot)))
          (then (call $RT_StrAddRef (i64.load offset=8 (local.get $LSlot)))))
        (local.set $LI (i64.add (local.get $LI) (i64.const 1)))
        (br $next)))
    (local.get $LNew))

  ;; RT_PackFree(APack: i64)
  ;; Releases string slots, then the block. Nil-safe.
  (func $RT_PackFree (param $APack i64)
    (local $LI i64)
    (local $LSlot i64)
    (if (i64.eqz (local.get $APack)) (then (return)))
    (local.set $LI (i64.const 0))
    (block $done
      (loop $next
        (br_if $done (i64.ge_u (local.get $LI) (i64.load (local.get $APack))))
        (local.set $LSlot (i64.add (local.get $APack)
          (i64.add (i64.const 16) (i64.mul (local.get $LI) (i64.const 16)))))
        (if (call $rt_pack_is_str (i64.load (local.get $LSlot)))
          (then (call $RT_StrRelease (i64.load offset=8 (local.get $LSlot)))))
        (local.set $LI (i64.add (local.get $LI) (i64.const 1)))
        (br $next)))
    (call $RT_FreeMem (local.get $APack)))

;;------------------------------------------------------------------------------
;; Data segments for runtime strings
;;------------------------------------------------------------------------------

  ;; Test runner strings (fixed addresses 488..1016; emitter data starts at 1024)
  (data (i64.const 488) "\n\1b[1;36m=== Unit Tests ===\1b[0m\n\00")
  (data (i64.const 520) "Running \00")
  (data (i64.const 536) " test(s)...\n\n\00")
  (data (i64.const 552) "\1b[1;32m[PASS]\1b[0m \00")
  (data (i64.const 576) "\1b[1;31m[FAIL]\1b[0m \00")
  (data (i64.const 600) "\n\1b[1;36m=== Results: \1b[32m\00")
  (data (i64.const 632) " passed\1b[0m\1b[1;36m, \1b[31m\00")
  (data (i64.const 664) " failed\1b[0m\1b[1;36m, \00")
  (data (i64.const 688) " total ===\1b[0m\n\00")
  (data (i64.const 704) "  \1b[1;31m\00")
  (data (i64.const 720) "\1b[31m failed at \00")
  (data (i64.const 744) ": expected \00")
  (data (i64.const 760) ", got \00")
  (data (i64.const 768) "not \00")
  (data (i64.const 776) "assert\00")
  (data (i64.const 784) "asserttrue\00")
  (data (i64.const 800) "assertfalse\00")
  (data (i64.const 816) "assertnil\00")
  (data (i64.const 832) "assertnotnil\00")
  (data (i64.const 848) "assertfail\00")
  (data (i64.const 864) "asserteq\00")
  (data (i64.const 880) "assertneq\00")
  (data (i64.const 896) "asserteqf\00")
  (data (i64.const 912) "assertneqf\00")
  (data (i64.const 928) "No tests registered.\n\00")
  (data (i64.const 952) " (\00")
  (data (i64.const 960) ")\00")
  (data (i64.const 968) "nil\00")
  (data (i64.const 976) " within \00")
  (data (i64.const 992) "true\00")
  (data (i64.const 1000) "false\00")
  (data (i64.const 1008) "\1b[0m\n\00")
  ;; varargs pack failure strings (426+)
  (data (i64.const 426) "varargs: expected type id \00")
  (data (i64.const 460) ", got \00")
  (data (i64.const 467) "varargs: index \00")
