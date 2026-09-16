{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.Semantics - Semantic analysis over the OOP AST.

  Resolves names, types, overloads and record layouts, and writes every
  result back into the AST. The emitter reads only what is written here.

  Semantics owns the primitive type sentinels (one TWklTypeRefNode per
  built-in type name). A TWklTypeRefNode in the tree whose Name is a primitive
  keyword gets ResolvedDecl pointed at the matching sentinel, so "resolved"
  always means non-nil. A ResolvedDecl that IS a TWklTypeRefNode is therefore
  a primitive; anything else is a user declaration.

  Overload groups are created here but owned by TWklModuleNode.OverloadGroups
  so they outlive the analysis scopes.

  Dependencies: StdApp.Base, StdApp.Resources, Waskal.Lexer, Waskal.AST
===============================================================================}

unit Waskal.Semantics;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Resources,
  Waskal.Lexer,
  Waskal.AST;

const
  // Error codes
  WKL_ERR_SEM_001 = 'SEM001';  // Undeclared identifier
  WKL_ERR_SEM_002 = 'SEM002';  // Duplicate declaration
  WKL_ERR_SEM_003 = 'SEM003';  // Type mismatch
  WKL_ERR_SEM_004 = 'SEM004';  // Break/continue outside loop
  WKL_ERR_SEM_005 = 'SEM005';  // Invalid return
  WKL_ERR_SEM_006 = 'SEM006';  // Unresolved forward
  WKL_ERR_SEM_007 = 'SEM007';  // Module validation error
  WKL_ERR_SEM_008 = 'SEM008';  // Invalid expression
  WKL_ERR_SEM_009 = 'SEM009';  // Argument count mismatch
  WKL_ERR_SEM_010 = 'SEM010';  // Invalid dot access
  WKL_ERR_SEM_011 = 'SEM011';  // No matching overload
  WKL_ERR_SEM_012 = 'SEM012';  // Forward/implementation signature mismatch
  WKL_ERR_SEM_013 = 'SEM013';  // varargs access outside a variadic routine

type
  { TWklScopeKind }
  TWklScopeKind = (
    skModule,
    skRoutine,
    skBlock
  );

  { TWklScope }
  // One lexical scope. Maps a name to the declaring node. Nothing is owned;
  // every value is a node inside the module tree or a primitive sentinel.
  TWklScope = class(TObject)
  private
    FScopeKind: TWklScopeKind;
    FParent: TWklScope;
    FSymbols: TDictionary<string, TWklNode>;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Declare(const AName: string; const ANode: TWklNode);
    function Lookup(const AName: string): TWklNode;
    function LookupLocal(const AName: string): TWklNode;

    property ScopeKind: TWklScopeKind read FScopeKind write FScopeKind;
    property Parent: TWklScope read FParent write FParent;
  end;

  { TWklSemantics }
  TWklSemantics = class(TBaseObject)
  private
    FLexer: TWklLexer;
    FModule: TWklModuleNode;
    FCurrentScope: TWklScope;
    FScopeStack: TStack<TWklScope>;
    FLoopDepth: Integer;
    FCurrentRoutine: TWklRoutineDeclNode;

    // Primitive type sentinels. Owned by Waskal.AST (WklPrimitiveType);
    // these are references only, valid for the life of the process.
    FTypeInt32: TWklTypeRefNode;
    FTypeInt64: TWklTypeRefNode;
    FTypeFloat32: TWklTypeRefNode;
    FTypeFloat64: TWklTypeRefNode;
    FTypeBoolean: TWklTypeRefNode;
    FTypeString: TWklTypeRefNode;
    FTypeWString: TWklTypeRefNode;
    FTypePointer: TWklTypeRefNode;

    // Scope management
    function PushScope(const AKind: TWklScopeKind): TWklScope;
    procedure PopScope();

    // Primitive sentinels
    function DoFindPrimitive(const AName: string): TWklTypeRefNode;

    // Type helpers
    function DoTypeOfDecl(const ADecl: TWklNode): TWklNode;
    function DoTypeDefOf(const AType: TWklNode): TWklNode;
    function DoPrimitiveNameOf(const AType: TWklNode): string;
    function DoIsLiteralExpr(const AExpr: TWklNode): Boolean;
    function DoTypesEqual(const ATypeA: TWklNode; const ATypeB: TWklNode): Boolean;
    function DoTypeIdOf(const AType: TWklNode): Int64;
    function DoParamSignaturesMatch(const ARoutineA: TWklRoutineDeclNode;
      const ARoutineB: TWklRoutineDeclNode): Boolean;
    function DoResolveOverload(const AGroup: TWklOverloadGroupNode;
      const AArgs: TWklNodeList): TWklRoutineDeclNode;
    function DoFindField(const ARecordDef: TWklNode;
      const AName: string): TWklFieldDeclNode;
    function DoFindChoicesValue(const AChoices: TWklChoicesTypeNode;
      const AName: string): TWklChoicesValueNode;
    function DoFindModuleMember(const AModule: TWklModuleNode;
      const AName: string): TWklNode;

    // Pass 1 - registration
    procedure DoRegisterDeclarations();
    procedure DoRegisterRoutine(const ARoutine: TWklRoutineDeclNode;
      const AExisting: TWklNode);
    procedure DoRegisterImports();

    // Pass 2 - declarations
    procedure DoAnalyzeDeclarations();
    procedure DoAnalyzeConstDecl(const ANode: TWklConstDeclNode);
    procedure DoAnalyzeTypeDecl(const ANode: TWklTypeDeclNode);
    procedure DoAnalyzeTypeDef(const ANode: TWklNode);
    procedure DoAnalyzeFieldList(const AFields: TWklNodeList);
    procedure DoAnalyzeVarDecl(const ANode: TWklVarDeclNode;
      const AIsGlobal: Boolean);
    procedure DoAnalyzeRoutineDecl(const ANode: TWklRoutineDeclNode);
    procedure DoAnalyzeForwardType(const ANode: TWklForwardTypeNode);
    procedure DoAnalyzeForwardRoutine(const ANode: TWklForwardRoutineNode);
    function DoForwardMismatchReason(const AForward: TWklForwardRoutineNode;
      const AImpl: TWklRoutineDeclNode): string;

    // Layout pass
    procedure DoComputeTypeLayouts();
    function DoComputeTypeSize(const AType: TWklNode): Int64;
    function DoIsAggregateTypeDef(const AType: TWklNode): Boolean;
    function DoPrimitiveSize(const AName: string): Int64;
    function DoComputeRecordLayout(const AFields: TWklNodeList;
      const AIsPacked: Boolean; const AAlignment: Int64;
      const ABaseType: TWklNode): Int64;
    function DoComputeOverlayLayout(const AFields: TWklNodeList): Int64;
    procedure DoShiftFieldOffsets(const AFields: TWklNodeList;
      const ADelta: Int64);
    function DoFoldIntLiteral(const AExpr: TWklNode; out AValue: Int64): Boolean;

    // Statements
    procedure DoAnalyzeStatement(const ANode: TWklNode);
    procedure DoAnalyzeStatementList(const AList: TWklNodeList);
    procedure DoAnalyzeBlock(const ABlock: TWklBlockNode);
    procedure DoAnalyzeAssign(const ANode: TWklAssignNode);
    procedure DoAnalyzeIf(const ANode: TWklIfNode);
    procedure DoAnalyzeWhile(const ANode: TWklWhileNode);
    procedure DoAnalyzeFor(const ANode: TWklForNode);
    procedure DoAnalyzeRepeat(const ANode: TWklRepeatNode);
    procedure DoAnalyzeMatch(const ANode: TWklMatchNode);
    procedure DoAnalyzeReturn(const ANode: TWklReturnNode);
    procedure DoAnalyzeGuard(const ANode: TWklGuardNode);
    procedure DoAnalyzeMemOp(const ANode: TWklMemOpNode);
    procedure DoAnalyzeMemOp2(const ANode: TWklMemOp2Node);
    procedure DoAnalyzeArgList(const AArgs: TWklNodeList);
    procedure DoPropagateLiteralType(const AExpr: TWklNode;
      const AType: TWklNode);

    // Expressions
    procedure DoAnalyzeExpr(const ANode: TWklNode);
    procedure DoAnalyzeLiteral(const ANode: TWklLiteralNode);
    procedure DoAnalyzeIdentifier(const ANode: TWklIdentifierNode);
    procedure DoAnalyzeDotAccess(const ANode: TWklDotAccessNode);
    procedure DoAnalyzeIndexAccess(const ANode: TWklIndexAccessNode);
    procedure DoAnalyzeDeref(const ANode: TWklDerefNode);
    procedure DoAnalyzeCallExpr(const ANode: TWklCallExprNode);
    procedure DoCoerceStringArgs(const ANode: TWklCallExprNode;
      const ARoutine: TWklRoutineDeclNode);
    procedure DoAnalyzeBinaryExpr(const ANode: TWklBinaryExprNode);
    procedure DoAnalyzeUnaryExpr(const ANode: TWklUnaryExprNode);
    procedure DoAnalyzeTypeCast(const ANode: TWklTypeCastNode);
    procedure DoAnalyzeIntrinsic(const ANode: TWklIntrinsicNode);
    procedure DoAnalyzeVarArgsIntrinsic(const ANode: TWklIntrinsicNode);
    procedure DoWidenPackedIntLiteral(const AArg: TWklNode);
    procedure DoAnalyzeTypeRef(const ANode: TWklTypeRefNode);
    procedure DoAnalyzeSetLiteral(const ANode: TWklSetLiteralNode);
    procedure DoAnalyzeRecordLiteral(const ANode: TWklRecordLiteralNode);

    // Module-level blocks and validation
    procedure DoAnalyzeTestBlocks();
    procedure DoValidateForwards();
    procedure DoValidateModule();

    // Errors
    procedure SemError(const ACode: string; const AMsg: string;
      const ANode: TWklNode); overload;
    procedure SemError(const ACode: string; const AMsg: string;
      const AArgs: array of const; const ANode: TWklNode); overload;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Analyze AModule in place. Returns True when no errors were reported.
    // Errors go to the shared TErrors set via SetErrors().
    function Analyze(const ALexer: TWklLexer;
      const AModule: TWklModuleNode): Boolean;
  end;

implementation

var
  { GNextTypeId }
  // Process-wide counter for runtime type tags of non-primitive TypeDefs.
  // Starts above the primitive range (1..Length(WKL_PRIMITIVE_NAMES)).
  GNextTypeId: Int64 = 1000;

{ TWklScope }
constructor TWklScope.Create();
begin
  inherited;

  FScopeKind := skModule;
  FParent := nil;
  FSymbols := TDictionary<string, TWklNode>.Create();
end;

destructor TWklScope.Destroy();
begin
  FSymbols.Free();

  inherited;
end;

procedure TWklScope.Declare(const AName: string; const ANode: TWklNode);
begin
  FSymbols.AddOrSetValue(AName, ANode);
end;

function TWklScope.Lookup(const AName: string): TWklNode;
var
  LScope: TWklScope;
begin
  Result := nil;
  LScope := Self;
  while LScope <> nil do
  begin
    if LScope.FSymbols.TryGetValue(AName, Result) then
      Exit;
    LScope := LScope.FParent;
  end;
end;

function TWklScope.LookupLocal(const AName: string): TWklNode;
begin
  if not FSymbols.TryGetValue(AName, Result) then
    Result := nil;
end;

{ TWklSemantics }
constructor TWklSemantics.Create();
begin
  inherited;

  FLexer := nil;
  FModule := nil;
  FCurrentScope := nil;
  FScopeStack := TStack<TWklScope>.Create();
  FLoopDepth := 0;
  FCurrentRoutine := nil;

  // Bind the well-known primitives once; the AST owns the nodes
  FTypeInt32 := DoFindPrimitive('int32');
  FTypeInt64 := DoFindPrimitive('int64');
  FTypeFloat32 := DoFindPrimitive('float32');
  FTypeFloat64 := DoFindPrimitive('float64');
  FTypeBoolean := DoFindPrimitive('bool');
  FTypeString := DoFindPrimitive('string');
  FTypeWString := DoFindPrimitive('wstring');
  FTypePointer := DoFindPrimitive('ptr');
