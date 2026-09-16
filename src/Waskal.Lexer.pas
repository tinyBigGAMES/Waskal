{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.Lexer - Lexical analysis

  Token definitions (TWklTokenCategory, TWklTokenKind, TWklToken), keyword
  registration, and tokenization engine (TWklLexer).

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources, Waskal.Common
===============================================================================}

unit Waskal.Lexer;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Rtti,
  StdApp.Base,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Utils,
  StdApp.Resources,
  Waskal.Common;

type

  { TWklTokenCategory }
  TWklTokenCategory = (
    tcKeyword,        // language reserved words
    tcPrimitive,      // built-in type names (int32, string, etc.)
    tcOperator,       // operators (+, -, :=, etc.)
    tcDelimiter,      // structural punctuation (; , . ( ) etc.)
    tcLiteral,        // integer, float, string, wstring literals
    tcIdentifier,     // user-defined identifiers
    tcDirective,      // @name directives
    tcSpecial         // EOF, unknown
  );

  { TWklTokenKind }
  TWklTokenKind = (

    // -- Special tokens --
    tkEOF,
    tkUnknown,
    tkIdentifier,
    tkDirective,

    // -- Literals --
    tkIntLiteral,
    tkFloatLiteral,
    tkStringLiteral,
    tkWStringLiteral,

    // -- Keywords --
    tkAddress,
    tkAlign,
    tkAnd,
    tkArray,
    tkAssert,
    tkAssertEq,
    tkAssertEqF,
    tkAssertFalse,
    tkAssertFail,
    tkAssertNil,
    tkAssertNotNil,
    tkAssertTrue,
    tkBegin,
    tkBreak,
    tkChoices,
    tkConst,
    tkContinue,
    tkNew,
    tkDispose,
    tkDiv,
    tkDo,
    tkDownTo,
    tkElse,
    tkEnd,
    tkExcept,
    tkExcCode,
    tkExcMsg,
    tkExternal,
    tkFalse,
    tkFinalize,
    tkFinally,
    tkFor,
    tkForward,
    tkFreeMem,
    tkGetMem,
    tkGuard,
    tkIf,
    tkImport,
    tkIn,
    tkInitialize,
    tkIs,
    tkLen,
    tkMatch,
    tkMod,
    tkModule,
    tkNil,
    tkNot,
    tkOf,
    tkOr,
    tkOverlay,
    tkPacked,
    tkParamCount,
    tkParamStr,
    tkPointer,
    tkPrint,
    tkPrintLn,
    tkPublic,
    tkRecord,
    tkRepeat,
    tkResizeMem,
    tkReturn,
    tkRoutine,
    tkSet,
    tkSetLength,
    tkShl,
    tkShr,
    tkSize,
    tkTest,
    tkThen,
    tkThrow,
    tkThrowCode,
    tkTo,
    tkTrue,
    tkType,
    tkUntil,
    tkUtf8,
    tkCStr,
    tkFormat,
    tkVar,
    tkVarArgs,
    tkWhile,
    tkWStr,
    tkXor,

    // -- Primitive types --
    // Registered as keywords with tcPrimitive category and wasm target type mappings.
    // ptr is already listed above as a keyword; it is registered once
    // with tcPrimitive category so GetTargetType works.
    tkInt8,
    tkInt16,
    tkInt32,
    tkInt64,
    tkUInt8,
    tkUInt16,
    tkUInt32,
    tkUInt64,
    tkFloat32,
    tkFloat64,
    tkBoolean,
    tkChar,
    tkWChar,
    tkString,
    tkWString,

    // -- Operators --
    tkPlus,           // +
    tkMinus,          // -
    tkStar,           // *
    tkSlash,          // /
    tkEqual,          // =
    tkNotEqual,       // <>
    tkLess,           // <
    tkGreater,        // >
    tkLessEqual,      // <=
    tkGreaterEqual,   // >=
    tkAssign,         // :=
    tkPlusAssign,     // +=
    tkMinusAssign,    // -=
    tkStarAssign,     // *=
    tkSlashAssign,    // /=
    tkCaret,          // ^
    tkPipe,           // |
    tkAmpersand,      // &

    // -- Delimiters --
    tkColon,          // :
    tkSemicolon,      // ;
    tkComma,          // ,
    tkDot,            // .
    tkDotDot,         // ..
    tkEllipsis,       // ...
    tkLParen,         // (
    tkRParen,         // )
    tkLBracket,       // [
    tkRBracket        // ]
  );

  { TWklToken }
  TWklToken = record
    Kind: TWklTokenKind;
    TokenText: string;        // canonical text (lowercased for keywords)
    RawText: string;          // exactly as it appeared in source
    LeadingTrivia: string;    // whitespace and comments preceding this token
    Location: TSourceRange;   // file, line, column
    Category: TWklTokenCategory; // what family this token belongs to
    LiteralValue: TValue;     // parsed literal (Int64, UInt64, Double, or string)
    procedure Clear();
  end;

  { TWklTokens }
  TWklTokens = TList<TWklToken>;

const

  // Error codes
  WKL_ERR_LEX_001 = 'LEX001';  // Unterminated string literal
  WKL_ERR_LEX_002 = 'LEX002';  // Unterminated block comment
  WKL_ERR_LEX_003 = 'LEX003';  // Invalid character
  WKL_ERR_LEX_004 = 'LEX004';  // Invalid hex literal
  WKL_ERR_LEX_005 = 'LEX005';  // Invalid escape sequence
  WKL_ERR_LEX_006 = 'LEX006';  // Invalid numeric literal
  WKL_ERR_LEX_007 = 'LEX007';  // Unexpected end of file
  WKL_ERR_LEX_008 = 'LEX008';  // Expected token
  WKL_ERR_LEX_009 = 'LEX009';  // File not found
  WKL_ERR_LEX_010 = 'LEX010';  // File read error

