{===============================================================================
  Waskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://waskal.org

  See LICENSE for license information
===============================================================================}

unit UWaskal;

{$I StdApp.Defines.inc}

interface

procedure RunCLI();

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Console,
  Waskal.CLI;

procedure RunCLI();
var
  LCLI: TWklCLI;
begin
 try
    ExitCode := 0;
    LCLI := TWklCLI.Create();
    try
      LCLI.Execute();
    finally
      LCLI.Free();
    end;
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: ' + E.Message + COLOR_RESET);
    end;
  end;
end;

end.