end;

destructor TWklSemantics.Destroy();
begin
  while FScopeStack.Count > 0 do
    FScopeStack.Pop().Free();
  FScopeStack.Free();

  inherited;
end;

function TWklSemantics.PushScope(const AKind: TWklScopeKind): TWklScope;
begin
  Result := TWklScope.Create();
  Result.ScopeKind := AKind;
  Result.Parent := FCurrentScope;
  FScopeStack.Push(Result);
  FCurrentScope := Result;
end;

procedure TWklSemantics.PopScope();
begin
  if FScopeStack.Count = 0 then
    Exit;
  FCurrentScope := FCurrentScope.Parent;
  FScopeStack.Pop().Free();
end;

function TWklSemantics.DoFindPrimitive(const AName: string): TWklTypeRefNode;
begin
  Result := WklPrimitiveType(AName);
end;

// The type a declaration contributes when an identifier resolves to it.
function TWklSemantics.DoTypeOfDecl(const ADecl: TWklNode): TWklNode;
begin
  Result := nil;
  if ADecl = nil then
    Exit;

  if ADecl is TWklVarDeclNode then
    Result := TWklVarDeclNode(ADecl).TypeExpr
  else if ADecl is TWklConstDeclNode then
  begin
    Result := TWklConstDeclNode(ADecl).TypeExpr;
    // Untyped const: type is whatever the value resolved to
    if (Result = nil) and (TWklConstDeclNode(ADecl).ValueExpr <> nil) then
      Result := TWklConstDeclNode(ADecl).ValueExpr.ResolvedType;
  end
  else if ADecl is TWklParamNode then
    Result := TWklParamNode(ADecl).TypeExpr
  else if ADecl is TWklFieldDeclNode then
    Result := TWklFieldDeclNode(ADecl).TypeExpr
  else if ADecl is TWklForNode then
  begin
    // Loop iterator takes the type of its start expression
    if TWklForNode(ADecl).StartExpr <> nil then
      Result := TWklForNode(ADecl).StartExpr.ResolvedType;
  end
  else if (ADecl is TWklRoutineDeclNode) or (ADecl is TWklOverloadGroupNode)
    or (ADecl is TWklTypeDeclNode) or (ADecl is TWklTypeRefNode) then
    // The declaration itself stands as the "type"
    Result := ADecl;
end;

// Follow a type expression to the structural definition it names.
// TypeRef -> TypeDecl -> TypeDef. Primitive sentinels return themselves.
function TWklSemantics.DoTypeDefOf(const AType: TWklNode): TWklNode;
var
  LDecl: TWklNode;
begin
  Result := AType;
  if AType = nil then
    Exit;

  if AType is TWklTypeRefNode then
  begin
    LDecl := TWklTypeRefNode(AType).ResolvedDecl;
    if LDecl = nil then
    begin
      // The primitive sentinel itself (e.g. a literal's ResolvedType) is
      // its own definition; anything else unresolved has no def
      if WklPrimitiveType(AType.Name) = AType then
        Exit(AType);
      Exit(nil);
    end;
    if LDecl is TWklTypeRefNode then
      Exit(LDecl);  // primitive sentinel
    if LDecl is TWklForwardTypeNode then
      LDecl := TWklForwardTypeNode(LDecl).ResolvedDecl;
    if LDecl is TWklTypeDeclNode then
      Exit(DoTypeDefOf(TWklTypeDeclNode(LDecl).TypeDef));
    Exit(LDecl);
  end;

  if AType is TWklTypeDeclNode then
    Exit(DoTypeDefOf(TWklTypeDeclNode(AType).TypeDef));

  if AType is TWklForwardTypeNode then
    Exit(DoTypeDefOf(TWklForwardTypeNode(AType).ResolvedDecl));
end;

// Primitive keyword name of a type, or '' when it is not primitive.
function TWklSemantics.DoPrimitiveNameOf(const AType: TWklNode): string;
var
  LDef: TWklNode;
begin
  Result := '';
  LDef := DoTypeDefOf(AType);
  if (LDef <> nil) and (LDef is TWklTypeRefNode) and
     (TWklTypeRefNode(LDef).ResolvedDecl = nil) then
    Result := LDef.Name;
end;

function TWklSemantics.DoIsLiteralExpr(const AExpr: TWklNode): Boolean;
begin
  Result := (AExpr <> nil) and (AExpr is TWklLiteralNode) and
    (TWklLiteralNode(AExpr).Kind in [lkInt, lkFloat, lkBool, lkNil, lkString,
    lkWString]);
end;

function TWklSemantics.DoTypesEqual(const ATypeA: TWklNode;
  const ATypeB: TWklNode): Boolean;
var
  LDefA: TWklNode;
  LDefB: TWklNode;
begin
  if ATypeA = ATypeB then
    Exit(True);
  if (ATypeA = nil) or (ATypeB = nil) then
    Exit(False);

  LDefA := DoTypeDefOf(ATypeA);
  LDefB := DoTypeDefOf(ATypeB);
  if (LDefA = nil) or (LDefB = nil) then
    Exit(False);

  // Same definition object = same type. Primitives are unique sentinels,
  // user types resolve to one TypeDef object, so pointer equality is exact.
  Result := (LDefA = LDefB);
end;

// Runtime type tag = DoTypesEqual lowered to an integer. Primitives carry a
// fixed id from creation; every other TypeDef object gets a program-unique
// id on first request (counter is process-wide so ids never collide across
// modules). 0 = unresolvable type.
function TWklSemantics.DoTypeIdOf(const AType: TWklNode): Int64;
var
  LDef: TWklNode;
begin
  Result := 0;
  LDef := DoTypeDefOf(AType);
  if LDef = nil then
    Exit;
  if LDef.TypeId = 0 then
  begin
    Inc(GNextTypeId);
    LDef.TypeId := GNextTypeId;
  end;
  Result := LDef.TypeId;
end;

function TWklSemantics.DoParamSignaturesMatch(
  const ARoutineA: TWklRoutineDeclNode;
  const ARoutineB: TWklRoutineDeclNode): Boolean;
var
  LI: Integer;
  LParamA: TWklParamNode;
  LParamB: TWklParamNode;
begin
  if ARoutineA.Params.Count <> ARoutineB.Params.Count then
    Exit(False);
  // f(a) and f(a; ...) are distinct signatures
  if ARoutineA.IsVariadic <> ARoutineB.IsVariadic then
    Exit(False);

  for LI := 0 to ARoutineA.Params.Count - 1 do
  begin
    LParamA := TWklParamNode(ARoutineA.Params[LI]);
    LParamB := TWklParamNode(ARoutineB.Params[LI]);

    if (LParamA.TypeExpr = nil) <> (LParamB.TypeExpr = nil) then
      Exit(False);
    if LParamA.TypeExpr = nil then
      Continue;

    // Registration runs before type refs are analyzed, so compare by
    // spelling: a TypeRef by Name, a structural type by node identity.
    if (LParamA.TypeExpr is TWklTypeRefNode) and
       (LParamB.TypeExpr is TWklTypeRefNode) then
    begin
      if LParamA.TypeExpr.Name <> LParamB.TypeExpr.Name then
        Exit(False);
    end
    else if LParamA.TypeExpr <> LParamB.TypeExpr then
      Exit(False);
  end;

  Result := True;
end;

function TWklSemantics.DoResolveOverload(const AGroup: TWklOverloadGroupNode;
  const AArgs: TWklNodeList): TWklRoutineDeclNode;
var
  LI: Integer;
  LJ: Integer;
  LPass: Integer;
  LCandidate: TWklRoutineDeclNode;
  LArgCount: Integer;
  LMatch: Boolean;
  LArgType: TWklNode;
  LParamType: TWklNode;
begin
  Result := nil;
  if AGroup = nil then
    Exit;

  LArgCount := 0;
  if AArgs <> nil then
    LArgCount := AArgs.Count;

  // Pass 0: exact (non-variadic) candidates. Pass 1: variadic candidates,
  // matched on the fixed prefix only. An exact match always wins.
  for LPass := 0 to 1 do
  begin
    for LI := 0 to AGroup.Routines.Count - 1 do
    begin
      LCandidate := TWklRoutineDeclNode(AGroup.Routines[LI]);
      if LCandidate.IsVariadic <> (LPass = 1) then
        Continue;
      if LPass = 0 then
      begin
        if LCandidate.Params.Count <> LArgCount then
          Continue;
      end
      else
      begin
        if LCandidate.Params.Count > LArgCount then
          Continue;
      end;

      LMatch := True;
      for LJ := 0 to LCandidate.Params.Count - 1 do
      begin
        LArgType := AArgs[LJ].ResolvedType;
        LParamType := TWklParamNode(LCandidate.Params[LJ]).TypeExpr;
        if (LArgType = nil) or (not DoTypesEqual(LArgType, LParamType)) then
        begin
          LMatch := False;
          Break;
        end;
      end;

      if LMatch then
        Exit(LCandidate);
    end;
  end;
end;

// Find a field by name in a record or overlay definition. Searches direct
// fields, fields inside anonymous overlays/records, then the base type.
function TWklSemantics.DoFindField(const ARecordDef: TWklNode;
  const AName: string): TWklFieldDeclNode;
var
  LFields: TWklNodeList;
  LBaseType: TWklNode;
  LI: Integer;
  LField: TWklNode;
begin
  Result := nil;
  if ARecordDef = nil then
    Exit;

  LFields := nil;
  LBaseType := nil;
  if ARecordDef is TWklRecordTypeNode then
  begin
    LFields := TWklRecordTypeNode(ARecordDef).Fields;
    LBaseType := TWklRecordTypeNode(ARecordDef).BaseType;
  end
  else if ARecordDef is TWklOverlayTypeNode then
    LFields := TWklOverlayTypeNode(ARecordDef).Fields
  else if ARecordDef is TWklAnonRecordNode then
    LFields := TWklAnonRecordNode(ARecordDef).Fields
  else if ARecordDef is TWklAnonOverlayNode then
    LFields := TWklAnonOverlayNode(ARecordDef).Fields;

  if LFields = nil then
    Exit;

  // Direct fields first
  for LI := 0 to LFields.Count - 1 do
  begin
    LField := LFields[LI];
    if (LField is TWklFieldDeclNode) and (LField.Name = AName) then
      Exit(TWklFieldDeclNode(LField));
  end;

  // Then nested anonymous groups
  for LI := 0 to LFields.Count - 1 do
  begin
    LField := LFields[LI];
    if (LField is TWklAnonOverlayNode) or (LField is TWklAnonRecordNode) then
    begin
      Result := DoFindField(LField, AName);
      if Result <> nil then
        Exit;
    end;
  end;

  // Then inheritance
  if LBaseType <> nil then
    Result := DoFindField(DoTypeDefOf(LBaseType), AName);
end;

function TWklSemantics.DoFindChoicesValue(const AChoices: TWklChoicesTypeNode;
  const AName: string): TWklChoicesValueNode;
var
  LI: Integer;
begin
  Result := nil;
  for LI := 0 to AChoices.Values.Count - 1 do
  begin
    if AChoices.Values[LI].Name = AName then
      Exit(TWklChoicesValueNode(AChoices.Values[LI]));
  end;
end;

// Find a top-level declaration in an imported module. Routines in a group
// resolve to the group so callers can overload-resolve.
function TWklSemantics.DoFindModuleMember(const AModule: TWklModuleNode;
  const AName: string): TWklNode;
var
  LI: Integer;
begin
  Result := nil;
  if AModule = nil then
    Exit;

  for LI := 0 to AModule.OverloadGroups.Count - 1 do
  begin
    if AModule.OverloadGroups[LI].Name = AName then
      Exit(AModule.OverloadGroups[LI]);
  end;

  for LI := 0 to AModule.Declarations.Count - 1 do
  begin
    if AModule.Declarations[LI].Name = AName then
      Exit(AModule.Declarations[LI]);
  end;
