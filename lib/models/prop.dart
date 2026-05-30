import 'package:xml/xml.dart';

import 'node_calc.dart' as calc;

/// Visual category for a prop, used to pick its little shape icon.
enum PropShape {
  arch,
  tree,
  matrix,
  star,
  circle,
  windowFrame,
  line,
  polyLine,
  custom,
  other,
}

PropShape _shapeFor(String displayAs) {
  switch (displayAs) {
    case 'Arches':
      return PropShape.arch;
    case 'Tree':
      return PropShape.tree;
    case 'Matrix':
      return PropShape.matrix;
    case 'Star':
      return PropShape.star;
    case 'Circle':
      return PropShape.circle;
    case 'Window Frame':
      return PropShape.windowFrame;
    case 'Single Line':
      return PropShape.line;
    case 'Poly Line':
      return PropShape.polyLine;
    case 'Custom':
      return PropShape.custom;
    default:
      return PropShape.other;
  }
}

/// A prop/model parsed from `xlights_rgbeffects.xml` (`<model>` element).
class XProp {
  XProp({
    required this.name,
    required this.displayAs,
    required this.controllerName,
    required this.port,
    required this.protocol,
    required this.startChannel,
    required this.universe,
    required this.modelChain,
    required this.nodeCount,
    required this.channelCount,
  });

  final String name;
  final String displayAs;

  /// Controller name as referenced by the model's `Controller` attribute.
  /// Empty / `"No Controller"` means unassigned.
  final String controllerName;

  /// Output port number from `<ControllerConnection Port="…">`; 0 if unassigned.
  final int port;

  /// Connection protocol from `<ControllerConnection Protocol="…">`, e.g. `ws2811`.
  final String protocol;

  /// Controller-relative start channel (the number after `!ctrl:` or an
  /// absolute channel), as displayed in the report.
  final int startChannel;

  /// Universe number when the model uses a `#universe:channel` start channel,
  /// else 0.
  final int universe;

  /// Name of the model this one is daisy-chained after (from `ModelChain`),
  /// without the leading `>`; empty if it starts a port.
  final String modelChain;

  final int nodeCount;
  final int channelCount;

  PropShape get shape => _shapeFor(displayAs);

  bool get isAssigned =>
      controllerName.isNotEmpty &&
      controllerName != 'No Controller' &&
      port > 0;

  /// `"ws2811:Port #17"` style string for the Detailed table.
  String get connectionLabel =>
      port > 0 ? '${protocol.isEmpty ? 'Port' : protocol}:Port #$port' : '';

  /// Whether this prop is chained onto a previous model (so the Condensed
  /// view shows it under the same port with a blank port label).
  bool get isChained => modelChain.isNotEmpty;

  factory XProp.fromXml(XmlElement e) {
    final attrs = <String, String>{
      for (final a in e.attributes) a.name.local: a.value,
    };
    String attr(String name) => attrs[name]?.trim() ?? '';

    // Normalise so pre-2026.04 variants (Horiz Matrix, Tree 360, …) collapse
    // onto the canonical type names used for shapes and node math.
    final displayAs = calc.normalizeDisplayAs(attr('DisplayAs'));

    // Controller connection child holds the physical port + protocol.
    var port = 0;
    var protocol = '';
    final conn = e.findElements('ControllerConnection').firstOrNull;
    if (conn != null) {
      port = int.tryParse(conn.getAttribute('Port')?.trim() ?? '') ?? 0;
      protocol = conn.getAttribute('Protocol')?.trim() ?? '';
    }

    final (startChannel, universe) = _parseStartChannel(attr('StartChannel'));

    var chain = attr('ModelChain');
    if (chain.startsWith('>')) chain = chain.substring(1).trim();

    return XProp(
      name: attr('name'),
      displayAs: displayAs,
      controllerName: attr('Controller'),
      port: port,
      protocol: protocol,
      startChannel: startChannel,
      universe: universe,
      modelChain: chain,
      nodeCount: calc.nodeCount(displayAs, attrs),
      channelCount: calc.channelCount(displayAs, attrs),
    );
  }
}

/// Parses an xLights `StartChannel` string into a (channel, universe) pair.
///
/// Supported forms:
///  - `!Controller:1234` → controller-relative channel 1234, universe 0
///  - `1234`             → absolute channel 1234, universe 0
///  - `#5:101`           → universe 5, channel 101
///  - `#192.168.1.5:5:101` → universe 5, channel 101 (leading IP ignored)
///  - `>Model:1`         → chained; channel 1 (best effort)
(int, int) _parseStartChannel(String raw) {
  if (raw.isEmpty) return (0, 0);

  if (raw.startsWith('#')) {
    final parts = raw.substring(1).split(':');
    // Last field is channel, the one before it is universe.
    if (parts.length >= 2) {
      final channel = int.tryParse(parts.last.trim()) ?? 0;
      final universe = int.tryParse(parts[parts.length - 2].trim()) ?? 0;
      return (channel, universe);
    }
    return (int.tryParse(parts.first.trim()) ?? 0, 0);
  }

  if (raw.startsWith('!') || raw.startsWith('>') || raw.startsWith('@')) {
    final colon = raw.lastIndexOf(':');
    if (colon >= 0) {
      return (int.tryParse(raw.substring(colon + 1).trim()) ?? 0, 0);
    }
    return (0, 0);
  }

  return (int.tryParse(raw.trim()) ?? 0, 0);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
