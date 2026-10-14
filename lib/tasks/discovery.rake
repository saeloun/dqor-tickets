namespace :discovery do
  desc "Validate and import an approved factual event snapshot; never import attendees or media"
  task :import, [ :path, :source_key ] => :environment do |_task, args|
    abort "Provide a reviewed snapshot path and source key." unless args[:path].present? && args[:source_key].present?
    puts JSON.generate(Discovery::Import.call(path: args[:path], source_key: args[:source_key]))
  rescue Discovery::Dataset::Invalid => error
    abort error.message
  end
end
