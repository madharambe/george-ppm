@echo off
setlocal
set SWIFTROOT=%LOCALAPPDATA%\Programs\Swift
set TOOLCHAIN=%SWIFTROOT%\Toolchains\6.4.2+Asserts\usr\bin
set RUNTIME=%SWIFTROOT%\Runtimes\6.4.2\usr\bin
set SDK=%SWIFTROOT%\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set PATH=%TOOLCHAIN%;%RUNTIME%;%PATH%
set SDKROOT=%SDK%

set PKG=D:\Android\swiftpm-test
if exist "%PKG%" rmdir /s /q "%PKG%"
mkdir "%PKG%\Sources\Hello"
cd /d "%PKG%"

> Package.swift echo // swift-tools-version:5.9
>> Package.swift echo import PackageDescription
>> Package.swift echo let package = Package(
>> Package.swift echo     name: "Hello",
>> Package.swift echo     targets: [.executableTarget(name: "Hello", path: "Sources/Hello")]
>> Package.swift echo )

> Sources\Hello\main.swift echo print("swiftpm works")

echo === swift --version ===
swift --version
echo.
echo === swift build ===
swift build 2>&1
echo.
echo === run ===
swift run 2>&1
