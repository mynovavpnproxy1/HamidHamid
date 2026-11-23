import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import '../models/vpn_server.dart';
import '../services/api_service.dart';
import '../services/connection_failover.dart';
import '../services/storage_service.dart';
import '../services/vpn_service.dart';
import 'server_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _ConnectionUi { disconnected, connecting, connected, disconnecting, error }

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();
  final VpnService _vpn = VpnService();

  StreamSubscription<V2RayStatus>? _statusSubscription;
  _ConnectionUi _connection = _ConnectionUi.disconnected;
  VpnServer? _activeServer;
  VpnServer? _preferredServer;
  String _language = 'fa';
  String _duration = '00:00:00';
  int _uploadSpeed = 0;
  int _downloadSpeed = 0;
  int _uploadedBytes = 0;
  int _downloadedBytes = 0;
  int? _pingMs;
  bool _pingAttempted = false;
  String? _message;
  bool _busy = false;
  bool _failoverRunning = false;
  int _currentAttempt = 0;
  int _attemptCount = 0;

  bool get _fa => _language == 'fa';
  bool get _connected => _connection == _ConnectionUi.connected;

  @override
  void initState() {
    super.initState();
    _storage.readLanguage().then((language) {
      if (mounted) setState(() => _language = language);
    });
    _statusSubscription = _vpn.statusChanges.listen(_onEngineStatus);
    _onEngineStatus(_vpn.currentStatus);
  }

  void _onEngineStatus(V2RayStatus status) {
    if (!mounted) return;
    setState(() {
      _uploadSpeed = status.uploadSpeed;
      _downloadSpeed = status.downloadSpeed;
      _uploadedBytes = status.upload;
      _downloadedBytes = status.download;
      switch (status.state.toUpperCase()) {
        case 'CONNECTED':
          _connection = _ConnectionUi.connected;
          _duration = status.duration;
          _message = null;
          break;
        case 'CONNECTING':
          _connection = _ConnectionUi.connecting;
          break;
        case 'DISCONNECTING':
          _connection = _ConnectionUi.disconnecting;
          break;
        case 'DISCONNECTED':
          if (!_failoverRunning || _connection == _ConnectionUi.disconnecting) {
            _connection = _ConnectionUi.disconnected;
            _duration = '00:00:00';
            _uploadSpeed = 0;
            _downloadSpeed = 0;
            _uploadedBytes = 0;
            _downloadedBytes = 0;
            _pingMs = null;
            _pingAttempted = false;
            _activeServer = null;
          }
          break;
        case 'ERROR':
          if (!_failoverRunning) {
            _connection = _ConnectionUi.error;
            _message = _fa
                ? 'موتور VPN اتصال را برقرار نکرد.'
                : 'VPN engine failed to connect.';
          }
          break;
      }
    });
    if (status.state.toUpperCase() == 'CONNECTED' && !_pingAttempted) {
      _pingAttempted = true;
      unawaited(_refreshConnectedPing());
    }
  }

  Future<void> _refreshConnectedPing() async {
    try {
      final delay = await _vpn.getConnectedServerDelay();
      if (mounted && _connected) {
        setState(() => _pingMs = delay >= 0 ? delay : null);
      }
    } catch (_) {
      if (mounted && _connected) setState(() => _pingMs = null);
    }
  }

  String _formatRate(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _api.close();
    super.dispose();
  }

  Future<void> _chooseServer() async {
    if (_busy || _connected) return;
    final selected = await Navigator.of(context).push<VpnServer>(
      MaterialPageRoute(
        builder: (_) => ServerListScreen(language: _language),
      ),
    );
    if (!mounted) return;
    if (selected == null) {
      await _storage.writeServerId('');
      setState(() {
        _preferredServer = null;
        _message = null;
      });
      return;
    }
    await _storage.writeServerId(selected.id);
    if (mounted) {
      setState(() {
        _preferredServer = selected;
        _message = null;
      });
    }
  }

  Future<void> _toggleConnection() async {
    if (_busy) return;
    if (_connected) {
      await _disconnect();
    } else {
      await _connectWithFallback();
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _busy = true;
      _connection = _ConnectionUi.disconnecting;
      _message = null;
    });
    try {
      await _vpn.disconnect();
      if (mounted) {
        setState(() {
          _connection = _ConnectionUi.disconnected;
          _activeServer = null;
          _duration = '00:00:00';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connection = _ConnectionUi.error;
          _message = _fa ? 'قطع اتصال انجام نشد.' : 'Could not disconnect.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectWithFallback() async {
    setState(() {
      _busy = true;
      _failoverRunning = true;
      _connection = _ConnectionUi.connecting;
      _message = _fa ? 'در حال دریافت فهرست سرورها…' : 'Loading available servers…';
      _currentAttempt = 0;
      _attemptCount = 0;
    });

    try {
      // Fresh metadata is fetched each time so owner changes need no APK update.
      final servers = await _api.fetchServers();
      if (!mounted) return;
      if (servers.isEmpty) {
        setState(() {
          _connection = _ConnectionUi.error;
          _message = _fa
              ? 'در حال حاضر سرور فعالی وجود ندارد.'
              : 'No active servers are currently available.';
        });
        return;
      }

      final savedId = await _storage.readServerId();
      if (!mounted) return;
      final preferredId = _preferredServer?.id ?? savedId;
      final savedServer = servers.where((server) => server.id == preferredId);
      final selectedServer = _preferredServer ??
          (savedServer.isEmpty ? null : savedServer.first);
      final selectedCountryCode = selectedServer?.countryCode;
      bool sameSelectedCity(VpnServer server) {
        if (selectedServer == null) return true;
        final selectedEn = (selectedServer.locationNameEn ?? '').trim().toLowerCase();
        final candidateEn = (server.locationNameEn ?? '').trim().toLowerCase();
        if (selectedEn.isNotEmpty && candidateEn.isNotEmpty) {
          return selectedEn == candidateEn;
        }
        final selectedFa = (selectedServer.locationNameFa ?? '').trim().toLowerCase();
        final candidateFa = (server.locationNameFa ?? '').trim().toLowerCase();
        if (selectedFa.isNotEmpty && candidateFa.isNotEmpty) {
          return selectedFa == candidateFa;
        }
        return (selectedEn.isNotEmpty && selectedEn == candidateEn) ||
            (selectedFa.isNotEmpty && selectedFa == candidateFa);
      }

      final countryServers = selectedCountryCode == null
          ? servers
          : servers.where((server) =>
              server.locationVerified &&
              server.countryCode == selectedCountryCode &&
              sameSelectedCity(server)).toList();
      if (countryServers.isEmpty) {
        setState(() {
          _connection = _ConnectionUi.error;
          _message = _fa
              ? 'برای این کشور در حال حاضر سرور فعالی وجود ندارد.'
              : 'No active servers are available for this location.';
        });
        return;
      }
      final candidates = <VpnServer>[
        ...countryServers.where((server) => server.id == preferredId),
        ...countryServers.where((server) => server.id != preferredId),
      ];
      _attemptCount = candidates.length;

      final connectedServer = await connectWithFallback<VpnServer>(
        candidates: candidates,
        isFatal: (error) =>
            error is ApiException || error is VpnPermissionException,
        onAttempt: (server, index) {
          if (!mounted) return;
          setState(() {
            _currentAttempt = index + 1;
            _activeServer = server;
            _connection = _ConnectionUi.connecting;
            _message = index == 0
                ? (_fa ? 'در حال اتصال…' : 'Connecting…')
                : (_fa ? 'تلاش با سرور بعدی…' : 'Trying the next server…');
          });
        },
        attempt: (server) async {
          // Profile remains transient and is requested only for this attempt.
          final profile = await _api.fetchServerConfig(server.id);
          await _vpn.connect(profile: profile, remark: server.name);
        },
      );

      await _storage.writeServerId(connectedServer.id);
      if (mounted) {
        setState(() {
          _activeServer = connectedServer;
          _preferredServer = connectedServer;
          _connection = _ConnectionUi.connected;
          _message = null;
        });
      }
    } on VpnPermissionException {
      if (mounted) {
        setState(() {
          _connection = _ConnectionUi.disconnected;
          _message = _fa ? 'مجوز VPN داده نشد.' : 'VPN permission was denied.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _connection = _ConnectionUi.error;
          _message = error.statusCode == 403
              ? (_fa
                  ? 'این دستگاه ثبت شده و منتظر تأیید مدیر است. پس از تأیید دوباره اتصال را بزنید.'
                  : 'This device is registered and awaiting administrator approval. Try connecting again after approval.')
              : (_fa
                  ? 'دریافت امن پروفایل از سمت سرویس در دسترس نیست.'
                  : 'Secure profile delivery is unavailable from the service.');
        });
      }
    } on AllCandidatesFailedException catch (error) {
      if (mounted) {
        setState(() {
          _connection = _ConnectionUi.error;
          _activeServer = null;
          _message = _fa
              ? 'اتصال به هیچ‌یک از ${error.attemptedCount} سرور برقرار نشد.'
              : 'Could not connect to any of the ${error.attemptedCount} servers.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connection = _ConnectionUi.error;
          _activeServer = null;
          _message = _fa ? 'اتصال VPN برقرار نشد.' : 'VPN connection failed.';
        });
      }
    } finally {
      _failoverRunning = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _stateLabel => switch (_connection) {
        _ConnectionUi.disconnected => _fa ? 'قطع' : 'Disconnected',
        _ConnectionUi.connecting => _fa ? 'در حال اتصال' : 'Connecting',
        _ConnectionUi.connected => _fa ? 'متصل' : 'Connected',
        _ConnectionUi.disconnecting => _fa ? 'در حال قطع' : 'Disconnecting',
        _ConnectionUi.error => _fa ? 'خطا' : 'Error',
      };

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: const Color(0xFF070D1A),
          body: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: -120,
                  right: -90,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF235BFF).withValues(alpha: .10),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -150,
                  left: -110,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF8A35FF).withValues(alpha: .08),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111D36),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: const Color(0xFF243B68)),
                                ),
                                child: Image.asset(
                                  'assets/brand/nova_logo_dark.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.shield_outlined,
                                    color: Color(0xFF69A0FF),
                                    size: 30,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('NOVA VPN', style: TextStyle(
                                      color: Colors.white, fontSize: 19,
                                      fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                                    SizedBox(height: 2),
                                    Text('PRIVATE • FAST • SECURE', style: TextStyle(
                                      color: Color(0xFF7184A9), fontSize: 9,
                                      letterSpacing: 1.45, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: _fa ? 'تنظیمات' : 'Settings',
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                                  );
                                  final language = await _storage.readLanguage();
                                  if (mounted) setState(() => _language = language);
                                },
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF111D32),
                                  foregroundColor: const Color(0xFFB8C7E4),
                                  fixedSize: const Size(44, 44),
                                ),
                                icon: const Icon(Icons.tune_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101A2D),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: const Color(0xFF202F4C)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _connected ? const Color(0xFF21D6B2) :
                                      (_connection == _ConnectionUi.connecting
                                        ? const Color(0xFFFFC857) : const Color(0xFF71809D)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_connected ? const Color(0xFF21D6B2) :
                                          const Color(0xFF71809D)).withValues(alpha: .45),
                                        blurRadius: 9,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Text(_stateLabel, style: const TextStyle(
                                  color: Color(0xFFDCE7FA), fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 26),
                          Center(
                            child: SizedBox(
                              width: 228,
                              height: 228,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 218, height: 218,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF29416E).withValues(alpha: .65),
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 190, height: 190,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          (_connected ? const Color(0xFF14CBA8) : const Color(0xFF2868FF))
                                            .withValues(alpha: .22),
                                          const Color(0xFF111D36).withValues(alpha: .04),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: (_connected ? const Color(0xFF21D6B2) : const Color(0xFF3477FF))
                                          .withValues(alpha: .45),
                                        width: 1.4,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 150, height: 150,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: _connected
                                          ? const [Color(0xFF13BFA2), Color(0xFF087D9D)]
                                          : const [Color(0xFF3978FF), Color(0xFF5436D8)],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_connected ? const Color(0xFF13BFA2) : const Color(0xFF3978FF))
                                            .withValues(alpha: .32),
                                          blurRadius: 34, spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _busy ? null : _toggleConnection,
                                        child: Center(
                                          child: _busy
                                            ? const SizedBox(
                                                width: 42, height: 42,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 3, color: Colors.white))
                                            : Icon(
                                                _connected ? Icons.pause_rounded : Icons.power_settings_new_rounded,
                                                color: Colors.white, size: 64,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 17),
                          Center(
                            child: Text(
                              _connected
                                ? (_fa ? 'اتصال امن برقرار است' : 'Secure connection is active')
                                : (_fa ? 'برای اتصال، دکمه را لمس کنید' : 'Tap the button to connect'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFD9E4F8), fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_connected) ...[
                            const SizedBox(height: 7),
                            Center(child: Text(_duration, style: const TextStyle(
                              color: Color(0xFF7F91B3), fontSize: 13,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ))),
                          ],
                          if (_connection == _ConnectionUi.connecting && _attemptCount > 0) ...[
                            const SizedBox(height: 8),
                            Center(child: Text(
                              _fa ? 'تلاش $_currentAttempt از $_attemptCount' : 'Attempt $_currentAttempt of $_attemptCount',
                              style: const TextStyle(color: Color(0xFFFFC857), fontSize: 12))),
                          ],
                          const SizedBox(height: 27),
                          InkWell(
                            onTap: _busy || _connected ? null : _chooseServer,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF142544), Color(0xFF101A30)],
                                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF2A426B)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48, height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E6BFF).withValues(alpha: .15),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: const Icon(Icons.public_rounded,
                                      color: Color(0xFF69A0FF), size: 25),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_fa ? 'موقعیت اتصال' : 'Connection location',
                                          style: const TextStyle(color: Color(0xFF8295B7), fontSize: 11)),
                                        const SizedBox(height: 5),
                                        Text(
                                          _activeServer?.name ?? _preferredServer?.name ??
                                            (_fa ? 'انتخاب خودکار سرور' : 'Auto select server'),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white,
                                            fontSize: 15, fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(_fa ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                                    color: const Color(0xFF8CA4CE), size: 25),
                                ],
                              ),
                            ),
                          ),
                          if (_connected) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101A2D),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFF202F4C)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _ConnectionMetric(label: _fa ? 'دریافت' : 'Download',
                                    value: _formatRate(_downloadSpeed), icon: Icons.download_rounded),
                                  _metricDivider(),
                                  _ConnectionMetric(label: _fa ? 'ارسال' : 'Upload',
                                    value: _formatRate(_uploadSpeed), icon: Icons.upload_rounded),
                                  _metricDivider(),
                                  _ConnectionMetric(label: _fa ? 'پینگ' : 'Ping',
                                    value: _pingMs == null ? '—' : '$_pingMs ms',
                                    icon: Icons.speed_rounded),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _trafficTile(
                                  _fa ? 'دریافت کل' : 'Total download',
                                  _formatBytes(_downloadedBytes), Icons.south_rounded)),
                                const SizedBox(width: 10),
                                Expanded(child: _trafficTile(
                                  _fa ? 'ارسال کل' : 'Total upload',
                                  _formatBytes(_uploadedBytes), Icons.north_rounded)),
                              ],
                            ),
                          ],
                          if (_message != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A2330).withValues(alpha: .55),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF754052)),
                              ),
                              child: Text(_message!, textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFFFFC5D0), height: 1.45, fontSize: 12)),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Center(child: Text(
                            _fa ? 'NOVA VPN  •  اتصال هوشمند و امن' : 'NOVA VPN  •  Smart and secure connection',
                            style: const TextStyle(color: Color(0xFF526583), fontSize: 10, letterSpacing: .6))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _metricDivider() => Container(width: 1, height: 34, color: const Color(0xFF293A59));

  Widget _trafficTile(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFF101A2D),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFF202F4C)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF69A0FF), size: 18),
            const SizedBox(width: 9),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF8295B7), fontSize: 10)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            )),
          ],
        ),
      );

}


class _ConnectionMetric extends StatelessWidget {
  const _ConnectionMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF69A0FF)),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      );
}
