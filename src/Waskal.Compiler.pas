{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.Compiler - Top-level compiler driver

  Owns and orchestrates the full pipeline:
    Lexer -> Parser -> Semantics -> Emitter (.wat) -> Build (.html)

  All components share a single error handler via SetErrors. Status callbacks
  propagate to all components via SetStatusCallback override.

  The caller configures build settings (output path, optimize level, etc.)
  before calling Compile(). Compile() runs the full pipeline in one shot:
  parse, analyze, emit .wat, assemble via wasm-opt, bundle JS, and package
  the final .html artifact.

  Imported units are parsed and analyzed into their own TWklModuleNode,
  owned by the compiler. Each TWklImportNode.ResolvedModule points at the
  unit's tree; semantics and the emitter read unit members through that
  reference. No declarations are copied between modules.

  Dependencies: Waskal.Common, Waskal.Lexer, Waskal.AST, Waskal.Parser,
  Waskal.Semantics, Waskal.Emitter, Waskal.Build
===============================================================================}

unit Waskal.Compiler;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  Waskal.Common,
  Waskal.Lexer,
  Waskal.AST,
  Waskal.Parser,
  Waskal.Semantics,
  Waskal.Emitter,
  Waskal.Build;

const
  // Error codes
  WKL_ERR_CMP_001 = 'CMP001';  // General compiler error
  WKL_ERR_CMP_002 = 'CMP002';  // Cannot auto-run non-exe module
  WKL_ERR_CMP_003 = 'CMP003';  // External library or unit not found

