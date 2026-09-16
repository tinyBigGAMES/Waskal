{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.Emitter.pas

  Wasm64 text emitter -- produces .wat (WebAssembly text format) from a
  semantically analysed OOP AST. Reads ONLY fields written by the semantic
  pass. Output-construction state (data segments, labels, temps, source map)
  is the only legitimate emitter state; program facts live in the AST.
===============================================================================}
unit Waskal.Emitter;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  StdApp.Base,
  StdApp.Utils,
  Waskal.Common,
  Waskal.Lexer,
  Waskal.AST;

const
  // Error codes
  WKL_DATA_START = 1024;
  WKL_ERR_EMT_001 = 'EMT001';
  WKL_ERR_EMT_002 = 'EMT002';
  WKL_ERR_EMT_003 = 'EMT003';
  WKL_ERR_EMT_004 = 'EMT004';

type
  { TWklRoutineVisitor }
  // Callback for DoWalkTableRoutines: invoked once per table entry, in order
  TWklRoutineVisitor = reference to procedure(const ARoutine: TWklRoutineDeclNode);

  { TWklEmitter }
  TWklEmitter = class(TBaseObject)
  private
    FModule: TWklModuleNode;
    FLexer: TWklLexer;
    FOutput: TStringBuilder;
    FDataOffset: Int64;
    FDataSegments: TStringList;
    FFunctions: TList<TWklEmittedFunc>;
    FLocalDecls: TStringBuilder;
    FBody: TStringBuilder;
    FBodyMap: TWklSourceMap;
    FBreakLabels: TStringList;
    FContinueLabels: TStringList;
    FStringTemps: TStringList;
    // Variadic pack temps (`_vap_N`) built for calls in the current
    // statement; freed at statement end like string temps
    FPackTemps: TStringList;
    // Aggregate sret temps (`_atmp_N`) -- heap blocks allocated before
    // sret calls, freed at statement end like string temps
    FAggTemps: TStringList;
    FAggTempCounter: Integer;
    FTempSeq: Integer;
    FDeclaredLocals: TStringList;
    // Declaring AST node -> wasm local name for the current function.
    // Output-construction state; the AST still owns what locals exist.
    FLocalNames: TDictionary<TWklNode, string>;
    FCurrentRoutine: TWklRoutineDeclNode;
    FIndent: Integer;
    FBodyIndent: Integer;
    FLabelSeq: Integer;
    FSourceMap: TWklSourceMap;
    FCurrentRange: TSourceRange;
    FWatLine: Integer;
    FRuntimeWat: string;
    FOptimizeLevel: Integer;
    FNeedMemShells: Boolean;

    function IndentStr(): string;
    function BodyIndentStr(): string;
    {$HINTS OFF}
    procedure W(const AText: string); overload;
    procedure W(const AFmt: string; const AArgs: array of const); overload;
    {$HINTS ON}
    procedure WLn(const AText: string); overload;
    procedure WLn(const AFmt: string; const AArgs: array of const); overload;
    procedure WLn(); overload;
    procedure BLn(const AText: string); overload;
    procedure BLn(const AFmt: string; const AArgs: array of const); overload;
    procedure DLn(const AText: string); overload;
    procedure DLn(const AFmt: string; const AArgs: array of const); overload;
    procedure DoAppendRawLines(const AText: string);
    procedure DoAppendFuncLines(const AFunc: TWklEmittedFunc);
    procedure Indent();
    procedure Dedent();
    procedure SetBodyIndent(const ALevel: Integer);
    {$HINTS OFF}
    procedure BodyIndent();
    procedure BodyDedent();
    {$HINTS ON}

    function DoGetPrimitiveName(const ATypeNode: TWklNode): string;
    function DoResolveTypeDef(const ATypeRef: TWklNode): TWklNode;
    function DoGetTypeByteSize(const ATypeNode: TWklNode): Int64;
    function DoMapWasmType(const ATypeNode: TWklNode): string;
    function DoIsFloatType(const ATypeNode: TWklNode): Boolean;
    function DoIsUnsignedType(const ATypeNode: TWklNode): Boolean;
    function DoIsStringType(const ATypeNode: TWklNode): Boolean;
    function DoIsSetType(const ATypeNode: TWklNode): Boolean;
    function DoIsAggregateType(const ATypeNode: TWklNode): Boolean;
    function DoIsMemHomed(const ADecl: TWklNode): Boolean;
    function DoGetStrCompareFunc(const ATypeNode: TWklNode): string;
    function DoMapMemLoadOp(const ATypeNode: TWklNode): string;
    function DoMapMemStoreOp(const ATypeNode: TWklNode): string;

    function DoAllocData(const ABytes: TBytes): Int64;
    function DoAllocString(const AValue: string): Int64;
    function DoMangledName(const ARoutine: TWklRoutineDeclNode): string;
    function DoGlobalName(const ADecl: TWklNode): string;

    // Decl-keyed wasm locals
    function DoDeclareLocal(const ADecl: TWklNode; const AWasmType: string): string;
    function DoLocalNameOf(const ADecl: TWklNode): string;
    function DoDeclOf(const ANode: TWklNode): TWklNode;
    function DoVarGet(const ANode: TWklNode): string;
    // Store: takes the value expression text, returns a COMPLETE statement.
    // Mem-homed decls become a memory store through the pointer slot.
    function DoVarSet(const ANode: TWklNode; const AValue: string): string;
    function DoVarSetDecl(const ADecl: TWklNode; const AValue: string): string;
    procedure DoEmitVarInit(const ADecl: TWklVarDeclNode);
    function DoGetDesignatorName(const ANode: TWklNode): string;
    function DoAllocStringTemp(const AExpr: string): string;
    function DoAllocAggTemp(const ASize: Int64): string;
    procedure DoEmitAggTempCleanup();
    procedure DoEmitStringTempCleanup();
    function DoTypeIdOf(const AType: TWklNode): Int64;
    function DoWidenToSlot(const AExpr: string; const AType: TWklNode): string;
    function DoNarrowFromSlot(const AExpr: string; const AType: TWklNode): string;
    function DoEmitVarArgsPack(const AArgs: TWklNodeList;
      const AFixedCount: Integer): string;
    function DoEmitVarArgsIntrinsic(const ANode: TWklIntrinsicNode): string;

    procedure DoEmitGlobalConst(const ANode: TWklConstDeclNode);
    function DoIsStringConst(const ANode: TWklConstDeclNode): Boolean;
    procedure DoEmitRuntimeConstInit(const ADecls: TWklNodeList);
    procedure DoEmitGlobalVar(const ANode: TWklVarDeclNode);

    procedure DoEmitLocalVars(const ARoutine: TWklRoutineDeclNode);
    procedure DoEmitLocalCleanup(const ARoutine: TWklRoutineDeclNode);
    procedure DoEmitVarListCleanup(const AVars: TWklNodeList);
    procedure DoEmitGlobalCleanup(const ADecls: TWklNodeList);
    procedure DoEmitGlobalAlloc(const ADecls: TWklNodeList);
    procedure DoEmitReleaseRecordFields(const ABase: string;
      const ATypeDef: TWklNode);
    procedure DoEmitAddRefRecordFields(const ABase: string;
      const ATypeDef: TWklNode);
    procedure DoEmitModuleBlock(const ABlock: TWklBlockNode;
      const AFuncName: string);
    procedure DoEmitRoutine(const ANode: TWklRoutineDeclNode);

    function DoEmitExpression(const ANode: TWklNode): string;
    function DoEmitExprAsI64(const ANode: TWklNode): string;
    function DoEmitExprAsF64(const ANode: TWklNode): string;
    function DoEmitBinaryExpr(const ANode: TWklBinaryExprNode): string;
    function DoEmitUnaryExpr(const ANode: TWklUnaryExprNode): string;
    function DoEmitCallExpr(const ANode: TWklCallExprNode): string;
    function DoEmitDotAccess(const ANode: TWklDotAccessNode): string;
    function DoEmitIndexAddress(const ANode: TWklIndexAccessNode): string;
    function DoEmitIndexAccess(const ANode: TWklIndexAccessNode): string;
    function DoEmitTypeCast(const ANode: TWklTypeCastNode): string;
    function DoEmitIntrinsic(const ANode: TWklIntrinsicNode): string;
    function DoEmitFormat(const ANode: TWklIntrinsicNode): string;
    function DoEmitFormatArg(const AChain: string; const AArgNode: TWklNode;
      const ASpec: Char; const APrec: Integer): string;

    procedure DoEmitStatementList(const AStatements: TWklNodeList);
    procedure DoEmitStatement(const ANode: TWklNode);
    procedure DoEmitAssign(const ANode: TWklAssignNode);
    function DoEmitAssignSretDirect(const ACall: TWklCallExprNode;
      const ATargetAddr: string): Boolean;
    procedure DoEmitReturn(const ANode: TWklReturnNode);
    procedure DoEmitCallStmt(const ANode: TWklCallStmtNode);
    procedure DoEmitIf(const ANode: TWklIfNode);
    procedure DoEmitWhile(const ANode: TWklWhileNode);
    procedure DoEmitFor(const ANode: TWklForNode);
    procedure DoEmitRepeat(const ANode: TWklRepeatNode);
    procedure DoEmitMatch(const ANode: TWklMatchNode);
    procedure DoEmitGuard(const ANode: TWklGuardNode);
    procedure DoEmitThrow(const ANode: TWklThrowNode);
    procedure DoEmitThrowCode(const ANode: TWklThrowCodeNode);
    procedure DoEmitPrint(const ANode: TWklPrintNode);
    procedure DoEmitAssert(const ANode: TWklAssertNode);
    procedure DoEmitRecordLiteralInto(const ANode: TWklRecordLiteralNode;
      const ABase: string; const AOffset: Int64);
    procedure DoEmitAllocInto(const ATarget: TWklNode);
    procedure DoEmitFreeInto(const ATarget: TWklNode);
    procedure DoEmitMemOp(const ANode: TWklMemOpNode);
    procedure DoEmitMemOp2(const ANode: TWklMemOp2Node);

    // Emit function bodies into FFunctions
    procedure DoEmitMemShellFuncs();
    procedure DoEmitMainBody();
    procedure DoEmitShutdownFunc();
    procedure DoEmitFrameFunc();
    procedure DoEmitTestBlocks();
    procedure DoEmitTestRegistrations();
    procedure DoEmitAllBodies();
    procedure DoLoadRuntime();

    // Function table: the ordered walk of every emitted routine. Both the
    // (elem) section and funcref literal indices derive from this one walk.
    procedure DoWalkTableRoutines(const AProc: TWklRoutineVisitor);
    function DoFuncTableIndex(const ARoutine: TWklRoutineDeclNode): Integer;
    function DoEmitFuncRef(const ADecl: TWklNode; const AName: string): string;
    function DoRoutineTypeSignature(const AType: TWklRoutineTypeNode): string;

    // Assemble final (module ...) by walking AST directly
    procedure DoAssembleImports();
    procedure DoAssembleGlobals();
    procedure DoAssembleTable();
    procedure DoAssembleExports();
    procedure DoAssemble();

  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetOptimizeLevel(const ALevel: Integer);
    function Emit(const ALexer: TWklLexer; const AModule: TWklModuleNode;
      const ASourceMap: TWklSourceMap): string;
  end;

implementation

uses
  StdApp.Resources;

{ TWklEmitter }
constructor TWklEmitter.Create();
begin
  inherited;

  FOutput := TStringBuilder.Create();
  FDataSegments := TStringList.Create();
  FFunctions := TList<TWklEmittedFunc>.Create();
  FLocalDecls := TStringBuilder.Create();
  FBody := TStringBuilder.Create();
  FBodyMap := TWklSourceMap.Create();
  FBreakLabels := TStringList.Create();
  FContinueLabels := TStringList.Create();
  FStringTemps := TStringList.Create();
  FPackTemps := TStringList.Create();
  FAggTemps := TStringList.Create();
  FDeclaredLocals := TStringList.Create();
  FLocalNames := TDictionary<TWklNode, string>.Create();
  FTempSeq := 0;
end;

destructor TWklEmitter.Destroy();
begin
  FLocalNames.Free();
  FDeclaredLocals.Free();
  FStringTemps.Free();
  FPackTemps.Free();
  FAggTemps.Free();
  FContinueLabels.Free();
  FBreakLabels.Free();
  FBodyMap.Free();
  FBody.Free();
  FLocalDecls.Free();
  FFunctions.Free();
  FDataSegments.Free();
  FOutput.Free();

  inherited;
end;

procedure TWklEmitter.SetOptimizeLevel(const ALevel: Integer);
begin
  FOptimizeLevel := ALevel;
end;

function TWklEmitter.IndentStr(): string;
begin
  Result := StringOfChar(' ', FIndent * 2);
end;

function TWklEmitter.BodyIndentStr(): string;
begin
  Result := StringOfChar(' ', FBodyIndent * 2);
end;

procedure TWklEmitter.W(const AText: string);
begin
  FOutput.Append(IndentStr() + AText);
end;

procedure TWklEmitter.W(const AFmt: string; const AArgs: array of const);
begin
  FOutput.Append(IndentStr() + Format(AFmt, AArgs));
end;

procedure TWklEmitter.WLn(const AText: string);
begin
  FOutput.AppendLine(IndentStr() + AText);
  if FSourceMap <> nil then
    FSourceMap.Add(FCurrentRange);
end;

procedure TWklEmitter.WLn(const AFmt: string; const AArgs: array of const);
begin
  FOutput.AppendLine(IndentStr() + Format(AFmt, AArgs));
  if FSourceMap <> nil then
    FSourceMap.Add(FCurrentRange);
end;

procedure TWklEmitter.WLn();
begin
  FOutput.AppendLine('');
  if FSourceMap <> nil then
    FSourceMap.Add(Default (TSourceRange));
end;

procedure TWklEmitter.BLn(const AText: string);
begin
  FBody.AppendLine(BodyIndentStr() + AText);
  FBodyMap.Add(FCurrentRange);
end;

procedure TWklEmitter.BLn(const AFmt: string; const AArgs: array of const);
begin
  FBody.AppendLine(BodyIndentStr() + Format(AFmt, AArgs));
  FBodyMap.Add(FCurrentRange);
end;

procedure TWklEmitter.DLn(const AText: string);
begin
  FLocalDecls.AppendLine(BodyIndentStr() + AText);
  FBodyMap.Add(FCurrentRange);
end;

procedure TWklEmitter.DLn(const AFmt: string; const AArgs: array of const);
begin
  FLocalDecls.AppendLine(BodyIndentStr() + Format(AFmt, AArgs));
  FBodyMap.Add(FCurrentRange);
end;

procedure TWklEmitter.DoAppendRawLines(const AText: string);
var
  LLines: TArray<string>;
  I: Integer;
