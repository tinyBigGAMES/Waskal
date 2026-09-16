{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
===============================================================================}

program waskal;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UWaskal in 'UWaskal.pas',
  StdApp.Resources in '..\..\src\StdApp.Resources.pas',
  Waskal.AST in '..\..\src\Waskal.AST.pas',
  Waskal.Build in '..\..\src\Waskal.Build.pas',
  Waskal.CLI in '..\..\src\Waskal.CLI.pas',
  Waskal.Common in '..\..\src\Waskal.Common.pas',
  Waskal.Compiler in '..\..\src\Waskal.Compiler.pas',
  Waskal.Emitter in '..\..\src\Waskal.Emitter.pas',
  Waskal.Lexer in '..\..\src\Waskal.Lexer.pas',
  Waskal.Parser in '..\..\src\Waskal.Parser.pas',
  Waskal.Semantics in '..\..\src\Waskal.Semantics.pas';

begin
  ReportMemoryLeaksOnShutdown := True;
  RunCLI();
end.
