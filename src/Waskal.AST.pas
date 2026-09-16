{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.AST - Abstract Syntax Tree

  Object tree with direct child references. Every node kind is its own class
  with named, typed fields. Every node is self-describing -- it carries its
  name, location, values, and operator kinds directly. No downstream phase
  reads the lexer for meaning; only source-map generation uses Token.

  Ownership: each node owns its structural children. Freeing the module node
  frees the entire tree. Cross-references written by semantics (ResolvedType,
  ResolvedDecl, ResolvedRoutine, ResolvedModule) and TWklOverloadGroupNode's
  Routines list are NOT owned by the referencing node.

  Dependencies: StdApp.Base
===============================================================================}

unit Waskal.AST;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base;

const
  { WKL_NO_TOKEN }
  WKL_NO_TOKEN = -1;

type
  { Forward declarations }
  TWklNode = class;
  TWklBlockNode = class;
  TWklModuleNode = class;
  TWklRoutineDeclNode = class;

  { TWklNodeList }
  TWklNodeList = TObjectList<TWklNode>;

  { TWklModuleKind }
  TWklModuleKind = (
    mkExe,
    mkLib,
    mkUnit
  );

  { TWklParamMode }
  TWklParamMode = (
    pmConst,
    pmVar,
    pmDefault
  );

  { TWklBinaryOp }
  TWklBinaryOp = (
    boMul,
    boDiv,
    boIntDiv,
    boMod,
    boAnd,
    boShl,
    boShr,
    boAdd,
    boSub,
    boOr,
    boXor,
    boLogicalAnd,
    boLogicalOr,
    boEq,
    boNotEq,
    boLess,
    boGreater,
    boLessEq,
    boGreaterEq,
    boIn
  );

  { TWklUnaryOp }
  TWklUnaryOp = (
    uoNot,
    uoNegate,
    uoPlus,
    uoAddressOf
  );

  { TWklAssignOp }
  TWklAssignOp = (
    aoAssign,
    aoAddAssign,
    aoSubAssign,
    aoMulAssign,
    aoDivAssign
  );

  { TWklLiteralKind }
  TWklLiteralKind = (
    lkInt,
    lkFloat,
    lkString,
    lkWString,
    lkBool,
    lkNil
  );

  { TWklDotAccessKind }
  TWklDotAccessKind = (
    dakUnresolved,
    dakField,
    dakModule,
    dakChoices
  );

  { TWklIntrinsicKind }
  TWklIntrinsicKind = (
    ikLen,
    ikSize,
    ikUtf8,
    ikCStr,
    ikWStr,
    ikParamCount,
    ikParamStr,
    ikExcCode,
    ikExcMsg,
    ikFormat,       // format(fmt, args...): printf-style into a string
    ikCStrToStr,  // synthetic: implicit ptr to char -> string (no source keyword)
    ikVarArgsCount, // varargs.count
    ikVarArgsNext,  // varargs.next(T)      -- TypeExpr = T
    ikVarArgsGet,   // varargs.get(i, T)    -- Args[0] = i, TypeExpr = T
    ikVarArgsReset, // varargs.reset()
    ikVarArgsCopy   // varargs.copy()
  );

  { TWklAssertKind }
  TWklAssertKind = (
    akAssert,
    akAssertTrue,
    akAssertFalse,
    akAssertEq,
    akAssertEqF,
    akAssertNil,
    akAssertNotNil,
    akAssertFail
  );

  { TWklMemOpKind }
  TWklMemOpKind = (
    moNew,
    moDispose,
    moGetMem,
    moFreeMem
  );

  { TWklMemOp2Kind }
  TWklMemOp2Kind = (
    mo2ResizeMem,
    mo2SetLength
  );

  { TWklNode }
  // Base for every AST node. Name holds the identifier text where the node
  // has one. Location is the source range. Token is retained only for
  // source-map generation. ResolvedType is written by semantics, not owned.
  TWklNode = class(TObject)
  public
    Name: string;
    // Declaring module's name for module-level declarations (const, type,
    // var, routine, forward). Set by the parser; '' for every other node.
    // The emitter qualifies wat identifiers with it so two units may
    // declare the same name.
    OwnerModule: string;
    Location: TSourceRange;
    Token: Int64;
    ResolvedType: TWklNode;
    // Program-unique runtime type tag for type-definition nodes. Written by
    // semantics in the layout pass (primitives fixed at creation). 0 = none.
    TypeId: Int64;
    constructor Create(); virtual;
  end;

  { TWklModuleNode }
  TWklModuleNode = class(TWklNode)
  public
    ModuleKind: TWklModuleKind;
    Filename: string;
    Directives: TWklNodeList;
    Imports: TWklNodeList;
    Declarations: TWklNodeList;
    InitBlock: TWklBlockNode;
    FinalizeBlock: TWklBlockNode;
    MainBody: TWklBlockNode;
    TestBlocks: TWklNodeList;
    UnitTestMode: Boolean;
    // Overload groups created by semantics. Owned here so they outlive the
    // analysis scope; scopes and ResolvedDecl only reference them.
    OverloadGroups: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklDirectiveNode }
  // Name = directive name (without @). Args = argument text values.
  TWklDirectiveNode = class(TWklNode)
  public
    Args: TArray<string>;
  end;

  { TWklImportNode }
  // Name = imported unit name. ResolvedModule set by compiler, not owned.
  TWklImportNode = class(TWklNode)
  public
    ResolvedModule: TWklModuleNode;
  end;

  { TWklBlockNode }
  TWklBlockNode = class(TWklNode)
  public
    Statements: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklTestBlockNode }
  // Name = test name string
  TWklTestBlockNode = class(TWklNode)
  public
    LocalVars: TWklNodeList;
    Statements: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklConstDeclNode }
  TWklConstDeclNode = class(TWklNode)
  public
    IsPublic: Boolean;
    TypeExpr: TWklNode;
    ValueExpr: TWklNode;
    // Set by semantics: True when ValueExpr is not a plain literal and the
    // emitter must generate initialisation code at module start.
    NeedsRuntimeInit: Boolean;
    destructor Destroy(); override;
  end;

  { TWklTypeDeclNode }
  TWklTypeDeclNode = class(TWklNode)
  public
    IsPublic: Boolean;
    TypeDef: TWklNode;
    // Set by semantics layout pass. 0 = not yet computed.
    ByteSize: Int64;
    destructor Destroy(); override;
  end;

  { TWklVarDeclNode }
  TWklVarDeclNode = class(TWklNode)
  public
    IsPublic: Boolean;
    TypeExpr: TWklNode;
    InitExpr: TWklNode;
    IsExternal: Boolean;
    ExternLib: string;
    ExternSymbol: string;
    // Set by semantics: True for module-level storage, False for routine
    // and test-block locals. The emitter reads this instead of tracking
    // locals in a side list.
    IsGlobal: Boolean;
    // Set by semantics: True when `address of` is applied to this variable
    // anywhere in the module. The emitter homes such scalars in linear
    // memory so they have an address.
    IsAddressTaken: Boolean;
    destructor Destroy(); override;
  end;

  { TWklRoutineDeclNode }
  TWklRoutineDeclNode = class(TWklNode)
  public
    IsPublic: Boolean;
    IsExternal: Boolean;
    IsVariadic: Boolean;
    Params: TWklNodeList;
    ReturnType: TWklNode;
    ExternLib: string;
    ExternSymbol: string;
    LocalTypes: TWklNodeList;
    LocalConsts: TWklNodeList;
    LocalVars: TWklNodeList;
    Body: TWklBlockNode;
    IsSret: Boolean;
    SretByteSize: Int64;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklOverloadGroupNode }
  // Routines references nodes owned by the parent Declarations list.
  TWklOverloadGroupNode = class(TWklNode)
  public
    Routines: TList<TWklNode>;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklForwardTypeNode }
  // Name = forward-declared type name. ResolvedDecl set by semantics to the
  // TWklTypeDeclNode that completes it; not owned.
  TWklForwardTypeNode = class(TWklNode)
  public
    ResolvedDecl: TWklNode;
  end;

  { TWklForwardRoutineNode }
  // ResolvedDecl set by semantics to the TWklRoutineDeclNode or
  // TWklOverloadGroupNode that completes it; not owned.
  TWklForwardRoutineNode = class(TWklNode)
  public
    Params: TWklNodeList;
    ReturnType: TWklNode;
    IsVariadic: Boolean;
    ResolvedDecl: TWklNode;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklParamNode }
  TWklParamNode = class(TWklNode)
  public
    ParamMode: TWklParamMode;
    TypeExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklRecordTypeNode }
  TWklRecordTypeNode = class(TWklNode)
  public
    IsPacked: Boolean;
    Alignment: Int64;
    BaseType: TWklNode;
    Fields: TWklNodeList;
    // Set by semantics layout pass. 0 = not yet computed.
    ByteSize: Int64;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklOverlayTypeNode }
  TWklOverlayTypeNode = class(TWklNode)
  public
    Fields: TWklNodeList;
    // Set by semantics layout pass. 0 = not yet computed.
    ByteSize: Int64;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklAnonRecordNode }
  TWklAnonRecordNode = class(TWklNode)
  public
    IsPacked: Boolean;
    Fields: TWklNodeList;
    // Set by semantics layout pass. 0 = not yet computed.
    ByteSize: Int64;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklAnonOverlayNode }
  TWklAnonOverlayNode = class(TWklNode)
  public
    Fields: TWklNodeList;
    // Set by semantics layout pass. 0 = not yet computed.
    ByteSize: Int64;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklFieldDeclNode }
  TWklFieldDeclNode = class(TWklNode)
  public
    TypeExpr: TWklNode;
    BitWidth: Int64;
    ByteOffset: Int64;
    // Set by semantics layout pass: bit position within the storage unit
    // at ByteOffset. Only meaningful when BitWidth > 0.
    BitPos: Int64;
    destructor Destroy(); override;
  end;

  { TWklArrayTypeNode }
  TWklArrayTypeNode = class(TWklNode)
  public
    ElementType: TWklNode;
    IsDynamic: Boolean;
    LowBound: TWklNode;
    HighBound: TWklNode;
    // Set by semantics for static arrays: HighBound - LowBound + 1, folded
    // from the bound literals. 0 for dynamic arrays.
    ElementCount: Int64;
    // Set by semantics layout pass. 0 = not yet computed.
    ByteSize: Int64;
    destructor Destroy(); override;
  end;

  { TWklPointerTypeNode }
  TWklPointerTypeNode = class(TWklNode)
  public
    TargetType: TWklNode;
    IsConst: Boolean;
    destructor Destroy(); override;
  end;

  { TWklSetTypeNode }
  TWklSetTypeNode = class(TWklNode)
  public
    ElementType: TWklNode;
    IsRange: Boolean;
    LowBound: TWklNode;
    HighBound: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklChoicesTypeNode }
  TWklChoicesTypeNode = class(TWklNode)
  public
    Values: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklChoicesValueNode }
  TWklChoicesValueNode = class(TWklNode)
  public
    ExplicitValue: TWklNode;
    ResolvedOrdinal: Int64;
    destructor Destroy(); override;
  end;

  { TWklRoutineTypeNode }
  TWklRoutineTypeNode = class(TWklNode)
  public
    Params: TWklNodeList;
    ReturnType: TWklNode;
    IsVariadic: Boolean;
    IsSret: Boolean;
    SretByteSize: Int64;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklTypeRefNode }
  // Name = type name (primitive or user-defined). ModuleName = importing
  // unit qualifier for Module.Type references ('' when unqualified).
  // ResolvedDecl set by semantics, not owned.
  TWklTypeRefNode = class(TWklNode)
  public
    ModuleName: string;
    ResolvedDecl: TWklNode;
  end;

  { TWklAssignNode }
  TWklAssignNode = class(TWklNode)
  public
    Op: TWklAssignOp;
    Target: TWklNode;
    Value: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklCallStmtNode }
  TWklCallStmtNode = class(TWklNode)
  public
    CallExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklIfNode }
  // ElseBody is nil when there is no else branch.
  TWklIfNode = class(TWklNode)
  public
    Condition: TWklNode;
    ThenBody: TWklNodeList;
    ElseBody: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklWhileNode }
  TWklWhileNode = class(TWklNode)
  public
    Condition: TWklNode;
    Body: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklForNode }
  // Name = loop variable name
  TWklForNode = class(TWklNode)
  public
    StartExpr: TWklNode;
    EndExpr: TWklNode;
    IsDownTo: Boolean;
    Body: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklRepeatNode }
  TWklRepeatNode = class(TWklNode)
  public
    Body: TWklNodeList;
    UntilCondition: TWklNode;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklMatchNode }
  // ElseBody is nil when there is no else branch.
  TWklMatchNode = class(TWklNode)
  public
    Scrutinee: TWklNode;
    Arms: TWklNodeList;
    ElseBody: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklMatchArmNode }
  TWklMatchArmNode = class(TWklNode)
  public
    Labels: TWklNodeList;
    Body: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklMatchLabelNode }
  TWklMatchLabelNode = class(TWklNode)
  public
    ValueExpr: TWklNode;
    RangeEnd: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklReturnNode }
  TWklReturnNode = class(TWklNode)
  public
    ValueExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklGuardNode }
  TWklGuardNode = class(TWklNode)
  public
    GuardBody: TWklBlockNode;
    ExceptBody: TWklBlockNode;
    FinallyBody: TWklBlockNode;
    destructor Destroy(); override;
  end;

  { TWklThrowNode }
  TWklThrowNode = class(TWklNode)
  public
    CodeExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklThrowCodeNode }
  TWklThrowCodeNode = class(TWklNode)
  public
    CodeExpr: TWklNode;
    MsgExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklMemOpNode }
  TWklMemOpNode = class(TWklNode)
  public
    Kind: TWklMemOpKind;
    ArgExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklMemOp2Node }
  TWklMemOp2Node = class(TWklNode)
  public
    Kind: TWklMemOp2Kind;
    FirstArg: TWklNode;
    SecondArg: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklPrintNode }
  TWklPrintNode = class(TWklNode)
  public
    IsPrintLn: Boolean;
    Args: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklAssertNode }
  TWklAssertNode = class(TWklNode)
  public
    Kind: TWklAssertKind;
    Args: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklBreakNode }
  TWklBreakNode = class(TWklNode)
  end;

  { TWklContinueNode }
  TWklContinueNode = class(TWklNode)
  end;

  { TWklBinaryExprNode }
  TWklBinaryExprNode = class(TWklNode)
  public
    Op: TWklBinaryOp;
    Left: TWklNode;
    Right: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklUnaryExprNode }
  TWklUnaryExprNode = class(TWklNode)
  public
    Op: TWklUnaryOp;
    Operand: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklLiteralNode }
  // Kind selects which value field is meaningful.
  TWklLiteralNode = class(TWklNode)
  public
    Kind: TWklLiteralKind;
    IntValue: Int64;
    FloatValue: Double;
    StringValue: string;
    BoolValue: Boolean;
    IsFloat32: Boolean;
  end;

  { TWklIdentifierNode }
  // Name = identifier text. ResolvedDecl set by semantics, not owned.
  TWklIdentifierNode = class(TWklNode)
  public
    ResolvedDecl: TWklNode;
  end;

  { TWklDotAccessNode }
  // Name = member name. AccessKind and ResolvedDecl set by semantics.
  TWklDotAccessNode = class(TWklNode)
  public
    BaseExpr: TWklNode;
    AccessKind: TWklDotAccessKind;
    ResolvedDecl: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklIndexAccessNode }
  TWklIndexAccessNode = class(TWklNode)
  public
    BaseExpr: TWklNode;
    IndexExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklDerefNode }
  TWklDerefNode = class(TWklNode)
  public
    BaseExpr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklCallExprNode }
  // ResolvedRoutine set by semantics after overload resolution, not owned.
  TWklCallExprNode = class(TWklNode)
  public
    Callee: TWklNode;
    Args: TWklNodeList;
    ResolvedRoutine: TWklRoutineDeclNode;
    // Set by semantics when the callee is a routine-typed value (not a
    // declared routine). The signature used for call_indirect. Not owned.
    ResolvedRoutineType: TWklRoutineTypeNode;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklSetLiteralNode }
  TWklSetLiteralNode = class(TWklNode)
  public
    Elements: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklSetElementNode }
  TWklSetElementNode = class(TWklNode)
  public
    ValueExpr: TWklNode;
    RangeEnd: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklRecordLiteralNode }
  // Name = record type name
  TWklRecordLiteralNode = class(TWklNode)
  public
    FieldInits: TWklNodeList;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

  { TWklFieldInitNode }
  // Name = field name. ResolvedField set by semantics, not owned.
  TWklFieldInitNode = class(TWklNode)
  public
    ValueExpr: TWklNode;
    ResolvedField: TWklFieldDeclNode;
    destructor Destroy(); override;
  end;

  { TWklTypeCastNode }
  TWklTypeCastNode = class(TWklNode)
  public
    TargetType: TWklNode;
    Expr: TWklNode;
    destructor Destroy(); override;
  end;

  { TWklIntrinsicNode }
  TWklIntrinsicNode = class(TWklNode)
  public
    Kind: TWklIntrinsicKind;
    Args: TWklNodeList;
    // Requested element type for varargs.next(T) / varargs.get(i, T); owned.
    // nil for every other kind.
    TypeExpr: TWklNode;
    constructor Create(); override;
    destructor Destroy(); override;
  end;

