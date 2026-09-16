{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.Parser - Recursive Descent Parser

  Converts a TWklLexer token stream into a TWklNode object tree. Every parse
  method returns the node it built. The caller owns the returned module node,
  which owns the entire tree.

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources, Waskal.Common,
                Waskal.Lexer, Waskal.AST
===============================================================================}

unit Waskal.Parser;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  Waskal.Common,
  Waskal.Lexer,
  Waskal.AST;

const
  // Error codes
  WKL_ERR_PAR_001 = 'PAR001';  // Unexpected token
  WKL_ERR_PAR_002 = 'PAR002';  // Expected token not found
  WKL_ERR_PAR_003 = 'PAR003';  // Invalid module kind
  WKL_ERR_PAR_004 = 'PAR004';  // Duplicate import
  WKL_ERR_PAR_005 = 'PAR005';  // Invalid type definition
  WKL_ERR_PAR_006 = 'PAR006';  // Invalid statement
  WKL_ERR_PAR_007 = 'PAR007';  // Invalid expression
  WKL_ERR_PAR_008 = 'PAR008';  // Expected identifier
  WKL_ERR_PAR_009 = 'PAR009';  // Invalid directive
  WKL_ERR_PAR_010 = 'PAR010';  // Invalid match arm
  WKL_ERR_PAR_020 = 'PAR020';  // Conditional directive missing identifier
  WKL_ERR_PAR_021 = 'PAR021';  // Unmatched @elseif/@else/@endif
  WKL_ERR_PAR_022 = 'PAR022';  // Unterminated @ifdef/@ifndef block

type
  { TWklCondState }
  TWklCondState = record
    Active: Boolean;
    HadTrue: Boolean;
    HadElse: Boolean;
    ParentActive: Boolean;
  end;

  { TWklParser }
  TWklParser = class(TBaseObject)
  private
    FLexer: TWklLexer;
    FLastConsumedLoc: TSourceRange;
    FDefines: TDictionary<string, string>;
    FCondStack: TList<TWklCondState>;

    // Node factory helpers
    procedure InitNode(const ANode: TWklNode; const ATokIdx: Int64);
    function TokIdx(): Int64;
    function TokLoc(const ATokIdx: Int64): TSourceRange;
    function TokText(const ATokIdx: Int64): string;

    // Token helpers
    function PeekAt(const AOffset: Int64): TWklToken;
    function Match(const AKind: TWklTokenKind): Boolean;
    function Expect(const AKind: TWklTokenKind): TWklToken;
    function Check(const AKind: TWklTokenKind): Boolean;
    procedure OptionalSemicolon(const AOptional: Boolean = False);
    procedure ExpectBlockEnd(const AConstruct: string; const AStartLocation: TSourceRange);

    // Predicates
    function GetPrecedence(const AKind: TWklTokenKind): Integer;
    function IsRelOp(const AKind: TWklTokenKind): Boolean;
    function IsAddOp(const AKind: TWklTokenKind): Boolean;
    function IsMulOp(const AKind: TWklTokenKind): Boolean;
    function IsAssignOp(const AKind: TWklTokenKind): Boolean;
    function IsStatementStart(const AKind: TWklTokenKind): Boolean;
    function IsIntrinsicToken(const AKind: TWklTokenKind): Boolean;
    function IsAssertToken(const AKind: TWklTokenKind): Boolean;
    function TokenToBinaryOp(const AKind: TWklTokenKind): TWklBinaryOp;
    function TokenToUnaryOp(const AKind: TWklTokenKind): TWklUnaryOp;
    function TokenToAssignOp(const AKind: TWklTokenKind): TWklAssignOp;
    function TokenToIntrinsicKind(const AKind: TWklTokenKind): TWklIntrinsicKind;
    function TokenToAssertKind(const AKind: TWklTokenKind): TWklAssertKind;

    // Conditional compilation
    procedure DoProcessConditionals();
    procedure DoSkipFalseBranch();
    procedure DoSetupPredefinedDefines(const AModuleKind: TWklModuleKind);

    // Module and declarations
    function DoParseModuleBody(const AFilename: string): TWklModuleNode;
    function DoParseModuleKind(): TWklModuleKind;
    procedure DoParseDirectives(const AModule: TWklModuleNode);
    function DoParseDirective(): TWklDirectiveNode;
    procedure DoParseImportClause(const AModule: TWklModuleNode);
    procedure DoParseDeclarations(const AModule: TWklModuleNode);
    function DoParseConstDecl(const AIsPublic: Boolean): TWklConstDeclNode;
    function DoParseTypeDecl(const AIsPublic: Boolean): TWklTypeDeclNode;
    function DoParseVarDecl(const AIsPublic: Boolean): TWklVarDeclNode;
    function DoParseRoutineDecl(const AIsPublic: Boolean): TWklRoutineDeclNode;
    function DoParseForwardDecl(): TWklNode;
    procedure DoParseFormalParams(const AParams: TWklNodeList; var AIsVariadic: Boolean);
    function DoParseParamDecl(): TWklParamNode;
    procedure DoParseExternalClause(var ALib: string; var ASymbol: string);
    procedure DoParseRoutineBody(const ARoutine: TWklRoutineDeclNode);
    procedure DoParseLocalDecls(const ATypes: TWklNodeList; const AConsts: TWklNodeList; const AVars: TWklNodeList);
    procedure DoParseInitializeBlock(const AModule: TWklModuleNode);
    procedure DoParseFinalizeBlock(const AModule: TWklModuleNode);
    procedure DoParseMainBody(const AModule: TWklModuleNode);
    procedure DoParseTestBlocks(const AModule: TWklModuleNode);

    // Types
    function DoParseTypeDef(): TWklNode;
    function DoParseRecordType(): TWklRecordTypeNode;
    function DoParseOverlayType(): TWklOverlayTypeNode;
    function DoParseAnonRecord(): TWklAnonRecordNode;
    function DoParseAnonOverlay(): TWklAnonOverlayNode;
    function DoParseFieldDecl(): TWklFieldDeclNode;
    function DoParseArrayType(): TWklArrayTypeNode;
    function DoParsePointerType(): TWklPointerTypeNode;
    function DoParseSetType(): TWklSetTypeNode;
    function DoParseChoicesType(): TWklChoicesTypeNode;
    function DoParseRoutineTypeDef(): TWklRoutineTypeNode;
    function DoParseTypeExpr(): TWklNode;

    // Statements
    procedure DoParseStatementSeq(const AList: TWklNodeList; const ATerminators: array of TWklTokenKind);
    function DoParseStatement(): TWklNode;
    function DoParseAssignOrCall(): TWklNode;
    function DoParseIfStmt(): TWklIfNode;
    function DoParseWhileStmt(): TWklWhileNode;
    function DoParseForStmt(): TWklForNode;
    function DoParseRepeatStmt(): TWklRepeatNode;
    function DoParseMatchStmt(): TWklMatchNode;
    function DoParseMatchArm(): TWklMatchArmNode;
    function DoParseReturnStmt(): TWklReturnNode;
    function DoParseGuardStmt(): TWklGuardNode;
    function DoParseThrowStmt(): TWklNode;
    function DoParseMemOpStmt(): TWklNode;
    function DoParsePrintStmt(): TWklPrintNode;
    function DoParseAssertStmt(): TWklAssertNode;

    // Expressions
    function DoParseExpression(): TWklNode;
    function DoParsePrecedence(const AMinPrec: Integer): TWklNode;
    function DoParsePrefix(): TWklNode;
    function DoParseDesignator(const ABase: TWklNode): TWklNode;
    function DoParseSetLiteral(): TWklSetLiteralNode;
    function DoParseIntrinsic(): TWklIntrinsicNode;
    function DoParseVarArgsAccess(): TWklIntrinsicNode;
    function DoParseRecordLiteral(const ATypeNameTokIdx: Int64): TWklRecordLiteralNode;
    function DoMakeLiteral(const ATokIdx: Int64): TWklLiteralNode;

  protected
    function Current(): TWklToken;
    function Consume(): TWklToken;

  public
    constructor Create(); override;
    destructor Destroy(); override;
    function ParseModule(const ALexer: TWklLexer; const AFilename: string): TWklModuleNode;
    function ParseModuleFromString(const ALexer: TWklLexer; const ASource: string; const AFilename: string): TWklModuleNode;
    function ParseUnit(const ALexer: TWklLexer; const AFilename: string): TWklModuleNode;
    procedure SetDefine(const AName: string; const AValue: string);
    procedure Undefine(const AName: string);
    function IsDefined(const AName: string): Boolean;
  end;

implementation

{ TWklParser }
constructor TWklParser.Create();
begin
  inherited;

  FLexer := nil;
  FDefines := TDictionary<string, string>.Create();
  FCondStack := TList<TWklCondState>.Create();
end;

