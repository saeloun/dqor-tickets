require "rails_helper"

RSpec.describe "Native attendee locked lifecycle", type: :model, native_attendee_bridge: true do
  self.use_transactional_tests = false

  before do
    @user = User.create!(email: "native-concurrent-#{SecureRandom.hex(8)}@example.test")
    @user_ids = [ @user.id ]
  end

  after do
    User.where(id: @user_ids).delete_all
  end

  def verified_attempt(identity = @user)
    record, creation = NativeAttendeeAuthorization.start!(client_id: "dqor-ios", callback_uri: NativeAttendeeBridgeHelpers::CALLBACK,
      state: NativeAttendeeBridgeHelpers::STATE, code_challenge: NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER), method: "S256")
    record.request_email!(identity.email, proof: creation)
    token = record.prepare_email!(identity.email)
    payload = NativeAttendeeAuthorization.verifier.verified(token, purpose: NativeAttendeeAuthorization::PURPOSE)
    proof = record.verify!(payload)
    [ record, proof ]
  end

  def race(count = 6, pool: ActiveRecord::Base.connection_pool)
    start = Queue.new
    threads = Array.new(count) do |index|
      Thread.new do
        start.pop
        pool.with_connection { yield index }
      rescue StandardError => error
        error
      end
    end
    count.times { start << true }
    results = threads.map do |thread|
      expect(thread.join(6)).not_to be_nil
      thread.value
    end
    results
  end

  it "matches the RFC7636 S256 vector and persists immutable binding and terminal checks" do
    expect(NativeAttendeeAuthorization.challenge(NativeAttendeeBridgeHelpers::VERIFIER)).to eq("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    record, proof = verified_attempt
    expect { record.update!(email_snapshot: "injected@example.test") }.to raise_error(ActiveRecord::RecordInvalid)
    record.reload.cancel!(proof: proof)
    expect { record.update!(status: :verified) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(record.reload).to be_canceled
  end

  it "permits exactly one authorization code under simultaneous consent" do
    record, proof = verified_attempt
    results = race { NativeAttendeeAuthorization.find(record.id).issue_code!(proof: proof) }
    codes = results.grep(String)
    expect(codes.size).to eq(1)
    expect(results.grep(NativeAttendeeAuthorization::Invalid).size).to eq(5)
    expect(record.reload.code_digest).to eq(NativeAttendeeAuthorization.digest(codes.first))
    expect(record).to be_issued
  end

  it "atomically consumes a code and creates exactly one session on separate connections" do
    record, proof = verified_attempt
    code = record.issue_code!(proof: proof)
    results = race do
      NativeAttendeeAuthorization.exchange(code: code, code_verifier: NativeAttendeeBridgeHelpers::VERIFIER,
        client_id: "dqor-ios", callback_uri: NativeAttendeeBridgeHelpers::CALLBACK)
    end
    expect(results.compact.size).to eq(1)
    expect(results.grep(StandardError)).to be_empty
    expect(NativeAttendeeSession.where(native_attendee_authorization_id: record.id).count).to eq(1)
    expect(record.reload).to be_consumed
    expect { NativeAttendeeSession.issue!(record) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "finishes concurrent User deletion against consent and exchange without inverse-lock deadlock" do
    %i[consent exchange].each do |operation|
      identity = User.create!(email: "native-delete-#{SecureRandom.hex(8)}@example.test")
      @user_ids << identity.id
      record, proof = verified_attempt(identity)
      code = record.issue_code!(proof: proof) if operation == :exchange
      results = race(2) do |index|
        if index.zero?
          User.find(identity.id).destroy!
          :deleted
        elsif operation == :consent
          NativeAttendeeAuthorization.find(record.id).issue_code!(proof: proof)
        else
          NativeAttendeeAuthorization.exchange(code: code, code_verifier: NativeAttendeeBridgeHelpers::VERIFIER,
            client_id: "dqor-ios", callback_uri: NativeAttendeeBridgeHelpers::CALLBACK)
        end
      end
      expect(results.grep(StandardError).reject { |error| error.is_a?(ActiveRecord::RecordNotFound) || error.is_a?(NativeAttendeeAuthorization::Invalid) }).to be_empty
      expect(User.where(id: identity.id)).not_to exist
      expect(NativeAttendeeSession.where(user_id: identity.id)).not_to exist
    end
  end

  it "serializes cold shared Solid Cache counters across connections and retains the bounded TTL" do
    store = SolidCache::Store.new(namespace: "native-attendee-concurrency-#{SecureRandom.hex(8)}")
    allow(Rails).to receive(:cache).and_return(store)
    SolidCache::Entry.columns
    identity = "synthetic-shared-ip"
    SolidCache::Record.connection_pool.release_connection
    results = race(4, pool: SolidCache::Record.connection_pool) { NativeAttendee::RateLimit.check!("cold", identity, maximum: 2, within: 3.minutes) }
    expect(results.grep(StandardError).reject { |error| error.is_a?(NativeAttendee::RateLimit::Exceeded) }).to be_empty
    expect(results.count(nil)).to eq(2)
    expect(results.grep(NativeAttendee::RateLimit::Exceeded).size).to eq(2)
    key = "native-attendee-rate:cold:#{Digest::SHA256.hexdigest(identity)}"
    expect(store.read(key)).to eq(4)
    expect(SolidCache::Entry.pluck(:key).join).not_to include(identity)
    travel 181.seconds do
      expect(store.read(key)).to be_nil
      expect { NativeAttendee::RateLimit.check!("cold", identity, maximum: 3, within: 3.minutes) }.not_to raise_error
    end
  ensure
    store&.clear
  end

  it "denies boundedly when another connection holds the same rate-counter lock" do
    identity = "synthetic-contended-ip"
    key = "native-attendee-rate:blocked:#{Digest::SHA256.hexdigest(identity)}"
    lock_id = Digest::SHA256.digest(key).unpack1("q>")
    ready = Queue.new
    release = Queue.new
    holder = Thread.new do
      SolidCache::Record.connection_pool.with_connection do |connection|
        SolidCache::Record.transaction do
          connection.execute("SELECT pg_advisory_xact_lock(#{lock_id})")
          ready << true
          release.pop
        end
      end
    end
    ready.pop
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { NativeAttendee::RateLimit.check!("blocked", identity, maximum: 3, within: 3.minutes) }.to raise_error(NativeAttendee::RateLimit::Unavailable)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
  ensure
    release << true if release
    holder&.join(5)
  end
end
