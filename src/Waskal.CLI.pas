{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Waskal.CLI - Command-line front-end

  Parses command-line arguments, configures the compiler, runs the full
  pipeline. Single entry point: TWklCLI.Execute().

  Dependencies: Waskal.Compiler, StdApp.Console
===============================================================================}

unit Waskal.CLI;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Console,
  Waskal.Common,
  Waskal.Compiler;

type
  { TWklCLI }
  TWklCLI = class
  private
    FCompiler: TWklCompiler;
    FSourceFile: string;
    FAutoRun: Boolean;
    FOutputPath: string;
    FOptLevel: string;
    procedure ShowBanner();
    procedure ShowHelp();
    procedure ShowErrors();
    procedure SetupCallbacks();
    function ParseArgs(): Boolean;
    procedure DoCompile();
  public
    constructor Create();
    destructor Destroy(); override;
    procedure Execute();
  end;

implementation

uses
  System.Classes,
  StdApp.Base,
  StdApp.Utils;

{ TWklCLI }
constructor TWklCLI.Create();
begin
  inherited Create();

  FCompiler := TWklCompiler.Create();
  FSourceFile := '';
  FAutoRun := False;
  FOutputPath := '';
  FOptLevel := '';
end;

destructor TWklCLI.Destroy();
begin
  FreeAndNil(FCompiler);

  inherited;
end;

procedure TWklCLI.ShowBanner();
var
  LVerInfo: TVersionInfo;
begin
  LVerInfo := Default(TVersionInfo);
  TUtils.GetVersionInfo(LVerInfo);

  TConsole.PrintLn(COLOR_WHITE + COLOR_BOLD +
    Format('%s v%s', [LVerInfo.ProductName, LVerInfo.VersionString]));
  TConsole.PrintLn(COLOR_WHITE +
    Format('%s, All Rights Reserved.', [LVerInfo.Copyright]));
  TConsole.PrintLn(COLOR_YELLOW + LVerInfo.URL);
  TConsole.PrintLn('');
end;

procedure TWklCLI.ShowHelp();
var
  LExeName: string;
begin
  LExeName := TPath.GetFileNameWithoutExtension(ParamStr(0));

  TConsole.PrintLn(COLOR_BOLD + 'USAGE:');
  TConsole.PrintLn('  ' + LExeName + ' ' + COLOR_CYAN +
    '<source>' + COLOR_RESET + ' [OPTIONS]');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'REQUIRED:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '<source>' + COLOR_RESET +
    '                  Waskal source file (.wkl)');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'OPTIONS:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-r, --run              ' + COLOR_RESET +
    '  Run after building (opens .html in default browser)');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-o, --output    <path>  ' + COLOR_RESET +
    '  Set output directory');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-opt, --optimize <level>' + COLOR_RESET +
    '  Set optimize level: none (default), 1, 2, 3, 4, s, z');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-h, --help             ' + COLOR_RESET +
    '  Display this help message');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'EXAMPLES:');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r -opt 3');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -o dist');
  TConsole.PrintLn('');
end;

procedure TWklCLI.ShowErrors();
begin
  FCompiler.PrintErrors();
end;

procedure TWklCLI.SetupCallbacks();
begin
  FCompiler.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      TConsole.PrintLn(AText);
    end, nil);
end;

function TWklCLI.ParseArgs(): Boolean;
var
  LI: Integer;
  LFlag: string;
begin
  Result := True;

  if ParamCount() = 0 then
  begin
    ShowHelp();
    Result := False;
    Exit;
  end;

  LI := 1;
  while LI <= ParamCount() do
  begin
    LFlag := ParamStr(LI).Trim();

    if (LFlag = '-h') or (LFlag = '--help') then
    begin
      ShowHelp();
      Result := False;
      Exit;
    end
    else if (LFlag = '-r') or (LFlag = '--run') then
    begin
      FAutoRun := True;
    end
    else if (LFlag = '-o') or (LFlag = '--output') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires a path argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FOutputPath := ParamStr(LI).Trim();
    end
    else if (LFlag = '-opt') or (LFlag = '--optimize') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires an optimize level argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FOptLevel := ParamStr(LI).Trim();
    end
    else if LFlag.StartsWith('-') then
    begin
      TConsole.PrintLn(COLOR_RED + 'Error: Unknown flag: ' +
        COLOR_YELLOW + LFlag);
      TConsole.PrintLn('');
      TConsole.PrintLn('Run ' + COLOR_CYAN +
        TPath.GetFileNameWithoutExtension(ParamStr(0)) + ' -h' +
        COLOR_RESET + ' to see available options');
      TConsole.PrintLn('');
      ExitCode := 2;
      Result := False;
      Exit;
    end
    else
    begin
      // Positional argument: source file
      if FSourceFile = '' then
        FSourceFile := LFlag
      else
      begin
        TConsole.PrintLn(COLOR_RED +
          'Error: Unexpected argument: ' + COLOR_YELLOW + LFlag);
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
    end;

    Inc(LI);
  end;

  // Validate: source file is required
  if FSourceFile = '' then
  begin
    TConsole.PrintLn(COLOR_RED +
      'Error: Source file is required');
    TConsole.PrintLn('');
    TConsole.PrintLn('Run ' + COLOR_CYAN +
      TPath.GetFileNameWithoutExtension(ParamStr(0)) + ' -h' +
      COLOR_RESET + ' to see available options');
    TConsole.PrintLn('');
    ExitCode := 2;
    Result := False;
    Exit;
  end;

  // Normalize source file extension
  FSourceFile := TUtils.ResolvePath(
    TPath.ChangeExtension(FSourceFile, WKL_SRCFILE_EXT));

  // Validate: source file must exist
  if not TFile.Exists(FSourceFile) then
  begin
    TConsole.PrintLn(COLOR_RED +
      'Error: Source file not found: ' + COLOR_YELLOW + FSourceFile);
    TConsole.PrintLn('');
    ExitCode := 2;
    Result := False;
    Exit;
  end;
end;

procedure TWklCLI.DoCompile();
var
  LOutputPath: string;
begin
  SetupCallbacks();

  // Inject CLI overrides into the compiler's key-value store
  if FOptLevel <> '' then
    FCompiler.SetKeyValue('optimize', FOptLevel);
  if FOutputPath <> '' then
    FCompiler.SetKeyValue('outputpath', FOutputPath);

  // Determine output path
  if FOutputPath <> '' then
    LOutputPath := TUtils.ResolvePath(FOutputPath)
  else
    LOutputPath := TUtils.ResolvePath('output');

  // Compile
  FCompiler.Compile(FSourceFile, LOutputPath, FAutoRun);

  // Display errors
  ShowErrors();

  if FCompiler.HasErrors() then
  begin
    TConsole.PrintLn(COLOR_RED + 'Failed.');
    ExitCode := 1;
  end
  else
    ExitCode := FCompiler.GetLastExitCode();
end;

procedure TWklCLI.Execute();
begin
  ShowBanner();

  if not ParseArgs() then
    Exit;

  try
    DoCompile();
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + COLOR_BOLD + 'Fatal Error: ' +
        E.Message + COLOR_RESET);
      TConsole.PrintLn('');
      ExitCode := 1;
    end;
  end;
end;

end.
