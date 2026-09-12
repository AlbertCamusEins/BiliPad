# BiliPad repository instructions

## Scope

Implement only the active milestone described in `README.md`. The current milestone is V0.1.1.

Do not add or implement:

- a backend or separate account system;
- analytics, tracking, advertising, or telemetry;
- private or reverse-engineered Bilibili APIs;
- cookie export, credential capture, or credential logging;
- video downloading, stream extraction, DRM handling, or unauthorized entitlement changes;
- App Store distribution work unless the milestone is explicitly changed.

All content, login, session, membership decisions, and playback must remain in Bilibili's normal web environment. Never claim or imply that BiliPad changes a user's content rights.

## Engineering rules

- Keep selectors in the injected web layer centralized and prefer URL/semantic attributes over CSS classes.
- Treat Bilibili DOM details as unstable. Fail visibly and preserve touch operation.
- Do not log cookies, tokens, credentials, page HTML, or personal viewing data.
- Keep controller navigation algorithms testable outside iOS when practical.
- Windows checks do not replace macOS compilation or iPhone/controller acceptance tests.
- Never commit signing certificates, Apple account details, provisioning profiles, or SideStore credentials.