const
  { WKL_PRIMITIVE_NAMES }
  // Every built-in type keyword. The AST owns one TWklTypeRefNode sentinel
  // per name for the lifetime of the process; ResolvedDecl/ResolvedType
  // pointers to them are valid in every module and every phase.
  WKL_PRIMITIVE_NAMES: array[0..16] of string = (
    'int8', 'int16', 'int32', 'int64',
    'uint8', 'uint16', 'uint32', 'uint64',
    'float32', 'float64', 'bool', 'char', 'wchar',
    'string', 'wstring', 'ptr', 'varargs'
  );

// Returns the AST-owned sentinel node for a primitive type name, or nil if
// the name is not a primitive. Never free the result.
function WklPrimitiveType(const AName: string): TWklTypeRefNode;

implementation

var
  { GPrimitiveTypes }
  // Process-lifetime primitive sentinels. Created in initialization, freed
  // in finalization. Name set from WKL_PRIMITIVE_NAMES, ResolvedDecl nil.
  GPrimitiveTypes: TObjectList<TWklTypeRefNode>;

procedure WklCreatePrimitiveTypes();
var
  I: Integer;
  LNode: TWklTypeRefNode;
begin
  GPrimitiveTypes := TObjectList<TWklTypeRefNode>.Create(True);
  for I := Low(WKL_PRIMITIVE_NAMES) to High(WKL_PRIMITIVE_NAMES) do
  begin
    LNode := TWklTypeRefNode.Create();
    LNode.Name := WKL_PRIMITIVE_NAMES[I];
    LNode.Token := -1;
    // Fixed runtime type tag: primitives are 1..N by table order
    LNode.TypeId := I + 1;
    GPrimitiveTypes.Add(LNode);
  end;
