# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in Ticklet, please **do not** open a public GitHub issue.

Instead, report it privately by emailing the maintainer or using [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) feature on this repository.

Please include:

- A description of the vulnerability and its potential impact
- Steps to reproduce the issue
- Your macOS version and Mac model (Intel/Apple Silicon)
- Any relevant log entries or screenshots

You can expect an acknowledgement within **48 hours** and a resolution or status update within **7 days**.

## Scope

Ticklet is a local-only macOS menu bar app. It:

- Does **not** communicate with any external servers or networks
- Does **not** store credentials, tokens, or sensitive personal data
- Writes only app name and window title to CSV files in `~/Library/Logs/Ticklet/`
- Requires Accessibility permission solely to read frontmost window titles

Security issues most relevant to this project include:

- Privilege escalation via the Accessibility API
- Unintended data exposure outside `~/Library/Logs/Ticklet/`
- Code injection through maliciously crafted window titles written to CSV logs
- Insecure handling of file paths or log rotation

## Out of Scope

- Theoretical attacks requiring physical access to an already-unlocked Mac
- Issues in macOS itself or the Accessibility framework
- Social engineering of the user granting Accessibility permission

## Disclosure Policy

Once a fix is available, vulnerabilities will be disclosed publicly via a GitHub Security Advisory. Credit will be given to the reporter unless they prefer to remain anonymous.
