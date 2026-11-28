#include "hello_vault.h"

#include <windows.h>
#include <bcrypt.h>
#include <unknwn.h>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>

#include <atomic>
#include <chrono>
#include <thread>

namespace hello_vault {
namespace {

using winrt::Windows::Security::Credentials::KeyCredential;
using winrt::Windows::Security::Credentials::KeyCredentialCreationOption;
using winrt::Windows::Security::Credentials::KeyCredentialManager;
using winrt::Windows::Security::Credentials::KeyCredentialStatus;
using winrt::Windows::Security::Cryptography::CryptographicBuffer;
using winrt::Windows::Storage::Streams::IBuffer;

constexpr wchar_t kCredentialName[] = L"VanKey vault";
constexpr uint8_t kVersion = 1;
constexpr size_t kChallengeLen = 32;
constexpr size_t kNonceLen = 12;
constexpr size_t kTagLen = 16;
constexpr size_t kHeaderLen = 1 + kChallengeLen + kNonceLen;

Result Fail(const char* code, std::string message = {}) {
  Result r;
  r.code = code;
  r.message = std::move(message);
  return r;
}

Result FromStatus(KeyCredentialStatus s) {
  switch (s) {
    case KeyCredentialStatus::UserCanceled:
    case KeyCredentialStatus::UserPrefersPassword:
      return Fail("canceled");
    case KeyCredentialStatus::NotFound:
      return Fail("invalidated", "Windows Hello key not found");
    case KeyCredentialStatus::SecurityDeviceLocked:
      return Fail("failed", "Windows Hello is locked, try again later");
    default:
      return Fail("failed", "Windows Hello status " + std::to_string(static_cast<int>(s)));
  }
}

IBuffer ToBuffer(const uint8_t* p, size_t n) {
  return CryptographicBuffer::CreateFromByteArray(winrt::array_view<const uint8_t>(p, p + n));
}

Bytes FromBuffer(const IBuffer& b) {
  winrt::com_array<uint8_t> a;
  CryptographicBuffer::CopyToByteArray(b, a);
  return Bytes(a.begin(), a.end());
}

bool Random(uint8_t* p, size_t n) {
  return BCRYPT_SUCCESS(BCryptGenRandom(nullptr, p, static_cast<ULONG>(n), BCRYPT_USE_SYSTEM_PREFERRED_RNG));
}

void Wipe(Bytes& b) {
  if (!b.empty()) SecureZeroMemory(b.data(), b.size());
  b.clear();
}

// The Windows Hello dialog often opens behind the app window. Bring it to the front while it is up.
class DialogToFront {
 public:
  DialogToFront() : worker_([this] {
      for (int i = 0; i < 100 && !stop_; ++i) {
        if (HWND w = FindWindowW(L"Credential Dialog Xaml Host", nullptr)) {
          SetForegroundWindow(w);
          return;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
      }
    }) {}
  ~DialogToFront() {
    stop_ = true;
    worker_.join();
  }

 private:
  std::atomic<bool> stop_{false};
  std::thread worker_;
};

// Signs the challenge (asks for Windows Hello) and returns SHA-256 of the signature as a 32-byte AES key.
Result DeriveKey(const KeyCredential& cred, const uint8_t* challenge) {
  DialogToFront front;
  auto signed_ = cred.RequestSignAsync(ToBuffer(challenge, kChallengeLen)).get();
  if (signed_.Status() != KeyCredentialStatus::Success) return FromStatus(signed_.Status());
  Bytes sig = FromBuffer(signed_.Result());
  Result r;
  r.data.resize(32);
  NTSTATUS st = BCryptHash(BCRYPT_SHA256_ALG_HANDLE, nullptr, 0, sig.data(), static_cast<ULONG>(sig.size()),
                           r.data.data(), static_cast<ULONG>(r.data.size()));
  Wipe(sig);
  if (!BCRYPT_SUCCESS(st)) return Fail("failed", "sha256");
  r.ok = true;
  return r;
}

// AES-256-GCM. encrypt: in = plaintext, out = ciphertext, tag written to `tag`.
// decrypt: in = ciphertext, tag read from `tag`, out = plaintext. Returns false on any error (incl. bad tag).
bool AesGcm(bool encrypt, const Bytes& key, const uint8_t* nonce, const uint8_t* in, size_t len, uint8_t* tag,
            Bytes& out) {
  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_KEY_HANDLE k = nullptr;
  bool ok = false;
  if (BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&alg, BCRYPT_AES_ALGORITHM, nullptr, 0)) &&
      BCRYPT_SUCCESS(BCryptSetProperty(alg, BCRYPT_CHAINING_MODE, (PUCHAR)BCRYPT_CHAIN_MODE_GCM,
                                       sizeof(BCRYPT_CHAIN_MODE_GCM), 0)) &&
      BCRYPT_SUCCESS(BCryptGenerateSymmetricKey(alg, &k, nullptr, 0, (PUCHAR)key.data(),
                                                static_cast<ULONG>(key.size()), 0))) {
    BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
    BCRYPT_INIT_AUTH_MODE_INFO(info);
    info.pbNonce = const_cast<uint8_t*>(nonce);
    info.cbNonce = static_cast<ULONG>(kNonceLen);
    info.pbTag = tag;
    info.cbTag = static_cast<ULONG>(kTagLen);
    out.assign(len, 0);
    ULONG done = 0;
    NTSTATUS st = encrypt
        ? BCryptEncrypt(k, const_cast<uint8_t*>(in), static_cast<ULONG>(len), &info, nullptr, 0, out.data(),
                        static_cast<ULONG>(out.size()), &done, 0)
        : BCryptDecrypt(k, const_cast<uint8_t*>(in), static_cast<ULONG>(len), &info, nullptr, 0, out.data(),
                        static_cast<ULONG>(out.size()), &done, 0);
    ok = BCRYPT_SUCCESS(st) && done == len;
    if (!ok) Wipe(out);
  }
  if (k) BCryptDestroyKey(k);
  if (alg) BCryptCloseAlgorithmProvider(alg, 0);
  return ok;
}

}  // namespace

