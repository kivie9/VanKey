#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Gắn một cờ DWORD vào nội dung clipboard đang mở. Thiếu cờ thì bản chép vẫn dùng được, chỉ mất phần bảo vệ.
void SetClipboardFlag(const wchar_t* format, DWORD value) {
  UINT id = RegisterClipboardFormatW(format);
  if (id == 0) return;
  HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
  if (!mem) return;
  *static_cast<DWORD*>(GlobalLock(mem)) = value;
  GlobalUnlock(mem);
  if (!SetClipboardData(id, mem)) GlobalFree(mem);
}

// Chép chữ vào clipboard nhưng không cho vào lịch sử clipboard (Win+V), không đồng bộ lên clipboard đám mây,
// và báo các app theo dõi clipboard bỏ qua (theo hướng dẫn của Microsoft cho trình quản lý mật khẩu).
bool CopySensitive(HWND owner, const std::string& utf8) {
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
  if (n < 0) return false;
  std::wstring text(n, L'\0');
  if (n > 0) MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), text.data(), n);

  if (!OpenClipboard(owner)) return false;
  EmptyClipboard();
  bool ok = false;
  size_t bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (mem) {
    memcpy(GlobalLock(mem), text.c_str(), bytes);
    GlobalUnlock(mem);
    ok = SetClipboardData(CF_UNICODETEXT, mem) != nullptr;
    if (!ok) GlobalFree(mem);
  }
  if (ok) {
    SetClipboardFlag(L"ExcludeClipboardContentFromMonitorProcessing", 0);
    SetClipboardFlag(L"CanIncludeInClipboardHistory", 0);
    SetClipboardFlag(L"CanUploadToCloudClipboard", 0);
  }
  CloseClipboard();
  return ok;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  platform_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "vankey/platform",
      &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "copySensitive") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        const std::string* text = nullptr;
        if (args) {
          auto it = args->find(flutter::EncodableValue("text"));
          if (it != args->end()) text = std::get_if<std::string>(&it->second);
        }
        if (!text) {
          result->Error("bad_args", "missing text");
          return;
        }
        if (CopySensitive(GetHandle(), *text)) {
          result->Success();
        } else {
          result->Error("failed", "clipboard unavailable");
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  platform_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
