# No scanner executable was found. This adapter deliberately cannot release files.
# A future supported local scanner must run in an isolated worker, not the web process.
class Hiring::ResumeScanner
  Verdict = Data.define(:status, :digest)

  def scan(bytes)
    Verdict.new(status: "unavailable", digest: Digest::SHA256.hexdigest(bytes))
  end
end
