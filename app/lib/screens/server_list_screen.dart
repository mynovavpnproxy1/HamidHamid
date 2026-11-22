import 'package:flutter/material.dart';

import '../models/vpn_server.dart';
import '../services/api_service.dart';

/// Country -> city/location picker. Raw VPN profiles are never exposed.
class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key, required this.language});
  final String language;

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  final ApiService _api = ApiService();
  late Future<List<VpnServer>> _servers;
  final Set<String> _expandedCountries = <String>{};
  bool get _fa => widget.language == 'fa';

  @override
  void initState() {
    super.initState();
    _servers = _api.fetchServers();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  String _countryName(VpnServer server) =>
      (_fa ? server.countryNameFa : server.countryNameEn) ??
      server.countryNameEn ??
      server.countryCode ??
      (_fa ? 'موقعیت نامشخص' : 'Unknown location');

  String _locationName(VpnServer server) =>
      (_fa ? server.locationNameFa : server.locationNameEn) ??
      server.locationNameEn ??
      (_fa ? 'سایر موقعیت‌ها' : 'Other locations');

  String _flag(String code) => String.fromCharCodes(
        code.toUpperCase().codeUnits.map((unit) => 0x1F1E6 + unit - 0x41),
      );

  Map<String, List<VpnServer>> _group(List<VpnServer> servers) {
    final groups = <String, List<VpnServer>>{};
    for (final server in servers) {
      final code = server.countryCode;
      if (!server.locationVerified || code == null || code.length != 2) {
        continue;
      }
      (groups[code] ??= []).add(server);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(title: Text(_fa ? 'انتخاب کشور و موقعیت' : 'Select Location')),
          body: FutureBuilder<List<VpnServer>>(
            future: _servers,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _EmptyState(
                  message: _fa
                      ? 'دریافت موقعیت‌ها ممکن نیست. اتصال اینترنت را بررسی کنید.'
                      : 'Could not load locations. Check your internet connection.',
                  actionLabel: _fa ? 'تلاش دوباره' : 'Retry',
                  onAction: () => setState(() => _servers = _api.fetchServers()),
                );
              }

              final groups = _group(snapshot.data ?? const <VpnServer>[]);
              final countries = groups.keys.toList()
                ..sort((a, b) => _countryName(groups[a]!.first)
                    .compareTo(_countryName(groups[b]!.first)));

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xFF101A2B),
                    child: ListTile(
                      leading: const Icon(Icons.public, color: Color(0xFF3B82F6), size: 28),
                      title: Text(_fa ? 'اتصال خودکار' : 'Automatic'),
                      subtitle: Text(_fa
                          ? 'انتخاب سرور از تمام کشورها و شهرها'
                          : 'Choose an available server from any country or city'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(null),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (countries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _fa ? 'هنوز موقعیت فعالی ثبت نشده است.' : 'No active locations are available yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final code in countries)
                    Card(
                      color: const Color(0xFF101A2B),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        children: [
                          ListTile(
                            leading: Text(_flag(code), style: const TextStyle(fontSize: 27)),
                            title: Text(_countryName(groups[code]!.first)),
                            subtitle: Text(_fa
                                ? '${groups[code]!.length} کانفیگ فعال'
                                : '${groups[code]!.length} active configurations'),
                            trailing: Icon(_expandedCountries.contains(code)
                                ? Icons.expand_less : Icons.expand_more),
                            onTap: () => setState(() {
                              if (!_expandedCountries.add(code)) _expandedCountries.remove(code);
                            }),
                          ),
                          if (_expandedCountries.contains(code))
                            ..._locations(groups[code]!).entries.map((entry) {
                              final first = entry.value.first;
                              return Padding(
                                padding: const EdgeInsetsDirectional.only(start: 18, end: 10, bottom: 8),
                                child: Card(
                                  color: const Color(0xFF17263A),
                                  child: ListTile(
                                    leading: const Icon(Icons.location_on_outlined, color: Color(0xFF60A5FA)),
                                    title: Text(_locationName(first)),
                                    subtitle: Text(_fa
                                        ? '${entry.value.length} سرور در این موقعیت'
                                        : '${entry.value.length} servers in this location'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.of(context).pop<VpnServer>(first),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );

  Map<String, List<VpnServer>> _locations(List<VpnServer> servers) {
    final result = <String, List<VpnServer>>{};
    for (final server in servers) {
      // Keep city grouping stable when a record has only one language.
      final english = (server.locationNameEn ?? '').trim().toLowerCase();
      final persian = (server.locationNameFa ?? '').trim().toLowerCase();
      final key = english.isNotEmpty ? 'en:$english' : (persian.isNotEmpty ? 'fa:$persian' : 'other');
      (result[key] ??= []).add(server);
    }
    return Map.fromEntries(result.entries.toList()
      ..sort((a, b) => _locationName(a.value.first).compareTo(_locationName(b.value.first))));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.actionLabel, required this.onAction});
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      );
}
