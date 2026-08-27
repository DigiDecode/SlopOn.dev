@echo off
rem SlopOn launcher wrapper (Windows): resolve a Node runtime and run the
rem shared launcher core. Prefers the bundled node-runtime installed by
rem install.ps1; falls back to Node on PATH.
setlocal
set "DIR=%~dp0"

if exist "%DIR%..\node-runtime\node.exe" (
  "%DIR%..\node-runtime\node.exe" "%DIR%launcher.mjs" %*
  exit /b %ERRORLEVEL%
)

where node >nul 2>nul
if errorlevel 1 (
  echo error: Node.js not found on PATH - re-run the SlopOn installer to provision a bundled runtime, or install Node 20/22 and retry.
  exit /b 1
)

node "%DIR%launcher.mjs" %*
exit /b %ERRORLEVEL%