end;

procedure TWklSemantics.DoRegisterDeclarations();
var
  LI: Integer;
  LDecl: TWklNode;
  LExisting: TWklNode;
begin
  for LI := 0 to FModule.Declarations.Count - 1 do
  begin
    LDecl := FModule.Declarations[LI];
    if LDecl.Name = '' then
      Continue;

    LExisting := FCurrentScope.LookupLocal(LDecl.Name);

    if LDecl is TWklRoutineDeclNode then
    begin
      DoRegisterRoutine(TWklRoutineDeclNode(LDecl), LExisting);
      Continue;
    end;

    if LExisting = nil then
    begin
      FCurrentScope.Declare(LDecl.Name, LDecl);
      Continue;
    end;

    // A real type declaration completes a forward type
    if (LDecl is TWklTypeDeclNode) and (LExisting is TWklForwardTypeNode) then
    begin
      FCurrentScope.Declare(LDecl.Name, LDecl);
      Continue;
    end;

    SemError(WKL_ERR_SEM_002, RSSemDuplicateDeclaration, [LDecl.Name], LDecl);
  end;
end;

// Register one routine, creating or extending an overload group when the
// name is already bound to a routine. Groups live in FModule.OverloadGroups.
procedure TWklSemantics.DoRegisterRoutine(const ARoutine: TWklRoutineDeclNode;
  const AExisting: TWklNode);
var
  LGroup: TWklOverloadGroupNode;
  LI: Integer;
begin
  if (AExisting = nil) or (AExisting is TWklForwardRoutineNode) then
  begin
    FCurrentScope.Declare(ARoutine.Name, ARoutine);
    Exit;
  end;

  if AExisting is TWklRoutineDeclNode then
  begin
    if DoParamSignaturesMatch(TWklRoutineDeclNode(AExisting), ARoutine) then
    begin
      SemError(WKL_ERR_SEM_002, RSSemDuplicateDeclaration,
        [ARoutine.Name], ARoutine);
      Exit;
    end;
    LGroup := TWklOverloadGroupNode.Create();
    LGroup.Name := ARoutine.Name;
    LGroup.Location := AExisting.Location;
    LGroup.Token := AExisting.Token;
    LGroup.Routines.Add(AExisting);
    LGroup.Routines.Add(ARoutine);
    FModule.OverloadGroups.Add(LGroup);
    FCurrentScope.Declare(ARoutine.Name, LGroup);
    Exit;
  end;

  if AExisting is TWklOverloadGroupNode then
  begin
    LGroup := TWklOverloadGroupNode(AExisting);
    for LI := 0 to LGroup.Routines.Count - 1 do
    begin
      if DoParamSignaturesMatch(TWklRoutineDeclNode(LGroup.Routines[LI]),
        ARoutine) then
      begin
        SemError(WKL_ERR_SEM_002, RSSemDuplicateDeclaration,
          [ARoutine.Name], ARoutine);
        Exit;
      end;
    end;
    LGroup.Routines.Add(ARoutine);
    Exit;
  end;

  SemError(WKL_ERR_SEM_002, RSSemDuplicateDeclaration, [ARoutine.Name], ARoutine);
end;

procedure TWklSemantics.DoRegisterImports();
var
  LI: Integer;
  LImport: TWklNode;
begin
  for LI := 0 to FModule.Imports.Count - 1 do
  begin
    LImport := FModule.Imports[LI];
    if LImport.Name = '' then
      Continue;
    if FCurrentScope.LookupLocal(LImport.Name) <> nil then
    begin
      SemError(WKL_ERR_SEM_002, RSSemDuplicateDeclaration,
        [LImport.Name], LImport);
      Continue;
    end;
    FCurrentScope.Declare(LImport.Name, LImport);
  end;
end;

procedure TWklSemantics.DoAnalyzeDeclarations();
var
  LI: Integer;
  LDecl: TWklNode;
begin
  for LI := 0 to FModule.Declarations.Count - 1 do
  begin
    LDecl := FModule.Declarations[LI];
    if LDecl is TWklConstDeclNode then
      DoAnalyzeConstDecl(TWklConstDeclNode(LDecl))
    else if LDecl is TWklTypeDeclNode then
      DoAnalyzeTypeDecl(TWklTypeDeclNode(LDecl))
    else if LDecl is TWklVarDeclNode then
      DoAnalyzeVarDecl(TWklVarDeclNode(LDecl), True)
    else if LDecl is TWklRoutineDeclNode then
      DoAnalyzeRoutineDecl(TWklRoutineDeclNode(LDecl))
    else if LDecl is TWklForwardTypeNode then
      DoAnalyzeForwardType(TWklForwardTypeNode(LDecl))
    else if LDecl is TWklForwardRoutineNode then
      DoAnalyzeForwardRoutine(TWklForwardRoutineNode(LDecl));
  end;
end;

procedure TWklSemantics.DoAnalyzeConstDecl(const ANode: TWklConstDeclNode);
begin
  if ANode.TypeExpr <> nil then
    DoAnalyzeExpr(ANode.TypeExpr);
  if ANode.ValueExpr <> nil then
  begin
    DoAnalyzeExpr(ANode.ValueExpr);
    if ANode.TypeExpr <> nil then
      DoPropagateLiteralType(ANode.ValueExpr, ANode.TypeExpr);
  end;

  // Anything but a plain non-string literal needs emitted init code at
  // module start. A string literal is included: a string is a heap object
  // (TStringRec), so it must be built by RT_StrFromLiteral at runtime.
  ANode.NeedsRuntimeInit := (ANode.ValueExpr <> nil) and
    ((not (ANode.ValueExpr is TWklLiteralNode)) or
     (TWklLiteralNode(ANode.ValueExpr).Kind = lkString));
end;

procedure TWklSemantics.DoAnalyzeTypeDecl(const ANode: TWklTypeDeclNode);
begin
  if ANode.TypeDef <> nil then
    DoAnalyzeTypeDef(ANode.TypeDef);
end;

procedure TWklSemantics.DoAnalyzeFieldList(const AFields: TWklNodeList);
var
  LI: Integer;
  LField: TWklNode;
begin
  if AFields = nil then
    Exit;
  for LI := 0 to AFields.Count - 1 do
  begin
    LField := AFields[LI];
    if LField is TWklFieldDeclNode then
    begin
      if TWklFieldDeclNode(LField).TypeExpr <> nil then
        DoAnalyzeExpr(TWklFieldDeclNode(LField).TypeExpr);
    end
    else
      // Nested anonymous record/overlay
      DoAnalyzeTypeDef(LField);
  end;
end;

procedure TWklSemantics.DoAnalyzeTypeDef(const ANode: TWklNode);
var
  LI: Integer;
  LValue: TWklChoicesValueNode;
  LNextOrdinal: Int64;
  LFolded: Int64;
begin
  if ANode = nil then
    Exit;

  if ANode is TWklRecordTypeNode then
  begin
    if TWklRecordTypeNode(ANode).BaseType <> nil then
      DoAnalyzeExpr(TWklRecordTypeNode(ANode).BaseType);
    DoAnalyzeFieldList(TWklRecordTypeNode(ANode).Fields);
  end
  else if ANode is TWklOverlayTypeNode then
    DoAnalyzeFieldList(TWklOverlayTypeNode(ANode).Fields)
  else if ANode is TWklAnonRecordNode then
    DoAnalyzeFieldList(TWklAnonRecordNode(ANode).Fields)
  else if ANode is TWklAnonOverlayNode then
    DoAnalyzeFieldList(TWklAnonOverlayNode(ANode).Fields)
  else if ANode is TWklArrayTypeNode then
  begin
    if TWklArrayTypeNode(ANode).ElementType <> nil then
      DoAnalyzeExpr(TWklArrayTypeNode(ANode).ElementType);
    if TWklArrayTypeNode(ANode).LowBound <> nil then
      DoAnalyzeExpr(TWklArrayTypeNode(ANode).LowBound);
    if TWklArrayTypeNode(ANode).HighBound <> nil then
      DoAnalyzeExpr(TWklArrayTypeNode(ANode).HighBound);
  end
  else if ANode is TWklPointerTypeNode then
  begin
    if TWklPointerTypeNode(ANode).TargetType <> nil then
      DoAnalyzeExpr(TWklPointerTypeNode(ANode).TargetType);
  end
  else if ANode is TWklSetTypeNode then
  begin
    if TWklSetTypeNode(ANode).ElementType <> nil then
      DoAnalyzeExpr(TWklSetTypeNode(ANode).ElementType);
    if TWklSetTypeNode(ANode).LowBound <> nil then
      DoAnalyzeExpr(TWklSetTypeNode(ANode).LowBound);
    if TWklSetTypeNode(ANode).HighBound <> nil then
      DoAnalyzeExpr(TWklSetTypeNode(ANode).HighBound);
  end
  else if ANode is TWklChoicesTypeNode then
  begin
    // Assign ordinals: explicit value when foldable, else previous + 1
    LNextOrdinal := 0;
    for LI := 0 to TWklChoicesTypeNode(ANode).Values.Count - 1 do
    begin
      LValue := TWklChoicesValueNode(TWklChoicesTypeNode(ANode).Values[LI]);
      if LValue.ExplicitValue <> nil then
      begin
        DoAnalyzeExpr(LValue.ExplicitValue);
        if DoFoldIntLiteral(LValue.ExplicitValue, LFolded) then
          LNextOrdinal := LFolded
        else
          SemError(WKL_ERR_SEM_008,
            'Choices value ''%s'' requires an integer literal',
            [LValue.Name], LValue);
      end;
      LValue.ResolvedOrdinal := LNextOrdinal;
      LValue.ResolvedType := FTypeInt32;
      Inc(LNextOrdinal);
    end;
  end
  else if ANode is TWklRoutineTypeNode then
  begin
    if TWklRoutineTypeNode(ANode).ReturnType <> nil then
    begin
      DoAnalyzeExpr(TWklRoutineTypeNode(ANode).ReturnType);
      if DoIsAggregateTypeDef(TWklRoutineTypeNode(ANode).ReturnType) then
      begin
        TWklRoutineTypeNode(ANode).IsSret := True;
        TWklRoutineTypeNode(ANode).SretByteSize :=
          DoComputeTypeSize(TWklRoutineTypeNode(ANode).ReturnType);
      end;
    end;
    for LI := 0 to TWklRoutineTypeNode(ANode).Params.Count - 1 do
    begin
      if TWklParamNode(TWklRoutineTypeNode(ANode).Params[LI]).TypeExpr <> nil then
        DoAnalyzeExpr(TWklParamNode(TWklRoutineTypeNode(ANode).Params[LI]).TypeExpr);
    end;
  end
  else if ANode is TWklTypeRefNode then
    DoAnalyzeTypeRef(TWklTypeRefNode(ANode));
end;

procedure TWklSemantics.DoAnalyzeVarDecl(const ANode: TWklVarDeclNode;
  const AIsGlobal: Boolean);
begin
  ANode.IsGlobal := AIsGlobal;

  if ANode.TypeExpr <> nil then
  begin
    DoAnalyzeExpr(ANode.TypeExpr);
    // Size anonymous array/record/overlay types now so the emitter can
    // read ByteSize off the type node instead of guessing
    DoComputeTypeSize(ANode.TypeExpr);
  end;

  if ANode.InitExpr <> nil then
  begin
    DoAnalyzeExpr(ANode.InitExpr);
    if ANode.TypeExpr <> nil then
      DoPropagateLiteralType(ANode.InitExpr, ANode.TypeExpr);
  end;

  if ANode.IsExternal then
  begin
    if ANode.ExternLib = '' then
      SemError(WKL_ERR_SEM_008, RSSemExtVarMissingLib, ANode);
    if ANode.ExternSymbol = '' then
      SemError(WKL_ERR_SEM_008, RSSemExtVarMissingName, ANode);
  end;
end;