type

  { TWklLexer }
  TWklLexer = class(TBaseObject)
  private
    // Source state
    FSource: string;
    FFilename: string;
    FPos: UInt64;
    FLine: UInt64;
    FCol: UInt64;

    // Token storage and navigation
    FTokens: TWklTokens;
    FTokenIndex: UInt64;

    // Registration dictionaries
    FKeywords: TDictionary<string, TWklTokenKind>;
    FCategories: TDictionary<TWklTokenKind, TWklTokenCategory>;
    FTargetTypes: TDictionary<TWklTokenKind, string>;

    // Source traversal
    function CurrentChar(): Char;
    function PeekChar(): Char;
    function PeekCharAt(const AOffset: Int64): Char;
    procedure Advance();
    function IsAtSourceEnd(): Boolean;
    function MakeLocation(const AStartLine: UInt64; const AStartCol: UInt64): TSourceRange;

    // Trivia and comment scanning
    function DoCollectTrivia(): string;
    procedure DoScanLineComment(var ATrivia: string);
    procedure DoScanBlockComment(var ATrivia: string);

    // Token scanning
    function DoScanToken(const ATrivia: string): TWklToken;
    function DoScanIdentifier(): TWklToken;
    function DoScanNumber(): TWklToken;
    function DoScanStringLiteral(): TWklToken;
    function DoScanWStringLiteral(): TWklToken;
    function DoScanDirective(): TWklToken;
    function DoScanOperator(): TWklToken;
    function DoProcessEscapeSeq(): Char;

    // Internal registration
    procedure RegisterKeywords();
    procedure RegisterPrimitives();
    procedure RegisterCategories();

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Tokenization
    function TokenizeString(const ASource: string;
      const AFilename: string;
      const AAppend: Boolean = False): Boolean;
    function TokenizeFile(const AFilename: string;
      const AAppend: Boolean = False): Boolean;

    // Keyword/type registration
    procedure AddKeyword(const AText: string; const AKind: TWklTokenKind;
      const ACategory: TWklTokenCategory); overload;
    procedure AddKeyword(const AText: string; const AKind: TWklTokenKind;
      const ACategory: TWklTokenCategory; const ATargetType: string); overload;
    function IsKeyword(const AName: string): Boolean;

    // Navigation API (used by parser)
    function CurrentToken(): TWklToken;
    function NextToken(): TWklToken;
    function PeekToken(): TWklToken;
    function PeekAt(const AOffset: Int64): TWklToken;
    function Match(const AKind: TWklTokenKind): Boolean;
    function Expect(const AKind: TWklTokenKind): TWklToken;
    function IsAtEnd(): Boolean;

    // Query helpers
    function IsDataType(const AKind: TWklTokenKind): Boolean;
    function IsOperator(const AKind: TWklTokenKind): Boolean;
    function GetTargetType(const AKind: TWklTokenKind): string;
    function GetCategory(const AKind: TWklTokenKind): TWklTokenCategory;
    function GetRegisteredWords(const ACategory: TWklTokenCategory): TWklStringArray;
    function TokenCount(): UInt64;
    function GetTokens(): TWklTokens;

    // Properties
    property SourceText: string read FSource;
    property TokenIndex: UInt64 read FTokenIndex;
    property Tokens: TWklTokens read FTokens;

    // Source reconstruction
    function ToSource(): string;
  end;

implementation

{ TWklToken }
procedure TWklToken.Clear();
begin
  Kind := tkUnknown;
  TokenText := '';
  RawText := '';
  LeadingTrivia := '';
  Location.Clear();
  Category := tcSpecial;
  LiteralValue := TValue.Empty;
end;

{ TWklLexer }
constructor TWklLexer.Create();
begin
  inherited;

  FTokens := TWklTokens.Create();
  FKeywords := TDictionary<string, TWklTokenKind>.Create();
  FCategories := TDictionary<TWklTokenKind, TWklTokenCategory>.Create();
  FTargetTypes := TDictionary<TWklTokenKind, string>.Create();

  FTokenIndex := 0;
  FPos := 1;
  FLine := 1;
  FCol := 1;

  RegisterKeywords();
  RegisterPrimitives();
  RegisterCategories();
end;

destructor TWklLexer.Destroy();
begin
  FTargetTypes.Free();
  FCategories.Free();
  FKeywords.Free();
  FTokens.Free();

  inherited;
end;

procedure TWklLexer.AddKeyword(const AText: string; const AKind: TWklTokenKind;
  const ACategory: TWklTokenCategory);
begin
  FKeywords.AddOrSetValue(AText.ToLower(), AKind);
  FCategories.AddOrSetValue(AKind, ACategory);
end;

procedure TWklLexer.AddKeyword(const AText: string; const AKind: TWklTokenKind;
  const ACategory: TWklTokenCategory; const ATargetType: string);
begin
  AddKeyword(AText, AKind, ACategory);
  FTargetTypes.AddOrSetValue(AKind, ATargetType);
end;

function TWklLexer.IsKeyword(const AName: string): Boolean;
begin
  Result := FKeywords.ContainsKey(AName.ToLower());
end;

