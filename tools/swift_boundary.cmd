@echo off
setlocal
set SWIFTROOT=%LOCALAPPDATA%\Programs\Swift
set TOOLCHAIN=%SWIFTROOT%\Toolchains\6.4.2+Asserts\usr\bin
set RUNTIME=%SWIFTROOT%\Runtimes\6.4.2\usr\bin
set SDK=%SWIFTROOT%\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set PATH=%TOOLCHAIN%;%RUNTIME%;%PATH%
set SRC=C:\Users\nicho\OneDrive\Desktop\Projects_deepseek\Tugas Kuliah\George PPM\ios\GeorgePPM
cd /d D:\Android\swiftbuild
copy /Y "%SRC%\*.swift" . >nul 2>&1

echo === Foundation-only group (typechecked together) ===
swiftc -sdk "%SDK%" -typecheck Telemetry.swift TelemetryFormatter.swift BleSpec.swift SyntheticTelemetry.swift Dashboard.swift >nul 2>&1
if errorlevel 1 ( echo   GROUP FAILED ) else ( echo   Telemetry TelemetryFormatter BleSpec SyntheticTelemetry Dashboard : ALL COMPILE )

echo.
echo === Apple-framework files (expected to fail on Windows) ===
for %%F in (BleCentral.swift Simulator.swift ContentView.swift GeorgePPMApp.swift) do (
  swiftc -sdk "%SDK%" -typecheck Telemetry.swift TelemetryFormatter.swift BleSpec.swift SyntheticTelemetry.swift Dashboard.swift %%F >nul 2>&1
  if errorlevel 1 ( echo   %%F : needs Apple frameworks ) else ( echo   %%F : COMPILES )
)
