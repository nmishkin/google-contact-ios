# google-contacts-ios

A native SwiftUI client (iOS/iPadOS/macOS) for full-fidelity access to Google Contacts data — labels, groups, custom fields, and multiple typed emails/phones/addresses — that Apple's Contacts app normally flattens or drops when synced from a Google account.

See the design spec ([docs/superpowers/specs/2026-09-19-google-contacts-app-design.md](docs/superpowers/specs/2026-09-19-google-contacts-app-design.md)) and implementation plan ([docs/superpowers/plans/2026-09-19-google-contacts-app.md](docs/superpowers/plans/2026-09-19-google-contacts-app.md)) for details.

The Xcode project is `GoogleContacts.xcodeproj`, generated from `project.yml`; app code lives under `App`, with shared logic in the `GoogleContactsKit` Swift package under `Packages`.
