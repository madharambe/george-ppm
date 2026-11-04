@echo off
setlocal
set SWIFTROOT=%LOCALAPPDATA%\Programs\Swift
set TOOLCHAIN=%SWIFTROOT%\Toolchains\6.4.2+Asserts\usr\bin
set RUNTIME=%SWIFTROOT%\Runtimes\6.4.2\usr\bin
set SDK=%SWIFTROOT%\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
set PATH=%TOOLCHAIN%;%RUNTIME%;%PATH%
set SDKROOT=%SDK%

cd /d D:\Android\xcodegen\XcodeGen-2.46.0
git config --global core.symlinks false
echo === swift build (reusing existing checkouts) ===
swift build -c release --disable-sandbox 2>&1
set BUILD_EXIT=%ERRORLEVEL%
git config --global --unset core.symlinks
echo.
echo EXITCODE=%BUILD_EXIT%
if exist ".build\release\xcodegen.exe" ( echo FOUND xcodegen.exe )
