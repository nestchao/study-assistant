@echo off
echo Starting Development Environment...

:: 1. Backend (Flask API)
start powershell -NoExit -Command "cd backend; .\venv\Scripts\activate; python app.py"

:: 2. Frontend (Flutter Web)
start powershell -NoExit -Command "cd frontend; flutter run -d edge"

:: 3. Celery Worker (Background Tasks)
start powershell -NoExit -Command "cd backend; .\venv\Scripts\activate; celery -A tasks worker --loglevel=info --pool=solo"

:: 4. Default Terminal (Root Directory)
start powershell -NoExit -Command "echo 'Ready for commands...'"

echo All services started!