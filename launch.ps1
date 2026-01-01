# Synapse-Flow Ground Control Orchestrator v2.5
$ErrorActionPreference = "SilentlyContinue"

# 1. Path Setup
$ROOT = Get-Location
$BIN_DIR = "$ROOT\backend_cpp\build\Release"
$SIG = "SYNAPSE_FLIGHT_ID" # 🚀 THE TRACKING SIGNATURE

Write-Host "`n--- [1/3] ORBITAL PURGE: ELIMINATING SIGNATURE MATCHES ---" -ForegroundColor Red

# 🚀 THE ELITE PURGE: Kill any process whose command line contains our signature
# This is 100% more reliable than window titles.
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$SIG*" } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force
    Write-Host "   - Terminated Signature Match: $($_.ProcessId)" -ForegroundColor Gray
}

# Also kill orphans
Stop-Process -Name "agent_service", "code_assistance_server" -Force

Start-Sleep -Milliseconds 400
Write-Host "✅ Purge complete. Decks cleared." -ForegroundColor Gray

Write-Host "--- [2/3] SYSTEM SYNC: RUNNING BUILD ---" -ForegroundColor Yellow
Set-Location "$ROOT\backend_cpp\build"
cmake --build . --config Release

Write-Host "--- [3/3] IGNITION: SPAWNING TAGGED TERMINALS ---" -ForegroundColor Green
if (Test-Path "$BIN_DIR") {
    Set-Location "$BIN_DIR"
    
    # 🚀 THE INJECTION: We include the $SIG in a comment at the end of the command
    # PowerShell will ignore the comment, but the OS records it in the process CommandLine
    $dashboardCmd = " `$host.UI.RawUI.WindowTitle = 'SYNAPSE: DASHBOARD'; ./code_assistance_server.exe #$SIG#"
    Start-Process "powershell.exe" -ArgumentList "-NoExit", "-Command", $dashboardCmd
    
    Write-Host "✅ DASHBOARD: Launched in fresh window." -ForegroundColor Gray
    Write-Host "✅ BRAIN: Starting in this window. Watching AI Monologue...`n" -ForegroundColor White
    
    # Set current window title and tag it so it can be killed next time if needed
    $host.UI.RawUI.WindowTitle = "SYNAPSE: BRAIN (MASTER) #$SIG#"
    ./agent_service.exe
}