end;

function WklPrimitiveType(const AName: string): TWklTypeRefNode;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to GPrimitiveTypes.Count - 1 do
  begin
    if GPrimitiveTypes[I].Name = AName then
      Exit(GPrimitiveTypes[I]);
  end;
end;

{ TWklNode }
constructor TWklNode.Create();
begin
  inherited;

  Name := '';
  Location.Clear();
  Token := WKL_NO_TOKEN;
  ResolvedType := nil;
end;

{ TWklModuleNode }
constructor TWklModuleNode.Create();
begin
  inherited;

  Directives := TWklNodeList.Create(True);
  Imports := TWklNodeList.Create(True);
  Declarations := TWklNodeList.Create(True);
  TestBlocks := TWklNodeList.Create(True);
  OverloadGroups := TWklNodeList.Create(True);
end;

destructor TWklModuleNode.Destroy();
begin
  OverloadGroups.Free();
  MainBody.Free();
  FinalizeBlock.Free();
  InitBlock.Free();
  TestBlocks.Free();
  Declarations.Free();
  Imports.Free();
  Directives.Free();

  inherited;
end;

{ TWklBlockNode }
constructor TWklBlockNode.Create();
begin
  inherited;

  Statements := TWklNodeList.Create(True);
end;

destructor TWklBlockNode.Destroy();
begin
  Statements.Free();

  inherited;