destructor TWklParser.Destroy();
begin
  FCondStack.Free();
  FDefines.Free();

  inherited;
end;

procedure TWklParser.InitNode(const ANode: TWklNode; const ATokIdx: Int64);
begin
  ANode.Token := ATokIdx;
  if ATokIdx <> WKL_NO_TOKEN then
  begin
    ANode.Location := TokLoc(ATokIdx);
    ANode.Name := TokText(ATokIdx);
  end;
end;

function TWklParser.TokIdx(): Int64;
begin
  Result := FLexer.TokenIndex;
end;

function TWklParser.TokLoc(const ATokIdx: Int64): TSourceRange;
begin
  if (ATokIdx >= 0) and (ATokIdx < FLexer.Tokens.Count) then
    Result := FLexer.Tokens[ATokIdx].Location
  else
    Result.Clear();
end;

function TWklParser.TokText(const ATokIdx: Int64): string;
begin
  if (ATokIdx >= 0) and (ATokIdx < FLexer.Tokens.Count) then
    Result := FLexer.Tokens[ATokIdx].TokenText
  else
    Result := '';
end;

function TWklParser.Current(): TWklToken;
begin
  Result := FLexer.CurrentToken();
end;

function TWklParser.Consume(): TWklToken;
begin
  Result := FLexer.CurrentToken();
  FLastConsumedLoc := Result.Location;
  FLexer.NextToken();
  DoProcessConditionals();
end;

function TWklParser.PeekAt(const AOffset: Int64): TWklToken;
begin
  Result := FLexer.PeekAt(AOffset);
end;

function TWklParser.Match(const AKind: TWklTokenKind): Boolean;
begin
  Result := Current().Kind = AKind;
  if Result then
  begin
    FLastConsumedLoc := Current().Location;
    FLexer.NextToken();
    DoProcessConditionals();
  end;
end;

function TWklParser.Expect(const AKind: TWklTokenKind): TWklToken;
begin
  Result := Current();
  if Result.Kind = AKind then
  begin
    FLastConsumedLoc := Result.Location;
    FLexer.NextToken();
    DoProcessConditionals();
  end
  else
    FLexer.Expect(AKind);
end;

function TWklParser.Check(const AKind: TWklTokenKind): Boolean;
begin
  Result := Current().Kind = AKind;
end;

procedure TWklParser.OptionalSemicolon(const AOptional: Boolean);
begin
  if AOptional then
    Match(tkSemicolon)
  else
    Expect(tkSemicolon);
end;

procedure TWklParser.ExpectBlockEnd(const AConstruct: string;
  const AStartLocation: TSourceRange);
begin
  if not Match(tkEnd) then
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_002,
      RSParExpectedEnd, [AConstruct, AStartLocation.StartLine]);
end;

function TWklParser.GetPrecedence(const AKind: TWklTokenKind): Integer;
begin
  if IsRelOp(AKind) then
    Result := 1
  else if IsAddOp(AKind) then
    Result := 2
  else if IsMulOp(AKind) then
    Result := 3
  else
    Result := 0;
end;

function TWklParser.IsRelOp(const AKind: TWklTokenKind): Boolean;
begin
  Result := (AKind = tkEqual) or (AKind = tkNotEqual) or
            (AKind = tkLess) or (AKind = tkGreater) or
            (AKind = tkLessEqual) or (AKind = tkGreaterEqual) or
            (AKind = tkIn);
end;

function TWklParser.IsAddOp(const AKind: TWklTokenKind): Boolean;
begin
  Result := (AKind = tkPlus) or (AKind = tkMinus) or
            (AKind = tkOr) or (AKind = tkXor);
end;

function TWklParser.IsMulOp(const AKind: TWklTokenKind): Boolean;
begin
  Result := (AKind = tkStar) or (AKind = tkSlash) or
            (AKind = tkDiv) or (AKind = tkMod) or
            (AKind = tkAnd) or (AKind = tkShl) or (AKind = tkShr);
end;

function TWklParser.IsAssignOp(const AKind: TWklTokenKind): Boolean;
begin
  Result := (AKind = tkAssign) or (AKind = tkPlusAssign) or
            (AKind = tkMinusAssign) or (AKind = tkStarAssign) or
            (AKind = tkSlashAssign);
end;

function TWklParser.IsStatementStart(const AKind: TWklTokenKind): Boolean;
begin
  Result :=
    (AKind = tkIf) or (AKind = tkWhile) or (AKind = tkFor) or
    (AKind = tkRepeat) or (AKind = tkMatch) or (AKind = tkReturn) or
    (AKind = tkGuard) or (AKind = tkThrow) or (AKind = tkThrowCode) or
    (AKind = tkBreak) or (AKind = tkContinue) or
    (AKind = tkNew) or (AKind = tkDispose) or
    (AKind = tkGetMem) or (AKind = tkFreeMem) or
    (AKind = tkResizeMem) or (AKind = tkSetLength) or
    (AKind = tkPrint) or (AKind = tkPrintLn) or
    IsAssertToken(AKind) or
    (AKind = tkDirective) or (AKind = tkVar) or
    (AKind = tkIdentifier) or (AKind = tkVarArgs);
end;

function TWklParser.IsIntrinsicToken(const AKind: TWklTokenKind): Boolean;
begin
  Result := (AKind = tkLen) or (AKind = tkSize) or (AKind = tkUtf8) or
            (AKind = tkCStr) or (AKind = tkWStr) or
            (AKind = tkParamCount) or (AKind = tkParamStr) or
            (AKind = tkExcCode) or (AKind = tkExcMsg) or
            (AKind = tkFormat);
end;

function TWklParser.IsAssertToken(const AKind: TWklTokenKind): Boolean;
begin
  Result := (AKind = tkAssert) or (AKind = tkAssertTrue) or
            (AKind = tkAssertFalse) or (AKind = tkAssertEq) or
            (AKind = tkAssertEqF) or (AKind = tkAssertNil) or
            (AKind = tkAssertNotNil) or (AKind = tkAssertFail);
end;

function TWklParser.TokenToBinaryOp(const AKind: TWklTokenKind): TWklBinaryOp;
begin
  if AKind = tkPlus then Result := boAdd
  else if AKind = tkMinus then Result := boSub
  else if AKind = tkStar then Result := boMul
  else if AKind = tkSlash then Result := boDiv
  else if AKind = tkDiv then Result := boIntDiv
  else if AKind = tkMod then Result := boMod
  else if AKind = tkAnd then Result := boAnd
  else if AKind = tkOr then Result := boOr
  else if AKind = tkXor then Result := boXor
  else if AKind = tkShl then Result := boShl
  else if AKind = tkShr then Result := boShr
  else if AKind = tkEqual then Result := boEq
  else if AKind = tkNotEqual then Result := boNotEq
  else if AKind = tkLess then Result := boLess
  else if AKind = tkGreater then Result := boGreater
  else if AKind = tkLessEqual then Result := boLessEq
  else if AKind = tkGreaterEqual then Result := boGreaterEq
  else if AKind = tkIn then Result := boIn
  else
    Result := boAdd;
end;

function TWklParser.TokenToUnaryOp(const AKind: TWklTokenKind): TWklUnaryOp;
begin
  if AKind = tkNot then Result := uoNot
  else if AKind = tkMinus then Result := uoNegate
  else if AKind = tkPlus then Result := uoPlus
  else if AKind = tkAddress then Result := uoAddressOf
  else
    Result := uoPlus;
end;

function TWklParser.TokenToAssignOp(const AKind: TWklTokenKind): TWklAssignOp;
begin
  if AKind = tkAssign then Result := aoAssign
  else if AKind = tkPlusAssign then Result := aoAddAssign
  else if AKind = tkMinusAssign then Result := aoSubAssign
  else if AKind = tkStarAssign then Result := aoMulAssign
  else if AKind = tkSlashAssign then Result := aoDivAssign
  else
    Result := aoAssign;
end;

function TWklParser.TokenToIntrinsicKind(const AKind: TWklTokenKind): TWklIntrinsicKind;
begin
  if AKind = tkLen then Result := ikLen
  else if AKind = tkSize then Result := ikSize
  else if AKind = tkUtf8 then Result := ikUtf8
  else if AKind = tkCStr then Result := ikCStr
  else if AKind = tkFormat then Result := ikFormat
  else if AKind = tkWStr then Result := ikWStr
  else if AKind = tkParamCount then Result := ikParamCount
  else if AKind = tkParamStr then Result := ikParamStr
  else if AKind = tkExcCode then Result := ikExcCode
  else if AKind = tkExcMsg then Result := ikExcMsg
  else
    Result := ikLen;
end;