procedure TWklSemantics.DoAnalyzeRoutineDecl(const ANode: TWklRoutineDeclNode);
var
  LI: Integer;
  LParam: TWklParamNode;
  LLocal: TWklNode;
begin
  PushScope(skRoutine);
  FCurrentRoutine := ANode;

  if ANode.ReturnType <> nil then
  begin
    DoAnalyzeExpr(ANode.ReturnType);
    if DoIsAggregateTypeDef(ANode.ReturnType) then
    begin
      ANode.IsSret := True;
      ANode.SretByteSize := DoComputeTypeSize(ANode.ReturnType);
    end;
  end;

  for LI := 0 to ANode.Params.Count - 1 do
  begin
    LParam := TWklParamNode(ANode.Params[LI]);
    if LParam.Name <> '' then
      FCurrentScope.Declare(LParam.Name, LParam);
    if LParam.TypeExpr <> nil then
      DoAnalyzeExpr(LParam.TypeExpr);
  end;

  // Local types, consts, vars are visible to each other and the body
  for LI := 0 to ANode.LocalTypes.Count - 1 do
  begin
    LLocal := ANode.LocalTypes[LI];
    if LLocal.Name <> '' then
      FCurrentScope.Declare(LLocal.Name, LLocal);
  end;
  for LI := 0 to ANode.LocalTypes.Count - 1 do
  begin
    LLocal := ANode.LocalTypes[LI];
    if LLocal is TWklTypeDeclNode then
      DoAnalyzeTypeDecl(TWklTypeDeclNode(LLocal));
  end;

  for LI := 0 to ANode.LocalConsts.Count - 1 do
  begin
    LLocal := ANode.LocalConsts[LI];
    if LLocal.Name <> '' then
      FCurrentScope.Declare(LLocal.Name, LLocal);
    if LLocal is TWklConstDeclNode then
      DoAnalyzeConstDecl(TWklConstDeclNode(LLocal));
  end;

  for LI := 0 to ANode.LocalVars.Count - 1 do
  begin
    LLocal := ANode.LocalVars[LI];
    if LLocal.Name <> '' then
      FCurrentScope.Declare(LLocal.Name, LLocal);
    if LLocal is TWklVarDeclNode then
      DoAnalyzeVarDecl(TWklVarDeclNode(LLocal), False);
  end;

  if ANode.IsExternal then
  begin
    if ANode.ExternLib = '' then
      SemError(WKL_ERR_SEM_008, RSSemExtRoutMissingLib, ANode);
    if ANode.ExternSymbol = '' then
      SemError(WKL_ERR_SEM_008, RSSemExtRoutMissingName, ANode);
  end
  else
    DoAnalyzeBlock(ANode.Body);

  FCurrentRoutine := nil;
  PopScope();
end;

procedure TWklSemantics.DoAnalyzeForwardType(const ANode: TWklForwardTypeNode);
var
  LResolved: TWklNode;
begin
  LResolved := FCurrentScope.Lookup(ANode.Name);
  if LResolved = nil then
  begin
    SemError(WKL_ERR_SEM_006, RSSemUnresolvedForwardType, [ANode.Name], ANode);
    Exit;
  end;
  if not (LResolved is TWklTypeDeclNode) then
  begin
    SemError(WKL_ERR_SEM_006, RSSemForwardTypeNotType, [ANode.Name], ANode);
    Exit;
  end;
  ANode.ResolvedDecl := LResolved;
end;

procedure TWklSemantics.DoAnalyzeForwardRoutine(
  const ANode: TWklForwardRoutineNode);
var
  LResolved: TWklNode;
  LI: Integer;
  LReason: string;
  LGroup: TWklOverloadGroupNode;
begin
  if ANode.ReturnType <> nil then
    DoAnalyzeExpr(ANode.ReturnType);
  for LI := 0 to ANode.Params.Count - 1 do
  begin
    if TWklParamNode(ANode.Params[LI]).TypeExpr <> nil then
      DoAnalyzeExpr(TWklParamNode(ANode.Params[LI]).TypeExpr);
  end;

  LResolved := FCurrentScope.Lookup(ANode.Name);
  if LResolved = nil then
  begin
    SemError(WKL_ERR_SEM_006, RSSemUnresolvedForwardRout, [ANode.Name], ANode);
    Exit;
  end;
  if not ((LResolved is TWklRoutineDeclNode) or
          (LResolved is TWklOverloadGroupNode)) then
  begin
    SemError(WKL_ERR_SEM_006, RSSemForwardRoutNotRout, [ANode.Name], ANode);
    Exit;
  end;
  ANode.ResolvedDecl := LResolved;

  // Forward/implementation parity: params, modes, types, return, variadic
  if LResolved is TWklRoutineDeclNode then
    LReason := DoForwardMismatchReason(ANode, TWklRoutineDeclNode(LResolved))
  else
  begin
    // Overload group: at least one member must match the forward exactly
    LReason := '';
    LGroup := TWklOverloadGroupNode(LResolved);
    for LI := 0 to LGroup.Routines.Count - 1 do
    begin
      LReason := DoForwardMismatchReason(ANode,
        TWklRoutineDeclNode(LGroup.Routines[LI]));
      if LReason = '' then
        Break;
    end;
  end;
  if LReason <> '' then
    SemError(WKL_ERR_SEM_012, RSSemForwardMismatch, [ANode.Name, LReason], ANode);
end;

// '' when AForward and AImpl agree on parameter count, modes, spelled types,
// return type and variadic-ness; otherwise a short description of the first
// difference. Types are compared by spelling because forwards are analyzed
// before the implementation's type refs are resolved.
function TWklSemantics.DoForwardMismatchReason(
  const AForward: TWklForwardRoutineNode;
  const AImpl: TWklRoutineDeclNode): string;
var
  LI: Integer;
  LParamA: TWklParamNode;
  LParamB: TWklParamNode;

  function TypeSpelling(const AType: TWklNode): string;
  begin
    if AType = nil then
      Result := ''
    else if AType is TWklTypeRefNode then
      Result := AType.Name
    else if AType is TWklPointerTypeNode then
      Result := 'ptr to ' + TypeSpelling(TWklPointerTypeNode(AType).TargetType)
    else
      // Other structural types are distinct objects per declaration; treat
      // as matching so a forward with an inline record/array type is not
      // rejected on identity alone
      Result := AType.ClassName;
  end;

begin
  Result := '';
  if AForward.Params.Count <> AImpl.Params.Count then
    Exit('parameter count');
  if AForward.IsVariadic <> AImpl.IsVariadic then
    Exit('variadic marker');
  for LI := 0 to AForward.Params.Count - 1 do
  begin
    LParamA := TWklParamNode(AForward.Params[LI]);
    LParamB := TWklParamNode(AImpl.Params[LI]);
    if LParamA.ParamMode <> LParamB.ParamMode then
      Exit('mode of parameter ' + IntToStr(LI + 1));
    if TypeSpelling(LParamA.TypeExpr) <> TypeSpelling(LParamB.TypeExpr) then
      Exit('type of parameter ' + IntToStr(LI + 1));
  end;
  if TypeSpelling(AForward.ReturnType) <> TypeSpelling(AImpl.ReturnType) then
    Exit('return type');
end;

procedure TWklSemantics.DoComputeTypeLayouts();
var
  LI: Integer;
  LDecl: TWklNode;
begin
  for LI := 0 to FModule.Declarations.Count - 1 do
  begin
    LDecl := FModule.Declarations[LI];
    if (LDecl is TWklTypeDeclNode) and
       (TWklTypeDeclNode(LDecl).TypeDef <> nil) and
       (TWklTypeDeclNode(LDecl).ByteSize = 0) then
      TWklTypeDeclNode(LDecl).ByteSize :=
        DoComputeTypeSize(TWklTypeDeclNode(LDecl).TypeDef);
    // Assign the runtime type tag alongside the layout
    if LDecl is TWklTypeDeclNode then
      DoTypeIdOf(LDecl);
  end;
end;

function TWklSemantics.DoPrimitiveSize(const AName: string): Int64;
begin
  if (AName = 'int8') or (AName = 'uint8') or (AName = 'bool') or
     (AName = 'char') then
    Result := 1
  else if (AName = 'int16') or (AName = 'uint16') or (AName = 'wchar') then
    Result := 2
  else if (AName = 'int32') or (AName = 'uint32') or (AName = 'float32') then
    Result := 4
  else
    // int64, uint64, float64, ptr, string, wstring, and anything unknown:
    // 8 bytes (i64 on memory64)
    Result := 8;
end;

// True when AExpr is an integer literal (optionally negated); AValue gets
// the folded value.
function TWklSemantics.DoFoldIntLiteral(const AExpr: TWklNode;
  out AValue: Int64): Boolean;
var
  LInner: Int64;
  LLeft: Int64;
  LRight: Int64;
  LBin: TWklBinaryExprNode;
begin
  AValue := 0;
  Result := False;
  if AExpr = nil then
    Exit;

  if (AExpr is TWklLiteralNode) and (TWklLiteralNode(AExpr).Kind = lkInt) then
  begin
    AValue := TWklLiteralNode(AExpr).IntValue;
    Exit(True);
  end;

  if (AExpr is TWklUnaryExprNode) and
     (TWklUnaryExprNode(AExpr).Op = uoNegate) then
  begin
    if DoFoldIntLiteral(TWklUnaryExprNode(AExpr).Operand, LInner) then
    begin
      AValue := -LInner;
      Exit(True);
    end;
  end;

  // Binary arithmetic on two foldable operands
  if AExpr is TWklBinaryExprNode then
  begin
    LBin := TWklBinaryExprNode(AExpr);
    if not DoFoldIntLiteral(LBin.Left, LLeft) then
      Exit;
    if not DoFoldIntLiteral(LBin.Right, LRight) then
      Exit;
    case LBin.Op of
      boAdd:    begin AValue := LLeft + LRight;   Exit(True); end;
      boSub:    begin AValue := LLeft - LRight;   Exit(True); end;
      boMul:    begin AValue := LLeft * LRight;   Exit(True); end;
      boIntDiv: begin if LRight = 0 then Exit; AValue := LLeft div LRight; Exit(True); end;
      boMod:    begin if LRight = 0 then Exit; AValue := LLeft mod LRight; Exit(True); end;
      boAnd:    begin AValue := LLeft and LRight; Exit(True); end;
      boOr:     begin AValue := LLeft or LRight;  Exit(True); end;
      boXor:    begin AValue := LLeft xor LRight; Exit(True); end;
      boShl:    begin AValue := LLeft shl LRight; Exit(True); end;
      boShr:    begin AValue := LLeft shr LRight; Exit(True); end;
    end;
    Exit;
  end;

  // Named constant with a literal value
  if (AExpr is TWklIdentifierNode) and
     (TWklIdentifierNode(AExpr).ResolvedDecl is TWklConstDeclNode) then
    Result := DoFoldIntLiteral(
      TWklConstDeclNode(TWklIdentifierNode(AExpr).ResolvedDecl).ValueExpr,
      AValue);
end;

function TWklSemantics.DoIsAggregateTypeDef(const AType: TWklNode): Boolean;
var
  LDef: TWklNode;
begin
  Result := False;
  if AType = nil then
    Exit;
  LDef := DoTypeDefOf(AType);
  if (LDef is TWklRecordTypeNode) or
    (LDef is TWklOverlayTypeNode) or
    (LDef is TWklAnonRecordNode) or
    (LDef is TWklAnonOverlayNode) or
    ((LDef is TWklArrayTypeNode) and (not TWklArrayTypeNode(LDef).IsDynamic)) then
    Result := True;
end;

function TWklSemantics.DoComputeTypeSize(const AType: TWklNode): Int64;
var
  LDef: TWklNode;
  LDecl: TWklNode;
  LArray: TWklArrayTypeNode;
  LLow: Int64;
  LHigh: Int64;