end;

{ TWklTestBlockNode }
constructor TWklTestBlockNode.Create();
begin
  inherited;

  LocalVars := TWklNodeList.Create(True);
  Statements := TWklNodeList.Create(True);
end;

destructor TWklTestBlockNode.Destroy();
begin
  Statements.Free();
  LocalVars.Free();

  inherited;
end;

{ TWklConstDeclNode }
destructor TWklConstDeclNode.Destroy();
begin
  ValueExpr.Free();
  TypeExpr.Free();

  inherited;
end;

{ TWklTypeDeclNode }
destructor TWklTypeDeclNode.Destroy();
begin
  TypeDef.Free();

  inherited;
end;

{ TWklVarDeclNode }
destructor TWklVarDeclNode.Destroy();
begin
  InitExpr.Free();
  TypeExpr.Free();

  inherited;
end;

{ TWklRoutineDeclNode }
constructor TWklRoutineDeclNode.Create();
begin
  inherited;

  Params := TWklNodeList.Create(True);
  LocalTypes := TWklNodeList.Create(True);
  LocalConsts := TWklNodeList.Create(True);
  LocalVars := TWklNodeList.Create(True);
end;

destructor TWklRoutineDeclNode.Destroy();
begin
  Body.Free();
  LocalVars.Free();
  LocalConsts.Free();
  LocalTypes.Free();
  ReturnType.Free();
  Params.Free();

  inherited;