type
  // Forwards
  TWklCompiler = class;

  { TWklPreParseCallback }
  TWklPreParseCallback = reference to procedure(const ACompiler: TWklCompiler;
    const AUserData: Pointer);

  { TWklPreParseCallbackEntry }
  TWklPreParseCallbackEntry = TCallback<TWklPreParseCallback>;

  { TWklPreParseCallbackList }
  TWklPreParseCallbackList = TList<TWklPreParseCallbackEntry>;

  { TWklPreBuildCallback }
  TWklPreBuildCallback = reference to procedure(const ACompiler: TWklCompiler;
    const AUserData: Pointer);

  { TWklPreBuildCallbackEntry }
  TWklPreBuildCallbackEntry = TCallback<TWklPreBuildCallback>;

  { TWklPreBuildCallbackList }
  TWklPreBuildCallbackList = TList<TWklPreBuildCallbackEntry>;

  { TWklCompiler }
  TWklCompiler = class(TBaseObject)
  private
    FLexer: TWklLexer;
    FParser: TWklParser;
    FSemantics: TWklSemantics;
    FEmitter: TWklEmitter;
    FBuild: TWklBuild;
    FSourceMap: TWklSourceMap;
    FOutputPath: string;
    FLastExitCode: DWORD;
    FPreParseCallbacks: TWklPreParseCallbackList;
    FPreBuildCallbacks: TWklPreBuildCallbackList;
    FKeyValues: TDictionary<string, string>;
    FModulePaths: TStringList;
    FFaviconPath: string;
    // The main module tree. Owned.
    FModule: TWklModuleNode;
    // Every imported unit tree, owned here. Import nodes only reference them.
    FUnitModules: TObjectList<TWklModuleNode>;
    // Unit name (lowercase) -> parsed unit module. References FUnitModules.
    FUnitCache: TDictionary<string, TWklModuleNode>;
    procedure DoClearModules();
    procedure DoProcessDirectives();
    procedure DoProcessUnitDirectives(const AUnit: TWklModuleNode);
    procedure DoFirePreParseCallbacks();
    procedure DoFirePreBuildCallbacks();
    procedure DoCLIDirectives();
    function DoFindUnitFile(const AUnitName: string;
      const ASourceDir: string; out AUnitFile: string): Boolean;
    function DoLoadUnit(const AImport: TWklImportNode;
      const ASourceDir: string): TWklModuleNode;
    procedure DoResolveImports(const AModule: TWklModuleNode);
    procedure DoCompileImportedUnits();
    function DoFindExternalLibFile(const ALibName: string;
      const ASourceDir: string; out AFilePath: string): Boolean;
    procedure DoResolveModuleExternalLibs(const AModule: TWklModuleNode;
      const AResolved: TDictionary<string, string>);
    procedure DoResolveExternalLibs();
    procedure DoEmitCode();
    function DoValidateUnitModule(): Boolean;
    function DoValidateAutoRun(const AAutoRun: Boolean): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure SetErrors(const AErrors: TErrors); override;
    function  HasErrors(): Boolean;
    procedure PrintErrors();

    procedure SetStatusCallback(const ACallback: TStatusCallback;
      const AUserData: Pointer = nil);

    // Full compilation pipeline: .wkl -> .wat -> .wasm -> .html
    procedure Compile(const ASourceFile: string; const AOutputPath: string;
      const AAutoRun: Boolean = False);

    // Run the last built artifact
    function Run(): Boolean;

    // Build configuration (set before calling Compile)
    procedure SetOptimizeLevel(const ALevel: Integer);

    // Defines
    procedure SetDefine(const ADefineName: string); overload;
    procedure SetDefine(const ADefineName: string;
      const AValue: string); overload;
    procedure SetDefines(const ADefineNames: array of string);

    // Undefines
    procedure UnsetDefine(const ADefineName: string);
    procedure RemoveUndefine(const ADefineName: string);
    procedure ClearUndefines();

    // Module and library search paths
    procedure AddModulePath(const APath: string);
    procedure AddLibraryPath(const APath: string);

    // Pre-parse callbacks (fired before parsing begins)
    procedure AddPreParseCallback(const ACallback: TWklPreParseCallback;
      const AUserData: Pointer = nil);
    procedure ClearPreParseCallbacks();

    // Pre-build callbacks (fired after directives, before build)
    procedure AddPreBuildCallback(const ACallback: TWklPreBuildCallback;
      const AUserData: Pointer = nil);
    procedure ClearPreBuildCallbacks();

    // Key-value store (generic property bag for cross-phase data)
    procedure SetKeyValue(const AKey: string; const AValue: string);
    function GetKeyValue(const AKey: string;
      const ADefault: string = ''): string;
    procedure ClearKeyValue(const AKey: string);

    // Getters
    function GetLastExitCode(): DWORD;
    function GetOutputPath(): string;
    function GetOptimizeLevel(): Integer;
    function GetOutputFilename(): string;
  end;

implementation


{ TWklCompiler }

constructor TWklCompiler.Create();
begin
  inherited;

  FErrors := TErrors.Create();
  FLexer := TWklLexer.Create();
  FParser := TWklParser.Create();
  FSemantics := TWklSemantics.Create();
  FEmitter := TWklEmitter.Create();
  FBuild := TWklBuild.Create();

  // Every component reports into the compiler's single error set
  FLexer.SetErrors(FErrors);
  FParser.SetErrors(FErrors);
  FSemantics.SetErrors(FErrors);
  FEmitter.SetErrors(FErrors);
  FBuild.SetErrors(FErrors);

  FSourceMap := TWklSourceMap.Create();
  FPreParseCallbacks := TWklPreParseCallbackList.Create();
  FPreBuildCallbacks := TWklPreBuildCallbackList.Create();
  FKeyValues := TDictionary<string, string>.Create();
  FModulePaths := TStringList.Create();
  FModulePaths.Duplicates := dupIgnore;

  FModule := nil;
  FUnitModules := TObjectList<TWklModuleNode>.Create(True);
  FUnitCache := TDictionary<string, TWklModuleNode>.Create();
  FLastExitCode := 0;
end;

destructor TWklCompiler.Destroy();
begin
  DoClearModules();
  FUnitCache.Free();
  FUnitModules.Free();
  FModulePaths.Free();
  FKeyValues.Free();
  FPreBuildCallbacks.Free();
  FPreParseCallbacks.Free();
  FSourceMap.Free();
  FBuild.Free();
  FEmitter.Free();
  FSemantics.Free();
  FParser.Free();
  FLexer.Free();
  FErrors.Free();

  inherited;
