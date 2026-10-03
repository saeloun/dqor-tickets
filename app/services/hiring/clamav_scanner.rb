require "tmpdir"
require "digest"

# One-shot local CLI only. Configure on an isolated hiring_scans worker, never web.
class Hiring::ClamavScanner
  MAX_BYTES = 5.megabytes
  OUTPUT_LIMIT = 64.kilobytes

  def initialize(executable:, database:, timeout: 30)
    @executable = executable.to_s
    @database = database.to_s
    @timeout = timeout.to_f.clamp(0.05, 60)
  end

  def scan(bytes)
    bytes = bytes.dup.freeze
    digest = Digest::SHA256.hexdigest(bytes)
    return verdict("unavailable", digest) unless configured? && bytes.bytesize.between?(1, MAX_BYTES)

    Dir.mktmpdir("hiring-clamav-") do |directory|
      input = File.join(directory, "resume.pdf")
      output = File.join(directory, "stdout")
      errors = File.join(directory, "stderr")
      File.write(input, bytes, mode: "wb", perm: 0o600)
      [ output, errors ].each { |path| File.write(path, "", perm: 0o600) }
      status = run(input, output, errors, directory)
      return verdict("quarantined", digest) unless status && File.size(output) <= OUTPUT_LIMIT && File.zero?(errors)
      if status.exitstatus == 1 && File.binread(output).match?(/\A#{Regexp.escape(input)}: [^\n]+ FOUND\n\z/)
        return verdict("infected", digest)
      end
      return verdict("quarantined", digest) unless status.success?
      return verdict("quarantined", digest) unless File.binread(output) == "#{input}: OK\n"
      return verdict("quarantined", digest) unless Digest::SHA256.file(input).hexdigest == digest

      verdict("clean", digest)
    end
  rescue SystemCallError, IOError, ArgumentError
    verdict("unavailable", digest)
  end

  private
    def configured?
      @executable.start_with?("/") && File.file?(@executable) && File.executable?(@executable) &&
        @database.start_with?("/") && File.directory?(@database) &&
        %w[main daily].all? { |name| %w[cvd cld].any? { |extension| File.file?(File.join(@database, "#{name}.#{extension}")) } }
    end

    def verdict(status, digest)
      Hiring::ResumeScanner::Verdict.new(status: status, digest: digest)
    end

    def run(input, output, errors, directory)
      arguments = [ "--database=#{@database}", "--official-db-only=yes",
        "--fail-if-cvd-older-than=3", "--no-summary", "--stdout", "--scan-pdf=yes",
        "--alert-encrypted=yes", "--alert-exceeds-max=yes", "--disable-cache",
        "--max-filesize=5M", "--max-scansize=32M", "--max-files=100", "--max-recursion=8",
        "--max-scantime=15000", "--bytecode-timeout=5000", "--bytecode-unsigned=no",
        "--tempdir=#{directory}", input ]
      options = { in: File::NULL, out: output, err: errors, pgroup: true, unsetenv_others: true,
        rlimit_core: 0, rlimit_cpu: 20, rlimit_fsize: 64.megabytes }
      # macOS does not reliably enforce RLIMIT_AS; production needs a memory-limited worker.
      options[:rlimit_as] = 4.gigabytes if RUBY_PLATFORM.include?("linux")
      pid = Process.spawn({ "LC_ALL" => "C", "PATH" => "/usr/bin:/bin", "TMPDIR" => directory }, [ @executable, "clamscan" ], *arguments, **options)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      loop do
        result = Process.waitpid2(pid, Process::WNOHANG)
        if result
          pid = nil
          return result.last
        end
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline || File.size(output) > OUTPUT_LIMIT || File.size(errors) > OUTPUT_LIMIT
        sleep 0.02
      end
    ensure
      if pid
        begin
          Process.kill("KILL", -pid)
        rescue Errno::ESRCH
          # Child exited between timeout and termination.
        end
        Process.waitpid(pid)
      end
    end
end
