@echo off
setlocal
set SWIFTROOT=%LOCALAPPDATA%\Programs\Swift
set TOOLCHAIN=%SWIFTROOT%\Toolchains\6.4.2+Asserts\usr\bin
set RUNTIME=%SWIFTROOT%\Runtimes\6.4.2\usr\bin
set SDK=%SWIFTROOT%\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set PATH=%TOOLCHAIN%;%RUNTIME%;%PATH%
cd /d D:\Android\swiftbuild

for %%F in (BleCentral.swift ContentView.swift Simulator.swift GeorgePPMApp.swift) do (
  copy /Y "C:\Users\nicho\OneDrive\Desktop\Projects_deepseek\Tugas Kuliah\George PPM\ios\GeorgePPM\%%F" . >nul 2>&1
  echo === %%F ===
  swiftc -sdk "%SDK%" -typecheck %%F 2>&1 | findstr /C:"error:" | more +0
  if errorlevel 1 echo   (no errors?)
  echo.
)
