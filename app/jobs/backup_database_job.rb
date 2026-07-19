require "tmpdir"
require "zlib"

class BackupDatabaseJob < ApplicationJob
  PREFIX = "db-backups/"
  R2_ENV = {
    endpoint: "R2_ENDPOINT",
    access_key_id: "R2_ACCESS_KEY_ID",
    secret_access_key: "R2_SECRET_ACCESS_KEY",
    bucket: "R2_BUCKET"
  }.freeze

  def perform(timestamp = Time.current)
    configuration = self.class.r2_configuration
    unless configuration.values.all?(&:present?)
      Rails.logger.warn("Skipping database backup because R2 is not configured")
      return
    end

    timestamp = timestamp.in_time_zone
    client = self.class.r2_client(configuration)
    key = "#{PREFIX}#{timestamp.strftime('%Y/%m/%d/%H%M')}.sqlite3.gz"

    Dir.mktmpdir("dqor-backup") do |directory|
      database_path = File.join(directory, "backup.sqlite3")
      archive_path = "#{database_path}.gz"
      connection = ActiveRecord::Base.connection
      connection.execute("VACUUM INTO #{connection.quote(database_path)}")

      Zlib::GzipWriter.open(archive_path) do |archive|
        File.open(database_path, "rb") { |database| IO.copy_stream(database, archive) }
      end

      File.open(archive_path, "rb") do |archive|
        client.put_object(
          bucket: configuration.fetch(:bucket),
          key:,
          body: archive,
          content_type: "application/vnd.sqlite3",
          content_encoding: "gzip"
        )
      end
    end

    prune(client, configuration.fetch(:bucket), timestamp - 7.days)
    Rails.logger.info("Uploaded database backup to #{key}")
    key
  end

  def self.r2_configuration
    R2_ENV.transform_values { |name| ENV[name] }
  end

  def self.r2_client(configuration = r2_configuration)
    require "aws-sdk-s3"

    Aws::S3::Client.new(
      endpoint: configuration.fetch(:endpoint),
      access_key_id: configuration.fetch(:access_key_id),
      secret_access_key: configuration.fetch(:secret_access_key),
      region: "auto",
      force_path_style: true,
      request_checksum_calculation: "when_required",
      response_checksum_validation: "when_required"
    )
  end

  private
    def prune(client, bucket, cutoff)
      continuation_token = nil

      loop do
        response = client.list_objects_v2(bucket:, prefix: PREFIX, continuation_token:)
        objects = response.contents.filter_map do |object|
          { key: object.key } if object.last_modified < cutoff
        end
        client.delete_objects(bucket:, delete: { objects: }) if objects.any?

        break unless response.is_truncated

        continuation_token = response.next_continuation_token
      end
    end
end
