@echo off
rem Bam dup: build ban Windows (release) tu code hien tai, tao bo cai roi cai de len ban VanKey dang dung.
rem App duoc cai vao %LOCALAPPDATA%\Programs\VanKey (mo bang Start Menu). Kho du lieu o %APPDATA%\com.vankey\vankey,
rem khong bi dung toi khi cai de hay go app.
rem Can Inno Setup 6:  winget install --id JRSoftware.InnoSetup -e --scope user
setlocal
set FLUTTER=E:\code\libs\flutter\bin\flutter.bat
set APPDIR=%LOCALAPPDATA%\Programs\VanKey
cd /d "%~dp0.."

set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if not exist "%ISCC%" (
  echo Chua cai Inno Setup 6. Chay lenh sau roi thu lai:
  echo   winget install --id JRSoftware.InnoSetup -e --scope user
  goto :fail
)

rem Phien ban lay tu dong "version: 1.0.0+1" trong pubspec.yaml (bo phan +1).
for /f "tokens=2" %%v in ('findstr /b "version:" pubspec.yaml') do set VER_FULL=%%v
for /f "tokens=1 delims=+" %%v in ("%VER_FULL%") do set VER=%%v
if "%VER%"=="" (
  echo Khong doc duoc phien ban trong pubspec.yaml.
  goto :fail
)

echo === Build Windows %VER% (mat khoang 1-2 phut) ===
call "%FLUTTER%" build windows --release --build-name=%VER% --dart-define=APP_VERSION=%VER%
if errorlevel 1 (
  echo Build loi, xem thong bao o tren. Ban VanKey dang cai giu nguyen.
  goto :fail
)

echo === Tao bo cai ===
"%ISCC%" /Qp /DAppVersion=%VER% installer\vankey.iss
if errorlevel 1 (
  echo Tao bo cai loi, xem thong bao o tren. Ban VanKey dang cai giu nguyen.
  goto :fail
)
set SETUP=%CD%\build\installer\vankey-%VER%-windows-setup.exe

echo === Cai de (VanKey dang mo se tu dong lai) ===
start "" /wait "%SETUP%" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
if errorlevel 1 (
  echo Cai dat khong thanh cong. Thu dong VanKey roi chay lai.
  goto :fail
)

echo.
echo XONG: VanKey %VER% da cai vao %APPDIR%
echo Bo cai (mang sang may khac duoc): %SETUP%
start "" "%APPDIR%\vankey.exe"
set RESULT=0
goto :end

:fail
set RESULT=1

:end
echo.
rem Goi voi tham so "nopause" khi chay tu terminal hoac script.
if /i not "%~1"=="nopause" pause
exit /b %RESULT%