function TWklParser.TokenToAssertKind(const AKind: TWklTokenKind): TWklAssertKind;
begin
  if AKind = tkAssert then Result := akAssert
  else if AKind = tkAssertTrue then Result := akAssertTrue
  else if AKind = tkAssertFalse then Result := akAssertFalse
  else if AKind = tkAssertEq then Result := akAssertEq
  else if AKind = tkAssertEqF then Result := akAssertEqF
  else if AKind = tkAssertNil then Result := akAssertNil
  else if AKind = tkAssertNotNil then Result := akAssertNotNil
  else if AKind = tkAssertFail then Result := akAssertFail
  else
    Result := akAssert;
end;

procedure TWklParser.SetDefine(const AName: string; const AValue: string);
begin
  FDefines.AddOrSetValue(AName, AValue);
end;

procedure TWklParser.Undefine(const AName: string);
begin
  FDefines.Remove(AName);
end;

function TWklParser.IsDefined(const AName: string): Boolean;
begin
  Result := FDefines.ContainsKey(AName);
end;

procedure TWklParser.DoProcessConditionals();
var
  LTok: TWklToken;
  LDirName: string;
  LSymbol: string;
  LState: TWklCondState;
  LActive: Boolean;
begin
  while Current().Kind = tkDirective do
  begin
    LTok := Current();
    LDirName := LTok.TokenText;

    if LDirName = 'define' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        SetDefine(Current().TokenText, '1');
        FLexer.NextToken();
      end
      else
        FErrors.Add(LTok.Location, esError, WKL_ERR_PAR_020,
          RSParDefineNeedsIdent);
    end
    else if LDirName = 'undef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        Undefine(Current().TokenText);
        FLexer.NextToken();
      end
      else
        FErrors.Add(LTok.Location, esError, WKL_ERR_PAR_020,
          RSParUndefNeedsIdent);
    end
    else if LDirName = 'ifdef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        LSymbol := Current().TokenText;
        FLexer.NextToken();
      end
      else
      begin
        FErrors.Add(LTok.Location, esError, WKL_ERR_PAR_020,
          RSParIfdefNeedsIdent);
        LSymbol := '';
      end;
      LActive := IsDefined(LSymbol);
      LState := Default(TWklCondState);
      LState.Active := LActive;
      LState.HadTrue := LActive;
      LState.HadElse := False;
      LState.ParentActive := True;
      FCondStack.Add(LState);
      if not LActive then
        DoSkipFalseBranch();
    end
    else if LDirName = 'ifndef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        LSymbol := Current().TokenText;
        FLexer.NextToken();
      end
      else
      begin
        FErrors.Add(LTok.Location, esError, WKL_ERR_PAR_020,
          RSParIfndefNeedsIdent);
        LSymbol := '';
      end;
      LActive := not IsDefined(LSymbol);
      LState := Default(TWklCondState);
      LState.Active := LActive;
      LState.HadTrue := LActive;
      LState.HadElse := False;
      LState.ParentActive := True;
      FCondStack.Add(LState);
      if not LActive then
        DoSkipFalseBranch();
    end
    else if LDirName = 'elseif' then
    begin
      if FCondStack.Count = 0 then
      begin
        FErrors.Add(LTok.Location, esError, WKL_ERR_PAR_021,
          RSParElseifNoMatch);
        FLexer.NextToken();
      end
      else
      begin
        LState := FCondStack[FCondStack.Count - 1];
        LState.HadTrue := True;
        FCondStack[FCondStack.Count - 1] := LState;
        DoSkipFalseBranch();
      end;
    end
    else if LDirName = 'else' then
    begin
      if FCondStack.Count = 0 then
      begin
        FErrors.Add(LTok.Location, esError, WKL_ERR_PAR_021,
          RSParElseNoMatch);
        FLexer.NextToken();
      end
      else
      begin
        LState := FCondStack[FCondStack.Count - 1];
        LState.HadTrue := True;
        LState.HadElse := True;
        FCondStack[FCondStack.Count - 1] := LState;
        DoSkipFalseBranch();
      end;
    end
    else if LDirName = 'endif' then
    begin
      if FCondStack.Count = 0 then
        FErrors.Add(LTok.Location, esError, WKL_ERR_PAR_021,
          RSParEndifNoMatch)
      else
        FCondStack.Delete(FCondStack.Count - 1);
      FLexer.NextToken();
    end
    else
      Break;
  end;
end;

procedure TWklParser.DoSkipFalseBranch();
var
  LDepth: Integer;
  LDirName: string;
  LState: TWklCondState;
  LSymbol: string;
begin
  LDepth := 0;
  while Current().Kind <> tkEOF do
  begin
    if Current().Kind = tkDirective then
    begin
      LDirName := Current().TokenText;

      if (LDirName = 'ifdef') or (LDirName = 'ifndef') then
      begin
        Inc(LDepth);
        FLexer.NextToken();
        if Current().Kind = tkIdentifier then
          FLexer.NextToken();
        Continue;
      end;

      if LDirName = 'endif' then
      begin
        if LDepth > 0 then
        begin
          Dec(LDepth);
          FLexer.NextToken();
          Continue;
        end;
        if FCondStack.Count > 0 then
          FCondStack.Delete(FCondStack.Count - 1);
        FLexer.NextToken();
        Exit;
      end;

      if (LDirName = 'else') and (LDepth = 0) then
      begin
        if FCondStack.Count > 0 then
        begin
          LState := FCondStack[FCondStack.Count - 1];
          if not LState.HadTrue then
          begin
            LState.Active := True;
            LState.HadTrue := True;
            LState.HadElse := True;
            FCondStack[FCondStack.Count - 1] := LState;
            FLexer.NextToken();
            Exit;
          end;
        end;
        FLexer.NextToken();
        Continue;
      end;

      if (LDirName = 'elseif') and (LDepth = 0) then
      begin
        FLexer.NextToken();
        LSymbol := '';
        if Current().Kind = tkIdentifier then
        begin
          LSymbol := Current().TokenText;
          FLexer.NextToken();
        end;
        if FCondStack.Count > 0 then
        begin
          LState := FCondStack[FCondStack.Count - 1];
          if (not LState.HadTrue) and IsDefined(LSymbol) then
          begin
            LState.Active := True;
            LState.HadTrue := True;
            FCondStack[FCondStack.Count - 1] := LState;
            Exit;
          end;
        end;
        Continue;
      end;
    end;

    FLexer.NextToken();
  end;

  if FCondStack.Count > 0 then
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_022,
      RSParUnterminatedIfdef);
end;

procedure TWklParser.DoSetupPredefinedDefines(const AModuleKind: TWklModuleKind);
begin
  SetDefine('WASKAL', '1');
  SetDefine('WASM64', '1');

  Undefine('BUILD_EXE');
  Undefine('BUILD_LIB');
  if AModuleKind = mkExe then
    SetDefine('BUILD_EXE', '1')
  else if AModuleKind = mkLib then
    SetDefine('BUILD_LIB', '1');
end;

function TWklParser.ParseModule(const ALexer: TWklLexer;
  const AFilename: string): TWklModuleNode;
var
  LNormalized: string;
begin
  Result := nil;
  FLexer := ALexer;
  LNormalized := TPath.ChangeExtension(AFilename, WKL_SRCFILE_EXT);
  if not FLexer.TokenizeFile(LNormalized) then
  begin
    FLexer := nil;
    Exit;
  end;
  Result := DoParseModuleBody(LNormalized);
  FLexer := nil;
end;

function TWklParser.ParseModuleFromString(const ALexer: TWklLexer;
  const ASource: string; const AFilename: string): TWklModuleNode;
begin
  Result := nil;
  FLexer := ALexer;
  if not FLexer.TokenizeString(ASource, AFilename) then
  begin
    FLexer := nil;
    Exit;
  end;
  Result := DoParseModuleBody(AFilename);
  FLexer := nil;
end;

function TWklParser.ParseUnit(const ALexer: TWklLexer;
  const AFilename: string): TWklModuleNode;
var
  LNormalized: string;
begin
  Result := nil;
  FLexer := ALexer;
  LNormalized := TPath.ChangeExtension(AFilename, WKL_SRCFILE_EXT);
  if not FLexer.TokenizeFile(LNormalized, True) then
  begin
    FLexer := nil;
    Exit;
  end;
  Result := DoParseModuleBody(LNormalized);
  FLexer := nil;
end;

function TWklParser.DoParseModuleBody(const AFilename: string): TWklModuleNode;
var
  LModKind: TWklModuleKind;
  LNameTokIdx: Int64;