begin
  Result := 0;
  if AType = nil then
    Exit;

  // A named user type memoizes on its TypeDecl
  if AType is TWklTypeRefNode then
  begin
    LDecl := TWklTypeRefNode(AType).ResolvedDecl;
    if LDecl is TWklForwardTypeNode then
      LDecl := TWklForwardTypeNode(LDecl).ResolvedDecl;
    if LDecl is TWklTypeDeclNode then
    begin
      if TWklTypeDeclNode(LDecl).ByteSize = 0 then
        TWklTypeDeclNode(LDecl).ByteSize :=
          DoComputeTypeSize(TWklTypeDeclNode(LDecl).TypeDef);
      Exit(TWklTypeDeclNode(LDecl).ByteSize);
    end;
  end;

  LDef := DoTypeDefOf(AType);
  if LDef = nil then
    Exit(8);

  if LDef is TWklTypeRefNode then
    Result := DoPrimitiveSize(LDef.Name)
  else if LDef is TWklRecordTypeNode then
  begin
    if TWklRecordTypeNode(LDef).ByteSize = 0 then
      TWklRecordTypeNode(LDef).ByteSize := DoComputeRecordLayout(
        TWklRecordTypeNode(LDef).Fields, TWklRecordTypeNode(LDef).IsPacked,
        TWklRecordTypeNode(LDef).Alignment, TWklRecordTypeNode(LDef).BaseType);
    Result := TWklRecordTypeNode(LDef).ByteSize;
  end
  else if LDef is TWklAnonRecordNode then
  begin
    if TWklAnonRecordNode(LDef).ByteSize = 0 then
      TWklAnonRecordNode(LDef).ByteSize := DoComputeRecordLayout(
        TWklAnonRecordNode(LDef).Fields, TWklAnonRecordNode(LDef).IsPacked,
        0, nil);
    Result := TWklAnonRecordNode(LDef).ByteSize;
  end
  else if LDef is TWklOverlayTypeNode then
  begin
    if TWklOverlayTypeNode(LDef).ByteSize = 0 then
      TWklOverlayTypeNode(LDef).ByteSize :=
        DoComputeOverlayLayout(TWklOverlayTypeNode(LDef).Fields);
    Result := TWklOverlayTypeNode(LDef).ByteSize;
  end
  else if LDef is TWklAnonOverlayNode then
  begin
    if TWklAnonOverlayNode(LDef).ByteSize = 0 then
      TWklAnonOverlayNode(LDef).ByteSize :=
        DoComputeOverlayLayout(TWklAnonOverlayNode(LDef).Fields);
    Result := TWklAnonOverlayNode(LDef).ByteSize;
  end
  else if LDef is TWklArrayTypeNode then
  begin
    LArray := TWklArrayTypeNode(LDef);
    if LArray.ByteSize > 0 then
      Exit(LArray.ByteSize);
    if LArray.IsDynamic then
    begin
      LArray.ElementCount := 0;
      Result := 8;  // heap pointer
    end
    else
    begin
      LLow := 0;
      LHigh := 0;
      if LArray.LowBound <> nil then
      begin
        if not DoFoldIntLiteral(LArray.LowBound, LLow) then
          SemError(WKL_ERR_SEM_008,
            'Array low bound must be a constant integer expression',
            LArray.LowBound);
      end;
      if LArray.HighBound <> nil then
      begin
        if not DoFoldIntLiteral(LArray.HighBound, LHigh) then
          SemError(WKL_ERR_SEM_008,
            'Array high bound must be a constant integer expression',
            LArray.HighBound);
      end;
      LArray.ElementCount := LHigh - LLow + 1;
      if LArray.ElementCount < 0 then
        LArray.ElementCount := 0;
      Result := DoComputeTypeSize(LArray.ElementType) * LArray.ElementCount;
    end;
    LArray.ByteSize := Result;
  end
  else if LDef is TWklChoicesTypeNode then
    Result := 4   // i32 ordinal
  else
    // Pointer, set (i64 bitmask or heap pointer), routine type: 8 bytes
    Result := 8;
end;

// Record layout with natural alignment (capped at 8), optional packing,
// inheritance (fields start after the base type) and bit fields packed into
// storage units the size of their declared type. Writes ByteOffset/BitPos
// on every field and returns the total size.
function TWklSemantics.DoComputeRecordLayout(const AFields: TWklNodeList;
  const AIsPacked: Boolean; const AAlignment: Int64;
  const ABaseType: TWklNode): Int64;
var
  LI: Integer;
  LNode: TWklNode;
  LField: TWklFieldDeclNode;
  LOffset: Int64;
  LMaxAlign: Int64;
  LFieldSize: Int64;
  LFieldAlign: Int64;
  LBaseSize: Int64;
  LGroupSize: Int64;
  LBitStorageBits: Int64;
  LBitStorageOffset: Int64;
  LBitPos: Int64;
begin
  LOffset := 0;
  LMaxAlign := 1;

  if ABaseType <> nil then
  begin
    LBaseSize := DoComputeTypeSize(ABaseType);
    LOffset := LBaseSize;
    if LBaseSize > 0 then
    begin
      LFieldAlign := LBaseSize;
      if LFieldAlign > 8 then
        LFieldAlign := 8;
      if LFieldAlign > LMaxAlign then
        LMaxAlign := LFieldAlign;
    end;
  end;

  if AAlignment > LMaxAlign then
    LMaxAlign := AAlignment;

  LBitStorageBits := 0;
  LBitStorageOffset := 0;
  LBitPos := 0;

  if AFields <> nil then
  begin
    for LI := 0 to AFields.Count - 1 do
    begin
      LNode := AFields[LI];

      // Anonymous overlay: members share the current offset. Its layout is
      // computed at 0, then every field inside it (including fields of
      // anonymous records nested within it) is shifted here.
      if LNode is TWklAnonOverlayNode then
      begin
        if LBitStorageBits > 0 then
        begin
          LOffset := LBitStorageOffset + (LBitStorageBits div 8);
          LBitStorageBits := 0;
        end;
        LGroupSize := DoComputeOverlayLayout(TWklAnonOverlayNode(LNode).Fields);
        DoShiftFieldOffsets(TWklAnonOverlayNode(LNode).Fields, LOffset);
        LOffset := LOffset + LGroupSize;
        Continue;
      end;

      if not (LNode is TWklFieldDeclNode) then
        Continue;
      LField := TWklFieldDeclNode(LNode);

      LFieldSize := DoComputeTypeSize(LField.TypeExpr);
      LFieldAlign := LFieldSize;
      if LFieldAlign > 8 then
        LFieldAlign := 8;
      if LFieldAlign < 1 then
        LFieldAlign := 1;

      // Bit field
      if LField.BitWidth > 0 then
      begin
        // Open a new storage unit when none is open, the current one is a
        // different width, or the field does not fit in what remains
        if (LBitStorageBits = 0) or (LBitStorageBits <> LFieldSize * 8) or
           (LBitPos + LField.BitWidth > LBitStorageBits) then
        begin
          if LBitStorageBits > 0 then
            LOffset := LBitStorageOffset + (LBitStorageBits div 8);
          if (not AIsPacked) and ((LOffset mod LFieldAlign) <> 0) then
            LOffset := LOffset + LFieldAlign - (LOffset mod LFieldAlign);
          LBitStorageOffset := LOffset;
          LBitStorageBits := LFieldSize * 8;
          LBitPos := 0;
          if LFieldAlign > LMaxAlign then
            LMaxAlign := LFieldAlign;
        end;
        LField.ByteOffset := LBitStorageOffset;
        LField.BitPos := LBitPos;
        LBitPos := LBitPos + LField.BitWidth;
        Continue;
      end;

      // Close any open bit storage before a normal field
      if LBitStorageBits > 0 then
      begin
        LOffset := LBitStorageOffset + (LBitStorageBits div 8);
        LBitStorageBits := 0;
        LBitPos := 0;
      end;

      if (not AIsPacked) and ((LOffset mod LFieldAlign) <> 0) then
        LOffset := LOffset + LFieldAlign - (LOffset mod LFieldAlign);

      LField.ByteOffset := LOffset;
      LField.BitPos := 0;
      LOffset := LOffset + LFieldSize;
      if LFieldAlign > LMaxAlign then
        LMaxAlign := LFieldAlign;
    end;
  end;

  if LBitStorageBits > 0 then
    LOffset := LBitStorageOffset + (LBitStorageBits div 8);

  // Pad total size to the largest alignment
  if (not AIsPacked) and (LMaxAlign > 1) and ((LOffset mod LMaxAlign) <> 0) then
    LOffset := LOffset + LMaxAlign - (LOffset mod LMaxAlign);

  Result := LOffset;
end;

// Overlay (union) layout: every member at offset 0, size = largest member.
function TWklSemantics.DoComputeOverlayLayout(const AFields: TWklNodeList): Int64;
var
  LI: Integer;
  LNode: TWklNode;
  LSize: Int64;
begin
  Result := 0;
  if AFields = nil then
    Exit;

  for LI := 0 to AFields.Count - 1 do
  begin
    LNode := AFields[LI];
    if LNode is TWklFieldDeclNode then
    begin
      TWklFieldDeclNode(LNode).ByteOffset := 0;
      TWklFieldDeclNode(LNode).BitPos := 0;
      LSize := DoComputeTypeSize(TWklFieldDeclNode(LNode).TypeExpr);
    end
    else
      LSize := DoComputeTypeSize(LNode);  // anonymous record inside overlay

    if LSize > Result then
      Result := LSize;
  end;
end;

// Add ADelta to the ByteOffset of every field in AFields, descending into
// anonymous records and overlays. Used after a nested group has been laid
// out at 0 to place it at its real position in the enclosing record.
procedure TWklSemantics.DoShiftFieldOffsets(const AFields: TWklNodeList;
  const ADelta: Int64);
var
  LI: Integer;
  LNode: TWklNode;
begin
  if (AFields = nil) or (ADelta = 0) then
    Exit;

  for LI := 0 to AFields.Count - 1 do
  begin
    LNode := AFields[LI];
    if LNode is TWklFieldDeclNode then
      TWklFieldDeclNode(LNode).ByteOffset :=
        TWklFieldDeclNode(LNode).ByteOffset + ADelta
    else if LNode is TWklAnonRecordNode then
      DoShiftFieldOffsets(TWklAnonRecordNode(LNode).Fields, ADelta)
    else if LNode is TWklAnonOverlayNode then
      DoShiftFieldOffsets(TWklAnonOverlayNode(LNode).Fields, ADelta);
  end;
end;

procedure TWklSemantics.DoAnalyzeStatementList(const AList: TWklNodeList);
var
  LI: Integer;
begin
  if AList = nil then
    Exit;
  for LI := 0 to AList.Count - 1 do
    DoAnalyzeStatement(AList[LI]);
end;

procedure TWklSemantics.DoAnalyzeBlock(const ABlock: TWklBlockNode);
begin
  if ABlock = nil then
    Exit;
  DoAnalyzeStatementList(ABlock.Statements);
end;

procedure TWklSemantics.DoAnalyzeArgList(const AArgs: TWklNodeList);
var
  LI: Integer;
begin
  if AArgs = nil then
    Exit;
  for LI := 0 to AArgs.Count - 1 do
    DoAnalyzeExpr(AArgs[LI]);
end;

// A bare numeric/bool/nil literal takes the type of its target so the
// emitter picks the right wasm constant (i64.const for an int64 target).
procedure TWklSemantics.DoPropagateLiteralType(const AExpr: TWklNode;
  const AType: TWklNode);
begin
  if (AType <> nil) and DoIsLiteralExpr(AExpr) then
    AExpr.ResolvedType := AType;
end;

