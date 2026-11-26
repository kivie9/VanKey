@echo off
rem Bam dup: build ban release tu code hien tai va cai len dien thoai dang cam USB, giu nguyen du lieu app.
setlocal
set FLUTTER=E:\code\libs\flutter\bin\flutter.bat
set ADB=E:\code\libs\android-sdk\platform-tools\adb.exe
cd /d "%~dp0app"

echo === Kiem tra dien thoai ===
"%ADB%" start-server >nul 2>&1
"%ADB%" get-state >nul 2>&1
if errorlevel 1 (
  echo Khong thay dien thoai. Cam cap USB, mo khoa man hinh, cho phep go loi USB roi chay lai.
  "%ADB%" devices
  goto :end
)

echo === Build APK (mat khoang 1-2 phut) ===
call "%FLUTTER%" build apk --release --split-per-abi
if errorlevel 1 (
  echo Build loi, xem thong bao o tren.
  goto :end
)

echo === Cai len dien thoai ===
"%ADB%" install -r build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
if errorlevel 1 (
  echo Cai khong thanh cong. Neu bao "offline": rut cap cam lai, hoac tat/bat lai Go loi USB.
  goto :end
)
echo.
echo XONG: da cai ban moi len dien thoai.

:end
echo.
pause