end;

{ TWklOverloadGroupNode }
constructor TWklOverloadGroupNode.Create();
begin
  inherited;

  Routines := TList<TWklNode>.Create();
end;

destructor TWklOverloadGroupNode.Destroy();
begin
  Routines.Free();

  inherited;
end;

{ TWklForwardRoutineNode }
constructor TWklForwardRoutineNode.Create();
begin
  inherited;

  Params := TWklNodeList.Create(True);
end;

destructor TWklForwardRoutineNode.Destroy();
begin
  ReturnType.Free();
  Params.Free();

  inherited;
end;

{ TWklParamNode }
destructor TWklParamNode.Destroy();
begin
  TypeExpr.Free();

  inherited;
end;

{ TWklRecordTypeNode }
constructor TWklRecordTypeNode.Create();
begin
  inherited;

  Fields := TWklNodeList.Create(True);
end;

destructor TWklRecordTypeNode.Destroy();
begin
  Fields.Free();
  BaseType.Free();

  inherited;
end;

{ TWklOverlayTypeNode }
constructor TWklOverlayTypeNode.Create();
begin
  inherited;

  Fields := TWklNodeList.Create(True);
end;

destructor TWklOverlayTypeNode.Destroy();
begin
  Fields.Free();

  inherited;
end;

{ TWklAnonRecordNode }
constructor TWklAnonRecordNode.Create();
begin
  inherited;

  Fields := TWklNodeList.Create(True);
