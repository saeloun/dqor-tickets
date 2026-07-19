require "tempfile"
require "zlib"

namespace :db do
  desc "Back up the primary SQLite database to R2"
  task backup: :environment do
    BackupDatabaseJob.perform_now
  end

  namespace :backup do
    desc "Restore an R2 database backup to storage/restored.sqlite3"
    task :restore, [ :key ] => :environment do |_task, arguments|
      key = arguments[:key].to_s
      abort "Provide a db-backups key" unless key.start_with?(BackupDatabaseJob::PREFIX)

      configuration = BackupDatabaseJob.r2_configuration
      abort "R2 is not configured" unless configuration.values.all?(&:present?)

      destination = Rails.root.join("storage/restored.sqlite3")
      abort "#{destination} already exists; move or remove it first" if destination.exist?

      Tempfile.create([ "dqor-restore", ".sqlite3.gz" ]) do |archive|
        archive.close
        BackupDatabaseJob.r2_client(configuration).get_object(
          bucket: configuration.fetch(:bucket),
          key:,
          response_target: archive.path
        )

        Tempfile.create([ "restored", ".sqlite3" ], destination.dirname) do |database|
          Zlib::GzipReader.open(archive.path) { |gzip| IO.copy_stream(gzip, database) }
          database.flush
          database.fsync
          File.link(database.path, destination)
        end
      end

      puts "Restored #{key} to #{destination}"
      puts "Verify it with: sqlite3 #{destination} 'PRAGMA integrity_check;'"
      puts "The live database was not changed; replace it manually only after verification."
    end
  end
end
