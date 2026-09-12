# BiliPad repository instructions

## Scope

Implement only the active milestone described in `README.md`. The current milestone is V0.5 native search, video detail, danmaku, comments, interactions, and segmented playback.

Do not add or implement:

- a backend or separate account system;
- analytics, tracking, advertising, or telemetry;
- credential export or credential logging;
- video downloading, stream extraction, DRM handling, or unauthorized entitlement changes;
- App Store distribution work unless the milestone is explicitly changed.

Content browsing and playback must use native UI. A mobile web view may only be used inside the login flow. Keep unofficial endpoint use centralized and replaceable. Never claim or imply that BiliPad changes a user's content rights.

## Engineering rules

- Treat Bilibili response formats as unstable. Decode defensively and fail visibly.
- Store the minimum session cookies in Keychain and never print them.
- Do not log cookies, tokens, credentials, page HTML, or personal viewing data.
- Keep controller navigation algorithms testable outside iOS when practical.
- Windows checks do not replace macOS compilation or iPhone/controller acceptance tests.
- Never commit signing certificates, Apple account details, provisioning profiles, or SideStore credentials.