procedure TWklSemantics.DoAnalyzeStatement(const ANode: TWklNode);
begin
  if ANode = nil then
    Exit;

  if ANode is TWklAssignNode then
    DoAnalyzeAssign(TWklAssignNode(ANode))
  else if ANode is TWklCallStmtNode then
    DoAnalyzeExpr(TWklCallStmtNode(ANode).CallExpr)
  else if ANode is TWklIfNode then
    DoAnalyzeIf(TWklIfNode(ANode))
  else if ANode is TWklWhileNode then
    DoAnalyzeWhile(TWklWhileNode(ANode))
  else if ANode is TWklForNode then
    DoAnalyzeFor(TWklForNode(ANode))
  else if ANode is TWklRepeatNode then
    DoAnalyzeRepeat(TWklRepeatNode(ANode))
  else if (ANode is TWklBreakNode) or (ANode is TWklContinueNode) then
  begin
    if FLoopDepth <= 0 then
      SemError(WKL_ERR_SEM_004, RSSemBreakOutsideLoop, ANode);
  end
  else if ANode is TWklMatchNode then
    DoAnalyzeMatch(TWklMatchNode(ANode))
  else if ANode is TWklReturnNode then
    DoAnalyzeReturn(TWklReturnNode(ANode))
  else if ANode is TWklGuardNode then
    DoAnalyzeGuard(TWklGuardNode(ANode))
  else if ANode is TWklThrowNode then
    DoAnalyzeExpr(TWklThrowNode(ANode).CodeExpr)
  else if ANode is TWklThrowCodeNode then
  begin
    DoAnalyzeExpr(TWklThrowCodeNode(ANode).CodeExpr);
    DoAnalyzeExpr(TWklThrowCodeNode(ANode).MsgExpr);
  end
  else if ANode is TWklPrintNode then
    DoAnalyzeArgList(TWklPrintNode(ANode).Args)
  else if ANode is TWklAssertNode then
    DoAnalyzeArgList(TWklAssertNode(ANode).Args)
  else if ANode is TWklMemOpNode then
    DoAnalyzeMemOp(TWklMemOpNode(ANode))
  else if ANode is TWklMemOp2Node then
    DoAnalyzeMemOp2(TWklMemOp2Node(ANode))
  else if ANode is TWklBlockNode then
    DoAnalyzeBlock(TWklBlockNode(ANode))
  else if ANode is TWklVarDeclNode then
  begin
    // Inline var declaration in statement position
    if ANode.Name <> '' then
      FCurrentScope.Declare(ANode.Name, ANode);
    DoAnalyzeVarDecl(TWklVarDeclNode(ANode), FCurrentScope.ScopeKind = skModule);
  end;
end;

procedure TWklSemantics.DoAnalyzeAssign(const ANode: TWklAssignNode);
var
  LValueDef: TWklNode;
  LWrapper: TWklIntrinsicNode;
  LValue: TWklNode;
begin
  DoAnalyzeExpr(ANode.Target);
  if ANode.Value <> nil then
  begin
    DoAnalyzeExpr(ANode.Value);
    if ANode.Target <> nil then
      DoPropagateLiteralType(ANode.Value, ANode.Target.ResolvedType);
  end;

  // Implicit ptr to char -> string (Delphi PAnsiChar -> string). The value
  // is wrapped in a synthetic ikCStrToStr intrinsic so the emitter copies
  // the C string into a fresh managed string; the source buffer is untouched
  if (ANode.Target = nil) or (ANode.Value = nil) then
    Exit;
  if DoPrimitiveNameOf(ANode.Target.ResolvedType) <> 'string' then
    Exit;
  LValueDef := DoTypeDefOf(ANode.Value.ResolvedType);
  if not (LValueDef is TWklPointerTypeNode) then
    Exit;
  if DoPrimitiveNameOf(TWklPointerTypeNode(LValueDef).TargetType) <> 'char' then
    Exit;

  LValue := ANode.Value;
  LWrapper := TWklIntrinsicNode.Create();
  LWrapper.Kind := ikCStrToStr;
  LWrapper.Location := LValue.Location;
  LWrapper.Token := -1;
  LWrapper.ResolvedType := FTypeString;
  LWrapper.Args.Add(LValue);
  ANode.Value := LWrapper;
end;

procedure TWklSemantics.DoAnalyzeIf(const ANode: TWklIfNode);
begin
  DoAnalyzeExpr(ANode.Condition);
  DoAnalyzeStatementList(ANode.ThenBody);
  DoAnalyzeStatementList(ANode.ElseBody);
end;

procedure TWklSemantics.DoAnalyzeWhile(const ANode: TWklWhileNode);
begin
  DoAnalyzeExpr(ANode.Condition);
  Inc(FLoopDepth);
  DoAnalyzeStatementList(ANode.Body);
  Dec(FLoopDepth);
end;

procedure TWklSemantics.DoAnalyzeFor(const ANode: TWklForNode);
begin
  // Bounds are evaluated outside the iterator's scope
  DoAnalyzeExpr(ANode.StartExpr);
  DoAnalyzeExpr(ANode.EndExpr);

  // The for node itself is the iterator's declaration; its type is the
  // start expression's type (see DoTypeOfDecl)
  PushScope(skBlock);
  if ANode.Name <> '' then
    FCurrentScope.Declare(ANode.Name, ANode);
  if ANode.StartExpr <> nil then
    ANode.ResolvedType := ANode.StartExpr.ResolvedType;

  Inc(FLoopDepth);
  DoAnalyzeStatementList(ANode.Body);
  Dec(FLoopDepth);

  PopScope();
end;

procedure TWklSemantics.DoAnalyzeRepeat(const ANode: TWklRepeatNode);
begin
  Inc(FLoopDepth);
  DoAnalyzeStatementList(ANode.Body);
  Dec(FLoopDepth);
  DoAnalyzeExpr(ANode.UntilCondition);
end;

procedure TWklSemantics.DoAnalyzeMatch(const ANode: TWklMatchNode);
var
  LI: Integer;
  LJ: Integer;
  LArm: TWklMatchArmNode;
  LLabel: TWklMatchLabelNode;
  LScrutineeType: TWklNode;
begin
  DoAnalyzeExpr(ANode.Scrutinee);
  LScrutineeType := nil;
  if ANode.Scrutinee <> nil then
    LScrutineeType := ANode.Scrutinee.ResolvedType;

  for LI := 0 to ANode.Arms.Count - 1 do
  begin
    LArm := TWklMatchArmNode(ANode.Arms[LI]);
    for LJ := 0 to LArm.Labels.Count - 1 do
    begin
      LLabel := TWklMatchLabelNode(LArm.Labels[LJ]);
      DoAnalyzeExpr(LLabel.ValueExpr);
      DoPropagateLiteralType(LLabel.ValueExpr, LScrutineeType);
      if LLabel.RangeEnd <> nil then
      begin
        DoAnalyzeExpr(LLabel.RangeEnd);
        DoPropagateLiteralType(LLabel.RangeEnd, LScrutineeType);
      end;
    end;
    DoAnalyzeStatementList(LArm.Body);
  end;

  DoAnalyzeStatementList(ANode.ElseBody);
end;

procedure TWklSemantics.DoAnalyzeReturn(const ANode: TWklReturnNode);
begin
  if ANode.ValueExpr = nil then
    Exit;
  DoAnalyzeExpr(ANode.ValueExpr);
  if FCurrentRoutine <> nil then
    DoPropagateLiteralType(ANode.ValueExpr, FCurrentRoutine.ReturnType);
end;

procedure TWklSemantics.DoAnalyzeGuard(const ANode: TWklGuardNode);
begin
  DoAnalyzeBlock(ANode.GuardBody);
  DoAnalyzeBlock(ANode.ExceptBody);
  DoAnalyzeBlock(ANode.FinallyBody);
end;

procedure TWklSemantics.DoAnalyzeMemOp(const ANode: TWklMemOpNode);
var
  LDef: TWklNode;
begin
  if ANode.ArgExpr = nil then
    Exit;
  DoAnalyzeExpr(ANode.ArgExpr);

  // new() needs a typed pointer so the emitter knows how much to allocate
  if ANode.Kind = moNew then
  begin
    LDef := DoTypeDefOf(ANode.ArgExpr.ResolvedType);
    if LDef = nil then
      SemError(WKL_ERR_SEM_003, 'new() requires a typed ptr argument', ANode)
    else if not (LDef is TWklPointerTypeNode) then
      SemError(WKL_ERR_SEM_003, 'new() requires a ptr argument', ANode)
    else if TWklPointerTypeNode(LDef).TargetType = nil then
      SemError(WKL_ERR_SEM_003,
        'new() requires a typed ptr, not an untyped ptr', ANode);
  end;
end;

procedure TWklSemantics.DoAnalyzeMemOp2(const ANode: TWklMemOp2Node);
begin
  DoAnalyzeExpr(ANode.FirstArg);
  DoAnalyzeExpr(ANode.SecondArg);
end;

procedure TWklSemantics.DoAnalyzeExpr(const ANode: TWklNode);
var
  LI: Integer;
begin
  if ANode = nil then
    Exit;

  if ANode is TWklLiteralNode then
    DoAnalyzeLiteral(TWklLiteralNode(ANode))
  else if ANode is TWklIdentifierNode then
    DoAnalyzeIdentifier(TWklIdentifierNode(ANode))
  else if ANode is TWklDotAccessNode then
    DoAnalyzeDotAccess(TWklDotAccessNode(ANode))
  else if ANode is TWklIndexAccessNode then
    DoAnalyzeIndexAccess(TWklIndexAccessNode(ANode))
  else if ANode is TWklDerefNode then
    DoAnalyzeDeref(TWklDerefNode(ANode))
  else if ANode is TWklCallExprNode then
    DoAnalyzeCallExpr(TWklCallExprNode(ANode))
  else if ANode is TWklBinaryExprNode then
    DoAnalyzeBinaryExpr(TWklBinaryExprNode(ANode))
  else if ANode is TWklUnaryExprNode then
    DoAnalyzeUnaryExpr(TWklUnaryExprNode(ANode))
  else if ANode is TWklTypeCastNode then
    DoAnalyzeTypeCast(TWklTypeCastNode(ANode))
  else if ANode is TWklIntrinsicNode then
    DoAnalyzeIntrinsic(TWklIntrinsicNode(ANode))
  else if ANode is TWklTypeRefNode then
    DoAnalyzeTypeRef(TWklTypeRefNode(ANode))
  else if ANode is TWklSetLiteralNode then
    DoAnalyzeSetLiteral(TWklSetLiteralNode(ANode))
  else if ANode is TWklSetElementNode then
  begin
    DoAnalyzeExpr(TWklSetElementNode(ANode).ValueExpr);
    DoAnalyzeExpr(TWklSetElementNode(ANode).RangeEnd);
  end
  else if ANode is TWklRecordLiteralNode then
    DoAnalyzeRecordLiteral(TWklRecordLiteralNode(ANode))
  else if ANode is TWklFieldInitNode then
    DoAnalyzeExpr(TWklFieldInitNode(ANode).ValueExpr)
  else if (ANode is TWklRecordTypeNode) or (ANode is TWklOverlayTypeNode) or
          (ANode is TWklAnonRecordNode) or (ANode is TWklAnonOverlayNode) or
          (ANode is TWklArrayTypeNode) or (ANode is TWklPointerTypeNode) or
          (ANode is TWklSetTypeNode) or (ANode is TWklChoicesTypeNode) or
          (ANode is TWklRoutineTypeNode) then
    // Inline structural type in expression position (e.g. var x: ptr int32)
    DoAnalyzeTypeDef(ANode)
  else if ANode is TWklOverloadGroupNode then
  begin
    for LI := 0 to TWklOverloadGroupNode(ANode).Routines.Count - 1 do
      DoAnalyzeExpr(TWklOverloadGroupNode(ANode).Routines[LI]);
  end;
end;

procedure TWklSemantics.DoAnalyzeLiteral(const ANode: TWklLiteralNode);
begin
  case ANode.Kind of
    lkInt:     ANode.ResolvedType := FTypeInt32;
    lkString:  ANode.ResolvedType := FTypeString;
    lkWString: ANode.ResolvedType := FTypeWString;
    lkBool:    ANode.ResolvedType := FTypeBoolean;
    lkNil:     ANode.ResolvedType := FTypePointer;
    lkFloat:
    begin
      if ANode.IsFloat32 then
        ANode.ResolvedType := FTypeFloat32
      else
        ANode.ResolvedType := FTypeFloat64;
    end;
  end;
