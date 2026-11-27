@echo off
rem Bam dup: tao khoa ky ban phat hanh Android (chi chay MOT lan). Xem create-android-signing-key.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0create-android-signing-key.ps1"
echo.
pause
