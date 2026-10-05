# Default disabled adapter. It deliberately cannot release files.
# The optional local ClamAV adapter is configured only on an isolated worker.
class Hiring::ResumeScanner
  Verdict = Data.define(:status, :digest)

  def scan(bytes)
    Verdict.new(status: "unavailable", digest: Digest::SHA256.hexdigest(bytes))
  end
end
