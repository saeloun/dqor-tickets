#if DEBUG
import Foundation

enum OwnedEventsFixture {
    static let catalog = #"""
    {
      "schema_version": 1,
      "events": [
        {
          "id": "hosted-event-101",
          "ownership": "hosted_event",
          "title": "Synthetic meetup contract fixture",
          "starts_at": "2026-11-07T00:15:00+05:30",
          "ends_at": "2026-11-07T01:30:00+05:30",
          "start_date": "2026-11-07",
          "end_date": "2026-11-07",
          "timezone": "Asia/Kolkata",
          "organizer": {
            "name": "Synthetic organizers",
            "slug": "synthetic-organizers"
          },
          "details_path": "/events/synthetic-organizers/synthetic-meetup"
        }
      ],
      "pagination": {
        "page": 1,
        "per_page": 24,
        "total": 1
      },
      "content_version": "4167d05e43118935a9ed68f3a171fdd98c7a4a302ef064d6dcb257fbc32ee1c9"
    }
    """#
    static let detail = #"""
    {
      "schema_version": 1,
      "event": {
        "id": "hosted-event-101",
        "ownership": "hosted_event",
        "title": "Synthetic meetup contract fixture",
        "starts_at": "2026-11-07T00:15:00+05:30",
        "ends_at": "2026-11-07T01:30:00+05:30",
        "start_date": "2026-11-07",
        "end_date": "2026-11-07",
        "timezone": "Asia/Kolkata",
        "organizer": {
          "name": "Synthetic organizers",
          "slug": "synthetic-organizers"
        },
        "details_path": "/events/synthetic-organizers/synthetic-meetup"
      },
      "content_version": "629dceedc06e191307d3bf55eeca52123a8adb61c65bf0e093f75c0fb0fa0812"
    }
    """#
}
#endif
