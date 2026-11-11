@echo off
rem arnet.dll for STORROR Active Ragdoll: build with the MSVC Build Tools (as SM64Map's sm64net.dll)
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul
cd /d "%~dp0"
cl /nologo /O2 /MT /LD /EHsc /std:c++17 arnet.cpp user32.lib /Fe:arnet.dll
