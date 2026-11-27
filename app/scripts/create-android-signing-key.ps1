# Tạo khóa ký bản phát hành Android cho VanKey (chạy MỘT lần, rồi giữ khóa này mãi mãi).
#
# - Khóa nằm ngoài thư mục dự án: %USERPROFILE%\vankey-signing\vankey-release.jks
# - Ghi app\android\key.properties (đã có trong .gitignore, KHÔNG commit) để Gradle ký bằng khóa này.
# - Mất khóa hoặc mật khẩu = không bao giờ phát hành được bản cập nhật cài đè lên máy đã cài nữa.
#   Hãy chép file .jks và mật khẩu vào nơi an toàn (ví dụ chính kho VanKey của bạn, và một USB cất riêng).
$ErrorActionPreference = 'Stop'

$dir = Join-Path $env:USERPROFILE 'vankey-signing'
$jks = Join-Path $dir 'vankey-release.jks'
$alias = 'vankey'
$props = Join-Path $PSScriptRoot '..\android\key.properties'

if (Test-Path $jks) {
  Write-Host "Đã có khóa: $jks"
  Write-Host 'Không tạo khóa mới (tạo mới sẽ làm bản sau không cài đè được bản cũ).'
  Write-Host 'Nếu chỉ thiếu app\android\key.properties, xóa dòng kiểm tra này hoặc tự viết file theo mẫu trong README.'
  exit 1
}

$keytool = @(
  $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' }),
  'C:\Program Files\Java\jdk-21\bin\keytool.exe',
  'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $keytool) {
  $cmd = Get-Command keytool -ErrorAction SilentlyContinue
  if ($cmd) { $keytool = $cmd.Source } else { throw 'Không tìm thấy keytool (cần JDK). Đặt JAVA_HOME rồi chạy lại.' }
}

function Read-Secret([string]$prompt) {
  $s = Read-Host -AsSecureString $prompt
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

$pw = Read-Secret 'Mật khẩu cho khóa ký (từ 12 ký tự, chỉ dùng chữ không dấu, số, - _ .)'
if ($pw.Length -lt 12) { throw 'Mật khẩu cần ít nhất 12 ký tự.' }
if ($pw -notmatch '^[A-Za-z0-9._-]+$') { throw 'Chỉ dùng chữ không dấu, số và - _ . (tránh lỗi khi Gradle đọc file).' }
if ((Read-Secret 'Nhập lại mật khẩu') -ne $pw) { throw 'Hai lần nhập không khớp.' }

New-Item -ItemType Directory -Force $dir | Out-Null
& $keytool -genkeypair -v -keystore $jks -storetype PKCS12 -alias $alias -keyalg RSA -keysize 4096 -validity 10000 `
  -storepass $pw -keypass $pw -dname 'CN=VanKey, O=VanKey' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'keytool báo lỗi, chưa tạo được khóa.' }

# Properties dùng dấu \ làm ký tự thoát: ghi đường dẫn bằng dấu /.
$jksPath = $jks -replace '\\', '/'
@"
storeFile=$jksPath
storePassword=$pw
keyAlias=$alias
keyPassword=$pw
"@ | Set-Content -Encoding ascii $props

Write-Host ''
Write-Host "XONG. Khóa: $jks"
Write-Host "Gradle đọc: $props (không commit file này)."
Write-Host ''
Write-Host 'Việc cần làm tiếp:'
Write-Host '  1. Chép file .jks và mật khẩu ra nơi an toàn. Mất là không cập nhật app được nữa.'
Write-Host '  2. Cho CI ký được (cần gh đã đăng nhập), chạy trong thư mục dự án:'
Write-Host "       [Convert]::ToBase64String([IO.File]::ReadAllBytes('$jks')) | gh secret set ANDROID_KEYSTORE_BASE64"
Write-Host '       gh secret set ANDROID_KEYSTORE_PASSWORD     (dán mật khẩu khi được hỏi)'
Write-Host "       gh secret set ANDROID_KEY_ALIAS --body $alias"
Write-Host '  3. Điện thoại đang cài bản ký bằng khóa debug: đồng bộ hoặc xuất sao lưu, gỡ app MỘT lần, rồi cài bản mới.'
