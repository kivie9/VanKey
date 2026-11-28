**[Tiếng Việt](SECURITY.md)** · English

# Security Policy

VanKey stores passwords, keys and 2FA codes. If you find a security vulnerability, please report it privately and do not make it public before a fix is available.

## How to report

1. **Recommended:** use GitHub's private vulnerability reporting: go to the repo page and choose **Security → Report a vulnerability**.
2. Or email: vankey@onigix.com.

Please include: steps to reproduce, the app or server version, and the impact you observed. When testing, do not access data or accounts that are not yours.

## Scope

- The VanKey app (`app/`), the server (`server/`), and the vault format (`docs/vault-format.md`).
- No independent audit has been done yet. Known gaps are listed in the [Security](https://github.com/kivie9/VanKey/blob/main/docs/STATUS.md) section and in `docs/STATUS.md`.

## Response time

`3 working days`. Fixed vulnerabilities are recorded in [CHANGELOG.md](CHANGELOG.md).