end;

procedure TWklCompiler.SetErrors(const AErrors: TErrors);
begin
end;

function  TWklCompiler.HasErrors(): Boolean;
begin
  Result := FErrors.HasErrors();
end;

procedure TWklCompiler.PrintErrors();
begin
  FErrors.PrintErrors();
end;

procedure TWklCompiler.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  FErrors.SetStatusCallback(ACallback, AUserData);
end;

procedure TWklCompiler.DoClearModules();
begin
  FreeAndNil(FModule);
  FUnitCache.Clear();
  FUnitModules.Clear();
end;

procedure TWklCompiler.DoProcessDirectives();
var
  LDir: TWklDirectiveNode;
  LDirName: string;
  LValue: string;
  LValue2: string;
  LValue3: string;
  LAssetResolved: string;
  LAssetKey: string;
  I: Integer;
begin
  if FModule = nil then
    Exit;

  for I := 0 to FModule.Directives.Count - 1 do
  begin
    if not (FModule.Directives[I] is TWklDirectiveNode) then
      Continue;

    LDir := TWklDirectiveNode(FModule.Directives[I]);
    LDirName := LDir.Name.ToLower();

    if Length(LDir.Args) > 0 then
      LValue := LDir.Args[0]
    else
      LValue := '';

    if Length(LDir.Args) > 1 then
      LValue2 := LDir.Args[1]
    else
      LValue2 := '';

    if Length(LDir.Args) > 2 then
      LValue3 := LDir.Args[2]
    else
      LValue3 := '';

    if LDirName = 'optimize' then
    begin
      if LValue.ToLower() = 'none' then
        SetOptimizeLevel(0)
      else if LValue = '1' then
        SetOptimizeLevel(1)
      else if LValue = '2' then
        SetOptimizeLevel(2)
      else if LValue = '3' then
        SetOptimizeLevel(3)
      else if LValue = '4' then
        SetOptimizeLevel(4)
      else if LValue.ToLower() = 's' then
        SetOptimizeLevel(5)
      else if LValue.ToLower() = 'z' then
        SetOptimizeLevel(6)
      else
        FErrors.Add(LDir.Location, esError, WKL_ERR_CMP_001,
          'Unknown @optimize value ''%s''; expected none, 1, 2, 3, 4, s, or z',
          [LValue]);
    end
    else if LDirName = 'modulepath' then
    begin
      AddModulePath(TUtils.ResolvePath(LValue.DeQuotedString('"')));
    end
    else if LDirName = 'addlibrarypath' then
    begin
      AddLibraryPath(TUtils.ResolvePath(LValue.DeQuotedString('"')));
    end
    else if LDirName = 'outputpath' then
    begin
      FOutputPath := TUtils.ResolvePath(LValue.DeQuotedString('"'));
    end
    else if LDirName = 'unittestmode' then
    begin
      if LValue.ToLower() = 'on' then
      begin
        FModule.UnitTestMode := True;
        FParser.SetDefine('UNITTESTMODE', '1');
      end
      else if LValue.ToLower() = 'off' then
      begin
        FModule.UnitTestMode := False;
        FParser.Undefine('UNITTESTMODE');
      end
      else
        FErrors.Add(LDir.Location, esWarning, WKL_ERR_CMP_001,
          'Unknown @unittestmode value ''%s''; expected on or off',
          [LValue]);
    end
    else if LDirName = 'favicon' then
    begin
      FFaviconPath := TUtils.ResolvePath(LValue.DeQuotedString('"'));
    end
    else if LDirName = 'message' then
    begin
      if LValue.ToLower() = 'hint' then
        FErrors.Add(LDir.Location, esHint, WKL_ERR_CMP_001, '%s', [LValue2])
      else if LValue.ToLower() = 'warn' then
        FErrors.Add(LDir.Location, esWarning, WKL_ERR_CMP_001, '%s', [LValue2])
      else if LValue.ToLower() = 'error' then
        FErrors.Add(LDir.Location, esError, WKL_ERR_CMP_001, '%s', [LValue2])
      else if LValue.ToLower() = 'fatal' then
        FErrors.Add(LDir.Location, esFatal, WKL_ERR_CMP_001, '%s', [LValue2])
      else
        FErrors.Add(LDir.Location, esWarning, WKL_ERR_CMP_001,
          'Unknown @message severity ''%s''; expected hint, warn, error, or fatal',
          [LValue]);
    end
    else if LDirName = 'asset' then
    begin
      if LValue2 = '' then
      begin
        FErrors.Add(LDir.Location, esError, WKL_ERR_CMP_001,
          '@asset requires two string arguments: @asset "filename" "virtual_path"',
          []);
      end
      else
      begin
        // Resolve physical path for reading the file
        LAssetResolved := TUtils.ResolvePath(LValue.DeQuotedString('"'));
        // Virtual key = virtual_path + filename
        LAssetKey := TPath.Combine(
          LValue2.DeQuotedString('"'),
          TPath.GetFileName(LAssetResolved));
        FBuild.AddAsset(LAssetKey, LAssetResolved);
      end;
    end
    else if LDirName = 'assets' then
    begin
      if (LValue2 = '') or (LValue3 = '') then
      begin
        FErrors.Add(LDir.Location, esError, WKL_ERR_CMP_001,
          '@assets requires three string arguments: @assets "source_path" "base_folder" "pattern"',
          []);
      end
      else
      begin
        FBuild.AddAssetPath(
          TUtils.ResolvePath(LValue.DeQuotedString('"')),
          LValue2.DeQuotedString('"'),
          LValue3.DeQuotedString('"'));
      end;
    end;
  end;
