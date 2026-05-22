@echo off
:: oem/install.bat — runs ONCE, automatically, at the end of the very first
:: Windows install inside a fresh `mise run vm:up`. Dockur's /oem hook copies
:: this file into C:\OEM and executes it as Administrator before anyone signs in.
::
:: Does NOT run on `mise run vm:up-snap` — the snapshot is already past
:: this point. So a fresh provision lands you on a fully-configured VM
:: with zero RDP click-through.
::
:: Generic Windows-host setup only. Per-app installs live in the sibling
:: vm-software repo — that gets git-cloned INSIDE the VM after first boot
:: and drives installs from there.
::
:: Log everything (see C:\OEM\install.log inside the VM, or
:: \\host.lan\Data\install.log via Z: from the host).

set LOG=C:\OEM\install.log
echo === vm-servers oem/install.bat starting %DATE% %TIME% === > "%LOG%"

:: 1. Map the shared folder as a persistent Z: drive so File Explorer
::    shows it without typing \\host.lan\Data every time.
echo Mapping Z: -> \\host.lan\Data >> "%LOG%"
net use Z: \\host.lan\Data /persistent:yes >> "%LOG%" 2>&1

:: 2. Windows Defender exclusions on hot paths. Real-time scanning of the
::    shared folder would kill TCG-already-slow throughput. Generic paths
::    only — per-app folders can be added by the relevant vm-software
::    install task.
echo Adding Defender exclusions >> "%LOG%"
powershell -NoProfile -Command "Add-MpPreference -ExclusionPath 'Z:\jobs','Z:\output','Z:\installers'" >> "%LOG%" 2>&1

:: 3. Don't sleep, don't hibernate, don't blank the screen. A remote VM
::    should stay responsive 24x7.
echo Disabling sleep / standby / monitor blank >> "%LOG%"
powercfg /change standby-timeout-ac 0 >> "%LOG%" 2>&1
powercfg /change monitor-timeout-ac 0 >> "%LOG%" 2>&1
powercfg /hibernate off >> "%LOG%" 2>&1

echo === oem/install.bat done %DATE% %TIME% === >> "%LOG%"
