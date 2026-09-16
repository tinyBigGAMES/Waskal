{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.Build - Wasm64 build pipeline driver

  Takes .wat text from the emitter and produces the final output artifact:
    exe -> .html (self-contained, base64-encoded wasm + minified JS)
    lib -> .wasm (standalone module)
    dll -> reserved for future use
    unit -> no output (validated at compile time only)

  Pipeline:
    .wat -> wasm-opt (assemble + optimize) -> .wasm
    .wasm + external .wasm -> wasm-merge -> merged .wasm (if externals exist)
    wasi64_shim.js + external .js -> esbuild (combine + minify) -> bundled .js
    .wasm (base64) + .js -> inject into index.html template -> output .html

  External tools (bin/res/wasm/):
    wasm-opt.exe   -- .wat to optimized .wasm in one step
    wasm-merge.exe -- merges multiple .wasm into one
    esbuild.exe    -- combines and minifies JS files

  Dependencies: StdApp.Base, StdApp.Utils, Waskal.Common, Waskal.AST
===============================================================================}

unit Waskal.Build;

{$I StdApp.Defines.inc}

interface

uses
  System.Types,
  System.SysUtils,
  System.Generics.Collections,
  System.Classes,
  System.IOUtils,
  System.NetEncoding,
  System.ZLib,
  Winapi.Windows,
  StdApp.Base,
  StdApp.Resources,
  StdApp.Utils,
  Waskal.Common,
  Waskal.AST;

const
  // Error codes
  WKL_ERR_BUILD_001 = 'BUILD001';  // Tool not found
  WKL_ERR_BUILD_002 = 'BUILD002';  // Tool execution failed
  WKL_ERR_BUILD_003 = 'BUILD003';  // File I/O error
  WKL_ERR_BUILD_004 = 'BUILD004';  // Template error

  // Wasm features
  WKL_WASM_FEATURES = '--enable-memory64 --enable-bulk-memory ' +
    '--enable-nontrapping-float-to-int --enable-exception-handling ' +
    '--enable-multivalue';

type
  { TWklAssetEntry }
  TWklAssetEntry = record
    Key: string;
    FilePath: string;
    MimeType: string;
  end;

  { TWklBuild }
  TWklBuild = class(TBaseObject)
  protected
    FOutputPath: string;
    FProjectName: string;
    FModuleKind: TWklModuleKind;
    FOptimizeLevel: Integer;
    FWatSource: string;
    FLibPaths: TStringList;
    FExternalJsFiles: TDictionary<string, string>;  // module name -> file path
    FExternalWasmFiles: TStringList;
    FAssetFiles: TList<TWklAssetEntry>;
    FAssetManifestJson: string;
    FAssetDataBase64: string;
    FAssetRuntimeJs: string;
    FToolPath: string;
    FOutputFilename: string;
    FLastExitCode: DWORD;
    FFaviconPath: string;
    FWatSourceMap: TWklSourceMap;  // WAT line -> .wkl source, set by compiler

    // Pipeline steps
    function DoWriteWat(): string;
    function DoAssembleWat(const AWatFile: string): string;
    function DoMergeWasm(const AWasmFile: string): string;
    function DoCollectJs(): string;
    function DoBundleJs(const ARawJs: string): string;
    function DoPackageHtml(const AWasmFile: string;
      const AJsBundle: string): Boolean;
    function DoGetOptFlags(): string;
    function DoGetOptDescription(): string;
    function DoGetToolPath(const AToolName: string): string;
    function DoBase64EncodeFile(const AFilePath: string): string;
    procedure DoParseWasmOptErrors(const ALines: TStringList);
    function DoDetectMime(const AFilePath: string): string;
    procedure DoPackAssets(out AManifestJson: string;
      out ADataBase64: string);
    function DoCollectAssetJs(const AManifestJson: string;
      const ADataBase64: string): string;
    function DoFindAssetRoot(const ASourceNorm: string;
      const ABaseNorm: string; out ARootDir: string): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Build configuration
    procedure SetOptimizationLevel(const AValue: Integer);
    function GetOptimizationLevel(): Integer;
    procedure AddLibPath(const APath: string);
    procedure AddExternalJs(const AModuleName: string; const APath: string);
    procedure AddExternalWasm(const APath: string);

    // Asset embedding
    procedure AddAsset(const AKey: string; const AFilePath: string);
    procedure AddAssetPath(const ASourcePath: string;
      const ABaseFolder: string; const APattern: string);

    // Target configuration
    procedure TargetExe(const APath: string);
    procedure TargetLib(const APath: string);

    // Emitter handoff
    procedure SetWatSource(const AWat: string);
    procedure SetWatSourceMap(const AMap: TWklSourceMap);

    // Favicon
    procedure SetFavicon(const APath: string);

    // Build and run
    function Build(const AAutoRun: Boolean): Boolean;
    function Run(AExitCode: PCardinal = nil): Boolean;
    function GetOutputPath(): string;

    property LibPaths: TStringList read FLibPaths;
  end;