end;

procedure TWklCompiler.DoProcessUnitDirectives(const AUnit: TWklModuleNode);
var
  LDir: TWklDirectiveNode;
  LDirName: string;
  LValue: string;
  I: Integer;
begin
  // Only the search-path directives matter from a unit; everything else is
  // a property of the main module.
  for I := 0 to AUnit.Directives.Count - 1 do
  begin
    if not (AUnit.Directives[I] is TWklDirectiveNode) then
      Continue;

    LDir := TWklDirectiveNode(AUnit.Directives[I]);
    LDirName := LDir.Name.ToLower();

    if Length(LDir.Args) > 0 then
      LValue := LDir.Args[0]
    else
      LValue := '';

    if LDirName = 'addlibrarypath' then
    begin
      AddLibraryPath(TUtils.ResolvePath(LValue.DeQuotedString('"')));
    end
    else if LDirName = 'modulepath' then
    begin
      AddModulePath(TUtils.ResolvePath(LValue.DeQuotedString('"')));
    end;
  end;
end;

procedure TWklCompiler.DoFirePreParseCallbacks();
var
  I: Integer;
begin
  for I := 0 to FPreParseCallbacks.Count - 1 do
    FPreParseCallbacks[I].Callback(Self, FPreParseCallbacks[I].UserData);
end;

procedure TWklCompiler.DoFirePreBuildCallbacks();
var
  I: Integer;
begin
  for I := 0 to FPreBuildCallbacks.Count - 1 do
    FPreBuildCallbacks[I].Callback(Self, FPreBuildCallbacks[I].UserData);
end;

procedure TWklCompiler.DoCLIDirectives();
var
  LValue: string;
  LLower: string;
