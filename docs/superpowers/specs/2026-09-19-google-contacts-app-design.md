# Google Contacts iOS App — Design Spec

Date: 2026-09-19
Status: Approved for implementation planning

## Purpose

A native SwiftUI client that gives full-fidelity access to Google Contacts data —
the fields and structure (labels/groups, custom fields, multiple typed
emails/phones/addresses, organizations, etc.) that Apple's Contacts app flattens
or drops when synced from a Google account. Not a mirror of iOS Contacts; a real
Google Contacts client.

## Audience & distribution

Personal use for now, but the app is architected so nothing blocks a later
public App Store release (no hardcoded assumptions that only one Google account
or one device will ever use it; auth and data layers are generic). Going public
would additionally require Google OAuth verification for the sensitive
`contacts` scope, a privacy policy, and App Store review — none of that is done
now, but the design doesn't preclude it later.

## Platforms

iOS, iPadOS, and macOS from a single SwiftUI codebase and a single Xcode
project with three platform destinations (native macOS, not Mac Catalyst).
Adaptive layout via `NavigationSplitView`, which collapses to a single column
on iPhone and shows sidebar/list/detail on iPad and Mac without separate view
hierarchies per platform.

## V1 scope

In scope:
- Browse, search, view, and edit all modeled contact fields: names (incl.
  phonetic), nickname, photo, starred, birthday (incl. year-less), notes,
  multiple labeled emails/phones/urls/relations, addresses, organizations,
  and Google's user-defined custom fields.
- Labels (Google contact groups): browse/filter by label, assign/remove a
  contact's labels, create/rename/delete labels.
- Create new contacts and delete existing ones.
- Local cache with offline read and offline edit (edits queue and sync when
  back online).

Explicitly out of scope for v1: "Other contacts" (auto-collected, unconfirmed
contacts from Gmail), duplicate detection/merge, batch operations across
multiple contacts at once, 3-way field-level conflict merging (conflicts are
resolved whole-contact, keep-mine-or-theirs).

## Architecture

Four layers, strict one-directional dependencies:

```
UI (SwiftUI)
   -> ContactsRepository (facade)
        -> SyncEngine (actor)
             -> PeopleAPIClient
                  -> GoogleAuth
        -> SwiftData store (ContactsStore)
```

- **GoogleAuth** — wraps the GoogleSignIn-iOS SDK. Exposes sign-in/sign-out,
  silent restore on launch (`restorePreviousSignIn()`), and
  `validAccessToken()` for callers that need a bearer token (the SDK handles
  refresh internally). Requests scope
  `https://www.googleapis.com/auth/contacts`.
- **PeopleAPIClient** — typed async wrapper over the People API REST
  endpoints used: `people.connections.list` (paginated, syncToken-aware),
  `people.get`/`batchGet`, `people.createContact`/`updateContact`/
  `deleteContact`, `contactGroups.list`/`create`/`update`/`delete`,
  `contactGroups.members.modify`. No caching, no SwiftData knowledge; decodes
  to API DTOs. Unit-testable against fixture JSON via a stubbed URL protocol.
- **SyncEngine** (actor) — the only component that touches both
  `PeopleAPIClient` and SwiftData. Owns full sync, incremental
  (syncToken-based) sync, outbox draining, and etag-conflict detection.
  Serialized as an actor so store writes never race.
- **ContactsStore (SwiftData)** — the models below. UI reads via `@Query`;
  writes only ever go through `ContactsRepository`.
- **ContactsRepository** — the facade UI calls: `save(edit:)`,
  `createContact()`, `delete(_:)`, `refresh()`. Writes optimistically to
  SwiftData and enqueues the corresponding `PendingMutation`; never blocks on
  network.

## Data model (SwiftData)