begin
  Result := nil;

  DoProcessConditionals();

  Expect(tkModule);
  LModKind := DoParseModuleKind();
  DoSetupPredefinedDefines(LModKind);

  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_008,
      RSParExpectedIdentifier);
    Exit;
  end;
  LNameTokIdx := TokIdx();
  Consume();

  // Semicolon after module name -- advance without DoProcessConditionals
  // so any @ifdef in directive section is left for DoParseDirectives
  if Current().Kind = tkSemicolon then
    FLexer.NextToken()
  else
    FLexer.Expect(tkSemicolon);

  Result := TWklModuleNode.Create();
  InitNode(Result, LNameTokIdx);
  Result.ModuleKind := LModKind;
  Result.Filename := AFilename;

  // Validate module name matches source filename
  if not Result.Name.ToLower().Equals(
     TPath.GetFileNameWithoutExtension(AFilename).ToLower()) then
    FErrors.Add(Result.Location, esError, WKL_ERR_PAR_008,
      'Module name ''%s'' does not match source filename ''%s''',
      [Result.Name, TPath.GetFileNameWithoutExtension(AFilename)]);

  DoParseDirectives(Result);
  DoParseImportClause(Result);
  DoParseDeclarations(Result);

  if FErrors.HasErrors() then
    Exit;

  DoParseInitializeBlock(Result);
  DoParseFinalizeBlock(Result);

  if FErrors.HasErrors() then
    Exit;

  DoParseMainBody(Result);

  if FErrors.HasErrors() then
    Exit;

  DoParseTestBlocks(Result);
end;

function TWklParser.DoParseModuleKind(): TWklModuleKind;
var
  LText: string;
begin
  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_003,
      RSParExpectedModuleKind);
    Result := mkExe;
    Exit;
  end;

  LText := Current().TokenText;
  if LText = 'exe' then
    Result := mkExe
  else if LText = 'lib' then
    Result := mkLib
  else if LText = 'unit' then
    Result := mkUnit
  else
  begin
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_003,
      RSParInvalidModuleKind, [LText]);
    Result := mkExe;
  end;
  Consume();
end;

function TWklParser.DoParseDirective(): TWklDirectiveNode;
var
  LArgs: TList<string>;
begin
  Result := TWklDirectiveNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  LArgs := TList<string>.Create();
  try
    while (Current().Kind = tkIdentifier) or (Current().Kind = tkStringLiteral) or
          (Current().Kind = tkIntLiteral) or (Current().Kind = tkFloatLiteral) do
    begin
      if Current().Kind = tkStringLiteral then
        LArgs.Add(Current().LiteralValue.AsString)
      else
        LArgs.Add(Current().TokenText);
      Consume();
    end;
    Result.Args := LArgs.ToArray();
  finally
    LArgs.Free();
  end;
  OptionalSemicolon();
end;

procedure TWklParser.DoParseDirectives(const AModule: TWklModuleNode);
begin
  DoProcessConditionals();
  while Current().Kind = tkDirective do
    AModule.Directives.Add(DoParseDirective());
end;

procedure TWklParser.DoParseImportClause(const AModule: TWklModuleNode);
var
  LSeen: TDictionary<string, Boolean>;
  LName: string;
  LImport: TWklImportNode;
begin
  if not Match(tkImport) then
    Exit;

  LSeen := TDictionary<string, Boolean>.Create();
  try
    repeat
      if Current().Kind <> tkIdentifier then
      begin
        FErrors.Add(Current().Location, esError, WKL_ERR_PAR_008,
          RSParExpectedImportName);
        Break;
      end;
      LName := Current().TokenText;
      if LSeen.ContainsKey(LName) then
        FErrors.Add(Current().Location, esError, WKL_ERR_PAR_004,
          RSParDuplicateImport, [LName])
      else
      begin
        LSeen.Add(LName, True);
        LImport := TWklImportNode.Create();
        InitNode(LImport, TokIdx());
        AModule.Imports.Add(LImport);
      end;
      Consume();
    until not Match(tkComma);
    OptionalSemicolon();
  finally
    LSeen.Free();
  end;
end;

procedure TWklParser.DoParseDeclarations(const AModule: TWklModuleNode);
var
  LIsPublic: Boolean;
  LNode: TWklNode;
  LImport: TWklImportNode;
begin
  while not (Check(tkBegin) or Check(tkInitialize) or Check(tkFinalize) or
             Check(tkTest) or Check(tkEnd) or Check(tkDot) or Check(tkEOF)) do
  begin
    LIsPublic := False;
    if Match(tkPublic) then
      LIsPublic := True;

    if Check(tkConst) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        if (FLexer.PeekToken().Kind <> tkEqual) and
           (FLexer.PeekToken().Kind <> tkColon) then
          Break;
        LNode := DoParseConstDecl(LIsPublic);
        if LNode <> nil then
        begin
          LNode.OwnerModule := AModule.Name;
          AModule.Declarations.Add(LNode);
        end;
      end;
    end
    else if Check(tkType) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        if FLexer.PeekToken().Kind <> tkEqual then
          Break;
        LNode := DoParseTypeDecl(LIsPublic);
        if LNode <> nil then
        begin
          LNode.OwnerModule := AModule.Name;
          AModule.Declarations.Add(LNode);
        end;
      end;
    end
    else if Check(tkVar) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        if FLexer.PeekToken().Kind <> tkColon then
          Break;
        LNode := DoParseVarDecl(LIsPublic);
        if LNode <> nil then
        begin
          LNode.OwnerModule := AModule.Name;
          AModule.Declarations.Add(LNode);
        end;
      end;
    end
    else if Check(tkRoutine) then
    begin
      LNode := DoParseRoutineDecl(LIsPublic);
      if LNode <> nil then
      begin
        LNode.OwnerModule := AModule.Name;
        AModule.Declarations.Add(LNode);
      end;
    end
    else if Check(tkForward) then
    begin
      Consume();
      LNode := DoParseForwardDecl();
      if LNode <> nil then
      begin
        LNode.OwnerModule := AModule.Name;
        AModule.Declarations.Add(LNode);
      end;
    end
    else if Check(tkDirective) then
    begin
      AModule.Directives.Add(DoParseDirective());
    end
    else if Check(tkImport) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        LImport := TWklImportNode.Create();
        InitNode(LImport, TokIdx());
        AModule.Imports.Add(LImport);
        Consume();
        if not Match(tkComma) then
          Break;
      end;
      OptionalSemicolon();
    end
    else
    begin
      FErrors.Add(Current().Location, esError, WKL_ERR_PAR_001,
        RSParUnexpectedToken, [Current().TokenText]);
      Consume();
    end;
  end;
end;

function TWklParser.DoParseConstDecl(const AIsPublic: Boolean): TWklConstDeclNode;
begin
  Result := TWklConstDeclNode.Create();
  InitNode(Result, TokIdx());
  Expect(tkIdentifier);
  Result.IsPublic := AIsPublic;

  if Match(tkColon) then
    Result.TypeExpr := DoParseTypeExpr();

  Expect(tkEqual);
  Result.ValueExpr := DoParseExpression();
  OptionalSemicolon();
end;

function TWklParser.DoParseTypeDecl(const AIsPublic: Boolean): TWklTypeDeclNode;
begin
  Result := TWklTypeDeclNode.Create();
  InitNode(Result, TokIdx());
  Expect(tkIdentifier);
  Result.IsPublic := AIsPublic;

  Expect(tkEqual);
  Result.TypeDef := DoParseTypeDef();
  OptionalSemicolon();
end;

procedure TWklParser.DoParseExternalClause(var ALib: string; var ASymbol: string);
begin
  ALib := '';
  ASymbol := '';

  // Optional library: string literal or identifier (module const name)
  if Current().Kind = tkStringLiteral then
  begin
    ALib := Current().LiteralValue.AsString;
    Consume();
  end
  else if (Current().Kind = tkIdentifier) and
          (Current().TokenText.ToLower() <> 'name') then
  begin
    ALib := Current().TokenText;
    Consume();
  end;

  // Optional name clause: name "symbol"
  if (Current().Kind = tkIdentifier) and
     (Current().TokenText.ToLower() = 'name') then
  begin
    Consume();
    if Current().Kind = tkStringLiteral then
    begin
      ASymbol := Current().LiteralValue.AsString;
      Consume();
    end;
  end;
end;

function TWklParser.DoParseVarDecl(const AIsPublic: Boolean): TWklVarDeclNode;
begin
  Result := TWklVarDeclNode.Create();
  InitNode(Result, TokIdx());
  Expect(tkIdentifier);
  Result.IsPublic := AIsPublic;

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();

  if Match(tkEqual) then
    Result.InitExpr := DoParseExpression();

  if Match(tkExternal) then
  begin
    Result.IsExternal := True;
    DoParseExternalClause(Result.ExternLib, Result.ExternSymbol);
  end;

  OptionalSemicolon();
end;

function TWklParser.DoParseRoutineDecl(const AIsPublic: Boolean): TWklRoutineDeclNode;
var
  LIsVariadic: Boolean;
