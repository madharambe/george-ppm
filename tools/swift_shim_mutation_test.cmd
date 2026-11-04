@echo off
setlocal
set SWIFTROOT=%LOCALAPPDATA%\Programs\Swift
set TOOLCHAIN=%SWIFTROOT%\Toolchains\6.4.2+Asserts\usr\bin
set RUNTIME=%SWIFTROOT%\Runtimes\6.4.2\usr\bin
set SDK=%SWIFTROOT%\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set PATH=%TOOLCHAIN%;%RUNTIME%;%PATH%
cd /d D:\Android\swiftbuild-shim

echo === mutation test: the shim must REJECT broken code ===

echo [1] misspelled modifier (.foregroundColour)
powershell -NoProfile -Command "(Get-Content ContentView.swift -Raw) -replace 'foregroundColor','foregroundColour' | Set-Content Mutant1.swift"
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift Dashboard.swift SyntheticTelemetry.swift Simulator.swift BleCentral.swift Mutant1.swift GeorgePPMApp.swift >nul 2>&1
if errorlevel 1 ( echo   CAUGHT ) else ( echo   MISSED - shim is too permissive )

echo [2] wrong argument label (.padding(hv: 4))
powershell -NoProfile -Command "(Get-Content ContentView.swift -Raw) -replace '\.padding\(16\)','.padding(hv: 16)' | Set-Content Mutant2.swift"
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift Dashboard.swift SyntheticTelemetry.swift Simulator.swift BleCentral.swift Mutant2.swift GeorgePPMApp.swift >nul 2>&1
if errorlevel 1 ( echo   CAUGHT ) else ( echo   MISSED - shim is too permissive )

echo [3] type error: passing a Double where a String is required
powershell -NoProfile -Command "(Get-Content ContentView.swift -Raw) -replace 'Text\(dash\.flow\)','Text(3.14)' | Set-Content Mutant3.swift"
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift Dashboard.swift SyntheticTelemetry.swift Simulator.swift BleCentral.swift Mutant3.swift GeorgePPMApp.swift >nul 2>&1
if errorlevel 1 ( echo   CAUGHT ) else ( echo   MISSED - shim is too permissive )

echo [4] missing import in BleCentral (the real bug found earlier)
powershell -NoProfile -Command "(Get-Content BleCentral.swift -Raw) -replace 'import Combine','' | Set-Content Mutant4.swift"
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift Dashboard.swift SyntheticTelemetry.swift Mutant4.swift >nul 2>&1
if errorlevel 1 ( echo   CAUGHT ) else ( echo   MISSED - shim is too permissive )

del Mutant*.swift >nul 2>&1
echo.
echo === unmodified sources still pass ===
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift Dashboard.swift SyntheticTelemetry.swift Simulator.swift BleCentral.swift ContentView.swift GeorgePPMApp.swift
if errorlevel 1 ( echo   FAILED ) else ( echo   ALL 9 FILES OK )
