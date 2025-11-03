@echo off
:: =============================================
:: AI Study Assistant - ONE-CLICK LAUNCHER (Windows)
:: =============================================
cd /d "%~dp0"

:: Colors
set GREEN=[92m
set RED=[91m
set YELLOW=[93m
set NC=[0m

echo %GREEN%Starting AI Study Assistant...%NC%

:: === BACKEND ===
echo.
echo %YELLOW%[1/3] Starting Flask Backend...%NC%
cd backend

if not exist "venv" (
    echo %RED%Virtual environment not found! Creating...%NC%
    python -m venv venv
    call venv\Scripts\activate
    pip install --upgrade pip
    pip install -r requirements.txt
) else (
    call venv\Scripts\activate
)

:: Start backend in background
start "Flask Backend" cmd /c "python app.py"

:: Wait for server
timeout /t 3 >nul
echo %GREEN%Backend running at http://127.0.0.1:5000%NC%

:: === FRONTEND ===
echo.
echo %YELLOW%[2/3] Starting Flutter Frontend...%NC%
cd ..\frontend

:: Auto pub get if needed
if not exist "pubspec.lock" (
    echo %YELLOW%Running flutter pub get...%NC%
    flutter pub get
)

:: Run Flutter
echo %YELLOW%[3/3] Launching app...%NC%
flutter run -d edge

pause