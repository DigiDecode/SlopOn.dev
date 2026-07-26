@echo off
setlocal enabledelayedexpansion

rem ---- parse arguments: only --https is valid (AC7) ----
set "BASE_URL=git@github.com:DigiDecode"
:args
if "%~1"=="" goto :argsdone
if /i "%~1"=="--https" (
  set "BASE_URL=https://github.com/DigiDecode"
  shift
  goto :args
)
echo error: unknown argument '%~1' (usage: setup.bat [--https])
exit /b 1
:argsdone

rem ---- AC2: git availability check first ----
where git >nul 2>nul
if errorlevel 1 (
  echo error: git is not installed or not on PATH
  exit /b 1
)

cd /d "%~dp0"
set "FAILED="

call :process slopon_frontend frontend
call :process slopon_backend backend
call :process gpt_markdown gpt_markdown
call :process re-editor re-editor
call :process re-highlight re-highlight

rem ---- final summary ----
echo.
if defined FAILED (
  echo FAILED:!FAILED!
  exit /b 1
)
echo All repositories cloned/updated successfully.
exit /b 0

:process
rem %~1 = github repo name, %~2 = target folder
git -C "%~2" rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 goto :notrepo
echo ^>^>^> %~2: pulling updates
git -C "%~2" pull
if errorlevel 1 set "FAILED=!FAILED! %~2(pull)"
goto :eof

:notrepo
if exist "%~2" (
  echo ^>^>^> %~2: WARNING exists but is not a git repository, skipping
  set "FAILED=!FAILED! %~2(not-a-git-repo)"
  goto :eof
)
echo ^>^>^> %~2: cloning %BASE_URL%/%~1.git
git clone "%BASE_URL%/%~1.git" "%~2"
if errorlevel 1 set "FAILED=!FAILED! %~2(clone)"
goto :eof
