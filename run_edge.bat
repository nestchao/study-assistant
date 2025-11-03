@echo off
cd /d "%~dp0\frontend"
flutter run -d edge --web-port=5001
pause