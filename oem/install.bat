@echo off
:: oem/install.bat — runs ONCE, automatically, at the end of the very first
:: Windows install inside a fresh `mise run vm:up`. Dockur's /oem hook
:: copies this file into C:\OEM and executes it as Administrator before
:: anyone signs in.
::
:: Does NOT run on `mise run vm:up-snap` — the snapshot is already past
:: this point. So a fresh provision lands you on a fully-configured VM
:: with zero RDP click-through.
::
:: Log everything (see C:\OEM\install.log inside the VM, or
:: \\host.lan\Data\install.log via Z: from the host).

set LOG=C:\OEM\install.log
echo === vm-servers oem/install.bat starting %DATE% %TIME% === > "%LOG%"

:: 1. Map the shared folder as a persistent Z: drive so File Explorer
::    shows it without typing \\host.lan\Data every time.
echo Mapping Z: -> \\host.lan\Data >> "%LOG%"
net use Z: \\host.lan\Data /persistent:yes >> "%LOG%" 2>&1

:: 2. RBP is staged in Z:\installers\RevitBatchProcessorSetup.exe (by
::    `mise run software:fetch`) but NOT installed here — RBP needs Revit
::    already on disk to drop its per-version addins. install-revit.bat
::    runs the RBP installer after Revit's own setup completes. Just log
::    presence.
if exist "Z:\installers\RevitBatchProcessorSetup.exe" (
  echo RBP installer present in Z:\installers\ — will be run by install-revit.bat after Revit >> "%LOG%"
) else (
  echo RBP installer not staged yet — run `mise run software:fetch` to bring it down >> "%LOG%"
)

:: 3. Windows Defender exclusions on hot paths. Real-time scanning of the
::    shared folder and the batch-job working areas would kill TCG-already-
::    slow throughput.
echo Adding Defender exclusions >> "%LOG%"
powershell -NoProfile -Command "Add-MpPreference -ExclusionPath 'Z:\jobs','Z:\output','Z:\installers','C:\Program Files\Revit Batch Processor'" >> "%LOG%" 2>&1

:: 4. Don't sleep, don't hibernate, don't blank the screen. A batch VM
::    should stay responsive 24x7.
echo Disabling sleep / standby / monitor blank >> "%LOG%"
powercfg /change standby-timeout-ac 0 >> "%LOG%" 2>&1
powercfg /change monitor-timeout-ac 0 >> "%LOG%" 2>&1
powercfg /hibernate off >> "%LOG%" 2>&1

:: 5. If a Revit installer is already staged in the shared folder, run it
::    silently. (Stage it BEFORE `vm:up` via `mise run software:fetch-revit`
::    if you want this to fire on the first boot — otherwise skip and run
::    `\\host.lan\Data\install-revit.bat` manually from RDP later.)
if exist "Z:\installers\Revit_Installer.exe" (
  echo Found Revit_Installer.exe — attempting silent install >> "%LOG%"
  "Z:\installers\Revit_Installer.exe" -silent >> "%LOG%" 2>&1
) else (
  echo Revit_Installer.exe not staged — skipping (run install-revit.bat from RDP later) >> "%LOG%"
)

echo === oem/install.bat done %DATE% %TIME% === >> "%LOG%"
