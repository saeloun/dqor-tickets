# Campfire active-socket revocation candidate

This is a reviewable patch set, not a production upgrade. It is stacked on the
Campfire binary preparation branch and changes no DQOR admission, scanner, commerce,
content, production credential, grant, storage, or service configuration.

## What was reproduced

The compiled, unpatched source-pin reconstruction kept both existing sockets open
and delivered a new message after each real HTTP logout, membership removal, role
downgrade, and ban. Fresh unauthorized connections were already rejected: reconnect
checks alone therefore miss the bug. See `evidence/baseline.txt`.

The patched native executable closes both affected sockets in all four cases,
prevents subsequent delivery, and preserves delivery to an unaffected user's socket.
Old-cookie/signed-stream replay is rejected after logout, membership removal and ban.
A downgraded user receives HTTP 403 on an admin write. The stock Turbo channel rejects
a lifted room stream in every scenario. See `evidence/candidate.txt`.

A role downgrade does not revoke legitimate room membership; this patch does not
claim all future room subscriptions must fail for a downgraded member. It retires the
old identity-bearing sockets and forces renewed authorization.

## Small source changes

- Roundhouse `RemoteConnections.where` carries the stable user ID. Cable snapshots
  matching live driver objects (never bare file descriptors) from its existing
  per-process registry, then revokes outside the registry lock.
- Driver revocation serializes against broadcasts/heartbeats, sends the Action Cable
  disconnect and WebSocket close frames, marks the driver retired, and calls socket
  shutdown to wake the receive owner. That owner retains exclusive fd-close and
  unsubscribe-cleanup responsibility. Buffered inbound frames are rejected once retired.
- Campfire's successful account-role update requests remote reconnection. Logout,
  ban and membership removal already invoke the existing API; their hooks are retained.
- `src/lower/module_mixins.rs`, Turbo/ActiveStorage authorization special cases and
  channel subscription guards are unchanged.

## Reproduction

Use public source only and a whitespace-free disposable path such as
`/tmp/dqor-campfire-revocation`. The verifier refuses non-loopback hosts and DB paths
outside that directory. It creates synthetic accounts and requires a fresh database
for each run; never point it at retained or production storage.

1. Clone `rubys/roundhouse`, `matz/spinel`, and `basecamp/once-campfire`; check out the
   full immutable revisions in `provenance.json`. Preserve their license notices.
2. Build Roundhouse with `cargo build --locked --bin roundhouse -j2` and Spinel with
   `make deps && make -j2 COPT=-O1`. Use an existing supported Ruby. Generate upstream
   Roundhouse fixtures with `bin/rh fixture` before its wider tests. Limit Rust tests
   with `RUST_TEST_THREADS=2`. Do not install into system paths.
3. From the Roundhouse root, emit the baseline with
   `target/debug/roundhouse --target spinel ../once-campfire -o ../revocation-baseline`.
   Apply the two patches to their respective source roots (`git apply --check` first),
   rebuild Roundhouse, and emit `../revocation-candidate` the same way.
4. The emitted `spin.toml` uses mutable package branches. Resolve the four public
   packages to the recorded immutable commits and use task-local path dependencies;
   never represent newly resolved branches as the installed release's dependency set.
   Set `XDG_CACHE_HOME` to a task-local directory. Required native libraries include
   SQLite, OpenSSL, libvips and jemalloc; verify architecture/linkage explicitly.
5. For **both test trees only**, declare
   `ffi_func :sp_net_listen_host, [:string, :int, :int], :int` in `runtime/tep/net.rb`
   and replace the `sphttp_listen` body with
   `Sock.sp_net_listen_host("127.0.0.1", port, 1024)`. This uses an existing Spinel API
   and limits listeners to loopback. The upstream startup banner still says 0.0.0.0;
   verify the actual listener with `lsof` rather than trusting that banner.
6. Compile each emitted program using `spin flags` and the pinned Spinel compiler,
   explicitly passing `--jobs=2 -O 1`; Make's job limit alone does not cap Spinel's
   generated-C compiler fan-out. The local run used two low-priority compile jobs.
7. Start the binaries from their respective emitted directories, with separate fresh
   `BLOG_DB` paths, `WORKERS=1`, `SPINEL_WORKERS=2` and ports 4317/4318. Run:

   ```sh
   ruby verify_sockets.rb http://127.0.0.1:4317 /tmp/dqor-campfire-revocation/revocation-baseline/storage/fresh.sqlite3
   ruby verify_sockets.rb http://127.0.0.1:4318 /tmp/dqor-campfire-revocation/revocation-candidate/storage/fresh.sqlite3
   ```

   The verifier needs the `websocket-driver` Ruby gem. Baseline should exit nonzero
   with all four revocation failures; candidate should pass. Stop both local servers.

## Release gates still open

The exact official upstream archive has now been recovered: its SHA-256 matches
`recorded_deployed_archive_sha256`. The retained emitted app/runtime and native
sources were reconciled against this candidate. The candidate was compiled and
passed all four sequential synthetic scenarios on Linux AMD64 with jemalloc linked.
This does not identify the currently running production image.

**Release remains blocked by reproduced adversarial failures.** A handshake identified
before revocation can register afterward; a reconnect in the modeled pre-commit ban
window survives; a non-reading peer blocks revocation. The first two are deterministic
source-level contract probes (the commit seam is not a real DB isolation test).
Backpressure also fails in a compiled Linux AMD64 Spinel/Driver regression. These
commands deliberately exit nonzero. Green DQOR CI does not certify these release gates.
See [Linux verification and remaining gates](LINUX_VERIFICATION.md) for exact evidence,
provenance, reproduction and scope. The original macOS provenance is retained in `provenance.json`.

The runtime remains single-process for Cable fan-out. Multi-worker/distributed
revocation, reconnect/commit races, adversarial socket backpressure, and comprehensive
SSO/tenant authorization are not certified by these sequential regression cases.
The existing per-user API revokes every device for that user, not only one session.
The role hook covers the existing account-role HTTP update path; future role-write
paths must invoke revocation too. Parent owns release decisions. This patch is not
permission to enable SSO, organizer administration, or multi-event chat.

## License/provenance

Roundhouse is MIT OR Apache-2.0 (MIT notice retained here); Campfire and Spinel are MIT.
Only source patches, the local verifier and non-sensitive synthetic evidence are
included. No executable or third-party native package source is redistributed here.
`provenance.json` records source revisions and the hashes of the actual tested native
executables. A complete notice inventory remains necessary for a distributed image.

Additional local checks: Roundhouse `cargo test --lib` passed 885 tests (one ignored)
after generating the required real-blog fixture and selecting Ruby 4.0.6. The targeted
`initializer_module_mixins`, `spinel_cable_identity`, `spinel_cable_channel`, and
`spinel_cable_heartbeat` integration suites passed 16 tests. These complement, rather
than replace, the actual native two-user/multiple-socket regressions above. The full
multi-target upstream matrix has not run. The verifier requires Ruby 3.1 or newer.