begin
  LValue := GetKeyValue('optimize');
  if LValue <> '' then
  begin
    LLower := LValue.ToLower();
    if (LLower = 'none') or (LLower = 'debug') then
      FBuild.SetOptimizationLevel(0)
    else if LLower = '1' then
      FBuild.SetOptimizationLevel(1)
    else if LLower = '2' then
      FBuild.SetOptimizationLevel(2)
    else if LLower = '3' then
      FBuild.SetOptimizationLevel(3)
    else if LLower = '4' then
      FBuild.SetOptimizationLevel(4)
    else if LLower = 's' then
      FBuild.SetOptimizationLevel(5)
    else if LLower = 'z' then
      FBuild.SetOptimizationLevel(6)
    else
      FErrors.Add(esError, WKL_ERR_CMP_001,
        'Unknown optimize level ''%s''; expected none, 1, 2, 3, 4, s, or z',
        [LValue]);
  end;

  LValue := GetKeyValue('outputpath');
  if LValue <> '' then
    FOutputPath := TUtils.ResolvePath(LValue);
end;

function TWklCompiler.DoFindUnitFile(const AUnitName: string;
  const ASourceDir: string; out AUnitFile: string): Boolean;
var
  K: Integer;
begin
  // Source dir first, then module search paths in declared order
  AUnitFile := TPath.Combine(ASourceDir, AUnitName + WKL_SRCFILE_EXT);
  if TFile.Exists(AUnitFile) then
    Exit(True);

  for K := 0 to FModulePaths.Count - 1 do
  begin
    AUnitFile := TPath.Combine(FModulePaths[K], AUnitName + WKL_SRCFILE_EXT);
    if TFile.Exists(AUnitFile) then
      Exit(True);
  end;

  AUnitFile := '';
  Result := False;
end;

function TWklCompiler.DoLoadUnit(const AImport: TWklImportNode;
  const ASourceDir: string): TWklModuleNode;
var
  LUnitName: string;
  LUnitKey: string;
  LUnitFile: string;
begin
  Result := nil;
  LUnitName := AImport.Name;
  LUnitKey := LUnitName.ToLower();

  // Already parsed and analyzed (diamond import or cycle)
  if FUnitCache.TryGetValue(LUnitKey, Result) then
    Exit;

  if not DoFindUnitFile(LUnitName, ASourceDir, LUnitFile) then
  begin
    FErrors.Add(AImport.Location, esError, WKL_ERR_CMP_003,
      'Imported unit not found: ''%s''', [LUnitName]);
    Exit;
  end;

  Status('Parsing unit ''%s''...', [LUnitName]);
  Result := FParser.ParseUnit(FLexer, LUnitFile);

  if FErrors.HasErrors() then
  begin
    Result.Free();
    Result := nil;
    Exit;
  end;

  if Result = nil then
  begin
    FErrors.Add(AImport.Location, esError, WKL_ERR_CMP_003,
      'Failed to parse unit: ''%s''', [LUnitName]);
    Exit;
  end;

  // Take ownership and cache before recursing so cycles terminate
  FUnitModules.Add(Result);
  FUnitCache.Add(LUnitKey, Result);

  // A unit may import other units; resolve them before analyzing this one
  DoResolveImports(Result);

  if FErrors.HasErrors() then
    Exit;

  Status('Analyzing unit ''%s''...', [LUnitName]);
  FSemantics.Analyze(FLexer, Result);

  if FErrors.HasErrors() then
    Exit;

  // Search-path directives declared by the unit apply to the whole build
  DoProcessUnitDirectives(Result);
end;

procedure TWklCompiler.DoResolveImports(const AModule: TWklModuleNode);
var
  LImport: TWklImportNode;
  LSourceDir: string;
  I: Integer;
begin
  if AModule.Imports.Count = 0 then
    Exit;

  LSourceDir := TPath.GetDirectoryName(AModule.Filename);

  for I := 0 to AModule.Imports.Count - 1 do
  begin
    if not (AModule.Imports[I] is TWklImportNode) then
      Continue;

    LImport := TWklImportNode(AModule.Imports[I]);

    // Not owned by the import node; the compiler owns every unit tree
    LImport.ResolvedModule := DoLoadUnit(LImport, LSourceDir);

    if FErrors.HasErrors() then
      Exit;
  end;
end;

procedure TWklCompiler.DoCompileImportedUnits();
begin
  if FModule = nil then
    Exit;

  DoResolveImports(FModule);
end;