end;

procedure TWklSemantics.DoAnalyzeIdentifier(const ANode: TWklIdentifierNode);
var
  LResolved: TWklNode;
begin
  if ANode.Name = '' then
    Exit;

  LResolved := FCurrentScope.Lookup(ANode.Name);
  if LResolved = nil then
  begin
    // A primitive type name used as a value (e.g. in a cast or size())
    LResolved := DoFindPrimitive(ANode.Name);
    if LResolved = nil then
    begin
      SemError(WKL_ERR_SEM_001, RSSemUndeclaredIdentifier, [ANode.Name], ANode);
      Exit;
    end;
  end;

  // Follow a completed forward to the real declaration
  if (LResolved is TWklForwardTypeNode) and
     (TWklForwardTypeNode(LResolved).ResolvedDecl <> nil) then
    LResolved := TWklForwardTypeNode(LResolved).ResolvedDecl
  else if (LResolved is TWklForwardRoutineNode) and
          (TWklForwardRoutineNode(LResolved).ResolvedDecl <> nil) then
    LResolved := TWklForwardRoutineNode(LResolved).ResolvedDecl;

  ANode.ResolvedDecl := LResolved;
  ANode.ResolvedType := DoTypeOfDecl(LResolved);
end;

procedure TWklSemantics.DoAnalyzeTypeRef(const ANode: TWklTypeRefNode);
var
  LResolved: TWklNode;
  LImport: TWklNode;
begin
  if ANode.Name = '' then
    Exit;

  // Qualified Module.Type: the module must be an import in scope and the
  // type a public member of that unit; resolution then continues exactly as
  // for a local type declaration
  if ANode.ModuleName <> '' then
  begin
    LImport := FCurrentScope.Lookup(ANode.ModuleName);
    if not (LImport is TWklImportNode) then
    begin
      SemError(WKL_ERR_SEM_001, RSSemUndeclaredType,
        [ANode.ModuleName + '.' + ANode.Name], ANode);
      Exit;
    end;
    LResolved := DoFindModuleMember(TWklImportNode(LImport).ResolvedModule,
      ANode.Name);
  end
  else
  begin
    // Primitive keyword: point at the owned sentinel
    LResolved := DoFindPrimitive(ANode.Name);
    if LResolved = nil then
      LResolved := FCurrentScope.Lookup(ANode.Name);
  end;

  if LResolved = nil then
  begin
    SemError(WKL_ERR_SEM_001, RSSemUndeclaredType, [ANode.Name], ANode);
    Exit;
  end;

  if (LResolved is TWklForwardTypeNode) and
     (TWklForwardTypeNode(LResolved).ResolvedDecl <> nil) then
    LResolved := TWklForwardTypeNode(LResolved).ResolvedDecl;

  if not ((LResolved is TWklTypeDeclNode) or (LResolved is TWklTypeRefNode) or
          (LResolved is TWklForwardTypeNode)) then
  begin
    SemError(WKL_ERR_SEM_001, RSSemUndeclaredType, [ANode.Name], ANode);
    Exit;
  end;

  ANode.ResolvedDecl := LResolved;
  ANode.ResolvedType := ANode;
end;

// Member access. Three shapes:
//   Import.member    -> dakModule, member found in the imported module
//   ChoicesType.name -> dakChoices, ordinal value
//   value.field      -> dakField, resolved through BaseExpr's type; this
//                       covers plain vars, params, a.b.c, p^.x and a[i].x
procedure TWklSemantics.DoAnalyzeDotAccess(const ANode: TWklDotAccessNode);
var
  LBaseDecl: TWklNode;
  LDef: TWklNode;
  LMember: TWklNode;
  LField: TWklFieldDeclNode;
