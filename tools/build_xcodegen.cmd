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

echo === materialise the SettingPresets resource ===
if not exist "Sources\XcodeGenKit\SettingPresets" (
  xcopy /E /I /Q /Y "SettingPresets" "Sources\XcodeGenKit\SettingPresets" >nul
  echo copied
) else ( echo already present )

echo === allow git to check out without symlinks ===
git config --global core.symlinks false

echo === clean build dir and rebuild ===
if exist ".build" rmdir /s /q ".build"
swift build -c release --disable-sandbox 2>&1
set BUILD_EXIT=%ERRORLEVEL%

echo === restore git config ===
git config --global --unset core.symlinks

echo.
echo EXITCODE=%BUILD_EXIT%
if exist ".build\release\xcodegen.exe" ( echo FOUND xcodegen.exe ) else ( echo NO BINARY )
