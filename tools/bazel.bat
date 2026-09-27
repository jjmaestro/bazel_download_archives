@echo off
setlocal

rem Windows counterpart of tools/bazel: Bazelisk on Windows runs .bat (or .ps1)
rem wrappers, not the extensionless shell script.

if "%BAZEL_REAL%"=="" (
    echo BAZEL_REAL must be set in the environment 1>&2
    exit /b 1
)

"%BAZEL_REAL%" %*
set "STATUS=%ERRORLEVEL%"

if not "%STATUS%"=="4" exit /b %STATUS%

rem NOTE:
rem "no test targets" error (exit code 4) is allowed for "bazel test"
:args
if "%~1"=="" exit /b %STATUS%
if /i "%~1"=="test" (
    echo INFO: ignoring 'no test targets found' error
    exit /b 0
)
shift
goto args