begin
  Consume(); // eat 'routine'

  Result := TWklRoutineDeclNode.Create();
  InitNode(Result, TokIdx());
  Expect(tkIdentifier);
  Result.IsPublic := AIsPublic;

  LIsVariadic := False;
  if Check(tkLParen) then
    DoParseFormalParams(Result.Params, LIsVariadic);
  Result.IsVariadic := LIsVariadic;

  if Match(tkColon) then
    Result.ReturnType := DoParseTypeExpr();

  OptionalSemicolon();

  if Match(tkExternal) then
  begin
    Result.IsExternal := True;
    DoParseExternalClause(Result.ExternLib, Result.ExternSymbol);
    OptionalSemicolon();
  end
  else
    DoParseRoutineBody(Result);

  OptionalSemicolon(True);
end;

procedure TWklParser.DoParseFormalParams(const AParams: TWklNodeList;
  var AIsVariadic: Boolean);
begin
  AIsVariadic := False;
  Expect(tkLParen);
  if not Check(tkRParen) then
  begin
    repeat
      // `...` marks the routine variadic; it must be the last entry
      if Match(tkEllipsis) then
      begin
        AIsVariadic := True;
        Break;
      end;
      AParams.Add(DoParseParamDecl());
    until not Match(tkSemicolon);
  end;
  Expect(tkRParen);
end;

function TWklParser.DoParseParamDecl(): TWklParamNode;
var
  LMode: TWklParamMode;
begin
  LMode := pmDefault;
  if Match(tkConst) then
    LMode := pmConst
  else if Match(tkVar) then
    LMode := pmVar;

  Result := TWklParamNode.Create();
  InitNode(Result, TokIdx());
  Expect(tkIdentifier);
  Result.ParamMode := LMode;

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();
end;

procedure TWklParser.DoParseLocalDecls(const ATypes: TWklNodeList;
  const AConsts: TWklNodeList; const AVars: TWklNodeList);
var
  LNode: TWklNode;
begin
  while Check(tkConst) or Check(tkType) or Check(tkVar) do
  begin
    if Check(tkConst) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        LNode := DoParseConstDecl(False);
        if LNode <> nil then
          AConsts.Add(LNode);
      end;
    end
    else if Check(tkType) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        LNode := DoParseTypeDecl(False);
        if LNode <> nil then
          ATypes.Add(LNode);
      end;
    end
    else if Check(tkVar) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        LNode := DoParseVarDecl(False);
        if LNode <> nil then
          AVars.Add(LNode);
      end;
    end;
  end;
end;

procedure TWklParser.DoParseRoutineBody(const ARoutine: TWklRoutineDeclNode);
begin
  DoParseLocalDecls(ARoutine.LocalTypes, ARoutine.LocalConsts, ARoutine.LocalVars);

  Expect(tkBegin);
  ARoutine.Body := TWklBlockNode.Create();
  InitNode(ARoutine.Body, TokIdx());
  DoParseStatementSeq(ARoutine.Body.Statements, [tkEnd]);
  ExpectBlockEnd('routine', ARoutine.Location);
end;

function TWklParser.DoParseForwardDecl(): TWklNode;
var
  LFwdType: TWklForwardTypeNode;
  LFwdRoutine: TWklForwardRoutineNode;
  LIsVariadic: Boolean;
begin
  if Check(tkType) then
  begin
    Consume();
    LFwdType := TWklForwardTypeNode.Create();
    InitNode(LFwdType, TokIdx());
    Expect(tkIdentifier);
    OptionalSemicolon();
    Result := LFwdType;
  end
  else if Check(tkRoutine) then
  begin
    Consume();
    LFwdRoutine := TWklForwardRoutineNode.Create();
    InitNode(LFwdRoutine, TokIdx());
    Expect(tkIdentifier);

    LIsVariadic := False;
    if Check(tkLParen) then
      DoParseFormalParams(LFwdRoutine.Params, LIsVariadic);
    LFwdRoutine.IsVariadic := LIsVariadic;

    if Match(tkColon) then
      LFwdRoutine.ReturnType := DoParseTypeExpr();
    OptionalSemicolon();
    Result := LFwdRoutine;
  end
  else
  begin
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_001,
      RSParExpectedAfterForward);
    Result := nil;
  end;
end;

procedure TWklParser.DoParseInitializeBlock(const AModule: TWklModuleNode);
begin
  if not Match(tkInitialize) then
    Exit;

  AModule.InitBlock := TWklBlockNode.Create();
  InitNode(AModule.InitBlock, TokIdx());
  DoParseStatementSeq(AModule.InitBlock.Statements, [tkEnd, tkFinalize, tkBegin, tkTest]);
  if Check(tkEnd) then
    Consume();
  OptionalSemicolon(True);
end;

procedure TWklParser.DoParseFinalizeBlock(const AModule: TWklModuleNode);
begin
  if not Match(tkFinalize) then
    Exit;

  AModule.FinalizeBlock := TWklBlockNode.Create();
  InitNode(AModule.FinalizeBlock, TokIdx());
  DoParseStatementSeq(AModule.FinalizeBlock.Statements, [tkEnd, tkBegin, tkTest]);
  if Check(tkEnd) then
    Consume();
  OptionalSemicolon(True);
end;

procedure TWklParser.DoParseMainBody(const AModule: TWklModuleNode);
begin
  if not Check(tkBegin) then
  begin
    Expect(tkEnd);
    Expect(tkDot);
    Exit;
  end;

  Consume();
  AModule.MainBody := TWklBlockNode.Create();
  InitNode(AModule.MainBody, TokIdx());
  DoParseStatementSeq(AModule.MainBody.Statements, [tkEnd]);
  ExpectBlockEnd('main body', AModule.Location);
  Expect(tkDot);
end;

procedure TWklParser.DoParseTestBlocks(const AModule: TWklModuleNode);
var
  LTest: TWklTestBlockNode;
  LNode: TWklNode;
begin
  while Match(tkTest) do
  begin
    LTest := TWklTestBlockNode.Create();
    if Current().Kind = tkStringLiteral then
    begin
      InitNode(LTest, TokIdx());
      LTest.Name := Current().LiteralValue.AsString;
      Consume();
    end;
    OptionalSemicolon(True);

    // Optional local var declarations
    if Match(tkVar) then
    begin
      while (Current().Kind = tkIdentifier) and not FErrors.HasErrors() do
      begin
        LNode := DoParseVarDecl(False);
        if LNode <> nil then
          LTest.LocalVars.Add(LNode);
      end;
    end;

    Expect(tkBegin);
    DoParseStatementSeq(LTest.Statements, [tkEnd]);
    ExpectBlockEnd('test', LTest.Location);
    OptionalSemicolon(True);
    AModule.TestBlocks.Add(LTest);
  end;
end;

function TWklParser.DoParseTypeDef(): TWklNode;
begin
  if Check(tkRecord) then
    Result := DoParseRecordType()
  else if Check(tkOverlay) then
    Result := DoParseOverlayType()
  else if Check(tkChoices) then
    Result := DoParseChoicesType()
  else if Check(tkRoutine) then
    Result := DoParseRoutineTypeDef()
  else
    Result := DoParseTypeExpr();
end;

function TWklParser.DoParseRecordType(): TWklRecordTypeNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklRecordTypeNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  if Match(tkPacked) then
    Result.IsPacked := True;

  if Match(tkAlign) then
  begin
    Expect(tkLParen);
    if Current().Kind = tkIntLiteral then
    begin
      Result.Alignment := Current().LiteralValue.AsInt64;
      Consume();
    end;
    Expect(tkRParen);
  end;

  if Match(tkLParen) then
  begin
    Result.BaseType := DoParseTypeExpr();
    Expect(tkRParen);
  end;

  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkOverlay) then
      Result.Fields.Add(DoParseAnonOverlay())
    else
      Result.Fields.Add(DoParseFieldDecl());
  end;
  ExpectBlockEnd('record', LStartLoc);
end;

function TWklParser.DoParseOverlayType(): TWklOverlayTypeNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklOverlayTypeNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkRecord) then
      Result.Fields.Add(DoParseAnonRecord())
    else
      Result.Fields.Add(DoParseFieldDecl());
  end;
  ExpectBlockEnd('overlay', LStartLoc);
end;

function TWklParser.DoParseAnonRecord(): TWklAnonRecordNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklAnonRecordNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  if Match(tkPacked) then
    Result.IsPacked := True;

  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkOverlay) then
      Result.Fields.Add(DoParseAnonOverlay())
    else
      Result.Fields.Add(DoParseFieldDecl());
  end;
  ExpectBlockEnd('record', LStartLoc);
  OptionalSemicolon();
end;

function TWklParser.DoParseAnonOverlay(): TWklAnonOverlayNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklAnonOverlayNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkRecord) then
      Result.Fields.Add(DoParseAnonRecord())
    else
      Result.Fields.Add(DoParseFieldDecl());
  end;
  ExpectBlockEnd('overlay', LStartLoc);
  OptionalSemicolon();
end;

