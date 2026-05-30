import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/layout_store.dart';
import '../services/report_pdf.dart';
import 'condensed_tab.dart';
import 'detailed_tab.dart';

/// Top-level page: a two-tab report (Detailed | Condensed) with load/print/
/// start-over actions, mirroring the original web tool's controls.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final LayoutStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _busy = false;

  LayoutStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Lets the user pick one or both xLights XML files and routes each to the
  /// right loader by inspecting its root element.
  Future<void> _loadFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['xml'],
      dialogTitle: 'Select xlights_rgbeffects.xml (and optionally xlights_networks.xml)',
    );
    if (result == null) return;

    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final head = _peek(bytes);
      if (head.contains('<Networks') || file.name.contains('networks')) {
        store.loadNetworks(bytes, file.name);
      } else if (head.contains('<xrgb') || file.name.contains('rgbeffects')) {
        store.loadRgbEffects(bytes, file.name);
      }
    }

    if (mounted && store.error != null) {
      _toast(store.error!);
    }
  }

  String _peek(List<int> bytes) {
    final take = bytes.length < 512 ? bytes : bytes.sublist(0, 512);
    try {
      return utf8.decode(take, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  Future<void> _print() async {
    if (!store.hasData) {
      _toast('Load an xlights_rgbeffects.xml file first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final detailed = _tabs.index == 0;
      await Printing.layoutPdf(
        name: detailed ? 'xLights Layout' : 'xLights Controller Wiring',
        onLayout: (format) =>
            ReportPdf.build(format, store, detailed: detailed),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('xLights Layout Viewer'),
            actions: [
              TextButton.icon(
                onPressed: _busy ? null : _loadFiles,
                icon: const Icon(Icons.folder_open),
                label: const Text('Load files'),
              ),
              IconButton(
                tooltip: 'Print / export PDF',
                onPressed: _busy || !store.hasData ? null : _print,
                icon: const Icon(Icons.print),
              ),
              IconButton(
                tooltip: 'Start over',
                onPressed: store.hasData ? store.clear : null,
                icon: const Icon(Icons.restart_alt),
              ),
              const SizedBox(width: 8),
            ],
            bottom: store.hasData
                ? TabBar(
                    controller: _tabs,
                    tabs: const [
                      Tab(text: 'Layout'),
                      Tab(text: 'Controller Wiring'),
                    ],
                  )
                : null,
          ),
          body: store.hasData
              ? TabBarView(
                  controller: _tabs,
                  children: [
                    DetailedTab(store: store),
                    CondensedTab(store: store),
                  ],
                )
              : _EmptyState(onLoad: _loadFiles),
          bottomNavigationBar: const _Footer(),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🕯️', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(
              'For Alex',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onLoad});

  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Load your xLights layout', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Select xlights_rgbeffects.xml (required) and, optionally,\n'
              'xlights_networks.xml to view and print your show layout.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.folder_open),
              label: const Text('Load files'),
            ),
          ],
        ),
      ),
    );
  }
}
