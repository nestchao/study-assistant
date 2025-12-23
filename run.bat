@echo off
setlocal enabledelayedexpansion

TITLE AI Study Assistant Launcher
cd /d "%~dp0"

echo ========================================================
echo       AI STUDY ASSISTANT - SYSTEM LAUNCHER
echo ========================================================

REM ---------------------------------------------------------
REM 1. CHECK PREREQUISITES
REM ---------------------------------------------------------
echo [1/6] Checking Prerequisites...

where python >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in PATH.
    pause
    exit /b
)

where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Flutter is not installed or not in PATH.
    pause
    exit /b
)

if not exist "firebase-credentials.json" (
    echo [WARNING] 'firebase-credentials.json' not found in root directory!
    echo Backend services will fail to connect.
)

@REM REM ---------------------------------------------------------
@REM REM 2. BACKEND SETUP
@REM REM ---------------------------------------------------------
@REM echo.
@REM echo [2/6] Setting up Backend Environment...

@REM pushd backend

@REM if not exist "venv" (
@REM     echo Creating Python Virtual Environment...
@REM     python -m venv venv
@REM )

@REM echo Activating Virtual Environment...
@REM call venv\Scripts\activate

@REM echo Installing Requirements...
@REM if exist "requirements.txt" (
@REM     pip install -r requirements.txt >nul 2>&1
@REM ) else (
@REM     echo [ERROR] backend/requirements.txt is missing!
@REM     pause
@REM     exit /b
@REM )

REM Return to root
popd

REM ---------------------------------------------------------
REM 3. STARTING SERVICES
REM ---------------------------------------------------------
echo.
echo [3/6] Checking Redis...
echo [INFO] Ensure Redis is running on port 6379.

echo.
echo [4/6] Launching Flask Server...
start "Flask Backend" cmd /k "cd backend && venv\Scripts\activate && python app.py"

echo.
echo [5/6] Launching Celery Worker...
start "Celery Worker" cmd /k "cd backend && venv\Scripts\activate && celery -A tasks worker --loglevel=info --pool=solo"

REM ---------------------------------------------------------
REM 4. FRONTEND SETUP
REM ---------------------------------------------------------
echo.
echo [6/6] Launching Flutter Frontend...

pushd frontend

REM Check if pubspec exists
if not exist "pubspec.yaml" (
    echo [ERROR] frontend/pubspec.yaml is MISSING!
    echo Please create the file before running this script.
    pause
    exit /b
)

REM Create assets folder if missing
if not exist "assets" mkdir assets

REM Create .env file if missing
if not exist "assets\.env" (
    echo [INFO] Creating default .env file...
    echo API_URL=http://127.0.0.1:5000 > assets\.env
)

echo Updating Flutter Dependencies...
call flutter pub get

@REM echo.
@REM echo ==========================================
@REM echo SELECT TARGET DEVICE
@REM echo ==========================================
@REM echo 1. Chrome (Web)
@REM echo 2. Windows Desktop
@REM echo 3. Android Emulator/Device
@REM echo ==========================================
@REM set /p device="Enter choice (1-3): "

@REM if "%device%"=="1" (
@REM     flutter run -d chrome
@REM ) else if "%device%"=="2" (
    flutter run -d windows
@REM ) else (
@REM     flutter run
@REM )

popd

echo.
echo Application session ended.
pause