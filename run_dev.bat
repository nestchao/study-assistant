@echo off
cd /d "%~dp0\backend"
start "Backend" cmd /c "call venv\Scripts\activate && python app.py"
timeout /t 3 >nul
cd ..\frontend
flutter run -d edge --hot
pause