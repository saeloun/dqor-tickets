# DQOR Roundhouse/Spinel experiment

Full DQOR does not compile to Spinel at this checkpoint. The ownership-schema patch is a tested first compatibility step. It changes the external Roundhouse compiler and its adapters; no DQOR application path loads it.

The experiment uses DQOR `585f1e5143dab85b1041a84fce0f3ee0d470ad72`, Roundhouse `be39e428ef6f3a47719d3ab9a46041133146178a`, and Spinel `ed603ed595db42626c747988a091c07f54532b94`. [CHECKPOINT.json](CHECKPOINT.json) records exact source, patch, compiler and native artifact digests. [ownership-schema.patch](ownership-schema.patch) is the complete 15-file compiler patch, SHA256 `17ab8652e4ce0f1458e7c7c26e334ddba1244bc305aaa63a97540e27044b9d81`.

The patch retains generated ownership columns, composite foreign keys, supported CHECK constraints and unique indexes. Ordinary ORM inserts and updates exclude generated fields. SQLite ownership schemas enforce integer domains, and each connection enables and reads back foreign-key enforcement. Unproved expressions, unsupported constraint options and unsupported target/migration paths fail explicitly. Both Spinel and CRuby pool initialization clean up opened handles when later initialization fails.

Measured verification on an Apple M5 Max with 128GB memory:

- Four affected integration targets: 29 passed, zero failures, four explicit toolchain-gated ignores.
- Full compiler library: 901 passed, zero failures, one intentional ignore in a working directory without spaces, with the repository's `RUST_MIN_STACK=33554432` setting.
- Explicit external SQLite oracle: one passed.
- Three real Spinel binaries built and ran successfully: generated ownership schema, two distinct file-backed pool connections, and emitted ORM create/update/reload. A separate execution with an empty inherited environment and fresh synthetic database passed for all three.
- Invalid cross-owner creates and updates, wrong-type owner writes, integer overflow, generated-field writes and applicable CHECK/unique violations were rejected. ORM failures preserved the persisted record and row count. Pool fault probes verified cleanup after later connection/shard/open failures.
- Five independent source reviews approved the exact patch. No deployment, real attendee lookup, payment, email, ticket issuance, role grant or feature activation occurred.

The pool proof uses two sequentially exercised connections; concurrency and a live application journey are unverified. The same compiled library test executable retains three LSP protocol failures from the physical Dropbox path containing spaces and passes in the directory without spaces. No LSP test or source workaround was added. These results do not establish existing-database upgrade, full schema, authentication, payment, job, QR/PDF or admin parity.

To reproduce, use a disposable checkout of the pinned Roundhouse revision with the repository's generated fixtures and documented Ruby/sqlite3 prerequisites. Check the patch with `git apply --check`, then apply it in that isolated checkout. Run the `generated_ownership_schema`, `schema_uuid_and_custom_key`, `roundtrip` and `sql_identifiers` Cargo test targets and `cargo test --lib`. The Python SQLite oracle is explicitly ignored by ordinary Cargo tests and requires its declared prerequisite when run separately. Use a working directory without spaces and the checked-in Cargo stack configuration. Keep build concurrency bounded, and use synthetic data with no production credentials. This package contains source and verification metadata; compiled binaries and raw execution logs are retained separately.

Strict unchanged DQOR ingestion still stops at `mount_avo`. Removing only that mount in a disposable source archive exposed 329 check errors and 348 emission errors; no full application output was emitted. Its Gemfile remained unchanged. Existing query serialization, privacy-module support, email validation constants and Rails model/job APIs remain blockers. PostgreSQL-specific constraints and Date semantics also require support before full compatibility can be claimed.

The no-Avo profile excludes all nine admin actions: announcement broadcast, attendee/order CSV export, order-link email, complimentary ticket issuance, selected check-in, refunds, attendee-detail requests and confirmation resends. Resource administration, existing session/role checks and legacy record scopes also need equivalent behavior. Avo remains installed in DQOR. Dropping its mount is not an admin replacement, and the experimental profile is not deployable.
