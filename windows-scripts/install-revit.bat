@echo off
:: install-revit.bat — run from inside the Windows VM once.
::
:: Prereq:
::   `mise run software:fetch-revit` has staged the installer at
::   \\host.lan\Data\installers\Revit_Installer.exe and copied THIS
::   script to \\host.lan\Data\install-revit.bat. Read it from there
::   (or copy locally first if your installer demands a non-UNC path).
::
:: After this finishes:
::   1. Revit will launch and show the Autodesk sign-in dialog.
::   2. Sign in with the account that owns the trial. ONE TIME.
::   3. Quit Revit cleanly.
::   4. On the Mac: `mise run snapshot:create`.
::      Every future `mise run vm:up-snap` boots already-signed-in.
::
:: Silent-install flags vary by Revit installer flavour:
::   - Standalone installer (2024+): typical flags `-silent` or
::     `-q -i deploy -o "<config.ini>"`
::   - Autodesk Access bootstrapper: usually no silent mode; falls back
::     to GUI. In that case omit /silent and click through.
::   - Deployment image (created via Autodesk Deployment Tool): silent
::     by design when launched with no args.
::
:: This template tries silent first, falls back to interactive on failure.

setlocal
set INSTALLER=\\host.lan\Data\installers\Revit_Installer.exe

if not exist "%INSTALLER%" (
    echo ERROR: installer not found at %INSTALLER%
    echo Run `mise run software:fetch-revit` on the Mac first.
    pause
    exit /b 1
)

echo Running %INSTALLER% silently (Ctrl-C to abort)...
"%INSTALLER%" -silent

if errorlevel 1 (
    echo Silent flag rejected. Falling back to interactive install.
    "%INSTALLER%"
)

echo.
echo Installer exited. Launch Revit from the Start menu to trigger
echo the one-time Autodesk sign-in (trial registration), then quit.
echo Back on the Mac: `mise run snapshot:create`.
pause
endlocal
