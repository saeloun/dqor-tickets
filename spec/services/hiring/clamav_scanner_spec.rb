require "rails_helper"
require "rbconfig"

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

  it "fails closed for missing engine, missing databases and oversized input" do
    expect(described_class.new(executable: "/missing/clamscan", database: @database).scan("fixture").status).to eq("unavailable")
    engine = scanner('puts "#{ARGV.last}: OK"')
    expect(engine.scan("x" * (described_class::MAX_BYTES + 1)).status).to eq("unavailable")
    File.unlink(File.join(@database, "daily.cvd"))
    expect(engine.scan("fixture").status).to eq("unavailable")
  end
end