procedure TWklLexer.RegisterKeywords();
begin
  AddKeyword('address',      tkAddress,      tcKeyword);
  AddKeyword('align',        tkAlign,        tcKeyword);
  AddKeyword('and',          tkAnd,          tcKeyword);
  AddKeyword('array',        tkArray,        tcKeyword);
  AddKeyword('assert',       tkAssert,       tcKeyword);
  AddKeyword('asserteq',     tkAssertEq,     tcKeyword);
  AddKeyword('asserteqf',    tkAssertEqF,    tcKeyword);
  AddKeyword('assertfalse',  tkAssertFalse,  tcKeyword);
  AddKeyword('assertfail',   tkAssertFail,   tcKeyword);
  AddKeyword('assertnil',    tkAssertNil,    tcKeyword);
  AddKeyword('assertnotnil', tkAssertNotNil, tcKeyword);
  AddKeyword('asserttrue',   tkAssertTrue,   tcKeyword);
  AddKeyword('begin',        tkBegin,        tcKeyword);
  AddKeyword('break',        tkBreak,        tcKeyword);
  AddKeyword('choices',      tkChoices,      tcKeyword);
  AddKeyword('const',        tkConst,        tcKeyword);
  AddKeyword('continue',     tkContinue,     tcKeyword);
  AddKeyword('new',          tkNew,          tcKeyword);
  AddKeyword('dispose',      tkDispose,      tcKeyword);
  AddKeyword('div',          tkDiv,          tcKeyword);
  AddKeyword('do',           tkDo,           tcKeyword);
  AddKeyword('downto',       tkDownTo,       tcKeyword);
  AddKeyword('else',         tkElse,         tcKeyword);
  AddKeyword('end',          tkEnd,          tcKeyword);
  AddKeyword('except',       tkExcept,       tcKeyword);
  AddKeyword('exccode',      tkExcCode,      tcKeyword);
  AddKeyword('excmsg',       tkExcMsg,       tcKeyword);
  AddKeyword('external',     tkExternal,     tcKeyword);
  AddKeyword('false',        tkFalse,        tcKeyword);
  AddKeyword('finalize',     tkFinalize,     tcKeyword);
  AddKeyword('finally',      tkFinally,      tcKeyword);
  AddKeyword('for',          tkFor,          tcKeyword);
  AddKeyword('forward',      tkForward,      tcKeyword);
  AddKeyword('freemem',      tkFreeMem,      tcKeyword);
  AddKeyword('getmem',       tkGetMem,       tcKeyword);
  AddKeyword('guard',        tkGuard,        tcKeyword);
  AddKeyword('if',           tkIf,           tcKeyword);
  AddKeyword('import',       tkImport,       tcKeyword);
  AddKeyword('in',           tkIn,           tcKeyword);
  AddKeyword('initialize',   tkInitialize,   tcKeyword);
  AddKeyword('is',           tkIs,           tcKeyword);
  AddKeyword('len',          tkLen,          tcKeyword);
  AddKeyword('match',        tkMatch,        tcKeyword);
  AddKeyword('mod',          tkMod,          tcKeyword);
  AddKeyword('module',       tkModule,       tcKeyword);
  AddKeyword('nil',          tkNil,          tcKeyword);
  AddKeyword('not',          tkNot,          tcKeyword);
  AddKeyword('of',           tkOf,           tcKeyword);
  AddKeyword('or',           tkOr,           tcKeyword);
  AddKeyword('overlay',      tkOverlay,      tcKeyword);
  AddKeyword('packed',       tkPacked,       tcKeyword);
  AddKeyword('paramcount',   tkParamCount,   tcKeyword);
  AddKeyword('paramstr',     tkParamStr,     tcKeyword);
  AddKeyword('print',        tkPrint,        tcKeyword);
  AddKeyword('println',      tkPrintLn,      tcKeyword);
  AddKeyword('public',       tkPublic,       tcKeyword);
  AddKeyword('record',       tkRecord,       tcKeyword);
  AddKeyword('repeat',       tkRepeat,       tcKeyword);
  AddKeyword('resizemem',    tkResizeMem,    tcKeyword);
  AddKeyword('return',       tkReturn,       tcKeyword);
  AddKeyword('routine',      tkRoutine,      tcKeyword);
  AddKeyword('set',          tkSet,          tcKeyword);
  AddKeyword('setlength',    tkSetLength,    tcKeyword);
  AddKeyword('shl',          tkShl,          tcKeyword);
  AddKeyword('shr',          tkShr,          tcKeyword);
  AddKeyword('size',         tkSize,         tcKeyword);
  AddKeyword('test',         tkTest,         tcKeyword);
  AddKeyword('then',         tkThen,         tcKeyword);
  AddKeyword('throw',        tkThrow,        tcKeyword);
  AddKeyword('throwcode',    tkThrowCode,    tcKeyword);
  AddKeyword('to',           tkTo,           tcKeyword);
  AddKeyword('true',         tkTrue,         tcKeyword);
  AddKeyword('type',         tkType,         tcKeyword);
  AddKeyword('until',        tkUntil,        tcKeyword);
  AddKeyword('utf8',         tkUtf8,         tcKeyword);
  AddKeyword('cstr',         tkCStr,         tcKeyword);
  AddKeyword('format',       tkFormat,       tcKeyword);
  AddKeyword('var',          tkVar,          tcKeyword);
  AddKeyword('varargs',      tkVarArgs,      tcKeyword);
  AddKeyword('while',        tkWhile,        tcKeyword);
  AddKeyword('wstr',         tkWStr,         tcKeyword);
  AddKeyword('xor',          tkXor,          tcKeyword);

  // Punctuation and operators (for Expect error messages)
  AddKeyword(';',   tkSemicolon,    tcDelimiter);
  AddKeyword(':',   tkColon,        tcDelimiter);
  AddKeyword(',',   tkComma,        tcDelimiter);
  AddKeyword('.',   tkDot,          tcDelimiter);
  AddKeyword('..',  tkDotDot,       tcDelimiter);
  AddKeyword('...', tkEllipsis,     tcDelimiter);
  AddKeyword('(',   tkLParen,       tcDelimiter);
  AddKeyword(')',   tkRParen,       tcDelimiter);
  AddKeyword('[',   tkLBracket,     tcDelimiter);
  AddKeyword(']',   tkRBracket,     tcDelimiter);
  AddKeyword('+',   tkPlus,         tcOperator);
  AddKeyword('-',   tkMinus,        tcOperator);
  AddKeyword('*',   tkStar,         tcOperator);
  AddKeyword('/',   tkSlash,        tcOperator);
  AddKeyword('=',   tkEqual,        tcOperator);
  AddKeyword('<>',  tkNotEqual,     tcOperator);
  AddKeyword('<',   tkLess,         tcOperator);
  AddKeyword('>',   tkGreater,      tcOperator);
  AddKeyword('<=',  tkLessEqual,    tcOperator);
  AddKeyword('>=',  tkGreaterEqual, tcOperator);
  AddKeyword(':=',  tkAssign,       tcOperator);
  AddKeyword('+=',  tkPlusAssign,   tcOperator);
  AddKeyword('-=',  tkMinusAssign,  tcOperator);
  AddKeyword('*=',  tkStarAssign,   tcOperator);
  AddKeyword('/=',  tkSlashAssign,  tcOperator);
  AddKeyword('^',   tkCaret,        tcOperator);
  AddKeyword('|',   tkPipe,         tcOperator);
  AddKeyword('&',   tkAmpersand,    tcOperator);
