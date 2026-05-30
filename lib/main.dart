import 'package:flutter/material.dart';

import 'services/layout_store.dart';
import 'ui/home_page.dart';

void main() => runApp(const XLightsLayoutApp());

class XLightsLayoutApp extends StatefulWidget {
  const XLightsLayoutApp({super.key});

  @override
  State<XLightsLayoutApp> createState() => _XLightsLayoutAppState();
}

class _XLightsLayoutAppState extends State<XLightsLayoutApp> {
  final LayoutStore _store = LayoutStore();

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xLights Layout Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
      ),
      home: HomePage(store: _store),
    );
  }
}