function TWklParser.DoParseFieldDecl(): TWklFieldDeclNode;
begin
  Result := TWklFieldDeclNode.Create();
  InitNode(Result, TokIdx());
  Expect(tkIdentifier);
  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();

  if Match(tkColon) then
  begin
    if Current().Kind = tkIntLiteral then
    begin
      Result.BitWidth := Current().LiteralValue.AsInt64;
      Consume();
    end;
  end;

  OptionalSemicolon();
end;

function TWklParser.DoParseArrayType(): TWklArrayTypeNode;
begin
  Result := TWklArrayTypeNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  if Match(tkLBracket) then
  begin
    Result.IsDynamic := False;
    Result.LowBound := DoParseExpression();
    Expect(tkDotDot);
    Result.HighBound := DoParseExpression();
    Expect(tkRBracket);
  end
  else
    Result.IsDynamic := True;

  Expect(tkOf);
  Result.ElementType := DoParseTypeExpr();
end;

function TWklParser.DoParsePointerType(): TWklPointerTypeNode;
begin
  Result := TWklPointerTypeNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  if Match(tkTo) then
  begin
    if Match(tkConst) then
      Result.IsConst := True;
    Result.TargetType := DoParseTypeExpr();
  end;
end;

function TWklParser.DoParseSetType(): TWklSetTypeNode;
var
  LFirst: TWklNode;
begin
  Result := TWklSetTypeNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  if Match(tkOf) then
  begin
    LFirst := DoParseExpression();
    if Match(tkDotDot) then
    begin
      Result.IsRange := True;
      Result.LowBound := LFirst;
      Result.HighBound := DoParseExpression();
    end
    else
      Result.ElementType := LFirst;
  end;
end;

function TWklParser.DoParseChoicesType(): TWklChoicesTypeNode;
var
  LValue: TWklChoicesValueNode;
begin
  Result := TWklChoicesTypeNode.Create();
  InitNode(Result, TokIdx());
  Consume();
  Expect(tkLParen);

  repeat
    LValue := TWklChoicesValueNode.Create();
    InitNode(LValue, TokIdx());
    Expect(tkIdentifier);
    if Match(tkEqual) then
      LValue.ExplicitValue := DoParseExpression();
    Result.Values.Add(LValue);
  until not Match(tkComma);

  Expect(tkRParen);
end;

function TWklParser.DoParseRoutineTypeDef(): TWklRoutineTypeNode;
var
  LIsVariadic: Boolean;
begin
  Result := TWklRoutineTypeNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  LIsVariadic := False;
  if Check(tkLParen) then
    DoParseFormalParams(Result.Params, LIsVariadic);
  Result.IsVariadic := LIsVariadic;

  if Match(tkColon) then
    Result.ReturnType := DoParseTypeExpr();
end;

function TWklParser.DoParseTypeExpr(): TWklNode;
var
  LTypeRef: TWklTypeRefNode;
begin
  if Check(tkPointer) or Check(tkCaret) then
  begin
    Result := DoParsePointerType();
    Exit;
  end;

  if Check(tkArray) then
  begin
    Result := DoParseArrayType();
    Exit;
  end;

  if Check(tkSet) then
  begin
    Result := DoParseSetType();
    Exit;
  end;

  LTypeRef := TWklTypeRefNode.Create();
  InitNode(LTypeRef, TokIdx());
  Consume();
  Result := LTypeRef;

  // Qualified name: Module.Type -- the first identifier becomes the module
  // qualifier and the second the type name; one TypeRef node either way
  if Match(tkDot) then
  begin
    LTypeRef.ModuleName := LTypeRef.Name;
    LTypeRef.Name := TokText(TokIdx());
    Expect(tkIdentifier);
  end;
end;

procedure TWklParser.DoParseStatementSeq(const AList: TWklNodeList;
  const ATerminators: array of TWklTokenKind);
var
  LNode: TWklNode;

  function IsTerminator(): Boolean;
  var
    LI: Integer;
  begin
    for LI := Low(ATerminators) to High(ATerminators) do
      if Current().Kind = ATerminators[LI] then
        Exit(True);
    Result := False;
  end;

begin
  while not IsTerminator() and (Current().Kind <> tkEOF) do
  begin
    LNode := DoParseStatement();
    if LNode <> nil then
      AList.Add(LNode);
    OptionalSemicolon(True);
    if FErrors.HasErrors() then
      Break;
  end;
end;

function TWklParser.DoParseStatement(): TWklNode;
var
  LBreak: TWklBreakNode;
  LContinue: TWklContinueNode;
begin
  Result := nil;

  if Check(tkIf) then
    Result := DoParseIfStmt()
  else if Check(tkWhile) then
    Result := DoParseWhileStmt()
  else if Check(tkFor) then
    Result := DoParseForStmt()
  else if Check(tkRepeat) then
    Result := DoParseRepeatStmt()
  else if Check(tkMatch) then
    Result := DoParseMatchStmt()
  else if Check(tkReturn) then
    Result := DoParseReturnStmt()
  else if Check(tkGuard) then
    Result := DoParseGuardStmt()
  else if Check(tkThrow) or Check(tkThrowCode) then
    Result := DoParseThrowStmt()
  else if Check(tkBreak) then
  begin
    LBreak := TWklBreakNode.Create();
    InitNode(LBreak, TokIdx());
    Consume();
    Result := LBreak;
  end
  else if Check(tkContinue) then
  begin
    LContinue := TWklContinueNode.Create();
    InitNode(LContinue, TokIdx());
    Consume();
    Result := LContinue;
  end
  else if Check(tkNew) or Check(tkDispose) or Check(tkGetMem) or
          Check(tkFreeMem) or Check(tkResizeMem) or Check(tkSetLength) then
    Result := DoParseMemOpStmt()
  else if Check(tkPrint) or Check(tkPrintLn) then
    Result := DoParsePrintStmt()
  else if IsAssertToken(Current().Kind) then
    Result := DoParseAssertStmt()
  else if Check(tkVar) then
  begin
    Consume();
    Result := DoParseVarDecl(False);
  end
  else if Check(tkIdentifier) or Check(tkVarArgs) then
    Result := DoParseAssignOrCall()
  else if Check(tkDirective) then
  begin
    DoProcessConditionals();
    Result := nil;
  end
  else
  begin
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_006,
      RSParInvalidStatement, [Current().TokenText]);
    Consume();
  end;
end;

function TWklParser.DoParseAssignOrCall(): TWklNode;
var
  LExpr: TWklNode;
  LAssign: TWklAssignNode;
  LCall: TWklCallStmtNode;
begin
  LExpr := DoParseExpression();

  if IsAssignOp(Current().Kind) then
  begin
    LAssign := TWklAssignNode.Create();
    InitNode(LAssign, TokIdx());
    LAssign.Op := TokenToAssignOp(Current().Kind);
    Consume();
    LAssign.Target := LExpr;
    LAssign.Value := DoParseExpression();
    Result := LAssign;
  end
  else
  begin
    LCall := TWklCallStmtNode.Create();
    LCall.Location := LExpr.Location;
    LCall.CallExpr := LExpr;
    Result := LCall;
  end;
end;

function TWklParser.DoParseIfStmt(): TWklIfNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklIfNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  Result.Condition := DoParseExpression();
  Expect(tkThen);
  DoParseStatementSeq(Result.ThenBody, [tkElse, tkEnd]);
  if Match(tkElse) then
  begin
    Result.ElseBody := TWklNodeList.Create(True);
    DoParseStatementSeq(Result.ElseBody, [tkEnd]);
  end;
  ExpectBlockEnd('if', LStartLoc);
end;

function TWklParser.DoParseWhileStmt(): TWklWhileNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklWhileNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  Result.Condition := DoParseExpression();
  Expect(tkDo);
  DoParseStatementSeq(Result.Body, [tkEnd]);
  ExpectBlockEnd('while', LStartLoc);
end;

function TWklParser.DoParseForStmt(): TWklForNode;
var
  LStartLoc: TSourceRange;
begin
  LStartLoc := Current().Location;
  Consume(); // eat 'for'

  Result := TWklForNode.Create();
  InitNode(Result, TokIdx());
  Expect(tkIdentifier);

  Expect(tkAssign);
  Result.StartExpr := DoParseExpression();
  if Match(tkTo) then
    Result.IsDownTo := False
  else if Match(tkDownTo) then
    Result.IsDownTo := True
  else
  begin
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_002,
      RSParExpectedToOrDownTo);
    Result.IsDownTo := False;
  end;
  Result.EndExpr := DoParseExpression();
  Expect(tkDo);
  DoParseStatementSeq(Result.Body, [tkEnd]);
  ExpectBlockEnd('for', LStartLoc);
end;

function TWklParser.DoParseRepeatStmt(): TWklRepeatNode;
begin
  Result := TWklRepeatNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  DoParseStatementSeq(Result.Body, [tkUntil]);
  Expect(tkUntil);
  Result.UntilCondition := DoParseExpression();
