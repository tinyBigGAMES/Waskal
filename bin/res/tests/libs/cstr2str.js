// cstr2str.js -- JS host functions for "cstr2str" import module
var cstr2str = {
  // Length query / fill, same contract as canvas2d ToDataURL. returns BigInt
  GetGreeting: function (buf, size) { return WKL.writeCStr("hello from js", buf, size); },
  // returns BigInt
  CStrLen: function (p) { return BigInt(WKL.readCStr(p).length); }
};