end;

procedure TWklLexer.RegisterPrimitives();
begin
  // Built-in types with wasm64 target type mappings
  AddKeyword('int8',     tkInt8,     tcPrimitive, 'i32');
  AddKeyword('int16',    tkInt16,    tcPrimitive, 'i32');
  AddKeyword('int32',    tkInt32,    tcPrimitive, 'i32');
  AddKeyword('int64',    tkInt64,    tcPrimitive, 'i64');
  AddKeyword('uint8',    tkUInt8,    tcPrimitive, 'i32');
  AddKeyword('uint16',   tkUInt16,   tcPrimitive, 'i32');
  AddKeyword('uint32',   tkUInt32,   tcPrimitive, 'i32');
  AddKeyword('uint64',   tkUInt64,   tcPrimitive, 'i64');
  AddKeyword('float32',  tkFloat32,  tcPrimitive, 'f32');
  AddKeyword('float64',  tkFloat64,  tcPrimitive, 'f64');
  AddKeyword('bool',     tkBoolean,  tcPrimitive, 'i32');
  AddKeyword('char',     tkChar,     tcPrimitive, 'i32');
  AddKeyword('wchar',    tkWChar,    tcPrimitive, 'i32');
  AddKeyword('string',   tkString,   tcPrimitive, 'i64');
  AddKeyword('wstring',  tkWString,  tcPrimitive, 'i64');
  AddKeyword('ptr',      tkPointer,  tcPrimitive, 'i64');
end;

procedure TWklLexer.RegisterCategories();
begin
  // Operators
  FCategories.AddOrSetValue(tkPlus,         tcOperator);
  FCategories.AddOrSetValue(tkMinus,        tcOperator);
  FCategories.AddOrSetValue(tkStar,         tcOperator);
  FCategories.AddOrSetValue(tkSlash,        tcOperator);
  FCategories.AddOrSetValue(tkEqual,        tcOperator);
  FCategories.AddOrSetValue(tkNotEqual,     tcOperator);
  FCategories.AddOrSetValue(tkLess,         tcOperator);
  FCategories.AddOrSetValue(tkGreater,      tcOperator);
  FCategories.AddOrSetValue(tkLessEqual,    tcOperator);
  FCategories.AddOrSetValue(tkGreaterEqual, tcOperator);
  FCategories.AddOrSetValue(tkAssign,       tcOperator);
  FCategories.AddOrSetValue(tkPlusAssign,   tcOperator);
  FCategories.AddOrSetValue(tkMinusAssign,  tcOperator);
  FCategories.AddOrSetValue(tkStarAssign,   tcOperator);
  FCategories.AddOrSetValue(tkSlashAssign,  tcOperator);
  FCategories.AddOrSetValue(tkCaret,        tcOperator);
  FCategories.AddOrSetValue(tkPipe,         tcOperator);
  FCategories.AddOrSetValue(tkAmpersand,    tcOperator);

  // Delimiters
  FCategories.AddOrSetValue(tkColon,        tcDelimiter);
  FCategories.AddOrSetValue(tkSemicolon,    tcDelimiter);
  FCategories.AddOrSetValue(tkComma,        tcDelimiter);
  FCategories.AddOrSetValue(tkDot,          tcDelimiter);
  FCategories.AddOrSetValue(tkDotDot,       tcDelimiter);
  FCategories.AddOrSetValue(tkEllipsis,     tcDelimiter);
  FCategories.AddOrSetValue(tkLParen,       tcDelimiter);
  FCategories.AddOrSetValue(tkRParen,       tcDelimiter);
  FCategories.AddOrSetValue(tkLBracket,     tcDelimiter);
  FCategories.AddOrSetValue(tkRBracket,     tcDelimiter);

  // Literals
  FCategories.AddOrSetValue(tkIntLiteral,     tcLiteral);
  FCategories.AddOrSetValue(tkFloatLiteral,   tcLiteral);
  FCategories.AddOrSetValue(tkStringLiteral,  tcLiteral);
  FCategories.AddOrSetValue(tkWStringLiteral, tcLiteral);

  // Special
  FCategories.AddOrSetValue(tkIdentifier, tcIdentifier);
  FCategories.AddOrSetValue(tkDirective,  tcDirective);
  FCategories.AddOrSetValue(tkEOF,        tcSpecial);
  FCategories.AddOrSetValue(tkUnknown,    tcSpecial);
end;

function TWklLexer.CurrentChar(): Char;
begin
  if FPos <= Length(FSource) then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TWklLexer.PeekChar(): Char;
begin
  Result := PeekCharAt(1);
end;

function TWklLexer.PeekCharAt(const AOffset: Int64): Char;
var
  LIdx: UInt64;
