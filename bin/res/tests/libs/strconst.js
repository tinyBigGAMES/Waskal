// strconst.js -- JS host functions for "strconst" import module
// Exposed to wasm as (import "strconst" "CStrLen" ...)
var strconst = {
  // returns BigInt (int64)
  CStrLen: function(p) { return BigInt(WKL.readCStr(p).length); }
};
