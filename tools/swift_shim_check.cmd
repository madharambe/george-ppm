@echo off
setlocal
set SWIFTROOT=%LOCALAPPDATA%\Programs\Swift
set TOOLCHAIN=%SWIFTROOT%\Toolchains\6.4.2+Asserts\usr\bin
set RUNTIME=%SWIFTROOT%\Runtimes\6.4.2\usr\bin
set SDK=%SWIFTROOT%\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set PATH=%TOOLCHAIN%;%RUNTIME%;%PATH%

set SRC=C:\Users\nicho\OneDrive\Desktop\Projects_deepseek\Tugas Kuliah\George PPM
set BUILD=D:\Android\swiftbuild-shim
if not exist "%BUILD%" mkdir "%BUILD%"
if not exist "%BUILD%\mods" mkdir "%BUILD%\mods"
cd /d "%BUILD%"
copy /Y "%SRC%\ios\GeorgePPM\*.swift" . >nul 2>&1
copy /Y "%SRC%\tests\swift\shims\*.swift" . >nul 2>&1

echo === building shim modules ===
swiftc -sdk "%SDK%" -emit-module -module-name Combine -emit-module-path mods\Combine.swiftmodule Combine.swift
if errorlevel 1 ( echo COMBINE SHIM FAILED & exit /b 1 )
swiftc -sdk "%SDK%" -emit-module -module-name CoreBluetooth -emit-module-path mods\CoreBluetooth.swiftmodule CoreBluetooth.swift -I mods
if errorlevel 1 ( echo COREBLUETOOTH SHIM FAILED & exit /b 1 )
swiftc -sdk "%SDK%" -emit-module -module-name SwiftUI -emit-module-path mods\SwiftUI.swiftmodule SwiftUI.swift -I mods
if errorlevel 1 ( echo SWIFTUI SHIM FAILED & exit /b 1 )
echo shim modules OK
echo.

echo === type-check BleCentral ===
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift Dashboard.swift SyntheticTelemetry.swift BleCentral.swift
if errorlevel 1 ( echo FAILED BleCentral ) else ( echo OK BleCentral )

echo === type-check Simulator ===
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift SyntheticTelemetry.swift Simulator.swift
if errorlevel 1 ( echo FAILED Simulator ) else ( echo OK Simulator )

echo === type-check ContentView + App ===
swiftc -sdk "%SDK%" -typecheck -I mods Telemetry.swift TelemetryFormatter.swift BleSpec.swift Dashboard.swift SyntheticTelemetry.swift Simulator.swift BleCentral.swift ContentView.swift GeorgePPMApp.swift
if errorlevel 1 ( echo FAILED ContentView ) else ( echo OK ContentView+App )