begin
  if AOffset >= 0 then
    LIdx := FPos + UInt64(AOffset)
  else
  begin
    if UInt64(-AOffset) > FPos then
    begin
      Result := #0;
      Exit;
    end;
    LIdx := FPos - UInt64(-AOffset);
  end;
  if (LIdx >= 1) and (LIdx <= UInt64(Length(FSource))) then
    Result := FSource[LIdx]
  else
    Result := #0;
end;

procedure TWklLexer.Advance();
var
  LCh: Char;
begin
  if FPos > Length(FSource) then
    Exit;
  LCh := FSource[FPos];
  Inc(FPos);
  if LCh = #10 then
  begin
    Inc(FLine);
    FCol := 1;
  end
  else if LCh <> #13 then
    Inc(FCol);
end;

function TWklLexer.IsAtSourceEnd(): Boolean;
begin
  Result := FPos > Length(FSource);
end;

function TWklLexer.MakeLocation(const AStartLine: UInt64;
  const AStartCol: UInt64): TSourceRange;
begin
  Result.Clear();
  Result.Filename := FFilename;
  Result.StartLine := AStartLine;
  Result.StartColumn := AStartCol;
  Result.EndLine := FLine;
  Result.EndColumn := FCol - 1;
end;

function TWklLexer.DoCollectTrivia(): string;
begin
  Result := '';
  while not IsAtSourceEnd() do
  begin
    if CharInSet(CurrentChar(), [' ', #9, #13, #10]) then
    begin
      Result := Result + CurrentChar();
      Advance();
    end
    else if (CurrentChar() = '/') and (PeekChar() = '/') then
      DoScanLineComment(Result)
    else if (CurrentChar() = '/') and (PeekChar() = '*') then
      DoScanBlockComment(Result)
    else
      Break;
  end;
end;

procedure TWklLexer.DoScanLineComment(var ATrivia: string);
begin
  while not IsAtSourceEnd() and (CurrentChar() <> #10) do
  begin
    ATrivia := ATrivia + CurrentChar();
    Advance();
  end;
  if not IsAtSourceEnd() then
  begin
    ATrivia := ATrivia + CurrentChar();
    Advance();
  end;
end;

procedure TWklLexer.DoScanBlockComment(var ATrivia: string);
var
  LDepth: Integer;
  LStartLine: UInt64;
  LStartCol: UInt64;
begin
  LStartLine := FLine;
  LStartCol := FCol;
  LDepth := 1;

  // Consume /*
  ATrivia := ATrivia + CurrentChar();
  Advance();
  ATrivia := ATrivia + CurrentChar();
  Advance();

  while not IsAtSourceEnd() and (LDepth > 0) do
  begin
    if (CurrentChar() = '/') and (PeekChar() = '*') then
    begin
      Inc(LDepth);
      ATrivia := ATrivia + CurrentChar();
      Advance();
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end
    else if (CurrentChar() = '*') and (PeekChar() = '/') then
    begin
      Dec(LDepth);
      ATrivia := ATrivia + CurrentChar();
      Advance();
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end
    else
    begin
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end;
  end;

  if LDepth > 0 then
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, WKL_ERR_LEX_002,
      RSLexUnterminatedComment);
end;

function TWklLexer.DoProcessEscapeSeq(): Char;
var
  LHexStr: string;
  LHexVal: Integer;
begin
  Result := #0;

  if IsAtSourceEnd() then
  begin
    FErrors.Add(FFilename, FLine, FCol, esError, WKL_ERR_LEX_005,
      RSLexInvalidEscape, ['EOF']);
    Exit;
  end;

  if CurrentChar() = 'n' then
  begin
    Result := #10;
    Advance();
  end
  else if CurrentChar() = 't' then
  begin
    Result := #9;
    Advance();
  end
  else if CurrentChar() = 'r' then
  begin
    Result := #13;
    Advance();
  end
  else if CurrentChar() = '0' then
  begin
    Result := #0;
    Advance();
  end
  else if CurrentChar() = '\' then
  begin
    Result := '\';
    Advance();
  end
  else if CurrentChar() = '''' then
  begin
    Result := '''';
    Advance();
  end
  else if CurrentChar() = '"' then
  begin
    Result := '"';
    Advance();
  end
  else if CurrentChar() = 'x' then
  begin
    // \xHH -- two hex digits required
    Advance(); // skip 'x'
    if IsAtSourceEnd() or not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, FLine, FCol, esError, WKL_ERR_LEX_005,
        RSLexInvalidEscape, ['x']);
      Exit;
    end;
    LHexStr := CurrentChar();
    Advance();
    if IsAtSourceEnd() or not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, FLine, FCol, esError, WKL_ERR_LEX_005,
        RSLexInvalidEscape, ['x' + LHexStr]);
      Exit;
    end;
    LHexStr := LHexStr + CurrentChar();
    Advance();
    if TryStrToInt('$' + LHexStr, LHexVal) then
      Result := Char(LHexVal)
    else
      FErrors.Add(FFilename, FLine, FCol, esError, WKL_ERR_LEX_005,
        RSLexInvalidEscape, ['x' + LHexStr]);
  end
  else
  begin
    FErrors.Add(FFilename, FLine, FCol, esError, WKL_ERR_LEX_005,
      RSLexInvalidEscape, [CurrentChar()]);
    Advance();
  end;
end;

