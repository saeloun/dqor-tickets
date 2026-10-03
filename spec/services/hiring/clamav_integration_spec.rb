require "rails_helper"

# Opt in only on an isolated scanner validation worker with real official databases.
# Never substitutes test signatures or protocol doubles for antivirus verification.
RSpec.describe "Local ClamAV engine integration" do
  before do
    skip "Real engine validation not enabled; no virus scan is claimed" unless ENV["HIRING_CLAMAV_INTEGRATION"] == "true"
  end

  let(:scanner) { Hiring::ClamavScanner.new(executable: ENV.fetch("HIRING_CLAMSCAN_PATH"), database: ENV.fetch("HIRING_CLAMAV_DATABASE")) }

  it "scans a synthetic blank PDF with real signatures" do
    pdf = "%PDF-1.4\n"
    offsets = [ 0 ]
    [ "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] >>" ].each_with_index do |object, index|
      offsets << pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
    end
    start = pdf.bytesize
    pdf << "xref\n0 4\n0000000000 65535 f \n"
    offsets.drop(1).each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n#{start}\n%%EOF\n"
    expect(scanner.scan(pdf).status).to eq("clean")
  end

  it "detects the standard harmless EICAR test string with real signatures" do
    fixture = 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'
    expect(fixture.bytesize).to eq(68)
    expect(scanner.scan(fixture).status).to eq("infected")
  end
end
