import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Sphere"`. Confirmed against a real
/// export: xLights' SphereModel reuses the same `NumStrings`/
/// `StrandsPerString`/`NodesPerString` buffer trio as Matrix/Tree (see
/// [buildMatrixBuffer]'s doc comment) — `NumStrings * StrandsPerString` is
/// the number of latitude rings, and `NodesPerString / StrandsPerString` is
/// the pixel count of each ring — swept from `StartLatitude` to
/// `EndLatitude` (degrees, 0 = equator) and around `Degrees` of longitude.
///
/// Rendered as a front-elevation projection (depth dropped) so it reads as a
/// globe's latitude lines, similar in spirit to the meridian/equator glyph
/// in `prop_icons.dart`'s sphere icon.
WiredModel buildSphere(XmlElement root) {
  final numStrings = math.max(1, attrInt(root, 'NumStrings', parmFallback: 'parm1', fallback: 1));
  final strandsPerString = math.max(1, attrInt(root, 'StrandsPerString', fallback: 1));
  final nodesPerString =
      math.max(1, attrInt(root, 'NodesPerString', parmFallback: 'parm2', fallback: 360));
  final pixelsPerRing = math.max(1, (nodesPerString / strandsPerString).round());
  final numRings = numStrings * strandsPerString;

  final startLat = attrDouble(root, 'StartLatitude', fallback: -90) * math.pi / 180.0;
  final endLat = attrDouble(root, 'EndLatitude', fallback: 90) * math.pi / 180.0;
  final degreesRaw = attrDouble(root, 'Degrees', fallback: 360);
  final degrees = (degreesRaw <= 0 ? 360 : degreesRaw) * math.pi / 180.0;
  final fullWrap = degreesRaw >= 360;

  // Radius chosen so the equator ring's own pixel spacing roughly matches
  // the pixel-index unit every other native shape in this module uses.
  final radius = pixelsPerRing / (2 * math.pi);

  final nodes = <WiredNode>[];
  var counter = 1;
  for (var r = 0; r < numRings; r++) {
    final lat = numRings > 1 ? startLat + (endLat - startLat) * r / (numRings - 1) : startLat;
    final ringRadius = radius * math.cos(lat);
    final y = radius * math.sin(lat);
    for (var n = 0; n < pixelsPerRing; n++) {
      final angle = fullWrap
          ? 2 * math.pi * n / pixelsPerRing
          : -degrees / 2 + (pixelsPerRing > 1 ? degrees * n / (pixelsPerRing - 1) : 0);
      final x = ringRadius * math.cos(angle);
      nodes.add(WiredNode(
        node: counter++,
        x: x,
        // y negated: same y-up -> y-down flip used across this module.
        y: -y,
        strand: 'Ring ${r + 1}',
        strandIndex: r,
      ));
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Sphere'),
    displayAs: 'Sphere',
    nodes: nodes,
  );
}
