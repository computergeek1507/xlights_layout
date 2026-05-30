import 'package:flutter/material.dart';

import '../models/prop.dart';
import '../services/layout_store.dart';
import 'prop_icons.dart';

/// "Condensed" report: props grouped by controller, then split into String /
/// Smart Receiver / LED Panel Matrix / Serial sections, each port labelled.
/// Unassigned props are shown first under a "not assigned" header.
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
            items: [
              for (final p in data.notAssigned)
                _PropItem(shape: p.shape, port: 'generic Port #0', name: p.name),
            ],
          ),
        for (final group in data.groups)
          _GroupCard(title: group.name, items: _itemsFor(group)),
      ],
    );
  }

  /// Flattens a controller into ordered section headers + prop rows: String
  /// ports first, then each Smart Receiver (A–F), then LED Panel Matrix, then
  /// Serial ports, then any unported props.
  List<_Item> _itemsFor(ControllerGroup group) {
    final items = <_Item>[];

    void portSection(String title, Map<int, List<XProp>> ports) {
      if (ports.isEmpty) return;
      items.add(_HeaderItem(title));
      for (final port in ControllerGroup.sortedKeys(ports)) {
        _addPortProps(items, ports[port]!);
      }
    }

    portSection('String Ports', group.stringPorts);

    for (final receiver in group.sortedReceivers) {
      items.add(_HeaderItem(group.smartReceiverLabel(receiver), smart: true));
      for (final port in receiver.sortedPorts) {
        _addPortProps(items, receiver.ports[port]!);
      }
    }

    portSection('LED Panel Matrix', group.panelPorts);
    portSection('Serial Ports', group.serialPorts);

    for (final p in group.unported) {
      items.add(_PropItem(shape: p.shape, port: p.displayAs, name: p.name));
    }
    return items;
  }

  /// Adds one row per prop on a port. The port number is shown once (on the
  /// first row); daisy-chained pixel props below share it, while DMX/serial
  /// models each show their own channel.
  void _addPortProps(List<_Item> items, List<XProp> props) {
    for (var i = 0; i < props.length; i++) {
      items.add(_PropItem(
        shape: props[i].shape,
        port: condensedPortLabel(props[i], firstOnPort: i == 0),
        name: props[i].name,
      ));
    }
  }
}

/// A flattened row in a controller card: either a section header or a prop.
sealed class _Item {}

class _HeaderItem extends _Item {
  _HeaderItem(this.text, {this.smart = false});

  final String text;

  /// Smart-receiver headers get the arrow prefix + tinted background.
  final bool smart;
}

class _PropItem extends _Item {
  _PropItem({required this.shape, required this.port, required this.name});

  final PropShape shape;
  final String port;
  final String name;
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.items,
    this.italic = false,
    this.footnote,
  });

  final String title;
  final List<_Item> items;
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
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0 && items[i] is _PropItem && items[i - 1] is _PropItem)
                    const Divider(height: 1),
                  _ItemRow(items[i]),
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

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.item);

  final _Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = item;
    if (i is _HeaderItem) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: i.smart
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Text(
          i.smart ? '→ ${i.text}' : i.text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: i.smart ? theme.colorScheme.onPrimaryContainer : null,
          ),
        ),
      );
    }
    final p = i as _PropItem;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          PropShapeIcon(p.shape, size: 20),
          const SizedBox(width: 10),
          SizedBox(width: 170, child: Text(p.port)),
          const SizedBox(width: 8),
          Expanded(child: Text(p.name)),
        ],
      ),
    );
  }
}
