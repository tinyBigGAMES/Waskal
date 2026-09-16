// mathjs.js -- JS host functions for "mathjs" import module
// Exposed to wasm as (import "mathjs" "JsAdd" ...)
var mathjs = {
  JsAdd: function(a, b) { return a + b; },
  JsMul: function(a, b) { return a * b; }
};