implementation

{ TWklBuild }
constructor TWklBuild.Create();
begin
  inherited;

  FLibPaths := TStringList.Create();
  FLibPaths.Duplicates := dupIgnore;
  FExternalJsFiles := TDictionary<string, string>.Create();
  FExternalWasmFiles := TStringList.Create();
  FExternalWasmFiles.Duplicates := dupIgnore;
  FAssetFiles := TList<TWklAssetEntry>.Create();
  FModuleKind := mkExe;
  FOptimizeLevel := 0;
  FLastExitCode := 0;

  // Tool path: bin/res/wasm/ relative to the running executable
  FToolPath := TUtils.ResolvePath(WKL_RES_WASM_PATH);
end;

destructor TWklBuild.Destroy();
begin

  FAssetFiles.Free();
  FExternalWasmFiles.Free();
  FExternalJsFiles.Free();
  FLibPaths.Free();

  inherited;
end;

procedure TWklBuild.SetOptimizationLevel(const AValue: Integer);
begin
  FOptimizeLevel := AValue;
end;

function TWklBuild.GetOptimizationLevel(): Integer;
begin
  Result := FOptimizeLevel;
end;

procedure TWklBuild.AddLibPath(const APath: string);
begin
  if APath <> '' then
    FLibPaths.Add(APath);
end;

procedure TWklBuild.AddExternalJs(const AModuleName: string;
  const APath: string);
begin
  if (AModuleName <> '') and (APath <> '') then
    FExternalJsFiles.AddOrSetValue(AModuleName, APath);
end;

procedure TWklBuild.AddExternalWasm(const APath: string);
begin
  if APath <> '' then
    FExternalWasmFiles.Add(APath);
end;

procedure TWklBuild.TargetExe(const APath: string);
begin
  FModuleKind := mkExe;
  FOutputPath := TPath.GetDirectoryName(TPath.GetFullPath(APath));
  FProjectName := TPath.GetFileNameWithoutExtension(APath);
  FOutputFilename := TPath.Combine(FOutputPath, FProjectName + '.html');
end;

procedure TWklBuild.TargetLib(const APath: string);
begin
  FModuleKind := mkLib;
  FOutputPath := TPath.GetDirectoryName(TPath.GetFullPath(APath));
  FProjectName := TPath.GetFileNameWithoutExtension(APath);
  FOutputFilename := TPath.Combine(FOutputPath, FProjectName + '.wasm');
end;

procedure TWklBuild.SetWatSource(const AWat: string);
begin
  FWatSource := AWat;
end;

procedure TWklBuild.SetWatSourceMap(const AMap: TWklSourceMap);
begin
  FWatSourceMap := AMap;
end;

{ TWklBuild }
procedure TWklBuild.SetFavicon(const APath: string);
begin
  FFaviconPath := APath;
end;

function TWklBuild.GetOutputPath(): string;
begin
  Result := FOutputFilename;
end;

function TWklBuild.DoGetToolPath(const AToolName: string): string;
begin
  Result := TPath.Combine(FToolPath, AToolName);
end;

function TWklBuild.DoGetOptFlags(): string;
begin
  case FOptimizeLevel of
    0: Result := '';
    1: Result := '-O1';
    2: Result := '-O2';
    3: Result := '-O3';
    4: Result := '-O4';
    5: Result := '-Os';
    6: Result := '-Oz';
  else
    Result := '';
  end;
end;

function TWklBuild.DoGetOptDescription(): string;
begin
  case FOptimizeLevel of
    0: Result := 'none (no optimization)';
    1: Result := '1 (quick and useful, good for iteration builds)';
    2: Result := '2 (most optimizations, generally best performance)';
    3: Result := '3 (aggressive, may take significant time)';
    4: Result := '4 (aggressive + IR flattening, high time and memory)';
    5: Result := 's (default optimizations, focusing on code size)';
    6: Result := 'z (default optimizations, super-focusing on code size)';
  else
    Result := 'unknown';
  end;
end;

function TWklBuild.DoWriteWat(): string;
var
  LWatFile: string;
begin
  Result := '';

  LWatFile := TPath.Combine(FOutputPath, FProjectName + '.wat');
  TUtils.CreateDirInPath(LWatFile);

  try
    TFile.WriteAllBytes(LWatFile, TEncoding.UTF8.GetBytes(FWatSource));
    Result := LWatFile;
    Status('Wrote %s', [TPath.GetFileName(LWatFile)]);
  except
    on E: Exception do
    begin
      FErrors.Add(esFatal, WKL_ERR_BUILD_003,
        RSBldWatWriteFailed, [E.Message]);
    end;
  end;
