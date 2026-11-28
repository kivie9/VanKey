# Cryptography Spike Results (M0)

> Date: 2026-11-19 · Machine: Windows 11 · Flutter 3.50.0 / Dart 3.14.0 · package `cryptography` 2.9.0
> Cross-checked with `libsodium-wrappers-sumo` 0.8.4 (libsodium compiled to WASM, run with Node 22)

## Questions to answer
1. Do Argon2id and XChaCha20-Poly1305 run correctly in Dart?
2. Do the results **match libsodium**? (required, because the future extension and server will read the same file format)
3. Is the speed of Argon2id acceptable?

## Results

### Correctness: PASSED
`app/test/spike/crypto_spike_test.dart` — **7/7 tests pass**:

| Test | Result |
|---|---|
| XChaCha20-Poly1305 matches the official test vector (draft-irtf-cfrg-xchacha, A.3.1) | pass |
| Encrypt then decrypt, 24-byte nonce, 16-byte tag | pass |
| Wrong key → error, no data returned | pass |
| Flipping 1 byte of the ciphertext or 1 byte of the tag → error | pass |
| Different AAD → error (protects against header tampering) | pass |
| Argon2id: same input gives the same key; different salt gives a different key | pass |
| Fixed output exported for cross-checking | pass |

### Compatibility with libsodium: PASSED, matches byte-for-byte
With the same input, the two independent implementations (Dart `cryptography` and libsodium) give:

| Check | Result |
|---|---|
| Argon2id: Vietnamese passphrase, fixed salt, opslimit=3, 64 MiB → 32-byte key | **match** |
| XChaCha20-Poly1305: ciphertext | **match** |
| XChaCha20-Poly1305: tag | **match** |
| libsodium decrypts a ciphertext created by Dart | **works** |
| libsodium rejects a ciphertext altered by 1 byte | **rejected** |

Consequence: **the file format specified in `vault-format.md` can be implemented in Dart and in TypeScript** (extension/server later), and the two can read and write each other's files. Parameter mapping: libsodium `opslimit` = number of iterations (`iterations`), `memlimit` = memory in bytes = `memory` (KiB) × 1024, parallelism = 1.

The data saved as the first test vector: `app/test/vectors/primitives-v0.json`.

### Argon2id speed on this PC

| Parameters | Dart AOT (`dart compile exe`) |
|---|---|
| 1 pass, 16 MiB | 54 ms |
| 2 passes, 32 MiB | 236 ms |
| **3 passes, 64 MiB** (expected default) | **876 ms** |
| 3 passes, 128 MiB | 1368 ms |

- `flutter test` mode (JIT) with 3 passes, 64 MiB: 856 ms (almost the same).
- For comparison: libsodium WASM with the same parameters, 3 passes, 64 MiB: **214 ms** (one run). The pure Dart version is about **4 times slower**.
- Each number was measured **once**, with no averaging, so use them only to compare orders of magnitude.

The threshold set in `docs/project/TASKS.md`: unlock ≤ ~1 second on a PC, ≤ ~1.5 seconds on a mid-range phone.
- **PC: passes** with 3 passes, 64 MiB (0.88 s). 128 MiB (1.37 s) exceeds the threshold.
- **Phone: NOT MEASURED.** Phones are usually several times slower than a PC, so 3 passes, 64 MiB with the pure Dart version may exceed 1.5 s.

## Not verified yet (stated clearly)
- **`sodium_libs` (native libsodium) not tried.** It needs a native Windows build, so it needs **Visual Studio** (not installed). Because the pure Dart spike passed, this is no longer a blocker; it is a future **speed-up** option.
- **Measurement on a real Android phone not done** (no Android SDK yet).
- **Memory use** of Argon2id not measured (64 MiB is the memory the algorithm needs; Dart's own overhead is not included).
- **Erasing keys from RAM:** Dart has a garbage collector, so it cannot guarantee that every copy is overwritten. Recorded in `threat-model.md`.
- **Protection against side-channel attacks (constant-time execution):** the pure Dart library makes no promise about this. Acceptable for the current threat model (a local app, not a service receiving remote input), but a qualified person must review it before real use.

## Decision (recorded in `decisions.md`, D4)
**Use `cryptography` (pure Dart) to continue M1**, placed behind the project's own `Kdf` and `Aead` interfaces. Because the algorithms are the same, switching to native libsodium later **does not change the file format**.

If measurements on Android are too slow, there are three options, in order:
1. Lower the parameters: for example 2 passes, 64 MiB (still above the lower bound of 2 passes, 32 MiB in the specification). Parameters are stored in each key slot, so they can be changed without changing the format.
2. Switch to `sodium_libs` on Android.
3. Keep the heavy Argon2id but run it in a separate isolate and show a waiting screen.

## How to run again
```powershell
cd E:\code\project\keymanager\app
flutter test test/spike/crypto_spike_test.dart

# measure time (AOT)
E:\code\libs\flutter\bin\cache\dart-sdk\bin\dart.exe compile exe test/spike/argon2_bench.dart -o build/argon2_bench.exe
.\build\argon2_bench.exe

# cross-check with libsodium (needs Node), run AFTER the flutter test command above:
cd tool\interop
npm install
node check.js
```
The cross-check script is in `app/tool/interop/` (it uses `libsodium-wrappers-sumo`; the regular build does **not** include Argon2) and reads `app/build/spike_out.json`, which the test creates.

Timings vary between runs (for example 856 ms, then 995 ms, for the same parameters), so a single number is only approximate.
