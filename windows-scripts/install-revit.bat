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
echo Revit installer exited. Now installing Revit Batch Processor (RBP)
echo so it can drop its per-Revit-version addins.
if exist "\\host.lan\Data\installers\RevitBatchProcessorSetup.exe" (
    "\\host.lan\Data\installers\RevitBatchProcessorSetup.exe" /VERYSILENT
) else (
    echo RBP installer not found at \\host.lan\Data\installers\RevitBatchProcessorSetup.exe
    echo Run `mise run software:fetch` on the Mac to stage it, then re-run this script.
)

echo.
echo Launch Revit from the Start menu to trigger the one-time Autodesk
echo sign-in (trial registration), then quit. Back on the Mac:
echo `mise run snapshot:create`.
pause
endlocal
