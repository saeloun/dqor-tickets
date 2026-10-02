# Local ClamAV adapter: implemented, engine validation blocked

Stacked on hiring consent PR 165. No migration, provider upload, paid resource, production activation, daemon, security-setting change or real resume is involved.

## Local setup evidence

The execution host has 48 GiB physical RAM, roughly 7 GiB free pages at inspection, and 116 GiB available disk. `brew install clamav` was attempted with auto-update and cleanup disabled. Homebrew rejected macOS 27 with `Error: unknown or unsupported macOS version: :dunno`; its output also identified the pre-release platform as unsupported. The CLI was not installed. No ClamAV engine or official virus signatures ran. We did not spoof the OS version, compile a heavyweight engine or start a daemon to bypass the unsupported platform.

## Adapter contract

The default adapter still returns unavailable. Explicit `HIRING_RESUME_SCANNER=clamav`, `HIRING_CLAMSCAN_PATH=/absolute/path/to/clamscan`, and `HIRING_CLAMAV_DATABASE=/absolute/path/to/official/database` select the new local adapter. The delivery flag remains independently off by default. Missing executable/database, unsupported flags, scanner errors, signals, output warnings, timeouts, ambiguous results, oversized inputs or byte changes cannot yield clean.

The adapter uses `Process.spawn` with an explicit executable/argv tuple and separate arguments, never a shell. Input is copied to a mode-0600 file inside a mode-0700 temporary directory, with no candidate filename or identifiers. It supplies an isolated environment, stdin closed, a process group, a 30-second wall limit (60-second hard configurable ceiling), 20 CPU seconds, 64 MiB per-file output limit and no core dumps. Captured scanner output is limited to 64 KiB and never logged. Linux additionally applies a 4 GiB address-space ceiling; macOS needs worker-level memory controls because RLIMIT_AS is unreliable there. On timeout/output overflow, only the spawned process group is killed and reaped; temporary files are removed on all paths.

CLI options require official signatures and reject databases older than three days. Limits are 5 MiB input, 32 MiB total scan size, 100 embedded files, recursion 8, 15 seconds scan time and 5 seconds bytecode time. Unsigned bytecode is disabled; encrypted content and exceeded limits trigger alerts rather than being treated as clean. Main and daily database files must exist. ClamAV itself is responsible for verifying/loading official signatures; unsupported/missing/stale databases fail closed.

A clean result requires exit 0, empty stderr, exactly the expected input-path `OK` result, and unchanged SHA-256 after scanning. Exit 1 plus a matching `FOUND` result reports infected; all other outcomes stay quarantined/unavailable. `ScanResumeJob` separately compares the verdict digest against current database bytes under lock before recording clean. The existing authenticated delivery route rechecks byte digest, consent and authorization on every access.

## Validation and remaining work

Local focused suite: 27 examples, zero failures, **two pending real-engine tests**. Process-protocol doubles test arguments, file permissions, exit codes, signals, warnings, stale/mutated input, output floods, timeout termination/reaping, temporary cleanup, missing configuration and oversize rejection. These doubles are not antivirus engines or signatures. Brakeman: zero warnings; scoped RuboCop: no offenses.

`spec/services/hiring/clamav_integration_spec.rb` contains opt-in checks for a synthetically generated valid blank PDF and the standard harmless 68-byte EICAR test string. On a supported isolated host, supply the three scanner environment variables and set `HIRING_CLAMAV_INTEGRATION=true` before running that spec. It requires real official databases and expects actual clean/detection verdicts; it never substitutes fake signatures. These checks remain unexecuted here.

Production prerequisites remain explicit: choose a supported scanner-worker host; provision genuine engine and current official databases; run the opt-in checks; establish a one-at-a-time dedicated `hiring_scans` worker with memory/CPU/disk limits; deny document-worker outbound network; update signatures separately using the official updater; pin/update engine versions; monitor failed scans and database age; and define retention/rescan policy. Do not configure inline/async-in-web execution or place AV in the existing web process. No production worker, updater, service or delivery flag was activated by this PR.

## Official references consulted

- ClamAV one-shot scanning and size-limit caveats: https://docs.clamav.net/manual/Usage/Scanning.html
- Official CLI options and return codes: https://github.com/Cisco-Talos/clamav/blob/main/docs/man/clamscan.1.in
- Official signature maintenance: https://docs.clamav.net/manual/Usage/SignatureManagement.html
- Recognized Homebrew package: https://formulae.brew.sh/formula/clamav
