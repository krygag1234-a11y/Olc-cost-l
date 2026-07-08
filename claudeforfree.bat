@echo off
setlocal EnableExtensions

title Claude Code via OmniRoute

REM ============================================================
REM USER CONFIG
REM ============================================================

REM 1) Вставьте сюда Base URL из OmniRoute -> API / Endpoints.
REM Для Claude Code обычно нужен URL БЕЗ /v1.
REM Пример: http://localhost:20128
set "OMNI_BASE_URL=http://localhost:20128"

REM 2) Вставьте сюда API Key из OmniRoute.
set "OMNI_API_KEY=sk-99b0b41468612f0c-80d2f3-2466c498"

REM 3) Вставьте сюда модель или combo из OmniRoute.
REM Примеры: kr/claude-sonnet-4.5 или free-combo
set "CLAUDE_MAIN_MODEL=kr/claude-sonnet-4.5"

REM 4) Быстрая модель для фоновых задач.
REM Можно оставить Haiku или поставить тот же combo.
set "CLAUDE_FAST_MODEL=kr/claude-haiku-4.5"

REM 5) Команда запуска OmniRoute.
REM Обычно достаточно: omniroute
set "OMNI_COMMAND=omniroute"

REM 6) Сколько секунд ждать запуска OmniRoute.
set "WAIT_TIMEOUT=90"

REM ============================================================
REM INTERNAL CONFIG
REM ============================================================

REM Достаем порт из OMNI_BASE_URL автоматически.
REM Работает для адресов вида:
REM http://localhost:20128
REM http://127.0.0.1:20128
REM http://localhost:3000
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='%OMNI_BASE_URL%'; try { ([Uri]$u).Port } catch { -1 }"`) do set "OMNI_PORT=%%P"

for /f "usebackq delims=" %%H in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='%OMNI_BASE_URL%'; try { ([Uri]$u).Host } catch { 'localhost' }"`) do set "OMNI_HOST=%%H"

if "%OMNI_PORT%"=="-1" (
    echo [ERROR] Cannot read port from OMNI_BASE_URL.
    echo Check this line in the bat file:
    echo OMNI_BASE_URL=%OMNI_BASE_URL%
    echo.
    pause
    exit /b 1
)

if "%OMNI_PORT%"=="" (
    echo [ERROR] Cannot read port from OMNI_BASE_URL.
    echo Check this line in the bat file:
    echo OMNI_BASE_URL=%OMNI_BASE_URL%
    echo.
    pause
    exit /b 1
)

REM Для проверки порта localhost надежнее проверять 127.0.0.1
if /I "%OMNI_HOST%"=="localhost" set "OMNI_CHECK_HOST=127.0.0.1"
if not defined OMNI_CHECK_HOST set "OMNI_CHECK_HOST=%OMNI_HOST%"

REM ============================================================
REM BASIC CHECKS
REM ============================================================

if "%OMNI_API_KEY%"=="PASTE_YOUR_OMNIROUTE_KEY_HERE" (
    echo [ERROR] You forgot to add your OmniRoute API key.
    echo.
    echo Open this file in Notepad and replace:
    echo PASTE_YOUR_OMNIROUTE_KEY_HERE
    echo.
    pause
    exit /b 1
)

where omniroute >nul 2>nul
if errorlevel 1 (
    echo [ERROR] OmniRoute is not installed or not found in PATH.
    echo.
    echo Install it with:
    echo npm install -g omniroute@latest
    echo.
    pause
    exit /b 1
)

where claude >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Claude Code is not installed or not found in PATH.
    echo.
    echo Install it with:
    echo winget install Anthropic.ClaudeCode
    echo.
    pause
    exit /b 1
)

REM ============================================================
REM START OMNIROUTE IF NEEDED
REM ============================================================

call :PortOpen "%OMNI_CHECK_HOST%" "%OMNI_PORT%"

if errorlevel 1 (
    echo [INFO] OmniRoute is not running on %OMNI_BASE_URL%
    echo [INFO] Starting OmniRoute...

    start "OmniRoute" /min cmd /d /c "cd /d ""%USERPROFILE%"" && %OMNI_COMMAND%"
) else (
    echo [OK] OmniRoute is already running on %OMNI_BASE_URL%
)

REM ============================================================
REM WAIT FOR OMNIROUTE PORT
REM ============================================================

echo [INFO] Waiting for OmniRoute to become ready...
echo [INFO] Host: %OMNI_CHECK_HOST%
echo [INFO] Port: %OMNI_PORT%

set /a ELAPSED=0

:WAIT_LOOP
call :PortOpen "%OMNI_CHECK_HOST%" "%OMNI_PORT%"

if not errorlevel 1 goto OMNI_READY

if %ELAPSED% GEQ %WAIT_TIMEOUT% (
    echo [ERROR] OmniRoute did not start within %WAIT_TIMEOUT% seconds.
    echo.
    echo Check the OmniRoute window and try again.
    echo.
    pause
    exit /b 1
)

timeout /t 2 /nobreak >nul
set /a ELAPSED+=2
goto WAIT_LOOP

:OMNI_READY
echo [OK] OmniRoute is ready: %OMNI_BASE_URL%

REM ============================================================
REM SET CLAUDE CODE VARIABLES
REM ============================================================

REM Для Claude Code Base URL берем из OmniRoute.
REM Обычно он должен быть БЕЗ /v1.
set "ANTHROPIC_BASE_URL=%OMNI_BASE_URL%"

REM Не добавляйте Bearer руками. Claude Code сам добавит Bearer.
set "ANTHROPIC_AUTH_TOKEN=%OMNI_API_KEY%"

REM Модель / combo из OmniRoute.
set "ANTHROPIC_MODEL=%CLAUDE_MAIN_MODEL%"

REM Значения по умолчанию для выбора моделей в Claude Code.
set "ANTHROPIC_DEFAULT_SONNET_MODEL=%CLAUDE_MAIN_MODEL%"
set "ANTHROPIC_DEFAULT_OPUS_MODEL=%CLAUDE_MAIN_MODEL%"
set "ANTHROPIC_DEFAULT_HAIKU_MODEL=%CLAUDE_FAST_MODEL%"

REM Старый параметр для быстрых фоновых задач.
set "ANTHROPIC_SMALL_FAST_MODEL=%CLAUDE_FAST_MODEL%"

REM Чтобы прямой Anthropic key не конфликтовал с gateway.
set "ANTHROPIC_API_KEY="
set "CLAUDE_CODE_OAUTH_TOKEN="

REM Чтобы localhost не уходил через proxy/VPN.
set "NO_PROXY=localhost,127.0.0.1"
set "no_proxy=localhost,127.0.0.1"

echo.
echo [INFO] Starting Claude Code through OmniRoute...
echo [INFO] Base URL: %ANTHROPIC_BASE_URL%
echo [INFO] Main model: %ANTHROPIC_MODEL%
echo.

claude --resume 90c863da-cac4-43df-9244-baba3d9997db --permission-mode bypassPermissions %*

exit /b %ERRORLEVEL%

REM ============================================================
REM FUNCTION: CHECK IF PORT IS OPEN
REM ============================================================

:PortOpen
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$client = New-Object Net.Sockets.TcpClient; try { $iar = $client.BeginConnect('%~1', [int]%~2, $null, $null); if (-not $iar.AsyncWaitHandle.WaitOne(1500, $false)) { $client.Close(); exit 1 }; $client.EndConnect($iar); $client.Close(); exit 0 } catch { exit 1 }" >nul 2>nul

exit /b %ERRORLEVEL%