# Store Privacy Disclosures

Verified against the codebase on 2026-08-26. Re-check whenever dependencies or network features change.

## Apple App Privacy

- Data collection: **No, we do not collect data from this app.**
- Tracking: **No.**
- Rationale: Leeef has no developer-operated account, analytics, advertising, telemetry, or content backend. On-device data is not “collected” under Apple's definition. Optional S3/WebDAV, AI/TTS, OPDS, external search, and sharing connections are initiated by the user and go directly to services selected and configured by the user; the publisher cannot access them.
- Privacy policy URL: https://gist.github.com/tianma-if/98290c0fdb7f9a689724e86a2185a37f

If a future release adds a developer-controlled backend or third-party SDK that retains app data, update this answer before submission.

## Google Play Data Safety

- Does the app collect or share required user data types? **No.**
- Is all transmitted user data encrypted in transit? **Yes for supported production configurations; users should configure HTTPS/TLS endpoints.**
- Account creation: **No account creation.**
- Data deletion request URL: **Not applicable to developer-held data.** The privacy policy explains local deletion and deletion from user-selected third-party services.
- Ads: **No.**

The app can transmit books, notes, reading progress, prompts, selected text, search terms, and credentials directly to services chosen by the user. The publisher does not receive or control that data. This behavior must remain clearly disclosed in-app and in the privacy policy.

## Permissions / Capabilities

- Network: book downloads, OPDS, optional sync, optional AI/TTS, update checks.
- Background processing and notifications: optional sync and completion notices.
- Audio playback: TTS narration and media controls.
- No location, contacts, camera, microphone, health, advertising ID, or tracking permission.