begin
  LLines := AText.Split([#10]);
  for I := 0 to Length(LLines) - 1 do
  begin
    FOutput.AppendLine(LLines[I].TrimRight([#13]));
    if FSourceMap <> nil then
      FSourceMap.Add(Default (TSourceRange));
  end;
end;

procedure TWklEmitter.DoAppendFuncLines(const AFunc: TWklEmittedFunc);
var
  LLines: TArray<string>;
  I: Integer;
begin
  FOutput.AppendLine(AFunc.WatText);
  LLines := AFunc.WatText.Split([#10]);
  for I := 0 to Length(LLines) - 1 do
  begin
    if I < Length(AFunc.LineMap) then
      FSourceMap.Add(AFunc.LineMap[I])
    else
      FSourceMap.Add(Default (TSourceRange));
  end;
end;

procedure TWklEmitter.Indent();
begin
  Inc(FIndent);
end;

procedure TWklEmitter.Dedent();
begin
  Dec(FIndent);
  if FIndent < 0 then
    FIndent := 0;
end;

procedure TWklEmitter.SetBodyIndent(const ALevel: Integer);
begin
  FBodyIndent := ALevel;
end;

procedure TWklEmitter.BodyIndent();
begin
  Inc(FBodyIndent);
end;

procedure TWklEmitter.BodyDedent();
begin
  Dec(FBodyIndent);
  if FBodyIndent < 0 then
    FBodyIndent := 0;
end;

function TWklEmitter.DoGetPrimitiveName(const ATypeNode: TWklNode): string;
var
  LDecl: TWklNode;
begin
  Result := '';
  if ATypeNode = nil then
    Exit;
  if ATypeNode is TWklTypeRefNode then
  begin
    if TWklTypeRefNode(ATypeNode).ResolvedDecl = nil then
      Exit(TWklTypeRefNode(ATypeNode).Name);
    LDecl := TWklTypeRefNode(ATypeNode).ResolvedDecl;
    if (LDecl is TWklTypeRefNode) and (TWklTypeRefNode(LDecl).ResolvedDecl = nil)
    then
      Exit(TWklTypeRefNode(LDecl).Name);
    if LDecl is TWklTypeDeclNode then
      Exit(DoGetPrimitiveName(TWklTypeDeclNode(LDecl).TypeDef));
  end;
  if ATypeNode is TWklTypeDeclNode then
    Exit(DoGetPrimitiveName(TWklTypeDeclNode(ATypeNode).TypeDef));
end;

function TWklEmitter.DoResolveTypeDef(const ATypeRef: TWklNode): TWklNode;
var
  LDecl: TWklNode;
begin
  Result := ATypeRef;
  if ATypeRef = nil then
    Exit;
  if ATypeRef is TWklTypeRefNode then
  begin
    LDecl := TWklTypeRefNode(ATypeRef).ResolvedDecl;
    if LDecl = nil then
      Exit(ATypeRef);
    if LDecl is TWklTypeDeclNode then
      Exit(TWklTypeDeclNode(LDecl).TypeDef);
    Exit(LDecl);
  end;
  if ATypeRef is TWklTypeDeclNode then
    Exit(TWklTypeDeclNode(ATypeRef).TypeDef);
end;

function TWklEmitter.DoGetTypeByteSize(const ATypeNode: TWklNode): Int64;
var
  LName: string;
  LDef: TWklNode;
  LDecl: TWklNode;
begin
  if ATypeNode = nil then
    Exit(8);
  LName := DoGetPrimitiveName(ATypeNode);
  if LName <> '' then
  begin
    if (LName = 'int8') or (LName = 'uint8') or (LName = 'char') or
      (LName = 'bool') then
      Exit(1)
    else if (LName = 'int16') or (LName = 'uint16') or (LName = 'wchar') then
      Exit(2)
    else if (LName = 'int32') or (LName = 'uint32') or (LName = 'float32') then
      Exit(4)
    else
      Exit(8);
  end;
  if ATypeNode is TWklTypeRefNode then
  begin
    LDecl := TWklTypeRefNode(ATypeNode).ResolvedDecl;
    if (LDecl <> nil) and (LDecl is TWklTypeDeclNode) and
      (TWklTypeDeclNode(LDecl).ByteSize > 0) then
      Exit(TWklTypeDeclNode(LDecl).ByteSize);
  end;
  if (ATypeNode is TWklTypeDeclNode) and
    (TWklTypeDeclNode(ATypeNode).ByteSize > 0) then
    Exit(TWklTypeDeclNode(ATypeNode).ByteSize);
  LDef := DoResolveTypeDef(ATypeNode);
  // Anonymous composite types carry their own size, written by semantics
  if (LDef is TWklArrayTypeNode) and (TWklArrayTypeNode(LDef).ByteSize > 0) then
    Exit(TWklArrayTypeNode(LDef).ByteSize);
  if (LDef is TWklRecordTypeNode) and (TWklRecordTypeNode(LDef).ByteSize > 0) then
    Exit(TWklRecordTypeNode(LDef).ByteSize);
  if (LDef is TWklOverlayTypeNode) and (TWklOverlayTypeNode(LDef).ByteSize > 0) then
    Exit(TWklOverlayTypeNode(LDef).ByteSize);
  if (LDef is TWklAnonRecordNode) and (TWklAnonRecordNode(LDef).ByteSize > 0) then
    Exit(TWklAnonRecordNode(LDef).ByteSize);
  if (LDef is TWklAnonOverlayNode) and (TWklAnonOverlayNode(LDef).ByteSize > 0) then
    Exit(TWklAnonOverlayNode(LDef).ByteSize);
  if LDef is TWklChoicesTypeNode then
    Exit(4);
  if LDef is TWklRoutineTypeNode then
    Exit(4);
  if LDef is TWklSetTypeNode then
    Exit(8);
  Result := 8;
end;

function TWklEmitter.DoMapWasmType(const ATypeNode: TWklNode): string;
var
  LName: string;
  LDef: TWklNode;
begin
  if ATypeNode = nil then
    Exit('i64');
  LName := DoGetPrimitiveName(ATypeNode);
  if LName <> '' then
  begin
    if (LName = 'int8') or (LName = 'int16') or (LName = 'int32') or
      (LName = 'uint8') or (LName = 'uint16') or (LName = 'uint32') or
      (LName = 'bool') or (LName = 'char') or (LName = 'wchar') then
      Exit('i32')
    else if (LName = 'int64') or (LName = 'uint64') then
      Exit('i64')
    else if LName = 'float32' then
      Exit('f32')
    else if LName = 'float64' then
      Exit('f64')
    else
      Exit('i64');
  end;
  LDef := DoResolveTypeDef(ATypeNode);
  if LDef = nil then
    Exit('i64');
  if LDef is TWklChoicesTypeNode then
    Exit('i32')
  else if LDef is TWklRoutineTypeNode then
    Exit('i32')
  else
    Result := 'i64';
end;

function TWklEmitter.DoIsFloatType(const ATypeNode: TWklNode): Boolean;
var
  LName: string;
begin
  LName := DoGetPrimitiveName(ATypeNode);
  Result := (LName = 'float32') or (LName = 'float64');
end;

function TWklEmitter.DoIsUnsignedType(const ATypeNode: TWklNode): Boolean;
var
  LName: string;
begin
  LName := DoGetPrimitiveName(ATypeNode);
  Result := (LName = 'uint8') or (LName = 'uint16') or (LName = 'uint32') or
    (LName = 'uint64');
end;

function TWklEmitter.DoIsStringType(const ATypeNode: TWklNode): Boolean;
var
  LName: string;
begin
  LName := DoGetPrimitiveName(ATypeNode);
  Result := (LName = 'string') or (LName = 'wstring');
end;

function TWklEmitter.DoIsSetType(const ATypeNode: TWklNode): Boolean;
var
  LDef: TWklNode;
begin
  LDef := DoResolveTypeDef(ATypeNode);
  Result := (LDef <> nil) and (LDef is TWklSetTypeNode);
end;

function TWklEmitter.DoIsAggregateType(const ATypeNode: TWklNode): Boolean;
var
  LDef: TWklNode;
begin
  Result := False;
  if ATypeNode = nil then
    Exit;
  LDef := DoResolveTypeDef(ATypeNode);
  // Composites live in linear memory and are represented by their address
  if (LDef is TWklRecordTypeNode) or
    (LDef is TWklOverlayTypeNode) or
    (LDef is TWklAnonRecordNode) or
    (LDef is TWklAnonOverlayNode) or
    ((LDef is TWklArrayTypeNode) and (not TWklArrayTypeNode(LDef).IsDynamic)) then
    Result := True;
end;

function TWklEmitter.DoIsMemHomed(const ADecl: TWklNode): Boolean;
begin
  Result := False;
  if not (ADecl is TWklVarDeclNode) then
    Exit;
  if not TWklVarDeclNode(ADecl).IsAddressTaken then
    Exit;
  // Composites (record, overlay, static array) are already pointers --
  // they live in linear memory by default and do not need double-alloc.
  if TWklVarDeclNode(ADecl).TypeExpr = nil then
    Exit;
  if DoIsAggregateType(TWklVarDeclNode(ADecl).TypeExpr) then
    Exit;
  Result := True;
end;

function TWklEmitter.DoGetStrCompareFunc(const ATypeNode: TWklNode): string;
begin
  if DoGetPrimitiveName(ATypeNode) = 'wstring' then
    Result := '$RT_WStrCompare'
  else
    Result := '$RT_StrCompare';
end;

function TWklEmitter.DoMapMemLoadOp(const ATypeNode: TWklNode): string;
var
  LName: string;
  LDef: TWklNode;
begin
  if ATypeNode = nil then
    Exit('i64.load');
  LName := DoGetPrimitiveName(ATypeNode);
  if LName <> '' then
  begin
    if LName = 'int8' then
      Exit('i32.load8_s')
    else if (LName = 'uint8') or (LName = 'bool') or (LName = 'char') then
      Exit('i32.load8_u')
    else if LName = 'int16' then
      Exit('i32.load16_s')
    else if (LName = 'uint16') or (LName = 'wchar') then
      Exit('i32.load16_u')
    else if (LName = 'int32') or (LName = 'uint32') then
      Exit('i32.load')
    else if (LName = 'int64') or (LName = 'uint64') then
      Exit('i64.load')
    else if LName = 'float32' then
      Exit('f32.load')
    else if LName = 'float64' then
      Exit('f64.load')
    else
      Exit('i64.load');
  end;
  LDef := DoResolveTypeDef(ATypeNode);
  if (LDef <> nil) and ((LDef is TWklChoicesTypeNode) or
    (LDef is TWklRoutineTypeNode)) then
    Exit('i32.load');
  Result := 'i64.load';
end;

function TWklEmitter.DoMapMemStoreOp(const ATypeNode: TWklNode): string;
var
  LName: string;
  LDef: TWklNode;
begin
  if ATypeNode = nil then
    Exit('i64.store');
  LName := DoGetPrimitiveName(ATypeNode);
  if LName <> '' then
  begin
    if (LName = 'int8') or (LName = 'uint8') or (LName = 'bool') or
      (LName = 'char') then
      Exit('i32.store8')
    else if (LName = 'int16') or (LName = 'uint16') or (LName = 'wchar') then
      Exit('i32.store16')
    else if (LName = 'int32') or (LName = 'uint32') then
      Exit('i32.store')
    else if (LName = 'int64') or (LName = 'uint64') then
      Exit('i64.store')
    else if LName = 'float32' then
      Exit('f32.store')
    else if LName = 'float64' then
      Exit('f64.store')
    else
      Exit('i64.store');
  end;
  LDef := DoResolveTypeDef(ATypeNode);
  if (LDef <> nil) and ((LDef is TWklChoicesTypeNode) or
    (LDef is TWklRoutineTypeNode)) then
    Exit('i32.store');
  Result := 'i64.store';
end;

function TWklEmitter.DoDeclareLocal(const ADecl: TWklNode;
  const AWasmType: string): string;
var
  LName: string;
  LSeq: Integer;
begin
  // Already materialized for this declaration: reuse, emit nothing
  if FLocalNames.TryGetValue(ADecl, Result) then
    Exit;

  // Unique wasm name: a shadowing declaration gets a numbered suffix
  LName := ADecl.Name;
  LSeq := 1;
  while FDeclaredLocals.IndexOf(LName) >= 0 do
  begin
    LName := Format('%s_%d', [ADecl.Name, LSeq]);
    Inc(LSeq);
  end;

  DLn('(local $%s %s)', [LName, AWasmType]);
  FDeclaredLocals.Add(LName);
  FLocalNames.Add(ADecl, LName);
  Result := LName;
end;

function TWklEmitter.DoLocalNameOf(const ADecl: TWklNode): string;
begin
  if (ADecl = nil) or (not FLocalNames.TryGetValue(ADecl, Result)) then
    Result := '';
end;

function TWklEmitter.DoDeclOf(const ANode: TWklNode): TWklNode;
begin
  Result := nil;
  if ANode is TWklIdentifierNode then
    Result := TWklIdentifierNode(ANode).ResolvedDecl
  else if ANode is TWklDotAccessNode then
    Result := TWklDotAccessNode(ANode).ResolvedDecl;
end;

function TWklEmitter.DoVarGet(const ANode: TWklNode): string;
var
  LLocal: string;
  LDecl: TWklNode;
  LPtrGet: string;
begin
  LDecl := DoDeclOf(ANode);
  LLocal := DoLocalNameOf(LDecl);
  if LLocal <> '' then
    LPtrGet := Format('(local.get $%s)', [LLocal])
  else
    LPtrGet := Format('(global.get $%s)', [DoGlobalName(LDecl)]);
  if DoIsMemHomed(LDecl) then
    Result := Format('(%s %s)', [DoMapMemLoadOp(TWklVarDeclNode(LDecl).TypeExpr),
      LPtrGet])
  else
    Result := LPtrGet;
end;

function TWklEmitter.DoVarSetDecl(const ADecl: TWklNode;
  const AValue: string): string;
var
  LLocal: string;
  LPtrGet: string;
begin
  if ADecl = nil then
    Exit(';; varset: nil declaration');
  LLocal := DoLocalNameOf(ADecl);
  if DoIsMemHomed(ADecl) then
  begin
    // The wasm local/global holds the pointer to the memory slot;
    // the store goes through it
    if LLocal <> '' then
      LPtrGet := Format('(local.get $%s)', [LLocal])
    else
      LPtrGet := Format('(global.get $%s)', [DoGlobalName(ADecl)]);
    Result := Format('(%s %s %s)',
      [DoMapMemStoreOp(TWklVarDeclNode(ADecl).TypeExpr), LPtrGet, AValue]);
  end
  else if LLocal <> '' then
    Result := Format('(local.set $%s %s)', [LLocal, AValue])
  else
    Result := Format('(global.set $%s %s)', [DoGlobalName(ADecl), AValue]);
end;

function TWklEmitter.DoVarSet(const ANode: TWklNode;
  const AValue: string): string;
begin
  Result := DoVarSetDecl(DoDeclOf(ANode), AValue);
end;

procedure TWklEmitter.DoEmitVarInit(const ADecl: TWklVarDeclNode);
var
  LValue: string;
begin
  LValue := DoEmitExpression(ADecl.InitExpr);
  // A string initializer is a new reference: addref before the store,
  // the same way DoEmitAssign does. No release -- the var is fresh.
  if (ADecl.TypeExpr <> nil) and DoIsStringType(ADecl.TypeExpr) then
    BLn('(call $RT_StrAddRef %s)', [LValue]);
  BLn('%s', [DoVarSetDecl(ADecl, LValue)]);
end;

function TWklEmitter.DoAllocData(const ABytes: TBytes): Int64;
var
  LOffset: Int64;
  LSb: TStringBuilder;
  I: Integer;
begin
  LOffset := FDataOffset;
  LSb := TStringBuilder.Create();
  try
    LSb.Append(Format('(data (i64.const %d) "', [LOffset]));
    for I := 0 to Length(ABytes) - 1 do
      LSb.Append(Format('\%.2x', [ABytes[I]]));
    LSb.Append('")');
    FDataSegments.Add(LSb.ToString());
  finally
    LSb.Free();
  end;
  FDataOffset := FDataOffset + Int64(Length(ABytes));
  FDataOffset := (FDataOffset + 7) and (not Int64(7));
  Result := LOffset;
end;

function TWklEmitter.DoAllocString(const AValue: string): Int64;
var
  LUtf8, LWithNull: TBytes;
begin
  LUtf8 := TEncoding.UTF8.GetBytes(AValue);
  SetLength(LWithNull, Length(LUtf8) + 1);
  if Length(LUtf8) > 0 then
    Move(LUtf8[0], LWithNull[0], Length(LUtf8));
  LWithNull[Length(LUtf8)] := 0;
  Result := DoAllocData(LWithNull);
end;

{ TWklEmitter.DoGlobalName }
// Wat identifier for a module-level global (const or var): the declaring
// module's name, a dot, the declared name. Two units may declare the same
// name; without the qualifier wasm-opt rejects the duplicate global.
function TWklEmitter.DoGlobalName(const ADecl: TWklNode): string;
begin
  if ADecl.OwnerModule <> '' then
    Result := ADecl.OwnerModule + '.' + ADecl.Name
  else
    Result := ADecl.Name;
end;

function TWklEmitter.DoMangledName(const ARoutine: TWklRoutineDeclNode): string;
var
  LSb: TStringBuilder;
  LParam: TWklParamNode;
  LPrimName: string;
  LDef: TWklNode;
  I: Integer;
begin
  LSb := TStringBuilder.Create();
  try
    if ARoutine.OwnerModule <> '' then
    begin
      LSb.Append(ARoutine.OwnerModule);
      LSb.Append('.');
    end;
    LSb.Append(ARoutine.Name);
    LSb.Append('__');
    if ARoutine.Params <> nil then
    begin
      for I := 0 to ARoutine.Params.Count - 1 do
      begin
        if I > 0 then
          LSb.Append('_');
        LParam := TWklParamNode(ARoutine.Params[I]);
        if LParam.TypeExpr = nil then
        begin
          LSb.Append('unknown');
          Continue;
        end;
        LPrimName := DoGetPrimitiveName(LParam.TypeExpr);
        if LPrimName <> '' then
        begin
          LSb.Append(LPrimName);
          Continue;
        end;
        LDef := DoResolveTypeDef(LParam.TypeExpr);
        if LDef is TWklPointerTypeNode then
          LSb.Append('ptr')
        else if LDef is TWklArrayTypeNode then
          LSb.Append('array')
        else if LDef is TWklRecordTypeNode then
          LSb.Append('record')
        else if LDef is TWklOverlayTypeNode then
          LSb.Append('overlay')
        else if LDef is TWklSetTypeNode then
          LSb.Append('set')
        else if LDef is TWklChoicesTypeNode then
          LSb.Append('choices')
        else if LDef is TWklRoutineTypeNode then
          LSb.Append('routine')
        else if (LParam.TypeExpr is TWklTypeRefNode) and
          (TWklTypeRefNode(LParam.TypeExpr).ResolvedDecl <> nil) then
          LSb.Append(TWklTypeRefNode(LParam.TypeExpr).ResolvedDecl.Name)
        else
          LSb.Append('unknown');
      end;
    end;
    // Variadic routines carry a trailing pack param; keep the name distinct
    if ARoutine.IsVariadic then
      LSb.Append('__va');
    Result := LSb.ToString();
  finally
    LSb.Free();
  end;
end;

function TWklEmitter.DoGetDesignatorName(const ANode: TWklNode): string;
begin
  Result := '';
  if ANode = nil then
    Exit;
  if (ANode is TWklIdentifierNode) or (ANode is TWklDotAccessNode) then
    Result := ANode.Name;
end;

function TWklEmitter.DoAllocStringTemp(const AExpr: string): string;
var
  LName: string;
begin
  LName := Format('_stmp_%d', [FTempSeq]);
  Inc(FTempSeq);
  if FDeclaredLocals.IndexOf(LName) < 0 then
  begin
    DLn('(local $%s i64)', [LName]);
    FDeclaredLocals.Add(LName);
  end;
  BLn('%s', [AExpr]);
  BLn('local.set $%s', [LName]);
  FStringTemps.Add(LName);
  Result := Format('(local.get $%s)', [LName]);
end;

procedure TWklEmitter.DoEmitStringTempCleanup();
var
  I: Integer;
begin
  for I := 0 to FStringTemps.Count - 1 do
    BLn('(call $RT_StrRelease (local.get $%s))', [FStringTemps[I]]);
  FStringTemps.Clear();
  // Caller-owned variadic packs die with the statement too
  for I := 0 to FPackTemps.Count - 1 do
    BLn('(call $RT_PackFree (local.get $%s))', [FPackTemps[I]]);
  FPackTemps.Clear();
  // Aggregate sret temps -- free heap blocks at statement end
  DoEmitAggTempCleanup();
end;

function TWklEmitter.DoAllocAggTemp(const ASize: Int64): string;
var
  LName: string;
begin
  LName := Format('_atmp_%d', [FAggTempCounter]);
  Inc(FAggTempCounter);
  if FDeclaredLocals.IndexOf(LName) < 0 then
  begin
    DLn('(local $%s i64)', [LName]);
    FDeclaredLocals.Add(LName);
  end;
  // Allocate heap block up front -- sret callee writes into it
  BLn('(local.set $%s (call $RT_GetMem (i64.const %d)))', [LName, ASize]);
  FAggTemps.Add(LName);
  Result := LName;
end;

procedure TWklEmitter.DoEmitAggTempCleanup();
var
  LI: Integer;
begin
  for LI := 0 to FAggTemps.Count - 1 do
    BLn('(call $RT_FreeMem (local.get $%s))', [FAggTemps[LI]]);
  FAggTemps.Clear();
end;

// Runtime tag of a type, as assigned by semantics (0 = unknown).
function TWklEmitter.DoTypeIdOf(const AType: TWklNode): Int64;
var
  LDef: TWklNode;
begin
  Result := 0;
  LDef := DoResolveTypeDef(AType);
  if LDef <> nil then
    Result := LDef.TypeId;
end;

// Widen any wasm value to the i64 pack slot: i32 zero-extended, f32/f64
// bit-reinterpreted, i64 as is.
function TWklEmitter.DoWidenToSlot(const AExpr: string;
  const AType: TWklNode): string;
var
  LWasm: string;
begin
  LWasm := DoMapWasmType(AType);
  if LWasm = 'i32' then
    Result := Format('(i64.extend_i32_u %s)', [AExpr])
  else if LWasm = 'f32' then
    Result := Format('(i64.extend_i32_u (i32.reinterpret_f32 %s))', [AExpr])
  else if LWasm = 'f64' then
    Result := Format('(i64.reinterpret_f64 %s)', [AExpr])
  else
    Result := AExpr;
end;

// Inverse of DoWidenToSlot.
function TWklEmitter.DoNarrowFromSlot(const AExpr: string;
  const AType: TWklNode): string;
var
  LWasm: string;
begin
  LWasm := DoMapWasmType(AType);
  if LWasm = 'i32' then
    Result := Format('(i32.wrap_i64 %s)', [AExpr])
  else if LWasm = 'f32' then
    Result := Format('(f32.reinterpret_i32 (i32.wrap_i64 %s))', [AExpr])
  else if LWasm = 'f64' then
    Result := Format('(f64.reinterpret_i64 %s)', [AExpr])
  else
    Result := AExpr;
end;

// Builds the pack for a variadic call from AArgs[AFixedCount..]. The pack
// lives in a `_vap_N` temp freed at statement end; returns the local.get.
function TWklEmitter.DoEmitVarArgsPack(const AArgs: TWklNodeList;
  const AFixedCount: Integer): string;
var
  LName: string;
  LCount: Integer;
  I: Integer;
  LArg: TWklNode;
begin
  LName := Format('_vap_%d', [FTempSeq]);
  Inc(FTempSeq);
  if FDeclaredLocals.IndexOf(LName) < 0 then
  begin
    DLn('(local $%s i64)', [LName]);
    FDeclaredLocals.Add(LName);
  end;
  LCount := 0;
  if AArgs <> nil then
    LCount := AArgs.Count - AFixedCount;
  if LCount < 0 then
    LCount := 0;
  BLn('(local.set $%s (call $RT_PackNew (i64.const %d)))', [LName, LCount]);
  for I := 0 to LCount - 1 do
  begin
    LArg := AArgs[AFixedCount + I];
    BLn('(call $RT_PackSet (local.get $%s) (i64.const %d) (i64.const %d) %s)',
      [LName, I, DoTypeIdOf(LArg.ResolvedType),
       DoWidenToSlot(DoEmitExpression(LArg), LArg.ResolvedType)]);
  end;
  FPackTemps.Add(LName);
  Result := Format('(local.get $%s)', [LName]);
end;

// A const is a string const when declared `: string`, or untyped with a
// string-typed value (literal or expression).
function TWklEmitter.DoIsStringConst(const ANode: TWklConstDeclNode): Boolean;
begin
  Result := False;
  if (ANode.TypeExpr <> nil) and DoIsStringType(ANode.TypeExpr) then
    Exit(True);
  if (ANode.ValueExpr <> nil) and (ANode.ValueExpr.ResolvedType <> nil) and
     DoIsStringType(ANode.ValueExpr.ResolvedType) then
    Exit(True);
end;

// Runtime initialisation of expression-based constants (string consts etc.)
// for one declaration list. Called for every imported unit and for the exe
// itself, so unit consts are live before any exe code reads them.
procedure TWklEmitter.DoEmitRuntimeConstInit(const ADecls: TWklNodeList);
var
  I: Integer;
  LConst: TWklConstDeclNode;
  LValue: string;
begin
  if ADecls = nil then
    Exit;
  for I := 0 to ADecls.Count - 1 do
  begin
    if ADecls[I] is TWklConstDeclNode then
    begin
      LConst := TWklConstDeclNode(ADecls[I]);
      if LConst.NeedsRuntimeInit then
      begin
        LValue := DoEmitExpression(LConst.ValueExpr);
        // A string const takes its own reference, exactly as DoEmitVarInit
        // does for a string var initialiser. The literal's _stmp_ temp is
        // released by the cleanup below, so the global keeps exactly one
        // reference for the program lifetime (released in the cleanup walk)
        if DoIsStringConst(LConst) then
          BLn('(call $RT_StrAddRef %s)', [LValue]);
        BLn('%s', [LValue]);
        BLn('global.set $%s', [DoGlobalName(LConst)]);
      end;
    end;
  end;
  // Release the literal temps created above here, not in the first
  // main-body statement's cleanup
  DoEmitStringTempCleanup();
end;

procedure TWklEmitter.DoEmitGlobalConst(const ANode: TWklConstDeclNode);
var
  LName, LWasmType: string;
  LVal: TWklNode;
  LLit: TWklLiteralNode;
begin
  LName := DoGlobalName(ANode);
  LVal := ANode.ValueExpr;
  if LVal = nil then
    Exit;

  // String constant -- a heap string built at _start (NeedsRuntimeInit) and
  // released in the cleanup walk; the global just holds the TStringRec ptr.
  // Typed (`: string`) or untyped (the literal itself is a string) alike.
  if DoIsStringConst(ANode) then
  begin
    WLn('(global $%s (mut i64) (i64.const 0))', [LName]);
    Exit;
  end;

  // Literal constants -- immutable globals
  if LVal is TWklLiteralNode then
  begin
    LLit := TWklLiteralNode(LVal);
    if LLit.Kind = lkInt then
    begin
      // Untyped const: the literal's resolved type is what reference sites use
      if ANode.TypeExpr <> nil then
        LWasmType := DoMapWasmType(ANode.TypeExpr)
      else if LVal.ResolvedType <> nil then
        LWasmType := DoMapWasmType(LVal.ResolvedType)
      else
        LWasmType := 'i64';
      WLn('(global $%s %s (%s.const %d))', [LName, LWasmType, LWasmType,
        LLit.IntValue]);
      Exit;
    end;
    if LLit.Kind = lkFloat then
    begin
      if ANode.TypeExpr <> nil then
        LWasmType := DoMapWasmType(ANode.TypeExpr)
      else if LVal.ResolvedType <> nil then
        LWasmType := DoMapWasmType(LVal.ResolvedType)
      else
        LWasmType := 'f64';
      WLn('(global $%s %s (%s.const %g))', [LName, LWasmType, LWasmType,
        LLit.FloatValue]);
      Exit;
    end;
    if LLit.Kind = lkBool then
    begin
      WLn('(global $%s i32 (i32.const %d))', [LName, Ord(LLit.BoolValue)]);
      Exit;
    end;
  end;

  // Expression-based or composite constant -- mutable zero-init, filled at _start
  if ANode.TypeExpr <> nil then
    LWasmType := DoMapWasmType(ANode.TypeExpr)
  else if (LVal.ResolvedType <> nil) then
    LWasmType := DoMapWasmType(LVal.ResolvedType)
  else
    LWasmType := 'i64';
  WLn('(global $%s (mut %s) (%s.const 0))', [LName, LWasmType, LWasmType]);
end;

procedure TWklEmitter.DoEmitGlobalVar(const ANode: TWklVarDeclNode);
var
  LName, LWasmType: string;
begin
  if ANode.IsExternal then
    Exit;
  if ANode.TypeExpr = nil then
    Exit;
  LName := DoGlobalName(ANode);
  if DoIsMemHomed(ANode) then
    LWasmType := 'i64'
  else
    LWasmType := DoMapWasmType(ANode.TypeExpr);
  WLn('(global $%s (mut %s) (%s.const 0))', [LName, LWasmType, LWasmType]);
end;

procedure TWklEmitter.DoEmitLocalVars(const ARoutine: TWklRoutineDeclNode);
var
  I: Integer;
  LVar: TWklVarDeclNode;
  LConst: TWklConstDeclNode;
  LWasmType: string;
  LDef: TWklNode;
  LSize: Int64;
  LNeedsAlloc: Boolean;
begin
  // Declare locals
  if ARoutine.LocalVars <> nil then
  begin
    for I := 0 to ARoutine.LocalVars.Count - 1 do
    begin
      if ARoutine.LocalVars[I] is TWklVarDeclNode then
      begin
        LVar := TWklVarDeclNode(ARoutine.LocalVars[I]);
        if LVar.TypeExpr <> nil then
        begin
          if DoIsMemHomed(LVar) then
            LWasmType := 'i64'
          else
            LWasmType := DoMapWasmType(LVar.TypeExpr);
          DoDeclareLocal(LVar, LWasmType);
        end;
      end;
    end;
  end;
  // Declare local consts as wasm locals
  if ARoutine.LocalConsts <> nil then
  begin
    for I := 0 to ARoutine.LocalConsts.Count - 1 do
    begin
      if ARoutine.LocalConsts[I] is TWklConstDeclNode then
      begin
        LConst := TWklConstDeclNode(ARoutine.LocalConsts[I]);
        if LConst.TypeExpr <> nil then
        begin
          LWasmType := DoMapWasmType(LConst.TypeExpr);
          DoDeclareLocal(LConst, LWasmType);
        end;
      end;
    end;
  end;
  // Auto-allocate composite locals
  if ARoutine.LocalVars <> nil then
  begin
    for I := 0 to ARoutine.LocalVars.Count - 1 do
    begin
      if ARoutine.LocalVars[I] is TWklVarDeclNode then
      begin
        LVar := TWklVarDeclNode(ARoutine.LocalVars[I]);
        if LVar.TypeExpr <> nil then
        begin
          LDef := DoResolveTypeDef(LVar.TypeExpr);
          LNeedsAlloc := DoIsMemHomed(LVar);
          if not LNeedsAlloc then
            LNeedsAlloc := (LDef is TWklRecordTypeNode) or
              (LDef is TWklOverlayTypeNode) or
              ((LDef is TWklArrayTypeNode) and
              (not TWklArrayTypeNode(LDef).IsDynamic));
          if LNeedsAlloc then
          begin
            // Skip if initialized with record literal
            if ((LDef is TWklRecordTypeNode) or (LDef is TWklOverlayTypeNode)) and
              (LVar.InitExpr <> nil) and (LVar.InitExpr is TWklRecordLiteralNode)
            then
              Continue;
            LSize := DoGetTypeByteSize(LVar.TypeExpr);
            BLn('(local.set $%s (call $RT_GetMem (i64.const %d)))',
              [DoLocalNameOf(LVar), LSize]);
          end;
        end;
      end;
    end;
  end;
  // Initialize local consts
  if ARoutine.LocalConsts <> nil then
  begin
    for I := 0 to ARoutine.LocalConsts.Count - 1 do
    begin
      if ARoutine.LocalConsts[I] is TWklConstDeclNode then
      begin
        LConst := TWklConstDeclNode(ARoutine.LocalConsts[I]);
        if (LConst.TypeExpr <> nil) and (LConst.ValueExpr <> nil) then
        begin
          BLn('%s', [DoEmitExpression(LConst.ValueExpr)]);
          BLn('local.set $%s', [DoLocalNameOf(LConst)]);
        end;
      end;
    end;
  end;
  // Initialize scalar local vars declared with an initializer
  if ARoutine.LocalVars <> nil then
  begin
    for I := 0 to ARoutine.LocalVars.Count - 1 do
    begin
      if ARoutine.LocalVars[I] is TWklVarDeclNode then
      begin
        LVar := TWklVarDeclNode(ARoutine.LocalVars[I]);
        if (LVar.InitExpr <> nil) and
          (not (LVar.InitExpr is TWklRecordLiteralNode)) then
          DoEmitVarInit(LVar);
      end;
    end;
  end;
end;

procedure TWklEmitter.DoEmitLocalCleanup(const ARoutine: TWklRoutineDeclNode);
begin
  DoEmitVarListCleanup(ARoutine.LocalVars);
end;

procedure TWklEmitter.DoEmitVarListCleanup(const AVars: TWklNodeList);
var
  I: Integer;
  LVar: TWklVarDeclNode;
  LDef: TWklNode;
begin
  if AVars = nil then
    Exit;
  // Release strings
  for I := 0 to AVars.Count - 1 do
  begin
    if AVars[I] is TWklVarDeclNode then
    begin
      LVar := TWklVarDeclNode(AVars[I]);
      if (LVar.TypeExpr <> nil) and DoIsStringType(LVar.TypeExpr) then
        BLn('(call $RT_StrRelease (local.get $%s))', [DoLocalNameOf(LVar)])
      // A `varargs` local owns the pack it was assigned (varargs.copy())
      else if (LVar.TypeExpr <> nil) and
        (DoGetPrimitiveName(LVar.TypeExpr) = 'varargs') then
        BLn('(call $RT_PackFree (local.get $%s))', [DoLocalNameOf(LVar)]);
    end;
  end;
  // Free composite locals
  for I := 0 to AVars.Count - 1 do
  begin
    if AVars[I] is TWklVarDeclNode then
    begin
      LVar := TWklVarDeclNode(AVars[I]);
      if LVar.TypeExpr <> nil then
      begin
        LDef := DoResolveTypeDef(LVar.TypeExpr);
        if DoIsMemHomed(LVar) or
          (LDef is TWklRecordTypeNode) or (LDef is TWklOverlayTypeNode) or
          ((LDef is TWklArrayTypeNode) and
          (not TWklArrayTypeNode(LDef).IsDynamic)) then
        begin
          DoEmitReleaseRecordFields(
            Format('(local.get $%s)', [DoLocalNameOf(LVar)]), LDef);
          BLn('(call $RT_FreeMem (local.get $%s))', [DoLocalNameOf(LVar)]);
        end
        else if (LDef is TWklArrayTypeNode) and TWklArrayTypeNode(LDef).IsDynamic
        then
          BLn('(call $RT_DynFree (local.get $%s))', [DoLocalNameOf(LVar)]);
      end;
    end;
  end;
end;

// Walks a record type's fields and emits RT_StrRelease for every string
// field, loading each from ABase at the field's ByteOffset. Handles
// derived records by recursing into BaseType first. Must run BEFORE the
// record block itself is freed.
procedure TWklEmitter.DoEmitReleaseRecordFields(const ABase: string;
  const ATypeDef: TWklNode);
var
  LFields: TWklNodeList;
  LField: TWklFieldDeclNode;
  I: Integer;
begin
  if ATypeDef = nil then
    Exit;
  LFields := nil;
  if ATypeDef is TWklRecordTypeNode then
  begin
    // Derived record: release inherited fields first
    if TWklRecordTypeNode(ATypeDef).BaseType <> nil then
      DoEmitReleaseRecordFields(ABase,
        DoResolveTypeDef(TWklRecordTypeNode(ATypeDef).BaseType));
    LFields := TWklRecordTypeNode(ATypeDef).Fields;
  end
  else if ATypeDef is TWklAnonRecordNode then
    LFields := TWklAnonRecordNode(ATypeDef).Fields;
  if LFields = nil then
    Exit;
  for I := 0 to LFields.Count - 1 do
  begin
    if not (LFields[I] is TWklFieldDeclNode) then
      Continue;
    LField := TWklFieldDeclNode(LFields[I]);
    if (LField.TypeExpr <> nil) and DoIsStringType(LField.TypeExpr) then
      BLn('(call $RT_StrRelease (i64.load offset=%d %s))',
        [LField.ByteOffset, ABase]);
  end;
end;

// Mirrors DoEmitReleaseRecordFields but calls RT_StrAddRef instead.
// Used after sret memory.copy so the caller owns the string references
// before the callee's cleanup releases its copies.
procedure TWklEmitter.DoEmitAddRefRecordFields(const ABase: string;
  const ATypeDef: TWklNode);
var
  LFields: TWklNodeList;
  LField: TWklFieldDeclNode;
  I: Integer;
begin
  if ATypeDef = nil then
    Exit;
  LFields := nil;
  if ATypeDef is TWklRecordTypeNode then
  begin
    if TWklRecordTypeNode(ATypeDef).BaseType <> nil then
      DoEmitAddRefRecordFields(ABase,
        DoResolveTypeDef(TWklRecordTypeNode(ATypeDef).BaseType));
    LFields := TWklRecordTypeNode(ATypeDef).Fields;
  end
  else if ATypeDef is TWklAnonRecordNode then
    LFields := TWklAnonRecordNode(ATypeDef).Fields;
  if LFields = nil then
    Exit;
  for I := 0 to LFields.Count - 1 do
  begin
    if not (LFields[I] is TWklFieldDeclNode) then
      Continue;
    LField := TWklFieldDeclNode(LFields[I]);
    if (LField.TypeExpr <> nil) and DoIsStringType(LField.TypeExpr) then
      BLn('(call $RT_StrAddRef (i64.load offset=%d %s))',
        [LField.ByteOffset, ABase]);
  end;
end;

// Emits RT_GetMem for every heap-backed global var in ADecls: mem-homed,
// record, overlay, static array. Same predicate as DoEmitLocalVars and
// DoEmitGlobalCleanup. Dynamic arrays are managed by setlength; vars with a
// record-literal initializer are allocated by DoEmitVarInit via $_rl_ptr.
procedure TWklEmitter.DoEmitGlobalAlloc(const ADecls: TWklNodeList);
var
  I: Integer;
  LVar: TWklVarDeclNode;
  LDef: TWklNode;
  LSize: Int64;
  LNeedsAlloc: Boolean;
begin
  if ADecls = nil then
    Exit;
  for I := 0 to ADecls.Count - 1 do
  begin
    if not (ADecls[I] is TWklVarDeclNode) then
      Continue;
    LVar := TWklVarDeclNode(ADecls[I]);
    if LVar.IsExternal or (LVar.TypeExpr = nil) then
      Continue;
    LDef := DoResolveTypeDef(LVar.TypeExpr);
    LNeedsAlloc := DoIsMemHomed(LVar);
    if not LNeedsAlloc then
      LNeedsAlloc := (LDef is TWklRecordTypeNode) or
        (LDef is TWklOverlayTypeNode) or
        ((LDef is TWklArrayTypeNode) and
        (not TWklArrayTypeNode(LDef).IsDynamic));
    if not LNeedsAlloc then
      Continue;
    if ((LDef is TWklRecordTypeNode) or (LDef is TWklOverlayTypeNode)) and
      (LVar.InitExpr <> nil) and (LVar.InitExpr is TWklRecordLiteralNode) then
      Continue;
    LSize := DoGetTypeByteSize(LVar.TypeExpr);
    BLn('(global.set $%s (call $RT_GetMem (i64.const %d)))',
      [DoGlobalName(LVar), LSize]);
  end;
end;

// Emits release/free calls for every heap-owning global var in ADecls.
// Mirrors DoEmitVarListCleanup but reads via global.get. Record globals
// have their string fields released before the block is freed.
procedure TWklEmitter.DoEmitGlobalCleanup(const ADecls: TWklNodeList);
var
  I: Integer;
  LVar: TWklVarDeclNode;
  LDef: TWklNode;
  LGet: string;
begin
  if ADecls = nil then
    Exit;
  for I := 0 to ADecls.Count - 1 do
  begin
    // String consts own a heap TStringRec built at _start -- release it
    if (ADecls[I] is TWklConstDeclNode) and
       DoIsStringConst(TWklConstDeclNode(ADecls[I])) then
    begin
      BLn('(call $RT_StrRelease (global.get $%s))', [DoGlobalName(ADecls[I])]);
      Continue;
    end;
    if not (ADecls[I] is TWklVarDeclNode) then
      Continue;
    LVar := TWklVarDeclNode(ADecls[I]);
    if LVar.IsExternal or (LVar.TypeExpr = nil) then
      Continue;
    LGet := Format('(global.get $%s)', [DoGlobalName(LVar)]);
    LDef := DoResolveTypeDef(LVar.TypeExpr);
    if DoIsStringType(LVar.TypeExpr) then
      BLn('(call $RT_StrRelease %s)', [LGet])
    else if (LDef is TWklArrayTypeNode) and TWklArrayTypeNode(LDef).IsDynamic
    then
      BLn('(call $RT_DynFree %s)', [LGet])
    else if DoIsMemHomed(LVar) or (LDef is TWklRecordTypeNode) or
      (LDef is TWklOverlayTypeNode) or (LDef is TWklArrayTypeNode) then
    begin
      DoEmitReleaseRecordFields(LGet, LDef);
      BLn('(call $RT_FreeMem %s)', [LGet]);
    end;
  end;
end;

// Emits a parameterless void function named AFuncName whose body is
// ABlock's statements. Used for unit initialize / finalize sections.
// Inline var decls inside the block become wasm locals (same scan as
// DoEmitMainBody), and are cleaned up on exit.
procedure TWklEmitter.DoEmitModuleBlock(const ABlock: TWklBlockNode;
  const AFuncName: string);
var
  LSb: TStringBuilder;
  LFunc: TWklEmittedFunc;
  LMap: TWklSourceMap;
  I: Integer;
  LStmt: TWklNode;
  LVar: TWklVarDeclNode;
  LWasmType: string;
begin
  if (ABlock = nil) or (ABlock.Statements = nil) then
    Exit;

  // Reset per-function state
  FLocalDecls.Clear();
  FBody.Clear();
  FBodyMap.Clear();
  FDeclaredLocals.Clear();
  FLocalNames.Clear();
  FTempSeq := 0;
  FStringTemps.Clear();
  FPackTemps.Clear();
  FAggTemps.Clear();
  FAggTempCounter := 0;
  SetBodyIndent(2);
  FCurrentRange := ABlock.Location;

  // Inline var decls become locals
  for I := 0 to ABlock.Statements.Count - 1 do
  begin
    LStmt := ABlock.Statements[I];
    if LStmt is TWklVarDeclNode then
    begin
      LVar := TWklVarDeclNode(LStmt);
      if LVar.TypeExpr <> nil then
      begin
        if DoIsMemHomed(LVar) then
          LWasmType := 'i64'
        else
          LWasmType := DoMapWasmType(LVar.TypeExpr);
        DoDeclareLocal(LVar, LWasmType);
      end;
    end;
  end;

  LSb := TStringBuilder.Create();
  LMap := TWklSourceMap.Create();
  try
    LSb.AppendLine(Format('  (func $%s', [AFuncName]));
    LMap.Add(ABlock.Location);

    FBreakLabels.Clear();
    FContinueLabels.Clear();
    BLn('(block $_exit');
    DoEmitStatementList(ABlock.Statements);
    BLn(')');
    DoEmitVarListCleanup(ABlock.Statements);

    if FLocalDecls.Length > 0 then
      LSb.Append(FLocalDecls.ToString());
    if FBody.Length > 0 then
      LSb.Append(FBody.ToString());
    for I := 0 to FBodyMap.Count - 1 do
      LMap.Add(FBodyMap[I]);

    LSb.Append('  )');
    LFunc.WatText := LSb.ToString();
    LFunc.LineMap := LMap.ToArray();
    FFunctions.Add(LFunc);
  finally
    LMap.Free();
    LSb.Free();
  end;
end;

procedure TWklEmitter.DoEmitRoutine(const ANode: TWklRoutineDeclNode);
var
  LSb: TStringBuilder;
  LFunc: TWklEmittedFunc;
  LMap: TWklSourceMap;
  I: Integer;
  LParamType, LReturnType, LMangledName: string;
  LRoutineRange: TSourceRange;
  LParam: TWklParamNode;
begin
  // Reset per-function state
  FLocalDecls.Clear();
  FBody.Clear();
  FBodyMap.Clear();
  FDeclaredLocals.Clear();
  FLocalNames.Clear();
  FTempSeq := 0;
  FStringTemps.Clear();
  FPackTemps.Clear();
  FAggTemps.Clear();
  FAggTempCounter := 0;
  SetBodyIndent(2);

  LRoutineRange := ANode.Location;
  FCurrentRange := LRoutineRange;
  FCurrentRoutine := ANode;

  // Params are wasm params: register by declaring node, no (local) emitted
  if ANode.Params <> nil then
    for I := 0 to ANode.Params.Count - 1 do
    begin
      FDeclaredLocals.Add(ANode.Params[I].Name);
      FLocalNames.Add(ANode.Params[I], ANode.Params[I].Name);
    end;

  // Reserve the return slot name so no user local can take it
  if (ANode.ReturnType <> nil) and (not ANode.IsSret) then
    FDeclaredLocals.Add('_ret');
  // sret: the hidden first param name is reserved
  if ANode.IsSret then
    FDeclaredLocals.Add('_sret');

  LSb := TStringBuilder.Create();
  LMap := TWklSourceMap.Create();
  try
    LMangledName := DoMangledName(ANode);
    LSb.Append(Format('  (func $%s', [LMangledName]));

    // sret: hidden first parameter receives the caller's destination pointer
    if ANode.IsSret then
      LSb.Append(' (param $_sret i64)');

    // Parameters
    if ANode.Params <> nil then
      for I := 0 to ANode.Params.Count - 1 do
      begin
        LParam := TWklParamNode(ANode.Params[I]);
        LParamType := DoMapWasmType(LParam.TypeExpr);
        LSb.Append(Format(' (param $%s %s)', [LParam.Name, LParamType]));
      end;
    // Variadic ABI: trailing pack pointer, owned by the caller
    if ANode.IsVariadic then
    begin
      LSb.Append(' (param $_va i64)');
      FDeclaredLocals.Add('_va');
    end;

    // Return type (omitted for sret -- function is void)
    if (ANode.ReturnType <> nil) and (not ANode.IsSret) then
    begin
      LReturnType := DoMapWasmType(ANode.ReturnType);
      LSb.Append(Format(' (result %s)', [LReturnType]));
    end;

    LSb.AppendLine('');
    LMap.Add(LRoutineRange);

    // Emit locals
    DoEmitLocalVars(ANode);

    // Return slot: every 'return' stores here and branches to $_exit,
    // so cleanup below always runs. Defaults to zero on fallthrough.
    // (sret routines write directly to $_sret, no $_ret needed)
    if (ANode.ReturnType <> nil) and (not ANode.IsSret) then
      DLn('(local $_ret %s)', [DoMapWasmType(ANode.ReturnType)]);

    // Body
    FBreakLabels.Clear();
    FContinueLabels.Clear();
    BLn('(block $_exit');
    if ANode.Body <> nil then
      DoEmitStatementList(ANode.Body.Statements);
    BLn(')');

    // Cleanup
    DoEmitLocalCleanup(ANode);

    // Push return value (sret is void -- no value on stack)
    if (ANode.ReturnType <> nil) and (not ANode.IsSret) then
      BLn('(local.get $_ret)');

    // Append locals then body
    if FLocalDecls.Length > 0 then
      LSb.Append(FLocalDecls.ToString());
    if FBody.Length > 0 then
      LSb.Append(FBody.ToString());
    for I := 0 to FBodyMap.Count - 1 do
      LMap.Add(FBodyMap[I]);

    LSb.Append('  )');
    LFunc.WatText := LSb.ToString();
    LFunc.LineMap := LMap.ToArray();
    FFunctions.Add(LFunc);
  finally
    LMap.Free();
    LSb.Free();
  end;
  FCurrentRoutine := nil;
end;

function TWklEmitter.DoEmitExpression(const ANode: TWklNode): string;
var
  LLit: TWklLiteralNode;
  LIdent: TWklIdentifierNode;
  LDeref: TWklDerefNode;
  LDataOffset: Int64;
  LRawPtr: string;
  LUtf8Len: Integer;
  LPrimName: string;
  LWasmType: string;
  LLoadOp: string;
  LRecLit: TWklRecordLiteralNode;
  LSize: Int64;
  LResolvedDecl: TWklNode;
  LSetElem: TWklSetElementNode;
  I: Integer;
begin
  Result := '';
  if ANode = nil then
  begin
    Result := '(i32.const 0)';
    Exit;
  end;

  // Literal
  if ANode is TWklLiteralNode then
  begin
    LLit := TWklLiteralNode(ANode);
    if LLit.Kind = lkInt then
    begin
      if ANode.ResolvedType <> nil then
        LWasmType := DoMapWasmType(ANode.ResolvedType)
      else
        LWasmType := 'i64';
      Result := Format('(%s.const %d)', [LWasmType, LLit.IntValue]);
    end
    else if LLit.Kind = lkFloat then
    begin
      // Resolved type wins (semantics propagates the target type onto
      // literals); the lexer suffix flag is only a fallback
      if ANode.ResolvedType <> nil then
        LWasmType := DoMapWasmType(ANode.ResolvedType)
      else if LLit.IsFloat32 then
        LWasmType := 'f32'
      else
        LWasmType := 'f64';
      Result := Format('(%s.const %g)', [LWasmType, LLit.FloatValue]);
    end
    else if LLit.Kind = lkString then
    begin
      // A string literal resolved as char/wchar by semantics is a code
      // point, not a heap string
      LPrimName := DoGetPrimitiveName(LLit.ResolvedType);
      if ((LPrimName = 'char') or (LPrimName = 'wchar')) and
        (Length(LLit.StringValue) > 0) then
        Exit(Format('(i32.const %d)', [Ord(LLit.StringValue[1])]));
      LDataOffset := DoAllocString(LLit.StringValue);
      LRawPtr := Format('(i64.const %d)', [LDataOffset]);
      LUtf8Len := Length(TEncoding.UTF8.GetBytes(LLit.StringValue));
      Result := DoAllocStringTemp
        (Format('(call $RT_StrFromLiteral %s (i64.const %d))',
        [LRawPtr, LUtf8Len]));
    end
    else if LLit.Kind = lkWString then
    begin
      // A wide literal resolved as char/wchar by semantics is a code point
      LPrimName := DoGetPrimitiveName(LLit.ResolvedType);
      if ((LPrimName = 'char') or (LPrimName = 'wchar')) and
        (Length(LLit.StringValue) > 0) then
        Exit(Format('(i32.const %d)', [Ord(LLit.StringValue[1])]));
      LDataOffset := DoAllocString(LLit.StringValue);
      LRawPtr := Format('(i64.const %d)', [LDataOffset]);
      // Literal bytes are UTF-8; the runtime builds the UTF-16 view on demand
      LUtf8Len := TEncoding.UTF8.GetByteCount(LLit.StringValue);
      Result := DoAllocStringTemp
        (Format('(call $RT_WStrFromLiteral %s (i64.const %d))',
        [LRawPtr, LUtf8Len]));
    end
    else if LLit.Kind = lkBool then
      Result := Format('(i32.const %d)', [Ord(LLit.BoolValue)])
    else if LLit.Kind = lkNil then
    begin
      // A routine reference is an i32 table index (slot 0 reserved = nil);
      // every other nil is a 64-bit null pointer.
      if DoResolveTypeDef(LLit.ResolvedType) is TWklRoutineTypeNode then
        Result := '(i32.const 0)'
      else
        Result := '(i64.const 0)';
    end;
    Exit;
  end;

  // Identifier
  if ANode is TWklIdentifierNode then
  begin
    LIdent := TWklIdentifierNode(ANode);
    // Function reference
    if (LIdent.ResolvedDecl <> nil) and
      (LIdent.ResolvedDecl is TWklRoutineDeclNode) then
    begin
      Result := DoEmitFuncRef(LIdent.ResolvedDecl, LIdent.Name);
      Exit;
    end;
    Result := DoVarGet(LIdent);
    Exit;
  end;

  if ANode is TWklBinaryExprNode then
  begin
    Result := DoEmitBinaryExpr(TWklBinaryExprNode(ANode));
    Exit;
  end;
  if ANode is TWklUnaryExprNode then
  begin
    Result := DoEmitUnaryExpr(TWklUnaryExprNode(ANode));
    Exit;
  end;
  if ANode is TWklCallExprNode then
  begin
    Result := DoEmitCallExpr(TWklCallExprNode(ANode));
    Exit;
  end;
  if ANode is TWklDotAccessNode then
  begin
    Result := DoEmitDotAccess(TWklDotAccessNode(ANode));
    Exit;
  end;
  if ANode is TWklIndexAccessNode then
  begin
    Result := DoEmitIndexAccess(TWklIndexAccessNode(ANode));
    Exit;
  end;
  if ANode is TWklTypeCastNode then
  begin
    Result := DoEmitTypeCast(TWklTypeCastNode(ANode));
    Exit;
  end;
  if ANode is TWklIntrinsicNode then
  begin
    Result := DoEmitIntrinsic(TWklIntrinsicNode(ANode));
    Exit;
  end;

  // Deref
  if ANode is TWklDerefNode then
  begin
    LDeref := TWklDerefNode(ANode);
    // An aggregate is represented by its address: p^ for ptr to record
    // IS the pointer value, no load (same contract as DoEmitDotAccess)
    if DoIsAggregateType(ANode.ResolvedType) then
    begin
      Result := DoEmitExpression(LDeref.BaseExpr);
      Exit;
    end;
    if ANode.ResolvedType <> nil then
      LLoadOp := DoMapMemLoadOp(ANode.ResolvedType)
    else
      LLoadOp := 'i64.load';
    Result := Format('(%s %s)', [LLoadOp, DoEmitExpression(LDeref.BaseExpr)]);
    Exit;
  end;

  // Record literal: allocate once, delegate field writes to
  // DoEmitRecordLiteralInto (handles nesting and string AddRef).
  if ANode is TWklRecordLiteralNode then
  begin
    LRecLit := TWklRecordLiteralNode(ANode);
    LResolvedDecl := ANode.ResolvedType;
    LSize := DoGetTypeByteSize(LResolvedDecl);
    if FDeclaredLocals.IndexOf('_rl_ptr') < 0 then
    begin
      DLn('(local $_rl_ptr i64)');
      FDeclaredLocals.Add('_rl_ptr');
    end;
    BLn('(local.set $_rl_ptr (call $RT_GetMem (i64.const %d)))', [LSize]);
    DoEmitRecordLiteralInto(LRecLit, '(local.get $_rl_ptr)', 0);
    Result := '(local.get $_rl_ptr)';
    Exit;
  end;

  // Set literal: fold elements into nested RT_SetAdd / RT_SetAddRange calls
  // over an empty set. Elements are widened to i64 for the runtime.
  if ANode is TWklSetLiteralNode then
  begin
    Result := '(call $RT_SetCreate)';
    for I := 0 to TWklSetLiteralNode(ANode).Elements.Count - 1 do
    begin
      LSetElem := TWklSetElementNode(TWklSetLiteralNode(ANode).Elements[I]);
      if LSetElem.RangeEnd <> nil then
        Result := Format('(call $RT_SetAddRange %s %s %s)',
          [Result, DoEmitExprAsI64(LSetElem.ValueExpr),
           DoEmitExprAsI64(LSetElem.RangeEnd)])
      else
        Result := Format('(call $RT_SetAdd %s %s)',
          [Result, DoEmitExprAsI64(LSetElem.ValueExpr)]);
    end;
    Exit;
  end;

  Result := '(i32.const 0) ;; unsupported expr';
end;

function TWklEmitter.DoEmitExprAsF64(const ANode: TWklNode): string;
var
  LExpr, LWasmType: string;
begin
  LExpr := DoEmitExpression(ANode);
  if ANode.ResolvedType <> nil then
    LWasmType := DoMapWasmType(ANode.ResolvedType)
  else
    LWasmType := 'f64';
  if LWasmType = 'f32' then
    Result := Format('(f64.promote_f32 %s)', [LExpr])
  else if LWasmType = 'i32' then
    Result := Format('(f64.convert_i32_s %s)', [LExpr])
  else if LWasmType = 'i64' then
    Result := Format('(f64.convert_i64_s %s)', [LExpr])
  else
    Result := LExpr;
end;

function TWklEmitter.DoEmitExprAsI64(const ANode: TWklNode): string;
var
  LExpr, LWasmType: string;
begin
  LExpr := DoEmitExpression(ANode);
  if ANode.ResolvedType <> nil then
    LWasmType := DoMapWasmType(ANode.ResolvedType)
  else
    LWasmType := 'i64';
  if LWasmType = 'i32' then
    Result := Format('(i64.extend_i32_s %s)', [LExpr])
  else if LWasmType = 'f64' then
    Result := Format('(i64.trunc_f64_s %s)', [LExpr])
  else if LWasmType = 'f32' then
    Result := Format('(i64.trunc_f32_s %s)', [LExpr])
  else
    Result := LExpr;
end;

function TWklEmitter.DoEmitBinaryExpr(const ANode: TWklBinaryExprNode): string;
var
  LLeft, LRight, LWasmType, LStrCompare: string;
  LIsFloat, LIsUnsigned, LIsString, LIsSet: Boolean;
  LLeftType: TWklNode;
begin
  LLeft := DoEmitExpression(ANode.Left);
  LRight := DoEmitExpression(ANode.Right);

  LLeftType := ANode.Left.ResolvedType;
  if LLeftType <> nil then
  begin
    LWasmType := DoMapWasmType(LLeftType);
    LIsFloat := DoIsFloatType(LLeftType);
    LIsUnsigned := DoIsUnsignedType(LLeftType);
    LIsString := DoIsStringType(LLeftType);
    LIsSet := DoIsSetType(LLeftType);
    if LIsString then
      LStrCompare := DoGetStrCompareFunc(LLeftType)
    else
      LStrCompare := '';
  end
  else
  begin
    LWasmType := 'i32';
    LIsFloat := False;
    LIsUnsigned := False;
    LIsString := False;
    LIsSet := False;
    LStrCompare := '';
  end;

  if ANode.Op = boAdd then
  begin
    if LIsString then
      Result := DoAllocStringTemp(Format('(call $RT_StrConcat %s %s)',
        [LLeft, LRight]))
    else if LIsSet then
      Result := Format('(call $RT_SetUnion %s %s)', [LLeft, LRight])
    else
      Result := Format('(%s.add %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boSub then
  begin
    if LIsSet then
      Result := Format('(call $RT_SetDiff %s %s)', [LLeft, LRight])
    else
      Result := Format('(%s.sub %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boMul then
  begin
    if LIsSet then
      Result := Format('(call $RT_SetInter %s %s)', [LLeft, LRight])
    else
      Result := Format('(%s.mul %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boDiv then
  begin
    if LIsFloat then
      Result := Format('(%s.div %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(f64.div (f64.convert_%s_s %s) (f64.convert_%s_s %s))',
        [LWasmType, LLeft, LWasmType, LRight]);
  end
  else if ANode.Op = boIntDiv then
  begin
    LRight := Format('(call $RT_CheckDiv%s %s)', [UpperCase(LWasmType), LRight]);
    if LIsUnsigned then
      Result := Format('(%s.div_u %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(%s.div_s %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boMod then
  begin
    LRight := Format('(call $RT_CheckDiv%s %s)', [UpperCase(LWasmType), LRight]);
    if LIsUnsigned then
      Result := Format('(%s.rem_u %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(%s.rem_s %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boAnd then
    Result := Format('(%s.and %s %s)', [LWasmType, LLeft, LRight])
  else if ANode.Op = boOr then
    Result := Format('(%s.or %s %s)', [LWasmType, LLeft, LRight])
  else if ANode.Op = boXor then
    Result := Format('(%s.xor %s %s)', [LWasmType, LLeft, LRight])
  else if ANode.Op = boShl then
    Result := Format('(%s.shl %s %s)', [LWasmType, LLeft, LRight])
  else if ANode.Op = boShr then
  begin
    if LIsUnsigned then
      Result := Format('(%s.shr_u %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(%s.shr_s %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boLogicalAnd then
    Result := Format('(i32.and %s %s)', [LLeft, LRight])
  else if ANode.Op = boLogicalOr then
    Result := Format('(i32.or %s %s)', [LLeft, LRight])
  else if ANode.Op = boEq then
  begin
    if LIsString then
      Result := Format('(i64.eqz (call %s %s %s))',
        [LStrCompare, LLeft, LRight])
    else if LIsSet then
      Result := Format('(call $RT_SetEq %s %s)', [LLeft, LRight])
    else
      Result := Format('(%s.eq %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boNotEq then
  begin
    if LIsString then
      Result := Format('(i32.eqz (i64.eqz (call %s %s %s)))',
        [LStrCompare, LLeft, LRight])
    else if LIsSet then
      Result := Format('(call $RT_SetNe %s %s)', [LLeft, LRight])
    else
      Result := Format('(%s.ne %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boLess then
  begin
    if LIsString then
      Result := Format('(i64.lt_s (call %s %s %s) (i64.const 0))',
        [LStrCompare, LLeft, LRight])
    else if LIsSet then
      Result := Format('(call $RT_SetSubset %s %s)', [LLeft, LRight])
    else if LIsFloat then
      Result := Format('(%s.lt %s %s)', [LWasmType, LLeft, LRight])
    else if LIsUnsigned then
      Result := Format('(%s.lt_u %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(%s.lt_s %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boGreater then
  begin
    if LIsString then
      Result := Format('(i64.gt_s (call %s %s %s) (i64.const 0))',
        [LStrCompare, LLeft, LRight])
    else if LIsSet then
      Result := Format('(call $RT_SetSuperset %s %s)', [LLeft, LRight])
    else if LIsFloat then
      Result := Format('(%s.gt %s %s)', [LWasmType, LLeft, LRight])
    else if LIsUnsigned then
      Result := Format('(%s.gt_u %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(%s.gt_s %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boLessEq then
  begin
    if LIsString then
      Result := Format('(i64.le_s (call %s %s %s) (i64.const 0))',
        [LStrCompare, LLeft, LRight])
    else if LIsFloat then
      Result := Format('(%s.le %s %s)', [LWasmType, LLeft, LRight])
    else if LIsUnsigned then
      Result := Format('(%s.le_u %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(%s.le_s %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boGreaterEq then
  begin
    if LIsString then
      Result := Format('(i64.ge_s (call %s %s %s) (i64.const 0))',
        [LStrCompare, LLeft, LRight])
    else if LIsFloat then
      Result := Format('(%s.ge %s %s)', [LWasmType, LLeft, LRight])
    else if LIsUnsigned then
      Result := Format('(%s.ge_u %s %s)', [LWasmType, LLeft, LRight])
    else
      Result := Format('(%s.ge_s %s %s)', [LWasmType, LLeft, LRight]);
  end
  else if ANode.Op = boIn then
    Result := Format('(call $RT_SetIn %s %s)', [LLeft, LRight])
  else
    Result := Format('(i32.const 0) ;; unsupported binop %d', [Ord(ANode.Op)]);
end;

function TWklEmitter.DoEmitUnaryExpr(const ANode: TWklUnaryExprNode): string;
var
  LOperand, LWasmType: string;
  LIsFloat: Boolean;
  LDecl: TWklNode;
  LLocal: string;
begin
  // Address-of
  if ANode.Op = uoAddressOf then
  begin
    if ANode.Operand is TWklIdentifierNode then
    begin
      LDecl := DoDeclOf(ANode.Operand);
      if DoIsMemHomed(LDecl) then
      begin
        // Mem-homed scalar: the local/global IS the pointer; do not load
        LLocal := DoLocalNameOf(LDecl);
        if LLocal <> '' then
          Result := Format('(local.get $%s)', [LLocal])
        else
          Result := Format('(global.get $%s)', [DoGlobalName(LDecl)]);
      end
      else
        Result := DoVarGet(ANode.Operand);
    end
    else if ANode.Operand is TWklIndexAccessNode then
      // Element address, not the element value
      Result := DoEmitIndexAddress(TWklIndexAccessNode(ANode.Operand))
    else
      Result := DoEmitExpression(ANode.Operand);
    Exit;
  end;

  LOperand := DoEmitExpression(ANode.Operand);
  if ANode.Operand.ResolvedType <> nil then
  begin
    LWasmType := DoMapWasmType(ANode.Operand.ResolvedType);
    LIsFloat := DoIsFloatType(ANode.Operand.ResolvedType);
  end
  else
  begin
    LWasmType := 'i32';
    LIsFloat := False;
  end;

  if ANode.Op = uoNegate then
  begin
    if LIsFloat then
      Result := Format('(%s.neg %s)', [LWasmType, LOperand])
    else
      Result := Format('(%s.sub (%s.const 0) %s)',
        [LWasmType, LWasmType, LOperand]);
  end
  else if ANode.Op = uoNot then
    Result := Format('(i32.eqz %s)', [LOperand])
  else if ANode.Op = uoPlus then
    Result := LOperand
  else
    Result := '(i32.const 0) ;; unsupported unary';
end;

function TWklEmitter.DoEmitCallExpr(const ANode: TWklCallExprNode): string;
var
  LSb: TStringBuilder;
  LFuncName: string;
  I: Integer;
  LFixed: Integer;
  LSretTemp: string;
begin
  // Call through a routine-typed value: indirect via the function table
  if ANode.ResolvedRoutineType <> nil then
  begin
    LFixed := ANode.Args.Count;
    if ANode.ResolvedRoutineType.IsVariadic then
      LFixed := ANode.ResolvedRoutineType.Params.Count;
    LSb := TStringBuilder.Create();
    try
      LSb.Append('(call_indirect $rt_functable');
      LSb.Append(DoRoutineTypeSignature(ANode.ResolvedRoutineType));
      // sret: prepend temp destination as hidden first arg
      if ANode.ResolvedRoutineType.IsSret then
        LSb.Append(Format(' (local.get $%s)', [DoAllocAggTemp(
          ANode.ResolvedRoutineType.SretByteSize)]));
      if ANode.Args <> nil then
        for I := 0 to LFixed - 1 do
          LSb.Append(' ' + DoEmitExpression(ANode.Args[I]));
      if ANode.ResolvedRoutineType.IsVariadic then
        LSb.Append(' ' + DoEmitVarArgsPack(ANode.Args, LFixed));
      LSb.Append(' ' + DoEmitExpression(ANode.Callee));
      LSb.Append(')');
      Result := LSb.ToString();
    finally
      LSb.Free();
    end;
    // sret: the call is void; emit it, result is the temp
    if ANode.ResolvedRoutineType.IsSret then
    begin
      LSretTemp := FAggTemps[FAggTemps.Count - 1];
      BLn('%s', [Result]);
      Result := Format('(local.get $%s)', [LSretTemp]);
      Exit;
    end;
    // A string result is a fresh reference owned by the caller: hold it in
    // a temp so it is released at statement end (assignment addrefs it)
    if DoIsStringType(ANode.ResolvedType) then
      Result := DoAllocStringTemp(Result);
    Exit;
  end;

  if ANode.ResolvedRoutine <> nil then
    LFuncName := DoMangledName(ANode.ResolvedRoutine)
  else
    LFuncName := DoGetDesignatorName(ANode.Callee);

  LFixed := ANode.Args.Count;
  if (ANode.ResolvedRoutine <> nil) and ANode.ResolvedRoutine.IsVariadic then
    LFixed := ANode.ResolvedRoutine.Params.Count;

  LSb := TStringBuilder.Create();
  try
    if LFuncName <> '' then
    begin
      LSb.Append(Format('(call $%s', [LFuncName]));
      // sret: prepend temp destination as hidden first arg
      if (ANode.ResolvedRoutine <> nil) and ANode.ResolvedRoutine.IsSret then
        LSb.Append(Format(' (local.get $%s)', [DoAllocAggTemp(
          ANode.ResolvedRoutine.SretByteSize)]));
      if ANode.Args <> nil then
        for I := 0 to LFixed - 1 do
          LSb.Append(' ' + DoEmitExpression(ANode.Args[I]));
      if (ANode.ResolvedRoutine <> nil) and ANode.ResolvedRoutine.IsVariadic then
        LSb.Append(' ' + DoEmitVarArgsPack(ANode.Args, LFixed));
      LSb.Append(')');
    end
    else
    begin
      LSb.Append('(call_indirect');
      if ANode.Args <> nil then
        for I := 0 to ANode.Args.Count - 1 do
          LSb.Append(' ' + DoEmitExpression(ANode.Args[I]));
      LSb.Append(' ' + DoEmitExpression(ANode.Callee));
      LSb.Append(')');
    end;
    Result := LSb.ToString();
  finally
    LSb.Free();
  end;
  // sret: the call is void; emit it as a statement, result is the temp
  if (ANode.ResolvedRoutine <> nil) and ANode.ResolvedRoutine.IsSret then
  begin
    LSretTemp := FAggTemps[FAggTemps.Count - 1];
    BLn('%s', [Result]);
    Result := Format('(local.get $%s)', [LSretTemp]);
    Exit;
  end;
  // A string result is a fresh reference owned by the caller: hold it in
  // a temp so it is released at statement end (assignment addrefs it)
  if DoIsStringType(ANode.ResolvedType) then
    Result := DoAllocStringTemp(Result);
end;

function TWklEmitter.DoEmitDotAccess(const ANode: TWklDotAccessNode): string;
var
  LBase, LMemberName, LFieldLoadOp: string;
  LFieldOffset, LBitWidth, LBitOffset, LMask: Int64;
  LFieldDef: TWklNode;
  LField: TWklFieldDeclNode;
  LChoices: TWklChoicesTypeNode;
  LVal: TWklChoicesValueNode;
  I: Integer;
begin
  LMemberName := ANode.Name;

  if ANode.AccessKind = dakChoices then
  begin
    if ANode.BaseExpr.ResolvedType <> nil then
    begin
      LFieldDef := DoResolveTypeDef(ANode.BaseExpr.ResolvedType);
      if LFieldDef is TWklChoicesTypeNode then
      begin
        LChoices := TWklChoicesTypeNode(LFieldDef);
        if LChoices.Values <> nil then
          for I := 0 to LChoices.Values.Count - 1 do
            if LChoices.Values[I].Name = LMemberName then
            begin
              LVal := TWklChoicesValueNode(LChoices.Values[I]);
              Result := Format('(i32.const %d)', [LVal.ResolvedOrdinal]);
              Exit;
            end;
      end;
    end;
    Result := Format('(i32.const 0) ;; unresolved choices %s', [LMemberName]);
    Exit;
  end;

  if ANode.AccessKind = dakField then
  begin
    LBase := DoEmitExpression(ANode.BaseExpr);
    LFieldLoadOp := 'i64.load';

    if ANode.ResolvedDecl is TWklFieldDeclNode then
    begin
      LField := TWklFieldDeclNode(ANode.ResolvedDecl);
      LFieldOffset := LField.ByteOffset;
      if LField.TypeExpr <> nil then
      begin
        LFieldDef := DoResolveTypeDef(LField.TypeExpr);
        if (LFieldDef is TWklRecordTypeNode) or
          (LFieldDef is TWklOverlayTypeNode) then
        begin
          if LFieldOffset > 0 then
            Result := Format('(i64.add %s (i64.const %d))',
              [LBase, LFieldOffset])
          else
            Result := LBase;
          Exit;
        end;
        LFieldLoadOp := DoMapMemLoadOp(LField.TypeExpr);
      end;

      if LFieldOffset > 0 then
        Result := Format('(%s offset=%d %s)',
          [LFieldLoadOp, LFieldOffset, LBase])
      else
        Result := Format('(%s %s)', [LFieldLoadOp, LBase]);

      LBitWidth := LField.BitWidth;
      if LBitWidth > 0 then
      begin
        LBitOffset := LField.BitPos;
        if LBitOffset > 0 then
          Result := Format('(i32.shr_u %s (i32.const %d))',
            [Result, LBitOffset]);
        LMask := (Int64(1) shl LBitWidth) - 1;
        Result := Format('(i32.and %s (i32.const %d))', [Result, LMask]);
      end;
      Exit;
    end;

    Result := Format('(%s %s)', [LFieldLoadOp, LBase]);
    Exit;
  end;

  if ANode.AccessKind = dakModule then
  begin
    if (ANode.ResolvedDecl <> nil) and
      (ANode.ResolvedDecl is TWklRoutineDeclNode) then
      Result := DoEmitFuncRef(ANode.ResolvedDecl, LMemberName)
    else
      Result := DoVarGet(ANode);
    Exit;
  end;

  Result := '(i32.const 0) ;; unsupported dot access kind';
end;

// Element address of Base[Index] as an i64 expression: base + index * elemsize.
// The one place this arithmetic lives; loads, stores and address-of all use it.
function TWklEmitter.DoEmitIndexAddress(const ANode
  : TWklIndexAccessNode): string;
var
  LBase, LIdx, LIndexType: string;
  LElemSize: Int64;
  LDef: TWklNode;
  LArr: TWklArrayTypeNode;
begin
  LBase := DoEmitExpression(ANode.BaseExpr);
  LIdx := DoEmitExpression(ANode.IndexExpr);
  LElemSize := 8;

  if ANode.BaseExpr.ResolvedType <> nil then
  begin
    LDef := DoResolveTypeDef(ANode.BaseExpr.ResolvedType);
    if LDef is TWklArrayTypeNode then
    begin
      LArr := TWklArrayTypeNode(LDef);
      if LArr.ElementType <> nil then
        LElemSize := DoGetTypeByteSize(LArr.ElementType);
    end;
  end;

  if ANode.IndexExpr.ResolvedType <> nil then
    LIndexType := DoMapWasmType(ANode.IndexExpr.ResolvedType)
  else
    LIndexType := 'i32';

  if LIndexType = 'i32' then
    Result := Format('(i64.add %s (i64.mul (i64.extend_i32_s %s) (i64.const %d)))',
      [LBase, LIdx, LElemSize])
  else
    Result := Format('(i64.add %s (i64.mul %s (i64.const %d)))',
      [LBase, LIdx, LElemSize]);
end;

function TWklEmitter.DoEmitIndexAccess(const ANode
  : TWklIndexAccessNode): string;
var
  LLoadOp: string;
  LDef: TWklNode;
  LArr: TWklArrayTypeNode;
begin
  LLoadOp := 'i64.load';

  if ANode.BaseExpr.ResolvedType <> nil then
  begin
    LDef := DoResolveTypeDef(ANode.BaseExpr.ResolvedType);
    if LDef is TWklArrayTypeNode then
    begin
      LArr := TWklArrayTypeNode(LDef);
      if LArr.ElementType <> nil then
        LLoadOp := DoMapMemLoadOp(LArr.ElementType);
    end;
  end;

  Result := Format('(%s %s)', [LLoadOp, DoEmitIndexAddress(ANode)]);
end;

function TWklEmitter.DoEmitTypeCast(const ANode: TWklTypeCastNode): string;
var
  LInner, LTargetWasm, LSourceWasm, LTargetPrim: string;
  LSourceIsFloat, LSourceIsUnsigned, LTargetIsFloat, LTargetIsUnsigned: Boolean;
begin
  LInner := DoEmitExpression(ANode.Expr);
  if ANode.TargetType = nil then
  begin
    Result := LInner;
    Exit;
  end;
  LTargetPrim := DoGetPrimitiveName(ANode.TargetType);
  if LTargetPrim = '' then
  begin
    Result := LInner;
    Exit;
  end;
  LTargetWasm := DoMapWasmType(ANode.TargetType);
  LTargetIsFloat := DoIsFloatType(ANode.TargetType);
  LTargetIsUnsigned := DoIsUnsignedType(ANode.TargetType);
  LSourceIsFloat := False;
  LSourceIsUnsigned := False;
  LSourceWasm := 'i32';
  if ANode.Expr.ResolvedType <> nil then
  begin
    LSourceIsFloat := DoIsFloatType(ANode.Expr.ResolvedType);
    LSourceIsUnsigned := DoIsUnsignedType(ANode.Expr.ResolvedType);
    LSourceWasm := DoMapWasmType(ANode.Expr.ResolvedType);
  end;
  if LTargetIsFloat and (not LSourceIsFloat) then
  begin
    if LSourceIsUnsigned then
      Result := Format('(%s.convert_%s_u %s)',
        [LTargetWasm, LSourceWasm, LInner])
    else
      Result := Format('(%s.convert_%s_s %s)',
        [LTargetWasm, LSourceWasm, LInner]);
    Exit;
  end;
  if LSourceIsFloat and (not LTargetIsFloat) then
  begin
    if LTargetIsUnsigned then
      Result := Format('(%s.trunc_sat_%s_u %s)',
        [LTargetWasm, LSourceWasm, LInner])
    else
      Result := Format('(%s.trunc_sat_%s_s %s)',
        [LTargetWasm, LSourceWasm, LInner]);
    Exit;
  end;
  if LSourceIsFloat and LTargetIsFloat then
  begin
    if (LSourceWasm = 'f32') and (LTargetWasm = 'f64') then
      Result := Format('(f64.promote_f32 %s)', [LInner])
    else if (LSourceWasm = 'f64') and (LTargetWasm = 'f32') then
      Result := Format('(f32.demote_f64 %s)', [LInner])
    else
      Result := LInner;
    Exit;
  end;
  if (LSourceWasm = 'i32') and (LTargetWasm = 'i64') then
  begin
    if LSourceIsUnsigned then
      Result := Format('(i64.extend_i32_u %s)', [LInner])
    else
      Result := Format('(i64.extend_i32_s %s)', [LInner]);
    Exit;
  end;
  if (LSourceWasm = 'i64') and (LTargetWasm = 'i32') then
  begin
    Result := Format('(i32.wrap_i64 %s)', [LInner]);
    Exit;
  end;
  if (LTargetPrim = 'uint8') or (LTargetPrim = 'int8') or (LTargetPrim = 'char')
  then
    Result := Format('(%s.and %s (%s.const 255))',
      [LTargetWasm, LInner, LTargetWasm])
  else if (LTargetPrim = 'uint16') or (LTargetPrim = 'int16') or
    (LTargetPrim = 'wchar') then
    Result := Format('(%s.and %s (%s.const 65535))',
      [LTargetWasm, LInner, LTargetWasm])
  else
    Result := LInner;
end;

function TWklEmitter.DoEmitFormatArg(const AChain: string;
  const AArgNode: TWklNode; const ASpec: Char; const APrec: Integer): string;
var
  LWasmType: string;
  LArgType: TWklNode;
  LVal: string;
begin
  // A string literal argument is appended straight from the data segment.
  if (AArgNode is TWklLiteralNode) and
    (TWklLiteralNode(AArgNode).Kind = lkString) then
  begin
    Result := Format('(call $rt_fmt_cstr %s (i64.const %d))',
      [AChain, DoAllocString(TWklLiteralNode(AArgNode).StringValue)]);
    Exit;
  end;
  LArgType := AArgNode.ResolvedType;
  if LArgType <> nil then
    LWasmType := DoMapWasmType(LArgType)
  else
    LWasmType := 'i64';
  LVal := DoEmitExpression(AArgNode);
  if ASpec = 'd' then
  begin
    if LWasmType = 'i32' then
      LVal := Format('(i64.extend_i32_s %s)', [LVal])
    else if LWasmType = 'f64' then
      LVal := Format('(i64.trunc_f64_s %s)', [LVal])
    else if LWasmType = 'f32' then
      LVal := Format('(i64.trunc_f64_s (f64.promote_f32 %s))', [LVal]);
    Result := Format('(call $rt_fmt_i64 %s %s)', [AChain, LVal]);
  end
  else if ASpec = 'u' then
  begin
    if LWasmType = 'i32' then
      LVal := Format('(i64.extend_i32_u %s)', [LVal]);
    Result := Format('(call $rt_fmt_u64 %s %s)', [AChain, LVal]);
  end
  else if (ASpec = 'x') or (ASpec = 'X') then
  begin
    if LWasmType = 'i32' then
      LVal := Format('(i64.extend_i32_u %s)', [LVal]);
    if ASpec = 'X' then
      Result := Format('(call $rt_fmt_hex_upper %s %s)', [AChain, LVal])
    else
      Result := Format('(call $rt_fmt_hex %s %s)', [AChain, LVal]);
  end
  else if ASpec = 'f' then
  begin
    if LWasmType = 'f32' then
      LVal := Format('(f64.promote_f32 %s)', [LVal])
    else if LWasmType = 'i32' then
      LVal := Format('(f64.convert_i32_s %s)', [LVal])
    else if LWasmType = 'i64' then
      LVal := Format('(f64.convert_i64_s %s)', [LVal]);
    if APrec >= 0 then
      Result := Format('(call $rt_fmt_f64_prec %s %s (i32.const %d))',
        [AChain, LVal, APrec])
    else
      Result := Format('(call $rt_fmt_f64 %s %s)', [AChain, LVal]);
  end
  else if ASpec = 's' then
  begin
    if (LArgType <> nil) and DoIsStringType(LArgType) then
      Result := Format('(call $rt_fmt_str %s %s)', [AChain, LVal])
    else
      Result := Format('(call $rt_fmt_cstr %s %s)', [AChain, LVal]);
  end
  else if ASpec = 'p' then
  begin
    if LWasmType = 'i32' then
      LVal := Format('(i64.extend_i32_u %s)', [LVal]);
    Result := Format('(call $rt_fmt_ptr %s %s)', [AChain, LVal]);
  end
  else if ASpec = 'c' then
    Result := Format('(call $rt_fmt_char %s %s)', [AChain, LVal])
  else
  begin
    // Unreachable: the scanner only passes known specs. Keep the chain intact.
    Result := AChain;
  end;
end;

function TWklEmitter.DoEmitFormat(const ANode: TWklIntrinsicNode): string;
var
  LArgIdx, LPos, LLen, LSpecPos, LPrec: Integer;
  LFmt, LFragment, LChain: string;
  LCh, LSpecChar: Char;

  procedure FlushFragment();
  begin
    if LFragment = '' then
      Exit;
    LChain := Format('(call $rt_fmt_cstr %s (i64.const %d))',
      [LChain, DoAllocString(LFragment)]);
    LFragment := '';
  end;

begin
  // Semantics guarantees Args[0] is a string literal (WKL_ERR_SEM_003).
  LFmt := TWklLiteralNode(ANode.Args[0]).StringValue;
  LChain := '(call $rt_fmt_new)';
  LArgIdx := 1;
  LPos := 1;
  LLen := Length(LFmt);
  LFragment := '';
  while LPos <= LLen do
  begin
    LCh := LFmt[LPos];
    if (LCh = '%') and (LPos < LLen) then
    begin
      LSpecPos := LPos + 1;
      LPrec := -1;
      // flags and width are accepted and ignored, as in println
      while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos],
        ['-', '+', ' ', '0', '#']) do
        Inc(LSpecPos);
      while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos], ['0' .. '9']) do
        Inc(LSpecPos);
      if (LSpecPos <= LLen) and (LFmt[LSpecPos] = '.') then
      begin
        Inc(LSpecPos);
        LPrec := 0;
        while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos],
          ['0' .. '9']) do
        begin
          LPrec := LPrec * 10 + Ord(LFmt[LSpecPos]) - Ord('0');
          Inc(LSpecPos);
        end;
      end;
      while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos], ['l', 'h']) do
        Inc(LSpecPos);
      if (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos],
        ['s', 'd', 'i', 'f', 'u', 'x', 'X', 'p', 'c', 'e', 'E', 'g', 'G'])
      then
      begin
        LSpecChar := LFmt[LSpecPos];
        if LSpecChar = 'i' then
          LSpecChar := 'd'
        else if CharInSet(LSpecChar, ['e', 'E', 'g', 'G']) then
          LSpecChar := 'f';
        FlushFragment();
        if LArgIdx < ANode.Args.Count then
        begin
          LChain := DoEmitFormatArg(LChain, ANode.Args[LArgIdx], LSpecChar, LPrec);
          Inc(LArgIdx);
        end;
        LPos := LSpecPos + 1;
        Continue;
      end
      else if LFmt[LPos + 1] = '%' then
      begin
        LFragment := LFragment + '%';
        Inc(LPos, 2);
        Continue;
      end;
    end;
    LFragment := LFragment + LCh;
    Inc(LPos);
  end;
  FlushFragment();
  // Allocating string producer: register as a string temp so the per-statement
  // cleanup releases it (same contract as RT_StrConcat).
  Result := DoAllocStringTemp(LChain);
end;

// varargs.* inside a variadic routine. The pack is the `$_va` param. Values
// read from the pack are borrowed (the pack holds the reference); an
// assignment addrefs a string like any other variable read.
function TWklEmitter.DoEmitVarArgsIntrinsic(const ANode: TWklIntrinsicNode): string;
var
  LTypeId: Int64;
begin
  Result := '(i32.const 0)';
  if ANode.Kind = ikVarArgsCount then
    Result := '(call $RT_PackCount (local.get $_va))'
  else if ANode.Kind = ikVarArgsReset then
    Result := '(call $RT_PackReset (local.get $_va))'
  else if ANode.Kind = ikVarArgsCopy then
    Result := '(call $RT_PackCopy (local.get $_va))'
  else if ANode.Kind = ikVarArgsNext then
  begin
    LTypeId := DoTypeIdOf(ANode.TypeExpr);
    Result := DoNarrowFromSlot(
      Format('(call $RT_PackNext (local.get $_va) (i64.const %d))', [LTypeId]),
      ANode.TypeExpr);
  end
  else if ANode.Kind = ikVarArgsGet then
  begin
    LTypeId := DoTypeIdOf(ANode.TypeExpr);
    Result := DoNarrowFromSlot(
      Format('(call $RT_PackGet (local.get $_va) %s (i64.const %d))',
        [DoEmitExprAsI64(ANode.Args[0]), LTypeId]),
      ANode.TypeExpr);
  end;
  // A string read must hit the pack exactly once (assignment evaluates its
  // RHS twice). Hold it in a statement temp that owns one reference.
  if (ANode.Kind in [ikVarArgsNext, ikVarArgsGet]) and
    DoIsStringType(ANode.TypeExpr) then
  begin
    Result := DoAllocStringTemp(Result);
    BLn('(call $RT_StrAddRef %s)', [Result]);
  end;
end;

function TWklEmitter.DoEmitIntrinsic(const ANode: TWklIntrinsicNode): string;
var
  LArgType: TWklNode;
  LTypeDeclNode: TWklTypeDeclNode;
begin
  Result := '(i32.const 0)';
  if ANode.Kind in [ikVarArgsCount, ikVarArgsNext, ikVarArgsGet,
    ikVarArgsReset, ikVarArgsCopy] then
    Result := DoEmitVarArgsIntrinsic(ANode)
  else if ANode.Kind = ikParamCount then
    Result := '(call $RT_ParamCount)'
  else if ANode.Kind = ikParamStr then
  begin
    if (ANode.Args <> nil) and (ANode.Args.Count > 0) then
      Result := Format('(call $RT_ParamStr %s)',
        [DoEmitExprAsI64(ANode.Args[0])]);
  end
  else if ANode.Kind = ikExcCode then
    Result := '(call $RT_GetExceptionCode)'
  else if ANode.Kind = ikExcMsg then
    Result := '(call $RT_GetExceptionMsg)'
  else if ANode.Kind = ikLen then
  begin
    if (ANode.Args <> nil) and (ANode.Args.Count > 0) then
    begin
      LArgType := ANode.Args[0].ResolvedType;
      if (LArgType <> nil) and (DoGetPrimitiveName(LArgType) = 'wstring') then
        Result := Format('(call $RT_WStrLen %s)',
          [DoEmitExpression(ANode.Args[0])])
      else if (LArgType <> nil) and DoIsStringType(LArgType) then
        Result := Format('(call $RT_StrLen %s)',
          [DoEmitExpression(ANode.Args[0])])
      else
        Result := Format('(call $RT_DynLen %s)',
          [DoEmitExpression(ANode.Args[0])]);
    end;
  end
  else if ANode.Kind = ikSize then
  begin
    if (ANode.Args <> nil) and (ANode.Args.Count > 0) then
    begin
      LArgType := ANode.Args[0].ResolvedType;
      if LArgType = nil then
        LArgType := ANode.Args[0];
      if LArgType is TWklTypeRefNode then
      begin
        if (TWklTypeRefNode(LArgType).ResolvedDecl <> nil) and
          (TWklTypeRefNode(LArgType).ResolvedDecl is TWklTypeDeclNode) then
        begin
          LTypeDeclNode := TWklTypeDeclNode(TWklTypeRefNode(LArgType)
            .ResolvedDecl);
          if LTypeDeclNode.ByteSize > 0 then
            Result := Format('(i64.const %d)', [LTypeDeclNode.ByteSize])
          else
            Result := Format('(i64.const %d)', [DoGetTypeByteSize(LArgType)]);
          Exit;
        end;
      end;
      Result := Format('(i64.const %d)', [DoGetTypeByteSize(LArgType)]);
    end;
  end
  else if ANode.Kind = ikUtf8 then
  begin
    // utf8(s): caller-owned copy of the UTF-8 bytes; a raw pointer, not a
    // managed string, so no string temp
    if (ANode.Args <> nil) and (ANode.Args.Count > 0) then
      Result := Format('(call $RT_Utf8 %s)', [DoEmitExpression(ANode.Args[0])]);
  end
  else if ANode.Kind = ikCStrToStr then
  begin
    // Allocating string producer: MUST go through DoAllocStringTemp so
    // DoEmitAssign's AddRef + set see one local, not two evaluations
    if (ANode.Args <> nil) and (ANode.Args.Count > 0) then
      Result := DoAllocStringTemp(Format('(call $RT_StrFromCStr %s)',
        [DoEmitExpression(ANode.Args[0])]));
  end
  else if ANode.Kind = ikFormat then
    Result := DoEmitFormat(ANode)
  else if ANode.Kind = ikCStr then
  begin
    if (ANode.Args <> nil) and (ANode.Args.Count > 0) then
    begin
      if (ANode.Args[0] is TWklLiteralNode) and
        (TWklLiteralNode(ANode.Args[0]).Kind = lkString) then
        Result := Format('(i64.const %d)',
          [DoAllocString(TWklLiteralNode(ANode.Args[0]).StringValue)])
      else
        Result := Format('(call $RT_StrData %s)',
          [DoEmitExpression(ANode.Args[0])]);
    end;
  end
  else if ANode.Kind = ikWStr then
  begin
    if (ANode.Args <> nil) and (ANode.Args.Count > 0) then
      Result := Format('(call $RT_WStrData %s)',
        [DoEmitExpression(ANode.Args[0])]);
  end;
end;

procedure TWklEmitter.DoEmitStatementList(const AStatements: TWklNodeList);
var
  I: Integer;
begin
  if AStatements = nil then
    Exit;
  for I := 0 to AStatements.Count - 1 do
  begin
    DoEmitStatement(AStatements[I]);
    DoEmitStringTempCleanup();
  end;
end;

procedure TWklEmitter.DoEmitStatement(const ANode: TWklNode);
var
  LVar: TWklVarDeclNode;
begin
  if ANode = nil then
    Exit;
  FCurrentRange := ANode.Location;
  if ANode is TWklAssignNode then
    DoEmitAssign(TWklAssignNode(ANode))
  else if ANode is TWklCallStmtNode then
    DoEmitCallStmt(TWklCallStmtNode(ANode))
  else if ANode is TWklPrintNode then
    DoEmitPrint(TWklPrintNode(ANode))
  else if ANode is TWklIfNode then
    DoEmitIf(TWklIfNode(ANode))
  else if ANode is TWklWhileNode then
    DoEmitWhile(TWklWhileNode(ANode))
  else if ANode is TWklForNode then
    DoEmitFor(TWklForNode(ANode))
  else if ANode is TWklRepeatNode then
    DoEmitRepeat(TWklRepeatNode(ANode))
  else if ANode is TWklReturnNode then
    DoEmitReturn(TWklReturnNode(ANode))
  else if ANode is TWklBreakNode then
  begin
    if FBreakLabels.Count > 0 then
      BLn('br $%s', [FBreakLabels[FBreakLabels.Count - 1]])
    else
      BLn('unreachable ;; break outside loop');
  end
  else if ANode is TWklContinueNode then
  begin
    if FContinueLabels.Count > 0 then
      BLn('br $%s', [FContinueLabels[FContinueLabels.Count - 1]])
    else
      BLn('unreachable ;; continue outside loop');
  end
  else if ANode is TWklMatchNode then
    DoEmitMatch(TWklMatchNode(ANode))
  else if ANode is TWklGuardNode then
    DoEmitGuard(TWklGuardNode(ANode))
  else if ANode is TWklThrowNode then
    DoEmitThrow(TWklThrowNode(ANode))
  else if ANode is TWklThrowCodeNode then
    DoEmitThrowCode(TWklThrowCodeNode(ANode))
  else if ANode is TWklAssertNode then
    DoEmitAssert(TWklAssertNode(ANode))
  else if ANode is TWklMemOpNode then
    DoEmitMemOp(TWklMemOpNode(ANode))
  else if ANode is TWklMemOp2Node then
    DoEmitMemOp2(TWklMemOp2Node(ANode))
  else if ANode is TWklVarDeclNode then
  begin
    LVar := TWklVarDeclNode(ANode);
    // Inline var: the statement is the declaration; materialize on first sight
    if LVar.TypeExpr <> nil then
    begin
      if DoIsMemHomed(LVar) then
        DoDeclareLocal(LVar, 'i64')
      else
        DoDeclareLocal(LVar, DoMapWasmType(LVar.TypeExpr));
    end;
    if LVar.InitExpr <> nil then
      DoEmitVarInit(LVar);
  end;
end;

procedure TWklEmitter.DoEmitAssign(const ANode: TWklAssignNode);
var
  LTarget: TWklNode;
  LValue, LWasmType, LGetOp, LArithOp: string;
  LStoreOp, LStoreAddr, LBase: string;
  LFieldOffset, LBitWidth, LBitOffset, LMask, LClearMask: Int64;
  LDef: TWklNode;
  LArr: TWklArrayTypeNode;
  LField: TWklFieldDeclNode;

begin
  LTarget := ANode.Target;
  if LTarget is TWklIndexAccessNode then
  begin
    LStoreAddr := DoEmitIndexAddress(TWklIndexAccessNode(LTarget));
    LValue := DoEmitExpression(ANode.Value);
    LStoreOp := 'i64.store';
    if TWklIndexAccessNode(LTarget).BaseExpr.ResolvedType <> nil then
    begin
      LDef := DoResolveTypeDef(TWklIndexAccessNode(LTarget)
        .BaseExpr.ResolvedType);
      if LDef is TWklArrayTypeNode then
      begin
        LArr := TWklArrayTypeNode(LDef);
        if LArr.ElementType <> nil then
          LStoreOp := DoMapMemStoreOp(LArr.ElementType);
      end;
    end;
    BLn('(%s %s %s)', [LStoreOp, LStoreAddr, LValue]);
    Exit;
  end;
  if (LTarget is TWklDotAccessNode) and
    (TWklDotAccessNode(LTarget).AccessKind = dakField) then
  begin
    LBase := DoEmitExpression(TWklDotAccessNode(LTarget).BaseExpr);
    LValue := DoEmitExpression(ANode.Value);
    LFieldOffset := 0;
    LField := nil;
    LStoreOp := 'i64.store';
    if TWklDotAccessNode(LTarget).ResolvedDecl is TWklFieldDeclNode then
    begin
      LField := TWklFieldDeclNode(TWklDotAccessNode(LTarget).ResolvedDecl);
      LFieldOffset := LField.ByteOffset;
      if LField.TypeExpr <> nil then
        LStoreOp := DoMapMemStoreOp(LField.TypeExpr);
      LBitWidth := LField.BitWidth;
      if LBitWidth > 0 then
      begin
        LBitOffset := LField.BitPos;
        if FDeclaredLocals.IndexOf('_bf_base') < 0 then
        begin
          DLn('(local $_bf_base i64)');
          FDeclaredLocals.Add('_bf_base');
        end;
        BLn('(local.set $_bf_base %s)', [LBase]);
        LMask := (Int64(1) shl LBitWidth) - 1;
        LClearMask := not(LMask shl LBitOffset);
        BLn('(%s offset=%d', [LStoreOp, LFieldOffset]);
        BLn('  (local.get $_bf_base)');
        BLn('  (i32.or');
        BLn('    (i32.and');
        BLn('      (%s offset=%d (local.get $_bf_base))',
          [StringReplace(LStoreOp, 'store', 'load', []), LFieldOffset]);
        BLn('      (i32.const %d))', [LClearMask and $FFFFFFFF]);
        if LBitOffset > 0 then
          BLn('    (i32.shl (i32.and %s (i32.const %d)) (i32.const %d)))',
            [LValue, LMask, LBitOffset])
        else
          BLn('    (i32.and %s (i32.const %d)))', [LValue, LMask]);
        BLn(')');
        Exit;
      end;
    end;
    // String field: addref new, release old -- same contract as DoVarSet.
    // Pin the base to a temp so a side-effecting base runs once.
    if (LField <> nil) and
      (LField.TypeExpr <> nil) and DoIsStringType(LField.TypeExpr) then
    begin
      if FDeclaredLocals.IndexOf('_sf_base') < 0 then
      begin
        DLn('(local $_sf_base i64)');
        FDeclaredLocals.Add('_sf_base');
      end;
      BLn('(local.set $_sf_base %s)', [LBase]);
      LBase := '(local.get $_sf_base)';
      BLn('(call $RT_StrAddRef %s)', [LValue]);
      BLn('(call $RT_StrRelease (i64.load offset=%d %s))',
        [LFieldOffset, LBase]);
    end;
    if LFieldOffset > 0 then
      BLn('(%s offset=%d %s %s)', [LStoreOp, LFieldOffset, LBase, LValue])
    else
      BLn('(%s %s %s)', [LStoreOp, LBase, LValue]);
    Exit;
  end;
  if LTarget is TWklDerefNode then
  begin
    LBase := DoEmitExpression(TWklDerefNode(LTarget).BaseExpr);
    LValue := DoEmitExpression(ANode.Value);
    if ANode.Target.ResolvedType <> nil then
      LStoreOp := DoMapMemStoreOp(ANode.Target.ResolvedType)
    else
      LStoreOp := 'i64.store';
    BLn('(%s %s %s)', [LStoreOp, LBase, LValue]);
    Exit;
  end;
  if DoDeclOf(ANode.Target) = nil then
  begin
    BLn(';; assign: could not resolve target declaration');
    Exit;
  end;
  LGetOp := DoVarGet(ANode.Target);
  // Record literal assigned to existing var: write fields in place,
  // no new allocation (avoids leaking the old block).
  if (ANode.Value is TWklRecordLiteralNode) and
    (ANode.Target.ResolvedType <> nil) and
    DoIsAggregateType(ANode.Target.ResolvedType) then
  begin
    DoEmitRecordLiteralInto(TWklRecordLiteralNode(ANode.Value),
      LGetOp, 0);
    Exit;
  end;
  // sret direct: aggregate target assigned from a sret call -- pass the
  // target's address directly as sret first arg, no temp or copy needed
  if (ANode.Op = aoAssign) and (ANode.Target.ResolvedType <> nil) and
    DoIsAggregateType(ANode.Target.ResolvedType) and
    (ANode.Value is TWklCallExprNode) then
  begin
    // Release old string fields before the callee overwrites the block
    DoEmitReleaseRecordFields(LGetOp,
      DoResolveTypeDef(ANode.Target.ResolvedType));
    if DoEmitAssignSretDirect(TWklCallExprNode(ANode.Value), LGetOp) then
      Exit;
  end;
  // Aggregate by-value copy: memory.copy instead of pointer alias
  if (ANode.Op = aoAssign) and (ANode.Target.ResolvedType <> nil) and
    DoIsAggregateType(ANode.Target.ResolvedType) then
  begin
    LValue := DoEmitExpression(ANode.Value);
    LDef := DoResolveTypeDef(ANode.Target.ResolvedType);
    // Release old string fields in the target before overwriting
    DoEmitReleaseRecordFields(LGetOp, LDef);
    BLn('(memory.copy %s %s (i64.const %d))',
      [LGetOp, LValue, DoGetTypeByteSize(ANode.Target.ResolvedType)]);
    // AddRef string fields in the target so both copies own their reference
    DoEmitAddRefRecordFields(LGetOp, LDef);
    Exit;
  end;
  LValue := DoEmitExpression(ANode.Value);
  if ANode.Op = aoAssign then
  begin
    if (ANode.Target.ResolvedType <> nil) and
      DoIsStringType(ANode.Target.ResolvedType) then
    begin
      BLn('(call $RT_StrAddRef %s)', [LValue]);
      BLn('(call $RT_StrRelease %s)', [LGetOp]);
    end;
    BLn('%s', [DoVarSet(ANode.Target, LValue)]);
  end
  else
  begin
    if ANode.Target.ResolvedType <> nil then
      LWasmType := DoMapWasmType(ANode.Target.ResolvedType)
    else
      LWasmType := 'i32';
    if ANode.Op = aoAddAssign then
      LArithOp := LWasmType + '.add'
    else if ANode.Op = aoSubAssign then
      LArithOp := LWasmType + '.sub'
    else if ANode.Op = aoMulAssign then
      LArithOp := LWasmType + '.mul'
    else if ANode.Op = aoDivAssign then
    begin
      if (ANode.Target.ResolvedType <> nil) and
        DoIsFloatType(ANode.Target.ResolvedType) then
        LArithOp := LWasmType + '.div'
      else
        LArithOp := LWasmType + '.div_s';
    end
    else
      LArithOp := LWasmType + '.add';
    // Compound: value = (op current value)
    if LArithOp.EndsWith('.div_s') then
      LValue := Format('(call $RT_CheckDiv%s %s)', [UpperCase(LWasmType), LValue]);
    LValue := Format('(%s %s %s)', [LArithOp, LGetOp, LValue]);
    BLn('%s', [DoVarSet(ANode.Target, LValue)]);
  end;
end;

function TWklEmitter.DoEmitAssignSretDirect(const ACall: TWklCallExprNode;
  const ATargetAddr: string): Boolean;
var
  LSb: TStringBuilder;
  LFuncName: string;
  I, LFixed: Integer;
begin
  Result := False;
  // Direct call with sret
  if (ACall.ResolvedRoutine <> nil) and ACall.ResolvedRoutine.IsSret then
  begin
    LFuncName := DoMangledName(ACall.ResolvedRoutine);
    LFixed := ACall.Args.Count;
    if ACall.ResolvedRoutine.IsVariadic then
      LFixed := ACall.ResolvedRoutine.Params.Count;
    LSb := TStringBuilder.Create();
    try
      LSb.Append(Format('(call $%s %s', [LFuncName, ATargetAddr]));
      if ACall.Args <> nil then
        for I := 0 to LFixed - 1 do
          LSb.Append(' ' + DoEmitExpression(ACall.Args[I]));
      if ACall.ResolvedRoutine.IsVariadic then
        LSb.Append(' ' + DoEmitVarArgsPack(ACall.Args, LFixed));
      LSb.Append(')');
      BLn('%s', [LSb.ToString()]);
    finally
      LSb.Free();
    end;
    Result := True;
    Exit;
  end;
  // Indirect call with sret
  if (ACall.ResolvedRoutineType <> nil) and ACall.ResolvedRoutineType.IsSret then
  begin
    LFixed := ACall.Args.Count;
    if ACall.ResolvedRoutineType.IsVariadic then
      LFixed := ACall.ResolvedRoutineType.Params.Count;
    LSb := TStringBuilder.Create();
    try
      LSb.Append('(call_indirect $rt_functable');
      LSb.Append(DoRoutineTypeSignature(ACall.ResolvedRoutineType));
      LSb.Append(' ' + ATargetAddr);
      if ACall.Args <> nil then
        for I := 0 to LFixed - 1 do
          LSb.Append(' ' + DoEmitExpression(ACall.Args[I]));
      if ACall.ResolvedRoutineType.IsVariadic then
        LSb.Append(' ' + DoEmitVarArgsPack(ACall.Args, LFixed));
      LSb.Append(' ' + DoEmitExpression(ACall.Callee));
      LSb.Append(')');
      BLn('%s', [LSb.ToString()]);
    finally
      LSb.Free();
    end;
    Result := True;
  end;
end;

procedure TWklEmitter.DoEmitReturn(const ANode: TWklReturnNode);
var
  LValue: string;
begin
  // Never emit a raw wasm return: the function epilogue (local cleanup)
  // lives after the $_exit block, so a return stores the value in $_ret
  // and branches out to it.
  if ANode.ValueExpr <> nil then
  begin
    LValue := DoEmitExpression(ANode.ValueExpr);
    // sret: copy the local aggregate into the caller's destination
    if FCurrentRoutine.IsSret then
    begin
      BLn('(memory.copy (local.get $_sret) %s (i64.const %d))',
        [LValue, FCurrentRoutine.SretByteSize]);
      // AddRef string fields in the sret destination so they survive the
      // callee's cleanup walk which releases the local's copies
      DoEmitAddRefRecordFields('(local.get $_sret)',
        DoResolveTypeDef(FCurrentRoutine.ReturnType));
      DoEmitStringTempCleanup();
    end
    // A string result is one reference handed to the caller: addref it,
    // then release this statement's temps BEFORE branching so nothing
    // is skipped by the br
    else if DoIsStringType(ANode.ValueExpr.ResolvedType) then
    begin
      BLn('(call $RT_StrAddRef %s)', [LValue]);
      BLn('(local.set $_ret %s)', [LValue]);
      DoEmitStringTempCleanup();
    end
    else
      BLn('(local.set $_ret %s)', [LValue]);
  end;
  BLn('br $_exit');
end;

procedure TWklEmitter.DoEmitCallStmt(const ANode: TWklCallStmtNode);
var
  LCallExpr: TWklCallExprNode;
  LCallWat: string;
  LHasReturn: Boolean;
begin
  // varargs.reset() / varargs.next(T) etc. used as a statement
  if ANode.CallExpr is TWklIntrinsicNode then
  begin
    BLn('%s', [DoEmitExpression(ANode.CallExpr)]);
    if ANode.CallExpr.ResolvedType <> nil then
      BLn('drop');
    Exit;
  end;
  if not(ANode.CallExpr is TWklCallExprNode) then
  begin
    BLn(';; call stmt: expected TWklCallExprNode');
    Exit;
  end;
  LCallExpr := TWklCallExprNode(ANode.CallExpr);
  LCallWat := DoEmitCallExpr(LCallExpr);
  LHasReturn := False;
  if LCallExpr.ResolvedRoutine <> nil then
    LHasReturn := LCallExpr.ResolvedRoutine.ReturnType <> nil
  else if LCallExpr.ResolvedRoutineType <> nil then
    LHasReturn := LCallExpr.ResolvedRoutineType.ReturnType <> nil;
  BLn('%s', [LCallWat]);
  if LHasReturn then
    BLn('drop');
end;

procedure TWklEmitter.DoEmitIf(const ANode: TWklIfNode);
begin
  BLn('%s', [DoEmitExpression(ANode.Condition)]);
  BLn('if');
  DoEmitStatementList(ANode.ThenBody);
  if (ANode.ElseBody <> nil) and (ANode.ElseBody.Count > 0) then
  begin
    BLn('else');
    DoEmitStatementList(ANode.ElseBody);
  end;
  BLn('end');
end;

procedure TWklEmitter.DoEmitWhile(const ANode: TWklWhileNode);
var
  LBreak, LContinue: string;
begin
  Inc(FLabelSeq);
  LBreak := Format('break_%d', [FLabelSeq]);
  LContinue := Format('continue_%d', [FLabelSeq]);
  FBreakLabels.Add(LBreak);
  FContinueLabels.Add(LContinue);
  BLn('block $%s', [LBreak]);
  BLn('loop $%s', [LContinue]);
  BLn('%s', [DoEmitExpression(ANode.Condition)]);
  BLn('i32.eqz');
  BLn('br_if $%s', [LBreak]);
  DoEmitStatementList(ANode.Body);
  BLn('br $%s', [LContinue]);
  BLn('end');
  BLn('end');
  FBreakLabels.Delete(FBreakLabels.Count - 1);
  FContinueLabels.Delete(FContinueLabels.Count - 1);
end;

procedure TWklEmitter.DoEmitFor(const ANode: TWklForNode);
var
  LBreak, LContinue, LWasmType, LCmpOp, LStepOp, LIterName: string;
begin
  if ANode.StartExpr.ResolvedType <> nil then
    LWasmType := DoMapWasmType(ANode.StartExpr.ResolvedType)
  else
    LWasmType := 'i32';
  if ANode.IsDownTo then
  begin
    if (ANode.StartExpr.ResolvedType <> nil) and
      DoIsUnsignedType(ANode.StartExpr.ResolvedType) then
      LCmpOp := LWasmType + '.lt_u'
    else
      LCmpOp := LWasmType + '.lt_s';
    LStepOp := LWasmType + '.sub';
  end
  else
  begin
    if (ANode.StartExpr.ResolvedType <> nil) and
      DoIsUnsignedType(ANode.StartExpr.ResolvedType) then
      LCmpOp := LWasmType + '.gt_u'
    else
      LCmpOp := LWasmType + '.gt_s';
    LStepOp := LWasmType + '.add';
  end;
  Inc(FLabelSeq);
  LBreak := Format('break_%d', [FLabelSeq]);
  LContinue := Format('continue_%d', [FLabelSeq]);
  FBreakLabels.Add(LBreak);
  FContinueLabels.Add(LContinue);
  // The for node is the iterator's declaration (semantics DoAnalyzeFor):
  // it gets its own wasm local, shadowing any outer name
  LIterName := DoDeclareLocal(ANode, LWasmType);
  BLn('%s', [DoEmitExpression(ANode.StartExpr)]);
  BLn('local.set $%s', [LIterName]);
  BLn('block $%s', [LBreak]);
  BLn('loop $%s', [LContinue]);
  BLn('(local.get $%s)', [LIterName]);
  BLn('%s', [DoEmitExpression(ANode.EndExpr)]);
  BLn('%s', [LCmpOp]);
  BLn('br_if $%s', [LBreak]);
  DoEmitStatementList(ANode.Body);
  BLn('(local.get $%s)', [LIterName]);
  BLn('(%s.const 1)', [LWasmType]);
  BLn('%s', [LStepOp]);
  BLn('local.set $%s', [LIterName]);
  BLn('br $%s', [LContinue]);
  BLn('end');
  BLn('end');
  FBreakLabels.Delete(FBreakLabels.Count - 1);
  FContinueLabels.Delete(FContinueLabels.Count - 1);
end;

procedure TWklEmitter.DoEmitRepeat(const ANode: TWklRepeatNode);
var
  LBreak, LContinue: string;
begin
  Inc(FLabelSeq);
  LBreak := Format('break_%d', [FLabelSeq]);
  LContinue := Format('continue_%d', [FLabelSeq]);
  FBreakLabels.Add(LBreak);
  FContinueLabels.Add(LContinue);
  BLn('block $%s', [LBreak]);
  BLn('loop $%s', [LContinue]);
  DoEmitStatementList(ANode.Body);
  BLn('%s', [DoEmitExpression(ANode.UntilCondition)]);
  BLn('i32.eqz');
  BLn('br_if $%s', [LContinue]);
  BLn('end');
  BLn('end');
  FBreakLabels.Delete(FBreakLabels.Count - 1);
  FContinueLabels.Delete(FContinueLabels.Count - 1);
end;

procedure TWklEmitter.DoEmitMatch(const ANode: TWklMatchNode);
var
  LWasmType, LMatchVar, LCmpSuffix: string;
  LArm: TWklMatchArmNode;
  LLabel: TWklMatchLabelNode;
  LArmIdx, LLabelIdx: Integer;
  LIsUnsigned: Boolean;
begin
  if ANode.Scrutinee.ResolvedType <> nil then
  begin
    LWasmType := DoMapWasmType(ANode.Scrutinee.ResolvedType);
    LIsUnsigned := DoIsUnsignedType(ANode.Scrutinee.ResolvedType);
  end
  else
  begin
    LWasmType := 'i32';
    LIsUnsigned := False;
  end;
  if LIsUnsigned then
    LCmpSuffix := '_u'
  else
    LCmpSuffix := '_s';
  Inc(FLabelSeq);
  LMatchVar := Format('__match_%d', [FLabelSeq]);
  DLn('(local $%s %s)', [LMatchVar, LWasmType]);
  BLn('%s', [DoEmitExpression(ANode.Scrutinee)]);
  BLn('local.set $%s', [LMatchVar]);
  if ANode.Arms = nil then
    Exit;
  for LArmIdx := 0 to ANode.Arms.Count - 1 do
  begin
    LArm := TWklMatchArmNode(ANode.Arms[LArmIdx]);
    if LArm.Labels <> nil then
      for LLabelIdx := 0 to LArm.Labels.Count - 1 do
      begin
        LLabel := TWklMatchLabelNode(LArm.Labels[LLabelIdx]);
        if LLabel.RangeEnd <> nil then
        begin
          BLn('(local.get $%s)', [LMatchVar]);
          BLn('%s', [DoEmitExpression(LLabel.ValueExpr)]);
          BLn('%s.ge%s', [LWasmType, LCmpSuffix]);
          BLn('(local.get $%s)', [LMatchVar]);
          BLn('%s', [DoEmitExpression(LLabel.RangeEnd)]);
          BLn('%s.le%s', [LWasmType, LCmpSuffix]);
          BLn('i32.and');
        end
        else
        begin
          BLn('(local.get $%s)', [LMatchVar]);
          BLn('%s', [DoEmitExpression(LLabel.ValueExpr)]);
          BLn('%s.eq', [LWasmType]);
        end;
        if LLabelIdx > 0 then
          BLn('i32.or');
      end;
    BLn('if');
    DoEmitStatementList(LArm.Body);
    if (LArmIdx < ANode.Arms.Count - 1) or
      ((ANode.ElseBody <> nil) and (ANode.ElseBody.Count > 0)) then
      BLn('else');
  end;
  if (ANode.ElseBody <> nil) and (ANode.ElseBody.Count > 0) then
    DoEmitStatementList(ANode.ElseBody);
  for LArmIdx := 0 to ANode.Arms.Count - 1 do
    BLn('end');
end;

procedure TWklEmitter.DoEmitGuard(const ANode: TWklGuardNode);
var
  LCatchLabel, LAfterLabel: string;
begin
  Inc(FLabelSeq);
  LCatchLabel := Format('catch_%d', [FLabelSeq]);
  LAfterLabel := Format('after_%d', [FLabelSeq]);
  BLn('block $%s', [LAfterLabel]);
  BLn('block $%s (result i32 i64)', [LCatchLabel]);
  BLn('try_table (catch $myr_exn $' + LCatchLabel + ')');
  if ANode.GuardBody <> nil then
    DoEmitStatementList(ANode.GuardBody.Statements);
  BLn('end');
  BLn('br $%s', [LAfterLabel]);
  BLn('end');
  if ANode.ExceptBody <> nil then
  begin
    BLn('(call $RT_SetException)');
    DoEmitStatementList(ANode.ExceptBody.Statements);
  end
  else
  begin
    BLn('(call $RT_SetException)');
  end;
  BLn('end');
  if ANode.FinallyBody <> nil then
    DoEmitStatementList(ANode.FinallyBody.Statements);
end;

procedure TWklEmitter.DoEmitThrow(const ANode: TWklThrowNode);
begin
  BLn('(i32.const 1)');
  if ANode.CodeExpr <> nil then
    BLn('%s', [DoEmitExpression(ANode.CodeExpr)])
  else
    BLn('(i64.const 0)');
  BLn('(call $RT_Raise)');
end;

procedure TWklEmitter.DoEmitThrowCode(const ANode: TWklThrowCodeNode);
begin
  BLn('%s', [DoEmitExpression(ANode.CodeExpr)]);
  if ANode.MsgExpr <> nil then
    BLn('%s', [DoEmitExpression(ANode.MsgExpr)])
  else
    BLn('(i64.const 0)');
  BLn('(call $RT_Raise)');
end;

procedure TWklEmitter.DoEmitPrint(const ANode: TWklPrintNode);
  procedure EmitArg(const AArgNode: TWklNode; const ASpec: Char;
    const APrec: Integer);
  var
    LWasmType: string;
    LArgType: TWklNode;
  begin
    if (AArgNode is TWklLiteralNode) and
      (TWklLiteralNode(AArgNode).Kind = lkString) then
    begin
      BLn('(i64.const %d)',
        [DoAllocString(TWklLiteralNode(AArgNode).StringValue)]);
      BLn('(call $rt_write_cstr)');
      Exit;
    end;
    LArgType := AArgNode.ResolvedType;
    if LArgType <> nil then
      LWasmType := DoMapWasmType(LArgType)
    else
      LWasmType := 'i64';
    BLn('%s', [DoEmitExpression(AArgNode)]);
    if ASpec = 'd' then
    begin
      if LWasmType = 'i32' then
      begin
        BLn('(i64.extend_i32_s)');
        BLn('(call $rt_write_i64)');
      end
      else if LWasmType = 'f64' then
      begin
        BLn('(i64.trunc_f64_s)');
        BLn('(call $rt_write_i64)');
      end
      else if LWasmType = 'f32' then
      begin
        BLn('(f64.promote_f32)');
        BLn('(i64.trunc_f64_s)');
        BLn('(call $rt_write_i64)');
      end
      else
        BLn('(call $rt_write_i64)');
    end
    else if ASpec = 'u' then
    begin
      if LWasmType = 'i32' then
      begin
        BLn('(i64.extend_i32_u)');
        BLn('(call $rt_write_u64)');
      end
      else
        BLn('(call $rt_write_u64)');
    end
    else if (ASpec = 'x') or (ASpec = 'X') then
    begin
      if LWasmType = 'i32' then
        BLn('(i64.extend_i32_u)');
      if ASpec = 'X' then
        BLn('(call $rt_write_hex_upper)')
      else
        BLn('(call $rt_write_hex)');
    end
    else if ASpec = 'f' then
    begin
      if LWasmType = 'f32' then
        BLn('(f64.promote_f32)');
      if LWasmType = 'i32' then
        BLn('(f64.convert_i32_s)')
      else if LWasmType = 'i64' then
        BLn('(f64.convert_i64_s)');
      if APrec >= 0 then
        BLn('(call $rt_write_f64_prec (i32.const %d))', [APrec])
      else
        BLn('(call $rt_write_f64)');
    end
    else if ASpec = 's' then
    begin
      if (LArgType <> nil) and DoIsStringType(LArgType) then
        BLn('(call $rt_write_managed_str)')
      else
        BLn('(call $rt_write_cstr)');
    end
    else if ASpec = 'p' then
    begin
      if LWasmType = 'i32' then
        BLn('(i64.extend_i32_u)');
      BLn('(call $rt_write_ptr)');
    end
    else if ASpec = 'c' then
      BLn('(call $rt_write_char)')
    else
    begin
      if LWasmType = 'f32' then
      begin
        BLn('(f64.promote_f32)');
        BLn('(call $rt_write_f64)');
      end
      else if LWasmType = 'f64' then
        BLn('(call $rt_write_f64)')
      else if LWasmType = 'i64' then
      begin
        if (LArgType <> nil) and DoIsStringType(LArgType) then
          BLn('(call $rt_write_managed_str)')
        else if (LArgType <> nil) and DoIsUnsignedType(LArgType) then
          BLn('(call $rt_write_u64)')
        else
          BLn('(call $rt_write_i64)');
      end
      else
      begin
        if (LArgType <> nil) and DoIsUnsignedType(LArgType) then
        begin
          BLn('(i64.extend_i32_u)');
          BLn('(call $rt_write_u64)');
        end
        else
        begin
          BLn('(i64.extend_i32_s)');
          BLn('(call $rt_write_i64)');
        end;
      end;
    end;
  end;

  procedure EmitTextFragment(const AText: string);
  begin
    if AText = '' then
      Exit;
    BLn('(i64.const %d)', [DoAllocString(AText)]);
    BLn('(call $rt_write_cstr)');
  end;

var
  I, LArgIdx, LPos, LLen, LSpecPos, LPrec: Integer;
  LFmt, LFragment: string;
  LCh, LSpecChar: Char;
  LLit: TWklLiteralNode;
begin
  if (ANode.Args <> nil) and (ANode.Args.Count >= 2) and
    (ANode.Args[0] is TWklLiteralNode) and
    (TWklLiteralNode(ANode.Args[0]).Kind = lkString) then
  begin
    LLit := TWklLiteralNode(ANode.Args[0]);
    LFmt := LLit.StringValue;
    LArgIdx := 1;
    LPos := 1;
    LLen := Length(LFmt);
    LFragment := '';
    while LPos <= LLen do
    begin
      LCh := LFmt[LPos];
      if (LCh = '%') and (LPos < LLen) then
      begin
        LSpecPos := LPos + 1;
        LPrec := -1;
        while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos],
          ['-', '+', ' ', '0', '#']) do
          Inc(LSpecPos);
        while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos], ['0' .. '9']) do
          Inc(LSpecPos);
        if (LSpecPos <= LLen) and (LFmt[LSpecPos] = '.') then
        begin
          Inc(LSpecPos);
          LPrec := 0;
          while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos],
            ['0' .. '9']) do
          begin
            LPrec := LPrec * 10 + Ord(LFmt[LSpecPos]) - Ord('0');
            Inc(LSpecPos);
          end;
        end;
        while (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos], ['l', 'h']) do
          Inc(LSpecPos);
        if (LSpecPos <= LLen) and CharInSet(LFmt[LSpecPos],
          ['s', 'd', 'i', 'f', 'u', 'x', 'X', 'p', 'c', 'e', 'E', 'g', 'G'])
        then
        begin
          LSpecChar := LFmt[LSpecPos];
          if LSpecChar = 'i' then
            LSpecChar := 'd'
          else if CharInSet(LSpecChar, ['e', 'E', 'g', 'G']) then
            LSpecChar := 'f';
          EmitTextFragment(LFragment);
          LFragment := '';
          if LArgIdx < ANode.Args.Count then
          begin
            EmitArg(ANode.Args[LArgIdx], LSpecChar, LPrec);
            Inc(LArgIdx);
          end;
          LPos := LSpecPos + 1;
          Continue;
        end
        else if LFmt[LPos + 1] = '%' then
        begin
          LFragment := LFragment + '%';
          Inc(LPos, 2);
          Continue;
        end;
      end;
      LFragment := LFragment + LCh;
      Inc(LPos);
    end;
    EmitTextFragment(LFragment);
  end
  else
  begin
    if ANode.Args <> nil then
      for I := 0 to ANode.Args.Count - 1 do
        EmitArg(ANode.Args[I], #0, -1);
  end;
  if ANode.IsPrintLn then
    BLn('(call $rt_write_newline)');
end;

procedure TWklEmitter.DoEmitAssert(const ANode: TWklAssertNode);
var
  LArgCount: Integer;
  LLeftType: TWklNode;
  LFileOffset: Int64;
  LLine: Integer;
  LTypeName: string;
  LHasMsg: Boolean;
  LArg0, LArg1, LArg2, LArgMsg: string;
  LRtFunc: string;

begin
  if ANode.Args <> nil then
    LArgCount := ANode.Args.Count
  else
    LArgCount := 0;

  LFileOffset := DoAllocString(ANode.Location.Filename);
  LLine := ANode.Location.StartLine;

  // assertfail(msg): unconditional failure
  if ANode.Kind = akAssertFail then
  begin
    if LArgCount > 0 then
      LArg0 := DoEmitExpression(ANode.Args[0])
    else
      LArg0 := '(i64.const 0)';
    BLn('(call $RT_TestFail %s (i64.const %d) (i64.const %d))',
      [LArg0, LFileOffset, LLine]);
    Exit;
  end;

  if LArgCount = 0 then
    Exit;

  // Simple condition asserts
  if (ANode.Kind = akAssert) or (ANode.Kind = akAssertTrue) then
  begin
    LArg0 := DoEmitExpression(ANode.Args[0]);
    BLn('(call $RT_TestAssert %s (i64.const %d) (i64.const %d))',
      [LArg0, LFileOffset, LLine]);
    Exit;
  end;

  if ANode.Kind = akAssertFalse then
  begin
    LArg0 := DoEmitExpression(ANode.Args[0]);
    BLn('(call $RT_TestAssertFalse %s (i64.const %d) (i64.const %d))',
      [LArg0, LFileOffset, LLine]);
    Exit;
  end;

  if ANode.Kind = akAssertNil then
  begin
    LArg0 := DoEmitExprAsI64(ANode.Args[0]);
    BLn('(call $RT_TestAssertNil %s (i64.const %d) (i64.const %d))',
      [LArg0, LFileOffset, LLine]);
    Exit;
  end;

  if ANode.Kind = akAssertNotNil then
  begin
    LArg0 := DoEmitExprAsI64(ANode.Args[0]);
    BLn('(call $RT_TestAssertNotNil %s (i64.const %d) (i64.const %d))',
      [LArg0, LFileOffset, LLine]);
    Exit;
  end;

  // asserteqf(expected, actual, epsilon [, msg])
  if (ANode.Kind = akAssertEqF) and (LArgCount >= 3) then
  begin
    LHasMsg := LArgCount >= 4;
    // Evaluate all args BEFORE building the call (side effects go to FBody first)
    LArg0 := DoEmitExprAsF64(ANode.Args[0]);
    LArg1 := DoEmitExprAsF64(ANode.Args[1]);
    LArg2 := DoEmitExprAsF64(ANode.Args[2]);
    if LHasMsg then
      LArgMsg := DoEmitExpression(ANode.Args[3])
    else
      LArgMsg := '(i64.const 0)';

    BLn('(call $RT_TestAssertCmpFloatTol %s %s %s (i64.const 0) %s (i64.const %d) (i64.const %d))',
      [LArg0, LArg1, LArg2, LArgMsg, LFileOffset, LLine]);
    Exit;
  end;

  // asserteq(expected, actual [, msg])
  if (ANode.Kind = akAssertEq) and (LArgCount >= 2) then
  begin
    LLeftType := ANode.Args[0].ResolvedType;
    LHasMsg := LArgCount >= 3;

    // Determine runtime function and evaluate args
    if DoIsStringType(LLeftType) then
    begin
      LTypeName := DoGetPrimitiveName(LLeftType);
      if LTypeName = 'wstring' then
        LRtFunc := '$RT_TestAssertCmpWStr'
      else
        LRtFunc := '$RT_TestAssertCmpStr';
      LArg0 := DoEmitExpression(ANode.Args[0]);
      LArg1 := DoEmitExpression(ANode.Args[1]);
    end
    else if DoIsFloatType(LLeftType) then
    begin
      LRtFunc := '$RT_TestAssertCmpFloat';
      LArg0 := DoEmitExprAsF64(ANode.Args[0]);
      LArg1 := DoEmitExprAsF64(ANode.Args[1]);
    end
    else
    begin
      LTypeName := DoGetPrimitiveName(LLeftType);
      if LTypeName = 'bool' then
        LRtFunc := '$RT_TestAssertCmpBool'
      else if LTypeName = 'char' then
        LRtFunc := '$RT_TestAssertCmpChar'
      else if LTypeName = 'wchar' then
        LRtFunc := '$RT_TestAssertCmpWChar'
      else if DoIsUnsignedType(LLeftType) then
        LRtFunc := '$RT_TestAssertCmpUInt'
      else if LLeftType is TWklPointerTypeNode then
        LRtFunc := '$RT_TestAssertCmpPtr'
      else
        LRtFunc := '$RT_TestAssertCmpInt';
      LArg0 := DoEmitExprAsI64(ANode.Args[0]);
      LArg1 := DoEmitExprAsI64(ANode.Args[1]);
    end;

    if LHasMsg then
      LArgMsg := DoEmitExpression(ANode.Args[2])
    else
      LArgMsg := '(i64.const 0)';

    BLn('(call %s %s %s (i64.const 0) %s (i64.const %d) (i64.const %d))',
      [LRtFunc, LArg0, LArg1, LArgMsg, LFileOffset, LLine]);
    Exit;
  end;
end;

procedure TWklEmitter.DoEmitRecordLiteralInto(
  const ANode: TWklRecordLiteralNode; const ABase: string;
  const AOffset: Int64);
var
  LFieldInit: TWklFieldInitNode;
  LFieldType: TWklNode;
  LFieldOffset: Int64;
  LValue: string;
  I: Integer;
begin
  if ANode.FieldInits = nil then
    Exit;
  for I := 0 to ANode.FieldInits.Count - 1 do
  begin
    LFieldInit := TWklFieldInitNode(ANode.FieldInits[I]);
    if LFieldInit.ResolvedField = nil then
      Continue;
    LFieldType := LFieldInit.ResolvedField.TypeExpr;
    LFieldOffset := AOffset + LFieldInit.ResolvedField.ByteOffset;
    // Nested record literal: write fields inline at accumulated offset.
    // No allocation -- aggregate fields are inline bytes.
    if (LFieldInit.ValueExpr is TWklRecordLiteralNode) and
      DoIsAggregateType(LFieldType) then
    begin
      DoEmitRecordLiteralInto(TWklRecordLiteralNode(LFieldInit.ValueExpr),
        ABase, LFieldOffset);
      Continue;
    end;
    LValue := DoEmitExpression(LFieldInit.ValueExpr);
    // String field init = new reference: AddRef before store,
    // same contract as DoEmitVarInit.
    if DoIsStringType(LFieldType) then
      BLn('(call $RT_StrAddRef %s)', [LValue]);
    BLn('(%s offset=%d %s %s)',
      [DoMapMemStoreOp(LFieldType), LFieldOffset, ABase, LValue]);
  end;
end;

procedure TWklEmitter.DoEmitAllocInto(const ATarget: TWklNode);
var
  LArgType: TWklNode;
  LDef: TWklNode;
  LSize: Int64;
begin
  LArgType := ATarget.ResolvedType;
  LSize := 8;
  if LArgType <> nil then
  begin
    LDef := DoResolveTypeDef(LArgType);
    if (LDef is TWklPointerTypeNode) and
      (TWklPointerTypeNode(LDef).TargetType <> nil) then
      LSize := DoGetTypeByteSize(TWklPointerTypeNode(LDef).TargetType);
  end;
  if DoDeclOf(ATarget) <> nil then
    BLn('%s', [DoVarSet(ATarget, Format('(call $RT_GetMem (i64.const %d))',
      [LSize]))])
  else
    BLn('(call $RT_GetMem (i64.const %d))', [LSize]);
end;

procedure TWklEmitter.DoEmitFreeInto(const ATarget: TWklNode);
var
  LBase: string;
  LDef: TWklNode;
begin
  LBase := DoEmitExpression(ATarget);
  // Release managed fields (strings) before the block itself is freed.
  // ATarget.ResolvedType is the pointer type; walk to the pointee record.
  if ATarget.ResolvedType <> nil then
  begin
    LDef := DoResolveTypeDef(ATarget.ResolvedType);
    if LDef is TWklPointerTypeNode then
      LDef := DoResolveTypeDef(TWklPointerTypeNode(LDef).TargetType);
    DoEmitReleaseRecordFields(LBase, LDef);
  end;
  BLn('(call $RT_FreeMem %s)', [LBase]);
  // Free contract: the pointer is nil afterwards (dispose and freemem alike)
  if DoDeclOf(ATarget) <> nil then
    BLn('%s', [DoVarSet(ATarget, '(i64.const 0)')]);
end;

procedure TWklEmitter.DoEmitMemOp(const ANode: TWklMemOpNode);
begin
  if ANode.Kind = moNew then
    DoEmitAllocInto(ANode.ArgExpr)
  else if ANode.Kind = moDispose then
    DoEmitFreeInto(ANode.ArgExpr)
  else if ANode.Kind = moGetMem then
    DoEmitAllocInto(ANode.ArgExpr)
  else if ANode.Kind = moFreeMem then
    DoEmitFreeInto(ANode.ArgExpr);
end;

procedure TWklEmitter.DoEmitMemOp2(const ANode: TWklMemOp2Node);
var
  LDef: TWklNode;
  LArr: TWklArrayTypeNode;
  LElemSize: Int64;
  LValue: string;
begin
  if ANode.Kind = mo2ResizeMem then
  begin
    LValue := Format('(call $RT_ReAllocMem %s %s)',
      [DoEmitExpression(ANode.FirstArg), DoEmitExprAsI64(ANode.SecondArg)]);
    if DoDeclOf(ANode.FirstArg) <> nil then
      BLn('%s', [DoVarSet(ANode.FirstArg, LValue)])
    else
      BLn('%s', [LValue]);
  end
  else if ANode.Kind = mo2SetLength then
  begin
    LElemSize := 8;
    if ANode.FirstArg.ResolvedType <> nil then
    begin
      LDef := DoResolveTypeDef(ANode.FirstArg.ResolvedType);
      if LDef is TWklArrayTypeNode then
      begin
        LArr := TWklArrayTypeNode(LDef);
        if LArr.ElementType <> nil then
          LElemSize := DoGetTypeByteSize(LArr.ElementType);
      end;
    end;
    LValue := Format('(call $RT_DynResize %s %s (i64.const %d))',
      [DoEmitExpression(ANode.FirstArg), DoEmitExprAsI64(ANode.SecondArg),
      LElemSize]);
    if DoDeclOf(ANode.FirstArg) <> nil then
      BLn('%s', [DoVarSet(ANode.FirstArg, LValue)])
    else
      BLn('%s', [LValue]);
  end;
end;

procedure TWklEmitter.DoLoadRuntime();
var
  LRuntimePath: string;
begin
  if FModule.ModuleKind = mkLib then
    Exit;

  LRuntimePath := TUtils.ResolvePath(WKL_RES_RUNTIME_WAT);
  if not TFile.Exists(LRuntimePath) then
  begin
    FErrors.RaiseOnError := True;
    FErrors.Add(esFatal, WKL_ERR_EMT_001, RSEmtRuntimeNotFound, [LRuntimePath]);
    Exit;
  end;
  try
    FRuntimeWat := TFile.ReadAllText(LRuntimePath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      FErrors.RaiseOnError := True;
      FErrors.Add(esFatal, WKL_ERR_EMT_002, RSEmtRuntimeReadFailed,
        [E.Message]);
    end;
  end;
end;

// Emit mem-tracking shell functions into FFunctions.
// The corresponding globals are emitted by DoAssembleGlobals.
procedure TWklEmitter.DoEmitMemShellFuncs();
var
  LFunc: TWklEmittedFunc;
  LSb: TStringBuilder;
  LLabelFrees, LLabelLeaked, LLabelPrefix: Int64;
begin
  FNeedMemShells := True;

  LSb := TStringBuilder.Create();
  try
    if FOptimizeLevel = 0 then
    begin
      // Data segments for leak report labels
      LLabelPrefix := DoAllocData(TEncoding.UTF8.GetBytes('[Heap] Allocs: '));
      LLabelFrees := DoAllocData(TEncoding.UTF8.GetBytes(', Frees: '));
      LLabelLeaked := DoAllocData(TEncoding.UTF8.GetBytes(', Leaked: '));

      LSb.Clear();
      LSb.AppendLine('  (func $RT_GetMem (param $ASize i64) (result i64)');
      LSb.AppendLine
        ('    (global.set $rt_alloc_count (i64.add (global.get $rt_alloc_count) (i64.const 1)))');
      LSb.Append('    (call $RT_GetMem_Impl (local.get $ASize)))');
      LFunc.WatText := LSb.ToString();
      LFunc.LineMap := nil;
      FFunctions.Add(LFunc);

      LSb.Clear();
      LSb.AppendLine('  (func $RT_FreeMem (param $APtr i64)');
      LSb.AppendLine('    (if (i64.eqz (local.get $APtr)) (then (return)))');
      LSb.AppendLine
        ('    (global.set $rt_free_count (i64.add (global.get $rt_free_count) (i64.const 1)))');
      LSb.Append('    (call $RT_FreeMem_Impl (local.get $APtr)))');
      LFunc.WatText := LSb.ToString();
      LFunc.LineMap := nil;
      FFunctions.Add(LFunc);

      LSb.Clear();
      LSb.AppendLine('  (func $RT_ReportLeaks');
      LSb.AppendLine
        (Format('    (call $rt_write_bytes (i64.const %d) (i64.const 15))',
        [LLabelPrefix]));
      LSb.AppendLine('    (call $rt_write_i64 (global.get $rt_alloc_count))');
      LSb.AppendLine
        (Format('    (call $rt_write_bytes (i64.const %d) (i64.const 9))',
        [LLabelFrees]));
      LSb.AppendLine('    (call $rt_write_i64 (global.get $rt_free_count))');
      LSb.AppendLine
        (Format('    (call $rt_write_bytes (i64.const %d) (i64.const 10))',
        [LLabelLeaked]));
      LSb.AppendLine
        ('    (call $rt_write_i64 (i64.sub (global.get $rt_alloc_count) (global.get $rt_free_count)))');
      LSb.Append('    (call $rt_write_newline))');
      LFunc.WatText := LSb.ToString();
      LFunc.LineMap := nil;
      FFunctions.Add(LFunc);

      LSb.Clear();
      LSb.AppendLine('  (func $RT_DebugOnExit');
      LSb.Append('    (call $RT_ReportLeaks))');
      LFunc.WatText := LSb.ToString();
      LFunc.LineMap := nil;
      FFunctions.Add(LFunc);
    end
    else
    begin
      LSb.Clear();
      LSb.AppendLine('  (func $RT_GetMem (param $ASize i64) (result i64)');
      LSb.Append('    (call $RT_GetMem_Impl (local.get $ASize)))');
      LFunc.WatText := LSb.ToString();
      LFunc.LineMap := nil;
      FFunctions.Add(LFunc);

      LSb.Clear();
      LSb.AppendLine('  (func $RT_FreeMem (param $APtr i64)');
      LSb.Append('    (call $RT_FreeMem_Impl (local.get $APtr)))');
      LFunc.WatText := LSb.ToString();
      LFunc.LineMap := nil;
      FFunctions.Add(LFunc);

      LFunc.WatText := '  (func $RT_DebugOnExit)';
      LFunc.LineMap := nil;
      FFunctions.Add(LFunc);
    end;
  finally
    LSb.Free();
  end;
end;

// Emit _start function into FFunctions. Walks Declarations INLINE for
// NeedsRuntimeInit consts -- no FExprConstInits list.
procedure TWklEmitter.DoEmitMainBody();
var
  LSb: TStringBuilder;
  LFunc: TWklEmittedFunc;
  LMap: TWklSourceMap;
  I: Integer;
  LStmt: TWklNode;
  LVar: TWklVarDeclNode;
  LWasmType: string;
  LDef: TWklNode;
  LSize: Int64;
  LDecl: TWklNode;
  LNeedsAlloc: Boolean;
  LImportNode: TWklImportNode;
  LUnitModule: TWklModuleNode;
begin
  if FModule.MainBody = nil then
    Exit;
  // In unittest mode, _start is needed even with an empty main body --
  // it hosts the test registrations and RT_TestRunAll call.
  if not (FModule.UnitTestMode and (FModule.TestBlocks.Count > 0)) then
    if (FModule.MainBody.Statements = nil) or
      (FModule.MainBody.Statements.Count = 0) then
      Exit;

  FLocalDecls.Clear();
  FBody.Clear();
  FBodyMap.Clear();
  FDeclaredLocals.Clear();
  FLocalNames.Clear();
  FTempSeq := 0;
  FStringTemps.Clear();
  FPackTemps.Clear();
  FAggTemps.Clear();
  FAggTempCounter := 0;
  SetBodyIndent(2);
  FCurrentRange := Default (TSourceRange);

  // Scan for inline var declarations
  for I := 0 to FModule.MainBody.Statements.Count - 1 do
  begin
    LStmt := FModule.MainBody.Statements[I];
    if LStmt is TWklVarDeclNode then
    begin
      LVar := TWklVarDeclNode(LStmt);
      FCurrentRange := LVar.Location;
      if LVar.TypeExpr <> nil then
      begin
        if DoIsMemHomed(LVar) then
          LWasmType := 'i64'
        else
          LWasmType := DoMapWasmType(LVar.TypeExpr);
        DoDeclareLocal(LVar, LWasmType);
      end;
    end;
  end;

  // Auto-allocate composite and mem-homed locals
  for I := 0 to FModule.MainBody.Statements.Count - 1 do
  begin
    LStmt := FModule.MainBody.Statements[I];
    if LStmt is TWklVarDeclNode then
    begin
      LVar := TWklVarDeclNode(LStmt);
      if LVar.TypeExpr <> nil then
      begin
        LDef := DoResolveTypeDef(LVar.TypeExpr);
        LNeedsAlloc := DoIsMemHomed(LVar);
        if not LNeedsAlloc then
          LNeedsAlloc := (LDef is TWklRecordTypeNode) or
            (LDef is TWklOverlayTypeNode) or
            ((LDef is TWklArrayTypeNode) and
            (not TWklArrayTypeNode(LDef).IsDynamic));
        if LNeedsAlloc then
        begin
          if ((LDef is TWklRecordTypeNode) or (LDef is TWklOverlayTypeNode)) and
            (LVar.InitExpr <> nil) and (LVar.InitExpr is TWklRecordLiteralNode)
          then
            Continue;
          LSize := DoGetTypeByteSize(LVar.TypeExpr);
          BLn('(local.set $%s (call $RT_GetMem (i64.const %d)))',
            [DoLocalNameOf(LVar), LSize]);
        end;
      end;
    end;
  end;

  LSb := TStringBuilder.Create();
  LMap := TWklSourceMap.Create();
  try
    LSb.AppendLine('  (func $_start');
    LMap.Add(Default (TSourceRange));

    FBreakLabels.Clear();
    FContinueLabels.Clear();

    // Init expression-based constants: imported units first, then the exe
    if FModule.Imports <> nil then
      for I := 0 to FModule.Imports.Count - 1 do
      begin
        if (FModule.Imports[I] is TWklImportNode) and
           (TWklImportNode(FModule.Imports[I]).ResolvedModule <> nil) then
          DoEmitRuntimeConstInit(
            TWklImportNode(FModule.Imports[I]).ResolvedModule.Declarations);
      end;
    DoEmitRuntimeConstInit(FModule.Declarations);

    // Allocate heap-backed global vars in linear memory: mem-homed, record,
    // overlay and static array. Imported units first (import order), then the
    // exe, so allocs pair with DoEmitGlobalCleanup's walk order. Vars with a
    // record-literal initializer allocate through $_rl_ptr in DoEmitVarInit.
    if FModule.Imports <> nil then
      for I := 0 to FModule.Imports.Count - 1 do
      begin
        if (FModule.Imports[I] is TWklImportNode) and
           (TWklImportNode(FModule.Imports[I]).ResolvedModule <> nil) then
          DoEmitGlobalAlloc(
            TWklImportNode(FModule.Imports[I]).ResolvedModule.Declarations);
      end;
    DoEmitGlobalAlloc(FModule.Declarations);

    // Module-level var initializers (e.g. x: int32 = 10)
    for I := 0 to FModule.Declarations.Count - 1 do
      begin
        LDecl := FModule.Declarations[I];
        if (LDecl is TWklVarDeclNode) and
          (TWklVarDeclNode(LDecl).InitExpr <> nil) and
          (not TWklVarDeclNode(LDecl).IsExternal) then
          DoEmitVarInit(TWklVarDeclNode(LDecl));
      end;

    // Unit initialize sections, in import order
    if FModule.Imports <> nil then
      for I := 0 to FModule.Imports.Count - 1 do
      begin
        if not(FModule.Imports[I] is TWklImportNode) then
          Continue;
        LImportNode := TWklImportNode(FModule.Imports[I]);
        LUnitModule := LImportNode.ResolvedModule;
        if (LUnitModule <> nil) and (LUnitModule.InitBlock <> nil) and
          (LUnitModule.InitBlock.Statements <> nil) and
          (LUnitModule.InitBlock.Statements.Count > 0) then
          BLn('(call $%s_init)', [LImportNode.Name]);
      end;

    // This module's initialize section, after all unit inits
    if (FModule.InitBlock <> nil) and (FModule.InitBlock.Statements <> nil) and
      (FModule.InitBlock.Statements.Count > 0) then
      BLn('(call $_module_init)');

    if FModule.UnitTestMode and (FModule.TestBlocks.Count > 0) then
    begin
      // Unittest mode: register each test block, then run all tests.
      // Table index = (existing routine count) + 1 (slot 0 reserved) + I.
      DoEmitTestRegistrations();
      BLn('(drop (call $RT_TestRunAll))');
    end
    else
    begin
      BLn('(block $_exit');
      DoEmitStatementList(FModule.MainBody.Statements);
      BLn(')');

      // Release strings and free composite locals declared inline in main
      DoEmitVarListCleanup(FModule.MainBody.Statements);
    end;

    if FLocalDecls.Length > 0 then
      LSb.Append(FLocalDecls.ToString());
    if FBody.Length > 0 then
      LSb.Append(FBody.ToString());
    for I := 0 to FBodyMap.Count - 1 do
      LMap.Add(FBodyMap[I]);

    LSb.Append('  )');
    LFunc.WatText := LSb.ToString();
    LFunc.LineMap := LMap.ToArray();
    FFunctions.Add(LFunc);
  finally
    LMap.Free();
    LSb.Free();
  end;
end;

procedure TWklEmitter.DoEmitShutdownFunc();
var
  LSb: TStringBuilder;
  LFunc: TWklEmittedFunc;
  I: Integer;
  LImportNode: TWklImportNode;
  LUnitModule: TWklModuleNode;
begin
  if FModule.ModuleKind = mkLib then
    Exit;
  if FModule.MainBody = nil then
    Exit;

  FBody.Clear();
  SetBodyIndent(2);

  // User shutdown handler (frame.Run's third argument), before any teardown.
  // 0 = nil = no handler; table slot 0 is reserved (see DoFuncTableIndex).
  BLn('(if (i32.ne (local.get $AIdx) (i32.const 0))');
  BLn('  (then (call_indirect $rt_functable (local.get $AIdx))))');

  // This module's finalize section, before unit finals
  if (FModule.FinalizeBlock <> nil) and
    (FModule.FinalizeBlock.Statements <> nil) and
    (FModule.FinalizeBlock.Statements.Count > 0) then
    BLn('(call $_module_final)');

  // Unit finalize sections, in reverse import order
  if FModule.Imports <> nil then
    for I := FModule.Imports.Count - 1 downto 0 do
    begin
      if not(FModule.Imports[I] is TWklImportNode) then
        Continue;
      LImportNode := TWklImportNode(FModule.Imports[I]);
      LUnitModule := LImportNode.ResolvedModule;
      if (LUnitModule <> nil) and (LUnitModule.FinalizeBlock <> nil) and
        (LUnitModule.FinalizeBlock.Statements <> nil) and
        (LUnitModule.FinalizeBlock.Statements.Count > 0) then
        BLn('(call $%s_final)', [LImportNode.Name]);
    end;

  // Free heap-owning globals: imported units first (reverse order), then
  // this module. Unit finals have already run so their globals are dead.
  if FModule.Imports <> nil then
    for I := FModule.Imports.Count - 1 downto 0 do
    begin
      if not(FModule.Imports[I] is TWklImportNode) then
        Continue;
      LImportNode := TWklImportNode(FModule.Imports[I]);
      LUnitModule := LImportNode.ResolvedModule;
      if LUnitModule <> nil then
        DoEmitGlobalCleanup(LUnitModule.Declarations);
    end;
  DoEmitGlobalCleanup(FModule.Declarations);

  // Runtime-owned state: last exception message
  BLn('(call $RT_ClearException)');

  // Debug mode leak report
  if FOptimizeLevel = 0 then
    BLn('(call $RT_ReportLeaks)');

  LSb := TStringBuilder.Create();
  try
    LSb.AppendLine('  (func $_shutdown (param $AIdx i32)');
    if FBody.Length > 0 then
      LSb.Append(FBody.ToString());
    LSb.Append('  )');
    LFunc.WatText := LSb.ToString();
    LFunc.LineMap := nil;
    FFunctions.Add(LFunc);
  finally
    LSb.Free();
  end;
end;

procedure TWklEmitter.DoEmitFrameFunc();
var
  LSb: TStringBuilder;
  LFunc: TWklEmittedFunc;
begin
  if FModule.ModuleKind = mkLib then
    Exit;

  LSb := TStringBuilder.Create();
  try
    LSb.AppendLine('  (func $_frame (param $AIdx i32) (param $ADt f64)');
    LSb.Append('    (call_indirect $rt_functable (param f64) (local.get $ADt) (local.get $AIdx)))');
    LFunc.WatText := LSb.ToString();
    LFunc.LineMap := nil;
    FFunctions.Add(LFunc);

    // Generic trampoline for parameterless routine references (render,
    // click, timer handlers): JS calls _call0(idx).
    LSb.Clear();
    LSb.AppendLine('  (func $_call0 (param $AIdx i32)');
    LSb.Append('    (call_indirect $rt_functable (local.get $AIdx)))');
    LFunc.WatText := LSb.ToString();
    LFunc.LineMap := nil;
    FFunctions.Add(LFunc);
  finally
    LSb.Free();
  end;
end;

// Emits each test block as a parameterless void function ($test_0, $test_1, ...).
// Follows the same pattern as DoEmitModuleBlock: reset per-function state,
// scan LocalVars for inline decl + mem-homed alloc, emit Statements, cleanup.
procedure TWklEmitter.DoEmitTestBlocks();
var
  I, J: Integer;
  LTestBlock: TWklTestBlockNode;
  LSb: TStringBuilder;
  LFunc: TWklEmittedFunc;
  LMap: TWklSourceMap;
  LStmt: TWklNode;
  LVar: TWklVarDeclNode;
  LWasmType: string;
  LDef: TWklNode;
  LSize: Int64;
  LNeedsAlloc: Boolean;

  // Same two passes DoEmitMainBody runs over its statements: declare the
  // wasm locals, then heap-allocate composite / mem-homed ones.
  procedure DeclareLocals(const AList: TWklNodeList);
  var
    J: Integer;
  begin
    if AList = nil then
      Exit;
    for J := 0 to AList.Count - 1 do
    begin
      LStmt := AList[J];
      if LStmt is TWklVarDeclNode then
      begin
        LVar := TWklVarDeclNode(LStmt);
        if LVar.TypeExpr <> nil then
        begin
          if DoIsMemHomed(LVar) then
            LWasmType := 'i64'
          else
            LWasmType := DoMapWasmType(LVar.TypeExpr);
          DoDeclareLocal(LVar, LWasmType);
        end;
      end;
    end;
  end;

  procedure AllocLocals(const AList: TWklNodeList);
  var
    J: Integer;
  begin
    if AList = nil then
      Exit;
    for J := 0 to AList.Count - 1 do
    begin
      LStmt := AList[J];
      if LStmt is TWklVarDeclNode then
      begin
        LVar := TWklVarDeclNode(LStmt);
        if LVar.TypeExpr <> nil then
        begin
          LDef := DoResolveTypeDef(LVar.TypeExpr);
          LNeedsAlloc := DoIsMemHomed(LVar);
          if not LNeedsAlloc then
            LNeedsAlloc := (LDef is TWklRecordTypeNode) or
              (LDef is TWklOverlayTypeNode) or
              ((LDef is TWklArrayTypeNode) and
              (not TWklArrayTypeNode(LDef).IsDynamic));
          if LNeedsAlloc then
          begin
            if ((LDef is TWklRecordTypeNode) or (LDef is TWklOverlayTypeNode)) and
              (LVar.InitExpr <> nil) and (LVar.InitExpr is TWklRecordLiteralNode)
            then
              Continue;
            LSize := DoGetTypeByteSize(LVar.TypeExpr);
            BLn('(local.set $%s (call $RT_GetMem (i64.const %d)))',
              [DoLocalNameOf(LVar), LSize]);
          end;
        end;
      end;
    end;
  end;

begin
  for I := 0 to FModule.TestBlocks.Count - 1 do
  begin
    LTestBlock := TWklTestBlockNode(FModule.TestBlocks[I]);

    // Reset per-function state
    FLocalDecls.Clear();
    FBody.Clear();
    FBodyMap.Clear();
    FDeclaredLocals.Clear();
    FLocalNames.Clear();
    FTempSeq := 0;
    FStringTemps.Clear();
    FPackTemps.Clear();
    FAggTemps.Clear();
    FAggTempCounter := 0;
    SetBodyIndent(2);
    FCurrentRange := LTestBlock.Location;

    DeclareLocals(LTestBlock.LocalVars);
    DeclareLocals(LTestBlock.Statements);
    AllocLocals(LTestBlock.LocalVars);
    AllocLocals(LTestBlock.Statements);

    LSb := TStringBuilder.Create();
    LMap := TWklSourceMap.Create();
    try
      LSb.AppendLine(Format('  (func $test_%d', [I]));
      LMap.Add(LTestBlock.Location);

      FBreakLabels.Clear();
      FContinueLabels.Clear();
      BLn('(block $_exit');
      DoEmitStatementList(LTestBlock.Statements);
      BLn(')');
      DoEmitVarListCleanup(LTestBlock.Statements);

      // Also cleanup LocalVars if present
      if LTestBlock.LocalVars <> nil then
        DoEmitVarListCleanup(LTestBlock.LocalVars);

      if FLocalDecls.Length > 0 then
        LSb.Append(FLocalDecls.ToString());
      if FBody.Length > 0 then
        LSb.Append(FBody.ToString());
      for J := 0 to FBodyMap.Count - 1 do
        LMap.Add(FBodyMap[J]);

      LSb.Append('  )');
      LFunc.WatText := LSb.ToString();
      LFunc.LineMap := LMap.ToArray();
      FFunctions.Add(LFunc);
    finally
      LMap.Free();
      LSb.Free();
    end;
  end;
end;

// Called from DoEmitMainBody when UnitTestMode is true. Emits
// $RT_TestRegister calls for each test block. Test names and filenames
// are allocated as data segment strings. Table indices are computed by
// counting existing routines (DoWalkTableRoutines) + 1 (slot 0 reserved).
procedure TWklEmitter.DoEmitTestRegistrations();
var
  I: Integer;
  LTestBlock: TWklTestBlockNode;
  LNameOffset: Int64;
  LFileOffset: Int64;
  LTableBase: Integer;
  LLine: Integer;
begin
  // Count existing routines to find where test funcs start in the table
  LTableBase := 0;
  DoWalkTableRoutines(
    procedure(const ANode: TWklRoutineDeclNode)
    begin
      Inc(LTableBase);
    end);
  // Slot 0 is reserved, so first routine is at index 1.
  // Test funcs are appended after existing routines in DoAssembleTable.

  for I := 0 to FModule.TestBlocks.Count - 1 do
  begin
    LTestBlock := TWklTestBlockNode(FModule.TestBlocks[I]);
    LNameOffset := DoAllocString(LTestBlock.Name);
    LFileOffset := DoAllocString(LTestBlock.Location.Filename);
    LLine := LTestBlock.Location.StartLine;

    // $RT_TestRegister(AName: i64, AFunc: i64, AFile: i64, ALine: i64) -> i32
    BLn('(drop (call $RT_TestRegister');
    BLn('  (i64.const %d)', [LNameOffset]);
    BLn('  (i64.const %d)', [LTableBase + 1 + I]);
    BLn('  (i64.const %d)', [LFileOffset]);
    BLn('  (i64.const %d)))', [LLine]);
  end;
end;

// Phase 1: walk AST and emit all routine bodies into FFunctions.
// String literals create FDataSegments as a side effect.
procedure TWklEmitter.DoEmitAllBodies();
var
  I, J, K: Integer;
  LDecl: TWklNode;
  LGroup: TWklOverloadGroupNode;
  LImportNode: TWklImportNode;
  LUnitModule: TWklModuleNode;
begin
  // This module's routine bodies
  if FModule.Declarations <> nil then
    for I := 0 to FModule.Declarations.Count - 1 do
    begin
      LDecl := FModule.Declarations[I];
      if (LDecl is TWklRoutineDeclNode) and
        (not TWklRoutineDeclNode(LDecl).IsExternal) then
        DoEmitRoutine(TWklRoutineDeclNode(LDecl))
      else if LDecl is TWklOverloadGroupNode then
      begin
        LGroup := TWklOverloadGroupNode(LDecl);
        if LGroup.Routines <> nil then
          for J := 0 to LGroup.Routines.Count - 1 do
            if (LGroup.Routines[J] is TWklRoutineDeclNode) and
              (not TWklRoutineDeclNode(LGroup.Routines[J]).IsExternal) then
              DoEmitRoutine(TWklRoutineDeclNode(LGroup.Routines[J]));
      end;
    end;

  // Imported-unit routine bodies
  if FModule.Imports <> nil then
    for I := 0 to FModule.Imports.Count - 1 do
    begin
      if not(FModule.Imports[I] is TWklImportNode) then
        Continue;
      LImportNode := TWklImportNode(FModule.Imports[I]);
      if LImportNode.ResolvedModule = nil then
        Continue;
      LUnitModule := LImportNode.ResolvedModule;
      if LUnitModule.Declarations = nil then
        Continue;

      for J := 0 to LUnitModule.Declarations.Count - 1 do
      begin
        LDecl := LUnitModule.Declarations[J];
        if (LDecl is TWklRoutineDeclNode) and
          (not TWklRoutineDeclNode(LDecl).IsExternal) then
          DoEmitRoutine(TWklRoutineDeclNode(LDecl))
        else if LDecl is TWklOverloadGroupNode then
        begin
          LGroup := TWklOverloadGroupNode(LDecl);
          if LGroup.Routines <> nil then
            for K := 0 to LGroup.Routines.Count - 1 do
              if (LGroup.Routines[K] is TWklRoutineDeclNode) and
                (not TWklRoutineDeclNode(LGroup.Routines[K]).IsExternal) then
                DoEmitRoutine(TWklRoutineDeclNode(LGroup.Routines[K]));
        end;
      end;
    end;

  // Imported-unit initialize / finalize sections as named functions.
  // Called from _start: inits in import order, finals in reverse.
  if FModule.Imports <> nil then
    for I := 0 to FModule.Imports.Count - 1 do
    begin
      if not(FModule.Imports[I] is TWklImportNode) then
        Continue;
      LImportNode := TWklImportNode(FModule.Imports[I]);
      if LImportNode.ResolvedModule = nil then
        Continue;
      LUnitModule := LImportNode.ResolvedModule;
      if (LUnitModule.InitBlock <> nil) and
        (LUnitModule.InitBlock.Statements <> nil) and
        (LUnitModule.InitBlock.Statements.Count > 0) then
        DoEmitModuleBlock(LUnitModule.InitBlock, LImportNode.Name + '_init');
      if (LUnitModule.FinalizeBlock <> nil) and
        (LUnitModule.FinalizeBlock.Statements <> nil) and
        (LUnitModule.FinalizeBlock.Statements.Count > 0) then
        DoEmitModuleBlock(LUnitModule.FinalizeBlock,
          LImportNode.Name + '_final');
    end;

  // This module's own initialize / finalize sections
  if (FModule.InitBlock <> nil) and (FModule.InitBlock.Statements <> nil) and
    (FModule.InitBlock.Statements.Count > 0) then
    DoEmitModuleBlock(FModule.InitBlock, '_module_init');
  if (FModule.FinalizeBlock <> nil) and
    (FModule.FinalizeBlock.Statements <> nil) and
    (FModule.FinalizeBlock.Statements.Count > 0) then
    DoEmitModuleBlock(FModule.FinalizeBlock, '_module_final');

  // Main body (_start)
  if FModule.ModuleKind <> mkLib then
    DoEmitMainBody();

  // Test block bodies ($test_0, $test_1, ...)
  if FModule.UnitTestMode and (FModule.TestBlocks.Count > 0) then
    DoEmitTestBlocks();

  // Teardown + frame trampoline (exe only, guard inside each method)
  DoEmitShutdownFunc();
  DoEmitFrameFunc();

  // Memory shell functions
  if FModule.ModuleKind <> mkLib then
    DoEmitMemShellFuncs();
end;

procedure TWklEmitter.DoWalkTableRoutines(const AProc: TWklRoutineVisitor);

  procedure WalkDecls(const ADecls: TWklNodeList);
  var
    I: Integer;
    J: Integer;
    LDecl: TWklNode;
    LGroup: TWklOverloadGroupNode;
  begin
    if ADecls = nil then
      Exit;
    for I := 0 to ADecls.Count - 1 do
    begin
      LDecl := ADecls[I];
      if (LDecl is TWklRoutineDeclNode) and
        (not TWklRoutineDeclNode(LDecl).IsExternal) then
        AProc(TWklRoutineDeclNode(LDecl))
      else if LDecl is TWklOverloadGroupNode then
      begin
        LGroup := TWklOverloadGroupNode(LDecl);
        if LGroup.Routines <> nil then
          for J := 0 to LGroup.Routines.Count - 1 do
            if (LGroup.Routines[J] is TWklRoutineDeclNode) and
              (not TWklRoutineDeclNode(LGroup.Routines[J]).IsExternal) then
              AProc(TWklRoutineDeclNode(LGroup.Routines[J]));
      end;
    end;
  end;

var
  I: Integer;
  LImportNode: TWklImportNode;
begin
  // Same order as DoEmitAllBodies: this module, then each imported unit
  WalkDecls(FModule.Declarations);
  if FModule.Imports <> nil then
    for I := 0 to FModule.Imports.Count - 1 do
    begin
      if not(FModule.Imports[I] is TWklImportNode) then
        Continue;
      LImportNode := TWklImportNode(FModule.Imports[I]);
      if LImportNode.ResolvedModule = nil then
        Continue;
      WalkDecls(LImportNode.ResolvedModule.Declarations);
    end;
end;

function TWklEmitter.DoFuncTableIndex(const ARoutine: TWklRoutineDeclNode): Integer;
var
  LIndex: Integer;
  LFound: Integer;
begin
  // Slot 0 is reserved so that a routine reference is never 0: nil = 0 =
  // "no routine" for every routine-typed value, in wasm and at the JS boundary.
  LIndex := 1;
  LFound := -1;
  DoWalkTableRoutines(
    procedure(const ANode: TWklRoutineDeclNode)
    begin
      if (LFound < 0) and (ANode = ARoutine) then
        LFound := LIndex;
      Inc(LIndex);
    end);
  Result := LFound;
end;

function TWklEmitter.DoEmitFuncRef(const ADecl: TWklNode; const AName: string): string;
var
  LIndex: Integer;
begin
  // A routine used as a value is its index in the function table
  LIndex := -1;
  if FModule.ModuleKind = mkLib then
  begin
    // Libs carry no runtime and therefore no function table (DoAssembleTable)
    FErrors.Add(esFatal, WKL_ERR_EMT_004,
      'Routine reference ''%s'' is not supported in a lib module', [AName]);
    Exit('(i32.const 0)');
  end;
  if ADecl is TWklRoutineDeclNode then
    LIndex := DoFuncTableIndex(TWklRoutineDeclNode(ADecl));
  if LIndex < 0 then
  begin
    FErrors.Add(esFatal, WKL_ERR_EMT_003,
      'Routine ''%s'' has no function table entry (external or overloaded)',
      [AName]);
    LIndex := 0;
  end;
  Result := Format('(i32.const %d) (; funcref $%s ;)', [LIndex, AName]);
end;

function TWklEmitter.DoRoutineTypeSignature(const AType: TWklRoutineTypeNode): string;
var
  I: Integer;
  LSb: TStringBuilder;
  LParam: TWklParamNode;
begin
  LSb := TStringBuilder.Create();
  try
    // sret: hidden first i64 param for the destination pointer
    if AType.IsSret then
      LSb.Append(' (param i64)');
    if AType.Params <> nil then
      for I := 0 to AType.Params.Count - 1 do
      begin
        LParam := TWklParamNode(AType.Params[I]);
        LSb.Append(Format(' (param %s)', [DoMapWasmType(LParam.TypeExpr)]));
      end;
    if AType.IsVariadic then
      LSb.Append(' (param i64)');
    // sret: function is void, no result
    if (AType.ReturnType <> nil) and (not AType.IsSret) then
      LSb.Append(Format(' (result %s)', [DoMapWasmType(AType.ReturnType)]));
    Result := LSb.ToString();
  finally
    LSb.Free();
  end;
end;

procedure TWklEmitter.DoAssembleTable();
var
  LCount: Integer;
  LSb: TStringBuilder;
  I: Integer;
begin
  // Lib modules carry no runtime, so $rt_functable does not exist there;
  // routine references inside a lib are rejected in DoFuncTableIndex.
  if FModule.ModuleKind = mkLib then
    Exit;
  LCount := 0;
  LSb := TStringBuilder.Create();
  try
    DoWalkTableRoutines(
      procedure(const ANode: TWklRoutineDeclNode)
      begin
        LSb.Append(' $' + DoMangledName(ANode));
        Inc(LCount);
      end);
    // Append test block functions after regular routines
    if FModule.UnitTestMode and (FModule.TestBlocks.Count > 0) then
      for I := 0 to FModule.TestBlocks.Count - 1 do
      begin
        LSb.Append(Format(' $test_%d', [I]));
        Inc(LCount);
      end;

    if LCount = 0 then
      Exit;
    // The runtime declares $rt_functable (256 funcref) and never populates
    // it; MVP wasm allows one table, so all routines go in that one.
    // Slot 0 is reserved (nil routine reference), so 255 routines fit.
    if LCount > 255 then
      FErrors.Add(esFatal, WKL_ERR_EMT_003,
        'Too many routines for $rt_functable (%d > 255)', [LCount]);
    WLn('(elem (table $rt_functable) (i32.const 1) func%s)', [LSb.ToString()]);
    WLn();
  finally
    LSb.Free();
  end;
end;

// Walk AST for IsExternal declarations and emit (import ...) lines directly.
procedure TWklEmitter.DoAssembleImports();

  procedure EmitExternRoutine(const ANode: TWklRoutineDeclNode);
  var
    LSb: TStringBuilder;
    LModule, LFuncName, LParamType, LReturnType: string;
    I: Integer;
  begin
    if ANode.ExternLib <> '' then
      LModule := ANode.ExternLib
    else
      LModule := 'env';
    if ANode.ExternSymbol <> '' then
      LFuncName := ANode.ExternSymbol
    else
      LFuncName := ANode.Name;

    LSb := TStringBuilder.Create();
    try
      LSb.Append(Format('(import "%s" "%s" (func $%s', [LModule, LFuncName,
        DoMangledName(ANode)]));
      // sret: hidden first i64 param + no result
      if ANode.IsSret then
      begin
        LSb.Append(' (param i64');
        if ANode.Params <> nil then
          for I := 0 to ANode.Params.Count - 1 do
          begin
            LParamType := DoMapWasmType(TWklParamNode(ANode.Params[I]).TypeExpr);
            LSb.Append(' ' + LParamType);
          end;
        LSb.Append(')');
      end
      else if ANode.Params <> nil then
      begin
        LSb.Append(' (param');
        for I := 0 to ANode.Params.Count - 1 do
        begin
          LParamType := DoMapWasmType(TWklParamNode(ANode.Params[I]).TypeExpr);
          LSb.Append(' ' + LParamType);
        end;
        LSb.Append(')');
      end;
      if (ANode.ReturnType <> nil) and (not ANode.IsSret) then
      begin
        LReturnType := DoMapWasmType(ANode.ReturnType);
        LSb.Append(Format(' (result %s)', [LReturnType]));
      end;
      LSb.Append('))');
      WLn('%s', [LSb.ToString()]);
    finally
      LSb.Free();
    end;
  end;

var
  I, J, K: Integer;
  LDecl: TWklNode;
  LGroup: TWklOverloadGroupNode;
  LImportNode: TWklImportNode;
  LUnitModule: TWklModuleNode;
  LHadImports: Boolean;
begin
  LHadImports := False;

  // External vars from this module
  if FModule.Declarations <> nil then
    for I := 0 to FModule.Declarations.Count - 1 do
    begin
      LDecl := FModule.Declarations[I];
      if (LDecl is TWklVarDeclNode) and TWklVarDeclNode(LDecl).IsExternal then
      begin
        WLn('(import "%s" "%s" (global $%s (mut %s)))',
          [TWklVarDeclNode(LDecl).ExternLib, TWklVarDeclNode(LDecl)
          .ExternSymbol, DoGlobalName(LDecl), DoMapWasmType(TWklVarDeclNode(LDecl)
          .TypeExpr)]);
        LHadImports := True;
      end;
    end;

  // External routines from this module
  if FModule.Declarations <> nil then
    for I := 0 to FModule.Declarations.Count - 1 do
    begin
      LDecl := FModule.Declarations[I];
      if (LDecl is TWklRoutineDeclNode) and TWklRoutineDeclNode(LDecl).IsExternal
      then
      begin
        EmitExternRoutine(TWklRoutineDeclNode(LDecl));
        LHadImports := True;
      end
      else if LDecl is TWklOverloadGroupNode then
      begin
        LGroup := TWklOverloadGroupNode(LDecl);
        if LGroup.Routines <> nil then
          for J := 0 to LGroup.Routines.Count - 1 do
            if (LGroup.Routines[J] is TWklRoutineDeclNode) and
              TWklRoutineDeclNode(LGroup.Routines[J]).IsExternal then
            begin
              EmitExternRoutine(TWklRoutineDeclNode(LGroup.Routines[J]));
              LHadImports := True;
            end;
      end;
    end;

  // Imported-unit consts, vars, and external routines
  if FModule.Imports <> nil then
    for I := 0 to FModule.Imports.Count - 1 do
    begin
      if not(FModule.Imports[I] is TWklImportNode) then
        Continue;
      LImportNode := TWklImportNode(FModule.Imports[I]);
      if LImportNode.ResolvedModule = nil then
        Continue;
      LUnitModule := LImportNode.ResolvedModule;
      if LUnitModule.Declarations = nil then
        Continue;

      for J := 0 to LUnitModule.Declarations.Count - 1 do
      begin
        LDecl := LUnitModule.Declarations[J];
        if (LDecl is TWklRoutineDeclNode) and TWklRoutineDeclNode(LDecl).IsExternal
        then
        begin
          EmitExternRoutine(TWklRoutineDeclNode(LDecl));
          LHadImports := True;
        end
        else if LDecl is TWklOverloadGroupNode then
        begin
          LGroup := TWklOverloadGroupNode(LDecl);
          if LGroup.Routines <> nil then
            for K := 0 to LGroup.Routines.Count - 1 do
              if (LGroup.Routines[K] is TWklRoutineDeclNode) and
                TWklRoutineDeclNode(LGroup.Routines[K]).IsExternal then
              begin
                EmitExternRoutine(TWklRoutineDeclNode(LGroup.Routines[K]));
                LHadImports := True;
              end;
        end;
      end;
    end;

  if LHadImports then
    WLn();
end;

// Walk AST for consts and vars, emit (global ...) lines directly.
procedure TWklEmitter.DoAssembleGlobals();
var
  I, J: Integer;
  LDecl: TWklNode;
  LHadGlobals: Boolean;
  LImportNode: TWklImportNode;
  LUnitModule: TWklModuleNode;
begin
  LHadGlobals := False;

  // This module's consts and vars
  if FModule.Declarations <> nil then
    for I := 0 to FModule.Declarations.Count - 1 do
    begin
      LDecl := FModule.Declarations[I];
      if LDecl is TWklConstDeclNode then
      begin
        DoEmitGlobalConst(TWklConstDeclNode(LDecl));
        LHadGlobals := True;
      end
      else if LDecl is TWklVarDeclNode then
      begin
        DoEmitGlobalVar(TWklVarDeclNode(LDecl));
        if not TWklVarDeclNode(LDecl).IsExternal then
          LHadGlobals := True;
      end;
    end;

  // Imported-unit consts and vars
  if FModule.Imports <> nil then
    for I := 0 to FModule.Imports.Count - 1 do
    begin
      if not(FModule.Imports[I] is TWklImportNode) then
        Continue;
      LImportNode := TWklImportNode(FModule.Imports[I]);
      if LImportNode.ResolvedModule = nil then
        Continue;
      LUnitModule := LImportNode.ResolvedModule;
      if LUnitModule.Declarations = nil then
        Continue;

      for J := 0 to LUnitModule.Declarations.Count - 1 do
      begin
        LDecl := LUnitModule.Declarations[J];
        if LDecl is TWklConstDeclNode then
        begin
          DoEmitGlobalConst(TWklConstDeclNode(LDecl));
          LHadGlobals := True;
        end
        else if LDecl is TWklVarDeclNode then
        begin
          DoEmitGlobalVar(TWklVarDeclNode(LDecl));
          if not TWklVarDeclNode(LDecl).IsExternal then
            LHadGlobals := True;
        end;
      end;
    end;

  // Runtime globals for mem tracking
  if FNeedMemShells and (FOptimizeLevel = 0) then
  begin
    WLn('(global $rt_alloc_count (mut i64) (i64.const 0))');
    WLn('(global $rt_free_count (mut i64) (i64.const 0))');
    LHadGlobals := True;
  end;

  if LHadGlobals then
    WLn();
end;

// Walk AST for IsPublic declarations, emit (export ...) lines directly.
procedure TWklEmitter.DoAssembleExports();
var
  I, J: Integer;
  LDecl: TWklNode;
  LRoutine: TWklRoutineDeclNode;
  LGroup: TWklOverloadGroupNode;
  LHadExports: Boolean;
begin
  LHadExports := False;

  // _start export for exe modules
  if FModule.ModuleKind <> mkLib then
  begin
    if ((FModule.MainBody <> nil) and (FModule.MainBody.Statements <> nil) and
      (FModule.MainBody.Statements.Count > 0)) or
      (FModule.UnitTestMode and (FModule.TestBlocks.Count > 0)) then
    begin
      WLn('(export "_start" (func $_start))');
      WLn('(export "_shutdown" (func $_shutdown))');
      WLn('(export "_frame" (func $_frame))');
      WLn('(export "_call0" (func $_call0))');
      LHadExports := True;
    end;
  end;

  // Public routine exports for lib modules
  if FModule.ModuleKind = mkLib then
  begin
    if FModule.Declarations <> nil then
      for I := 0 to FModule.Declarations.Count - 1 do
      begin
        LDecl := FModule.Declarations[I];
        if LDecl is TWklRoutineDeclNode then
        begin
          LRoutine := TWklRoutineDeclNode(LDecl);
          if (not LRoutine.IsExternal) and LRoutine.IsPublic then
          begin
            // Bare name: importers declare `external "<lib>" name "<n>"`
            WLn('(export "%s" (func $%s))', [LRoutine.Name,
              DoMangledName(LRoutine)]);
            LHadExports := True;
          end;
        end
        else if LDecl is TWklOverloadGroupNode then
        begin
          LGroup := TWklOverloadGroupNode(LDecl);
          if LGroup.Routines <> nil then
            for J := 0 to LGroup.Routines.Count - 1 do
              if LGroup.Routines[J] is TWklRoutineDeclNode then
              begin
                LRoutine := TWklRoutineDeclNode(LGroup.Routines[J]);
                if (not LRoutine.IsExternal) and LRoutine.IsPublic then
                begin
                  // An export name is the bare routine name, so a public
                  // overload group cannot be exported from a lib
                  FErrors.Add(esFatal, WKL_ERR_EMT_004,
                    'Public routine ''%s'' is overloaded; a lib module cannot export overloads',
                    [LRoutine.Name]);
                end;
              end;
        end;
      end;
  end;

  if LHadExports then
    WLn();
end;

// assemble the final (module ...) by walking the AST directly.
// No FImports, FGlobals, FExports, FExprConstInits, FUsedWasi.
procedure TWklEmitter.DoAssemble();
var
  I: Integer;
begin
  FOutput.Clear();
  WLn('(module');
  Indent();

  // Imports -- walk AST directly
  DoAssembleImports();

  // Runtime
  if FRuntimeWat <> '' then
  begin
    WLn(';; -- runtime --');
    DoAppendRawLines(FRuntimeWat);
    WLn(';; -- end runtime --');
    WLn();
  end;

  // Memory
  WLn('(memory $mem i64 1)');
  WLn('(export "memory" (memory $mem))');
  WLn();

  // Globals -- walk AST directly
  DoAssembleGlobals();

  // Function table -- walk AST directly
  DoAssembleTable();

  // Data segments (accumulated during body emission in phase 1)
  for I := 0 to FDataSegments.Count - 1 do
    WLn(FDataSegments[I]);
  if FDataSegments.Count > 0 then
    WLn();

  // Functions (accumulated during body emission in phase 1)
  for I := 0 to FFunctions.Count - 1 do
  begin
    DoAppendFuncLines(FFunctions[I]);
    WLn();
  end;

  // Exports -- walk AST directly
  DoAssembleExports();

  Dedent();
  WLn(')');
end;

function TWklEmitter.Emit(const ALexer: TWklLexer;
  const AModule: TWklModuleNode; const ASourceMap: TWklSourceMap): string;
begin
  FLexer := ALexer;
  FModule := AModule;
  FOutput.Clear();
  FIndent := 0;
  FDataOffset := WKL_DATA_START;
  FDataSegments.Clear();
  FFunctions.Clear();
  FLabelSeq := 0;
  FLocalDecls.Clear();
  FBody.Clear();
  FBodyMap.Clear();
  FDeclaredLocals.Clear();
  FLocalNames.Clear();
  FBreakLabels.Clear();
  FContinueLabels.Clear();
  FStringTemps.Clear();
  FPackTemps.Clear();
  FAggTemps.Clear();
  FAggTempCounter := 0;
  FTempSeq := 0;
  FRuntimeWat := '';
  FWatLine := 0;
  FCurrentRange := Default (TSourceRange);
  FSourceMap := ASourceMap;
  FNeedMemShells := False;

  // Phase 1: load runtime, emit all function bodies into FFunctions
  DoLoadRuntime();
  DoEmitAllBodies();

  // Phase 2: assemble final (module ...) by walking AST directly
  DoAssemble();

  Result := FOutput.ToString();
end;

end.