end;

destructor TWklAnonRecordNode.Destroy();
begin
  Fields.Free();

  inherited;
end;

{ TWklAnonOverlayNode }
constructor TWklAnonOverlayNode.Create();
begin
  inherited;

  Fields := TWklNodeList.Create(True);
end;

destructor TWklAnonOverlayNode.Destroy();
begin
  Fields.Free();

  inherited;
end;

{ TWklFieldDeclNode }
destructor TWklFieldDeclNode.Destroy();
begin
  TypeExpr.Free();

  inherited;
end;

{ TWklArrayTypeNode }
destructor TWklArrayTypeNode.Destroy();
begin
  HighBound.Free();
  LowBound.Free();
  ElementType.Free();

  inherited;
end;

{ TWklPointerTypeNode }
destructor TWklPointerTypeNode.Destroy();
begin
  TargetType.Free();

  inherited;
end;

{ TWklSetTypeNode }
destructor TWklSetTypeNode.Destroy();
begin
  HighBound.Free();
  LowBound.Free();
  ElementType.Free();

  inherited;
end;

{ TWklChoicesTypeNode }
constructor TWklChoicesTypeNode.Create();
begin
  inherited;

  Values := TWklNodeList.Create(True);
end;

destructor TWklChoicesTypeNode.Destroy();
begin
  Values.Free();

  inherited;