```swift
@Model final class Contact {
    @Attribute(.unique) var resourceName: String   // "people/c123..." or "local/<uuid>" pre-create
    var etag: String
    var updateTime: Date

    var givenName: String
    var familyName: String
    var middleName: String
    var phoneticGivenName: String
    var phoneticFamilyName: String
    var nickname: String
    var photoURL: String?
    var isStarred: Bool
    var birthday: DateComponents?   // People API allows partial (year-less) dates
    var notes: String

    @Relationship(deleteRule: .cascade) var emails: [LabeledValue]
    @Relationship(deleteRule: .cascade) var phones: [LabeledValue]
    @Relationship(deleteRule: .cascade) var addresses: [PostalAddress]
    @Relationship(deleteRule: .cascade) var organizations: [Organization]
    @Relationship(deleteRule: .cascade) var urls: [LabeledValue]
    @Relationship(deleteRule: .cascade) var relations: [LabeledValue]
    @Relationship(deleteRule: .cascade) var userDefinedFields: [LabeledValue]
    @Relationship var memberships: [ContactGroup]

    var isPendingCreate: Bool
    var isDeletedLocally: Bool
}

@Model final class LabeledValue {   // emails, phones, urls, relations, custom fields
    var label: String
    var value: String
    var isPrimary: Bool
}

@Model final class PostalAddress {
    var label: String
    var street: String, city: String, region: String, postalCode: String, country: String
    var formattedValue: String   // fallback for addresses that don't decompose cleanly
}

@Model final class Organization {
    var name: String, title: String, department: String
    var isCurrent: Bool
}

@Model final class ContactGroup {   // Google "labels"
    @Attribute(.unique) var resourceName: String
    var name: String
    var groupType: String   // USER_CONTACT_GROUP vs SYSTEM (My Contacts, Starred, ...)
    @Relationship(inverse: \Contact.memberships) var members: [Contact]
}

@Model final class PendingMutation {
    var id: UUID
    var kind: MutationKind   // .create, .update(fieldMask), .delete, .groupMembershipChange
    var targetResourceName: String?
    var payload: Data
    var createdAt: Date
    var retryCount: Int
    var lastError: String?
}
```

Notes:
- Custom fields round-trip as free-text label/value pairs (`LabeledValue`), no
  special typing.
- Photos: the People API photo URL is stored; a downsized thumbnail is cached
  to disk (not SwiftData) keyed by `resourceName`. Fetch failures fall back to
  an initials avatar, silently.
- New contacts get a locally-generated placeholder `resourceName`
  (`"local/<uuid>"`) and `isPendingCreate = true` until the outbox create call
  returns the server's real resourceName, which is then rewritten in place.

## Sync engine

**Full sync** — triggered on first launch, after sign-in, or when a syncToken
is rejected as expired (People API returns 410 `EXPIRED_SYNC_TOKEN`):
1. Paginate `people.connections.list` (`pageSize: 200`) for all modeled field
   groups.
2. Upsert each person into SwiftData by `resourceName`.
3. Fetch `contactGroups.list` and upsert groups + memberships.
4. Store the final page's `nextSyncToken`.
5. Delete any locally cached contact not seen in the full sync.

**Incremental sync** — on pull-to-refresh, app foreground, and periodic
background refresh:
1. Call `people.connections.list` with the stored `syncToken` and
   `requestSyncToken: true`.
2. Upsert returned persons; a person flagged `metadata.deleted` is deleted
   locally.
3. Store the new `nextSyncToken`.
4. If an incoming change targets a contact with a queued local mutation, that
   is the etag-conflict path (below) rather than a silent overwrite.

**Outbox draining** — runs after every successful sync and immediately after
each local edit while online:
1. Process `PendingMutation`s oldest first.
2. `.create` → `people.createContact`; on success, replace the local
   placeholder resourceName/etag with the server's.
3. `.update` → `people.updateContact` with an `updatePersonFields` mask and
   the last-known etag.
   - Success → update local etag/updateTime, clear the mutation.
   - 409/etag mismatch → fetch the current server copy, surface the conflict
     UI (below); mutation stays queued until resolved.
4. `.delete` → `people.deleteContact`; a 404 (already gone) counts as success.
5. `.groupMembershipChange` → `contactGroups.members.modify`.
6. Network failure → stays queued, exponential backoff via `retryCount`,
   retried on next foreground/connectivity-restored event.

**Conflict resolution** — an etag mismatch shows a banner on the affected
contact's detail view: "This contact changed elsewhere," with **Keep mine**
(refetch etag, force-repush the local version) or **Use theirs** (discard the
queued mutation, accept the server version). No field-level 3-way merge in v1.

## UI & navigation

- **Sidebar**: "All Contacts," "Starred," then user labels
  (`ContactGroup`s with `groupType == USER_CONTACT_GROUP`) with counts.
  Filters the contact list. On iPhone, reached as a root list rather than a
  persistent column.
