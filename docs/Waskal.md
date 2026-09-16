<div align="center">

![Waskal](../media/logo.jpg)

</div>

<a id="overview"></a>

## 🚀 Overview

**Waskal** compiles a Pascal/Oberon-inspired language to wasm64 and ships the result as a single, self-contained `.html` file -- a single-file executable for the browser. Double-click it, email it, upload it, serve it from any web server; it runs on any operating system with a modern browser. No external toolchain, no runtime install, no platform-specific output.

Four ideas hold the whole system up:

| Pillar | Principle |
|--------|-----------|
| 🌐 **The browser is the universal operating system** | Every device with a screen already has one. It handles graphics, audio, input, networking, storage, threading. Waskal does not reinvent any of it. |
| ⚙️ **WebAssembly is the machine code** | wasm64 is the compile target -- portable, sandboxed, near-native speed, and the same binary runs on every OS the browser does. |
| 📜 **JavaScript is the device driver** | All platform access flows through thin JS shims. The wasm module declares imports; the JS layer satisfies them. Swap the JS layer and the same binary runs in Node, Deno, or any wasm64-capable host. |
| 📦 **HTML is the single-file executable** | One `.html` carries the runtime, the JS host layer, the assets, and the base64-encoded wasm binary. No installer, no dependencies, no moving parts. |

```wkl
module exe hello;

begin
  println("Hello, I am %s! 🚀🔥✨", "Waskal");

  var i: int32 = 0;
  var s: string = "Waskal™ " + "Programming Language";

  println(s);

  for i := 1 to 10 do
    println("%d", i);
  end
end.
```

```
> waskal hello -r
```

The compiler builds `hello.wkl` into `output/hello.html`, then opens it in your default browser. The page shows the module name as a heading and prints stdout into the body -- no canvas, no framework, just text on a dark page.

### ⚙️ The Pipeline

Every `.wkl` source file flows through the same stages:

```
.wkl source
  --> Waskal.Lexer           (source text --> tokens)
  --> Waskal.Parser          (tokens --> AST)
  --> Waskal.Semantics       (type checking, name resolution)
  --> Waskal.Emitter         (AST --> .wat, WebAssembly text format)
  --> wasm-opt               (.wat --> optimized .wasm binary)
  --> esbuild                (combine + minify all JS into one block)
  --> Waskal.Build           (base64-encode .wasm, inject JS + wasm
                              into HTML template)
  --> output.html            (one self-contained file, runs anywhere)
```

Two bundled tools handle the binary stage: **wasm-opt** (Binaryen) assembles, validates, optimizes, and strips the `.wat` into a `.wasm`; **esbuild** combines and minifies all JavaScript into a single block. Both are standalone executables shipped in `bin/res/wasm/` -- no npm, no package manager.

A third tool, **wasm-merge**, activates only when the program declares an external `.wasm` library. It merges the program module with external wasm modules into one binary before the HTML packaging step.

### 📋 Key Capabilities

| Capability | Details |
|---|---|
| **Single-file output** | The generated `.html` embeds the JS host layer and the base64-encoded wasm64 binary. No external dependencies. Runs from `file://` or any server. |
| **Two module kinds** | `exe` produces a `.html` executable. `lib` produces a `.wasm` library that other Waskal programs (and other wasm hosts) can link against. |
| **wasm64 features** | memory64, bulk-memory, nontrapping-float-to-int, exception-handling, multivalue -- all enabled by default. |
| **Browser is the machine** | All platform access -- graphics, audio, input, storage, networking -- is delegated to the browser through thin JavaScript shims. The wasm module handles computation; the browser handles everything else. |
| **Standard library** | Six built-in modules ship with the compiler: `frame` (game loop), `canvas2d` (2D drawing), `input` (keyboard/mouse/gamepad), `audio` (sound and music), `video` (playback), `localstorage` (persistence). |
| **Seven optimization levels** | `none` through `4`, plus `s` and `z` for size. Each maps to a wasm-opt pass. |
| **Conditional compilation** | `@define`, `@undef`, `@ifdef`, `@ifndef`, `@elseif`, `@else`, `@endif`. Four predefined symbols: `WASKAL`, `WASM64`, `BUILD_EXE`, `BUILD_LIB`. |
| **Module system** | `exe`, `lib`, and `unit` modules with `import`, full module qualification, `initialize`/`finalize` lifecycle hooks, and `public`/`private` visibility. |
| **Unit tests** | `test` blocks after `end.` with eight assertion intrinsics. Enable with `@unittestmode on;` and the test runner replaces the normal entry point. |
| **Embedded assets** | `@asset` and `@assets` directives deflate-compress files and base64-encode them into the `.html`. At runtime they decompress into an in-memory filesystem. |

### 💡 What Makes It Different

The user installs nothing beyond the compiler itself. No wasm toolchain to configure, no JavaScript bundler to manage, no platform SDK to match. The three external tools (wasm-opt, esbuild, wasm-merge) ship inside the compiler's own directory -- they are invisible to the workflow.

One command produces one file. That file IS the application.

### 🖥️ System Requirements

| Area | Requirement |
|---|---|
| **Host OS** | Windows 10/11 x64 (the compiler runs here) |
| **Target** | Any modern browser with wasm64 (memory64) support |
| **Runtime dependencies** | None -- the `.html` is self-contained |
| **Building the compiler** | Delphi 12.x or higher |

> [!NOTE]
> **Cross-platform output, single-platform compiler.** The compiler itself runs on Windows. The *output* runs everywhere -- any OS, any device, any browser that supports wasm64.

<a id="documentation-guide"></a>

## 🧭 Documentation Guide