end;

{ TWklChoicesValueNode }
destructor TWklChoicesValueNode.Destroy();
begin
  ExplicitValue.Free();

  inherited;
end;

{ TWklRoutineTypeNode }
constructor TWklRoutineTypeNode.Create();
begin
  inherited;

  Params := TWklNodeList.Create(True);
end;

destructor TWklRoutineTypeNode.Destroy();
begin
  ReturnType.Free();
  Params.Free();

  inherited;
end;

{ TWklAssignNode }
destructor TWklAssignNode.Destroy();
begin
  Value.Free();
  Target.Free();

  inherited;
end;

{ TWklCallStmtNode }
destructor TWklCallStmtNode.Destroy();
begin
  CallExpr.Free();

  inherited;
end;

{ TWklIfNode }
constructor TWklIfNode.Create();
begin
  inherited;

  ThenBody := TWklNodeList.Create(True);
end;

destructor TWklIfNode.Destroy();
begin
  ElseBody.Free();
  ThenBody.Free();
  Condition.Free();

  inherited;
end;

{ TWklWhileNode }
constructor TWklWhileNode.Create();
begin
  inherited;

  Body := TWklNodeList.Create(True);
end;

destructor TWklWhileNode.Destroy();
begin
  Body.Free();
  Condition.Free();

  inherited;
end;

{ TWklForNode }
constructor TWklForNode.Create();
begin
  inherited;

  Body := TWklNodeList.Create(True);
end;

destructor TWklForNode.Destroy();
begin
  Body.Free();
  EndExpr.Free();
  StartExpr.Free();

  inherited;
end;

{ TWklRepeatNode }
constructor TWklRepeatNode.Create();
begin
  inherited;

  Body := TWklNodeList.Create(True);
end;

destructor TWklRepeatNode.Destroy();
begin
  UntilCondition.Free();
  Body.Free();

  inherited;
end;

{ TWklMatchNode }
constructor TWklMatchNode.Create();
begin
  inherited;

  Arms := TWklNodeList.Create(True);
end;

destructor TWklMatchNode.Destroy();
begin
  ElseBody.Free();
  Arms.Free();
  Scrutinee.Free();

  inherited;
end;

{ TWklMatchArmNode }
constructor TWklMatchArmNode.Create();
begin
  inherited;

  Labels := TWklNodeList.Create(True);
  Body := TWklNodeList.Create(True);
end;

destructor TWklMatchArmNode.Destroy();
begin
  Body.Free();
  Labels.Free();

  inherited;
end;

{ TWklMatchLabelNode }
destructor TWklMatchLabelNode.Destroy();
begin
  RangeEnd.Free();
  ValueExpr.Free();

  inherited;
