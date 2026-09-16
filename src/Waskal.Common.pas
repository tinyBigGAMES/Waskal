{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
===============================================================================}

unit Waskal.Common;

{$I StdApp.Defines.inc}

interface

uses
  System.Generics.Collections,
  StdApp.Base;

type

  { TWklSourceMap }
  TWklSourceMap = TList<TSourceRange>;

  { TWklStringArray }
  TWklStringArray = TArray<string>;

  { TWklLineMap }
  TWklLineMap = TArray<TSourceRange>;

  { TWklEmittedFunc }
  TWklEmittedFunc = record
    WatText: string;
    LineMap: TWklLineMap;
  end;

const
  WKL_MAJOR_VERSION = 0;
  WKL_MINOR_VERSION = 1;
  WKL_PATCH_VERSION = 0;

  WKL_VERSION     = (WKL_MAJOR_VERSION * 10000) + (WKL_MINOR_VERSION * 100) +
                     WKL_PATCH_VERSION;
  WKL_VERSION_STR = '0.1.0';

  WKL_SRCFILE_EXT = '.wkl';

  WKL_RES_TESTS_DIR   = '$P:res/tests';
  WKL_RES_STD_DIR     = '$P:res/libs/std';
  WKL_RES_VENDOR_DIR  = '$P:res/libs/vendor';
  WKL_RES_RUNTIME_WAT = '$P:res/wasm/runtime.wat';
  WKL_RES_WASM_PATH   = '$P:res/wasm';

function  WklSanitizeIdentifier(const AName: string): string;
procedure WklLogStdErr(const AMsg: string);

implementation

uses
  System.SysUtils;

function WklSanitizeIdentifier(const AName: string): string;
var
  LI: Integer;
  LChar: Char;
begin
  Result := '';
  for LI := 1 to Length(AName) do
  begin
    LChar := AName[LI];
    if CharInSet(LChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Result := Result + LChar
    else
      Result := Result + '_';
  end;
end;

procedure WklLogStdErr(const AMsg: string);
begin
  WriteLn(ErrOutput, AMsg);
end;

end.