begin
  ANode.AccessKind := dakUnresolved;
  ANode.ResolvedDecl := nil;

  DoAnalyzeExpr(ANode.BaseExpr);
  if (ANode.Name = '') or (ANode.BaseExpr = nil) then
    Exit;

  LBaseDecl := nil;
  if ANode.BaseExpr is TWklIdentifierNode then
    LBaseDecl := TWklIdentifierNode(ANode.BaseExpr).ResolvedDecl;

  // Import.member
  if LBaseDecl is TWklImportNode then
  begin
    ANode.AccessKind := dakModule;
    LMember := DoFindModuleMember(TWklImportNode(LBaseDecl).ResolvedModule,
      ANode.Name);
    if LMember = nil then
    begin
      SemError(WKL_ERR_SEM_010, '''%s'' not found in imported unit',
        [ANode.Name], ANode);
      Exit;
    end;
    ANode.ResolvedDecl := LMember;
    ANode.ResolvedType := DoTypeOfDecl(LMember);
    Exit;
  end;

  // ChoicesType.name
  if LBaseDecl is TWklTypeDeclNode then
  begin
    LDef := DoTypeDefOf(LBaseDecl);
    if LDef is TWklChoicesTypeNode then
    begin
      ANode.AccessKind := dakChoices;
      LMember := DoFindChoicesValue(TWklChoicesTypeNode(LDef), ANode.Name);
      if LMember = nil then
      begin
        SemError(WKL_ERR_SEM_010, RSSemChoicesNoMember, [ANode.Name], ANode);
        Exit;
      end;
      ANode.ResolvedDecl := LMember;
      ANode.ResolvedType := LBaseDecl;
      Exit;
    end;
  end;

  // value.field
  ANode.AccessKind := dakField;
  LDef := DoTypeDefOf(ANode.BaseExpr.ResolvedType);
  LField := DoFindField(LDef, ANode.Name);
  if LField = nil then
  begin
    SemError(WKL_ERR_SEM_010, RSSemNoFieldFound, [ANode.Name], ANode);
    Exit;
  end;
  ANode.ResolvedDecl := LField;
  ANode.ResolvedType := LField.TypeExpr;
end;

procedure TWklSemantics.DoAnalyzeIndexAccess(const ANode: TWklIndexAccessNode);
var
  LDef: TWklNode;
begin
  DoAnalyzeExpr(ANode.BaseExpr);
  DoAnalyzeExpr(ANode.IndexExpr);
  if ANode.BaseExpr = nil then
    Exit;

  LDef := DoTypeDefOf(ANode.BaseExpr.ResolvedType);
  if LDef is TWklArrayTypeNode then
    ANode.ResolvedType := TWklArrayTypeNode(LDef).ElementType
  else if (LDef is TWklTypeRefNode) and
          ((LDef.Name = 'string') or (LDef.Name = 'wstring')) then
  begin
    // Indexing a string yields a character
    if LDef.Name = 'string' then
      ANode.ResolvedType := DoFindPrimitive('char')
    else
      ANode.ResolvedType := DoFindPrimitive('wchar');
  end;
end;

procedure TWklSemantics.DoAnalyzeDeref(const ANode: TWklDerefNode);
var
  LDef: TWklNode;
begin
  DoAnalyzeExpr(ANode.BaseExpr);
  if ANode.BaseExpr = nil then
    Exit;

  LDef := DoTypeDefOf(ANode.BaseExpr.ResolvedType);
  if LDef is TWklPointerTypeNode then
    ANode.ResolvedType := TWklPointerTypeNode(LDef).TargetType;
end;

procedure TWklSemantics.DoAnalyzeCallExpr(const ANode: TWklCallExprNode);
var
  LCalleeDecl: TWklNode;
  LRoutine: TWklRoutineDeclNode;
  LI: Integer;
  LParamType: TWklNode;
  LDef: TWklNode;
begin
  ANode.ResolvedRoutine := nil;
  ANode.ResolvedRoutineType := nil;

  DoAnalyzeExpr(ANode.Callee);
  DoAnalyzeArgList(ANode.Args);
  if ANode.Callee = nil then
    Exit;

  LCalleeDecl := nil;
  if ANode.Callee is TWklIdentifierNode then
    LCalleeDecl := TWklIdentifierNode(ANode.Callee).ResolvedDecl
  else if ANode.Callee is TWklDotAccessNode then
    LCalleeDecl := TWklDotAccessNode(ANode.Callee).ResolvedDecl;
  if LCalleeDecl = nil then
    Exit;

  LRoutine := nil;
  if LCalleeDecl is TWklRoutineDeclNode then
    LRoutine := TWklRoutineDeclNode(LCalleeDecl)
  else if LCalleeDecl is TWklOverloadGroupNode then
  begin
    LRoutine := DoResolveOverload(TWklOverloadGroupNode(LCalleeDecl), ANode.Args);
    if LRoutine = nil then
    begin
      SemError(WKL_ERR_SEM_011, RSSemNoMatchingOverload,
        [ANode.Callee.Name], ANode);
      Exit;
    end;
  end;

  if LRoutine = nil then
  begin
    // Calling through a routine-typed value: signature comes from the type
    LDef := DoTypeDefOf(ANode.Callee.ResolvedType);
    if LDef is TWklRoutineTypeNode then
    begin
      ANode.ResolvedRoutineType := TWklRoutineTypeNode(LDef);
      ANode.ResolvedType := TWklRoutineTypeNode(LDef).ReturnType;
      if TWklRoutineTypeNode(LDef).IsVariadic then
      begin
        if ANode.Args.Count < TWklRoutineTypeNode(LDef).Params.Count then
          SemError(WKL_ERR_SEM_009, RSSemArgCountAtLeast,
            [ANode.Callee.Name, TWklRoutineTypeNode(LDef).Params.Count,
             ANode.Args.Count], ANode);
        for LI := TWklRoutineTypeNode(LDef).Params.Count to ANode.Args.Count - 1 do
        begin
          DoWidenPackedIntLiteral(ANode.Args[LI]);
          DoTypeIdOf(ANode.Args[LI].ResolvedType);
        end;
      end
      else if ANode.Args.Count <> TWklRoutineTypeNode(LDef).Params.Count then
        SemError(WKL_ERR_SEM_009, RSSemArgCountMismatch,
          [ANode.Callee.Name, TWklRoutineTypeNode(LDef).Params.Count,
           ANode.Args.Count], ANode);
    end;
    Exit;
  end;

  ANode.ResolvedRoutine := LRoutine;
  ANode.ResolvedType := LRoutine.ReturnType;

  // Arity: exact for fixed routines, at-least for variadic ones
  if LRoutine.IsVariadic then
  begin
    if ANode.Args.Count < LRoutine.Params.Count then
      SemError(WKL_ERR_SEM_009, RSSemArgCountAtLeast,
        [LRoutine.Name, LRoutine.Params.Count, ANode.Args.Count], ANode);
    // Materialize the runtime tag of every packed (extra) argument. A bare
    // int literal that does not fit int32 packs as int64 so the callee can
    // read it back with varargs.next(int64).
    for LI := LRoutine.Params.Count to ANode.Args.Count - 1 do
    begin
      DoWidenPackedIntLiteral(ANode.Args[LI]);
      DoTypeIdOf(ANode.Args[LI].ResolvedType);
    end;
  end
  else if ANode.Args.Count <> LRoutine.Params.Count then
    SemError(WKL_ERR_SEM_009, RSSemArgCountMismatch,
      [LRoutine.Name, LRoutine.Params.Count, ANode.Args.Count], ANode);

  // Wrap string args bound to "ptr char" params before literal typing,
  // otherwise the literal would take the pointer type and never be seen
  // as a string
  DoCoerceStringArgs(ANode, LRoutine);

  // Literal args take their parameter's type
  for LI := 0 to ANode.Args.Count - 1 do
  begin
    if LI >= LRoutine.Params.Count then
      Break;
    LParamType := TWklParamNode(LRoutine.Params[LI]).TypeExpr;
    DoPropagateLiteralType(ANode.Args[LI], LParamType);
  end;
end;

// A string argument passed to a "ptr char" parameter is wrapped in an
// implicit cstr() intrinsic. The wrapper takes the argument's place in Args
// and owns it.
procedure TWklSemantics.DoCoerceStringArgs(const ANode: TWklCallExprNode;
  const ARoutine: TWklRoutineDeclNode);
var
  LI: Integer;
  LParamDef: TWklNode;
  LArg: TWklNode;
  LWrapper: TWklIntrinsicNode;
begin
  for LI := 0 to ANode.Args.Count - 1 do
  begin
    if LI >= ARoutine.Params.Count then
      Break;

    LParamDef := DoTypeDefOf(TWklParamNode(ARoutine.Params[LI]).TypeExpr);
    if not (LParamDef is TWklPointerTypeNode) then
      Continue;
    if DoPrimitiveNameOf(TWklPointerTypeNode(LParamDef).TargetType) <> 'char' then
      Continue;

    LArg := ANode.Args[LI];
    if DoPrimitiveNameOf(LArg.ResolvedType) <> 'string' then
      Continue;

    LWrapper := TWklIntrinsicNode.Create();
    LWrapper.Kind := ikCStr;
    LWrapper.Location := LArg.Location;
    LWrapper.Token := -1;
    LWrapper.ResolvedType := FTypePointer;

    // Move ownership of the arg into the wrapper, then put the wrapper
    // where the arg was
    ANode.Args.Extract(LArg);
    LWrapper.Args.Add(LArg);
    ANode.Args.Insert(LI, LWrapper);
  end;
end;

procedure TWklSemantics.DoAnalyzeBinaryExpr(const ANode: TWklBinaryExprNode);
begin
  DoAnalyzeExpr(ANode.Left);
  DoAnalyzeExpr(ANode.Right);

  // A literal operand adopts the other side's type (x + 1 with x: int64)
  if (ANode.Left <> nil) and (ANode.Right <> nil) then
  begin
    if DoIsLiteralExpr(ANode.Right) and (not DoIsLiteralExpr(ANode.Left)) then
      DoPropagateLiteralType(ANode.Right, ANode.Left.ResolvedType)
    else if DoIsLiteralExpr(ANode.Left) and (not DoIsLiteralExpr(ANode.Right)) then
      DoPropagateLiteralType(ANode.Left, ANode.Right.ResolvedType);
  end;

  if ANode.Op in [boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq,
     boIn, boLogicalAnd, boLogicalOr] then
    ANode.ResolvedType := FTypeBoolean
  else if ANode.Left <> nil then
    ANode.ResolvedType := ANode.Left.ResolvedType;
end;

procedure TWklSemantics.DoAnalyzeUnaryExpr(const ANode: TWklUnaryExprNode);
begin
  DoAnalyzeExpr(ANode.Operand);
  case ANode.Op of
    uoNot:       ANode.ResolvedType := FTypeBoolean;
    uoAddressOf:
    begin
      ANode.ResolvedType := FTypePointer;
      // Mark the target variable as address-taken so the emitter
      // homes it in linear memory (scalars have no address otherwise)
      if (ANode.Operand is TWklIdentifierNode) and
        (TWklIdentifierNode(ANode.Operand).ResolvedDecl is TWklVarDeclNode) then
        TWklVarDeclNode(TWklIdentifierNode(ANode.Operand).ResolvedDecl).IsAddressTaken := True;
    end;
  else
    if ANode.Operand <> nil then
      ANode.ResolvedType := ANode.Operand.ResolvedType;
  end;
end;

procedure TWklSemantics.DoAnalyzeTypeCast(const ANode: TWklTypeCastNode);
begin
  DoAnalyzeExpr(ANode.TargetType);
  DoAnalyzeExpr(ANode.Expr);
  ANode.ResolvedType := ANode.TargetType;
end;

procedure TWklSemantics.DoAnalyzeIntrinsic(const ANode: TWklIntrinsicNode);
begin
  DoAnalyzeArgList(ANode.Args);
  // format() is decomposed at compile time, so the format string must be a
  // literal. Enforce it here so the emitter's precondition is an AST fact.
  if ANode.Kind = ikFormat then
  begin
    if (ANode.Args = nil) or (ANode.Args.Count < 1) or
      (not (ANode.Args[0] is TWklLiteralNode)) or
      (TWklLiteralNode(ANode.Args[0]).Kind <> lkString) then
      SemError(WKL_ERR_SEM_003, 'format() requires a string literal format string', ANode);
  end;
  case ANode.Kind of
    ikLen, ikSize:          ANode.ResolvedType := FTypeInt64;
    ikParamCount:           ANode.ResolvedType := FTypeInt64;
    ikExcCode:              ANode.ResolvedType := FTypeInt32;
    ikParamStr, ikExcMsg, ikCStrToStr, ikFormat: ANode.ResolvedType := FTypeString;
    ikCStr, ikWStr, ikUtf8: ANode.ResolvedType := FTypePointer;
    ikVarArgsCount, ikVarArgsNext, ikVarArgsGet, ikVarArgsReset,
    ikVarArgsCopy:          DoAnalyzeVarArgsIntrinsic(ANode);
  end;
end;

// varargs.* is only meaningful inside a variadic routine. next/get take
// their result type from the requested TypeExpr; the pack element must
// carry the same TypeId at runtime (checked by the runtime, UD-3).
procedure TWklSemantics.DoAnalyzeVarArgsIntrinsic(const ANode: TWklIntrinsicNode);
begin
  if (FCurrentRoutine = nil) or (not FCurrentRoutine.IsVariadic) then
  begin
    SemError(WKL_ERR_SEM_013, RSSemVarArgsOutside, [], ANode);
    Exit;
  end;
  if ANode.TypeExpr <> nil then
  begin
    DoAnalyzeExpr(ANode.TypeExpr);
    // Materialize the tag now so the emitter reads a resolved id
    DoTypeIdOf(ANode.TypeExpr);
  end;
  case ANode.Kind of
    ikVarArgsCount: ANode.ResolvedType := FTypeInt32;
    ikVarArgsNext, ikVarArgsGet: ANode.ResolvedType := ANode.TypeExpr;
    ikVarArgsReset: ANode.ResolvedType := nil;
    ikVarArgsCopy: ANode.ResolvedType := DoFindPrimitive('varargs');
  end;
  if (ANode.Kind = ikVarArgsGet) and (ANode.Args.Count = 1) then
    DoPropagateLiteralType(ANode.Args[0], FTypeInt32);
end;

// A packed bare int literal outside the int32 range is retyped to int64.
procedure TWklSemantics.DoWidenPackedIntLiteral(const AArg: TWklNode);
var
  LValue: Int64;
begin
  if not ((AArg is TWklLiteralNode) and
    (TWklLiteralNode(AArg).Kind = lkInt)) then
    Exit;
  if not DoTypesEqual(AArg.ResolvedType, FTypeInt32) then
    Exit;
  LValue := TWklLiteralNode(AArg).IntValue;
  if (LValue > High(Int32)) or (LValue < Low(Int32)) then
    DoPropagateLiteralType(AArg, FTypeInt64);
end;

procedure TWklSemantics.DoAnalyzeSetLiteral(const ANode: TWklSetLiteralNode);
begin
  DoAnalyzeArgList(ANode.Elements);
end;

procedure TWklSemantics.DoAnalyzeRecordLiteral(
  const ANode: TWklRecordLiteralNode);
var
  LDecl: TWklNode;
  LDef: TWklNode;
  LI: Integer;
  LInit: TWklFieldInitNode;
  LField: TWklFieldDeclNode;
begin
  // Name = record type name
  LDecl := FCurrentScope.Lookup(ANode.Name);
  if (LDecl is TWklForwardTypeNode) and
     (TWklForwardTypeNode(LDecl).ResolvedDecl <> nil) then
    LDecl := TWklForwardTypeNode(LDecl).ResolvedDecl;
  if not (LDecl is TWklTypeDeclNode) then
  begin
    SemError(WKL_ERR_SEM_001, RSSemUndeclaredType, [ANode.Name], ANode);
    Exit;
  end;
  ANode.ResolvedType := LDecl;
  LDef := DoTypeDefOf(LDecl);

  for LI := 0 to ANode.FieldInits.Count - 1 do
  begin
    LInit := TWklFieldInitNode(ANode.FieldInits[LI]);
    DoAnalyzeExpr(LInit.ValueExpr);
    LField := DoFindField(LDef, LInit.Name);
    if LField = nil then
    begin
      SemError(WKL_ERR_SEM_010, RSSemNoFieldFound, [LInit.Name], LInit);
      Continue;
    end;
    // The init resolves to its field so the emitter has the offset
    LInit.ResolvedField := LField;
    DoPropagateLiteralType(LInit.ValueExpr, LField.TypeExpr);
  end;
end;

procedure TWklSemantics.DoAnalyzeTestBlocks();
var
  LI: Integer;
  LJ: Integer;
  LTest: TWklTestBlockNode;
  LLocal: TWklNode;
begin
  for LI := 0 to FModule.TestBlocks.Count - 1 do
  begin
    LTest := TWklTestBlockNode(FModule.TestBlocks[LI]);
    PushScope(skRoutine);

    for LJ := 0 to LTest.LocalVars.Count - 1 do
    begin
      LLocal := LTest.LocalVars[LJ];
      if LLocal.Name <> '' then
        FCurrentScope.Declare(LLocal.Name, LLocal);
      if LLocal is TWklVarDeclNode then
        DoAnalyzeVarDecl(TWklVarDeclNode(LLocal), False);
    end;

    DoAnalyzeStatementList(LTest.Statements);
    PopScope();
  end;
end;

procedure TWklSemantics.DoValidateForwards();
var
  LI: Integer;
  LDecl: TWklNode;
begin
  for LI := 0 to FModule.Declarations.Count - 1 do
  begin
    LDecl := FModule.Declarations[LI];
    if (LDecl is TWklForwardTypeNode) and
       (TWklForwardTypeNode(LDecl).ResolvedDecl = nil) then
      SemError(WKL_ERR_SEM_006, RSSemUnresolvedForwardType, [LDecl.Name], LDecl)
    else if (LDecl is TWklForwardRoutineNode) and
            (TWklForwardRoutineNode(LDecl).ResolvedDecl = nil) then
      SemError(WKL_ERR_SEM_006, RSSemUnresolvedForwardRout, [LDecl.Name], LDecl);
  end;
end;

procedure TWklSemantics.DoValidateModule();
begin
  if (FModule.ModuleKind = mkExe) and (FModule.MainBody = nil) then
    SemError(WKL_ERR_SEM_007, RSSemExeNeedsMainBody, FModule)
  else if (FModule.ModuleKind = mkUnit) and (FModule.MainBody <> nil) then
    SemError(WKL_ERR_SEM_007, RSSemUnitForbidsMainBody, FModule);
end;

procedure TWklSemantics.SemError(const ACode: string; const AMsg: string;
  const ANode: TWklNode);
begin
  SemError(ACode, AMsg, [], ANode);
end;

procedure TWklSemantics.SemError(const ACode: string; const AMsg: string;
  const AArgs: array of const; const ANode: TWklNode);
var
  LRange: TSourceRange;
begin
  if ANode <> nil then
    LRange := ANode.Location
  else
    LRange.Clear();
  FErrors.Add(LRange, esError, ACode, AMsg, AArgs);
end;

function TWklSemantics.Analyze(const ALexer: TWklLexer;
  const AModule: TWklModuleNode): Boolean;
begin
  FLexer := ALexer;
  FModule := AModule;
  FLoopDepth := 0;
  FCurrentRoutine := nil;

  if FModule = nil then
    Exit(False);

  PushScope(skModule);

  // Pass 1: bind every top-level name and import
  DoRegisterDeclarations();
  DoRegisterImports();

  // Pass 2: resolve declarations, then lay out types
  DoAnalyzeDeclarations();
  DoComputeTypeLayouts();

  // Module bodies
  DoAnalyzeBlock(FModule.InitBlock);
  DoAnalyzeBlock(FModule.FinalizeBlock);
  DoAnalyzeBlock(FModule.MainBody);
  DoAnalyzeTestBlocks();

  DoValidateForwards();
  DoValidateModule();

  PopScope();

  Result := not FErrors.HasErrors();
end;

end.
