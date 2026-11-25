# NOVA VPN build and engine progress log

Last updated: 2026-11-24

## Scope

Active implementation repository: `mynovavpnproxy1/HamidHamid`, branch `main`.
This log records verified repository changes and test evidence. A GitHub commit is not proof of a successful APK or VPN traffic.

## Five-stage execution plan

| Stage | Scope | Status |
|---|---|---|
| 1 | Audit engine integration, Android project configuration, and build pipeline | Complete (repository-level) |
| 2 | Fix source/dependency/Android integration issues found by audit | Complete for the current CI baseline; analyzer and Flutter tests pass |
| 3 | Produce a debug APK through CI and retain the artifact | Complete; CI artifact downloaded and APK archive integrity verified |
| 4 | Test a valid owner-supplied profile on a physical Android device (TCP, DNS, IPv4/IPv6, UDP, upload/download) | Blocked until APK and authorized working profile/device test |
| 5 | Review stability, security, performance evidence, then determine release readiness | Not started |

## Verified findings on 2026-11-24

- The app pins `flutter_v2ray_client` 3.5.0 to Git commit `138faaddc216ef2b2960a0acd265151f065234e3`.
- The selected plugin uses Xray native TUN on Android. This is the existing engine integration; this work is not a claim that a new independent engine has been implemented.
- The repository does not commit an Android Gradle project. The CI workflow generates Android platform files using `flutter create` before dependency resolution/build.
- Latest prior CI run #88 (run ID `45160753236`, commit `e295639731eeffda37ca57224a1de4e1dc648157`) passed backend tests but failed Flutter analysis. Flutter tests and APK build were skipped.
- The prior analyzer errors were:
  - `const_with_non_const` at `app/lib/screens/splash_screen.dart:76` because `Image.asset` was nested in a const Column.
  - `undefined_identifier` for `Image` in `app/test/widget_test.dart`, caused by the missing direct Flutter SDK dependency in `app/pubspec.yaml`.
- Applied changes:
  - Commit `41c30924484b6e36ce6b1a9df7d43c61b4044ff6`: added `flutter: sdk: flutter` to app dependencies.
  - Commit `0f1899cf8e1d252f70246c3799c6256591266ea9`: removed the invalid const from the splash Column.
- Both edited files were fetched again from `main` and their new blob SHAs verified:
  - `app/pubspec.yaml`: `3e2d03098eec1e75259b0bbbc73aa19438159bf3`
  - `app/lib/screens/splash_screen.dart`: `ef00896fbda5a1a3e51f49e1e1c397cea73b611e`
- CI run #90 (run ID `45413283642`, commit `0f1899cf8e1d252f70246c3799c6256591266ea9`) completed: backend tests passed; Flutter formatting passed; Flutter analysis failed on one remaining error: `Image` was referenced in `app/test/widget_test.dart` without importing `package:flutter/material.dart`. Flutter tests and APK build were skipped.
- Fixed the remaining test import in commit `e8159305b88be8d24c41e8bf159f861c8304ca80`; resulting blob SHA for `app/test/widget_test.dart` is `b4a05b469e46d6164d441e4060fac317f0bb8442`.
- CI run #91 (run ID `45416056741`, commit `e8159305b88be8d24c41e8bf159f861c8304ca80`) completed with `success`. Both jobs passed. The Flutter job passed dependency resolution, Dart formatting, Flutter analysis, Flutter tests, Android debug APK build, and artifact upload; the backend tests job also passed.
- Artifact `nova-vpn-debug-apk` (artifact ID `14931878171`) was downloaded. ZIP size: `125,958,438` bytes; GitHub artifact digest: `sha256:b2fcfd1b55faec98734abed67e85b2dbf8124814e8a06ebcaef96f1ad6b64f52`. ZIP integrity test passed and contains `app-debug.apk` (276,391,896 bytes). Extracted APK SHA-256: `57bb1c1e63a46dc25e52bf0a3de7f7097f060a45b9a86b90eab01e5ee1273353`.
- This is a debug APK, not a release build. Its large size is consistent with debug Flutter assets and multiple ABI libraries; size optimization is a separate later task.

## JumpJump visual reference audit — 2026-11-24