function TWklCompiler.DoFindExternalLibFile(const ALibName: string;
  const ASourceDir: string; out AFilePath: string): Boolean;
var
  LExt: string;
  K: Integer;
begin
  // Source dir first, then @addlibrarypath dirs; .wasm before .js in each
  for LExt in ['.wasm', '.js'] do
  begin
    AFilePath := TPath.Combine(ASourceDir, ALibName + LExt);
    if TFile.Exists(AFilePath) then
      Exit(True);
  end;

  for K := 0 to FBuild.LibPaths.Count - 1 do
  begin
    for LExt in ['.wasm', '.js'] do
    begin
      AFilePath := TPath.Combine(FBuild.LibPaths[K], ALibName + LExt);
      if TFile.Exists(AFilePath) then
        Exit(True);
    end;
  end;

  AFilePath := '';
  Result := False;
end;

procedure TWklCompiler.DoResolveModuleExternalLibs(
  const AModule: TWklModuleNode;
  const AResolved: TDictionary<string, string>);
var
  LDecl: TWklNode;
  LLibName: string;
  LSourceDir: string;
  LFilePath: string;
  I: Integer;
begin
  LSourceDir := TPath.GetDirectoryName(AModule.Filename);

  for I := 0 to AModule.Declarations.Count - 1 do
  begin
    LDecl := AModule.Declarations[I];

    // Only external routines and vars carry a library name
    if LDecl is TWklRoutineDeclNode then
    begin
      if not TWklRoutineDeclNode(LDecl).IsExternal then
        Continue;
      LLibName := TWklRoutineDeclNode(LDecl).ExternLib;
    end
    else if LDecl is TWklVarDeclNode then
    begin
      if not TWklVarDeclNode(LDecl).IsExternal then
        Continue;
      LLibName := TWklVarDeclNode(LDecl).ExternLib;
    end
    else
      Continue;

    if LLibName = '' then
      Continue;

    // Skip built-in WASI imports
    if LLibName = 'wasi_snapshot_preview1' then
      Continue;

    // Already resolved (or already reported missing) by any module
    if AResolved.ContainsKey(LLibName) then
      Continue;

    if not DoFindExternalLibFile(LLibName, LSourceDir, LFilePath) then
    begin
      FErrors.Add(LDecl.Location, esError, WKL_ERR_CMP_003,
        'External library not found: ''%s'' (searched .wasm and .js)',
        [LLibName]);
      AResolved.Add(LLibName, '');
      Continue;
    end;

    AResolved.Add(LLibName, LFilePath);

    if TPath.GetExtension(LFilePath).ToLower() = '.js' then
      FBuild.AddExternalJs(LLibName, LFilePath)
    else
      FBuild.AddExternalWasm(LFilePath);
  end;
end;

procedure TWklCompiler.DoResolveExternalLibs();
var
  LResolved: TDictionary<string, string>;
  I: Integer;
begin
  if FModule = nil then
    Exit;

  // Externals are declared wherever the routine lives: the main module or
  // any imported unit. Each is searched relative to its own source file.
  LResolved := TDictionary<string, string>.Create();
  try
    DoResolveModuleExternalLibs(FModule, LResolved);
    for I := 0 to FUnitModules.Count - 1 do
      DoResolveModuleExternalLibs(FUnitModules[I], LResolved);
  finally
    LResolved.Free();
  end;
end;

procedure TWklCompiler.DoEmitCode();
var
  LWat: string;
begin
  Status('Emitting code...');

  FSourceMap.Clear();
  FEmitter.SetOptimizeLevel(GetOptimizeLevel());
  LWat := FEmitter.Emit(FLexer, FModule, FSourceMap);

  if FErrors.HasErrors() then
    Exit;

  // Hand the .wat text and its line map to the build pipeline so wasm-opt
  // errors can be reported against .wkl source locations
  FBuild.SetWatSource(LWat);
  FBuild.SetWatSourceMap(FSourceMap);
end;