end;

{ TWklReturnNode }
destructor TWklReturnNode.Destroy();
begin
  ValueExpr.Free();

  inherited;
end;

{ TWklGuardNode }
destructor TWklGuardNode.Destroy();
begin
  FinallyBody.Free();
  ExceptBody.Free();
  GuardBody.Free();

  inherited;
end;

{ TWklThrowNode }
destructor TWklThrowNode.Destroy();
begin
  CodeExpr.Free();

  inherited;
end;

{ TWklThrowCodeNode }
destructor TWklThrowCodeNode.Destroy();
begin
  MsgExpr.Free();
  CodeExpr.Free();

  inherited;
end;

{ TWklMemOpNode }
destructor TWklMemOpNode.Destroy();
begin
  ArgExpr.Free();

  inherited;
end;

{ TWklMemOp2Node }
destructor TWklMemOp2Node.Destroy();
begin
  SecondArg.Free();
  FirstArg.Free();

  inherited;
end;

{ TWklPrintNode }
constructor TWklPrintNode.Create();
begin
  inherited;

  Args := TWklNodeList.Create(True);
end;

destructor TWklPrintNode.Destroy();
begin
  Args.Free();

  inherited;
end;

{ TWklAssertNode }
constructor TWklAssertNode.Create();
begin
  inherited;

  Args := TWklNodeList.Create(True);
end;

destructor TWklAssertNode.Destroy();
begin
  Args.Free();

  inherited;
end;

{ TWklBinaryExprNode }
destructor TWklBinaryExprNode.Destroy();
begin
  Right.Free();
  Left.Free();

  inherited;
end;

{ TWklUnaryExprNode }
destructor TWklUnaryExprNode.Destroy();
begin
  Operand.Free();

  inherited;
end;

{ TWklDotAccessNode }
destructor TWklDotAccessNode.Destroy();
begin
  BaseExpr.Free();

  inherited;
end;

{ TWklIndexAccessNode }
destructor TWklIndexAccessNode.Destroy();
begin
  IndexExpr.Free();
  BaseExpr.Free();

  inherited;
end;

{ TWklDerefNode }
destructor TWklDerefNode.Destroy();
begin
  BaseExpr.Free();

  inherited;
end;

{ TWklCallExprNode }
constructor TWklCallExprNode.Create();
begin
  inherited;

  Args := TWklNodeList.Create(True);
end;

destructor TWklCallExprNode.Destroy();
begin
  Args.Free();
  Callee.Free();

  inherited;
end;

{ TWklSetLiteralNode }
constructor TWklSetLiteralNode.Create();
begin
  inherited;

  Elements := TWklNodeList.Create(True);
end;

destructor TWklSetLiteralNode.Destroy();
begin
  Elements.Free();

  inherited;
end;

{ TWklSetElementNode }
destructor TWklSetElementNode.Destroy();
begin
  RangeEnd.Free();
  ValueExpr.Free();

  inherited;
end;

{ TWklRecordLiteralNode }
constructor TWklRecordLiteralNode.Create();
begin
  inherited;

  FieldInits := TWklNodeList.Create(True);
end;

destructor TWklRecordLiteralNode.Destroy();
begin
  FieldInits.Free();

  inherited;
end;

{ TWklFieldInitNode }
destructor TWklFieldInitNode.Destroy();
begin
  ValueExpr.Free();

  inherited;
end;

{ TWklTypeCastNode }
destructor TWklTypeCastNode.Destroy();
begin
  Expr.Free();
  TargetType.Free();

  inherited;
end;

{ TWklIntrinsicNode }
constructor TWklIntrinsicNode.Create();
begin
  inherited;

  Args := TWklNodeList.Create(True);
end;

destructor TWklIntrinsicNode.Destroy();
begin
  Args.Free();
  TypeExpr.Free();

  inherited;
end;

initialization
  WklCreatePrimitiveTypes();

finalization
  GPrimitiveTypes.Free();

end.
