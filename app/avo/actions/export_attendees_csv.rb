class Avo::Actions::ExportAttendeesCsv < Avo::BaseAction
  self.name = "Export attendees CSV"

  def handle(query:, **)
    download Order.attendees_csv(query), "attendees-#{Date.current}.csv"
  end
end
