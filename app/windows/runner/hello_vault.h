#ifndef RUNNER_HELLO_VAULT_H_
#define RUNNER_HELLO_VAULT_H_

#include <cstdint>
#include <string>
#include <vector>

// Windows Hello bound key, the Windows counterpart of BiometricVault.kt on Android.
//
// A Windows Hello key credential is an RSA key pair kept in the TPM (or the software Hello container when there is
// no TPM). Its private key can only be used after the user verifies with face, fingerprint or PIN. Hello keys can
// only sign, so the wrapping key is SHA-256 of the signature over a random 32-byte challenge stored in the blob
// (RSA PKCS#1 v1.5 signatures are deterministic, so the same challenge always gives the same key).
//
// Blob: version(1) | challenge(32) | nonce(12) | AES-256-GCM ciphertext | tag(16).
//
// Every function blocks (it may show the Windows Hello dialog), so call them off the UI thread.
// Error codes match the Android side: "canceled", "invalidated", "unavailable", "failed", "corrupt".
namespace hello_vault {

using Bytes = std::vector<uint8_t>;

struct Result {
  bool ok = false;
  Bytes data;
  std::string code;     // set when !ok
  std::string message;  // optional detail
};

bool Available();
Result Encrypt(const Bytes& plain);
Result Decrypt(const Bytes& blob);
void Delete();

}  // namespace hello_vault

#endif  // RUNNER_HELLO_VAULT_H_