function TWklLexer.DoScanIdentifier(): TWklToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LText: string;
  LLower: string;
  LKind: TWklTokenKind;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  while not IsAtSourceEnd() and
    CharInSet(CurrentChar(), ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Advance();

  LText := FSource.Substring(LStart - 1, FPos - LStart);
  LLower := LText.ToLower();

  if FKeywords.TryGetValue(LLower, LKind) then
  begin
    Result.Kind := LKind;
    Result.TokenText := LLower;
    Result.Category := FCategories[LKind];
  end
  else
  begin
    Result.Kind := tkIdentifier;
    Result.TokenText := LText;
    Result.Category := tcIdentifier;
  end;

  Result.RawText := LText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

function TWklLexer.DoScanNumber(): TWklToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LText: string;
  LParseText: string;
  LFloatVal: Double;
  LUIntVal: UInt64;
  LIsFloat: Boolean;
  LIsHex: Boolean;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;
  LIsFloat := False;
  LIsHex := False;

  // Check for hex: 0x or 0X
  if (CurrentChar() = '0') and CharInSet(PeekChar(), ['x', 'X']) then
  begin
    LIsHex := True;
    Advance(); // 0
    Advance(); // x
    if IsAtSourceEnd() or
      not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, WKL_ERR_LEX_004,
        RSLexInvalidHexLiteral);
      LText := FSource.Substring(LStart - 1, FPos - LStart);
      Result.Kind := tkUnknown;
      Result.TokenText := LText;
      Result.RawText := LText;
      Result.Location := MakeLocation(LStartLine, LStartCol);
      Result.Category := tcSpecial;
      Exit;
    end;
    while not IsAtSourceEnd() and
      CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) do
      Advance();
  end
  else
  begin
    // Decimal digits
    while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
      Advance();

    // Check for decimal point (not '..' range operator)
    if not IsAtSourceEnd() and (CurrentChar() = '.') and (PeekChar() <> '.') then
    begin
      LIsFloat := True;
      Advance();
      while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
        Advance();
    end;

    // Check for exponent
    if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['e', 'E']) then
    begin
      LIsFloat := True;
      Advance();
      if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['+', '-']) then
        Advance();
      while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
        Advance();
    end;

    // Check for f/F suffix (always makes it float)
    if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['f', 'F']) then
    begin
      LIsFloat := True;
      Advance();
    end;
  end;

  LText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := LText;
  Result.Location := MakeLocation(LStartLine, LStartCol);

  if LIsFloat then
  begin
    Result.Kind := tkFloatLiteral;
    Result.Category := tcLiteral;
    Result.TokenText := LText;
    // Strip f/F suffix for parsing
    LParseText := LText;
    if LParseText.EndsWith('f', True) then
      LParseText := LParseText.Substring(0, LParseText.Length - 1);
    if TryStrToFloat(LParseText, LFloatVal, TFormatSettings.Invariant) then
      Result.LiteralValue := TValue.From<Double>(LFloatVal)
    else
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, WKL_ERR_LEX_006,
        RSLexInvalidNumber);
      Exit;
    end;
  end
  else
  begin
    Result.Kind := tkIntLiteral;
    Result.Category := tcLiteral;
    Result.TokenText := LText;
    if LIsHex then
      LParseText := '$' + LText.Substring(2)
    else
      LParseText := LText;
    if TryStrToUInt64(LParseText, LUIntVal) then
      Result.LiteralValue := TValue.From<UInt64>(LUIntVal)
    else
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, WKL_ERR_LEX_006,
        RSLexInvalidNumber);
      Exit;
    end;
  end;
end;