> [!TIP]
> **Fast path:** read [Getting Started](#getting-started), skim [Language Reference](#language-reference), then jump to [JS Interop](#js-interop) when you are ready to call browser APIs from your program.

### 🎯 Who Is This For?

- **Browser app and game developers** who want Pascal syntax, wasm64 performance, and single-file deployment with no JavaScript build tooling.
- **Delphi and Pascal developers** who want to ship to the web with nothing to install -- write familiar syntax, get a `.html` that runs anywhere.
- **Anyone who wants a single-file deliverable** -- one `.html` is the entire application. Email it, upload it, double-click it.

### 🖥️ CLI Reference

<a id="cli-reference"></a>

Waskal ships a single command-line compiler. There is nothing else to install.

**Syntax:**

```
waskal <source> [OPTIONS]
```

Pass the source filename with or without the `.wkl` extension -- the compiler normalizes it.

| Flag | Description |
|---|---|
| `<source>` | Waskal source file (`.wkl`) |
| `-r, --run` | Run after building (opens `.html` in default browser) |
| `-o, --output <path>` | Set output directory (default: `output/` beside working directory) |
| `-opt, --optimize <level>` | Set optimization level (see table below) |
| `-h, --help` | Show help |

**Examples:**

```
waskal hello
waskal hello -r
waskal hello -r -opt 3
waskal hello -o dist
```

> [!NOTE]
> **CLI overrides source directives.** A `-opt` flag on the command line takes precedence over an `@optimize` directive in the source file.

### 🎚️ Optimization Levels

The optimization level controls the wasm-opt pass applied to the `.wasm` binary. Set it with `-opt <level>` on the command line or `@optimize <level>;` in source.

| Level | wasm-opt flag | Description |
|---|---|---|
| `none` | *(skipped)* | No optimization -- default. Debug-friendly: leak report enabled, no dead code removal. |
| `1` | `-O1` | Quick and useful. Good for iteration builds. |
| `2` | `-O2` | Most optimizations. Generally best performance. |
| `3` | `-O3` | Aggressive. May take significant time. |
| `4` | `-O4` | Aggressive with IR flattening. High time and memory. |
| `s` | `-Os` | Default optimizations, focusing on code size. |
| `z` | `-Oz` | Default optimizations, super-focusing on code size. |

### 📌 Current Status

The compiler is working end-to-end. Feature summary:

- 18 primitive types with exact wasm32/wasm64 sizes (BNF sec 3)
- Variables, typed and untyped constants, constant folding
- Arithmetic, comparison, logical, bitwise, and compound assignment operators (BNF sec 4)
- Control flow: `if`/`else`, `while`, `for`, `repeat`/`until`, `match`, `break`, `continue` (BNF sec 11)
- Exception handling: `guard`/`except`/`finally`, `throw`, `throwcode`, `exccode`, `excmsg` (BNF sec 11)
- Routines: procedures, functions, unconditional overloading, const/var parameters, variadic arguments (BNF sec 9, 14)
- Records: plain, packed, aligned, derived, overlay, bitfield, with methods and operators (BNF sec 10)
- Choices (discriminated unions), sets, fixed arrays, dynamic arrays (BNF sec 10)
- Typed and untyped pointers, `new`/`dispose`, `getmem`/`freemem`/`resizemem` (BNF sec 13)
- Module system: `exe`, `lib`, `unit` with `import`, full qualification, `initialize`/`finalize` (BNF sec 6)
- JS interop: `external` clause with library resolution for `.js` and `.wasm` files (BNF sec 9)
- Conditional compilation: `@define`/`@undef`/`@ifdef`/`@ifndef`/`@elseif`/`@else`/`@endif` (BNF sec 7)
- Embedded assets: `@asset`/`@assets` with deflate compression and base64 encoding
- Standard library: `frame`, `canvas2d`, `input`, `audio`, `video`, `localstorage`
- Built-in testing: `test` blocks with eight assertion intrinsics (BNF sec 15)
- 17 compiler intrinsics: `len`, `size`, `format`, `new`, `dispose`, `getmem`, `freemem`, `resizemem`, `setlength`, `print`, `println`, `utf8`, `cstr`, `wstr`, `paramcount`, `paramstr`, `exccode`, `excmsg` (BNF sec 13)

### 🗺️ Table of Contents

- 🚀 [Overview](#overview) -- what Waskal is, the pipeline, key capabilities
- 🧭 [Documentation Guide](#documentation-guide) -- audience, CLI reference, status
- 📖 [Getting Started](#getting-started) -- install, first program, build and run
- 📘 [Language Reference](#language-reference) -- types, operators, routines, control flow
- 📦 [Module System](#module-system) -- exe, lib, unit, imports, visibility, directives
- 🔗 [JS Interop](#js-interop) -- external clause, JS libs, wasm libs, marshalling
- 🧠 [Memory](#memory-management) -- heap, strings, arrays, cleanup, leak report
- 🧾 [Formal Grammar](#bnf-grammar) -- BNF rules derived from the parser
- 📦 [Standard Library](#standard-library) -- frame, canvas2d, input, audio, video, localstorage
- ⚙️ [Runtime](#runtime-internals) -- runtime.wat, runtime.js, WASI shim, exceptions, assets
- 🔍 [Diagnostics](#diagnostics) -- optimization, leak report, DevTools, conditional compilation
- ✍️ [Code Style](#code-style) -- naming conventions and formatting
- 🛠️ [Common Tasks](#common-tasks) -- practical recipes for everyday Waskal work

<a id="getting-started"></a>

## 🚀 Getting Started

*Install the compiler, write a program, build it, open the result in your browser -- all in under a minute.*

> [!TIP]
> **Already set up?** Skip to [Your First Program](#your-first-program). For the big picture, see the [Overview](#overview).


### 📋 Prerequisites

Waskal compiles your `.wkl` source into a self-contained `.html` file. No linker, no external SDK, no JavaScript toolchain. You need:

| Requirement | Details |
|---|---|
| **Host OS** | Windows 10/11 x64 (the compiler runs here) |
| **Target** | Any modern browser with wasm64 (memory64) support |

That is all. The three tools the compiler uses internally -- wasm-opt, esbuild, wasm-merge -- ship inside `bin/res/wasm/` and are invisible to your workflow.

> [!NOTE]
> **Building the compiler from source** requires Delphi 12.x or higher. Most users only need the pre-built `waskal` binary.


### 📥 Installation

<a id="installation"></a>

1. Clone or download the repository from [GitHub](https://github.com/tinyBigGAMES/Waskal).
2. Add the `bin/` directory to your system `PATH`, or run `waskal.exe` directly from it.

There is nothing to download on first build and nothing to cache.

The `bin/` directory contains everything the compiler needs:

| Path | What it is |
|---|---|
| `bin/waskal.exe` | The compiler |
| `bin/res/wasm/` | Runtime files (runtime.wat, runtime.js, index.html) and build tools (wasm-opt, wasm-merge, esbuild) |
| `bin/res/libs/std/` | Standard library modules (`frame`, `canvas2d`, `input`, `audio`, `video`, `localstorage`) |
| `bin/res/libs/vendor/` | Third-party library bindings, one folder each |
| `bin/res/examples/` | Runnable example programs including `hello.wkl` |
| `bin/res/tests/` | Compliance and probe test suites |


### 📝 Your First Program

<a id="your-first-program"></a>

Create a file called `hello.wkl`:

```wkl
module exe hello;

begin
  println("Hello, I am %s! 🚀🔥✨", "Waskal");

  var i: int32 = 0;
  var s: string = "Waskal™ " + "Programming Language";

  println(s);

  for i := 1 to 10 do
    println("%d", i);
  end
end.
```

Every Waskal program starts with a **module declaration**: `module exe hello;`. The keyword `exe` means this module produces an executable `.html` file. The name `hello` must match the source filename without extension.

`begin...end.` is the program entry point. The period after `end` marks the end of the module.

A few things to notice in this snippet:

- `println` uses printf-style format strings: `%s` for strings, `%d` for integers.
- Variables are declared with `var` in the body.
- `for...do...end` -- control structures are block-terminated, not semicolon-terminated.


### 🔨 Build and Run

<a id="building-and-running"></a>

Open a terminal in the directory containing `hello.wkl` and run:

```
waskal hello -r
```

The compiler builds `hello.wkl` and opens the result in your default browser. You will see status lines like:

```
Parsing hello.wkl...
Analyzing...
Processing directives...
Emitting code...
Output: C:\...\output\hello.html
Build succeeded.
Running hello.html...
```

In the browser: a dark page with the module name as a heading, your program's `println` output in the body, and `exit code: 0` at the bottom.

> [!NOTE]
> **The source extension is optional.** `waskal hello` and `waskal hello.wkl` are equivalent -- the compiler normalizes the extension.

To build without running, drop the `-r` flag:

```
waskal hello
```

The full set of command-line options:

| Flag | Argument | Effect |
|---|---|---|
| `<source>` | | Waskal source file (`.wkl`), extension optional |
| `-r`, `--run` | | Open the `.html` in the default browser after building |
| `-o`, `--output` | `<path>` | Set the output directory |
| `-opt`, `--optimize` | `<level>` | Set optimization level: `none` (default), `1`, `2`, `3`, `4`, `s`, `z` |
| `-h`, `--help` | | Display the help message |

> [!TIP]
> **Optimization in depth.** Each level maps to a wasm-opt pass. See [Runtime Internals](#runtime-internals) for the full table and what each level does.


### 📂 Output Folder

<a id="output-folder"></a>

By default the compiler writes output to `output/` under the current working directory. Three settings control the output path, highest priority first:

1. **`-o <path>`** on the command line.
2. **`@outputpath "path";`** directive in the source file.
3. **Default** -- `output/` under the working directory.

What lands in the output folder depends on the module kind:

| Module kind | Files produced |
|---|---|
| `exe` | `hello.wat` (readable text), `hello.wasm` (binary), **`hello.html`** (the deliverable) |
| `lib` | `hello.wat`, `hello.wasm` |
| `unit` | Nothing -- unit modules are compiled inline into the importing module |

> [!TIP]
> **Ship only the `.html`.** The `.wat` and `.wasm` files are build by-products. The `.html` embeds everything it needs.


### 📦 What the .html Contains

The generated `.html` is one file carrying five things:

1. **Page shell** -- the module name as `<title>` and `<h1>`, plus an optional favicon from the `@favicon` directive.
2. **Embedded assets** -- any files packed by `@asset` or `@assets` directives, deflate-compressed and base64-encoded. At runtime they decompress into an in-memory filesystem.
3. **JavaScript host layer** -- runtime.js (a vendored WASI preview1 shim for memory64, MIT OR Apache-2.0) plus every standard-library and user `.js` file the program pulled in, combined and minified into one `<script>` block.
4. **wasm64 binary** -- the compiled module, base64-encoded. Decoded and instantiated at page load.
5. **Runner** -- feature-detects memory64 support, decodes assets, instantiates the wasm module with its imports, calls `_start`, and handles shutdown when the program finishes or the page closes.

The file runs from `file://` -- no web server, no network connection, no external dependencies. Double-click it, email it, drop it on a USB stick. It just works on any OS with a modern browser.

> [!WARNING]
> **memory64 required.** If the browser does not support WebAssembly memory64, the page displays a message instead of running the program. All current versions of Chrome, Edge, and Firefox support it. Safari added support in version 18.2.

Next: [Language Reference](#language-reference)

<a id="language-reference"></a>

## 📘 Language Reference

*Everything the language can express -- types, operators, control flow, routines, and more -- in one place with worked examples.*

Waskal is case-sensitive: keywords are lowercase, and identifiers that differ only in case are distinct. The naming convention is PascalCase for types, camelCase for variables, and UPPER_CASE for constants. There is no `T` prefix on type names.

> [!TIP]
> **Where to look next.** This section covers syntax and constructs. For multi-module projects see [Module System](#module-system). For calling JavaScript or linking wasm libraries see [JS Interop](#js-interop). For heap allocation, strings, and dynamic arrays see [Memory](#memory).


### 🔢 1. Primitive Types

*Eighteen built-in types map directly to WebAssembly value types.*

| Type | Size | Wasm type | Description |
|------|------|-----------|-------------|
| `int8` | 1 byte | i32 | Signed 8-bit integer |
| `int16` | 2 bytes | i32 | Signed 16-bit integer |
| `int32` | 4 bytes | i32 | Signed 32-bit integer |
| `int64` | 8 bytes | i64 | Signed 64-bit integer |
| `uint8` | 1 byte | i32 | Unsigned 8-bit integer |
| `uint16` | 2 bytes | i32 | Unsigned 16-bit integer |
| `uint32` | 4 bytes | i32 | Unsigned 32-bit integer |
| `uint64` | 8 bytes | i64 | Unsigned 64-bit integer |
| `float32` | 4 bytes | f32 | 32-bit IEEE 754 float |
| `float64` | 8 bytes | f64 | 64-bit IEEE 754 float |
| `bool` | 1 byte | i32 | Boolean (`true` or `false`) |
| `char` | 1 byte | i32 | 8-bit character (UTF-8 code unit) |
| `wchar` | 2 bytes | i32 | 16-bit wide character (UTF-16 code unit) |
| `string` | 8 bytes | i64 | Managed, refcounted UTF-8 string |
| `wstring` | 8 bytes | i64 | Managed, refcounted UTF-16 string |
| `ptr` | 8 bytes | i64 | Untyped pointer |
| `varargs` | 8 bytes | i64 | Variadic argument pack (see [Routines](#routines)) |

All type names are reserved words and cannot be used as identifiers.

> [!NOTE]
> **Wasm64 and pointer width.** Waskal targets wasm64 (memory64), so pointers, strings, and dynamic arrays are 64-bit addresses. Sub-32-bit integer types (int8, uint16, etc.) are stored in memory at their natural size but are widened to i32 for computation.


### ✏️ 2. Literals

*Integer, float, string, character, boolean, nil, record, and set.*

#### Integer literals

```wkl
42          // decimal, type is int32
0xFF        // hexadecimal (0x prefix), type is int32
```

Untyped integer literals default to `int32`. If the value does not fit in 32 bits, it is promoted to `int64`.

#### Float literals

```wkl
3.14        // contextual -- float32 or float64 depending on target type
3.14f       // explicit float32 (f suffix)
1.0e10      // scientific notation
```

Without a suffix, the type is determined by context: assigned to a `float32` variable it becomes `float32`, otherwise `float64`. The `f` or `F` suffix forces `float32`.

#### String literals

Strings use double quotes with C-style escape sequences:

```wkl
"hello world"
"line1\nline2\ttab"
```

| Escape | Meaning |
|--------|---------|
| `\n` | Newline |
| `\t` | Tab |
| `\r` | Carriage return |
| `\0` | Null character |
| `\\` | Backslash |
| `\'` | Single quote |
| `\"` | Double quote |
| `\xHH` | Hex byte value |

#### Wide string literals

Prefix a string with lowercase `w` for UTF-16:

```wkl
w"hello wide world"
```

Wide strings support the same escape sequences.

#### Boolean literals

```wkl
true
false
```

#### Nil

```wkl
nil       // null pointer, null routine reference
```

#### Character assignment

There is no dedicated character literal. Characters are assigned from single-character strings; the compiler verifies length at compile time:

```wkl
var c: char;
c := "A";          // single UTF-8 character

var wc: wchar;
wc := w"X";        // single UTF-16 character
```

#### Record literals

Construct a record value inline by naming the type and its fields:

```wkl
type
  Point = record
    x: int32;
    y: int32;
  end;

var p: Point;
p := Point(x: 10, y: 20);
```

#### Set literals

```wkl
[]              // empty set
[5]             // single element
[1, 3, 5, 7]   // multiple elements
[1..10]         // range
[1, 3..7, 10]   // mixed elements and ranges
```


### 📦 3. Variables

*Declared with `var`, zero-initialized by default.*

Variables are declared in a `var` section with a type and an optional initializer:

```wkl
var
  x: int32;                  // zero-initialized
  y: int32 = 10;             // explicit initializer
  name: string = "Alice";
```

Variables can also be declared inline at statement level:

```wkl
begin
  var sum: int32 = a + b;
  println("sum = %d", sum);
end.
```

> [!NOTE]
> **Inline `var` is statement-level.** The declaration `var ident: Type [= expr];` can appear anywhere a statement is expected, not only at the top of a block.


### 🔒 4. Constants

*Compile-time values, typed or untyped.*

```wkl
const
  MAX: int32 = 100;           // typed constant
  PI: float64 = 3.14159;
  GREETING = "hello";         // untyped -- type inferred from the value
  DOUBLED = 21 * 2;           // expression constant (42)
  IS_EQ = 5 = 5;              // boolean expression constant (true)
```

Constant expressions are evaluated at compile time. Untyped integer constants default to `int32`; untyped string constants to `string`.


### ➕ 5. Operators

*Arithmetic, comparison, logical, bitwise, compound assignment, and pointer operators.*

#### Arithmetic

| Operator | Meaning | Example |
|----------|---------|---------|
| `+` | Addition | `a + b` |
| `-` | Subtraction / unary negation | `a - b`, `-x` |
| `*` | Multiplication | `a * b` |
| `/` | Division | `a / b` |
| `div` | Integer division | `a div b` |
| `mod` | Modulo | `a mod b` |

#### Comparison

| Operator | Meaning |
|----------|---------|
| `=` | Equal |
| `<>` | Not equal |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less or equal |
| `>=` | Greater or equal |
| `in` | Set membership |

#### Logical and bitwise

| Operator | Meaning |
|----------|---------|
| `and` | Logical/bitwise AND |
| `or` | Logical/bitwise OR |
| `xor` | Logical/bitwise XOR |
| `not` | Logical/bitwise NOT |
| `shl` | Bit shift left |
| `shr` | Bit shift right |

#### Compound assignment

| Operator | Equivalent |
|----------|------------|
| `+=` | `x := x + y` |
| `-=` | `x := x - y` |
| `*=` | `x := x * y` |
| `/=` | `x := x / y` |

#### Other operators

| Operator | Meaning | Example |
|----------|---------|---------|
| `:=` | Assignment | `x := 42` |
| `^` | Pointer dereference (postfix) | `p^` |
| `address of` | Address-of (prefix) | `address of x` |

#### Precedence (highest to lowest)

| Level | Operators |
|-------|-----------|
| 1 (highest) | `not`, unary `-`, unary `+`, `address of` |
| 2 | `*`, `/`, `div`, `mod`, `and`, `shl`, `shr` |
| 3 | `+`, `-`, `or`, `xor` |
| 4 (lowest) | `=`, `<>`, `<`, `>`, `<=`, `>=`, `in` |

All operators are left-associative at every level. Use parentheses to override precedence.


### 🔀 6. Control Flow

*Block-terminated statements -- no parentheses around conditions, no `begin` inside loops.*

#### if / then / else / end

```wkl
if x > 0 then
  println("positive");
end;

if x > 0 then
  println("positive");
else
  println("non-positive");
end;
```

#### while / do / end

```wkl
while x > 0 do
  x -= 1;
end;
```

> [!NOTE]
> **No `begin` in loops.** The syntax is `while expr do stmts end` -- the `do` keyword opens the body directly.

#### for / to / downto / do / end

```wkl
for i := 1 to 10 do
  println("%d", i);
end;

for i := 10 downto 1 do
  println("%d", i);
end;
```

The loop variable must be declared before the loop. `continue` performs the iterator step before re-testing the bound.

#### repeat / until

```wkl
repeat
  x += 1;
until x >= 10;
```

The body executes at least once. `repeat...until` does **not** use `end` -- the `until` keyword closes the loop.

#### match / of / end

```wkl
match value of
  1: println("one");
  2, 3: println("two or three");
  4..10: println("four through ten");
else
  println("something else");
end;
```

`match` supports single values, comma-separated lists, and ranges (`low..high`). The `else` branch handles unmatched values.

#### break and continue

`break` exits the innermost loop. `continue` starts the next iteration. Both are valid only inside `while`, `for`, and `repeat` loops.


### ⚠️ 7. Exception Handling

*guard/except/finally protects code; throw/throwcode raises exceptions.*

#### guard / except / finally / end

```wkl
guard
  // protected code
except
  println("error: code=%d, msg=%s", exccode(), cstr(excmsg()));
finally
  // always runs, even if no exception
end;
```

You can use `except` alone, `finally` alone, or both. The `guard` block catches both software exceptions (`throw`/`throwcode`) and hardware traps (division by zero, out-of-bounds access).

#### throw and throwcode

```wkl
throw("something went wrong");           // code defaults to 1
throwcode(42, "custom error");            // user-defined error code
```

#### Exception intrinsics

| Intrinsic | Returns | Description |
|-----------|---------|-------------|
| `exccode()` | `int32` | Error code of the current exception |
| `excmsg()` | `string` | Error message of the current exception |


### 🔧 8. Routines

*Declared with `routine`. No return type means procedure; with a return type, function.*

#### Procedures

```wkl
routine greet(const name: string);
begin
  println("Hello, %s!", cstr(name));
end;
```

#### Functions

```wkl
routine add(const a: int32; const b: int32): int32;
begin
  return a + b;
end;
```

> [!IMPORTANT]
> **Semicolons separate parameters.** Parameters use `;` between groups, not commas. Use `return` to return a value.

#### Parameter modifiers

| Modifier | Behavior |
|----------|----------|
| *(none)* | Pass by value -- caller's value is copied |
| `const` | Immutable pass by value -- the routine cannot modify the copy |
| `var` | Pass by reference -- the routine modifies the caller's variable |

```wkl
routine swap(var a: int32; var b: int32);
var
  temp: int32;
begin
  temp := a;
  a := b;
  b := temp;
end;
```

> [!TIP]
> **Convention: `const` on every value parameter.** Waskal convention is to mark every value parameter `const` unless `var` is needed. Bare (no modifier) is syntactically valid but `const` makes intent explicit.

#### Local declarations

Routines can contain their own `const`, `type`, and `var` sections in any order:

```wkl
routine compute(): int32;
const
  LOCAL_CONST: int32 = 10;
var
  x: int32;
begin
  x := LOCAL_CONST * 2;
  return x;
end;
```

#### Overloading

Routines with the same name but different parameter signatures are permitted unconditionally -- no opt-in required:

```wkl
routine add(const a: int32; const b: int32): int32;
begin
  return a + b;
end;

routine add(const a: float64; const b: float64): float64;
begin
  return a + b;
end;
```

Resolution prefers an exact non-variadic match; failing that, a variadic routine whose fixed parameters match.

#### Forward declarations

Declare a routine's signature before its implementation:

```wkl
forward routine myFunc(const a: int32): int32;

// ... other code ...

routine myFunc(const a: int32): int32;
begin
  return a * 2;
end;
```

The full declaration must appear later in the same module and must match the forward exactly.

#### Variadic routines

A trailing `...` in the parameter list accepts extra arguments of any type. Access them through `varargs.*`:

```wkl
routine sum(...): int32;
var
  i: int32;
  total: int32;
begin
  total := 0;
  for i := 0 to varargs.count - 1 do
    total += varargs.next(int32);
  end;
  return total;
end;

// sum(1, 2, 3) returns 6
```

| Access | Description |
|--------|-------------|
| `varargs.count` | Number of extra arguments (`int32`) |
| `varargs.next(T)` | Consume and return the next argument as type `T` |
| `varargs.get(i, T)` | Return argument at index `i` as type `T` (no advance) |
| `varargs.reset()` | Reset the cursor to the first argument |
| `varargs.copy()` | Return an independent copy of the pack |

> [!WARNING]
> **Type-checked at runtime.** `next(T)` and `get(i, T)` verify the stored type matches `T`. A mismatch raises a runtime exception (code 900 for type, 901 for index).


### 🔠 9. Type Declarations

*Aliases, pointers, records, choices, overlays, arrays, sets, and routine types.*

#### Type aliases

```wkl
type
  Age = int32;
  Meters = float64;
```

#### Pointer types

```wkl
type
  IntPtr = ptr to int32;
  ConstPtr = ptr to const int32;
```

`^T` is shorthand for `ptr to T`:

```wkl
type
  NodePtr = ^Node;
```

A `ptr` with no target type is an untyped pointer (equivalent to the built-in `ptr` type). Use `address of expr` to take an address and `p^` to dereference.

#### Record types

Records group named fields into a single value:

```wkl
type
  Point = record
    x: int32;
    y: int32;
  end;
```

Records support **single inheritance**, **packed layout**, **alignment control**, and **bit fields**:

```wkl
type
  // Inheritance -- Point3D extends Point
  Point3D = record(Point)
    z: int32;
  end;

  // Packed record -- no padding between fields
  PackedHeader = record packed
    tag: uint8;
    len: uint16;
  end;

  // Alignment -- 16-byte aligned
  AlignedBlock = record align(16)
    data: int64;
  end;

  // Bit fields -- width in bits after the colon
  BitPack = record
    a: uint32 : 4;
    b: uint32 : 4;
    c: uint32 : 8;
  end;
```

> [!NOTE]
> **Record literals.** Construct a value inline: `Point(x: 10, y: 20)`. See [Literals](#literals).

#### Choices (enumerations)

`choices` defines a set of named integer constants:

```wkl
type
  Color = choices(red, green, blue = 5, alpha);
  Dir = choices(north, east, south, west);
```

Values are assigned sequentially starting from 0. An explicit `= N` sets the value and subsequent entries continue from `N + 1`. In the example above, `red = 0`, `green = 1`, `blue = 5`, `alpha = 6`.

#### Overlay types (unions)

`overlay` shares memory between fields -- all fields occupy the same address:

```wkl
type
  Value = overlay
    asInt: int64;
    asFloat: float64;
  end;
```

Anonymous overlays can nest inside records, and anonymous records inside overlays:

```wkl
type
  Tagged = record
    tag: int32;
    overlay
      iVal: int64;
      fVal: float64;
    end;
  end;
```

#### Array types

Static arrays have fixed bounds; dynamic arrays are resizable:

```wkl
type
  Matrix = array[0..3] of array[0..3] of float64;   // static 4x4
  IntList = array of int32;                          // dynamic
```

Use `setlength(arr, n)` to resize a dynamic array and `len(arr)` to query its length. See [Memory](#memory) for details.

#### Set types

Bounded bitsets supporting membership, union, intersection, and difference:

```wkl
var s: set;
s := [1, 3..7, 10];
if 5 in s then
  println("five is in the set");
end;

var a: set;
var b: set;
a := [1, 2, 3];
b := [3, 4, 5];
println("union has 1: %d", int32(1 in (a + b)));    // union
println("isect has 3: %d", int32(3 in (a * b)));    // intersection
println("diff has 1: %d", int32(1 in (a - b)));     // difference
```

Sets support `+` (union), `*` (intersection), `-` (difference), `=` (equality), `<>` (inequality), and `in` (membership).

#### Routine types

Function and procedure types for callbacks:

```wkl
type
  MathFunc = routine(const x: float64): float64;
  Callback = routine(const a: int32; const b: int32): int32;
  Action = routine();
```

A routine-typed variable holds a reference to a routine. A `nil` value means "no routine".

#### Forward types

Declare a type name before its full definition for use in `ptr to` contexts:

```wkl
forward type Node;

type
  NodePtr = ptr to Node;

type
  Node = record
    value: int32;
    next: NodePtr;
  end;
```

The full definition must appear later in the same module.


### 🔤 10. Type Casts

*Explicit conversions use the target primitive as a function call.*

```wkl
var x: int64 = 12345;
var y: int32 = int32(x);         // narrow cast
var f: float64 = 3.14;
var i: int32 = int32(f);         // float to int (truncates)
var g: float64 = float64(y);     // int to float
```

Only built-in type keywords can be used as cast operators (`int32(x)`, `float64(n)`). A user-defined type name followed by parentheses is a call or record literal, not a cast.

#### Automatic type promotion

When mixing types in expressions, the compiler promotes to the wider type:

| Expression | Result type |
|------------|-------------|
| integer + float | float (integer promoted) |
| smaller int + larger int | larger int |
| `float32` + `float64` | `float64` |
| boolean ops (`and`, `or`, `xor`, `not`) | `bool` |
| comparisons (`=`, `<>`, `<`, etc.) | `bool` |
| `string` + `string` | `string` (concatenation) |


### 💬 11. Comments

*Line comments and nestable block comments.*

```wkl
// This is a line comment

/* This is a block comment.
   Block comments can span multiple lines.
   /* They can also be nested. */
*/
```

> [!NOTE]
> **No Pascal-style comments.** The `{ }` and `(* *)` comment forms are not supported.


### ⚡ 12. Intrinsics

*Seventeen built-in operations available without imports.*

#### Value intrinsics

| Intrinsic | Returns | Description |
|-----------|---------|-------------|
| `len(x)` | `int32` | Length of a `string`, `wstring`, or dynamic array |
| `size(T)` | `int64` | Byte size of a type or expression |
| `format(fmt, ...)` | `string` | Build a managed string from printf-style format and arguments |
| `utf8(ws)` | `ptr` | Convert `wstring` to a newly allocated raw UTF-8 buffer (caller owns) |
| `cstr(s)` | `ptr` | Borrowed raw `char*` into a managed string's storage (do not free) |
| `wstr(s)` | `ptr` | Borrowed `wchar*` with runtime caching (do not free) |
| `paramcount()` | `int32` | Number of CLI arguments (excludes program name) |
| `paramstr(i)` | `string` | CLI argument by index (0 = program name) |
| `exccode()` | `int32` | Error code of the current exception |
| `excmsg()` | `string` | Error message of the current exception |

#### Statement-level intrinsics

| Intrinsic | Description |
|-----------|-------------|
| `new(p)` | Allocate and zero-initialize a typed pointer target |
| `dispose(p)` | Free a typed pointer target and set the pointer to nil |
| `getmem(p)` | Allocate raw memory |
| `freemem(p)` | Free raw memory |
| `resizemem(p, n)` | Resize raw memory |
| `setlength(arr, n)` | Resize a dynamic array |

#### Output intrinsics

| Intrinsic | Description |
|-----------|-------------|
| `print(fmt, ...)` | Printf-style formatted output, no newline |
| `println(fmt, ...)` | Printf-style formatted output with newline |

The format string must be a string literal. Supported specifiers: `%d` (int32), `%u` (uint32), `%x`/`%X` (hex), `%f`/`%.Nf` (float), `%s` (ptr to char), `%c` (char), `%lld` (int64), `%%` (literal percent).

> [!TIP]
> **`format` builds a string; `println` writes to the console.** Use `format` when you need the result as a value -- for concatenation, passing to a routine, or assigning to a variable. Example: `var msg: string = format("count: %d", n);`


### 🔀 13. Conditional Compilation

*Compile-time symbol tests that control which code is included.*

Conditional directives are processed at the parser level and do **not** end with semicolons:

```wkl
@define MY_FEATURE

@ifdef MY_FEATURE
  println("feature enabled");
@endif

@ifndef SOME_FLAG
  println("flag not set");
@endif

@ifdef BUILD_EXE
  println("building an executable");
@elseif BUILD_LIB
  println("building a library");
@else
  println("building a unit");
@endif
```

| Directive | Purpose |
|-----------|---------|
| `@define SYMBOL` | Define a compilation symbol |
| `@undef SYMBOL` | Undefine a compilation symbol |
| `@ifdef SYMBOL` | Compile block if symbol is defined |
| `@ifndef SYMBOL` | Compile block if symbol is not defined |
| `@elseif SYMBOL` | Alternate branch with condition |
| `@else` | Alternate branch |
| `@endif` | End conditional block |

Conditional blocks can be nested. They work inside imported unit modules, evaluated with the root module's defines.

#### Predefined symbols

| Symbol | Defined when |
|--------|-------------|
| `WASKAL` | Always |
| `WASM64` | Always (wasm64 architecture) |
| `BUILD_EXE` | Module kind is `exe` |
| `BUILD_LIB` | Module kind is `lib` |

> [!NOTE]
> **No DEBUG or RELEASE symbols.** Use `@define DEBUG` explicitly if you want conditional debug code. See [Diagnostics](#diagnostics) for the `@ifdef DEBUG` pattern.


### 📋 14. Module-Level Directives

*Brief reference -- full details in [Module System](#module-system).*

These directives configure the build and end with a semicolon:

| Directive | Value | Purpose |
|-----------|-------|---------|
| `@outputpath` | `"path"` | Output directory for compiled files |
| `@addlibrarypath` | `"path"` | Add a directory to the JS/wasm library search path |
| `@modulepath` | `"path"` | Add a directory to the module (unit) search path |
| `@optimize` | `none\|1\|2\|3\|4\|s\|z` | Optimization level (bare identifier or digit) |
| `@unittestmode` | `on\|off` | Enable test block compilation and test runner |
| `@favicon` | `"path"` | Set the favicon for the generated `.html` |
| `@asset` | `"path" "vpath"` | Embed a single file as a compressed asset |
| `@assets` | `"path" "base" "pattern"` | Batch-embed files matching a pattern |
| `@message` | `hint\|warn\|error\|fatal "text"` | Emit a compiler diagnostic |

#### Path prefixes

| Prefix | Base directory |
|--------|---------------|
| `$P:` | Compiler executable directory |
| `$D:` | Current working directory |
| `$S:` | Declaring module's directory (the default) |


### 🧪 15. Testing

*Built-in test runner with eight non-aborting assertions.*

Enable testing with `@unittestmode on;` and place test blocks after the module's `end.`:

```wkl
module exe mathlib;

@unittestmode on;

routine add(const a: int32; const b: int32): int32;
begin
  return a + b;
end;

end.

test "add returns correct sum"
var
  result: int32;
begin
  result := add(2, 3);
  asserteq(5, result);
end;

test "add handles negative numbers"
begin
  asserteq(-2, add(-5, 3));
  asserteq(-8, add(-5, -3));
end;
```

When `@unittestmode` is on, the test runner replaces the normal program entry point. Each test runs independently; failures accumulate and are reported at the end.

#### Assertion reference

| Assertion | Purpose |
|-----------|---------|
| `assert(expr)` | Fail if `expr` is false |
| `asserttrue(expr)` | Fail if not true |
| `assertfalse(expr)` | Fail if not false |
| `asserteq(expected, actual)` | Fail if values are not equal (type-dispatched) |
| `asserteqf(expected, actual, epsilon)` | Float equality within tolerance |
| `assertnil(expr)` | Fail if not nil |
| `assertnotnil(expr)` | Fail if nil |
| `assertfail("msg")` | Unconditional failure with a message |

> [!TIP]
> **Test blocks can include `var` sections** for local variables. The compiler injects source file and line number into failure messages automatically.

Next: [Module System](#module-system)

<a id="module-system"></a>

## 📦 Module System

*Every source file is a module. The module kind decides what the compiler produces -- a self-contained web page, a standalone wasm binary, or inline code folded into the importer. One declaration, one rule for visibility, one rule for naming, and the rest follows.*

Waskal compiles one `.wkl` file at a time. The first line declares the module kind and name, and that single decision controls everything downstream: what the output artifact is, whether a main body is allowed, and which symbols other modules can see. Imports are explicit, qualification is mandatory, and every module can define startup and shutdown logic that the runtime wires into the correct order automatically.

> [!TIP]
> **Where to look next.** For the language constructs available inside a module see [Language Reference](#language-reference). For calling JavaScript or linking external wasm libraries see [JS Interop](#js-interop). For heap allocation, strings, and dynamic arrays see [Memory](#memory).


### 📝 1. Module Kinds

*Three kinds, three outputs -- pick the one that matches what you are shipping.*

Every `.wkl` file starts with a module declaration:

```wkl
module <kind> <name>;
```

The name must match the source filename without extension (case-insensitive). A file named `demo.wkl` declares `module exe demo;`.

| Kind | Output | Main body | Description |
|------|--------|-----------|-------------|
| `exe` | `.html` | `begin...end.` | Self-contained web page with embedded wasm64 binary and JS host layer. Double-click it or serve it -- runs in any modern browser. |
| `lib` | `.wasm` | `end.` | Standalone wasm64 binary. Public routines exported by bare name. Consumed via `external` and wasm-merge. |
| `unit` | None (inline) | `end.` | Code incorporated directly into the importing module. No separate artifact. |

> [!NOTE]
> **Exe is a web page.** The `.html` file embeds the base64-encoded wasm binary, the WASI shim, all JS host APIs, and any embedded assets. No external dependencies, no network requests. It runs from `file://` or any web server.

#### Exe module

An exe module is a standalone program. It has a `begin...end.` main body that serves as the entry point:

```wkl
// hello.wkl -- from examples/hello.wkl
module exe hello;

begin
  println("Hello, I am %s! 🚀🔥✨", "Waskal");
end.
```

Only exe modules may have a main body. Compiling `hello.wkl` produces `hello.html`.

#### Unit module

A unit module contains reusable declarations -- routines, types, constants, variables -- that other modules import. Units are compiled inline: their code is emitted into the importing module's wasm output.

```wkl
// bnf_unit_compliance.wkl (trimmed) -- from tests/compliance/bnf_unit_compliance.wkl
module unit bnf_unit_compliance;

public const
  UNIT_VERSION: int32 = 1;

public type
  UnitPoint = record
    x: int32;
    y: int32;
  end;

public routine unit_add(a: int32; b: int32): int32;
begin
  return a + b;
end;

initialize
  unit_global_x := 1;
  unit_global_flag := true;
end;

finalize
  unit_global_x := 0;
  unit_global_flag := false;
end;

end.
```

A unit has no main body -- it ends with `end.` after the optional `initialize`/`finalize` blocks.

#### Lib module

A lib module produces a standalone `.wasm` file containing only the public routines and memory:

```wkl
// mathlib.wkl -- from tests/probe/mathlib.wkl
module lib mathlib;

@outputpath "$P:res/tests/libs";

public routine Add(a: int64; b: int64): int64;
begin
  return a + b;
end;

routine Mul(a: int64; b: int64): int64;
begin
  return a * b;
end;

end.
```

`Add` is exported by bare name. `Mul` is private -- compiled but not exported. The output is `mathlib.wasm`.

> [!IMPORTANT]
> **Lib export rules.** Only `public` routines are exported by bare name. Constants, types, and variables are not exported -- wasm has no mechanism for it. Overloaded public exports are not yet supported (planned via mangled export names).

For how another program consumes a `.wasm` lib, see [JS Interop](#js-interop).


### 📥 2. Imports

*Import a module, qualify every use -- no shortcuts, no ambiguity.*

```wkl
import bnf_unit_compliance;
```

Multiple modules may be imported in one statement or in separate statements. Imports appear after the module header and may also appear among declarations:

```wkl
module exe bnf_exe_compliance;

import bnf_unit_compliance;

const
  MY_CONST: int32 = 100;

// ...

begin
  println("UNIT_VERSION = %d", bnf_unit_compliance.UNIT_VERSION);
  println("unit_add(3, 4) = %d", bnf_unit_compliance.unit_add(3, 4));
end.
```

Every imported symbol must be fully qualified with the module name. `bnf_unit_compliance.unit_add(3, 4)` is correct; bare `unit_add(3, 4)` is a compile error. This applies to routines, types, constants, and variables alike.

> [!NOTE]
> **No unqualified imports.** There is no `use` or `from X import Y` syntax. You always write `module.symbol`. This keeps the origin of every reference immediately visible in the source.

#### Module search paths

The compiler resolves imports by searching for a `.wkl` file in this order:

1. Directory of the importing module's source file
2. Paths added via `@modulepath "path";` directives (in declared order)
3. Built-in standard library: `$P:res/libs/std`
4. Built-in vendor libraries: each subfolder of `$P:res/libs/vendor`

Diamond imports (A imports B and C, both of which import D) are handled by an internal cache -- the unit is parsed and analyzed once and reused.


### 🔒 3. Visibility

*Private by default. Say `public` to export.*

All declarations are private unless marked `public`. The `public` keyword works on constants, types, variables, and routines:

```wkl
public const
  UNIT_VERSION: int32 = 1;

public type
  UnitPoint = record x: int32; y: int32; end;

public var
  unit_global_x: int32;

public routine unit_add(a: int32; b: int32): int32;
begin
  return a + b;
end;
```

Private declarations are visible only within the declaring module.


### 🚀 4. Initialize and Finalize

*Startup and shutdown hooks, wired in dependency order.*

Any module kind can declare `initialize` and `finalize` blocks:

```wkl
initialize
  unit_global_x := 1;
  unit_global_flag := true;
  private_counter := 0;
end;

finalize
  unit_global_x := 0;
  unit_global_flag := false;
end;
```

Both blocks are optional.

**Startup order (`_start`):** runtime init -> unit `initialize` blocks in import order -> this module's `initialize` -> main body (exe only).

**Shutdown order (`_shutdown`):** this module's `finalize` -> unit `finalize` blocks in reverse import order -> global cleanup in reverse order.

This is the standard Pascal/Delphi pattern: units initialize in dependency order, finalize in reverse.

> [!TIP]
> **Use `initialize` for one-time setup** -- allocating resources, registering callbacks, setting initial state. **Use `finalize` for cleanup** -- freeing memory, zeroing handles.


### 🔀 5. Directives

*Nine module-level directives configure the build. Seven conditional-compilation directives gate code at parse time.*

#### Module-level directives

These appear after the module header, before or among declarations. Each is terminated by `;`.

| Directive | Arguments | Effect |
|-----------|-----------|--------|
| `@outputpath "path";` | Quoted string | Sets the output directory for the compiled artifact |
| `@addlibrarypath "path";` | Quoted string | Adds a JS/wasm external library search directory |
| `@modulepath "path";` | Quoted string | Adds a module (unit) search directory |
| `@optimize none|1|2|3|4|s|z;` | Bare identifier | Sets the wasm-opt optimization level. `none` is the default. `1`-`4` map to `-O1`-`-O4`, `s` to `-Os`, `z` to `-Oz` |
| `@unittestmode on|off;` | Bare identifier | Enables or disables test block compilation and test runner |
| `@favicon "path";` | Quoted string | Sets the favicon for the generated `.html` |
| `@asset "path" "virtual_path";` | Two quoted strings | Embeds a single file as a compressed, base64-encoded asset |
| `@assets "source" "base" "pattern";` | Three quoted strings | Batch-embeds every file matching the pattern |
| `@message hint|warn|error|fatal "text";` | Severity + text | Emits a compiler diagnostic at the directive's source location |

> [!NOTE]
> **Directives in units.** Only `@addlibrarypath` and `@modulepath` are honored from imported unit modules. All other directives in a unit are silently ignored -- they are a property of the root module.

#### Path prefixes

Every directive taking a `"path"` resolves relative paths against the declaring module's directory. An optional prefix overrides the base:

| Prefix | Base directory | Typical use |
|--------|---------------|-------------|
| `$P:` | Compiler executable directory | Shipped assets under the compiler's `res` tree |
| `$D:` | Current working directory | Paths relative to where the compiler was invoked |
| `$S:` | Declaring module's directory (the default) | Explicit when a module mixes bases |

```wkl
@addlibrarypath "$P:res/libs/vendor/raylib";
@favicon "$P:res/assets/icons/waskal.ico";
@asset "$P:res/assets/images/waskal.png" "assets/images";
```

> [!TIP]
> **Use `$P:` for portable modules.** A vendor binding that uses a bare relative path breaks as soon as the module is imported from another folder. The `$P:` form always resolves against the compiler's own directory.

#### Conditional compilation directives

These take no terminator (no `;`) and may appear at module level or inside statements. They are evaluated at parse time.

| Directive | Purpose |
|-----------|---------|
| `@define <ident>` | Define a symbol |
| `@undef <ident>` | Undefine a symbol |
| `@ifdef <ident>` | Compile the following block if the symbol is defined |
| `@ifndef <ident>` | Compile the following block if the symbol is not defined |
| `@elseif <ident>` | Else-if: compile if this symbol is defined instead |
| `@else` | Else branch |
| `@endif` | End the conditional block |

```wkl
@define UNIT_FEATURE_A

@ifdef UNIT_FEATURE_A
  // compiled
@endif

@ifndef UNIT_FEATURE_B
  // compiled (UNIT_FEATURE_B was never defined)
@endif
```

Conditional directives work inside imported units too, evaluated with the root module's defines.

#### Predefined symbols

| Symbol | Defined when |
|--------|-------------|
| `WASKAL` | Always |
| `WASM64` | Always (wasm64 architecture) |
| `BUILD_EXE` | Module kind is `exe` |
| `BUILD_LIB` | Module kind is `lib` |
| `UNITTESTMODE` | `@unittestmode on;` is active |


### 🧪 6. Unit Testing

*Test blocks after `end.`, a dedicated runner, eight assertion functions -- built into the language.*

When `@unittestmode on;` is set, test blocks after the module's `end.` terminator are compiled and the test runner replaces the normal entry point. The `begin...end.` main body is not executed.

```wkl
// bnf_unittest_compliance.wkl (trimmed) -- from tests/compliance/bnf_unittest_compliance.wkl
module exe bnf_unittest_compliance;

@unittestmode on;

type
  TPoint = record
    x: int32;
    y: int32;
  end;

routine make_point(const ax: int32; const ay: int32): TPoint;
begin
  var result: TPoint;
  result.x := ax;
  result.y := ay;
  return result;
end;

begin
  // This main body does NOT run when @unittestmode is on.
  // The test runner replaces it.
end.

test "integer arithmetic"
begin
  asserteq(4, 2 + 2);
  asserteq(0, 5 - 5);
end;

test "test-local variables"
var
  i: int32;
  total: int32;
begin
  total := 0;
  for i := 1 to 10 do
    total := total + i;
  end;
  asserteq(55, total, "loop inside a test block");
end;

test "initialize ran before tests"
begin
  asserteq(1, init_flag, "initialize block should have run");
end;
```

Each test block has an optional string name, optional local `var` declarations, and a body containing assertions.

#### Assertions

| Function | Purpose |
|----------|---------|
| `assert(expr)` | Fail if `expr` is false |
| `asserttrue(expr)` | Fail if not true |
| `assertfalse(expr)` | Fail if not false |
| `asserteq(expected, actual [, msg])` | Fail if not equal (type-dispatched) |
| `asserteqf(expected, actual, epsilon)` | Float equality within tolerance |
| `assertnil(expr)` | Fail if not nil |
| `assertnotnil(expr)` | Fail if nil |
| `assertfail(msg)` | Unconditional failure |

All assertions are non-aborting. A failed assertion records the failure but continues executing the test. Failures accumulate and are reported at the end with a summary. Exit code 0 means all tests passed.

> [!NOTE]
> **Initialize and finalize still run.** When unit test mode is on, `initialize` runs before the first test and `finalize` runs after the last. This lets you set up and tear down shared state for the test suite.


### 🏗️ 7. Module Structure Summary

*The complete skeleton, with every optional section in place.*

```wkl
module <kind> <name>;

// directives (optional, in any order, may repeat among declarations)
@optimize s;
@modulepath "$S:../shared";
@unittestmode on;

// imports (optional, may also appear among declarations)
import other_unit;

// declarations: const, type, var, routine -- in any order, repeatable
const
  VERSION: int32 = 1;

type
  MyRecord = record x: int32; y: int32; end;

var
  counter: int32;

routine do_work(): int32;
begin
  return counter + 1;
end;

// lifecycle (optional, all module kinds)
initialize
  counter := 0;
end;

finalize
  counter := 0;
end;

// main body (exe only) or module terminator
begin        // exe: entry point
  // ...
end.

// -- OR for lib/unit: --
end.

// test blocks (only compiled with @unittestmode on)
test "example"
begin
  asserteq(1, do_work());
end;
```

> [!NOTE]
> **`end.` with a period** marks the end of the module proper. Everything after it is test blocks, compiled only when `@unittestmode on;` is active.

<a id="js-interop"></a>

## 🔗 5. JavaScript Interop

*The wasm module computes; the browser does everything else.*

Waskal programs run inside the browser as WebAssembly. Every capability the browser provides -- graphics, audio, input, networking, storage -- reaches Waskal through JavaScript host functions declared with the `external` clause. This section covers how those declarations work, how the build pipeline resolves them, and how to write your own JS and wasm libraries.

Here is the simplest possible JS interop -- two routines imported from a `.js` file and a `.wasm` module, called from `begin..end.`:

```wkl
// probe_extlibs.wkl -- JS and wasm external library test
module exe probe_extlibs;

@addlibrarypath "$P:res/tests/libs";

// JS external -- resolved from mathjs.js in libs/
routine JsAdd(a: int32; b: int32): int32;
  external "mathjs" name "JsAdd";

// Wasm external -- resolved from mathlib.wasm in libs/
routine Add(a: int64; b: int64): int64;
  external "mathlib" name "Add";

var
  r: int64;
begin
  println("JsAdd(2, 3) = %d", JsAdd(2, 3));
  r := Add(10, 20);
  println("Add(10, 20) = %d", r);
end.
```

The JS file that satisfies `"mathjs"`:

```javascript
// mathjs.js
var mathjs = {
  JsAdd: function(a, b) { return a + b; },
  JsMul: function(a, b) { return a * b; }
};
```

The `.wasm` file that satisfies `"mathlib"`:

```wat
;; mathlib.wat (assembled to mathlib.wasm by wasm-opt)
(module
  (memory $mem i64 1)
  (export "memory" (memory $mem))
  (func $Add (param $a i64) (param $b i64) (result i64)
    (i64.add (local.get $a) (local.get $b))
  )
  (export "Add" (func $Add))
)
```

Build and run: `waskal probe_extlibs -r`. The JS lib is bundled into the output `.html`; the wasm lib is merged into the program binary. Both resolve at build time, not at runtime.

> [!NOTE]
> **Two kinds of external library.** A `.js` file becomes a wasm host import -- its functions are called from wasm through the browser's import mechanism. A `.wasm` file is merged into the program module by wasm-merge, so its exports become local functions in the final binary. The external clause is the same for both; the file extension determines the pipeline.


### 🔌 The External Clause

The `external` clause declares a routine whose implementation lives outside the Waskal module -- in a JS file or a pre-compiled wasm module.

```
ExternalClause = "external" [ cstring | ident ] [ "name" cstring ] ";" .
```

| Part | Purpose |
|------|---------|
| `external` | Marks the routine as an import (no body generated) |
| `"mathjs"` | Library name -- becomes the wasm import module name |
| `name "JsAdd"` | Import function name (defaults to the routine name if omitted) |

The library name after `external` can be a string literal or an identifier naming a module-level string constant:

```wkl
// extlibs.wkl -- unit wrapping externals with a constant lib name
public const LIB_MATH: string = "mathjs";

public routine JsAdd(a: int32; b: int32): int32;
  external LIB_MATH name "JsAdd";
```

When the identifier form is used, the compiler resolves it to the constant's value at compile time. A compile error is raised if no such string constant exists.

#### External Variables

The grammar also supports external variable declarations:

```
VarDecl = ident ":" TypeExpr [ "=" Expression ] [ ExternalVarClause ] ";" .
ExternalVarClause = "external" [ cstring | ident ] [ "name" cstring ] .
```

The emitter produces a wasm global import: `(import "lib" "sym" (global $name (mut type)))`.


### 📂 Library File Resolution

When the compiler encounters an `external` clause, it resolves the library name to a file on disk. The search order:

1. The directory of the declaring module
2. Each `@addlibrarypath` directory, in declaration order

At each location the compiler tries `.wasm` first, then `.js`. The first match wins.

| File found | Pipeline |
|------------|----------|
| `.js` | Added to the JS bundle (concatenated with runtime.js, minified by esbuild, injected into `.html`) |
| `.wasm` | Merged into the program binary by wasm-merge |

> [!TIP]
> **Wrap externals in a unit module.** Instead of declaring externals and `@addlibrarypath` in every consumer, put them in a `module unit` and let consumers `import` it. The unit owns the library resolution; consumers see clean, module-qualified calls.

```wkl
// extlibs.wkl -- unit wrapping external libraries
module unit extlibs;

@addlibrarypath "$P:res/tests/libs";

public routine JsAdd(a: int32; b: int32): int32;
  external "mathjs" name "JsAdd";

public routine Add(a: int64; b: int64): int64;
  external "mathlib" name "Add";

end.
```

```wkl
// probe_extlibs_unit.wkl -- consuming externals via a unit
module exe probe_extlibs_unit;

import extlibs;

var
  r: int64;
begin
  println("JsAdd(2, 3) = %d", extlibs.JsAdd(2, 3));
  r := extlibs.Add(10, 20);
  println("Add(10, 20) = %d", r);
end.
```


### ✍️ Writing a JS Library

A JS library is a plain `.js` file that exposes functions as properties of a `var`-declared object. The object name must match the wasm import module name used in the `external` clause.

**Rules:**

1. **Use `var`, not `let` or `const`.** esbuild minification scopes away non-`var` declarations. A `var` declaration survives because it becomes a global property.
2. **Every DOM or browser API call must be wrapped in `try/catch`.** No exception may unwind into wasm -- the program will abort. Return a safe default (false, -1, 0) on failure.
3. **Namespace isolation.** Use an IIFE or a plain object literal. Never reference another shim's globals; shared state goes through documented slots on the `WKL` object only.

Minimal example (the `mathjs.js` from above):

```javascript
var mathjs = {
  JsAdd: function(a, b) { return a + b; },
  JsMul: function(a, b) { return a * b; }
};
```

A std module like `canvas2d.js` uses the IIFE pattern for private state:

```javascript
var canvas2d = (function () {
  var ctx = null;   // private -- not visible to other shims
  return {
    Init: function(w, h, opts) { /* ... */ },
    Clear: function(r, g, b, a) { /* ... */ }
  };
})();
```

#### How JS Libraries Wire into the Output

The build pipeline collects all external JS files, concatenates them after `runtime.js`, runs esbuild for minification, and injects the result into the HTML template. The wasm instantiate call in `index.html` passes each library object as an import namespace:

```javascript
WebAssembly.instantiate(bytes, {
  wasi_snapshot_preview1: wasi.wasiImport,
  waskal: assetBridge,
  mathjs: mathjs      // <-- wired automatically for each JS external
});
```

The `__WKL_EXTRA_IMPORTS__` placeholder in the template is replaced with comma-separated entries for every JS external library the program uses.


### 🔢 Marshalling Contract

Numbers, strings, and JS objects cross the wasm/JS boundary according to a fixed contract. Every std module and every user shim follows the same rules.

#### Numbers

| Domain | Wasm type | Examples |
|--------|-----------|---------|
| Geometry, sizes, angles, alpha, time | `float64` | canvas coordinates, delta time, opacity |
| Counts, indices, handles, booleans | `int32` | key codes, handle IDs, true/false |
| Never pass to a DOM API | `int64` | Arrives as BigInt in JS -- the browser throws on any DOM call that receives one |

A routine declared `int64` in the `.wkl` must return `BigInt` from JS. Mark it with a `// returns BigInt` comment in the shim.

#### Strings In (Waskal to JS)

An extern parameter typed `ptr to char` receives a pointer to a NUL-terminated UTF-8 string in wasm linear memory. The `string` type converts implicitly to `ptr to char` at the call site. On the JS side, read it with `WKL.readCStr(ptr)`.

#### Strings Out (JS to Waskal)

Returning a string from an extern is never correct -- the JS side cannot allocate in wasm memory. Instead, the extern uses a **length-query/fill pattern**:

**Extern shape:**
```wkl
routine GetGreetingInto(buf: ptr to char; bufSize: int64): int64;
  external "cstr2str" name "GetGreeting";
```

**JS side:**
```javascript
GetGreeting: function(buf, size) {
  return WKL.writeCStr("hello from js", buf, size);
}
```

`WKL.writeCStr(str, buf, size)` writes `min(len, size-1)` bytes plus a NUL terminator and returns the full byte length as `BigInt`. Passing `bufSize = 0` is a length query -- nothing is written.

**Waskal wrapper pattern:**
```wkl
// probe_cstr2str.wkl -- string marshalling round-trip
var
  needed: int64;
  buf: ptr to char;
  s: string;
begin
  needed := GetGreetingInto(nil, 0);      // length query
  getmem(buf);
  resizemem(buf, needed + 1);             // allocate
  GetGreetingInto(buf, needed + 1);       // fill
  s := buf;                                // assign to managed string
  freemem(buf);                            // release raw buffer
  println("%s", cstr(s));                  // "hello from js"
end.
```

#### JS Object Handles

Browser objects (canvases, gradients, audio nodes) cannot cross the wasm boundary. The shim stores them in a handle table created by `WKL.handles()` and returns an `int32` handle to Waskal. The Waskal side declares a type alias: `type Gradient = int32;`. Handle 0 means "none". A `Release(h)` call frees the slot.


### 🌐 The WKL Shared Object

`runtime.js` creates a global `WKL` object that every shim and the runtime itself depend on. It is the only communication channel between std modules.

| Slot | Set by | Read by | Purpose |
|------|--------|---------|---------|
| `moduleName` | `index.html` | shims | Program name from wasi args |
| `onLoopEnd` | `index.html` | `frame.js` | Called when the animation loop ends |
| `onTick` | `input.js` | `frame.js` | Called at the top of every tick before any wasm call |
| `canvas` | `canvas2d.js` | `input.js` | The active canvas element for mouse coordinate mapping |
| `canvasDpr` | `canvas2d.js` | `input.js` | Device pixel ratio for coordinate scaling |
| `onExit` | std modules | `index.html` | Array of cleanup callbacks run after `_shutdown` |

**Helper methods:**

| Method | Purpose |
|--------|---------|
| `readCStr(ptr)` | Read a NUL-terminated UTF-8 string from wasm memory |
| `writeCStr(str, buf, size)` | Write UTF-8 into a wasm buffer; returns `BigInt` byte length |
| `handles()` | Factory -- returns `{alloc, get, release}` for a handle table |
| `fail(e)` | Uniform error handler (logs and throws) |
| `runExit()` | Fire `onExit` callbacks; leave app mode |

> [!NOTE]
> **Std modules never reference each other.** `input.js` reads `WKL.canvas` to map mouse coordinates, but it never imports anything from `canvas2d.js` directly. All cross-module communication goes through `WKL` slots. This keeps the modules independently optional.


### 📦 Wasm Library Authoring

A pre-compiled `.wasm` file can be linked into a Waskal program via wasm-merge. The program declares the import; the build pipeline merges the two modules into one binary.

**Requirements:**
- The `.wasm` module must export the functions the Waskal program imports by name.
- It must export its `memory` (wasm-merge needs it for linking).

Example `.wat` source for a wasm library:

```wat
;; mathlib.wat
(module
  (memory $mem i64 1)
  (export "memory" (memory $mem))
  (func $Add (param $a i64) (param $b i64) (result i64)
    (i64.add (local.get $a) (local.get $b))
  )
  (export "Add" (func $Add))
)
```

Waskal side:

```wkl
routine Add(a: int64; b: int64): int64;
  external "mathlib" name "Add";
```

The library file name (without extension) becomes the wasm module name for the merge. wasm-merge combines the program `.wasm` and every external `.wasm` into one binary, then wasm-opt optimizes the result.


### 🏗️ Waskal Lib Modules

A Waskal program can produce a `.wasm` library instead of an `.html` executable. Declare the module as `lib`:

```wkl
module lib mathutils;

public routine Add(a: int64; b: int64): int64;
begin
  return a + b;
end;

end.
```

Public non-external routines are exported by their bare name. Other Waskal programs (or any wasm host) link against the output `.wasm` via `external "mathutils" name "Add"`.

> [!NOTE]
> **Overloaded exports are not yet supported.** Lib modules currently reject public overloaded routines because exports use bare names. Mangled-name exports are planned -- see the project roadmap.


### 📋 Build Pipeline Summary

The external library pipeline from source to output:

| Stage | JS library (.js) | Wasm library (.wasm) |
|-------|-------------------|----------------------|
| **Resolve** | Compiler finds `.js` file via search paths | Compiler finds `.wasm` file via search paths |
| **Collect** | Added to JS bundle after `runtime.js` | Added to wasm-merge input list |
| **Bundle** | Concatenated, minified by esbuild | Merged with program `.wasm` by wasm-merge |
| **Inject** | Minified JS injected into HTML template | Merged `.wasm` base64-encoded into HTML template |
| **Wire** | Import namespace entry added to `WebAssembly.instantiate()` | Imports resolved internally (same module) |

The result is a single `.html` file where every external dependency -- JS or wasm -- is embedded. No runtime resolution, no network requests, no external files.

Next: [Memory and Data Structures](#memory-data-structures)

<a id="memory-data-structures"></a>

## 🧠 6. Memory and Data Structures

*Waskal manages memory at runtime so you rarely have to -- but gives you full control when you want it.*

Every Waskal program runs on a single wasm64 linear memory. The runtime provides a heap allocator for dynamic data, reference-counted strings, resizable arrays, and automatic cleanup walks that free temporaries and locals at every scope exit. At optimization level 0, the runtime also tracks allocations and reports leaks on shutdown -- a one-line diagnostic that catches every unpaired `getmem`/`freemem` in the program.

Here is heap allocation and dynamic arrays in action, trimmed from the compliance suite:

```wkl
// bnf_exe_compliance.wkl -- phases 21 + 25
var mbuf: ptr to uint8;
var darr: array of int32;

// Raw heap allocation
getmem(mbuf);
freemem(mbuf);

getmem(mbuf);
resizemem(mbuf, 1024);
setlength(mbuf, 2048);
freemem(mbuf);

// Dynamic array
setlength(darr, 5);
darr[0] := 100;
darr[4] := 500;
println("len=%lld darr[0]=%d", len(darr), darr[0]);

setlength(darr, 7);       // grow -- old data preserved
darr[6] := 700;
println("len=%lld darr[6]=%d", len(darr), darr[6]);
```

Build at O0 to see the leak report: `waskal bnf_exe_compliance -opt none`. On shutdown the runtime prints `[Heap] Allocs: N, Frees: N, Leaked: 0` -- confirming every allocation was paired with a free.


### 🏗️ The Heap Allocator

Waskal's heap is a free-list allocator layered over the wasm64 linear memory. There is no OS heap and no external allocator -- the runtime manages everything in the same address space the program already has.

Every allocated block carries an 8-byte header storing the block size (including the header). Free blocks chain through a singly-linked list embedded in the first 8 bytes of user data. All sizes are rounded up to 16-byte alignment, so the minimum block is 16 bytes (8 header + 8 link).

Allocation tries the free list first (first-fit), then bumps a heap pointer. If the bump exceeds the current memory, the runtime grows the linear memory automatically. Deallocation prepends the block back to the free list. Adjacent free blocks are not coalesced -- for browser-hosted programs with short lifetimes (games, demos, tools), the simplicity trade-off is acceptable.

> [!NOTE]
> **Page 0 is reserved.** The first 65536 bytes (page 0) of linear memory are reserved for runtime scratch data -- static data segments, the function table, and internal bookkeeping. The heap begins above all static data segments.


### 🔧 Memory Builtins

Six builtins map to runtime calls. The compiler emits the appropriate wasm instructions for each.

| Builtin | Purpose | Notes |
|---------|---------|-------|
| `getmem(p)` | Allocate raw memory | Size determined by the pointer's target type |
| `freemem(p)` | Free raw memory | Sets `p` to `nil` afterwards |
| `resizemem(p, n)` | Resize an allocation to `n` bytes | Copies existing data; assigns the new pointer back to `p` |
| `new(p)` | Typed allocation | Same as `getmem` -- allocates `size(T)` bytes for `ptr to T` |
| `dispose(p)` | Typed deallocation | Same as `freemem` -- frees and nils |
| `setlength(x, n)` | Resize a dynamic array or raw buffer | Dispatches by type: dynamic arrays, strings, and raw pointers each have their own runtime path |

> [!TIP]
> **Pair every allocation.** `getmem` pairs with `freemem`, `new` pairs with `dispose`, and dynamic arrays are freed by `setlength(arr, 0)`. At O0 the leak report catches any mismatch.


### 📜 Strings

Strings are reference-counted, heap-allocated, NUL-terminated UTF-8 values. A string variable holds a 64-bit pointer to an internal record (40 bytes):

| Offset | Field | Size | Purpose |
|--------|-------|------|---------|
| 0 | RefCount | i64 | Reference count (1+ = live, 0 = dead) |
| 8 | Length | i64 | Byte length excluding NUL |
| 16 | Capacity | i64 | Buffer capacity excluding NUL |
| 24 | Data | i64 | Pointer to the UTF-8 byte buffer |
| 32 | Data16 | i64 | Cached UTF-16 view (built lazily on first wide-string access) |

A `nil` string pointer (0) represents the empty string -- all runtime operations are nil-safe.

> [!NOTE]
> **Immortal strings.** The runtime supports a special refcount value of -1 meaning "never freed" -- AddRef and Release are no-ops for these strings. The compiler does not currently create immortal strings (all literals get refcount 1), but the machinery exists in the runtime for future use.

#### Reference Counting

The runtime manages string lifetimes through three operations:

- **AddRef** -- increments the reference count when a string is assigned to a new variable or passed to a routine.
- **Release** -- decrements the reference count; when it reaches zero, the runtime frees the Data buffer, the optional Data16 buffer, and the record itself (three heap frees).
- **Assign** -- AddRefs the source first (safe for self-assignment), stores the new pointer, then releases the old value.

You never call these yourself -- the compiler inserts them at every assignment, scope exit, and temporary cleanup.

Here is the string lifecycle exercised across five paths:

```wkl
// probe_string_lifetime.wkl -- string refcount lifecycle
module exe probe_string_lifetime;

begin
  var s1: string;
  s1 := "hello";               // literal -> new string (refcount 1)
  println("%s", s1);

  var s2: string;
  s2 := "hello " + "world";    // concat -> new string (refcount 1)
  println("%s", s2);

  s1 := "goodbye";             // Release old "hello", assign new
  println("%s", s1);

  var s3: string;
  s3 := s2;                    // AddRef on s2 (refcount 2)
  println("%s", s3);

  if s1 = "goodbye" then       // lexicographic comparison
    println("match");
  end
end.
```

At scope exit the compiler releases `s1`, `s2`, and `s3`. Because `s2` and `s3` share the same underlying record, `s3`'s release decrements to 1 and `s2`'s release decrements to 0 -- which triggers the free.

#### Concatenation and SetLength

`s1 + s2` allocates a new string with the combined content. Neither operand is modified; the result has refcount 1.

`setlength(s, n)` allocates a new string of capacity `n`, copies the existing prefix, zero-fills the tail, and releases the old string. This is useful for building strings incrementally.

#### Wide Strings

Wide strings (`wstring`) use the same record layout. The difference is that `len()` and comparison operate on the UTF-16 view (the Data16 field) rather than the raw UTF-8 bytes. The UTF-16 view is built lazily on first access and cached for subsequent calls. Concatenation delegates to the UTF-8 path -- the Data16 cache is rebuilt on demand.

#### Format Builders

`print` and `println` use printf-style format strings. The compiler decomposes the format at compile time into a chain of typed append calls (`rt_fmt_i64`, `rt_fmt_f64`, `rt_fmt_str`, etc.) that build a managed string, write it to stdout, and release it. You never interact with format builders directly.


### 📐 Dynamic Arrays

A dynamic array is a heap-allocated contiguous block with an 8-byte element count stored immediately before the first element:

```
[count: i64] [element 0] [element 1] [element 2] ...
 (ptr - 8)    ptr ->
```

The array variable holds a pointer to element 0. `len(arr)` reads the count at `ptr - 8`. A nil pointer (0) means length 0.

All lifecycle operations go through `setlength`:

```wkl
// probe_array.wkl -- dynamic array lifecycle (trimmed)
var darr: array of int32;

setlength(darr, 5);             // allocate, zero-filled
darr[0] := 100;
darr[4] := 500;
println("len=%lld", len(darr)); // 5

setlength(darr, 7);             // grow -- old data preserved, tail zeroed
darr[6] := 700;

setlength(darr, 3);             // shrink -- truncates
setlength(darr, 0);             // free
println("len=%lld", len(darr)); // 0
```

Growing an array allocates a new block, copies the existing elements, and zero-fills the new slots. Shrinking truncates in place. Setting the length to 0 frees the block entirely.

> [!NOTE]
> **Managed element cleanup.** When a dynamic array of strings or pointers is freed or shrunk, the runtime walks the removed elements and releases each one (strings via Release, pointers via FreeMem, nested dynamic arrays via DynFree). You do not need to release individual elements before resizing.


### 📦 Varargs Packs

Variadic routines (`...` parameter) receive their arguments as a heap-allocated tagged pack. Each slot stores a type tag and a value (16 bytes per slot). The runtime checks types at access time and raises error code 900 (type mismatch) or 901 (index out of bounds) on violations.

Varargs packs are created by the caller, passed by pointer, and freed by the cleanup walk after the call. For full syntax and usage, see the Variadic Routines section of the [Language Reference](#language-reference).


### 🧹 Cleanup Walks

The compiler generates cleanup code at three levels to ensure no managed resource leaks:

**Statement temporaries.** After every statement that produces string temporaries (concatenation results, format builder outputs), the compiler emits Release calls for each temporary. Aggregate temporaries (record or array intermediates) are freed via FreeMem.

**Routine exit.** When a routine returns, the compiler walks every local variable. Strings are released. Heap-backed locals (records, overlays, static arrays allocated on the heap) have their managed fields released, then the block itself is freed. Dynamic array locals are freed via DynFree.

**Program shutdown.** The `_shutdown` export runs the full teardown:

1. User shutdown handler (if registered, e.g. via `frame.Run`)
2. This module's `finalize` block
3. Imported units' `finalize` blocks in reverse import order
4. Global variable cleanup for imported units (reverse order), then this module
5. Clear the last exception record
6. Leak report (O0 only)

This sequence is deterministic -- finalize blocks and global cleanup always run in the same order for a given program. The reverse ordering ensures that a unit's globals are still alive when its dependents finalize.


### 📊 Leak Report

At optimization level 0, the runtime tracks every allocation and deallocation through wrapper functions that increment two counters. On shutdown, after the full cleanup walk, the runtime prints:

```
[Heap] Allocs: 42, Frees: 42, Leaked: 0
```

A non-zero "Leaked" count means the program has unpaired allocations. Since the cleanup walks handle strings, dynamic arrays, and all managed temporaries automatically, a leak usually points to a raw `getmem` without a matching `freemem`.

At optimization level 1 and above, the wrappers are pass-through -- no counters, no report, no overhead.

> [!TIP]
> **Use O0 during development.** Build with `waskal myprogram -opt none` to catch leaks early. The leak report runs after all cleanup walks, so it reflects the program's actual resource discipline, not just the final state of the heap.

Next: [BNF Grammar](#bnf-grammar)

<a id="bnf-grammar"></a>

## 🧾 BNF Grammar

### 🧾 Syntax Notation

This section is the formal grammar reference for the Waskal Programming Language. It is intended for implementers, tooling authors, and anyone who needs exact syntax rules.

The grammar uses EBNF notation. Brackets `[` and `]` mark optional elements. Braces `{` and `}` mark repetition, zero or more times. Parentheses group alternatives. The vertical bar `|` separates alternatives. Terminal symbols are enclosed in quotes or written as lowercase literal tokens. Non-terminals are written in PascalCase.


> [!NOTE]
> 🧾 This file is intentionally formal. Use it when you need the exact grammar contract.

### 🔎 How to Read This Grammar

| Symbol | Meaning |
|--------|---------|
| `A B` | `A` followed by `B` |
| `A | B` | either `A` or `B` |
| `[ A ]` | optional `A` |
| `{ A }` | zero or more repetitions of `A` |
| `( A | B )` | grouped alternatives |
| `"text"` | literal source text |

> [!TIP]
> 💡 When implementing a parser, treat this file as the external behavior contract, not as a required internal parser architecture. Recursive descent, Pratt parsing, table-driven parsing, or another strategy can all implement the same grammar.


### 🔤 1. Lexical Elements

```
letter     = "A" | ... | "Z" | "a" | ... | "z" | "_" .
digit      = "0" | ... | "9" .
hexDigit   = digit | "A" | ... | "F" | "a" | ... | "f" .
character  = (* any source character except the delimiter *) .
newline    = (* line feed (U+000A) *) .

ident      = letter { letter | digit } .
integer    = digit { digit } | "0" ( "x" | "X" ) hexDigit { hexDigit } .
float_literal = digit { digit } "." { digit } [ exponent ] [ "f" | "F" ] .
exponent      = ( "e" | "E" ) [ "+" | "-" ] digit { digit } .
cstring    = '"' { character | escapeSeq } '"' .
wstring    = "w" '"' { character | escapeSeq } '"' .
escapeSeq  = "\" ( "n" | "t" | "r" | "0" | "\" | "'" | '"' | "x" hexDigit hexDigit ) .
```

#### 🔢 Numeric Literal Type Rules

| Literal         | Suffix | Type      | Example         |
|----------------|--------|-----------|-----------------|
| `42`           | --     | `int32` | integer |
| `1.5`          | --     | contextual | float literal |
| `1.5f`, `1.5F` | `f`/`F` | `float32` | explicit `float32` |

**Float literal resolution without a suffix:**

- Assigned to a `float32` variable or passed to a `float32` parameter: `float32`
- Assigned to a `float64` variable or passed to a `float64` parameter: `float64`
- Ambiguous or unknown context: `float64`

**Float literal resolution with `f` or `F` suffix:**

- Always `float32`, regardless of context

#### 🧵 String Literal Convention

- `"..."` -- String literal. Escape sequences processed. UTF-8 encoded.
- `w"..."` -- Wide string literal. Escape sequences processed. UTF-16 encoded. Prefix is case-sensitive: only lowercase `w`.

#### 🔤 Character Type Assignment Rules

The `char` and `wchar` types have no dedicated literal syntax. Characters are
assigned using string literals, variable-to-variable assignment, or string indexing.
The semantic pass validates type compatibility using the AST.

**Valid `char` assignments:**
- `c := "x";` -- A `cstring` literal of exactly one character. The semantic pass
  verifies `len = 1`; longer literals produce a compile error.
- `c := d;` -- Where `d` is also of type `char`.
- `c := s[i];` -- Indexing a `string` yields a `char`.

**Valid `wchar` assignments:**
- `wc := w"x";` -- A `wstring` literal of exactly one character (semantic-checked).
- `wc := wd;` -- Where `wd` is also of type `wchar`.
- `wc := ws[i];` -- Indexing a `wstring` yields a `wchar`.

**Invalid assignments (compile error):**
- `c := "abc";` -- Multi-character literal assigned to `char`.
- `c := s;` -- `string` variable assigned to `char` (use indexing instead).
- `c := wc;` -- `wchar` assigned to `char` (width mismatch).
- `wc := c;` -- `char` assigned to `wchar` (width mismatch).


### 🚫 2. Reserved Words

The language is **case-sensitive** for keywords and identifiers.

```
address    align      and        array      assert     asserteq
asserteqf  assertfalse assertfail assertnil assertnotnil asserttrue
begin      break      choices    const      continue
cstr       dispose    div        do         downto
else       end        except     exccode    excmsg
external   false      finalize   finally    format
for        forward    freemem    getmem     guard
if         import     in         initialize is         len
match      mod        module     new
nil        not        of         or         overlay
packed     paramcount paramstr   print      ptr
println    public     record     repeat     resizemem
return     routine    set        setlength  shl
shr        size       test       then       throw
throwcode  to         true       type       until      utf8
var        varargs    while      wstr       xor
```

> [!NOTE]
> The identifiers `exe`, `lib`, and `unit` are contextual. They have special meaning only in the `ModuleKind` position and may be used as ordinary identifiers elsewhere. Unit modules are `.wkl` source files that are compiled inline into the importing module rather than producing separate output.


### 🧱 3. Built-in Types

```
int8       int16      int32      int64
uint8      uint16     uint32     uint64
float32    float64
bool
char       wchar
string     wstring
ptr
varargs
```

#### 📏 Type Sizes

| Type        | Size (bytes) | Description            |
|-------------|-------------|------------------------|
| `int8`      | 1           | Signed 8-bit integer   |
| `int16`     | 2           | Signed 16-bit integer  |
| `int32`     | 4           | Signed 32-bit integer  |
| `int64`     | 8           | Signed 64-bit integer  |
| `uint8`     | 1           | Unsigned 8-bit integer |
| `uint16`    | 2           | Unsigned 16-bit integer|
| `uint32`    | 4           | Unsigned 32-bit integer|
| `uint64`    | 8           | Unsigned 64-bit integer|
| `float32`   | 4           | 32-bit IEEE 754 float  |
| `float64`   | 8           | 64-bit IEEE 754 float  |
| `bool`      | 1           | Boolean (0 or 1)       |
| `char`      | 1           | 8-bit character        |
| `wchar`     | 2           | 16-bit wide character  |
| `string`    | 8 (pointer) | Managed UTF-8 string   |
| `wstring`   | 8 (pointer) | Managed UTF-16 string  |
| `ptr`       | 8           | Untyped pointer        |
| `varargs`   | 8 (pointer) | Variadic argument pack (see Section 14) |


### ⚙️ 4. Operators and Delimiters

```
+    -    *    /    =    <>   <    >    <=   >=
:=   +=   -=   *=   /=
:    ;    ,    .    ..   ...  ^    |    &
(    )    [    ]
```

#### 🧠 Operator Semantics

- `:=` -- Assignment
- `=` -- Equality comparison
- `<>` -- Not equal
- `^` -- Postfix: pointer dereference. Prefix in a type position: pointer type (Section 10)
- `address of` -- Prefix: address-of (Section 12)
- `...` -- Variadic marker in a parameter list (Section 9)
- `|`, `&` -- Reserved tokens (lexed, not accepted by the grammar)


### 💬 5. Comments

```
Comment    = "//" { character } newline
           | "/*" { character | Comment } "*/" .
```

- `//` -- Line comment.
- `/* ... */` -- Block comment. May be nested.

> [!NOTE]
> `(* *)` and `{ }` are not comment delimiters in Waskal.


### 🧱 6. Module Structure

```
Module        = "module" ModuleKind ident ";" [ Directives ] [ ImportClause ]
                { Declaration | Directive | ImportClause }
                [ "initialize" StatementSeq "end" ";" ]
                [ "finalize" StatementSeq "end" ";" ]
                ( MainBody | "end" "." )
                { TestBlock } .

MainBody      = "begin" StatementSeq "end" "." .   (* exe modules only *)

ModuleKind    = "exe" | "lib" | "unit" .

Directives    = { Directive } .
Directive     = "@" ident [ DirectiveValue ] ";" .
DirectiveValue = ( cstring | integer | float_literal | ident )
                 { cstring | integer | float_literal | ident } .

ImportClause  = "import" ident { "," ident } ";" .

TestBlock     = "test" [ cstring ] [ ";" ] [ "var" { VarDecl } ]
                "begin" StatementSeq "end" ";" .
```

> [!NOTE]
> **Module name.** The module identifier must equal the source file name
> without extension (case-insensitive). `module exe demo;` must live in
> `demo.wkl`.

> [!NOTE]
> **Directives and imports among declarations.** Non-conditional directives
> and additional `import` clauses may appear anywhere in the declaration
> section, not only in the header.

> [!NOTE]
> **Module lifecycle: `initialize` and `finalize`.** The `initialize` and `finalize`
> blocks are module lifecycle hooks. `initialize` runs at startup (before the
> entry point), `finalize` runs at shutdown. Both are optional and supported on
> all module kinds. They are separate from `begin`, which is the main program
> body for exe modules. For unit modules, `initialize`/`finalize` provide
> startup and shutdown hooks. The emitter wires them into the entry point.

> [!IMPORTANT]
> **Module qualification rule.** All public symbols from an imported module must be
> accessed using full module qualification: `moduleName.symbolName`. Unqualified
> access to imported symbols is a compile error. This applies to routines, types,
> variables, and constants alike. If modules A and B both export a symbol `Foo`,
> they are distinguished as `A.Foo` and `B.Foo` -- there is no ambiguity.

> [!NOTE]
> **Directive termination.** Every directive is terminated by `;` -- with one
> exception: the seven conditional-compilation directives (Section 7:
> `@define`, `@undef`, `@ifdef`, `@ifndef`, `@elseif`, `@else`, `@endif`)
> take **no** terminator.

> [!NOTE]
> **Test blocks.** Test blocks appear after `end.` and are only compiled when
> `@unittestmode on;` is active. Each test block has an optional string name, optional local
> variables, and a body. When unittest mode is on, the compiler replaces the normal
> entry point with the test runner. Test blocks have access to all module declarations.


### 🔀 7. Conditional Compilation

```
ConditionalDirective = DefineDir | UndefDir | IfdefDir | IfndefDir
                     | ElseIfDir | ElseDir | EndifDir .

DefineDir   = "@define" ident .
UndefDir    = "@undef" ident .
IfdefDir    = "@ifdef" ident .
IfndefDir   = "@ifndef" ident .
ElseIfDir   = "@elseif" ident .
ElseDir     = "@else" .
EndifDir    = "@endif" .
```

#### 📜 Known Directives

All directives below are terminated by `;`. Bare identifiers are the canonical
form for enumerated values; quoted strings are reserved for paths and free text.

**Module-level directives** (appear after `module` header, before or among declarations):

- `@outputpath "path";` -- Sets the output directory for the compiled `.html` file.
- `@addlibrarypath "path";` -- Adds a directory to the JS/wasm external library search path.
- `@modulepath "path";` -- Adds a directory to the module (unit) search path.
- `@optimize none|1|2|3|4|s|z;` -- Sets optimization level (bare identifier or digit). `none` is the default. Controls the wasm-opt pass: `1`..`4` map to `-O1`..`-O4`, `s` to `-Os`, `z` to `-Oz`.
- `@unittestmode on|off;` -- Enables or disables test block compilation and test runner entry point (bare identifier).
- `@favicon "path";` -- Sets the favicon for the generated `.html` file.
- `@asset "path" "virtual_path";` -- Embeds a single file as a compressed, base64-encoded asset in the output `.html`. The physical file at `"path"` is deflate-compressed and injected; at runtime it is decompressed and preloaded. The `"virtual_path"` determines the folder component of the asset key; the filename is appended automatically (e.g. `@asset "$P:res/images/logo.png" "assets/images";` produces key `assets/images/logo.png`).
- `@assets "source_path" "base_folder" "pattern";` -- Batch-embeds every file under `"source_path"` (recursive) whose name matches `"pattern"` (`*`, `*.ogg`, `song*.ogg`). Each file is compressed and encoded like `@asset`. `"base_folder"` must name a whole path segment of the resolved `"source_path"` (deepest match wins; `"assets/audio"` also allowed); the virtual key is the file's path relative to the directory containing that segment, so `@assets "$P:res/assets/audio" "assets" "*.ogg";` yields keys like `assets/audio/sfx/samp0.ogg`. A base folder not present in the source path is a build error.
- `@message hint|warn|error|fatal "text";` -- Emits a compiler diagnostic with the given severity and message text at the directive's source location.

##### Path resolution

Every directive taking a `"path"` resolves it the same way. An absolute path is
used as-is. A relative path resolves against the directory of the module that
declares the directive, so a module and the files it references travel together.

An optional prefix overrides that base:

| Prefix | Base | Use for |
|---|---|---|
| `$P:` | Directory of the running compiler executable | Shipped assets under the compiler's own `res` tree |
| `$D:` | Current working directory | Paths relative to where the compiler was invoked |
| `$S:` | Declaring module's directory -- the default, stated explicitly | Clarity in modules that mix bases |

The prefix is matched case-insensitively and only at the very start of the
string. A path containing `$P:` anywhere else is left alone.

`$P:` is the correct choice for any module meant to be imported from another
folder. A vendor binding that says `@addlibrarypath "res/libs/vendor"` resolves
against its own directory and fails as soon as the module is used from elsewhere;
the `$P:` form always finds the file shipped beside the compiler:

```
@addlibrarypath "$P:res/libs/vendor/raylib";
@favicon "$P:res/assets/icons/waskal.ico";
```

**Statement-level directives:**

Only the conditional-compilation directives (`@ifdef`, `@ifndef`, `@elseif`,
`@else`, `@endif`, `@define`, `@undef`) are accepted at statement level.
`@message` is module-level only. There is no `@breakpoint` directive.

> [!NOTE]
> **Conditionals in imported units.** The conditional-compilation directives
> (`@define`, `@undef`, `@ifdef`, `@ifndef`, `@elseif`, `@else`, `@endif`)
> take no terminator and also work inside imported unit modules, evaluated
> with the root module's defines (e.g. `WASKAL`, `WASM64`).

#### 🏁 Predefined Symbols

| Symbol               | Defined when                          |
|----------------------|---------------------------------------|
| `WASKAL`             | Always                                |
| `WASM64`             | Always (wasm64 architecture)          |
| `BUILD_EXE`          | Module kind is `exe`                  |
| `BUILD_LIB`          | Module kind is `lib`                  |


### 📦 8. Declarations

```
Declaration     = [ "public" ] ( ConstSection | TypeSection | VarSection | RoutineDecl )
                | [ "public" ] ForwardDecl .

ConstSection    = "const" { ConstDecl } .
ConstDecl       = ident [ ":" TypeExpr ] "=" Expression ";" .

TypeSection     = "type" { TypeDecl } .
TypeDecl        = ident "=" TypeDef ";" .

VarSection      = "var" { VarDecl } .
VarDecl         = ident ":" TypeExpr [ "=" Expression ] [ ExternalVarClause ] ";" .
ExternalVarClause = "external" [ cstring | ident ] [ "name" cstring ] .

ForwardDecl     = "forward" ( ForwardType | ForwardRoutine ) .
ForwardType     = "type" ident ";" .
ForwardRoutine  = "routine" ident [ FormalParams ] [ ":" TypeExpr ] ";" .
```

> [!NOTE]
> **`public` placement.** `public` precedes the section keyword (`const`,
> `type`, `var`), `routine`, or `forward`, and applies to every declaration
> in that section. It is not accepted on individual entries inside a section.

> [!IMPORTANT]
> **Forward declaration semantics.** A `forward` declaration introduces a name
> before its full definition appears. The full declaration must appear later in
> the same module. For types, a forward-declared name may only be used in
> `ptr to` contexts until the full definition is seen, because the type's
> size and layout are unknown. For routines, the forward carries the full
> signature, so calls are valid immediately. If a forward declaration has no
> matching full declaration by module end, it is a compile error. The full
> declaration must match the forward exactly: parameter count, parameter
> modes, parameter types, return type, and the `...` variadic marker
> (error SEM012 on mismatch).


### 🔧 9. Routine Declarations

```
RoutineDecl     = "routine" ident [ FormalParams ] [ ":" TypeExpr ] ";"
                  ( ExternalClause | RoutineBody ) .

FormalParams    = "(" [ ParamList ] ")" .
ParamList       = ParamDecl { ";" ParamDecl } [ ";" "..." ] | "..." .
ParamDecl       = [ "var" | "const" ] ident ":" TypeExpr .

ExternalClause  = "external" [ cstring | ident ] [ "name" cstring ] ";" .

RoutineBody     = { "type" { TypeDecl }
                  | "const" { ConstDecl }
                  | "var" { VarDecl } }
                  "begin" StatementSeq "end" ";" .
```

> [!NOTE]
> **Local sections.** `type`, `const`, and `var` sections inside a routine
> may appear in any order and may repeat.

> [!NOTE]
> **No linkage spec.** Waskal has no `clink` or `cpplink` keywords. All routines
> use unconditional name mangling in the wasm output. Overloading is always
> available -- no opt-in required.

> [!IMPORTANT]
> **Arity is checked on every call.** A call to a non-variadic routine must
> pass exactly `Params.Count` arguments; a call to a variadic routine must
> pass at least that many (error SEM009 otherwise). The extra arguments are
> packed for the callee (Section 14).

#### 🔄 Routine Overloading

Multiple routines with the same name but different parameter signatures are
permitted unconditionally. A variadic routine `f(a: int32; ...)` and a fixed
routine `f(a: int32)` are distinct signatures. Overload resolution at the
call site first looks for a non-variadic routine whose parameter count and
types match the arguments exactly; failing that, a variadic routine whose
fixed parameters match the leading arguments. The emitter always generates
mangled wasm names (`$<module>.<name>__<sig>`, with a trailing `__va` for
variadic routines) for all functions.

```
routine add(const a: int32; const b: int32): int32;
begin
  return a + b;
end;

routine add(const a: float64; const b: float64): float64;
begin
  return a + b;
end;
```

#### 🔗 External Clause Semantics

The `external` clause declares a routine that is provided by an external JS or
wasm module, resolved at build time via `@addlibrarypath`.

The optional value after `external` names the library to import from:

- **String literal** -- the library name/path directly: `external "mathjs";`
- **Identifier** -- names a module-level string constant declared in the
  enclosing module; the constant's value is used as the library name.
  A compile error is raised if no such string constant exists.

```
public const LIB_MATH: string = "mathjs";

routine jsAdd(const a: float64; const b: float64): float64;
  external LIB_MATH name "JsAdd";
```

**Resolution rules** for the library name:

- `.js` -- JavaScript host import. The routine becomes a wasm import satisfied
  by the JS host layer bundled into the output `.html` file.
- `.wasm` -- WebAssembly module import. The module is merged into the output
  via wasm-merge.
- **Extensionless** -- the library search paths (set by `@addlibrarypath`) are
  probed for a `.js` file first, then `.wasm`.

> [!TIP]
> 💡 External JS modules must expose functions as properties of a `var`-declared
> object matching the wasm import module name. This survives esbuild minification.
> Bare function declarations get scoped away during minification.


### 🏷️ 10. Type Definitions

```
TypeDef         = RecordType | OverlayType | ArrayType
                | PointerType | SetType | ChoicesType | RoutineType | TypeExpr .

RecordType      = "record" [ "packed" ] [ "align" "(" integer ")" ]
                  [ "(" TypeExpr ")" ]
                  { FieldDecl | AnonOverlay } "end" .

OverlayType     = "overlay" { FieldDecl | AnonRecord } "end" .
AnonRecord      = "record" [ "packed" ] { FieldDecl | AnonOverlay } "end" ";" .
AnonOverlay     = "overlay" { FieldDecl | AnonRecord } "end" ";" .

FieldDecl       = ident ":" TypeExpr [ ":" integer ] ";" .

ArrayType       = "array" [ "[" ArrayBounds "]" ] "of" TypeExpr .
ArrayBounds     = Expression ".." Expression .

PointerType     = ( "ptr" | "^" ) [ "to" [ "const" ] TypeExpr ] .

SetType         = "set" [ "of" Expression [ ".." Expression ] ] .

ChoicesType     = "choices" "(" ChoicesValue { "," ChoicesValue } ")" .
ChoicesValue    = ident [ "=" Expression ] .

RoutineType     = "routine" [ FormalParams ] [ ":" TypeExpr ] .

TypeExpr        = QualIdent
                | PointerType
                | ArrayType
                | SetType .

QualIdent       = ident [ "." ident ] .
```

> [!NOTE]
> **Array bounds** are constant expressions (`array[0..N-1] of int32` is
> valid). `array of T` with no brackets is a dynamic array; `array[] of T`
> is not accepted. **Set** bounds are likewise expressions; `set of T` with a
> single expression names an element type or a single bound. **Qualified
> type names** are exactly `Module.Type` -- one qualifier. `^T` is an
> alternative spelling of `ptr to T`.

> [!NOTE]
> `choices` is used instead of `enum`,
> and `overlay` instead of `union`. Anonymous overlays and records can nest
> inside each other for data interop. Records support single inheritance
> via `record(BaseType)` syntax and bit fields via `fieldname: type : width`.


### 📋 11. Statements

```
StatementSeq    = { Statement } .

Statement       = Assignment | CallStmt | IfStmt | WhileStmt | ForStmt
                | RepeatStmt | BreakStmt | ContinueStmt
                | MatchStmt | ReturnStmt | GuardStmt | RaiseStmt
                | NewStmt | DisposeStmt
                | GetMemStmt | FreeMemStmt | ResizeMemStmt | SetLengthStmt
                | PrintStmt
                | AssertStmt | InlineVarDecl | ConditionalDirective .

InlineVarDecl   = "var" ident ":" TypeExpr [ "=" Expression ] ";" .

Assignment      = Designator ( ":=" | "+=" | "-=" | "*=" | "/=" ) Expression [ ";" ] .

CallStmt        = ( Designator | VarArgsAccess ) [ ";" ] .

IfStmt          = "if" Expression "then" StatementSeq [ "else" StatementSeq ] "end" [ ";" ] .

WhileStmt       = "while" Expression "do" StatementSeq "end" [ ";" ] .

ForStmt         = "for" ident ":=" Expression ( "to" | "downto" ) Expression
                  "do" StatementSeq "end" [ ";" ] .

RepeatStmt      = "repeat" StatementSeq "until" Expression [ ";" ] .

BreakStmt       = "break" [ ";" ] .
ContinueStmt    = "continue" [ ";" ] .

MatchStmt       = "match" Expression "of" { MatchArm } [ "else" StatementSeq ] "end" [ ";" ] .
MatchArm        = MatchLabel { "," MatchLabel } ":" StatementSeq .
MatchLabel      = Expression [ ".." Expression ] .

ReturnStmt      = "return" [ Expression ] [ ";" ] .

GuardStmt       = "guard" StatementSeq
                  ( "except" StatementSeq [ "finally" StatementSeq ]
                  | "finally" StatementSeq ) "end" [ ";" ] .

RaiseStmt       = ( "throw" "(" Expression ")"
                  | "throwcode" "(" Expression "," Expression ")" ) [ ";" ] .

NewStmt         = "new" "(" Expression ")" [ ";" ] .
DisposeStmt     = "dispose" "(" Expression ")" [ ";" ] .
GetMemStmt      = "getmem" "(" Expression ")" [ ";" ] .
FreeMemStmt     = "freemem" "(" Expression ")" [ ";" ] .
ResizeMemStmt   = "resizemem" "(" Expression "," Expression ")" [ ";" ] .
SetLengthStmt   = "setlength" "(" Expression "," Expression ")" [ ";" ] .
PrintStmt       = ( "print" | "println" ) "(" cstring { "," Expression } ")" [ ";" ] .
```

> [!NOTE]
> **Empty statements.** A stray `;` where a statement is expected is a
> parse error (PAR006); the only place a bare `;` is tolerated is between
> `match` arms.

> [!NOTE]
> **`print`/`println` are printf-style.** The first argument is a format
> string literal; the remaining arguments are consumed by its `%` specs
> (`%d %u %x %X %f %.Nf %s %c %lld %%`). The same spec set is used by the
> `format` intrinsic (Section 13).

> [!NOTE]
> `break` and `continue` are valid only inside a `while`, `for`, or `repeat`
> body (compile error otherwise). `break` exits the innermost loop;
> `continue` starts its next iteration. In a `for` loop, `continue` still
> performs the iterator step before re-testing the bound.

> [!NOTE]
> **`while` loops have no `begin`.** The syntax is `while <expr> do <stmts> end` --
> the `do` keyword opens the body and `end` closes it. No `begin` is used.

#### 🧪 Assert Statements (Unit Testing)

Assert statements are available in all code but are primarily used inside test blocks.
All assertions continue after failure -- failures accumulate and are reported per test.
The compiler handles all test infrastructure automatically. When `@unittestmode on;` is active, test blocks are compiled, registered, and executed by the built-in test runner.
The compiler injects source file and line number automatically.

```
AssertStmt      = ( "assert" "(" Expression ")"
                  | "asserttrue" "(" Expression ")"
                  | "assertfalse" "(" Expression ")"
                  | "asserteq" "(" Expression "," Expression ")"
                  | "asserteqf" "(" Expression "," Expression "," Expression ")"
                  | "assertnil" "(" Expression ")"
                  | "assertnotnil" "(" Expression ")"
                  | "assertfail" "(" Expression ")" ) [ ";" ] .
```

- `assert(expr)` -- Fails if `expr` is false.
- `asserttrue(expr)` -- Fails if `expr` is not true.
- `assertfalse(expr)` -- Fails if `expr` is not false.
- `asserteq(expected, actual)` -- Fails if values are not equal. Type-dispatched: the compiler selects the appropriate comparison (int, uint, float, string, bool, ptr) based on operand types.
- `asserteqf(expected, actual, epsilon)` -- Float equality within a tolerance. Fails if `|expected - actual| > epsilon`. All three operands must be `float32` or `float64`; a non-float operand is a compile error, not an implicit conversion.
- `assertnil(expr)` -- Fails if `expr` is not nil.
- `assertnotnil(expr)` -- Fails if `expr` is nil.
- `assertfail("message")` -- Unconditional failure with a message.


### 🧮 12. Expressions

```
Expression      = SimpleExpr { RelOp SimpleExpr } .
RelOp           = "=" | "<>" | "<" | ">" | "<=" | ">=" | "in" .

SimpleExpr      = [ "+" | "-" ] Term { AddOp Term } .
AddOp           = "+" | "-" | "or" | "xor" .

Term            = Factor { MulOp Factor } .
MulOp           = "*" | "/" | "div" | "mod" | "and" | "shl" | "shr" .

Factor          = "not" Factor | "-" Factor | "+" Factor
                | "address" "of" Factor | Primary .

Primary         = integer | float_literal | cstring | wstring
                | "true" | "false" | "nil"
                | SetLiteral | RecordLiteral
                | "(" Expression ")" { Selector }
                | Designator | Intrinsic | VarArgsAccess
                | TypeCast { Selector }
                | primitive .

Designator      = ident { Selector } .
Selector        = "." ident | "[" Expression "]" | "^" | "(" [ ArgList ] ")" .

ArgList         = Expression { "," Expression } .

SetLiteral      = "[" [ SetElement { "," SetElement } ] "]" .
SetElement      = Expression [ ".." Expression ] .

RecordLiteral   = ident "(" FieldInit { "," FieldInit } ")" .
FieldInit       = ident ":" Expression .

TypeCast        = primitive "(" Expression ")" .
```

> [!NOTE]
> **Operators are left-associative at every level**, relational included:
> `a < b = c` parses as `(a < b) = c`. **Type casts** use a built-in type
> keyword only (`int32(x)`, `float64(n)`); `Name(x)` with a user type name
> is a call. A bare built-in type name is a valid Primary so that
> `size(int32)` works. Selectors may follow a parenthesized expression or a
> cast: `(p^).x`, `int32(v)^`.

#### 📍 Pointer Operations

- `address of expr` -- Returns a pointer to the operand.
- `expr^` -- Postfix (selector): dereference. Follows the pointer to its target.


### ⚡ 13. Intrinsics

```
Intrinsic       = LenExpr | SizeExpr | Utf8Expr | CStrExpr | WStrExpr
                | ParamCountExpr | ParamStrExpr | ExcCodeExpr | ExcMsgExpr
                | FormatExpr .

LenExpr         = "len" "(" Expression ")" .
SizeExpr        = "size" "(" ( TypeExpr | Expression ) ")" .
Utf8Expr        = "utf8" "(" Expression ")" .
CStrExpr        = "cstr" "(" Expression ")" .
WStrExpr        = "wstr" "(" Expression ")" .
ParamCountExpr  = "paramcount" "(" ")" .
ParamStrExpr    = "paramstr" "(" Expression ")" .
ExcCodeExpr     = "exccode" "(" ")" .
ExcMsgExpr      = "excmsg" "(" ")" .
FormatExpr      = "format" "(" cstring { "," Expression } ")" .
```

> [!NOTE]
> `format(fmt, ...)` builds a managed `string` from a printf-style format
> literal and its arguments, using the same `%` specs as `print`/`println`
> (Section 11). The format string must be a string literal. Calls nest
> freely: `format("%s!", format("%d", n))`.

> [!NOTE]
> `len` returns the length of strings, wide strings, and dynamic arrays.
> `size` returns the byte size of a type or expression. `utf8` converts a
> string to a newly allocated, raw UTF-8 buffer (`char*`) -- NOT a managed
> string; the buffer is owned by the caller. `cstr` returns a BORROWED raw
> UTF-8 `char*` pointing into an existing managed string's own storage -- it
> allocates nothing and must never be freed, and the pointer is valid only
> while the owning string is alive. `wstr` is the UTF-16 counterpart of
> `cstr`: it returns a BORROWED `wchar*` that the runtime widens once and
> CACHES on the string itself, so repeat calls are free and the buffer must
> never be freed by the caller. Memory management (`new`/`dispose`/`getmem`/
> `freemem`/`resizemem`/`setlength`) is defined in Statements (Section 11).


### 🧺 14. Variadic Arguments

```
ParamList       = ParamDecl { ";" ParamDecl } [ ";" "..." ] | "..." .

VarArgsAccess   = "varargs" "." "next" "(" TypeExpr ")"
                | "varargs" "." "get" "(" Expression "," TypeExpr ")"
                | "varargs" "." "reset" "(" ")"
                | "varargs" "." "copy" "(" ")"
                | "varargs" "." "count" .
```

- `varargs.next(TypeExpr)` -- Retrieves and consumes the next variadic argument. Result type is `TypeExpr`.
- `varargs.get(Expression, TypeExpr)` -- Retrieves the argument at the given zero-based index without advancing the cursor.
- `varargs.reset()` -- Resets the cursor back to the first argument.
- `varargs.count` -- Total number of variadic arguments passed (`int32`).
- `varargs.copy()` -- Returns a new `varargs` value: an independent copy of the pack including its cursor position. Assign it to a local of type `varargs`; it is released automatically when the routine exits.

> [!IMPORTANT]
> **Semantics.**
> - `...` is the only variadic marker and must be the last entry in the
>   parameter list. `varargs.*` is valid only inside a routine declared with
>   `...` (error SEM013 elsewhere).
> - Every packed argument carries its static type. A bare integer literal
>   packs as `int32`, or as `int64` when it does not fit in 32 bits; a float
>   literal packs as `float64`; a string literal packs as `string`.
> - `next(T)` and `get(i, T)` verify at runtime that the stored type is `T`
>   and that `i` is in range. A mismatch raises a runtime exception
>   (code 900 for type, 901 for index) with a descriptive message; there is
>   no C-style untyped access.
> - The pack is owned by the caller and released when the calling statement
>   completes. Strings inside the pack are reference-counted through it.

```
routine sum(...): int32;
var
  i: int32;
  total: int32;
begin
  total := 0;
  for i := 0 to varargs.count - 1 do
    total += varargs.next(int32);
  end;
  return total;
end;

// sum(1, 2, 3) = 6
```


### 🧪 15. Unit Testing

Test blocks appear after the module's `end.` and are only compiled when the
`@unittestmode on;` directive is active. When `@unittestmode on;` is active:

1. The compiler parses test blocks after `end.`
2. Each test block is compiled as a parameterless routine
3. The normal entry point is replaced with the built-in test runner

```
TestBlock     = "test" cstring [ "var" { VarDecl } ]
                "begin" StatementSeq "end" ";" .
```

#### Example

```
module exe mathlib;

@unittestmode on;

routine add(const a: int32; const b: int32): int32;
begin
  return a + b;
end;

routine mul(const a: int32; const b: int32): int32;
begin
  return a * b;
end;

initialize
  println("Module initialized");
end;

finalize
  println("Module finalized");
end;

end.

test "add returns correct sum"
var
  result: int32;
begin
  result := add(2, 3);
  asserteq(5, result);
end;

test "add handles negative numbers"
begin
  asserteq(-2, add(-5, 3));
  asserteq(-8, add(-5, -3));
end;

test "mul returns correct product"
begin
  asserteq(20, mul(4, 5));
  asserteq(0, mul(0, 100));
end;
```


### 🎚️ 16. Operator Precedence (Highest to Lowest)

| Precedence | Operators                                        |
|------------|--------------------------------------------------|
| 1 (highest)| `not` `-` (unary) `+` (unary) `address of`      |
| 2          | `*` `/` `div` `mod` `and` `shl` `shr`           |
| 3          | `+` `-` `or` `xor`                               |
| 4 (lowest) | `=` `<>` `<` `>` `<=` `>=` `in`                  |


### 🎯 17. Output Model

Waskal compiles source to a single `.html` file that runs in any modern browser
supporting wasm64 (memory64). The HTML file is fully self-contained:

1. **JS host layer** -- all JavaScript combined into one minified block:
   - WASI64 shim (built-in, always included) -- console I/O, files, clock, random
   - Built-in host APIs (opt-in) -- graphics, audio, input helpers
   - User JS libs -- any `.js` files declared via `external` clauses and
     resolved through `@addlibrarypath`
2. **Wasm64 binary** -- base64-encoded, decoded and instantiated at runtime
3. **HTML shell** -- minimal page structure, wires JS host to wasm imports

No external dependencies. No network requests. Runs from `file://` or any server.
Double-click to run.

> [!TIP]
> 💡 The wasm module declares imports that the JS host layer satisfies:
> `wasi_snapshot_preview1.*` for WASI calls (fd_write, clock_time_get, etc.)
> and custom namespaces for graphics, audio, input, or user-defined host functions.


### 🧪 Grammar Validation Checklist

Use this checklist when updating the grammar or adding syntax:

- 🔤 Lexical rules define the token shape before parser rules depend on it
- 🚫 Reserved words are listed before examples rely on them
- 🧱 New type forms appear in both the type grammar and any reference sections
- 🔧 New routine syntax is reflected in declarations, statements, and examples where applicable
- 🧮 Operator changes update precedence and expression grammar together
- 🧪 Unit-test syntax matches the assertion helper documentation
- 🧭 Any new directive is added to the known directive table and the conditional compilation section

> [!WARNING]
> 🧯 Keep grammar changes synchronized with examples. A grammar rule that accepts syntax not shown anywhere else is hard for users to discover, and an example that violates the grammar is worse than no example at all.

<a id="standard-library"></a>

## 📦 7. Standard Library

*Six browser-API modules ship with Waskal -- import one, call its routines, and the compiler wires everything into the final `.html` for you.*

Waskal programs run in the browser, and the browser already has a canvas, an audio mixer, a gamepad API, and persistent storage. The standard library is a set of thin Waskal wrappers over these APIs. Each module is a `module unit` backed by a JavaScript shim; the two are paired so that `import canvas2d;` gives you the full HTML5 Canvas 2D surface with no configuration. Modules couple only through documented hook slots on the shared `WKL` object in runtime.js -- they never reference each other's globals.

Every extern in every std module follows the marshalling contract described in [JavaScript Interop](#js-interop): geometry and time are `float64`, counts and handles are `int32`, strings cross as `ptr to char`, JS objects live in the `WKL.handles` table as `int32` aliases, and nothing ever passes `int64` to a DOM API.


### 🎞️ frame -- Game Loop

*A fixed-step update loop driven by the browser's `requestAnimationFrame`.*

After `_start` returns, the browser owns the execution loop. `frame.Run` registers your Update, Render, and Shutdown callbacks, then hands control to `requestAnimationFrame`. Update runs at a fixed time step (default 60 Hz) so physics and movement are frame-rate-independent. Render runs once per display refresh. When the loop ends -- via `frame.Stop`, a trap, or the page closing -- the runtime calls `_shutdown` from a clean stack.

```wkl
// frame_loop.wkl -- fixed-step update + render (trimmed)
module exe frame_loop;

import canvas2d;
import frame;

var
  x: float64;

routine Update(const dt: float64);
begin
  x := x + 120.0 * dt;
  if x > 800.0 then
    x := 0.0;
  end;
end;

routine Render();
begin
  canvas2d.SetFillStyle("#000");
  canvas2d.FillRect(0.0, 0.0, 800.0, 600.0);
  canvas2d.SetFillStyle("#0f0");
  canvas2d.FillRect(x, 280.0, 40.0, 40.0);
end;

begin
  canvas2d.Init(800, 600);
  frame.Run(Update, Render, nil);
end.
```

Any handler may be `nil` -- pass `nil` for Render if you only need the update tick, or `nil` for Shutdown if you have no teardown.

#### Types

| Type | Definition |
|------|------------|
| `UpdateProc` | `routine(const dt: float64)` -- fixed step, called 0..N times per tick |
| `RenderProc` | `routine()` -- once per display refresh |
| `ShutdownProc` | `routine()` -- called once when the loop ends |

#### Routines

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `Run` | `(const update: UpdateProc; const render: RenderProc; const shutdown: ShutdownProc)` | Start the loop. Any handler may be `nil`. |
| `SetTargetFPS` | `(const fps: float64)` | Fixed update rate (default 60). `dt` = 1 / fps. |
| `Stop` | `()` | End the loop after the current tick. |
| `IsRunning` | `(): bool` | True while the loop is active. |
| `Time` | `(): float64` | Wall-clock seconds since loop start. |
| `FPS` | `(): float64` | Current frames per second. |

> [!TIP]
> **`_start` returns immediately.** Unlike a native program, the Waskal entry point sets up state and calls `frame.Run`, then returns. The browser's animation loop takes over. This is the normal lifecycle for any graphical Waskal program.


### 🖼️ canvas2d -- 2D Drawing

*The full HTML5 Canvas 2D API, DPI-aware, with convenience wrappers for common shapes.*

`canvas2d.Init(w, h)` creates a canvas at the given logical size. The backing store is scaled by `devicePixelRatio` automatically -- you work in CSS pixels and the output is sharp on every display. Colours, fonts, and enum-like properties are CSS strings; the module provides named constants so you never write a magic string.

```wkl
// house.wkl -- static 2D drawing (trimmed)
module exe house;

import canvas2d;

begin
  canvas2d.Init(800, 600);
  canvas2d.Clear(100, 149, 237);          // sky
  canvas2d.Rect(0, 400, 800, 200, 34, 139, 34);  // ground
  canvas2d.Rect(250, 250, 200, 150, 178, 102, 51); // house
  canvas2d.Circle(650, 100, 60, 255, 223, 0);      // sun
  println("Canvas demo rendered.");
end.
```

#### Types

| Type | Kind | Purpose |
|------|------|---------|
| `Gradient` | `int32` handle | JS `CanvasGradient`; release with `GradientRelease` |
| `Pattern` | `int32` handle | JS `CanvasPattern`; release with `PatternRelease` |
| `Path` | `int32` handle | JS `Path2D`; release with `PathRelease` |
| `ImageData` | `int32` handle | JS `ImageData`; release with `ImageDataRelease` |
| `TextMetrics` | record, 12 × `float64` | Width, bounding boxes, baselines |
| `Matrix` | record, 6 × `float64` | DOMMatrix fields a..f |

#### Constants

All are `string` constants matching CSS values. Use them with the corresponding Set* routines.

| Group | Count | Examples |
|-------|-------|---------|
| Line cap | 3 | `LINE_CAP_BUTT`, `LINE_CAP_ROUND`, `LINE_CAP_SQUARE` |
| Line join | 3 | `LINE_JOIN_MITER`, `LINE_JOIN_ROUND`, `LINE_JOIN_BEVEL` |
| Fill rule | 2 | `FILL_RULE_NON_ZERO`, `FILL_RULE_EVEN_ODD` |
| Text align | 5 | `TEXT_ALIGN_START` .. `TEXT_ALIGN_CENTER` |
| Text baseline | 6 | `BASELINE_TOP` .. `BASELINE_BOTTOM` |
| Direction | 3 | `DIRECTION_LTR`, `DIRECTION_RTL`, `DIRECTION_INHERIT` |
| Font kerning | 3 | `KERNING_AUTO`, `KERNING_NORMAL`, `KERNING_NONE` |
| Font stretch | 9 | `STRETCH_ULTRA_CONDENSED` .. `STRETCH_ULTRA_EXPANDED` |
| Font variant caps | 7 | `VARIANT_CAPS_NORMAL` .. `VARIANT_CAPS_TITLING` |
| Text rendering | 4 | `RENDERING_AUTO` .. `RENDERING_GEOMETRIC_PRECISION` |
| Placement | 4 | `PLACE_FLOW`, `PLACE_CENTER`, `PLACE_FILL`, `PLACE_WINDOW` |
| Smoothing quality | 3 | `SMOOTHING_LOW`, `SMOOTHING_MEDIUM`, `SMOOTHING_HIGH` |
| Composite operation | 26 | `COMPOSITE_SOURCE_OVER` .. `COMPOSITE_LUMINOSITY` |

#### Routines by Category

**Setup and canvas element**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `Init` | `(const w: int32; const h: int32)` | Create a canvas at logical size |
| `InitOn` | `(const id: ptr to char; const w: int32; const h: int32): bool` | Attach to an existing DOM element |
| `Resize` | `(const w: int32; const h: int32)` | Resize the canvas |
| `Width` / `Height` | `(): int32` | Logical canvas size |
| `ViewportWidth` / `ViewportHeight` | `(): int32` | Browser window inner size |
| `SetBackground` | `(const css: ptr to char)` | Page background colour |
| `SetPlacement` | `(const mode: ptr to char)` | `PLACE_FLOW` / `CENTER` / `FILL` / `WINDOW` |

**State:** `Save`, `Restore`, `Reset`

**Rectangles:** `ClearRect`, `FillRect`, `StrokeRect` -- all `(x, y, w, h: float64)`

**Path building:** `BeginPath`, `ClosePath`, `MoveTo`, `LineTo`, `Arc`, `ArcTo`, `BezierCurveTo`, `QuadraticCurveTo`, `Ellipse`, `PathRect`, `RoundRect`, `RoundRect4`

**Path drawing:** `Fill`, `FillRule`, `Stroke`, `Clip`, `ClipRule`, plus Path2D variants (`FillPath`, `StrokePath`, `ClipPath`) and hit-testing (`IsPointInPath`, `IsPointInStroke`)

**Path2D objects:** `PathCreate`, `PathCreateSVG`, `PathRelease`, `PathMoveTo`, `PathLineTo`, `PathArc`, `PathArcTo`, `PathBezierCurveTo`, `PathQuadraticCurveTo`, `PathEllipse`, `PathAddRect`, `PathRoundRect`, `PathClosePath`, `PathAddPath`

**Line styles:** `SetLineWidth`, `GetLineWidth`, `SetLineCap`, `SetLineJoin`, `SetMiterLimit`, `SetLineDash`, `SetLineDashOffset`

**Fill and stroke style:** `SetFillStyle`, `SetStrokeStyle`, `SetFillRGB`, `SetStrokeRGB`, `SetFillGradient`, `SetStrokeGradient`, `SetFillPattern`, `SetStrokePattern`

**Gradients and patterns:** `CreateLinearGradient`, `CreateRadialGradient`, `CreateConicGradient`, `AddColorStop`, `CreatePattern`, `GradientRelease`, `PatternRelease`

**Compositing:** `SetGlobalAlpha`, `GetGlobalAlpha`, `SetGlobalCompositeOperation`, `SetFilter`

**Shadows:** `SetShadowColor`, `SetShadowBlur`, `SetShadowOffsetX`, `SetShadowOffsetY`

**Text:** `SetFont`, `SetTextAlign`, `SetTextBaseline`, `SetDirection`, `SetLetterSpacing`, `SetWordSpacing`, `SetFontKerning`, `SetFontStretch`, `SetTextRendering`, `SetFontVariantCaps`, `FillText`, `FillTextMax`, `StrokeText`, `StrokeTextMax`, `MeasureTextWidth`, `FillTextLines`, `StrokeTextLines`, `FillTextWrapped`, `StrokeTextWrapped`, `LoadFont`, `FontsReady`

**Transforms:** `Translate`, `Rotate`, `Scale`, `Transform`, `SetTransform`, `ResetTransform`

**Images:** `DrawImageAt`, `DrawImageSize`, `DrawImageRect`, `SetImageSmoothingEnabled`, `SetImageSmoothingQuality`, `ImageWidth`, `ImageHeight`

**Pixel data (ImageData):** `CreateImageData`, `GetImageData`, `ImageDataWidth`, `ImageDataHeight`, `ImageDataRead`, `ImageDataWrite`, `PutImageData`, `PutImageDataDirty`, `ImageDataRelease`

**Convenience wrappers:** `Clear(r, g, b)`, `Rect(x, y, w, h, r, g, b)`, `Circle(x, y, radius, r, g, b)`, `Line(x1, y1, x2, y2, r, g, b, width)`, `DrawImage(asset, x, y, w, h)`, `MeasureText(text, var m)`, `GetTransform(var m)`, `ToDataURL(mime): string`, plus ten text-property getters (`GetFont` .. `GetTextRendering`)

> [!NOTE]
> **Placement modes.** `PLACE_FLOW` (default) puts the canvas in the page flow alongside the developer console. `PLACE_CENTER` centres it at a fixed size (splash screens). `PLACE_FILL` letterboxes to the window at the logical resolution (games). `PLACE_WINDOW` makes the logical size follow the window (apps, dashboards). See `examples/responsive_canvas.wkl` for a PLACE_WINDOW demo.

> [!WARNING]
> **SetFilter and DPI.** `SetFilter` passes the CSS filter string verbatim to the canvas context. Length values like `blur(5px)` are not adjusted for `devicePixelRatio`, so the visual radius will differ between standard and high-DPI displays.


### 🎮 input -- Keyboard, Mouse, and Gamepad

*Snapshotted once per tick: Down (held), Pressed (just went down), Released (just went up).*

The input module reads keyboard, mouse, and gamepad state. State is snapshotted at the top of every frame tick (via the `WKL.onTick` hook) so it is consistent for the entire Update call. Keys are physical USB HID codes -- layout-independent. Mouse position is in canvas pixels and requires `canvas2d.Init`. Gamepads use the standard mapping with a configurable radial deadzone on sticks.

```wkl
// input_square.wkl -- keyboard + mouse input (trimmed)
module exe input_square;

import canvas2d;
import frame;
import input;

const
  SPEED = 200.0;

var
  x: float64;
  y: float64;

routine Update(const dt: float64);
begin
  if input.KeyDown(input.KEY_LEFT) then
    x := x - SPEED * dt;
  end;
  if input.KeyDown(input.KEY_RIGHT) then
    x := x + SPEED * dt;
  end;
  if input.MousePressed(input.MOUSE_LEFT) then
    x := input.MouseX();
    y := input.MouseY();
  end;
  if input.KeyPressed(input.KEY_ESCAPE) then
    frame.Stop();
  end;
end;
```

#### Constants

| Group | Count | Notes |
|-------|-------|-------|
| `KEY_*` | 62 | USB HID usage codes (page 0x07). `KEY_A`..`KEY_Z`, `KEY_0`..`KEY_9`, arrow keys, F1..F12, modifiers, navigation, numpad. |
| `MOUSE_*` | 5 | `MOUSE_LEFT`, `MOUSE_MIDDLE`, `MOUSE_RIGHT`, `MOUSE_BACK`, `MOUSE_FORWARD` |
| `PAD_*` | 17 | Standard gamepad buttons: `PAD_A`/`B`/`X`/`Y`, bumpers, triggers, sticks, d-pad, guide |
| `AXIS_*` | 4 | `AXIS_LEFT_X`, `AXIS_LEFT_Y`, `AXIS_RIGHT_X`, `AXIS_RIGHT_Y` |

#### Routines

**Keyboard**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `KeyDown` | `(const key: int32): bool` | Held during this tick |
| `KeyPressed` | `(const key: int32): bool` | Went down since previous tick |
| `KeyReleased` | `(const key: int32): bool` | Went up since previous tick |
| `AnyKeyPressed` | `(): bool` | Any key went down |

**Mouse**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `MouseDown` / `MousePressed` / `MouseReleased` | `(const button: int32): bool` | Button state |
| `MouseX` / `MouseY` | `(): float64` | Canvas-pixel position |
| `MouseDeltaX` / `MouseDeltaY` | `(): float64` | Movement since previous tick |
| `MouseWheel` | `(): float64` | Scroll amount (positive = down) |

**Gamepad**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `GamepadConnected` | `(const pad: int32): bool` | Gamepad 0..3 present |
| `GamepadDown` / `GamepadPressed` / `GamepadReleased` | `(const pad: int32; const button: int32): bool` | Button state |
| `GamepadButtonValue` | `(const pad: int32; const button: int32): float64` | 0..1 (analog triggers) |
| `GamepadAxis` | `(const pad: int32; const axis: int32): float64` | -1..1 with deadzone |
| `GamepadAxisRaw` | `(const pad: int32; const axis: int32): float64` | -1..1 raw |
| `SetDeadzone` | `(const dz: float64)` | Radial deadzone for sticks |

> [!TIP]
> **Input needs both frame and canvas2d.** State is snapshotted by `WKL.onTick`, which frame.js fires at the top of every tick. Mouse coordinates are mapped through `WKL.canvas`, which `canvas2d.Init` sets. Without both, input routines return stale or zero values.


### 🔊 audio -- Sound Effects and Music

*Decoded sound effects with per-voice control, plus one streamed music track at a time.*

Sounds are short audio clips loaded from embedded `@asset` files and fully decoded into memory. Each `Play` starts a Voice -- an active instance you can stop, pan, or pitch-shift independently. Multiple Voices can play the same Sound simultaneously. Music is a single streamed track (one at a time) with transport controls and a fade function. Three gain buses -- master, sfx, and music -- let you mix volumes globally.

```wkl
// audio_player.wkl -- loading and playing audio (trimmed)
module exe audio_player;

import canvas2d, frame, input, audio;

@assets "$P:res/assets/audio" "assets" "*.ogg";

var
  sfx: audio.Sound;
  song: audio.Music;

begin
  canvas2d.Init(800, 600);
  sfx := audio.LoadSound("assets/audio/sfx/samp0.ogg");
  song := audio.LoadMusic("assets/audio/music/song01.ogg");
  frame.Run(Update, Render, nil);
end.
```

The full example (`examples/audio_player.wkl`) plays sfx on key presses, toggles a looping engine voice with Space, and streams music with M/P/F controls.

#### Types

| Type | Kind | Purpose |
|------|------|---------|
| `Sound` | `int32` handle | Decoded audio buffer; 0 = none |
| `Voice` | `int32` handle | Active playing instance; 0 = none |
| `Music` | `int32` handle | Streamed track; 0 = none |

#### Routines

**Context**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `Unlock` | `(): bool` | Resume audio context; true when running |
| `IsReady` | `(): bool` | All LoadSound decodes finished |

**Sounds (sfx)**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `LoadSound` | `(const asset: ptr to char): Sound` | Load from `@asset` name; 0 if missing |
| `ReleaseSound` | `(const s: Sound)` | Free the decoded buffer |
| `Play` | `(const s: Sound): Voice` | Play at default settings (vol 1, pitch 1, centre pan, no loop) |
| `PlayEx` | `(const s: Sound; const volume: float64; const pitch: float64; const pan: float64; const loop: bool): Voice` | Full control |
| `StopVoice` | `(const v: Voice)` | Stop a playing instance |
| `SetVoiceVolume` | `(const v: Voice; const volume: float64)` | |
| `SetVoicePan` | `(const v: Voice; const pan: float64)` | -1 (left) .. 1 (right) |
| `SetVoicePitch` | `(const v: Voice; const pitch: float64)` | Playback rate; 1.0 = normal |
| `IsVoicePlaying` | `(const v: Voice): bool` | False once ended or stopped |
| `StopAllSounds` | `()` | Stop every active Voice |

**Music**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `LoadMusic` | `(const asset: ptr to char): Music` | Streamed from `@asset`; 0 if missing |
| `ReleaseMusic` | `(const m: Music)` | |
| `PlayMusic` | `(const m: Music; const loop: bool)` | Start from beginning; stops the current track |
| `StopMusic` / `PauseMusic` / `ResumeMusic` | `()` | Transport controls |
| `IsMusicPlaying` | `(): bool` | |
| `MusicPosition` / `MusicDuration` | `(): float64` | Seconds; duration is 0 until the browser knows |
| `SeekMusic` | `(const seconds: float64)` | |
| `FadeMusic` | `(const toVolume: float64; const seconds: float64)` | Ramp the music bus |

**Buses**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `SetMasterVolume` / `GetMasterVolume` | `(volume: float64)` / `(): float64` | 0..1 |
| `SetSfxVolume` / `GetSfxVolume` | same | |
| `SetMusicVolume` / `GetMusicVolume` | same | |

> [!NOTE]
> **Autoplay policy.** Browsers refuse to play sound before the first user gesture (click, key press, tap). `Play` returns 0 and `PlayMusic` queues silently until the context unlocks. No error is raised -- the sound simply starts once the user interacts. Poll `Unlock()` if you need to know when audio is live.


### 🎬 video -- Video Playback

*Load an embedded or external video, then draw it onto the canvas or show it as a page element.*

The video module wraps `HTMLVideoElement`. Load a clip from an embedded `@asset` (.mp4 or .webm) or an external URL, then choose one of two rendering modes: **Draw** paints the current frame onto the canvas2d surface every render tick (composited with your own drawing), or **Show** places the video element itself in the page using the same `PLACE_*` modes as canvas2d. Embedded assets grow the .html by roughly 1.35× their file size (base64 overhead).

```wkl
// video_player.wkl -- loading and playing video (trimmed)
module exe video_player;

import canvas2d, frame, input, video;

@asset "$P:res/assets/video/intro.mp4" "assets/video";

var
  clip: video.Video;

begin
  canvas2d.Init(960, 600);
  clip := video.Load("assets/video/intro.mp4");
  video.Play(clip);
  frame.Run(Update, Render, nil);
end.
```

In the render callback, either `video.Draw(clip, x, y, w, h)` to composite on your canvas, or `video.Show(clip, video.PLACE_CENTER)` to show the element itself.

#### Types and Constants

| Name | Kind | Purpose |
|------|------|---------|
| `Video` | `int32` handle | HTMLVideoElement; 0 = none |
| `PLACE_FLOW` / `PLACE_CENTER` / `PLACE_FILL` / `PLACE_WINDOW` | `string` | Same placement modes as canvas2d |

#### Routines

**Lifetime**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `Load` | `(const asset: ptr to char): Video` | Load from `@asset` name; 0 if missing |
| `LoadURL` | `(const url: ptr to char): Video` | External URL (canvas drawing needs CORS) |
| `Release` | `(const v: Video)` | Free the handle |

**Transport**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `Play` / `Pause` / `Stop` | `(const v: Video)` | Stop pauses and rewinds to 0 |
| `Seek` | `(const v: Video; const seconds: float64)` | |
| `SetVolume` | `(const v: Video; const volume: float64)` | 0..1 |
| `SetLoop` / `SetMuted` | `(const v: Video; const value: bool)` | |
| `SetPlaybackRate` | `(const v: Video; const rate: float64)` | 1.0 = normal |

**State**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `IsReady` | `(const v: Video): bool` | Metadata loaded, frames available |
| `IsPlaying` / `IsEnded` / `IsMuted` | `(const v: Video): bool` | |
| `Position` / `Duration` | `(const v: Video): float64` | Seconds; duration is 0 until metadata loads |
| `Width` / `Height` | `(const v: Video): int32` | 0 until metadata loads |

**Rendering**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `Draw` | `(v: Video; dx, dy, dw, dh: float64)` | Paint current frame onto canvas2d |
| `DrawRect` | `(v: Video; sx, sy, sw, sh, dx, dy, dw, dh: float64)` | Source rect to dest rect |
| `Show` | `(const v: Video; const mode: ptr to char)` | Place the element in the page |
| `Hide` | `(const v: Video)` | Remove the element |

> [!NOTE]
> **Autoplay policy.** The same browser restriction as audio applies. Muted playback starts immediately; unmuted playback queues until the first user gesture.


### 💾 localstorage -- Persistent Storage

*Key-value persistence backed by `window.localStorage`, scoped to your app.*

The localstorage module provides simple string and typed key-value storage that survives page reloads. Keys are automatically prefixed with the module name, so multiple Waskal programs served from the same origin (or the same `file://` folder) never collide. Nothing raises -- a missing key returns your default, a failed write returns `false`.

```wkl
// run_counter.wkl -- persistent run counter (trimmed)
module exe run_counter;

import localstorage;

var runs: int64;

begin
  runs := localstorage.GetInt("runs", 0) + 1;
  localstorage.SetInt("runs", runs);
  println("runs = %lld (reload to increment)", runs);
end.
```

#### Routines

**Core**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `Available` | `(): bool` | Probes localStorage with a throwaway key |
| `SetItem` | `(const key: ptr to char; const value: ptr to char): bool` | False on quota or security error |
| `GetItem` | `(const key: string; const default: string): string` | Returns `default` if key missing |
| `RemoveItem` | `(const key: ptr to char)` | |
| `Clear` | `()` | Removes only this app's prefixed keys |
| `Length` | `(): int32` | Count of this app's keys |
| `Key` | `(const index: int32): string` | Empty string if out of range |
| `HasItem` | `(const key: ptr to char): bool` | |

**Typed helpers**

| Routine | Signature | Purpose |
|---------|-----------|---------|
| `SetInt` / `GetInt` | `(key: ptr to char; value/default: int64): bool / int64` | Shim converts to/from text |
| `SetFloat` / `GetFloat` | `(key: ptr to char; value/default: float64): bool / float64` | |
| `SetBool` / `GetBool` | `(key: ptr to char; value/default: bool): bool / bool` | |

> [!TIP]
> **Isolation on `file://`.** Because keys are prefixed with the module name, two different Waskal programs opened from local files never see each other's data -- even though `file://` shares a single localStorage origin in most browsers.


### 🔗 Cross-Module Dependencies

No std module imports another. All coupling flows through documented hook slots on the `WKL` object in runtime.js.

| Module | Depends on (via WKL) | Notes |
|--------|----------------------|-------|
| frame | -- | Sets `WKL.onLoopEnd` |
| canvas2d | -- | Sets `WKL.canvas` |
| input | frame, canvas2d | Snapshot via `WKL.onTick` (frame); mouse coords via `WKL.canvas` (canvas2d) |
| audio | -- | Standalone |
| video | canvas2d (Draw mode) | Show mode is standalone |
| localstorage | -- | Reads `WKL.moduleName` for key prefix |


### 📋 Example-to-Module Map

| Example | Modules | What it demonstrates |
|---------|---------|----------------------|
| `hello.wkl` | (none) | Console output only |
| `frame_loop.wkl` | canvas2d, frame | Basic game loop |
| `house.wkl` | canvas2d | Static shape drawing |
| `canvas2d_tour.wkl` | canvas2d | Canvas API showcase |
| `embedded_image.wkl` | canvas2d | `@asset` image drawn on canvas |
| `text_rendering.wkl` | canvas2d, frame, input | Fonts, wrapping, metrics |
| `responsive_canvas.wkl` | canvas2d, frame, input | `PLACE_WINDOW` responsive layout |
| `input_square.wkl` | canvas2d, frame, input | Keyboard + mouse demo |
| `particles.wkl` | canvas2d, frame, input | Particle system |
| `bouncing_squares.wkl` | canvas2d, frame, input, localstorage | Game with persistence |
| `audio_player.wkl` | canvas2d, frame, input, audio | Audio playback |
| `video_player.wkl` | canvas2d, frame, input, video | Video playback |
| `run_counter.wkl` | localstorage | Console-only persistence |

To build your own std-style module, see [JavaScript Interop](#js-interop) for the marshalling contract and shim authoring guide.

Next: [Runtime](#runtime-library)

<a id="runtime-library"></a>

## ⚙️ 8. Runtime

*Three files make every Waskal program run: a wasm runtime baked into the binary, a JavaScript host layer that bridges wasm to the browser, and an HTML template that wires them together.*

A Waskal `.html` is self-contained, but it is not magic. Inside it are three layers, each with a clear job. `runtime.wat` is hand-written WebAssembly that ships inside the wasm module itself -- heap allocation, strings, exceptions, console I/O, the test runner. `runtime.js` is the JavaScript side -- the WASI preview1 shim, the shared `WKL` helper object that every std module depends on, and the embedded asset decoder. `index.html` is the runner template that decodes the base64 wasm binary, feature-checks memory64, instantiates the module, and manages the startup-to-shutdown lifecycle. You never touch these files directly. The compiler's build pipeline (`Waskal.Build`) assembles them into the final artifact.


### 🧱 runtime.wat -- The Wasm Runtime

The emitter includes `runtime.wat` verbatim into every output module. Its functions are real wasm functions in the same module as your code -- not JS imports.

Internal dependency order:

```
heap -> memutils -> strings -> intrinsics -> lifecycle -> test runner
```

runtime.wat imports exactly four WASI preview1 functions:

| Import | Used by |
|--------|---------|
| `fd_write` | All console output (`print` / `println`) |
| `proc_exit` | `halt()` (abnormal termination) |
| `args_sizes_get` | Command-line argument init |
| `args_get` | Command-line argument init |

These are the only imports from `wasi_snapshot_preview1` that the runtime needs. All other browser API access goes through JS imports in custom namespaces (canvas2d, input, audio, etc.).

#### Function Table

```wat
(type $rt_void_func (func))
(type $rt_thunk_type (func (param i64)))
(table $rt_functable 256 funcref)
```

Slot 0 is reserved (`nil`). The emitter populates the table with `elem` declarations for routine references. A routine used as a value is its `int32` index in this table. Maximum 255 user routines per module.

#### Memory

```wat
(memory $mem i64 1)
(export "memory" (memory $mem))
```

One page (64 KB) initial, memory64 addressing (i64 pointers). The heap allocator grows the memory as needed via `memory.grow`. See [Memory](#memory-data-structures) for the allocator and string runtime details.


### 🌐 runtime.js -- The JavaScript Host

runtime.js is the JS-side runtime injected into every `.html`. It contains three subsystems.

#### The WKL Shared Object

`WKL` is the single namespace that every std module shim reads from and writes to. Modules never reference each other directly -- all coupling flows through these documented slots.

| Slot | Type | Set by | Read by |
|------|------|--------|---------|
| `moduleName` | string | index.html | std modules (localstorage key prefix, window title) |
| `onLoopEnd` | function \| null | index.html | frame.js (triggers `_shutdown` after the loop exits) |
| `onTick` | function \| null | input.js | frame.js (fired every tick before any wasm call) |
| `canvas` | HTMLCanvasElement \| null | canvas2d.Init | input.js (mouse coordinate mapping) |
| `canvasDpr` | number | canvas2d | input.js |
| `onExit` | callback array | std modules push | index.html (fired after `_shutdown`) |

Helper methods available to every shim:

| Method | Purpose |
|--------|---------|
| `readCStr(ptr)` | Read NUL-terminated UTF-8 from wasm memory at a BigInt address |
| `writeCStr(str, buf, size)` | Encode UTF-8 into wasm memory; returns full byte length as BigInt |
| `handles()` | Create a handle table (alloc / get / release; slot 0 = none) |
| `fail(e)` | Uniform error path -- `WASIProcExit` is a normal stop, anything else surfaces in the page |
| `runExit()` | Fire `onExit` callbacks, remove app-mode styling (restores the console area) |

#### The WASI Preview1 Shim

A full WASI preview1 implementation for memory64, forked from `@bjorn3/browser_wasi_shim` v0.4.2 (MIT OR Apache-2.0). All pointer and size parameters use BigInt (i64).

Key implemented calls:

| Category | Functions |
|----------|-----------|
| Args | `args_sizes_get`, `args_get` |
| Environ | `environ_sizes_get`, `environ_get` |
| Clock | `clock_time_get` (realtime + monotonic via `performance.now`) |
| File I/O | `fd_read`, `fd_write`, `fd_seek`, `fd_close`, `fd_fdstat_get`, `fd_prestat_get`, `fd_prestat_dir_name`, `fd_readdir` |
| Process | `proc_exit` (throws `WASIProcExit`) |
| Random | `random_get` (`crypto.getRandomValues`) |
| Misc | `sched_yield`, `poll_oneoff` (stubbed) |

Console I/O maps three file descriptors: fd 0 = stdin (empty), fd 1 = stdout (line-buffered, renders to `#out` with ANSI colour support), fd 2 = stderr (renders to `#err`).

> [!NOTE]
> **ANSI colour in the browser console.** The WASI stdout shim includes an SGR parser that converts escape codes to styled HTML spans. Supported: reset (0), bold (1), standard foreground colours (30--37), bright foreground colours (90--97). Your Waskal `println` calls with ANSI escapes render in colour just as they would in a native terminal.

#### The Embedded Asset System

Assets packed by the build pipeline (see [Embedded Assets](#embedded-assets) below) arrive as a base64 blob with a JSON manifest. runtime.js decodes them at startup and provides two APIs:

**Wasm-side imports** (namespace `waskal`, available in your code through `external "waskal"`):

| Import | Signature | Notes |
|--------|-----------|-------|
| `asset_exists` | `(namePtr: i64): i32` | 1 if asset exists, 0 otherwise |
| `asset_size` | `(namePtr: i64): i64` | Byte count |
| `asset_load` | `(namePtr: i64, buf: i64, bufSize: i64): i64` | Copy raw bytes into wasm memory |
| `asset_text` | `(namePtr: i64, buf: i64, bufSize: i64): i64` | Copy UTF-8 text into wasm memory |

**JS-side helpers** (for std module shims):

`WaskalAssets.bytes(name)`, `.blob(name)`, `.url(name)` (creates a blob URL for media elements), `.text(name)`, `.exists(name)`, `.size(name)`, `.getImageBitmap(name)` (for canvas2d `DrawImage`).


### 🚀 Startup and Shutdown Lifecycle

The HTML template (`index.html`) drives the full lifecycle. Understanding it helps when debugging browser console output or writing custom JS host code.

#### Startup Sequence

1. Decode base64 wasm bytes
2. Feature-detect memory64 (instantiate a tiny test module with i64 memory; if it fails, show a user-friendly error)
3. If embedded assets exist, decode the base64 blob
4. `WebAssembly.instantiate(bytes, imports)` with three import namespaces: `wasi_snapshot_preview1` (WASI shim), `waskal` (asset bridge), and one entry per std module in use
5. Call `_start()` via the WASI shim

#### After _start Returns

6. If a game loop is active (`frame.IsRunning()`): set `WKL.onLoopEnd = finish` and register a `pagehide` listener as a fallback -- shutdown is deferred until the loop ends
7. Otherwise: call `finish()` immediately

#### finish()

1. If the `_shutdown` export exists, call it with the shutdown handler index (from `frame.shutdownHandler()`, or 0 if no frame loop)
2. Call `WKL.runExit()` -- fires `onExit` callbacks, drops app-mode styling

All of this is wrapped in `.catch(WKL.fail)`. Errors surface in the `#err` element. A non-zero exit code is shown even when the page is in app mode (canvas visible, console hidden).


### 📤 Exe Exports

Every exe module exports exactly five symbols:

| Export | Signature | Purpose |
|--------|-----------|---------|
| `_start` | `() -> void` | Entry point -- init, main body, return |
| `_shutdown` | `(idx: i32) -> void` | Teardown -- user handler, finalize, cleanup, leak report |
| `_frame` | `(idx: i32, dt: f64) -> void` | Trampoline: calls `routine(const x: float64)` at table[idx] |
| `_call0` | `(idx: i32) -> void` | Trampoline: calls `routine()` at table[idx] |
| `memory` | memory i64 | Linear memory (exported for JS access) |

Lib modules export only `memory` plus any routines marked `public`.

#### _start Internals

1. Allocate composite and memory-homed locals
2. Evaluate expression-based constants (imported units first, then exe)
3. Allocate heap-backed global variables (imported units first, then exe)
4. Run module-level variable initializers (e.g. `x: int32 = 10`)
5. Execute unit `initialize` sections, in import order
6. Execute this module's `initialize` section
7. (Unit test mode: register tests, run `RT_TestRunAll`, skip main body)
8. (Normal mode: execute `begin`..`end.` statements)
9. Release temporary locals, return to JS

#### _shutdown Internals

1. Call user shutdown handler via `call_indirect` (if idx != 0)
2. Execute this module's `finalize` section
3. Execute unit `finalize` sections, in **reverse** import order
4. Global cleanup: imported units (reverse order), then this module
5. Clear the exception state
6. Report leaks (O0 only -- see [Optimization Levels](#optimization-levels))

> [!TIP]
> **The browser owns the loop.** `_start` returns immediately after setting up the game loop. The browser's `requestAnimationFrame` drives subsequent ticks. `_shutdown` is called from a clean JS stack -- never from inside a wasm call. This is why `frame.Stop()` only flips a flag; the actual shutdown happens on the next tick boundary.


### 🛡️ Exception Handling

Waskal uses native wasm exception handling (tags, `try_table`, `catch`, `throw`). No emulation, no polyfill.

#### The Exception Tag

The wasm module defines one tag that carries an error code and a message pointer:

```wat
(tag $myr_exn (param i32 i64))
;;  code ─┘     └─ message (managed string ptr, or 0)
```

Two globals store the last caught exception: `$rt_exc_code` (i32) and `$rt_exc_msg` (i64, managed string).

#### Runtime Exception Codes

| Code | Meaning |
|------|---------|
| 1 | Software exception (default for `throw`) |
| 2 | Division by zero |
| 900 | Varargs type mismatch |
| 901 | Varargs index out of bounds |

User code raises exceptions with `throw` (code 1) or `throwcode` (any code):

```wkl
// bnf_exe_compliance.wkl -- exception handling (trimmed)
guard
  throw("test error");
  println("should not print");
except
  println("caught, code=%lld, msg=%s", exccode(), excmsg());
end;

guard
  throwcode(42, "custom error");
except
  println("code=%lld, msg=%s", exccode(), excmsg());
end;

guard
  throw("err2");
except
  println("except caught");
finally
  println("finally runs");
end;
```

The `guard`/`except`/`finally` block compiles to wasm's `try_table` with a catch clause for the exception tag. `exccode()` returns the integer code; `excmsg()` returns the message string. Both are valid only inside an `except` block.

Hardware traps (division by zero, unreachable) are caught by the same mechanism -- code 2 for integer division by zero.

> [!NOTE]
> **Nested guards.** Guard blocks nest freely. An inner `except` catches only its own `guard` body; an uncaught exception propagates outward. A `finally` block always runs, whether or not an exception occurred.


<a id="embedded-assets"></a>

### 📦 Embedded Assets

The `@asset` and `@assets` directives embed files into the output `.html` at build time. At runtime they are available to both wasm code and JS shims without any network requests.

```wkl
// probe_assets.wkl -- embedding an image (trimmed)
module exe probe_assets;

@asset "$P:res/assets/images/waskal.png" "assets/images";

import canvas2d;

begin
  canvas2d.Init(640, 480);
  canvas2d.Clear(70, 30, 120);
  canvas2d.DrawImage("assets/images/waskal.png", 18, 136, 603, 208);
  println("Asset probe: image drawn");
end.
```

#### Build Pipeline

1. The compiler collects asset entries from `@asset` / `@assets` directives
2. Files are concatenated into a single binary blob; a JSON manifest maps each asset name to its offset and size
3. The manifest and the base64-encoded blob are injected into the HTML template
4. At startup, `WaskalAssets.decode()` unpacks the blob into an ArrayBuffer

#### Wasm-Side Access

Four functions in the `waskal` import namespace let your code query and load assets:

| Function | Purpose |
|----------|---------|
| `asset_exists(name)` | 1 if the asset was embedded, 0 otherwise |
| `asset_size(name)` | Byte count of the raw asset |
| `asset_load(name, buf, bufSize)` | Copy raw bytes into a wasm buffer |
| `asset_text(name, buf, bufSize)` | Copy the asset as UTF-8 text |

The std modules use the JS-side API (`WaskalAssets.url`, `.getImageBitmap`, `.blob`) to feed assets directly to browser media APIs without copying through wasm memory.


<a id="optimization-levels"></a>

### 🎚️ Optimization Levels

The `@optimize` directive or `-opt` CLI flag controls both the wasm-opt pass and emitter behaviour.

| Level | wasm-opt flag | Description |
|-------|---------------|-------------|
| 0 | (none) | No optimization. Leak counters enabled. |
| 1 | `-O1` | Quick optimizations, good for iteration |
| 2 | `-O2` | Most optimizations, best general performance |
| 3 | `-O3` | Aggressive, may take significant time |
| 4 | `-O4` | Aggressive + IR flattening, high time and memory |
| s | `-Os` | Optimized for code size |
| z | `-Oz` | Aggressively optimized for code size |

#### Emitter Behaviour at O0 vs O1+

| O0 (debug) | O1+ (release) |
|------------|---------------|
| `RT_GetMem` / `RT_FreeMem` wrappers count every allocation and free | Direct pass-through wrappers (no counting) |
| `_shutdown` prints `[Heap] Allocs: N  Frees: N  Leaked: N` | No leak report |
| Globals `$rt_alloc_count`, `$rt_free_count` emitted | Not emitted |

#### Wasm Features Always Enabled

Regardless of optimization level, wasm-opt runs with these feature flags:

```
--enable-memory64
--enable-bulk-memory
--enable-nontrapping-float-to-int
--enable-exception-handling
--enable-multivalue
```

> [!TIP]
> **Start with O0.** During development, `@optimize none;` (or omit the directive entirely) gives you the heap leak report at shutdown. Once the program runs cleanly, switch to `@optimize 2;` for release builds.


### 🔧 JS Pipeline

The build pipeline assembles all JavaScript into one minified block before injecting it into the HTML template.

```
runtime.js                  (always included)
  +
Std shims (bin/res/libs/std/<lib>.js)
  +
Vendor shims (bin/res/libs/vendor/<lib>/<lib>.js)
  +
User JS (<lib>.js beside the declaring unit or on @addlibrarypath)
  =
Combined -> esbuild --minify -> Injected into HTML template
```

esbuild combines the files and minifies them. The `--legal-comments=inline` flag preserves `/*!` attribution comments from third-party libraries.

#### HTML Template Placeholders

| Placeholder | Replaced with |
|-------------|---------------|
| `__WKL_WASM_MODULE__` | Module name |
| `__WKL_WASM_BASE64__` | Base64-encoded `.wasm` binary |
| `__WKL_WASI64_SHIM__` | Combined + minified JS |
| `__WKL_EXTRA_IMPORTS__` | Import object entries for std module namespaces |
| `__WKL_FAVICON__` | Favicon link tag (from `@favicon` directive) |
| `__WKL_ASSET_MANIFEST__` | JSON asset manifest |
| `__WKL_ASSET_DATA__` | Base64-encoded asset blob |


### 🧪 Unit Test Mode

When `@unittestmode on;` is active, the compiler replaces the normal entry point with a test runner. Each `test` block is emitted as a function and registered via `RT_TestRegister`. `_start` calls the registrations then `RT_TestRunAll`, which runs each test, catches exceptions, and prints a pass/fail/error summary. Exit code 0 means all tests passed; 1 means at least one failed.

See the Testing section in the Language Reference for the assertion functions and test block syntax.

Next: [Debugging](#debugging)

<a id="debugging"></a>

## 🐛 9. Diagnostics

*Waskal has no source-level debugger. What it has is better for the browser: a leak detector, coloured console output, error mapping back to your source, and the full power of browser DevTools.*

Waskal programs run inside a browser, so the debugging story is the browser's debugging story -- plus a few compiler features that make it practical. Optimization level 0 is effectively debug mode: the output is unoptimized and includes a heap leak report at shutdown. ANSI escape codes render in colour in the browser console. Compiler errors from the wasm layer are mapped back to your `.wkl` source lines. And conditional compilation lets you gate debug-only code behind a symbol you define yourself.


### 🎚️ Optimization Levels

The `-opt` CLI flag or `@optimize` directive controls both the wasm-opt pass and emitter behaviour. Level 0 is the default and the primary diagnostic mode.

| Level | wasm-opt flag | Description |
|-------|---------------|-------------|
| 0 | *(none)* | No optimization. Leak counters enabled. Debug mode. |
| 1 | `-O1` | Quick optimizations, good for iteration |
| 2 | `-O2` | Most optimizations, best general performance |
| 3 | `-O3` | Aggressive, may increase build time |
| 4 | `-O4` | Aggressive + IR flattening |
| s | `-Os` | Optimized for code size |
| z | `-Oz` | Aggressively optimized for code size |

Set the level per file with a directive:

```wkl
@optimize 2;
```

Or from the command line:

```
waskal myprogram -opt 2 -r
```

> [!TIP]
> **Start with O0.** Omit the `@optimize` directive during development -- the default gives you the leak report. Switch to `@optimize 2;` for release builds. See [Optimization Levels](#optimization-levels) in the Runtime section for the full emitter behaviour differences.


### 🔍 Heap Leak Report

At optimization level 0, the emitter generates a leak counter that prints to the browser console at shutdown:

```
[Heap] Allocs: 12  Frees: 12  Leaked: 0
```

Every `getmem`, `new`, string allocation, and dynamic array resize is counted. If `Leaked` is greater than zero, the program has a memory leak -- a heap object was allocated but never freed before shutdown.

```wkl
// frame_loop.wkl -- game loop with zero leaks (trimmed)
// Source: examples/frame_loop.wkl
module exe frame_loop;

import canvas2d;
import frame;

var w: int32 = 800;
var h: int32 = 600;

routine Update(const dt: float64);
begin
end;

routine Render();
begin
  canvas2d.Clear(40, 40, 40);
  canvas2d.SetFillStyle("white");
  canvas2d.FillText("frame loop running", 10.0, 30.0);
end;

routine Shutdown();
begin
  println("shutting down");
end;

begin
  canvas2d.Init(w, h);
  frame.Run(Update, Render, Shutdown);
end.
```

Build at O0 (the default) and open the browser console. After closing the window or calling `frame.Stop()`, the `[Heap]` line appears. A clean program shows `Leaked: 0`.

> [!NOTE]
> **O1 and above suppress the report.** The leak counters add overhead, so they are only emitted at optimization level 0. A release build produces no `[Heap]` output.
<!-- Source: Waskal.Emitter.pas:3952-4006 (RT_ReportLeaks), Emitter.pas:4281-4283 (call site) -->


### 🎨 ANSI Colour Output

The HTML shell includes an SGR parser that converts ANSI escape codes in `println` output to styled `<span>` elements in the browser's output pane.
<!-- Source: index.html:69-110 (writeAnsi) -->

Supported SGR codes:

| Code | Effect |
|------|--------|
| 0 | Reset all attributes |
| 1 | Bold |
| 30--37 | Standard foreground colours (black, red, green, yellow, blue, magenta, cyan, white) |
| 90--97 | Bright foreground colours |

```wkl
// ANSI colour example (not a shipped file -- illustrative)
println("\x1b[1;32mPASS\x1b[0m test_math");
println("\x1b[1;31mFAIL\x1b[0m test_string");
```

The output renders with green "PASS" and red "FAIL" in the browser console, just as it would in a native terminal. The compiler's own test runner uses ANSI codes for pass/fail markers.

> [!NOTE]
> **Unknown codes are ignored.** Background colours and 256-colour/truecolour sequences are not supported by the parser and are silently dropped.


### 🗺️ Compiler Error Mapping

When wasm-opt reports an error (typically a validation failure in the generated `.wat`), the compiler maps the WAT line number back to the original `.wkl` source file and line. You see an error pointing at your code, not at a `.wat` line you never wrote.
<!-- Source: Waskal.Build.pas:505-565 (DoMapWasmOptErrors) -->

```wkl
// probe_sourcemap.wkl -- uncaught exception triggers error mapping (trimmed)
// Source: tests/probe/probe_sourcemap.wkl
module exe probe_sourcemap;

begin
  println("before throw");
  throwcode(42, "sourcemap probe");
  println("should not reach here");
end.
```

This is internal to the compiler's error reporting pipeline. It is not a user-facing debug tool -- it exists so that build errors are actionable without understanding the intermediate `.wat` output.


### 🖥️ Browser DevTools

Waskal does not ship a custom debugger. The browser's built-in developer tools are the primary debugging environment.

**Console tab.** All `println` output appears here, with ANSI colours rendered as styled text. JS warnings from std module shims (`console.warn`) also surface here. In app mode (when canvas2d takes over the page), the console pane is hidden -- but the runtime crash handler (`runtime.js`) ensures that uncaught wasm traps always print to the console, even when the visual output area is not visible.
<!-- Source: runtime.js:69-80 (crash handler) -->

**Sources tab.** The wasm module appears under `wasm://` in the browser's source tree. The built-in wasm inspector can show disassembled wasm instructions. At optimization level 0 the output is unoptimized and maps more directly to your source structure; at higher levels, wasm-opt may restructure the code.

**Network tab.** A self-contained `.html` makes no network requests at runtime (all assets are embedded). If the Network tab shows unexpected traffic, something outside Waskal is responsible.

> [!TIP]
> **Chrome DevTools shortcut.** Press F12 or Ctrl+Shift+I to open DevTools. The Console tab is usually the first place to look when something goes wrong.


### 🔀 Conditional Compilation for Debug Code

Waskal does not define `DEBUG` or `RELEASE` symbols. If you want debug-only code, define your own symbol with `@define` and gate it with `@ifdef`:

```wkl
// bnf_exe_compliance.wkl -- conditional compilation (trimmed)
// Source: tests/compliance/bnf_exe_compliance.wkl:1007-1069
@define MY_DEBUG

@ifdef MY_DEBUG
  println("debug trace: entering main loop");
@endif

// Predefined symbols are always available
@ifdef WASKAL
  println("this is a Waskal program");
@endif

@ifdef WASM64
  println("running on wasm64");
@endif

// Module kind symbols
@ifdef BUILD_EXE
  println("this is an exe module");
@endif

// Nested conditionals
@ifdef WASKAL
  @ifdef WASM64
    println("Waskal on wasm64 confirmed");
  @endif
@endif

// Remove the symbol when no longer needed
@undef MY_DEBUG
@ifdef MY_DEBUG
  println("this will NOT print");
@endif
```

#### Predefined Symbols

| Symbol | Defined when |
|--------|--------------|
| `WASKAL` | Always |
| `WASM64` | Always |
| `BUILD_EXE` | Module kind is `exe` |
| `BUILD_LIB` | Module kind is `lib` |
<!-- Source: Waskal.Parser.pas:684-692 -->

There are no other predefined symbols. `WINDOWS`, `LINUX`, `DEBUG`, `RELEASE` do not exist. See the Conditional Compilation section in the [Language Reference](#language-reference) for the full directive syntax.

> [!WARNING]
> **No conditional `@define` from the command line.** Symbols can only be defined in source code with `@define`. There is no `-D` flag or equivalent. If you need a build-wide symbol, define it in a shared unit that every module imports.

Next: [Code Style](#code-style)



<a id="code-style"></a>

## 📐 10. Code Style

*Consistent naming, formatting, and file layout keep Waskal code readable -- whether it is yours or someone else's.*

Waskal conventions are few and predictable. Types are PascalCase with no prefix, variables are camelCase, constants are UPPER_CASE, and every value parameter takes `const`. The standard library and all shipped examples follow these rules, so adopting them means your code reads like the rest of the ecosystem.


### 🏷️ Naming Conventions

| Category | Style | Example |
|----------|-------|---------|
| Types | PascalCase, no prefix | `Point`, `Color`, `TextMetrics` |
| Variables | camelCase | `count`, `totalScore`, `isReady` |
| Constants | UPPER_CASE with underscores | `MAX_SIZE`, `LINE_CAP_BUTT`, `PI` |
| Routines | camelCase or snake_case | `add`, `getLength`, `make_point` |
| Module names | lowercase | `mathlib`, `canvas2d`, `localstorage` |

> [!NOTE]
> **No T prefix on types.** If you are coming from Delphi or Object Pascal, write `Point` instead of `TPoint`, `Color` instead of `TColor`. Waskal types stand on their own name.


### 📄 File Organization

Every `.wkl` source file follows this structure:

```wkl
module <kind> <name>;

// imports
import other_module;

// constants
const
  MY_CONST: int32 = 42;

// types
type
  MyRecord = record
    x: int32;
    y: int32;
  end;

// routines
routine helper(const a: int32): int32;
begin
  return a * 2;
end;

// public API
public routine doWork(const value: int32): int32;
begin
  return helper(value) + MY_CONST;
end;

// initialization (optional)
initialize
  println("module loaded");
end;

// finalization (optional)
finalize
  println("module unloaded");
end;

// main body (exe modules only)
begin
  println("Hello, Waskal!");
end.
```

The module declaration is always first, followed by imports, then declarations (constants, types, variables, routines), optional initialize/finalize blocks, and the closing `end.` (with a main body for `exe` modules).


### 💬 Comments

Waskal supports two comment styles:

```wkl
// Line comment -- everything after // to end of line

/* Block comment
   Can span multiple lines
   and can be /* nested */ safely */
```

Use line comments for short annotations. Use block comments for longer explanations or temporarily disabling code. The `(* *)` and `{ }` comment styles from traditional Pascal are **not** supported.


### 🔤 Formatting Guidelines

**Indentation.** Use consistent indentation (two or four spaces). Pick one and stick with it throughout your project.

**Semicolons.** Every statement ends with a semicolon. The `end` that closes a block also takes a semicolon (`end;`), except the final `end.` that closes the module.

**String literals.** Waskal uses double quotes for both strings and characters: `"hello"`, `"A"`. Single quotes are not valid.

**Control structures.** `if`, `while`, `for`, `match`, and `guard` always terminate with `end;`. There are no single-statement forms without `end`. The `then` keyword follows the condition in `if` statements, and `else` appears on its own line:

```wkl
if x > 0 then
  println("positive");
end;

if x > 0 then
  println("positive");
  count += 1;
else
  println("non-positive");
end;
```

**Routine parameters.** Separate parameters with semicolons. Use `const` on every value parameter:

```wkl
routine move(const x: int32; const y: int32; const speed: float64): boolean;
```

Use `var` only when the callee writes through the parameter. This convention is followed by every std module and all shipped examples.

**Formatted output.** `println` and `print` use printf-style formatting: `println("x = %d, name = %s", x, name);`. Format specifiers follow C conventions (`%d`, `%s`, `%f`, `%x`, etc.).

**Blank lines.** Use blank lines to separate logical sections: between routines, between groups of related declarations, and before/after initialize/finalize blocks.


### 📦 Visibility

Declarations are private by default. Use the `public` keyword to export a declaration from a module:

```wkl
public const API_VERSION: int32 = 1;       // visible to importers
const INTERNAL_LIMIT: int32 = 256;          // private

public routine calculate(const x: int32): int32;  // exported
routine helper(const x: int32): int32;             // private
```

When consuming imported symbols, always qualify them with the module name:

```wkl
import mathlib;
var result: int32 = mathlib.add(2, 3);
```


### ✅ Example: Well-Structured Source File

```wkl
// geometry.wkl -- a reusable geometry unit
// Source: illustrative (follows std module conventions)
module unit geometry;

// -- Constants --

public const ORIGIN_X: int32 = 0;
public const ORIGIN_Y: int32 = 0;

// -- Types --

public type
  Point = record
    x: int32;
    y: int32;
  end;

public type
  Rect = record
    left: int32;
    top: int32;
    width: int32;
    height: int32;
  end;

// -- Public API --

public routine makePoint(const px: int32; const py: int32): Point;
var
  result: Point;
begin
  result.x := px;
  result.y := py;
  return result;
end;

public routine area(const r: Rect): int32;
begin
  return r.width * r.height;
end;

public routine contains(const r: Rect; const p: Point): boolean;
begin
  return (p.x >= r.left) and (p.x < r.left + r.width)
     and (p.y >= r.top) and (p.y < r.top + r.height);
end;

// -- Module lifecycle --

initialize
  println("geometry loaded");
end;

end.
```

> [!TIP]
> **Keep routines short and focused.** If a routine grows beyond a screenful, split it into smaller helpers. Group related routines together and separate groups with blank lines and a short comment header.

Next: [Common Tasks](#common-tasks)



<a id="common-tasks"></a>

## 🛠️ 11. Common Tasks

*Practical recipes for everyday Waskal work -- each one a working program you can build and run.*

Every recipe below is lifted from a shipped example or test file in the Waskal distribution. Build any of them with `waskal <name> -r` and they run in your browser immediately.


### 📝 Hello World

The smallest Waskal program: a module declaration, a `begin` block, and a call to `println`.

```wkl
// hello.wkl (trimmed)
// Source: examples/hello.wkl
module exe hello;

begin
  println("Hello, I am %s! 🚀🔥✨", "Waskal");

  var s: string = "Waskal™ " + "Programming Language";
  println(s);

  for var i: int32 := 1 to 10 do
    println("%d", i);
  end
end.
```

Build and run: `waskal hello -r`. The browser opens, the output appears in the console pane, and the program exits.


### 🔄 Game Loop

A frame loop with update, render, and shutdown callbacks. The browser owns the animation loop -- `_start` returns immediately, and `requestAnimationFrame` drives the tick cycle.

```wkl
// frame_loop.wkl (trimmed)
// Source: examples/frame_loop.wkl
module exe frame_loop;

import canvas2d;
import frame;

var
  x: float64;
  updates: int64;

routine Update(const dt: float64);
begin
  x := x + 120.0 * dt;
  if x > 800.0 then
    x := 0.0;
  end;
  updates := updates + 1;
  if updates = 600 then
    frame.Stop();
  end;
end;

routine Render();
begin
  canvas2d.SetFillStyle("#000");
  canvas2d.FillRect(0.0, 0.0, 800.0, 600.0);
  canvas2d.SetFillStyle("#0f0");
  canvas2d.FillRect(x, 280.0, 40.0, 40.0);
end;

routine Shutdown();
begin
  println("shutdown handler");
end;

begin
  x := 0.0;
  updates := 0;
  canvas2d.Init(800, 600);
  frame.Run(Update, Render, Shutdown);
end.
```

`frame.Run` takes three routine references: `Update(dt)` is called at a fixed step, `Render()` once per tick, and `Shutdown()` once when `frame.Stop()` fires. After `Shutdown` returns, the runtime calls `_shutdown` for cleanup.


### 🎨 Drawing on Canvas

A static scene drawn with the `canvas2d` module. No frame loop needed -- just `Init`, draw calls, and `end.`

```wkl
// house.wkl (trimmed)
// Source: examples/house.wkl
module exe house;

import canvas2d;

begin
  canvas2d.Init(800, 600);

  // Sky
  canvas2d.Clear(100, 149, 237);

  // House body
  canvas2d.Rect(250, 250, 200, 150, 178, 102, 51);

  // Door
  canvas2d.Rect(325, 320, 50, 80, 101, 67, 33);

  // Sun
  canvas2d.Circle(650, 100, 60, 255, 223, 0);

  println("Canvas demo rendered.");
end.
```

For animated drawing, combine `canvas2d` with `frame.Run` as shown in the game loop recipe. The `canvas2d` module provides rectangles, circles, lines, arcs, paths, gradients, text, images, and pixel manipulation. See the [Standard Library](#standard-library) for the full API.


### ⌨️ Handling Input

Keyboard, mouse, and gamepad input via the `input` module. Input state is snapshotted once per tick by `frame.Run`.

```wkl
// input_square.wkl (trimmed)
// Source: examples/input_square.wkl
module exe input_square;

import canvas2d;
import frame;
import input;

const
  W = 800;
  H = 600;
  SPEED = 200.0;

var
  x: float64;
  y: float64;

routine Update(const dt: float64);
begin
  if input.KeyDown(input.KEY_LEFT) then
    x := x - SPEED * dt;
  end;
  if input.KeyDown(input.KEY_RIGHT) then
    x := x + SPEED * dt;
  end;
  if input.MousePressed(input.MOUSE_LEFT) then
    x := input.MouseX();
    y := input.MouseY();
  end;
  if input.KeyPressed(input.KEY_ESCAPE) then
    frame.Stop();
  end;
end;

// ... Render and Shutdown callbacks, then:
// canvas2d.Init(W, H); frame.Run(Update, Render, Shutdown);
```

`KeyDown` returns true every frame the key is held. `KeyPressed` returns true only on the frame the key transitions from up to down, ignoring auto-repeat. Mouse and gamepad follow the same pressed/down/released pattern.


### 🔊 Playing Sound

Sound effects and music via the `audio` module. Assets are embedded with `@asset` or `@assets`.

```wkl
// audio_player.wkl (trimmed)
// Source: examples/audio_player.wkl
module exe audio_player;

@assets "$P:res/assets/audio" "assets" "*";

import audio;
import canvas2d;
import frame;

var
  sfx: audio.Sound;
  music: audio.Music;

begin
  canvas2d.Init(800, 600);
  audio.Init();
  sfx := audio.LoadSound("assets/audio/sfx/samp0.ogg");
  music := audio.LoadMusic("assets/audio/music/song0.ogg");
  audio.PlayMusic(music, true);
  // audio.PlaySound(sfx) on a key press in the Update callback
  frame.Run(Update, Render, Shutdown);
end.
```

`Sound` plays fully in memory (short effects). `Music` streams from the decoded buffer (long tracks). Both use the Web Audio API underneath. Browser autoplay policy blocks audio until a user gesture -- the `audio` module handles the unlock automatically on the first click or key press.

> [!NOTE]
> **Asset embedding.** The `@assets` directive bulk-embeds every matching file. At runtime, `audio.LoadSound` and `audio.LoadMusic` resolve the virtual path against the embedded asset manifest.


### 🎬 Playing Video

Video playback via the `video` module. Two rendering modes: draw onto a canvas2d surface, or show as a standalone HTML element.

```wkl
// video_player.wkl (trimmed)
// Source: examples/video_player.wkl
module exe video_player;

@asset "$P:res/assets/video/demo.mp4" "assets/video";

import video;

var
  v: video.Video;

begin
  v := video.Load("assets/video/demo.mp4");
  video.Show(v, "contain");
  video.Play(v);
  println("video playing");
end.
```

`video.Show` places the video element in the page, sized by the CSS `object-fit` value (`"contain"`, `"cover"`, `"fill"`). For compositing onto a canvas, use `video.Draw(v, x, y, w, h)` inside a `Render` callback instead.


### 💾 Persistent Storage

Key-value persistence across page reloads via the `localstorage` module.

```wkl
// run_counter.wkl (trimmed)
// Source: examples/run_counter.wkl
module exe run_counter;

import localstorage;

var runs: int64;

begin
  if localstorage.Available() then
    runs := localstorage.GetInt("runs", 0) + 1;
    localstorage.SetInt("runs", runs);
    println("runs = %lld (reload to increment)", runs);
  else
    println("localStorage not available");
  end;
end.
```

Keys are automatically prefixed with the module name, so two different programs using the same key name do not collide. `Clear`, `RemoveItem`, `Length`, `Key`, and `HasItem` round out the API. All operations return false or a default value on failure -- no exceptions.

> [!TIP]
> **Check availability first.** `localstorage.Available()` returns false when the browser blocks storage (private browsing, storage quota exceeded, or `file://` in some browsers).


### 📦 Embedding Assets

The `@asset` directive packs a file into the `.html` output at build time. At runtime, the asset is decompressed and available by its virtual path.

```wkl
// embedded_image.wkl (trimmed)
// Source: examples/embedded_image.wkl
module exe embedded_image;

@asset "$P:res/assets/images/waskal.png" "assets/images";

import canvas2d;

begin
  canvas2d.Init(640, 480);
  canvas2d.Clear(70, 30, 120);
  canvas2d.DrawImage("assets/images/waskal.png", 18, 136, 603, 208);
  println("Asset demo: image drawn");
end.
```

For bulk embedding, `@assets` takes a source directory and a glob pattern: `@assets "$P:res/assets/audio" "assets" "*.ogg";` embeds every `.ogg` file recursively. See the [Module System](#module-system) for the full directive syntax.


### 🌐 Calling JavaScript

Write a JS namespace object, declare its functions as `external` in Waskal, and the compiler wires them together at build time.

**mathjs.js** (the JS side):

```javascript
// Source: tests/libs/mathjs.js
var mathjs = {
  JsAdd: function(a, b) { return a + b; }
};
```

**probe_extlibs.wkl** (the Waskal side):

```wkl
// probe_extlibs.wkl (trimmed)
// Source: tests/probe/probe_extlibs.wkl
module exe probe_extlibs;

@addlibrarypath "$P:res/tests/libs";

routine JsAdd(a: int32; b: int32): int32;
  external "mathjs" name "JsAdd";

begin
  println("JsAdd(2, 3) = %d", JsAdd(2, 3));
end.
```

The `external "mathjs"` clause tells the compiler to find `mathjs.js` on the library search path. The `name "JsAdd"` maps the Waskal routine name to the JS property name. Numbers cross as-is; strings cross as `ptr to char` via `WKL.readCStr`. See [JS Interop](#js-interop) for the full marshalling contract.


### 📤 Shipping a .wasm Library

A `module lib` produces a standalone `.wasm` file that other Waskal programs or any wasm host can consume.

```wkl
// mathlib.wkl
// Source: tests/probe/mathlib.wkl
module lib mathlib;

@outputpath "$P:res/tests/libs";

public routine Add(a: int64; b: int64): int64;
begin
  return a + b;
end;

end.
```

Build: `waskal mathlib`. The output is a `.wasm` file containing the exported `Add` function. Only `public` routines are exported, and overloaded names cannot be exported (each export name must be unique). A consuming program declares `external "mathlib" name "Add"` and the build pipeline merges the `.wasm` via `wasm-merge`. See [JS Interop](#js-interop) for details.


### ⚡ Exception Handling

`guard`/`except`/`finally` blocks catch both software exceptions (`throw`, `throwcode`) and hardware traps (division by zero).

```wkl
// bnf_exe_compliance.wkl (trimmed)
// Source: tests/compliance/bnf_exe_compliance.wkl:862-933
guard
  throw("test error");
  println("should not print");
except
  println("caught, code=%lld, msg=%s", exccode(), excmsg());
end;

guard
  throwcode(42, "custom error");
except
  println("code=%lld, msg=%s", exccode(), excmsg());
end;

guard
  println("guard-finally body");
finally
  println("finally always runs");
end;

guard
  throw("err");
except
  println("except caught");
finally
  println("finally runs after except");
end;
```

`exccode()` returns the integer error code (0 for a bare `throw`, the user-supplied value for `throwcode`, or a runtime code for hardware traps). `excmsg()` returns the message string. Nested `guard` blocks and exception propagation from called routines both work.


### 📋 Records and Pointers

Records group related fields. They can live on the stack or be heap-allocated with `new`/`dispose`.

```wkl
// probe_record.wkl (trimmed)
// Source: tests/probe/probe_record.wkl
type
  Point = record
    x: int32;
    y: int32;
  end;

// Stack allocation with record literal
var p: Point = Point(x: 10, y: 20);
println("p = (%d, %d)", p.x, p.y);

// Heap allocation
var pp: pointer to Point;
new(pp);
pp^.x := 30;
pp^.y := 40;
println("pp^ = (%d, %d)", pp^.x, pp^.y);
dispose(pp);
```

Records also support `packed` (no padding), `align(N)` (minimum alignment), inheritance (`record(Base)`), and anonymous overlay sections. See the [Language Reference](#language-reference) for the full type definition syntax.


### 📊 Dynamic Arrays

Heap-allocated, resizable arrays managed with `setlength` and `len`.

```wkl
// probe_array.wkl (trimmed)
// Source: tests/probe/probe_array.wkl
var nums: array of int32;

setlength(nums, 5);
nums[0] := 10;
nums[1] := 20;
nums[2] := 30;
println("len=%d, nums[0]=%d, nums[2]=%d", len(nums), nums[0], nums[2]);

// Grow
setlength(nums, 8);
nums[7] := 99;
println("after grow: len=%d, nums[7]=%d", len(nums), nums[7]);

// Free
setlength(nums, 0);
```

Static arrays use a fixed range: `var buf: array[0..9] of int32;`. Dynamic arrays start at length zero and grow with `setlength`. Both are indexed from their declared lower bound (dynamic arrays from 0). See [Memory](#memory-management) for how dynamic arrays interact with the heap.


### 🧪 Unit Tests

Test blocks after `end.` run in place of the normal entry point when `@unittestmode` is on.

```wkl
// bnf_unittest_compliance.wkl (trimmed)
// Source: tests/compliance/bnf_unittest_compliance.wkl
module exe bnf_unittest_compliance;

@unittestmode on;

routine add(const a: int32; const b: int32): int32;
begin
  return a + b;
end;

begin
  // This block does NOT run in test mode
  println("MAIN BLOCK MUST NOT RUN");
end.

test "integer arithmetic"
begin
  asserteq(3, add(1, 2));
  asserteq(0, add(-1, 1));
  asserteq(5, add(2, 3));
end;

test "test-local variables"
var
  total: int32;
  i: int32;
begin
  total := 0;
  for i := 1 to 10 do
    total := total + i;
  end;
  asserteq(55, total, "loop inside a test block");
end;
```

Assertions: `asserteq(expected, actual)`, `asserteqf(expected, actual, epsilon)`, `asserttrue(val)`, `assertfalse(val)`. All four accept an optional trailing message string. Failures are non-aborting -- every test runs and the runner prints a summary. Build and run with `waskal bnf_unittest_compliance -r`.


### 🔀 Conditional Compilation

Define symbols with `@define`, test with `@ifdef`/`@ifndef`, branch with `@else`/`@elseif`, close with `@endif`.

```wkl
// bnf_exe_compliance.wkl (trimmed)
// Source: tests/compliance/bnf_exe_compliance.wkl:1007-1069

// User-defined symbol
@define MY_DEBUG
@ifdef MY_DEBUG
  println("debug trace active");
@endif

// Predefined: always available
@ifdef WASKAL
  println("this is a Waskal program");
@endif

// Module kind check
@ifdef BUILD_EXE
  println("exe module");
@endif

// Nested
@ifdef WASKAL
  @ifdef WASM64
    println("Waskal on wasm64");
  @endif
@endif

// Remove a symbol
@undef MY_DEBUG
@ifdef MY_DEBUG
  println("this will NOT print");
@endif
```

Four predefined symbols are always available: `WASKAL`, `WASM64`, `BUILD_EXE` (when module kind is `exe`), and `BUILD_LIB` (when module kind is `lib`). There are no `DEBUG` or `RELEASE` builtins -- define your own with `@define`. See the [Language Reference](#language-reference) and [Module System](#module-system) for the full directive syntax.

> [!NOTE]
> **No `-D` flag.** Symbols can only be defined in source code. If you need a build-wide symbol, define it in a shared unit that every module imports.

Next: [Contributing](#contributing)



<a id="contributing"></a>

## 🤝 Contributing

Waskal is developed by tinyBigGAMES. Whether you are fixing a bug, improving documentation, improving examples, or proposing a feature, contributions are welcome.

| Contribution | Best Way to Help |
|--------------|------------------|
| 🐞 Bug report | Open an issue with a minimal reproduction and the exact command used |
| 💡 Feature idea | Describe the real use case first, then the proposed syntax or behavior |
| 🧾 Documentation fix | Point to the section and explain what was unclear or missing |
| 🧪 Test case | Include the smallest `.wkl` file that proves the behavior |
| 🔧 Pull request | Keep the change focused and explain the before/after behavior |

> [!TIP]
> 🚀 Small, focused contributions are the easiest to review and the fastest to land.

## 💖 Support the Project

If Waskal saves you time, helps you learn, or sparks something useful:

- ⭐ **Star the repo**: it costs nothing and helps others find the project
- 🗣️ **Spread the word**: write a post, mention it in a community, or share a screenshot
- 💬 **Join the community**: show what you are building and help shape what comes next
- 🧪 **Try examples**: real usage finds issues that synthetic tests miss
- 💖 **[Become a sponsor](https://github.com/sponsors/tinyBigGAMES)**: sponsorship directly funds development, examples, and documentation

## 📜 License

Waskal is licensed under the **Apache License, Version 2.0**. See [LICENSE](https://github.com/tinyBigGAMES/Waskal?tab=License-1-ov-file#) for details.

Apache 2.0 is a permissive open source license that lets you use, modify, and distribute Waskal freely in both open source and commercial projects. You are not required to release your own source code. Attribution is required: keep the copyright notice and license file in place.

## 🔗 Links

- 🌐 [Homepage](https://waskal.org/)
- 🧑‍💻 [GitHub](https://github.com/tinyBigGAMES/Waskal)
- 💬 [Discord](https://discord.gg/Wb6z8Wam7p)
- 🦋 [Bluesky](https://bsky.app/profile/tinybiggames.com)
- 🎮 [tinyBigGAMES](https://tinybiggames.com)

<div align="center">

**💎 Waskal&trade;** - Write Pascal. Ship one file. Runs everywhere.

Copyright &copy; 2026-present tinyBigGAMES&trade; LLC<br/>All Rights Reserved.

</div>
