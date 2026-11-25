# Android engine integration status

The client now depends on `flutter_v2ray_client` 3.5.0 and has an adapter that initializes the engine, requests Android VPN permission, starts/stops a tunnel, and listens to engine status callbacks. The UI only enters the Connected state after receiving the plugin's `CONNECTED` event.

The backend now supports device registration, administrator approval, and short-lived client tokens. On first connection, the app registers its device; an administrator must approve it in `/admin` before profile delivery. Missing or invalid tokens return 401 and unapproved devices return 403. The app then requests the profile just in time over HTTPS. No actual server/profile has been provided, and no device build or live tunnel test has been performed.

Before public launch, deploy the backend behind HTTPS, configure the app's `API_BASE_URL`, add rate limiting and abuse controls at the edge, and validate revocation and token expiry. Then test every profile against the selected engine with owner-provided infrastructure and Android devices. The plugin documents VLESS, VMess, Trojan, Shadowsocks, and Hysteria URL parsing; a protocol label in the admin panel alone does not guarantee profile compatibility.


## Supported protocol boundary

The pinned Android dependency is `flutter_v2ray_client` 3.5.0, which embeds Xray. The current server API therefore accepts only VLESS, VMess, Trojan, and Shadowsocks profile schemes. Hysteria/Hysteria2, TUIC, and WireGuard are not enabled in the current client path. A Sing-box migration is a separate decision: the inspected `flutter_singbox_client` Android plugin is GPL-3.0-only, so its copyleft obligations must be assessed before using it in an ad-supported distributable app. The current Xray plugin is MIT-licensed. Do not advertise or accept a protocol just because the backend can store its name.


## Native socket protection hardening — 2026-11-25

The owned `flutter_v2ray_client` fork was patched and pinned to commit `d50467c1510edf740cae80d4556e3c4512cd4354`. Its native socket protector now fails closed when the service listener is absent, the descriptor is invalid, the callback throws, or Android `protect(fd)` returns false. JUnit test source was added for these cases. The app dependency pin is updated in `app/pubspec.yaml`.

This patch does **not** prove successful tunnel traffic and does not fix the candidate's immediate CONNECTED state transition, bypass-subnet routing, or IPv6 sinkhole policy. The native AAR's exact source/build provenance and redistribution notices also remain unverified. Build and test results after the patch are pending.


## Native status and data-plane distinction

The plugin's `CONNECTED` callback is currently emitted after the native `startLoop()` call returns and the manager sets its internal state. It confirms native core startup, not end-to-end TUN traffic. The exposed server-delay method calls the core's outbound delay measurement; it is useful as a server-reachability signal but is not proof that arbitrary Android app packets traverse the TUN. A dedicated data-plane probe and physical-device traffic tests are still required.