end;

function TWklParser.DoParseMatchStmt(): TWklMatchNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklMatchNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  Result.Scrutinee := DoParseExpression();
  Expect(tkOf);

  while not (Check(tkElse) or Check(tkEnd) or Check(tkEOF)) and
        not FErrors.HasErrors() do
    Result.Arms.Add(DoParseMatchArm());

  if Match(tkElse) then
  begin
    Result.ElseBody := TWklNodeList.Create(True);
    DoParseStatementSeq(Result.ElseBody, [tkEnd]);
  end;

  ExpectBlockEnd('match', LStartLoc);
  OptionalSemicolon(True);
end;

function TWklParser.DoParseMatchArm(): TWklMatchArmNode;
var
  LLabel: TWklMatchLabelNode;
  LStmt: TWklNode;
begin
  Result := TWklMatchArmNode.Create();
  Result.Location := Current().Location;

  repeat
    LLabel := TWklMatchLabelNode.Create();
    LLabel.Location := Current().Location;
    LLabel.ValueExpr := DoParseExpression();
    if Match(tkDotDot) then
      LLabel.RangeEnd := DoParseExpression();
    Result.Labels.Add(LLabel);
  until not Match(tkComma);

  Expect(tkColon);

  while not (Check(tkEnd) or Check(tkElse) or Check(tkEOF)) do
  begin
    if Match(tkSemicolon) then
      Continue;

    if not IsStatementStart(Current().Kind) then
      Break;

    LStmt := DoParseStatement();
    if LStmt <> nil then
      Result.Body.Add(LStmt);

    if FErrors.HasErrors() then
      Break;
  end;
end;

function TWklParser.DoParseReturnStmt(): TWklReturnNode;
begin
  Result := TWklReturnNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  if (Current().Kind = tkIdentifier) or (Current().Kind = tkIntLiteral) or
     (Current().Kind = tkFloatLiteral) or (Current().Kind = tkStringLiteral) or
     (Current().Kind = tkWStringLiteral) or (Current().Kind = tkTrue) or
     (Current().Kind = tkFalse) or (Current().Kind = tkNil) or
     (Current().Kind = tkLParen) or (Current().Kind = tkLBracket) or
     (Current().Kind = tkMinus) or (Current().Kind = tkPlus) or
     (Current().Kind = tkNot) or (Current().Kind = tkVarArgs) or
     (Current().Kind = tkAddress) or IsIntrinsicToken(Current().Kind) or
     (FLexer.GetCategory(Current().Kind) = tcPrimitive) then
    Result.ValueExpr := DoParseExpression();
end;

function TWklParser.DoParseGuardStmt(): TWklGuardNode;
var
  LStartLoc: TSourceRange;
begin
  Result := TWklGuardNode.Create();
  InitNode(Result, TokIdx());
  LStartLoc := Current().Location;
  Consume();

  Result.GuardBody := TWklBlockNode.Create();
  InitNode(Result.GuardBody, TokIdx());
  DoParseStatementSeq(Result.GuardBody.Statements, [tkExcept, tkFinally, tkEnd]);

  if Match(tkExcept) then
  begin
    Result.ExceptBody := TWklBlockNode.Create();
    InitNode(Result.ExceptBody, TokIdx());
    DoParseStatementSeq(Result.ExceptBody.Statements, [tkFinally, tkEnd]);
  end;

  if Match(tkFinally) then
  begin
    Result.FinallyBody := TWklBlockNode.Create();
    InitNode(Result.FinallyBody, TokIdx());
    DoParseStatementSeq(Result.FinallyBody.Statements, [tkEnd]);
  end;

  ExpectBlockEnd('guard', LStartLoc);
end;

function TWklParser.DoParseThrowStmt(): TWklNode;
var
  LThrow: TWklThrowNode;
  LThrowCode: TWklThrowCodeNode;
begin
  if Check(tkThrowCode) then
  begin
    LThrowCode := TWklThrowCodeNode.Create();
    InitNode(LThrowCode, TokIdx());
    Consume();
    Expect(tkLParen);
    LThrowCode.CodeExpr := DoParseExpression();
    Expect(tkComma);
    LThrowCode.MsgExpr := DoParseExpression();
    Expect(tkRParen);
    Result := LThrowCode;
  end
  else
  begin
    LThrow := TWklThrowNode.Create();
    InitNode(LThrow, TokIdx());
    Consume();
    Expect(tkLParen);
    LThrow.CodeExpr := DoParseExpression();
    Expect(tkRParen);
    Result := LThrow;
  end;
end;

function TWklParser.DoParseMemOpStmt(): TWklNode;
var
  LMemOp: TWklMemOpNode;
  LMemOp2: TWklMemOp2Node;
  LKind: TWklTokenKind;
begin
  LKind := Current().Kind;

  if (LKind = tkResizeMem) or (LKind = tkSetLength) then
  begin
    LMemOp2 := TWklMemOp2Node.Create();
    InitNode(LMemOp2, TokIdx());
    if LKind = tkResizeMem then
      LMemOp2.Kind := mo2ResizeMem
    else
      LMemOp2.Kind := mo2SetLength;
    Consume();
    Expect(tkLParen);
    LMemOp2.FirstArg := DoParseExpression();
    Expect(tkComma);
    LMemOp2.SecondArg := DoParseExpression();
    Expect(tkRParen);
    Result := LMemOp2;
  end
  else
  begin
    LMemOp := TWklMemOpNode.Create();
    InitNode(LMemOp, TokIdx());
    if LKind = tkNew then
      LMemOp.Kind := moNew
    else if LKind = tkDispose then
      LMemOp.Kind := moDispose
    else if LKind = tkGetMem then
      LMemOp.Kind := moGetMem
    else
      LMemOp.Kind := moFreeMem;
    Consume();
    Expect(tkLParen);
    LMemOp.ArgExpr := DoParseExpression();
    Expect(tkRParen);
    Result := LMemOp;
  end;
end;

function TWklParser.DoParsePrintStmt(): TWklPrintNode;
begin
  Result := TWklPrintNode.Create();
  InitNode(Result, TokIdx());
  Result.IsPrintLn := Check(tkPrintLn);
  Consume();

  Expect(tkLParen);
  if not Check(tkRParen) then
  begin
    repeat
      Result.Args.Add(DoParseExpression());
    until not Match(tkComma);
  end;
  Expect(tkRParen);
end;

function TWklParser.DoParseAssertStmt(): TWklAssertNode;
begin
  Result := TWklAssertNode.Create();
  InitNode(Result, TokIdx());
  Result.Kind := TokenToAssertKind(Current().Kind);
  Consume();

  Expect(tkLParen);
  if not Check(tkRParen) then
  begin
    repeat
      Result.Args.Add(DoParseExpression());
    until not Match(tkComma);
  end;
  Expect(tkRParen);
end;

function TWklParser.DoParseExpression(): TWklNode;
begin
  Result := DoParsePrecedence(1);
end;

function TWklParser.DoParsePrecedence(const AMinPrec: Integer): TWklNode;
var
  LLeft: TWklNode;
  LBin: TWklBinaryExprNode;
  LPrec: Integer;
  LOpKind: TWklTokenKind;
  LOpTokIdx: Int64;
begin
  LLeft := DoParsePrefix();

  while True do
  begin
    LOpKind := Current().Kind;
    LPrec := GetPrecedence(LOpKind);
    if LPrec < AMinPrec then
      Break;

    LOpTokIdx := TokIdx();
    Consume();

    LBin := TWklBinaryExprNode.Create();
    InitNode(LBin, LOpTokIdx);
    LBin.Op := TokenToBinaryOp(LOpKind);
    LBin.Left := LLeft;
    LBin.Right := DoParsePrecedence(LPrec + 1);
    LLeft := LBin;
  end;

  Result := LLeft;
end;

function TWklParser.DoMakeLiteral(const ATokIdx: Int64): TWklLiteralNode;
var
  LTok: TWklToken;
begin
  Result := TWklLiteralNode.Create();
  InitNode(Result, ATokIdx);
  LTok := FLexer.Tokens[ATokIdx];

  if LTok.Kind = tkIntLiteral then
  begin
    Result.Kind := lkInt;
    Result.IntValue := LTok.LiteralValue.AsInt64;
  end
  else if LTok.Kind = tkFloatLiteral then
  begin
    Result.Kind := lkFloat;
    Result.FloatValue := LTok.LiteralValue.AsExtended;
    Result.IsFloat32 := LTok.RawText.EndsWith('f', True);
  end
  else if LTok.Kind = tkStringLiteral then
  begin
    Result.Kind := lkString;
    Result.StringValue := LTok.LiteralValue.AsString;
  end
  else if LTok.Kind = tkWStringLiteral then
  begin
    Result.Kind := lkWString;
    Result.StringValue := LTok.LiteralValue.AsString;
  end
  else if (LTok.Kind = tkTrue) or (LTok.Kind = tkFalse) then
  begin
    Result.Kind := lkBool;
    Result.BoolValue := LTok.Kind = tkTrue;
  end
  else if LTok.Kind = tkNil then
    Result.Kind := lkNil;
