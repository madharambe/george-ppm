@echo off
setlocal
set SWIFTROOT=%LOCALAPPDATA%\Programs\Swift
set TOOLCHAIN=%SWIFTROOT%\Toolchains\6.4.2+Asserts\usr\bin
set RUNTIME=%SWIFTROOT%\Runtimes\6.4.2\usr\bin
set SDK=%SWIFTROOT%\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk

call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

set PATH=%TOOLCHAIN%;%RUNTIME%;%PATH%

set BUILD=D:\Android\swiftbuild
if not exist "%BUILD%" mkdir "%BUILD%"
copy /Y "George PPM\ios\GeorgePPM\Telemetry.swift" "%BUILD%\" >nul
copy /Y "George PPM\ios\GeorgePPM\TelemetryFormatter.swift" "%BUILD%\" >nul
copy /Y "George PPM\ios\GeorgePPM\BleSpec.swift" "%BUILD%\" >nul
copy /Y "George PPM\ios\GeorgePPM\SyntheticTelemetry.swift" "%BUILD%\" >nul
copy /Y "George PPM\tests\swift\main.swift" "%BUILD%\" >nul

cd /d "%BUILD%"
echo SDK: %SDK%
echo.
echo === compiling (with -sdk) ===
swiftc -sdk "%SDK%" Telemetry.swift TelemetryFormatter.swift BleSpec.swift SyntheticTelemetry.swift main.swift -o harness.exe
if errorlevel 1 (
  echo COMPILE FAILED
  exit /b 1
)
echo compile OK
echo.
echo === running harness ===
harness.exe