function TWklCompiler.DoValidateUnitModule(): Boolean;
begin
  Result := FModule.ModuleKind = mkUnit;
  if not Result then
    Exit;

  Status('Unit ''%s'' validated successfully.', [FModule.Name]);
  Status('Warning: Unit modules produce no output. Import this unit from an exe or lib module.');
end;

function TWklCompiler.DoValidateAutoRun(const AAutoRun: Boolean): Boolean;
begin
  if not AAutoRun then
    Exit(False);

  Result := True;

  if FModule.ModuleKind <> mkExe then
  begin
    if FModule.ModuleKind = mkLib then
      FErrors.Add(FModule.Location, esWarning, WKL_ERR_CMP_002,
        'Cannot auto-run a library module', [])
    else
      FErrors.Add(FModule.Location, esWarning, WKL_ERR_CMP_002,
        'Cannot auto-run a unit module', []);
    Result := False;
  end;
end;

procedure TWklCompiler.Compile(const ASourceFile: string;
  const AOutputPath: string; const AAutoRun: Boolean);
var
  LSourceFile: string;
  LOutputFilename: string;
  LVendorDir: string;
  LVendorSub: string;
begin
  FErrors.Clear();
  DoClearModules();
  FFaviconPath := '';
  FSourceMap.Clear();

  try
    // Normalize source file extension and resolve path
    LSourceFile := TUtils.ResolvePath(
      TPath.ChangeExtension(ASourceFile, WKL_SRCFILE_EXT));

    if not TFile.Exists(LSourceFile) then
    begin
      FErrors.Add(esFatal, WKL_ERR_CMP_001,
        'Source file not found: %s', [LSourceFile]);
      Exit;
    end;

    FOutputPath := TUtils.ResolvePath(AOutputPath);

    // Fire pre-parse callbacks (CLI stores key-values here)
    DoFirePreParseCallbacks();

    // Default module search path
    AddModulePath(TUtils.ResolvePath(WKL_RES_STD_DIR));

    // Each vendor library lives in its own folder beside its LICENSE
    LVendorDir := TUtils.ResolvePath(WKL_RES_VENDOR_DIR);
    if TDirectory.Exists(LVendorDir) then
      for LVendorSub in TDirectory.GetDirectories(LVendorDir) do
        AddModulePath(LVendorSub);

    // Phase 1: Parse
    Status('Parsing %s...', [TPath.GetFileName(LSourceFile)]);
    FModule := FParser.ParseModule(FLexer, LSourceFile);

    if FErrors.HasErrors() then
      Exit;

    if FModule = nil then
    begin
      FErrors.Add(esFatal, WKL_ERR_CMP_001,
        'Parser returned no module', []);
      Exit;
    end;

    // Phase 1.5: Parse and analyze imported units
    DoCompileImportedUnits();

    if FErrors.HasErrors() then
      Exit;

    // Phase 2: Semantic analysis
    Status('Analyzing...');
    FSemantics.Analyze(FLexer, FModule);

    if FErrors.HasErrors() then
      Exit;

    // Process directives from enriched AST (after semantics)
    Status('Processing directives...');
    DoProcessDirectives();

    // Apply CLI directive overrides from key-value store
    DoCLIDirectives();

    if FErrors.HasErrors() then
      Exit;

    // Fire pre-build callbacks
    DoFirePreBuildCallbacks();

    // Unit modules: validate only, no codegen or build
    if DoValidateUnitModule() then
      Exit;

    // Resolve external library files (.wasm/.js) and register with build
    DoResolveExternalLibs();

    if FErrors.HasErrors() then
      Exit;

    // Phase 3: Code generation via TWklEmitter
    DoEmitCode();

    if FErrors.HasErrors() then
      Exit;

    // Phase 4: Build via TWklBuild (wasm-opt + JS bundle + HTML package)
    LOutputFilename := TPath.Combine(FOutputPath, FModule.Name);

    if FModule.ModuleKind = mkExe then
      FBuild.TargetExe(LOutputFilename)
    else
      FBuild.TargetLib(LOutputFilename);

    // Favicon
    if FFaviconPath <> '' then
      FBuild.SetFavicon(FFaviconPath);

    if not FBuild.Build(False) then
      Exit;

    // Run the built artifact if requested
    if DoValidateAutoRun(AAutoRun) then
      Run();

  except
    on E: Exception do
    begin
      if not FErrors.HasErrors() then
        FErrors.Add(esFatal, WKL_ERR_CMP_001,
          'Internal compiler error: %s', [E.Message]);
    end;
  end;
