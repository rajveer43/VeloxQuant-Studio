# Security Policy

## Supported Versions

VeloxQuant Studio is under active development. Security fixes are made
against the `main` branch; there are no separately maintained release
branches at this time.

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

## Reporting a Vulnerability

Please **do not open a public GitHub issue** for security vulnerabilities.

Instead, report it privately using one of the following:

- **GitHub Private Vulnerability Reporting** (preferred): open a report via
  the [Security tab](https://github.com/rajveer43/VeloxQuant-Studio/security/advisories/new)
  on this repository.
- **Email**: rathodrajveer1311@gmail.com

Please include as much detail as possible:

- A description of the vulnerability and its potential impact
- Steps to reproduce, or a proof-of-concept
- Affected version/commit
- Any suggested mitigation, if known

You should receive an initial response within **5 business days**. We'll
keep you updated as the issue is triaged, fixed, and released, and will
credit you in the release notes unless you prefer to remain anonymous.

## Scope

This app is a native macOS client that:

- Authenticates users via [Supabase](https://supabase.com) (email/password,
  session tokens stored via the OS keychain/`Secrets.xcconfig` locally).
- Drives the [VeloxQuant-MLX](https://github.com/rajveer43/VeloxQuant-MLX)
  Python CLI as a local subprocess to quantize, benchmark, and serve models.

Issues in scope include (non-exhaustive):

- Credential or session token handling/leakage
- Insecure storage of secrets (e.g. Supabase keys, auth tokens)
- Command/argument injection in the subprocess invocation of the Python CLI
- Path traversal or unsafe file handling in model/artifact directories
- Auth bypass or privilege issues in `AuthViewModel`/Supabase integration
- Deep link / URL scheme handling issues (e.g. email confirmation redirect)

Issues in the upstream `VeloxQuant-MLX` Python package should be reported in
[that repository](https://github.com/rajveer43/VeloxQuant-MLX) instead.

## Out of Scope

- Vulnerabilities requiring physical access to an already-unlocked device
- Issues in third-party dependencies without a demonstrated impact on this
  app (report those upstream)
- Social engineering, spam, or denial-of-service reports without a working
  proof-of-concept
