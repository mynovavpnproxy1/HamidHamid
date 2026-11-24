import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_vpn_app/app.dart';

void main() {
  testWidgets('renders NOVA VPN branding on the splash screen', (tester) async {
    await tester.pumpWidget(const NovaVpnApp());

    expect(find.text('NOVA VPN'), findsOneWidget);
    expect(find.text('اتصال هوشمند، سریع و امن'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
