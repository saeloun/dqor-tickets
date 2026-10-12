require "active_record"
require "pg"
require "json"
require "digest"
require "uri"
require "timeout"

mode = ARGV.fetch(0, "staged")
raise "Use staged or baseline mode" unless %w[staged baseline].include?(mode)
url = ENV.fetch("COMMUNITY_MIGRATION_DATABASE_URL")
uri = URI.parse(url)
unless %w[postgres postgresql].include?(uri.scheme) && %w[127.0.0.1 localhost].include?(uri.host) && uri.port == 53448 && uri.user == "sward" && uri.password.nil? && uri.path.match?(%r{\A/dqor_community_migration_[a-z0-9_]+\z}) && uri.query.nil?
  raise "Use a dedicated local dqor_community_migration_* scratch database on port 53448 without credentials"
end

ActiveRecord::Base.establish_connection(url: url, pool: 4)
ActiveRecord::Migration.verbose = false
observer = PG.connect(url)
index_name = "idx_on_organization_id_community_group_id_starts_at_360868f23d"
foreign_key = "events_same_organization_group"
root = File.expand_path("..", __dir__)
if mode == "baseline"
  old_source = File.expand_path(ARGV.fetch(1))
  unless Digest::SHA256.file(old_source).hexdigest == "e0d5785b625f4e905320bff023a63a4ca876053fdde510ca9c6c5335645a04a5"
    raise "Baseline must be the exact retained migration from 206ce7c"
  end
  require old_source
else
  %w[20261011030000_create_community_groups 20261011030100_add_community_group_events_index 20261011030200_add_community_group_event_foreign_key 20261011030300_validate_community_group_event_foreign_key].each do |file|
    require File.join(root, "db/migrate", file)
  end
end

report = { mode: mode, controlled_pause_is_lock_contract_not_timing_benchmark: true }
worker = nil
release = nil

assert = ->(condition, message) { raise message unless condition }
wait_until = lambda do |seconds, &condition|
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  until condition.call
    raise "Bounded migration observation timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.05
  end
end
run = lambda do |migration|
  ActiveRecord::Base.connection_pool.with_connection do |connection|
    if migration.disable_ddl_transaction
      migration.new.migrate(:up)
    else
      connection.transaction { migration.new.migrate(:up) }
    end
  end
end
start = lambda do |migration, paused: false|
  started = Queue.new
  reached = Queue.new
  release = Queue.new
  worker = Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      before = %w[lock_timeout statement_timeout].to_h { |setting| [ setting, connection.select_value("SHOW #{setting}") ] }
      started << connection.raw_connection.backend_pid
      subscriber = nil
      if paused
        thread = Thread.current
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          next unless Thread.current == thread && payload[:sql].match?(/(?:CREATE INDEX.*ON "events"|ALTER TABLE "events" VALIDATE CONSTRAINT)/)
          reached << true
          release.pop
        end
      end
      error = nil
      begin
        run.call(migration)
      rescue StandardError => exception
        error = exception
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end
      after = %w[lock_timeout statement_timeout].to_h { |setting| [ setting, connection.select_value("SHOW #{setting}") ] }
      { error: error, before: before, after: after }
    end
  end
  [ Timeout.timeout(5) { started.pop }, reached ]
end
finish = lambda do
  assert.call(worker.join(12), "Migration worker exceeded its bound")
  result = worker.value
  assert.call(result[:before] == result[:after], "Connection timeouts were not restored")
  result
end
locks = lambda do |pid|
  observer.exec_params("SELECT mode FROM pg_locks WHERE pid = $1 AND relation = 'events'::regclass AND granted", [ pid ]).map { |row| row.fetch("mode") }
end
probe = lambda do |blocked|
  observer.exec("SET lock_timeout = '200ms'")
  outcomes = [ "SELECT id FROM events LIMIT 1", "UPDATE events SET title = title WHERE id = (SELECT max(id) FROM events)" ].map do |sql|
    begin
      observer.exec(sql)
      "allowed"
    rescue PG::LockNotAvailable
      "bounded_lock_timeout"
    end
  end
  expected = blocked ? "bounded_lock_timeout" : "allowed"
  assert.call(outcomes.all? { |outcome| outcome == expected }, "Independent reader/writer lock contract differs: #{outcomes}")
  outcomes
