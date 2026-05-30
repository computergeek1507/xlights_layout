import 'package:flutter/material.dart';

import '../models/prop.dart';
import '../services/layout_store.dart';
import 'prop_icons.dart';

/// Maps a connection protocol to the port-label word xLights/FPP use.
String portWord(String protocol) {
  final p = protocol.toLowerCase();
  if (p.contains('dmx') ||
      p.contains('serial') ||
      p.contains('renard') ||
      p.contains('lor') ||
      p.contains('pixelnet')) {
    return 'Serial';
  }
  if (p.isEmpty) return 'generic';
  return 'String';
}

/// "Condensed" report: props grouped by controller, then by port. Unassigned
/// props are shown first under a "not assigned" header.
class CondensedTab extends StatelessWidget {
  const CondensedTab({super.key, required this.store});

  final LayoutStore store;

  @override
  Widget build(BuildContext context) {
    final data = store.grouped;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (data.notAssigned.isNotEmpty)
          _GroupCard(
            title: 'not assigned',
            italic: true,
            footnote: '* Port 0 means the prop was not assigned to a port in your layout',
            rows: [
              for (final p in data.notAssigned)
                _PropRow(
                  shape: p.shape,
                  port: 'generic Port #0',
                  name: p.name,
                ),
            ],
          ),
        for (final group in data.groups)
          _GroupCard(
            title: group.name,
            rows: _rowsFor(group),
          ),
      ],
    );
  }

  List<_PropRow> _rowsFor(ControllerGroup group) {
    final rows = <_PropRow>[];
    for (final port in group.sortedPorts) {
      final props = group.ports[port]!;
      for (var i = 0; i < props.length; i++) {
        final p = props[i];
        rows.add(_PropRow(
          shape: p.shape,
          // Only the first prop on a port shows the port label; daisy-chained
          // props below it share the port and show a blank label.
          port: i == 0 ? '${portWord(p.protocol)} Port #$port' : '',
          name: p.name,
        ));
      }
    }
    for (final p in group.unported) {
      rows.add(_PropRow(shape: p.shape, port: p.displayAs, name: p.name));
    }
    return rows;
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.rows,
    this.italic = false,
    this.footnote,
  });

  final String title;
  final List<_PropRow> rows;
  final bool italic;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: theme.colorScheme.primary, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  rows[i],
                ],
                if (footnote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(footnote!, style: theme.textTheme.bodySmall),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _PropRow extends StatelessWidget {
  const _PropRow({required this.shape, required this.port, required this.name});

  final PropShape shape;
  final String port;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          PropShapeIcon(shape, size: 20),
          const SizedBox(width: 10),
          SizedBox(width: 160, child: Text(port)),
          const SizedBox(width: 8),
          Expanded(child: Text(name)),
        ],
      ),
    );
  }
}