function TWklLexer.DoScanStringLiteral(): TWklToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LContent: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume opening "

  LContent := '';
  while not IsAtSourceEnd() and (CurrentChar() <> '"') and (CurrentChar() <> #10) do
  begin
    if CurrentChar() = '\' then
    begin
      Advance(); // skip backslash
      LContent := LContent + DoProcessEscapeSeq();
    end
    else
    begin
      LContent := LContent + CurrentChar();
      Advance();
    end;
  end;

  if IsAtSourceEnd() or (CurrentChar() = #10) then
  begin
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, WKL_ERR_LEX_001,
      RSLexUnterminatedString);
    Result.Kind := tkUnknown;
    Result.Category := tcSpecial;
    Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
    Result.RawText := Result.TokenText;
    Result.Location := MakeLocation(LStartLine, LStartCol);
    Exit;
  end;

  Advance(); // consume closing "

  Result.Kind := tkStringLiteral;
  Result.Category := tcLiteral;
  Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := Result.TokenText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
  Result.LiteralValue := TValue.From<string>(LContent);
end;

function TWklLexer.DoScanWStringLiteral(): TWklToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LContent: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume 'w'
  Advance(); // consume opening "

  LContent := '';
  while not IsAtSourceEnd() and (CurrentChar() <> '"') and (CurrentChar() <> #10) do
  begin
    if CurrentChar() = '\' then
    begin
      Advance();
      LContent := LContent + DoProcessEscapeSeq();
    end
    else
    begin
      LContent := LContent + CurrentChar();
      Advance();
    end;
  end;

  if IsAtSourceEnd() or (CurrentChar() = #10) then
  begin
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, WKL_ERR_LEX_001,
      RSLexUnterminatedString);
    Result.Kind := tkUnknown;
    Result.Category := tcSpecial;
    Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
    Result.RawText := Result.TokenText;
    Result.Location := MakeLocation(LStartLine, LStartCol);
    Exit;
  end;

  Advance(); // consume closing "

  Result.Kind := tkWStringLiteral;
  Result.Category := tcLiteral;
  Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := Result.TokenText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
  Result.LiteralValue := TValue.From<string>(LContent);
end;

function TWklLexer.DoScanDirective(): TWklToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LDirectiveName: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume '@'

  LDirectiveName := '';
  while not IsAtSourceEnd() and
    CharInSet(CurrentChar(), ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    LDirectiveName := LDirectiveName + CurrentChar();
    Advance();
  end;

  Result.Kind := tkDirective;
  Result.Category := tcDirective;
  Result.TokenText := LDirectiveName.ToLower();
  Result.RawText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

function TWklLexer.DoScanOperator(): TWklToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LCh: Char;
  LNext: Char;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LCh := CurrentChar();
  LNext := PeekChar();

  // Multi-character operators first
  if (LCh = ':') and (LNext = '=') then
  begin
    Result.Kind := tkAssign;
    Result.TokenText := ':=';
    Advance(); Advance();
  end
  else if (LCh = '+') and (LNext = '=') then
  begin
    Result.Kind := tkPlusAssign;
    Result.TokenText := '+=';
    Advance(); Advance();
  end
  else if (LCh = '-') and (LNext = '=') then
  begin
    Result.Kind := tkMinusAssign;
    Result.TokenText := '-=';
    Advance(); Advance();
  end
  else if (LCh = '*') and (LNext = '=') then
  begin
    Result.Kind := tkStarAssign;
    Result.TokenText := '*=';
    Advance(); Advance();
  end
  else if (LCh = '/') and (LNext = '=') then
  begin
    Result.Kind := tkSlashAssign;
    Result.TokenText := '/=';
    Advance(); Advance();
  end
  else if (LCh = '<') and (LNext = '>') then
  begin
    Result.Kind := tkNotEqual;
    Result.TokenText := '<>';
    Advance(); Advance();
  end
  else if (LCh = '<') and (LNext = '=') then
  begin
    Result.Kind := tkLessEqual;
    Result.TokenText := '<=';
    Advance(); Advance();
  end
  else if (LCh = '>') and (LNext = '=') then
  begin
    Result.Kind := tkGreaterEqual;
    Result.TokenText := '>=';
    Advance(); Advance();
  end
  // ... (triple dot) must be checked before .. (double dot)
  else if (LCh = '.') and (LNext = '.') and (PeekCharAt(2) = '.') then
  begin
    Result.Kind := tkEllipsis;
    Result.TokenText := '...';
    Advance(); Advance(); Advance();
  end
  else if (LCh = '.') and (LNext = '.') then
  begin
    Result.Kind := tkDotDot;
    Result.TokenText := '..';
    Advance(); Advance();
  end

  // Single-character operators and delimiters
  else
  begin
    Advance();
    if LCh = '+' then
    begin
      Result.Kind := tkPlus;
      Result.TokenText := '+';
    end
    else if LCh = '-' then
    begin
      Result.Kind := tkMinus;
      Result.TokenText := '-';
    end
    else if LCh = '*' then
    begin
      Result.Kind := tkStar;
      Result.TokenText := '*';
    end
    else if LCh = '/' then
    begin
      Result.Kind := tkSlash;
      Result.TokenText := '/';
    end
    else if LCh = '=' then
    begin
      Result.Kind := tkEqual;
      Result.TokenText := '=';
    end
    else if LCh = '<' then
    begin
      Result.Kind := tkLess;
      Result.TokenText := '<';
    end
    else if LCh = '>' then
    begin
      Result.Kind := tkGreater;
      Result.TokenText := '>';
    end
    else if LCh = '^' then
    begin
      Result.Kind := tkCaret;
      Result.TokenText := '^';
    end
    else if LCh = '|' then
    begin
      Result.Kind := tkPipe;
      Result.TokenText := '|';
    end
    else if LCh = '&' then
    begin
      Result.Kind := tkAmpersand;
      Result.TokenText := '&';
    end
    else if LCh = ':' then
    begin
      Result.Kind := tkColon;
      Result.TokenText := ':';
    end
    else if LCh = ';' then
    begin
      Result.Kind := tkSemicolon;
      Result.TokenText := ';';
    end
    else if LCh = ',' then
    begin
      Result.Kind := tkComma;
      Result.TokenText := ',';
    end
    else if LCh = '.' then
    begin
      Result.Kind := tkDot;
      Result.TokenText := '.';
    end
    else if LCh = '(' then
    begin
      Result.Kind := tkLParen;
      Result.TokenText := '(';
    end
    else if LCh = ')' then
    begin
      Result.Kind := tkRParen;
      Result.TokenText := ')';
    end
    else if LCh = '[' then
    begin
      Result.Kind := tkLBracket;
      Result.TokenText := '[';
    end
    else if LCh = ']' then
    begin
      Result.Kind := tkRBracket;
      Result.TokenText := ']';
    end
    else
    begin
      Result.Kind := tkUnknown;
      Result.TokenText := LCh;
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, WKL_ERR_LEX_003,
        RSLexInvalidCharacter, [LCh]);
    end;
  end;

  Result.RawText := Result.TokenText;
  Result.Category := FCategories[Result.Kind];
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

function TWklLexer.DoScanToken(const ATrivia: string): TWklToken;
var
  LCh: Char;
begin
  LCh := CurrentChar();

  // Identifier or keyword (check for w"..." wstring first)
  if CharInSet(LCh, ['A'..'Z', 'a'..'z', '_']) then
  begin
    if (LCh = 'w') and (PeekChar() = '"') then
      Result := DoScanWStringLiteral()
    else
      Result := DoScanIdentifier();
  end
  // Numeric literal
  else if CharInSet(LCh, ['0'..'9']) then
    Result := DoScanNumber()
  // String literal
  else if LCh = '"' then
    Result := DoScanStringLiteral()
  // Directive
  else if LCh = '@' then
    Result := DoScanDirective()
  // Operator or delimiter
  else
    Result := DoScanOperator();

  Result.LeadingTrivia := ATrivia;
end;

function TWklLexer.TokenizeFile(const AFilename: string;
  const AAppend: Boolean): Boolean;
var
  LSource: string;
  LFilename: string;
begin
  Result := False;

  LFilename := TPath.ChangeExtension(TUtils.ResolvePath(AFilename), WKL_SRCFILE_EXT);

  if not TFile.Exists(LFilename) then
  begin
    FErrors.Add(esFatal, WKL_ERR_LEX_009, RSFatalFileNotFound, [LFilename]);
    Exit;
  end;

  try
    LSource := TFile.ReadAllText(LFilename);
  except
    on E: Exception do
    begin
      FErrors.Add(esFatal, WKL_ERR_LEX_010, RSFatalFileReadError, [LFilename, E.Message]);
      Exit;
    end;
  end;

  Result := TokenizeString(LSource, LFilename, AAppend);
end;

function TWklLexer.TokenizeString(const ASource: string;
  const AFilename: string; const AAppend: Boolean): Boolean;
var
  LTrivia: string;
  LToken: TWklToken;
begin
  // Reset scanning state for the new source
  FSource := ASource;
  FFilename := AFilename;
  FPos := 1;
  FLine := 1;
  FCol := 1;

  if not AAppend then
  begin
    FTokenIndex := 0;
    FTokens.Clear();
  end
  else
  begin
    // Position cursor at the start of newly appended tokens
    FTokenIndex := UInt64(FTokens.Count);
  end;

  while not IsAtSourceEnd() do
  begin
    LTrivia := DoCollectTrivia();
    if IsAtSourceEnd() then
    begin
      // Trailing trivia goes on the EOF token
      LToken.Clear();
      LToken.Kind := tkEOF;
      LToken.TokenText := '';
      LToken.RawText := '';
      LToken.LeadingTrivia := LTrivia;
      LToken.Location := MakeLocation(FLine, FCol);
      LToken.Category := tcSpecial;
      FTokens.Add(LToken);
      Result := not FErrors.HasErrors();
      Exit;
    end;
    LToken := DoScanToken(LTrivia);
    FTokens.Add(LToken);
  end;

  // Ensure EOF token always present
  LToken.Clear();
  LToken.Kind := tkEOF;
  LToken.TokenText := '';
  LToken.RawText := '';
  LToken.LeadingTrivia := '';
  LToken.Location := MakeLocation(FLine, FCol);
  LToken.Category := tcSpecial;
  FTokens.Add(LToken);

  Result := not FErrors.HasErrors();
end;

function TWklLexer.CurrentToken(): TWklToken;
begin
  if FTokenIndex < FTokens.Count then
    Result := FTokens[FTokenIndex]
  else
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Result.Category := tcSpecial;
  end;
end;

function TWklLexer.NextToken(): TWklToken;
begin
  if FTokenIndex < FTokens.Count - 1 then
    Inc(FTokenIndex);
  Result := CurrentToken();
end;

function TWklLexer.PeekToken(): TWklToken;
begin
  Result := PeekAt(1);
end;

function TWklLexer.PeekAt(const AOffset: Int64): TWklToken;
var
  LIdx: UInt64;
begin
  if AOffset >= 0 then
    LIdx := FTokenIndex + UInt64(AOffset)
  else
  begin
    if UInt64(-AOffset) > FTokenIndex then
    begin
      Result.Clear();
      Result.Kind := tkEOF;
      Result.Category := tcSpecial;
      Exit;
    end;
    LIdx := FTokenIndex - UInt64(-AOffset);
  end;
  if LIdx < UInt64(FTokens.Count) then
    Result := FTokens[LIdx]
  else
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Result.Category := tcSpecial;
  end;
end;

function TWklLexer.Match(const AKind: TWklTokenKind): Boolean;
begin
  Result := CurrentToken().Kind = AKind;
  if Result then
    NextToken();
end;

function TWklLexer.Expect(const AKind: TWklTokenKind): TWklToken;
var
  LExpected: string;
  LPair: TPair<string, TWklTokenKind>;
begin
  Result := CurrentToken();
  if Result.Kind <> AKind then
  begin
    LExpected := '';
    for LPair in FKeywords do
    begin
      if LPair.Value = AKind then
      begin
        LExpected := '''' + LPair.Key + '''';
        Break;
      end;
    end;
    if LExpected = '' then
      LExpected := 'token';
    FErrors.Add(Result.Location, esError, WKL_ERR_LEX_008,
      RSLexExpected, [LExpected, Result.RawText]);
  end
  else
    NextToken();
end;

function TWklLexer.IsAtEnd(): Boolean;
begin
  Result := CurrentToken().Kind = tkEOF;
end;

function TWklLexer.IsDataType(const AKind: TWklTokenKind): Boolean;
var
  LCategory: TWklTokenCategory;
begin
  Result := FCategories.TryGetValue(AKind, LCategory) and
    (LCategory = tcPrimitive);
end;

function TWklLexer.IsOperator(const AKind: TWklTokenKind): Boolean;
var
  LCategory: TWklTokenCategory;
begin
  Result := FCategories.TryGetValue(AKind, LCategory) and
    (LCategory = tcOperator);
end;

function TWklLexer.GetTargetType(const AKind: TWklTokenKind): string;
begin
  if not FTargetTypes.TryGetValue(AKind, Result) then
    Result := '';
end;

function TWklLexer.GetCategory(const AKind: TWklTokenKind): TWklTokenCategory;
begin
  if not FCategories.TryGetValue(AKind, Result) then
    Result := tcSpecial;
end;

function TWklLexer.GetRegisteredWords(
  const ACategory: TWklTokenCategory): TWklStringArray;
var
  LPair: TPair<string, TWklTokenKind>;
  LCat: TWklTokenCategory;
  LList: TList<string>;
begin
  LList := TList<string>.Create();
  try
    for LPair in FKeywords do
    begin
      if FCategories.TryGetValue(LPair.Value, LCat) and (LCat = ACategory) then
        LList.Add(LPair.Key);
    end;
    LList.Sort();
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

function TWklLexer.TokenCount(): UInt64;
begin
  Result := FTokens.Count;
end;

function TWklLexer.GetTokens(): TWklTokens;
begin
  Result := FTokens;
end;

function TWklLexer.ToSource(): string;
var
  LBuilder: TStringBuilder;
  LIdx: Int64;
begin
  LBuilder := TStringBuilder.Create();
  try
    for LIdx := 0 to FTokens.Count - 1 do
    begin
      LBuilder.Append(FTokens[LIdx].LeadingTrivia);
      LBuilder.Append(FTokens[LIdx].RawText);
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

end.