ensure
  observer.exec("SET lock_timeout = '0'")
end

begin
  assert.call(observer.exec("SELECT to_regclass('community_groups') AS relation").first["relation"].nil?, "Scratch DB already contains community groups")
  assert.call(observer.exec("SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'events' AND column_name = 'community_group_id'").ntuples.zero?, "Scratch DB already contains the event link")
  ids = observer.exec("SELECT id FROM events ORDER BY id").map { |row| row.fetch("id").to_i }
  assert.call(ids.size == 72, "Use the prepared 72-event synthetic main-schema scratch database")
  facts = lambda do
    rows = observer.exec_params("SELECT (to_jsonb(events) - 'community_group_id')::text AS facts FROM events WHERE id = ANY($1::bigint[]) ORDER BY id", [ "{#{ids.join(',')}}" ]).map { |row| JSON.parse(row.fetch("facts")) }
    Digest::SHA256.hexdigest(JSON.generate(rows))
  end
  before_facts = facts.call
  if mode == "baseline"
    pid, reached = start.call(CreateCommunityGroups, paused: true)
    Timeout.timeout(10) { reached.pop }
    held = locks.call(pid)
    assert.call(held.include?("AccessExclusiveLock"), "Old full transaction did not retain the expected exclusive event lock")
    report[:old_long_phase] = { event_locks: held, independent_read_write: probe.call(true) }
    release << true
    result = finish.call
    raise result[:error] if result[:error]
  else
    reader = PG.connect(url)
    reader.exec("BEGIN")
    reader.exec("SELECT id FROM events LIMIT 1")
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    start.call(CreateCommunityGroups)
    result = finish.call
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    reader.exec("ROLLBACK")
    reader.close
    assert.call(result[:error].is_a?(ActiveRecord::LockWaitTimeout), "Held reader did not cause the expected bounded first-stage failure")
    assert.call(elapsed.between?(4.5, 10), "First-stage lock wait was not bounded to about five seconds")
    assert.call(observer.exec("SELECT to_regclass('community_groups') AS relation").first["relation"].nil?, "Failed short stage left a group table behind")
    assert.call(observer.exec("SELECT 1 FROM information_schema.columns WHERE table_name = 'events' AND column_name = 'community_group_id'").ntuples.zero?, "Failed short stage left an event link behind")
    assert.call(facts.call == before_facts, "First-stage abort changed retained event facts")
    report[:held_reader_abort] = { error: result[:error].class.name, seconds: elapsed, stage_rolled_back: true }
    run.call(CreateCommunityGroups)
    writer = PG.connect(url)
    writer.exec("BEGIN")
    writer.exec("UPDATE events SET title = title WHERE id = (SELECT min(id) FROM events)")
    pid, = start.call(AddCommunityGroupEventsIndex)
    wait_until.call(4) do
      observer.exec_params("SELECT 1 FROM pg_index WHERE indexrelid = to_regclass($1) AND NOT indisvalid", [ index_name ]).ntuples == 1
    end
    assert.call(!locks.call(pid).include?("AccessExclusiveLock"), "Concurrent index acquired an exclusive event lock")
    report[:actual_concurrent_wait] = { event_locks: locks.call(pid), independent_read_write: probe.call(false) }
    assert.call(observer.exec_params("SELECT pg_cancel_backend($1) AS cancelled", [ pid ]).first["cancelled"] == "t", "Owned concurrent build was not cancelled")
    result = finish.call
    writer.exec("ROLLBACK")
    writer.close
    assert.call(result[:error].is_a?(ActiveRecord::QueryCanceled), "Concurrent cancellation did not surface its failure")
    assert.call(observer.exec_params("SELECT 1 FROM pg_index WHERE indexrelid = to_regclass($1) AND NOT indisvalid", [ index_name ]).ntuples == 1, "Real failed build did not retain an invalid owned index")
    report[:cancelled_index] = { error: result[:error].class.name, invalid_index_retained: true, timeouts_restored: true }
    pid, reached = start.call(AddCommunityGroupEventsIndex, paused: true)
    Timeout.timeout(10) { reached.pop }
    held = locks.call(pid)
    assert.call(!held.include?("AccessExclusiveLock"), "Concurrent retry retained an exclusive event lock")
    report[:new_long_phase] = { event_locks: held, independent_read_write: probe.call(false) }
    release << true
    result = finish.call
    raise result[:error] if result[:error]
    report[:invalid_index_retry] = { rebuilt_validly: true, timeouts_restored: true }
    run.call(AddCommunityGroupEventForeignKey)
    definition = observer.exec_params("SELECT convalidated FROM pg_constraint WHERE conrelid = 'events'::regclass AND conname = $1", [ foreign_key ]).first
    assert.call(definition.fetch("convalidated") == "f", "FK was scanned during its short addition stage")
    other = observer.exec("INSERT INTO organizations (name, slug, created_at, updated_at) VALUES ('Synthetic migration foreign tenant', 'synthetic-migration-foreign', now(), now()) RETURNING id").first.fetch("id")
    group = observer.exec_params("INSERT INTO community_groups (organization_id, name, slug, created_at, updated_at) VALUES ($1, 'Synthetic foreign group', 'synthetic-foreign', now(), now()) RETURNING id", [ other ]).first.fetch("id")
    rejected = []
    [
      [ "UPDATE events SET community_group_id = $1 WHERE id = $2", [ group, ids.first ] ],
      [ "INSERT INTO events (organization_id, community_group_id, title, slug, created_at, updated_at) SELECT organization_id, $1, 'Synthetic invalid migration event', 'synthetic-invalid-migration', now(), now() FROM events WHERE id = $2", [ group, ids.first ] ]
    ].each do |sql, arguments|
      begin
        observer.exec_params(sql, arguments)
        rejected << false
      rescue PG::ForeignKeyViolation
        rejected << true
      end
    end
    assert.call(rejected == [ true, true ], "NOT VALID foreign key allowed a new cross-tenant update or insert")
    report[:not_valid_write_enforcement] = { validated_before_stage: false, cross_tenant_update_and_insert_rejected: true }
    pid, reached = start.call(ValidateCommunityGroupEventForeignKey, paused: true)
    Timeout.timeout(10) { reached.pop }
    held = locks.call(pid)
    assert.call(held.include?("ShareUpdateExclusiveLock") && !held.include?("AccessExclusiveLock"), "Validation did not retain its lower event lock mode")
    report[:validation] = { event_locks: held, independent_read_write: probe.call(false) }
    release << true
    result = finish.call
    raise result[:error] if result[:error]
  end
  index = ActiveRecord::Base.connection_pool.with_connection { |connection| connection.indexes(:events).find { |candidate| candidate.name == index_name } }
  assert.call(index && index.valid? && index.columns == %w[organization_id community_group_id starts_at], "Final concurrent index is absent, invalid or mismatched")
  validated = observer.exec_params("SELECT convalidated FROM pg_constraint WHERE conrelid = 'events'::regclass AND conname = $1", [ foreign_key ]).first.fetch("convalidated") == "t"
  assert.call(validated, "Final tenant foreign key is not validated")
  assert.call(facts.call == before_facts, "Retained event facts changed")
  report[:final] = { valid_index: true, validated_foreign_key: true, retained_events: ids.size, retained_facts_sha256: before_facts, retained_facts_unchanged: true }
  puts JSON.pretty_generate(report.merge(result: "PASS"))
ensure
  release << true if release
  [ reader, writer ].compact.each do |client|
    next if client.finished?
    client.exec("ROLLBACK") if client.transaction_status != PG::PQTRANS_IDLE
    client.close
  end
  if worker&.alive?
    observer.exec_params("SELECT pg_cancel_backend($1)", [ pid ]) if pid
    worker.join(12)
  end
  observer.close unless observer.finished?
  ActiveRecord::Base.connection_pool.disconnect!
end
