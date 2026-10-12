# Private community workspace

This bounded slice comes from the reviewed tenant-owned community work in PR240 and its PR245 pagination follow-up, preserved in `dqor-organizer-foundation-20261012`. It starts from main `6eee2b9cfc89ea03ec2a3128cf0a525cc2fcda69`. Public group HTML, catalog APIs, publication actions and external discovery are excluded.

All three existing gates must be enabled in an authorized environment: `ORGANIZER_PLATFORM_ENABLED`, `FREE_EVENT_PILOT_ENABLED` and `MEETUP_GROUPS_ENABLED`. This change does not activate any gate. Existing verified organization owners and admins can create/edit private groups and start a linked draft event directly inside a group. Existing editors and viewers can read groups only. A fresh locked membership and tenant-scoped group protect each write. Saving an event does not publish it, create tickets, invite people or open registration.

The existing additive `20261011030000_create_community_groups` migration creates a group table, adds a nullable event relation and enforces the matching organization with a composite foreign key. Existing event rows remain unlinked. Deployment requires actual migration review/rehearsal, backup and rollback readiness; reverting this migration would delete group data and remove links, so do not run its destructive down without explicit approval.

Real group creation, organizer access grants, public group publication, registration activation, billing, credentials and production feature settings remain separate approval/release gates. The conference, public owned-event API and native application sources are preserved.
