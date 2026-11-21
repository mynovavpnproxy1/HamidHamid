# NOVA VPN Android continuation roadmap

## Current repository state

- Active development repository: `mynovavpnproxy1/HamidHamid`, default branch `main`.
- Android client: Flutter UI, Persian/English language preference, metadata-only server list, saved server selection, secure device token storage, and failover across enabled servers.
- VPN engine: Android `flutter_v2ray_client` 3.5.0 pinned to commit `138faaddc216ef2b2960a0acd265151f065234e3`. The plugin embeds Xray and uses Android `VpnService` with a TUN interface.
- Connection state: the UI waits for the engine's native `CONNECTED` event. The UI now displays engine-reported upload/download rates and measures HTTPS latency through the active tunnel.
- Backend: FastAPI admin API and Persian admin panel. Device registration, approval/revocation, short-lived client tokens, and protected on-demand profile delivery are implemented. The server catalogue starts empty.
- Database: SQLite remains the local default. Optional PostgreSQL support is implemented for hosted deployment and has a PostgreSQL CI integration test.
- Hosting: `render.yaml` provides a free Render Web Service blueprint. It requires an external PostgreSQL URL and administrator credentials. Render Free sleeps after 15 minutes idle, can take about one minute to wake, and has an ephemeral local filesystem; PostgreSQL must be used for persistent data. Free hosting is a zero-cost early deployment option, not an uptime or production SLA.
- CI: `.github/workflows/nova_ci.yml` runs backend tests (including PostgreSQL integration), Flutter analysis, widget/service tests, and only builds the Android APK after an HTTPS `API_BASE_URL` is configured.

## Verified versus not yet verified

- Backend SQLite tests passed in CI before PostgreSQL support was added.
- Flutter analysis and Flutter tests passed in CI before the latest live-throughput UI changes.
- PostgreSQL support and integration tests have been added; the latest CI run must complete before calling them verified.
- No production backend has been deployed and no real HTTPS API URL exists yet.
- No APK artifact has been produced by a successful current CI run.
- No owner-supplied server profile has passed a physical-device end-to-end test for DNS, IPv4/IPv6 routing, upload/download throughput, latency, or stability.
- A native `CONNECTED` event alone is not proof of working internet traffic or good speed.

## Next implementation sequence

1. Complete CI for the current Android throughput/latency UI and PostgreSQL adapter.
2. Deploy the FastAPI backend with persistent PostgreSQL and HTTPS using a no-cost hosting setup, while documenting free-tier sleep and quota limitations.
3. Set the resulting HTTPS API URL as the GitHub repository variable `API_BASE_URL`, then build and retain the APK artifact.
4. Add owner-provided, legally usable VPN profiles only through the protected admin panel; never commit credentials or public sample profiles.
5. Test the actual tunnel on a physical Android device. Record measured ping, download/upload throughput, DNS behavior, IPv4/IPv6 routing, and stability for each profile.
6. Use those measurements to decide whether Xray is adequate or whether a different Android core is needed. Do not replace the engine based on assumptions or a protocol label.
7. Complete security/privacy review before advertising or public release.

## Protocol and engine constraints

The pinned plugin documents share-link parsing for VLESS, VMess, Trojan, Shadowsocks, and Hysteria. This does not mean every server profile or transport variant is compatible. WireGuard, WARP, MASQUE, and other protocols are not currently exposed as complete, verified end-to-end options in the app. Do not advertise unsupported protocols as working.

## Cost and release policy

- Do not purchase a domain, paid hosting, or paid engine dependencies during the current build phase.
- No public proxy credentials or user-provided profiles may be copied into GitHub or bundled in the APK.
- No APK is release-ready until it is built with the deployed HTTPS backend and the real tunnel passes traffic tests.
- iOS work is explicitly deferred; continue Android only.