bool Available() {
  try {
    return KeyCredentialManager::IsSupportedAsync().get();
  } catch (...) {
    return false;
  }
}

Result Encrypt(const Bytes& plain) {
  try {
    if (!KeyCredentialManager::IsSupportedAsync().get()) return Fail("unavailable");
    // Reuse the existing key if there is one (one Hello prompt), otherwise create it.
    auto opened = KeyCredentialManager::OpenAsync(kCredentialName).get();
    KeyCredential cred{nullptr};
    if (opened.Status() == KeyCredentialStatus::Success) {
      cred = opened.Credential();
    } else {
      DialogToFront front;
      auto created =
          KeyCredentialManager::RequestCreateAsync(kCredentialName, KeyCredentialCreationOption::ReplaceExisting)
              .get();
      if (created.Status() != KeyCredentialStatus::Success) return FromStatus(created.Status());
      cred = created.Credential();
    }

    Bytes blob(kHeaderLen + plain.size() + kTagLen);
    blob[0] = kVersion;
    uint8_t* challenge = blob.data() + 1;
    uint8_t* nonce = challenge + kChallengeLen;
    if (!Random(challenge, kChallengeLen) || !Random(nonce, kNonceLen)) return Fail("failed", "random");

    Result key = DeriveKey(cred, challenge);
    if (!key.ok) return key;
    Bytes cipher;
    uint8_t* tag = blob.data() + kHeaderLen + plain.size();
    bool ok = AesGcm(true, key.data, nonce, plain.data(), plain.size(), tag, cipher);
    Wipe(key.data);
    if (!ok) return Fail("failed", "encrypt");
    std::copy(cipher.begin(), cipher.end(), blob.begin() + kHeaderLen);

    Result r;
    r.ok = true;
    r.data = std::move(blob);
    return r;
  } catch (const winrt::hresult_error& e) {
    return Fail("failed", winrt::to_string(e.message()));
  } catch (...) {
    return Fail("failed");
  }
}

Result Decrypt(const Bytes& blob) {
  try {
    if (blob.size() < kHeaderLen + kTagLen || blob[0] != kVersion) return Fail("corrupt");
    if (!KeyCredentialManager::IsSupportedAsync().get()) return Fail("unavailable");
    auto opened = KeyCredentialManager::OpenAsync(kCredentialName).get();
    if (opened.Status() != KeyCredentialStatus::Success) return FromStatus(opened.Status());

    const uint8_t* challenge = blob.data() + 1;
    const uint8_t* nonce = challenge + kChallengeLen;
    size_t len = blob.size() - kHeaderLen - kTagLen;
    Result key = DeriveKey(opened.Credential(), challenge);
    if (!key.ok) return key;
    uint8_t tag[kTagLen];
    std::copy(blob.end() - kTagLen, blob.end(), tag);
    Result r;
    bool ok = AesGcm(false, key.data, nonce, blob.data() + kHeaderLen, len, tag, r.data);
    Wipe(key.data);
    if (!ok) return Fail("corrupt");
    r.ok = true;
    return r;
  } catch (const winrt::hresult_error& e) {
    return Fail("failed", winrt::to_string(e.message()));
  } catch (...) {
    return Fail("failed");
  }
}

void Delete() {
  try {
    KeyCredentialManager::DeleteAsync(kCredentialName).get();
  } catch (...) {
    // Not there, or Hello unavailable: nothing to delete.
  }
}

}  // namespace hello_vault
