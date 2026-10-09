@echo off
rem Offline checks of mod-loot-filter; run from the module root.
rem %1 = AzerothCore root for Define.h (default ..\..\azerothcore-wotlk next to
rem the worktree, else the operator box checkout). Writes only into build\.
setlocal
set CORE=%~1
if "%CORE%"=="" set CORE=C:\Users\Anwender\Documents\GitHub\azerothcore-wotlk
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -host_arch=amd64 >nul
if errorlevel 1 exit /b 1
if not exist build mkdir build
cl /nologo /EHsc /std:c++17 /W4 /WX /I "%CORE%\src\common" /Fe:build\rules_test.exe /Fo:build\rules_test.obj tests\rules_test.cpp
if errorlevel 1 exit /b 1
build\rules_test.exe
if errorlevel 1 exit /b 1
if not exist build\lua.exe (
    powershell -NoProfile -Command "Get-ChildItem -LiteralPath 'C:\wowstuff\dcore_bin\_deps\lua52-src\src' -Filter '*.c' | Where-Object { $_.Name -ne 'luac.c' } | ForEach-Object { [char]34 + $_.FullName + [char]34 } | Set-Content -LiteralPath 'build\lua-sources.rsp' -Encoding ascii"
    cl /nologo /TC /W0 /D_CRT_SECURE_NO_WARNINGS /Fe:build\lua.exe /Fo:build\ @build\lua-sources.rsp
    if errorlevel 1 exit /b 1
)
if exist tests\client_test.lua (
    build\lua.exe tests\client_test.lua lua_scripts\LootFilter_Client.lua
    if errorlevel 1 exit /b 1
)
echo offline checks passed
