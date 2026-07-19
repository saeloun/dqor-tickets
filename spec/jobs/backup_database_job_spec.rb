require "rails_helper"
require "aws-sdk-s3"

RSpec.describe BackupDatabaseJob, type: :job do
  let(:configuration) do
    {
      endpoint: "https://account.r2.cloudflarestorage.com",
      access_key_id: "access-key",
      secret_access_key: "secret-key",
      bucket: "tickets"
    }
  end

  it "uploads an online backup and prunes objects older than seven days" do
    timestamp = Time.zone.local(2026, 7, 19, 12, 34)
    client = Aws::S3::Client.new(stub_responses: true)
    client.stub_responses(:list_objects_v2, {
      contents: [
        { key: "db-backups/2026/07/11/1200.sqlite3.gz", last_modified: timestamp - 8.days },
        { key: "db-backups/2026/07/12/1234.sqlite3.gz", last_modified: timestamp - 7.days }
      ],
      is_truncated: false
    })
    allow(described_class).to receive(:r2_configuration).and_return(configuration)
    allow(described_class).to receive(:r2_client).with(configuration).and_return(client)
    connection = ActiveRecord::Base.connection
    expect(connection).to receive(:execute) do |sql|
      expect(sql).to start_with("VACUUM INTO '")
      File.binwrite(sql.match(/'(.+)'/)[1], "SQLite format 3\u0000backup")
    end

    expect(described_class.perform_now(timestamp)).to eq("db-backups/2026/07/19/1234.sqlite3.gz")

    upload = client.api_requests.find { |request| request.fetch(:operation_name) == :put_object }.fetch(:params)
    deletion = client.api_requests.find { |request| request.fetch(:operation_name) == :delete_objects }.fetch(:params)
    expect(upload).to include(
      bucket: "tickets",
      key: "db-backups/2026/07/19/1234.sqlite3.gz",
      content_encoding: "gzip"
    )
    expect(deletion.dig(:delete, :objects)).to eq([ { key: "db-backups/2026/07/11/1200.sqlite3.gz" } ])
  end

  it "skips cleanly when R2 is not configured" do
    allow(described_class).to receive(:r2_configuration).and_return(configuration.merge(bucket: nil))
    expect(described_class).not_to receive(:r2_client)
    expect(ActiveRecord::Base.connection).not_to receive(:execute)
    expect(Rails.logger).to receive(:warn).with("Skipping database backup because R2 is not configured")

    expect(described_class.perform_now).to be_nil
  end
end
