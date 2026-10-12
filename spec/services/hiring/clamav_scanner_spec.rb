require "rails_helper"
require "rbconfig"
require "open3"

RSpec.describe Hiring::ClamavScanner do
  around do |example|
    Dir.mktmpdir("hiring-scanner-test-") do |directory|
      @directory = directory
      @database = File.join(directory, "database")
      Dir.mkdir(@database)
      %w[main.cvd daily.cvd].each { |name| File.write(File.join(@database, name), "TEST DOUBLE ONLY") }
      example.run
    end
  end

  # These are process-protocol doubles, never virus signatures or real ClamAV scans.
  def scanner(body, timeout: 2)
    executable = File.join(@directory, "test-engine")
    File.write(executable, "#!#{RbConfig.ruby}\n#{body}\n", perm: 0o700)
    described_class.new(executable: executable, database: @database, timeout: timeout)
  end

  def wait_for_zombie(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    loop do
      state, status = Open3.capture2("ps", "-o", "stat=", "-p", pid.to_s)
      return if status.success? && state.strip.start_with?("Z")

      raise "Owned synthetic child did not finish" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
  end

  def scan_with_group_denial(completed: false, wait_error: false)
    body = 'puts "x" * 100000; STDOUT.flush'
    body += "; sleep 2" unless completed
    engine = scanner(body)
    executable = File.join(@directory, "test-engine")
    observed = { recovery_calls: 0 }
    real_wait = Process.method(:waitpid2)

    allow(Process).to receive(:spawn).and_wrap_original do |original, *args, **options|
      pid = original.call(*args, **options)
      if args[1] == [ executable, "clamscan" ]
        observed.merge!(pid: pid, stdout: options.fetch(:out), input_directory: File.dirname(args.last))
      end
      pid
    end

    allow(Process).to receive(:waitpid2).and_wrap_original do |original, pid, flags = 0|
      if pid == observed[:pid] && flags == Process::WNOHANG
        next nil unless observed[:denied]

        observed[:recovery_calls] += 1
        raise Errno::ECHILD if wait_error

        observed[:recovery] = original.call(pid, flags)
      else
        original.call(pid, flags)
      end
    end

    allow(Process).to receive(:kill).and_wrap_original do |original, signal, target|
      if observed[:pid] && signal == "KILL" && target == -observed[:pid]
        observed[:flood_bytes] = File.size(observed.fetch(:stdout))
        wait_for_zombie(observed[:pid]) if completed
        observed[:denied] = true
        raise Errno::EPERM
      end
      original.call(signal, target)
    end

    observed[:verdict] = engine.scan("%PDF-synthetic")
    observed
  ensure
    if observed && observed[:pid] && !observed[:recovery]
      begin
        real_wait.call(observed[:pid])
      rescue Errno::ECHILD
      end
    end
  end

  it "accepts only exact bytes, explicit OK and exit zero; uses private files and defensive arguments" do
    engine = scanner(<<~RUBY)
      required = %w[--official-db-only=yes --fail-if-cvd-older-than=3 --alert-exceeds-max=yes --alert-encrypted=yes --max-scantime=15000 --bytecode-unsigned=no]
      abort unless (required - ARGV).empty?
      abort unless File.stat(ARGV.last).mode & 0777 == 0600
      abort unless File.stat(File.dirname(ARGV.last)).mode & 0777 == 0700
      abort unless File.binread(ARGV.last) == "%PDF-synthetic"
      puts "\#{ARGV.last}: OK"
    RUBY
    result = engine.scan("%PDF-synthetic")
    expect(result.status).to eq("clean")
    expect(result.digest).to eq(Digest::SHA256.hexdigest("%PDF-synthetic"))
  end

  it "quarantines detection, engine errors, signals, empty results and warnings" do
    [ 'exit 1', 'exit 2', 'Process.kill("KILL", Process.pid)', 'exit 0', 'warn "database warning"; puts "#{ARGV.last}: OK"', 'puts "other-file: OK"' ].each do |body|
      expect(scanner(body).scan("%PDF-synthetic").status).to eq("quarantined")
    end
  end

  it "kills and reaps a timed-out child and cleans its private directory" do
    marker = File.join(@directory, "process")
    engine = scanner("File.write(#{marker.inspect}, [Process.pid, ARGV.last].join(\"\\n\")); sleep 10", timeout: 1.5)
    expect(engine.scan("%PDF-synthetic").status).to eq("quarantined")
    pid, input = File.read(marker).split("\n")
    expect { Process.kill(0, pid.to_i) }.to raise_error(Errno::ESRCH)
    expect(File.exist?(File.dirname(input))).to eq(false)
  end

  it "reports an explicit detection only for a FOUND result and exit one" do
    engine = scanner('puts "#{ARGV.last}: Test.Signature FOUND"; exit 1')
    expect(engine.scan("synthetic").status).to eq("infected")
  end

  it "rejects output floods and bytes modified by the child" do
    expect(scanner('puts "x" * 100000').scan("%PDF-synthetic").status).to eq("quarantined")
    expect(scanner('File.write(ARGV.last, "changed"); puts "#{ARGV.last}: OK"').scan("%PDF-synthetic").status).to eq("quarantined")
  end

  it "quarantines a real output flood when denied termination finds its child already completed" do
    observed = scan_with_group_denial(completed: true)

    expect(observed[:verdict].status).to eq("quarantined")
    expect(observed[:flood_bytes]).to eq(100001)
    expect(observed[:flood_bytes]).to be > described_class::OUTPUT_LIMIT
    pid, status = observed.fetch(:recovery)
    expect(pid).to eq(observed[:pid])
    expect(status).to be_a(Process::Status)
    expect(status.exitstatus).to eq(0)
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    expect(File.exist?(observed[:input_directory])).to be(false)
  end

  it "remains unavailable when denied termination finds its child still running" do
    observed = scan_with_group_denial

    expect(observed[:verdict].status).to eq("unavailable")
    expect(observed[:flood_bytes]).to eq(100001)
    expect(observed[:recovery]).to be_nil
    expect(observed[:recovery_calls]).to eq(1)
    expect(File.exist?(observed[:input_directory])).to be(false)
  end

  it "remains unavailable when child status cannot be recovered after denied termination" do
    observed = scan_with_group_denial(completed: true, wait_error: true)

    expect(observed[:verdict].status).to eq("unavailable")
    expect(observed[:flood_bytes]).to eq(100001)
    expect(observed[:recovery]).to be_nil
    expect(observed[:recovery_calls]).to eq(1)
    expect(File.exist?(observed[:input_directory])).to be(false)
  end

  it "fails closed for missing engine, missing databases and oversized input" do
    expect(described_class.new(executable: "/missing/clamscan", database: @database).scan("fixture").status).to eq("unavailable")
    engine = scanner('puts "#{ARGV.last}: OK"')
    expect(engine.scan("x" * (described_class::MAX_BYTES + 1)).status).to eq("unavailable")
    File.unlink(File.join(@database, "daily.cvd"))
    expect(engine.scan("fixture").status).to eq("unavailable")
  end
end
