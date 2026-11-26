@echo off
rem Bam dup: build ban Windows (release) tu code hien tai roi chep ra app\dist\windows.
rem Chay app: app\dist\windows\vankey.exe. Muon mang sang may khac thi chep CA thu muc nay (can ca DLL va data).
setlocal
set FLUTTER=E:\code\libs\flutter\bin\flutter.bat
set SRC=build\windows\x64\runner\Release
set OUT=dist\windows
cd /d "%~dp0app"

echo === Build Windows (mat khoang 1-2 phut) ===
call "%FLUTTER%" build windows --release
if errorlevel 1 (
  echo Build loi, xem thong bao o tren. Thu muc %OUT% giu nguyen ban cu.
  goto :fail
)

echo === Chep ra %OUT% ===
rem /MIR: thu muc dich giong het ban vua build (xoa tep cu thua). Kho du lieu cua app khong nam o day.
robocopy "%SRC%" "%OUT%" /MIR /XF *.old /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
rem robocopy: ma tu 8 tro len moi la loi.
if errorlevel 8 (
  echo Chep khong thanh cong. Neu VanKey dang mo thi dong lai roi chay lai.
  goto :fail
)
rem Don tep .old con sot lai; tep nao dang bi app giu thi bo qua.
del /s /q "%OUT%\*.old" >nul 2>&1
echo.
echo XONG: %CD%\%OUT%\vankey.exe
set RESULT=0
goto :end

:fail
set RESULT=1

:end
echo.
rem Goi voi tham so "nopause" khi chay tu terminal hoac script.
if /i not "%~1"=="nopause" pause
exit /b %RESULT%
