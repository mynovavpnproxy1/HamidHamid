# Psiphon engine integration plan

Status: investigation complete; implementation is gated on Android traffic-loop and build validation.

## Non-destructive constraints

- Keep the existing Xray engine and its VLESS, VMess, Trojan, and Shadowsocks connection path.
- Keep the existing server directory, profile delivery, device registration, admin panel, settings, and failover behavior.
- Add Psiphon as an additional engine. Do not replace Xray or change the backend profile contract as part of this integration.
- Do not report a successful connection until the selected engine reports connected and real traffic has passed through the tunnel.

## Repository baseline inspected

- Flutter client root: `app/`.
- Current engine adapter: `app/lib/services/vpn_service.dart`.
- Current dependency: `flutter_v2ray_client`, pinned to `138faaddc216ef2b2960a0acd265151f065234e3`.
- Android platform files are not committed in this repository. CI creates them with `flutter create --platforms=android` when absent.
- Current Xray adapter owns initialization, Android VPN permission, start/stop, status events, and a two-hour session limit. Preserve those semantics for the Xray option.
- Current CI runs Dart formatting, analysis, Flutter tests, and an Android debug APK build.

## Verified Psiphon library interfaces

The official Android library documentation describes an embeddable AAR dependency:
`ca.psiphon:psiphontunnel:x.y.z`, hosted from the Psiphon Android-library Maven repository. The latest release observed during this investigation is `v2.0.43` (2026-11-17).

The official `PsiphonTunnel` source exposes:
- `PsiphonTunnel.newPsiphonTunnel(HostService)`
- `startTunneling(String embeddedServerEntries)`
- `stop()`
- `setVpnMode(boolean)`
- `getLocalSocksProxyPort()`
- `HostService.onListeningSocksProxyPort(int)`
- `HostService.onConnected()`
- `HostService.onBytesTransferred(long sent, long received)`

The library initializes with VPN mode false by default. Its listener reports the dynamically selected local SOCKS port. The official TunneledWebView sample uses that local proxy port to proxy application traffic. This establishes that Psiphon can expose a local proxy; it does not yet prove that the Nova Xray TUN path can safely consume it.

## Candidate integration architecture

Preferred candidate: keep Xray as the only Android VPN/TUN owner and start Psiphon in non-VPN/local-SOCKS mode. Add a dedicated Psiphon Android bridge and a Dart engine adapter. When Psiphon reports both a listening SOCKS port and its connected callback, construct an Xray configuration that sends user traffic through a loopback SOCKS outbound. The existing direct-to-server Xray path remains unchanged and available as the default engine.

This architecture is only accepted after proving all of the following on Android:
1. Psiphon local SOCKS listener is reachable from the Xray process.
2. Xray can route the complete intended traffic set through the SOCKS outbound without bypassing the proxy.
3. Psiphon's own upstream sockets do not re-enter the Xray TUN and create a routing loop.
4. DNS and IPv4/IPv6 traffic do not leak directly when Psiphon is starting, connected, restarting, or failing.
5. Stopping Psiphon causes the Xray path to fail closed rather than silently falling back to direct internet access.

If any of these fail, do not ship the proxy-chain mode. Evaluate a mutually exclusive Psiphon-owned VPN service as a separate fallback, with an explicit engine handoff that stops Xray before Psiphon establishes its VPN interface. Never run two independent VPN services concurrently.

## Implementation sequence

1. Add the Android Psiphon AAR dependency and a native bridge without changing the existing Xray adapter.
2. Add a Dart Psiphon service with explicit lifecycle states: idle, starting, proxy-ready, connected, stopping, failed.
3. Add an engine selection abstraction while preserving Xray as the default and retaining existing server/profile selection behavior.
4. Implement the Xray-to-local-SOCKS configuration as an isolated path, guarded until Android integration tests pass.
5. Add tests for lifecycle, timeout, cancellation, engine switching, and recovery.
6. Build a debug APK and test on a physical Android device: IP exit, DNS, IPv4/IPv6, upload/download, forced Psiphon failure, reconnect, and at least 30 minutes of stability.

## Licensing and release gate

The inspected Psiphon tunnel-core source declares GNU GPL version 3 or later. The Android library README documents distributing the AAR dependency. Before publishing an APK that bundles this library, review the applicable GPL-3.0 obligations, including notices and corresponding-source availability for the distributed work. Do not assume that using a separate process or a binary AAR removes those obligations. Include the applicable license and notices in the app if the integration proceeds.

## Current completion status

No Psiphon code has been added yet. No APK build, device connection, traffic-routing, leak, or stability test is claimed. This document records the verified interfaces and the engineering gates for the next implementation step.
