import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/layout_store.dart';
import '../services/preview_pdf.dart';
import '../services/report_pdf.dart';
import 'condensed_tab.dart';
import 'detailed_tab.dart';
import 'github_picker_dialog.dart';
import 'layout_preview_tab.dart';

/// Top-level page: a three-tab report (Layout | Controller Wiring | Preview)
/// with load/print/start-over actions, mirroring the original web tool's
/// controls.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final LayoutStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _previewKey = GlobalKey<LayoutPreviewTabState>();
  bool _busy = false;

  LayoutStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
      _routeFile(bytes, file.name);
    }

    if (mounted && store.error != null) {
      _toast(store.error!);
    }
  }

  /// Lets the user browse a private GitHub repo (via a personal access
  /// token) and pick a file, then routes it the same way as a local file.
  Future<void> _loadFromGitHub() async {
    final result = await showGitHubPickerDialog(context);
    if (result == null) return;
    _routeFile(result.bytes, result.name);
    if (mounted && store.error != null) {
      _toast(store.error!);
    }
  }

  /// Inspects a loaded file's root element (or name, as a fallback) to route
  /// it to the right loader, regardless of where it came from.
  void _routeFile(List<int> bytes, String name) {
    final head = _peek(bytes);
    if (head.contains('<Networks') || name.contains('networks')) {
      store.loadNetworks(bytes, name);
    } else if (head.contains('<xrgb') || name.contains('rgbeffects')) {
      store.loadRgbEffects(bytes, name);
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
      if (_tabs.index == 2) {
        final group = _previewKey.currentState?.selectedGroup;
        await Printing.layoutPdf(
          name: 'xLights Layout Preview',
          onLayout: (format) => PreviewPdf.build(format, store, group: group),
        );
        return;
      }
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
              _LoadMenuButton(
                enabled: !_busy,
                onLoadLocal: _loadFiles,
                onLoadGitHub: _loadFromGitHub,
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
                      Tab(text: 'Preview'),
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
                    LayoutPreviewTab(key: _previewKey, store: store),
                  ],
                )
              : _EmptyState(onLoadLocal: _loadFiles, onLoadGitHub: _loadFromGitHub),
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

/// "Load files" action with a dropdown for choosing the source (local disk
/// or a private GitHub repo).
class _LoadMenuButton extends StatelessWidget {
  const _LoadMenuButton({
    required this.enabled,
    required this.onLoadLocal,
    required this.onLoadGitHub,
  });

  final bool enabled;
  final VoidCallback onLoadLocal;
  final VoidCallback onLoadGitHub;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) {
        return TextButton.icon(
          onPressed: enabled
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
          icon: const Icon(Icons.folder_open),
          label: const Text('Load files'),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.computer_outlined),
          onPressed: onLoadLocal,
          child: const Text('From this computer'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.code),
          onPressed: onLoadGitHub,
          child: const Text('From private GitHub repo'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onLoadLocal, required this.onLoadGitHub});

  final VoidCallback onLoadLocal;
  final VoidCallback onLoadGitHub;

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
              onPressed: onLoadLocal,
              icon: const Icon(Icons.folder_open),
              label: const Text('Load files from this computer'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onLoadGitHub,
              icon: const Icon(Icons.code),
              label: const Text('Load from private GitHub repo'),
            ),
          ],
        ),
      ),
    );
  }
}