end;

function TWklParser.DoParsePrefix(): TWklNode;
var
  LTokIdx: Int64;
  LUnary: TWklUnaryExprNode;
  LIdent: TWklIdentifierNode;
  LCast: TWklTypeCastNode;
  LTypeRef: TWklTypeRefNode;
begin
  // Unary operators
  if Check(tkNot) or Check(tkMinus) or Check(tkPlus) or Check(tkAddress) then
  begin
    LUnary := TWklUnaryExprNode.Create();
    InitNode(LUnary, TokIdx());
    LUnary.Op := TokenToUnaryOp(Current().Kind);
    if Current().Kind = tkAddress then
    begin
      Consume();
      Expect(tkOf);
    end
    else
      Consume();
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  // Literals
  if Check(tkIntLiteral) or Check(tkFloatLiteral) or Check(tkStringLiteral) or
     Check(tkWStringLiteral) or Check(tkTrue) or Check(tkFalse) or Check(tkNil) then
  begin
    LTokIdx := TokIdx();
    Consume();
    Result := DoMakeLiteral(LTokIdx);
    Exit;
  end;

  // Parenthesized expression
  if Check(tkLParen) then
  begin
    Consume();
    Result := DoParseExpression();
    Expect(tkRParen);
    Result := DoParseDesignator(Result);
    Exit;
  end;

  // Set literal
  if Check(tkLBracket) then
  begin
    Result := DoParseSetLiteral();
    Exit;
  end;

  // Intrinsic calls
  if IsIntrinsicToken(Current().Kind) then
  begin
    Result := DoParseIntrinsic();
    Exit;
  end;

  // Type cast: primitive_type(expr)
  if FLexer.GetCategory(Current().Kind) = tcPrimitive then
  begin
    if PeekAt(1).Kind = tkLParen then
    begin
      LCast := TWklTypeCastNode.Create();
      InitNode(LCast, TokIdx());
      LTypeRef := TWklTypeRefNode.Create();
      InitNode(LTypeRef, TokIdx());
      LCast.TargetType := LTypeRef;
      Consume();
      Expect(tkLParen);
      LCast.Expr := DoParseExpression();
      Expect(tkRParen);
      Result := DoParseDesignator(LCast);
      Exit;
    end;

    // Bare primitive type name (e.g. size(int32))
    LTypeRef := TWklTypeRefNode.Create();
    InitNode(LTypeRef, TokIdx());
    Consume();
    Result := LTypeRef;
    Exit;
  end;

  // varargs.<count|next|get|reset|copy> -- keyword-shaped intrinsic access
  if Check(tkVarArgs) then
  begin
    Result := DoParseVarArgsAccess();
    Exit;
  end;

  // Identifier -- possibly call, field access, record literal, etc.
  if Check(tkIdentifier) then
  begin
    LTokIdx := TokIdx();
    Consume();

    // Record literal: TypeName(fieldname: expr, ...)
    if Check(tkLParen) and (PeekAt(1).Kind = tkIdentifier) and
       (PeekAt(2).Kind = tkColon) then
    begin
      Result := DoParseRecordLiteral(LTokIdx);
      Exit;
    end;

    LIdent := TWklIdentifierNode.Create();
    InitNode(LIdent, LTokIdx);
    Result := DoParseDesignator(LIdent);
    Exit;
  end;

  FErrors.Add(Current().Location, esError, WKL_ERR_PAR_007,
    RSParInvalidExpression, [Current().TokenText]);
  Result := nil;
  Consume();
end;

function TWklParser.DoParseDesignator(const ABase: TWklNode): TWklNode;
var
  LCurrent: TWklNode;
  LDot: TWklDotAccessNode;
  LIndex: TWklIndexAccessNode;
  LDeref: TWklDerefNode;
  LCall: TWklCallExprNode;
begin
  LCurrent := ABase;

  while True do
  begin
    if Check(tkDot) then
    begin
      Consume();
      LDot := TWklDotAccessNode.Create();
      InitNode(LDot, TokIdx());
      Expect(tkIdentifier);
      LDot.BaseExpr := LCurrent;
      LDot.AccessKind := dakUnresolved;
      LCurrent := LDot;
    end
    else if Check(tkLBracket) then
    begin
      LIndex := TWklIndexAccessNode.Create();
      InitNode(LIndex, TokIdx());
      Consume();
      LIndex.BaseExpr := LCurrent;
      LIndex.IndexExpr := DoParseExpression();
      Expect(tkRBracket);
      LCurrent := LIndex;
    end
    else if Check(tkCaret) then
    begin
      LDeref := TWklDerefNode.Create();
      InitNode(LDeref, TokIdx());
      Consume();
      LDeref.BaseExpr := LCurrent;
      LCurrent := LDeref;
    end
    else if Check(tkLParen) then
    begin
      LCall := TWklCallExprNode.Create();
      InitNode(LCall, TokIdx());
      Consume();
      LCall.Callee := LCurrent;
      if not Check(tkRParen) then
      begin
        repeat
          LCall.Args.Add(DoParseExpression());
        until not Match(tkComma);
      end;
      Expect(tkRParen);
      LCurrent := LCall;
    end
    else
      Break;
  end;

  Result := LCurrent;
end;

function TWklParser.DoParseSetLiteral(): TWklSetLiteralNode;
var
  LElem: TWklSetElementNode;
begin
  Result := TWklSetLiteralNode.Create();
  InitNode(Result, TokIdx());
  Consume();

  if not Check(tkRBracket) then
  begin
    repeat
      LElem := TWklSetElementNode.Create();
      LElem.Location := Current().Location;
      LElem.ValueExpr := DoParseExpression();
      if Match(tkDotDot) then
        LElem.RangeEnd := DoParseExpression();
      Result.Elements.Add(LElem);
    until not Match(tkComma);
  end;
  Expect(tkRBracket);
end;

function TWklParser.DoParseIntrinsic(): TWklIntrinsicNode;
begin
  Result := TWklIntrinsicNode.Create();
  InitNode(Result, TokIdx());
  Result.Kind := TokenToIntrinsicKind(Current().Kind);
  Consume();
  Expect(tkLParen);

  if not Check(tkRParen) then
  begin
    repeat
      Result.Args.Add(DoParseExpression());
    until not Match(tkComma);
  end;
  Expect(tkRParen);
end;

function TWklParser.DoParseVarArgsAccess(): TWklIntrinsicNode;
var
  LMember: string;
begin
  Result := TWklIntrinsicNode.Create();
  InitNode(Result, TokIdx());
  Consume(); // eat 'varargs'
  Expect(tkDot);
  LMember := Current().TokenText;
  if not Check(tkIdentifier) then
  begin
    FErrors.Add(Current().Location, esError, WKL_ERR_PAR_008,
      RSParExpectedIdentifier);
    Exit;
  end;
  Consume();

  if LMember = 'count' then
    Result.Kind := ikVarArgsCount
  else if LMember = 'next' then
  begin
    Result.Kind := ikVarArgsNext;
    Expect(tkLParen);
    Result.TypeExpr := DoParseTypeExpr();
    Expect(tkRParen);
  end
  else if LMember = 'get' then
  begin
    Result.Kind := ikVarArgsGet;
    Expect(tkLParen);
    Result.Args.Add(DoParseExpression());
    Expect(tkComma);
    Result.TypeExpr := DoParseTypeExpr();
    Expect(tkRParen);
  end
  else if LMember = 'reset' then
  begin
    Result.Kind := ikVarArgsReset;
    Expect(tkLParen);
    Expect(tkRParen);
  end
  else if LMember = 'copy' then
  begin
    Result.Kind := ikVarArgsCopy;
    Expect(tkLParen);
    Expect(tkRParen);
  end
  else
    FErrors.Add(Result.Location, esError, WKL_ERR_PAR_007,
      RSParInvalidExpression, [LMember]);
end;

function TWklParser.DoParseRecordLiteral(const ATypeNameTokIdx: Int64): TWklRecordLiteralNode;
var
  LInit: TWklFieldInitNode;
begin
  Result := TWklRecordLiteralNode.Create();
  InitNode(Result, ATypeNameTokIdx);
  Consume(); // eat '('

  if not Check(tkRParen) then
  begin
    repeat
      LInit := TWklFieldInitNode.Create();
      InitNode(LInit, TokIdx());
      Expect(tkIdentifier);
      Expect(tkColon);
      LInit.ValueExpr := DoParseExpression();
      Result.FieldInits.Add(LInit);
    until not Match(tkComma);
  end;
  Expect(tkRParen);
end;

end.