end;

function TWklCompiler.Run(): Boolean;
var
  LExitCode: Cardinal;
begin
  LExitCode := 0;
  Result := FBuild.Run(@LExitCode);
  FLastExitCode := LExitCode;
end;

procedure TWklCompiler.SetOptimizeLevel(const ALevel: Integer);
begin
  FBuild.SetOptimizationLevel(ALevel);
end;

procedure TWklCompiler.SetDefine(const ADefineName: string);
begin
  FParser.SetDefine(ADefineName, '1');
end;

procedure TWklCompiler.SetDefine(const ADefineName: string;
  const AValue: string);
begin
  FParser.SetDefine(ADefineName, AValue);
end;

procedure TWklCompiler.SetDefines(const ADefineNames: array of string);
var
  I: Integer;
begin
  for I := 0 to Length(ADefineNames) - 1 do
    FParser.SetDefine(ADefineNames[I], '1');
end;

procedure TWklCompiler.UnsetDefine(const ADefineName: string);
begin
  FParser.Undefine(ADefineName);
end;

procedure TWklCompiler.RemoveUndefine(const ADefineName: string);
begin
  FParser.Undefine(ADefineName);
end;

procedure TWklCompiler.ClearUndefines();
begin
  // No bulk clear on parser -- individual Undefine calls are the mechanism
end;

procedure TWklCompiler.AddModulePath(const APath: string);
begin
  if APath <> '' then
    FModulePaths.Add(APath);
end;

procedure TWklCompiler.AddLibraryPath(const APath: string);
begin
  FBuild.AddLibPath(TUtils.ResolvePath(APath));
end;

procedure TWklCompiler.AddPreParseCallback(
  const ACallback: TWklPreParseCallback; const AUserData: Pointer);
var
  LEntry: TWklPreParseCallbackEntry;
begin
  LEntry.Callback := ACallback;
  LEntry.UserData := AUserData;
  FPreParseCallbacks.Add(LEntry);
end;

procedure TWklCompiler.ClearPreParseCallbacks();
begin
  FPreParseCallbacks.Clear();
end;

procedure TWklCompiler.AddPreBuildCallback(
  const ACallback: TWklPreBuildCallback; const AUserData: Pointer);
var
  LEntry: TWklPreBuildCallbackEntry;
begin
  LEntry.Callback := ACallback;
  LEntry.UserData := AUserData;
  FPreBuildCallbacks.Add(LEntry);
end;

procedure TWklCompiler.ClearPreBuildCallbacks();
begin
  FPreBuildCallbacks.Clear();
end;

procedure TWklCompiler.SetKeyValue(const AKey: string; const AValue: string);
begin
  FKeyValues.AddOrSetValue(AKey, AValue);
end;

function TWklCompiler.GetKeyValue(const AKey: string;
  const ADefault: string): string;
begin
  if not FKeyValues.TryGetValue(AKey, Result) then
    Result := ADefault;
end;

procedure TWklCompiler.ClearKeyValue(const AKey: string);
begin
  FKeyValues.Remove(AKey);
end;

function TWklCompiler.GetLastExitCode(): DWORD;
begin
  Result := FLastExitCode;
end;

function TWklCompiler.GetOutputPath(): string;
begin
  Result := FOutputPath;
end;

function TWklCompiler.GetOptimizeLevel(): Integer;
begin
  Result := FBuild.GetOptimizationLevel();
end;

function TWklCompiler.GetOutputFilename(): string;
begin
  Result := FBuild.GetOutputPath();
end;

end.