end;

function TWklBuild.DoAssembleWat(const AWatFile: string): string;
var
  LWasmOpt: string;
  LWasmFile: string;
  LParams: string;
  LExitCode: DWORD;
  LCapturedLines: TStringList;
begin
  Result := '';

  LWasmOpt := DoGetToolPath('wasm-opt.exe');
  if not TFile.Exists(LWasmOpt) then
  begin
    FErrors.Add(esFatal, WKL_ERR_BUILD_001,
      RSBldWasmOptNotFound, [LWasmOpt]);
    Exit;
  end;

  LWasmFile := TPath.ChangeExtension(AWatFile, '.wasm');

  // Build command: wasm-opt input.wat -o output.wasm [features] [opt level]
  LParams := Format('"%s" -o "%s" %s', [AWatFile, LWasmFile, WKL_WASM_FEATURES]);

  // Add optimization flags if any
  if DoGetOptFlags() <> '' then
    LParams := LParams + ' ' + DoGetOptFlags();

  Status('Assembling %s...', [TPath.GetFileName(AWatFile)]);

  LCapturedLines := TStringList.Create();
  try
    try
      TUtils.CaptureConsoleOutput(
        '',
        PChar(LWasmOpt),
        PChar(LParams),
        FOutputPath,
        LExitCode,
        Pointer(LCapturedLines),
        procedure(const ALine: string; const AUserData: Pointer)
        begin
          TStringList(AUserData).Add(ALine);
        end
      );
    except
      on E: Exception do
      begin
        FErrors.Add(esFatal, WKL_ERR_BUILD_002,
          RSBldWasmOptStartFailed, [E.Message]);
        Exit;
      end;
    end;

    if LExitCode <> 0 then
    begin
      DoParseWasmOptErrors(LCapturedLines);
      Exit;
    end;
  finally
    LCapturedLines.Free();
  end;

  if not TFile.Exists(LWasmFile) then
  begin
    FErrors.Add(esError, WKL_ERR_BUILD_002,
      RSBldWasmOptNoOutput, [LWasmFile]);
    Exit;
  end;

  Status('Assembled %s (%d bytes)',
    [TPath.GetFileName(LWasmFile), TFile.GetSize(LWasmFile)]);
  Result := LWasmFile;
end;

{ TWklBuild.DoMergeWasm }
function TWklBuild.DoMergeWasm(const AWasmFile: string): string;
var
  LMergeTool: string;
  LMergedFile: string;
  LParams: string;
  LExitCode: DWORD;
  LCapturedLines: TStringList;
  I: Integer;
  LExtPath: string;
  LModuleName: string;
begin
  Result := '';

  // No externals -- nothing to merge, pass through
  if FExternalWasmFiles.Count = 0 then
  begin
    Result := AWasmFile;
    Exit;
  end;

  LMergeTool := DoGetToolPath('wasm-merge.exe');
  if not TFile.Exists(LMergeTool) then
  begin
    FErrors.Add(esFatal, WKL_ERR_BUILD_001,
      RSBldWasmMergeNotFound, [LMergeTool]);
    Exit;
  end;

  LMergedFile := TPath.Combine(FOutputPath, 'output.wasm');

  // Build command: compiled module first, then each external
  LParams := Format('"%s" "%s"', [AWasmFile, FProjectName]);

  for I := 0 to FExternalWasmFiles.Count - 1 do
  begin
    LExtPath := FExternalWasmFiles[I];
    LModuleName := TPath.GetFileNameWithoutExtension(LExtPath);
    LParams := LParams + Format(' "%s" "%s"', [LExtPath, LModuleName]);
  end;

  LParams := LParams + Format(' -o "%s" --skip-export-conflicts %s',
    [LMergedFile, WKL_WASM_FEATURES]);

  Status('Merging %d external wasm module(s)...', [FExternalWasmFiles.Count]);

  LCapturedLines := TStringList.Create();
  try
    try
      TUtils.CaptureConsoleOutput(
        '',
        PChar(LMergeTool),
        PChar(LParams),
        FOutputPath,
        LExitCode,
        Pointer(LCapturedLines),
        procedure(const ALine: string; const AUserData: Pointer)
        begin
          TStringList(AUserData).Add(ALine);
        end
      );
    except
      on E: Exception do
      begin
        FErrors.Add(esFatal, WKL_ERR_BUILD_002,
          RSBldWasmMergeStartFailed, [E.Message]);
        Exit;
      end;
    end;

    if LExitCode <> 0 then
    begin
      // Report captured output as errors
      for I := 0 to LCapturedLines.Count - 1 do
      begin
        if LCapturedLines[I].Trim() <> '' then
          FErrors.Add(esError, WKL_ERR_BUILD_002,
            RSBldWasmMergeError, [LCapturedLines[I]]);
      end;
      if FErrors.Count = 0 then
        FErrors.Add(esError, WKL_ERR_BUILD_002,
          RSBldWasmMergeExitCode, [LExitCode]);
      Exit;
    end;
  finally
    LCapturedLines.Free();
  end;

  if not TFile.Exists(LMergedFile) then
  begin
    FErrors.Add(esError, WKL_ERR_BUILD_002,
      RSBldWasmMergeNoOutput, [LMergedFile]);
    Exit;
  end;

  Status('Merged %d module(s) -> %s (%d bytes)',
    [FExternalWasmFiles.Count, TPath.GetFileName(AWasmFile),
     TFile.GetSize(LMergedFile)]);

  // Replace the pre-merge .wasm with the merged result
  TFile.Copy(LMergedFile, AWasmFile, True);
  TFile.Delete(LMergedFile);

  Result := AWasmFile;