- **Contact list**: alphabetically sectioned, section-index on iPad/Mac,
  search across name/email/phone/org via local SwiftData predicate (instant,
  offline-capable), swipe actions for star/delete, pull-to-refresh triggers
  incremental sync, toolbar `+` opens new-contact form.
- **Detail view**: all populated fields grouped by type, Edit button,
  conflict banner when relevant.
- **Edit form**: sheet on iPhone, inline/pushed on iPad/Mac. Multi-value
  sections (emails, phones, etc.) show one row per value with a label picker
  (Home/Work/Mobile/Custom…) and an "Add" row. Save diffs against the
  last-synced snapshot to build the field mask, writes to SwiftData
  immediately, queues the outbox mutation. New-contact form reuses this view
  with no diffing (full create payload).
- **Labels management screen**: create/rename/delete labels, see member
  counts; label assignment also happens inline from a contact's edit form.
- **Sign-in / empty / offline states**: pre-auth sign-in screen; empty state
  for a zero-contact account; a persistent non-blocking offline indicator
  (local browsing/editing still works and queues).

## Error handling

- **Auth**: cancelled sign-in returns to the sign-in screen without error
  noise. A revoked/expired token detected on an API call triggers forced
  sign-out and re-presentation of the sign-in screen with a one-line
  explanation.
- **Network errors**: sync/outbox failures retry silently with backoff; a
  small persistent banner reads "Offline — changes will sync later" only
  while actually offline. No blocking alerts for transient connectivity.
- **Per-mutation API errors** (4xx other than 409): retry up to a small
  ceiling, then surface a "Couldn't sync this change" indicator on that
  specific contact (tap for retry/discard) rather than a global alert.
- **Rate limiting (429)**: honor `Retry-After` if present, else exponential
  backoff.
- **Sync token expiry (410)**: transparent fallback to full sync.
- **Photo fetch failures**: silent fallback to initials avatar.
- **Malformed/unexpected payloads**: log and skip that one contact rather
  than failing the whole sync page.

Principle: local-first UI never blocks or alarms on transient network issues —
edits are safe in SwiftData regardless of connectivity. Errors surface only
when a decision is needed (conflict) or something has definitively and
repeatedly failed.

## Testing strategy

- **PeopleAPIClient**: unit tests against fixture JSON via a stubbed URL
  protocol — request construction (field masks, pagination, syncToken),
  response decoding, error-code mapping. No live network in tests.
- **SyncEngine**: unit tests with a fake `PeopleAPIClient` and an in-memory
  SwiftData container — full sync upserts, incremental deltas, remote
  deletions, etag-mismatch produces a conflict (not silent overwrite), outbox
  drains in order and requeues on failure.
- **ContactsRepository**: focused tests on field-mask diffing (edit → correct
  minimal `updatePersonFields`).
- **Data model**: SwiftData round-trip tests for edge cases (partial
  birthdays, empty optional sections, custom-field label collisions).
- **UI**: SwiftUI previews per screen state (empty, populated, conflict,
  offline); a small number of `XCUITest` smoke tests for the critical path
  (sign in → view → edit → persisted), not broad UI coverage.
- **Auth**: `GoogleAuth` is thin and mostly exercised via manual/integration
  testing rather than unit tests, since GoogleSignIn's SDK is tested upstream.

## Key technology choices (and why)

- **GoogleSignIn-iOS SDK** over hand-rolled PKCE: delegates OAuth correctness
  and token refresh to Google's maintained SDK. Trade-off accepted: extra
  transitive dependencies (AppAuth, GTMAppAuth, GTMSessionFetcher) and a
  second, SDK-owned source of sign-in state, in exchange for not owning OAuth
  edge cases ourselves.
- **SwiftData** over Core Data or a raw SQLite layer (e.g. GRDB): integrates
  natively with SwiftUI (`@Query`/`@Model`) and is mature enough at this
  deployment target (iOS 26) that Core Data's extra maturity isn't needed;
  revisit only if SwiftData's relationship handling proves troublesome for a
  contact's several one-to-many child collections.
- **Local cache + incremental sync** over live-API-only: local SwiftData
  store makes browsing/search instant and offline-capable, and lets edits
  queue rather than block on network — accepted cost is the outbox/conflict
  machinery above.
- **NavigationSplitView single view tree** over per-platform layouts: one
  codebase adapts across iPhone/iPad/Mac via the view's own collapsing
  behavior, avoiding a maintained fork per platform.