- Reviewed both Library recordings end-to-end by extracting and inspecting frames at one-second intervals: `screen-۲۰۲۶۱۱۱۵-۱۱۰۰۱۲.mp4` (720x1612, 111.756944s; 112 sampled frames) and `screen-۲۰۲۶۱۱۱۱-۱۶۲۰۰۹.mp4` (720x1612, 53.540800s; 54 sampled frames). Also inspected the five individual screen captures `chart-1(1).png`–`chart-5(1).png`.
- Reviewed the timestamped extracted screenshots and individual screen captures, including the main/disconnected screen, connecting globe/progress state, country/location picker, expanded city/server rows, connected state with IP/rates/timer, settings, account prompt, and ad interruptions.
- Excluded NOVA logo/mockup/splash assets `1000143671.png`, `1000143673.png`, `1000279624*.png`, and `1000313396.png` from JumpJump reference evidence. The Library Favorites collection is not to be mixed with JumpJump screenshots. The in-app JumpJump location selector's own `مورد علاقه` tab is a real visible feature and must be treated separately.
- Reference observations and a detailed screen-to-code mapping are saved in the Library file `/NOVA_JUMPJUMP_REFERENCE_AUDIT.md`.
- Current NOVA UI mismatch confirmed in `app/lib/screens/home_screen.dart`, `app/lib/screens/server_list_screen.dart`, and `app/lib/screens/settings_screen.dart`: home hierarchy/control shape differs; location picker lacks the three tabs and inline expanded server rows/favorites/recent; settings are still minimal.
- JumpJump decompiled source confirms Flutter: its `MainActivity.smali` extends `FlutterActivity`; `lib/arm64-v8a/libapp.so` contains compiled AOT app code. Original editable Dart widget source is not present in the decompiled repository, so NOVA's Dart UI must be reconstructed from the recording/screenshots, not copied from smali.
- JumpJump Flutter assets include its own logo/status/server/VIP/empty-state artwork and Lottie loading/network assets. These are reference evidence only; do not copy JumpJump branding or third-party ad creatives into NOVA.
- No NOVA UI code was changed as part of this reference audit. Next: map the observed UI into NOVA widgets while preserving current VPN service, API, storage, and failover logic; verify actual functionality before presenting any control as working.

## Explicitly not verified

- A successful CI debug APK artifact has been downloaded and verified for archive integrity. It has not yet been installed or tested on a physical device.
- No live VPN tunnel has been tested with an owner-authorized working profile.
- A native `CONNECTED` callback is not proof of internet traffic.
- No speed, latency, packet-loss, DNS, IPv6, or battery-performance claim is made.
- No production backend URL/profile has been supplied and verified as live in this log.
- Exact contents/empty states of JumpJump's Favorites and Recent tabs and exact ad timing/trigger conditions have not yet been established.

## Next actions

1. Begin the JumpJump-informed UI implementation on a separate feature branch, starting with the home screen hierarchy and location selector.
2. Preserve `VpnService`, `ApiService`, storage, connection failover, and current Xray TUN integration unless a separately verified defect requires a change.
3. Add Favorites/Recent persistence only with explicit, testable behavior; do not invent the unseen contents of the reference app's Favorites/Recent tabs.
4. Run CI after each coherent UI milestone and verify the artifact before claiming a build.
5. Install the debug APK on an Android device and test with an authorized working profile; verify TCP, DNS, IPv4/IPv6, UDP, upload/download, and disconnect behavior.
6. Record measured results and only then assess release readiness.


## Native protector hardening — 2026-11-25

- Static review of the exact pinned plugin revision found a fail-open callback: `V2rayCoreManager.setUpListener()` returned `true` when the Android service/protector listener was missing.
- Patched the owned fork `mynovavpnproxy1/flutter_v2ray_client`:
  - Commit `39df80d6fb14e25110e580aaebf3654d4ca0b07e`: added `SocketProtection.isProtected()`, rejecting a missing listener and invalid descriptor range, and returning false on callback exceptions.
  - Commit `a7a2b0cee91b8d94ed2151083d3dc25564b2b1b5`: added JUnit tests for missing listener, protect success/failure, callback exception, and invalid descriptors.
  - Commit `d50467c1510edf740cae80d4556e3c4512cd4354`: wired the native `Libv2ray.useProtector` callback to the fail-closed helper. The final manager source was fetched again and verified.
- Updated `app/pubspec.yaml` to pin the fork to `d50467c1510edf740cae80d4556e3c4512cd4354`; the file was fetched again and the pin verified. App dependency update commit: `061e1b3af2041daf59371ade522b2a77a2c3a22e`.
- **Not yet verified:** Android/Gradle compilation, JUnit execution, Flutter analysis/tests, or APK build after this change. Do not treat source-level tests as executed tests.
- Other candidate issues remain open: core reports CONNECTED immediately after `startLoop` without an end-to-end TUN traffic probe; bypass-subnet API naming conflicts with include-route behavior and needs an explicit contract; this is not a confirmed routing defect; IPv6 is sinkholed rather than tunneled; native AAR provenance and redistribution notices are unresolved. See the engine research audit in the Hamid documentation repository.


### Native status semantics clarification — 2026-11-25
Updated `app/lib/services/vpn_service.dart` comments to distinguish the native core's CONNECTED callback from proof of end-to-end TUN traffic. The delay method is documented as the native core's outbound delay check, not a data-plane test of ordinary app traffic through the TUN. This is a documentation correction; it does not change connection runtime behavior.