end;

function TWklBuild.DoBase64EncodeFile(const AFilePath: string): string;
var
  LBytes: TBytes;
begin
  LBytes := TFile.ReadAllBytes(AFilePath);
  Result := TNetEncoding.Base64.EncodeBytesToString(LBytes);
  Result := Result.Replace(#13#10, '').Replace(#10, '').Replace(#13, '');
end;

procedure TWklBuild.DoParseWasmOptErrors(const ALines: TStringList);
var
  LI: Integer;
  LLine: string;
  LRest: string;
  LColonPos: Integer;
  LWatLine: Integer;
  LMessage: string;
  LRange: TSourceRange;
  LMapped: Boolean;
begin
  // Parse wasm-opt error lines and map WAT line numbers back to .wkl source.
  // Format: "Fatal: <filepath>:<line>:<col>: error: <message>"
  // We look for lines containing "error:" and extract the WAT line number.
  LMapped := False;
  for LI := 0 to ALines.Count - 1 do
  begin
    LLine := ALines[LI].Trim();
    if LLine = '' then
      Continue;

    // Try to extract WAT line number from "Fatal: path:LINE:COL: error: msg"
    // Skip the "Fatal: " prefix if present
    LRest := LLine;
    if LRest.StartsWith('Fatal: ') then
      LRest := LRest.Substring(7);

    // Find the filepath:line:col pattern -- skip to after the filepath
    // The filepath ends at the first colon followed by a digit
    LWatLine := -1;
    LMessage := LLine;

    // Walk past the filepath to find :LINE:COL: pattern
    // Look for :<digits>:<digits>: which is the line:col portion
    LColonPos := LRest.LastIndexOf(': error:');
    if LColonPos >= 0 then
    begin
      LMessage := LRest.Substring(LColonPos + 9).Trim();
      // Now parse backwards from LColonPos to find line:col
      LRest := LRest.Substring(0, LColonPos);
      // LRest is now "filepath:LINE:COL"
      // Split from the right to extract col and line
      LColonPos := LRest.LastIndexOf(':');
      if LColonPos >= 0 then
      begin
        // Strip col, get "filepath:LINE"
        LRest := LRest.Substring(0, LColonPos);
        LColonPos := LRest.LastIndexOf(':');
        if LColonPos >= 0 then
          TryStrToInt(LRest.Substring(LColonPos + 1), LWatLine);
      end;
    end;

    // Map WAT line to .wkl source if we have a source map
    if (LWatLine > 0) and Assigned(FWatSourceMap) and
       (LWatLine - 1 < FWatSourceMap.Count) then
    begin
      LRange := FWatSourceMap[LWatLine - 1];  // WAT lines are 1-based
      if LRange.Filename <> '' then
      begin
        FErrors.Add(LRange.Filename, LRange.StartLine, LRange.StartColumn,
          esError, WKL_ERR_BUILD_002, LMessage);
        LMapped := True;
        Continue;
      end;
    end;

    // Fallback - no mapping (runtime line, or parse failure)
    FErrors.Add(esError, WKL_ERR_BUILD_002,
      RSBldWasmOptError, [LLine]);
    LMapped := True;
  end;

  // If no lines were captured at all, report generic failure
  if not LMapped then
    FErrors.Add(esError, WKL_ERR_BUILD_002,
      RSBldWasmOptFailedNoOut);
end;

function TWklBuild.DoCollectJs(): string;
var
  LShimPath: string;
  LPair: TPair<string, string>;
begin
  Result := '';

  // Always include the JS runtime (WASI shim + asset system)
  LShimPath := DoGetToolPath('runtime.js');
  if not TFile.Exists(LShimPath) then
  begin
    FErrors.Add(esFatal, WKL_ERR_BUILD_003,
      RSBldJsRuntimeNotFound, [LShimPath]);
    Exit;
  end;

  Result := TFile.ReadAllText(LShimPath);

  // Append external JS files
  for LPair in FExternalJsFiles do
  begin
    if TFile.Exists(LPair.Value) then
      Result := Result + sLineBreak + TFile.ReadAllText(LPair.Value)
    else
      FErrors.Add(esWarning, WKL_ERR_BUILD_003,
        RSBldExternalJsNotFound, [LPair.Value]);
  end;
end;

function TWklBuild.DoBundleJs(const ARawJs: string): string;
var
  LEsbuild: string;
  LInputFile: string;
  LOutputFile: string;
  LParams: string;
  LExitCode: Cardinal;
begin
  Result := ARawJs;

  LEsbuild := DoGetToolPath('esbuild.exe');
  if not TFile.Exists(LEsbuild) then
  begin
    FErrors.Add(esWarning, WKL_ERR_BUILD_001,
      RSBldEsbuildNotFound, [LEsbuild]);
    Exit;
  end;

  // Write raw JS to temp file
  LInputFile := TPath.Combine(FOutputPath, FProjectName + '_bundle.js');
  LOutputFile := TPath.Combine(FOutputPath, FProjectName + '_bundle.min.js');

  try
    TFile.WriteAllBytes(LInputFile, TEncoding.UTF8.GetBytes(ARawJs));
  except
    on E: Exception do
    begin
      FErrors.Add(esWarning, WKL_ERR_BUILD_003,
        RSBldJsTempWriteFailed, [E.Message]);
      Exit;
    end;
  end;

  // Run esbuild --minify
  LParams := Format('"%s" --minify --legal-comments=inline --outfile="%s"', [LInputFile, LOutputFile]);
  Status('Minifying JS bundle...');

  try
    LExitCode := TUtils.RunPE(LEsbuild, LParams, FOutputPath, True, SW_HIDE);
  except
    on E: Exception do
    begin
      FErrors.Add(esWarning, WKL_ERR_BUILD_002,
        RSBldEsbuildStartFailed, [E.Message]);
      Exit;
    end;
  end;

  if LExitCode <> 0 then
  begin
    FErrors.Add(esWarning, WKL_ERR_BUILD_002,
      RSBldEsbuildExitCode, [LExitCode]);
    Exit;
  end;

  if not TFile.Exists(LOutputFile) then
  begin
    FErrors.Add(esWarning, WKL_ERR_BUILD_002,
      RSBldEsbuildNoOutput);
    Exit;
  end;

  // Read minified output
  try
    Result := TFile.ReadAllText(LOutputFile, TEncoding.UTF8);
    Status('JS minified (%d -> %d bytes)',
      [Length(ARawJs), Length(Result)]);
  except
    on E: Exception do
    begin
      FErrors.Add(esWarning, WKL_ERR_BUILD_003,
        RSBldMinifiedJsReadFailed, [E.Message]);
      // Result stays as ARawJs (graceful fallback)
    end;
  end;

  // Clean up temp files
  if TFile.Exists(LInputFile) then
    TFile.Delete(LInputFile);
  if TFile.Exists(LOutputFile) then
    TFile.Delete(LOutputFile);
end;

function TWklBuild.DoDetectMime(const AFilePath: string): string;
var
  LExt: string;
begin
  LExt := TPath.GetExtension(AFilePath).ToLower();
  if LExt = '.png' then Result := 'image/png'
  else if LExt = '.jpg' then Result := 'image/jpeg'
  else if LExt = '.jpeg' then Result := 'image/jpeg'
  else if LExt = '.gif' then Result := 'image/gif'
  else if LExt = '.svg' then Result := 'image/svg+xml'
  else if LExt = '.webp' then Result := 'image/webp'
  else if LExt = '.ico' then Result := 'image/x-icon'
  else if LExt = '.ogg' then Result := 'audio/ogg'
  else if LExt = '.mp3' then Result := 'audio/mpeg'
  else if LExt = '.wav' then Result := 'audio/wav'
  else if LExt = '.json' then Result := 'application/json'
  else if LExt = '.txt' then Result := 'text/plain'
  else if LExt = '.html' then Result := 'text/html'
  else if LExt = '.css' then Result := 'text/css'
  else if LExt = '.js' then Result := 'text/javascript'
  else if LExt = '.wasm' then Result := 'application/wasm'
  else if LExt = '.xml' then Result := 'text/xml'
  else if LExt = '.glsl' then Result := 'text/plain'
  else if LExt = '.vert' then Result := 'text/plain'
  else if LExt = '.frag' then Result := 'text/plain'
  else if LExt = '.ttf' then Result := 'font/ttf'
  else if LExt = '.otf' then Result := 'font/otf'
  else if LExt = '.woff' then Result := 'font/woff'
  else if LExt = '.woff2' then Result := 'font/woff2'
  else if LExt = '.mp4' then Result := 'video/mp4'
  else if LExt = '.webm' then Result := 'video/webm'
  else Result := 'application/octet-stream';
end;

procedure TWklBuild.AddAsset(const AKey: string; const AFilePath: string);
var
  LEntry: TWklAssetEntry;
  LI: Integer;
begin
  // Check for duplicate key
  for LI := 0 to FAssetFiles.Count - 1 do
  begin
    if FAssetFiles[LI].Key = AKey then
    begin
      FErrors.Add(esError, WKL_ERR_BUILD_003,
        RSBldDuplicateAssetKey, [AKey]);
      Exit;
    end;
  end;

  if not TFile.Exists(AFilePath) then
  begin
    FErrors.Add(esError, WKL_ERR_BUILD_003,
      RSBldAssetFileNotFound, [AFilePath]);
    Exit;
  end;

  LEntry.Key := AKey.Replace('\', '/');
  LEntry.FilePath := AFilePath;
  LEntry.MimeType := DoDetectMime(AFilePath);
  FAssetFiles.Add(LEntry);
end;

function TWklBuild.DoFindAssetRoot(const ASourceNorm: string;
  const ABaseNorm: string; out ARootDir: string): Boolean;
var
  LSrcSegs: TArray<string>;
  LBaseSegs: TArray<string>;
  LStart: Integer;
  LI: Integer;
  LMatch: Boolean;
begin
  Result := False;
  ARootDir := '';
  LSrcSegs := ASourceNorm.Split(['/']);
  LBaseSegs := ABaseNorm.Split(['/']);
  if (Length(LBaseSegs) = 0) or (Length(LBaseSegs) > Length(LSrcSegs)) then
    Exit;

  // Scan from the deepest possible position backwards so the occurrence
  // nearest the files wins (e.g. a parent folder also named "assets")
  for LStart := Length(LSrcSegs) - Length(LBaseSegs) downto 0 do
  begin
    LMatch := True;
    for LI := 0 to Length(LBaseSegs) - 1 do
    begin
      if not SameText(LSrcSegs[LStart + LI], LBaseSegs[LI]) then
      begin
        LMatch := False;
        Break;
      end;
    end;
    if LMatch then
    begin
      // Root = everything before the base segment; keys are relative to it
      ARootDir := string.Join('/', Copy(LSrcSegs, 0, LStart));
      Result := True;
      Exit;
    end;
  end;
end;

procedure TWklBuild.AddAssetPath(const ASourcePath: string;
  const ABaseFolder: string; const APattern: string);
var
  LFiles: TStringDynArray;
  LFile: string;
  LFileFull: string;
  LSourceNorm: string;
  LBaseNorm: string;
  LRootDir: string;
  LKey: string;
begin
  if not TDirectory.Exists(ASourcePath) then
  begin
    FErrors.Add(esError, WKL_ERR_BUILD_003,
      RSBldAssetDirNotFound, [ASourcePath]);
    Exit;
  end;

  LSourceNorm := TPath.GetFullPath(ASourcePath).Replace('\', '/').TrimRight(['/']);
  LBaseNorm := ABaseFolder.Replace('\', '/').Trim(['/']);

  if not DoFindAssetRoot(LSourceNorm, LBaseNorm, LRootDir) then
  begin
    FErrors.Add(esError, WKL_ERR_BUILD_003,
      RSBldAssetBaseNotInPath, [ABaseFolder, ASourcePath]);
    Exit;
  end;

  LFiles := TDirectory.GetFiles(ASourcePath, APattern,
    TSearchOption.soAllDirectories);
  for LFile in LFiles do
  begin
    LFileFull := TPath.GetFullPath(LFile);
    // Every file lives under the source dir, which lives under the root,
    // so stripping the root prefix (+ its slash) yields the virtual key
    LKey := LFileFull.Replace('\', '/').Substring(Length(LRootDir) + 1);
    AddAsset(LKey, LFileFull);
  end;
end;

procedure TWklBuild.DoPackAssets(out AManifestJson: string;
  out ADataBase64: string);
var
  LBlob: TBytesStream;
  LCompressed: TBytesStream;
  LGzip: TCompressionStream;
  LFileBytes: TBytes;
  LEntry: TWklAssetEntry;
  LManifest: TStringBuilder;
  LOffset: Int64;
  LFirst: Boolean;
  LRawSize: Int64;
  LCompSize: Int64;
begin
  AManifestJson := '{}';
  ADataBase64 := '';

  if FAssetFiles.Count = 0 then
    Exit;

  LBlob := TBytesStream.Create();
  LManifest := TStringBuilder.Create();
  try
    LManifest.Append('{');
    LFirst := True;

    for LEntry in FAssetFiles do
    begin
      LFileBytes := TFile.ReadAllBytes(LEntry.FilePath);
      LOffset := LBlob.Size;
      LBlob.WriteBuffer(LFileBytes[0], Length(LFileBytes));

      if not LFirst then
        LManifest.Append(',');
      LManifest.Append(Format('"%s":{"offset":%d,"size":%d,"mime":"%s"}',
        [LEntry.Key, LOffset, Length(LFileBytes), LEntry.MimeType]));
      LFirst := False;
    end;

    LManifest.Append('}');
    AManifestJson := LManifest.ToString();
    LRawSize := LBlob.Size;

    // Gzip compress the blob
    LCompressed := TBytesStream.Create();
    try
      LGzip := TCompressionStream.Create(clDefault, LCompressed);
      try
        LGzip.WriteBuffer(LBlob.Bytes[0], LBlob.Size);
      finally
        LGzip.Free();
      end;
      LCompSize := LCompressed.Size;

      Status('Assets: %d file(s), %d bytes raw, %d bytes compressed (%.0f%% saved)',
        [FAssetFiles.Count, LRawSize, LCompSize,
         (1.0 - LCompSize / LRawSize) * 100]);

      // Base64 encode the compressed blob (no line breaks for JS embedding)
      ADataBase64 := TNetEncoding.Base64.EncodeBytesToString(
        LCompressed.Bytes, LCompressed.Size);
      ADataBase64 := ADataBase64.Replace(#13#10, '').Replace(#10, '').Replace(#13, '');
    finally
      LCompressed.Free();
    end;
  finally
    LManifest.Free();
    LBlob.Free();
  end;
end;

function TWklBuild.DoCollectAssetJs(const AManifestJson: string;
  const ADataBase64: string): string;
var
  LJsPath: string;
begin
  Result := '';
  if FAssetFiles.Count = 0 then
    Exit;

  LJsPath := DoGetToolPath('waskal_assets.js');
  if not TFile.Exists(LJsPath) then
  begin
    FErrors.Add(esWarning, WKL_ERR_BUILD_003,
      RSBldAssetRuntimeNotFound, [LJsPath]);
    Exit;
  end;

  Result := TFile.ReadAllText(LJsPath);
  Result := Result.Replace('__WKL_ASSET_MANIFEST__', AManifestJson);
  Result := Result.Replace('__WKL_ASSET_DATA__', ADataBase64);
end;

function TWklBuild.DoPackageHtml(const AWasmFile: string;
  const AJsBundle: string): Boolean;
var
  LTemplatePath: string;
  LHtml: string;
  LWasmBase64: string;
  LFaviconB64: string;
  LFaviconTag: string;
  LExtraImports: string;
  LPair: TPair<string, string>;
begin
  Result := False;

  LTemplatePath := DoGetToolPath('index.html');
  if not TFile.Exists(LTemplatePath) then
  begin
    FErrors.Add(esFatal, WKL_ERR_BUILD_004,
      RSBldHtmlTemplateNotFound, [LTemplatePath]);
    Exit;
  end;

  // Read template
  LHtml := TFile.ReadAllText(LTemplatePath);

  // Base64 encode the wasm binary
  Status('Encoding wasm binary...');
  LWasmBase64 := DoBase64EncodeFile(AWasmFile);

  // Build extra wasm import entries for external JS libs
  LExtraImports := '';
  for LPair in FExternalJsFiles do
    LExtraImports := LExtraImports + ',' + sLineBreak +
      '    ' + LPair.Key + ': ' + LPair.Key;

  // Replace placeholders
  LHtml := LHtml.Replace('__WKL_WASM_MODULE__', FProjectName);
  LHtml := LHtml.Replace('__WKL_WASI64_SHIM__', AJsBundle);
  LHtml := LHtml.Replace('__WKL_WASM_BASE64__', LWasmBase64);
  LHtml := LHtml.Replace('__WKL_EXTRA_IMPORTS__', LExtraImports);

  // Replace asset placeholders (inside the JS bundle)
  LHtml := LHtml.Replace('__WKL_ASSET_MANIFEST__', FAssetManifestJson);
  LHtml := LHtml.Replace('"__WKL_ASSET_DATA__"', '"' + FAssetDataBase64 + '"');

  // Favicon injection
  if (FFaviconPath <> '') and FileExists(FFaviconPath) then
  begin
    LFaviconB64 := DoBase64EncodeFile(FFaviconPath);
    if FFaviconPath.EndsWith('.png', True) then
      LFaviconTag := Format(
        '<link rel="icon" type="image/png" href="data:image/png;base64,%s">',
        [LFaviconB64])
    else
      LFaviconTag := Format(
        '<link rel="icon" type="image/x-icon" href="data:image/x-icon;base64,%s">',
        [LFaviconB64]);
    LHtml := LHtml.Replace('__WKL_FAVICON__', LFaviconTag);
    Status('Favicon: %s', [TPath.GetFileName(FFaviconPath)]);
  end
  else
  begin
    if (FFaviconPath <> '') and not FileExists(FFaviconPath) then
      FErrors.Add(esWarning, WKL_ERR_BUILD_003,
        RSBldFaviconNotFound, [FFaviconPath]);
    LHtml := LHtml.Replace('__WKL_FAVICON__', '');
  end;

  // Write output
  try
    TUtils.CreateDirInPath(FOutputFilename);
    TFile.WriteAllText(FOutputFilename, LHtml, TEncoding.UTF8);
    Status('Output: %s', [FOutputFilename]);
    Result := True;
  except
    on E: Exception do
    begin
      FErrors.Add(esFatal, WKL_ERR_BUILD_003,
        RSBldOutputWriteFailed, [E.Message]);
    end;
  end;
end;

function TWklBuild.Build(const AAutoRun: Boolean): Boolean;
var
  LWatFile: string;
  LWasmFile: string;
  LJsBundle: string;
begin
  Result := False;

  if FWatSource = '' then
  begin
    FErrors.Add(esFatal, WKL_ERR_BUILD_003, RSBldNoWatSource);
    Exit;
  end;

  Status('Building %s...', [FProjectName]);
  Status('Optimization: %s', [DoGetOptDescription()]);

  // Step 1: Write .wat to disk
  LWatFile := DoWriteWat();
  if LWatFile = '' then
    Exit;

  // Step 2: Assemble .wat -> .wasm via wasm-opt
  LWasmFile := DoAssembleWat(LWatFile);
  if LWasmFile = '' then
    Exit;

  // Step 2b: Merge external .wasm modules (if any)
  LWasmFile := DoMergeWasm(LWasmFile);
  if LWasmFile = '' then
    Exit;

  // Step 3: Package based on module kind
  case FModuleKind of
    mkExe:
    begin
      // Collect and minify JS (runtime + external)
      LJsBundle := DoBundleJs(DoCollectJs());
      if LJsBundle = '' then
        Exit;

      // Pack embedded assets (if any)
      FAssetManifestJson := '{}';
      FAssetDataBase64 := '';
      if FAssetFiles.Count > 0 then
        DoPackAssets(FAssetManifestJson, FAssetDataBase64);

      // Package into .html
      if not DoPackageHtml(LWasmFile, LJsBundle) then
        Exit;
    end;

    mkLib:
    begin
      // For lib/dll, the .wasm IS the output -- just copy to final name
      // if it's not already there
      if not SameText(LWasmFile, FOutputFilename) then
      begin
        try
          TFile.Copy(LWasmFile, FOutputFilename, True);
        except
          on E: Exception do
          begin
            FErrors.Add(esFatal, WKL_ERR_BUILD_003,
              RSBldWasmCopyFailed, [E.Message]);
            Exit;
          end;
        end;
      end;
      Status('Output: %s', [FOutputFilename]);
    end;
  end;

  Status('Build succeeded.');
  Result := True;

  // Auto-run if requested
  if AAutoRun then
    Run();
end;

function TWklBuild.Run(AExitCode: PCardinal): Boolean;
begin
  Result := False;

  if FModuleKind <> mkExe then
  begin
    FErrors.Add(esError, WKL_ERR_BUILD_002,
      RSBldOnlyExeCanRun);
    Exit;
  end;

  if not TFile.Exists(FOutputFilename) then
  begin
    FErrors.Add(esError, WKL_ERR_BUILD_002,
      RSBldOutputNotFound, [FOutputFilename]);
    Exit;
  end;

  Status('Running %s...', [TPath.GetFileName(FOutputFilename)]);
  Result := TUtils.ShellOpen(FOutputFilename, FOutputPath);

  // Browser-based execution has no meaningful exit code
  if Assigned(AExitCode) then
    AExitCode^ := 0;
end;



end.
