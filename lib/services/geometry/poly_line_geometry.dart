import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Poly Line"`. Unlike every other
/// shape here, its outline isn't derived from a node/arc count — xLights
/// stores the exact path the user drew as `PointData`
/// (`"x0,y0,z0,x1,y1,z1,..."`, one triple per drag handle, z ignored for
/// this 2D preview).
///
/// `DropPattern` (a comma-separated, cycling list of pixel counts — a bare
/// number like `"5"` means every location uses that count) turns each
/// evenly-spaced location along the path into a vertical "icicle" of that
/// many pixels instead of a single point on the path — confirmed against a
/// real file's "Pixel_Stakes" models (`DropPattern="5"`, evenly spaced
/// stakes along a line) vs. its "Dormer" (`DropPattern="1"`, i.e. no real
/// drop — just a point on the path, same as this builder's behavior before
/// drops were supported). Each drop's length is sized relative to the gap
/// between locations (see the comment at its computation below), not from
/// `ModelHeight` — its real-world meaning wasn't confirmed against a sample
/// where it made a visible difference. Enough locations are cycled through
/// the pattern to total `PolyStrings * NodesPerString` pixels (matching the
/// node-count formula in node_calc.dart), spaced at equal arc-length
/// intervals, mirroring xLights' own even distribution.
///
/// The first point is always `(0,0)`, matching the world-placement
/// convention: unlike the scale/rotate shapes this file's siblings build
/// (whose `WorldPosX/Y` is their bounding-box *center*), a Poly Line's
/// `WorldPosX/Y` is that first drag handle, so [buildWorldPlacedModel]
/// anchors this local origin directly at world position instead of
/// centering it.
WiredModel buildPolyLine(XmlElement root) {
  final coords = attrString(root, 'PointData')
      .split(',')
      .map((s) => double.tryParse(s.trim()))
      .whereType<double>()
      .toList();
  final vertexCount = coords.length ~/ 3;

  final nodes = <WiredNode>[];
  if (vertexCount < 2) {
    return WiredModel.fromNodes(
      name: attrString(root, 'name', fallback: 'Poly Line'),
      displayAs: 'Poly Line',
      nodes: nodes,
    );
  }

  final vertices = [
    for (var i = 0; i < vertexCount; i++) (x: coords[i * 3], y: coords[i * 3 + 1]),
  ];

  final segLengths = <double>[];
  for (var i = 0; i < vertices.length - 1; i++) {
    final a = vertices[i], b = vertices[i + 1];
    segLengths.add(math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2)));
  }
  final totalLen = segLengths.fold(0.0, (sum, l) => sum + l);

  final polyStrings = math.max(1, attrInt(root, 'PolyStrings', parmFallback: 'parm1', fallback: 1));
  final nodesPerString = math.max(1, attrInt(root, 'NodesPerString', parmFallback: 'parm2', fallback: 1));
  final totalNodes = polyStrings * nodesPerString;

  ({double x, double y}) pointAtDistance(double dist) {
    if (totalLen <= 0) return vertices.first;
    var acc = 0.0;
    var segIdx = segLengths.length - 1;
    for (var s = 0; s < segLengths.length; s++) {
      if (dist <= acc + segLengths[s] || s == segLengths.length - 1) {
        segIdx = s;
        break;
      }
      acc += segLengths[s];
    }
    final segLen = segLengths[segIdx];
    final segT = segLen <= 0 ? 0.0 : (dist - acc) / segLen;
    final a = vertices[segIdx], b = vertices[segIdx + 1];
    return (x: a.x + (b.x - a.x) * segT, y: a.y + (b.y - a.y) * segT);
  }

  var dropPattern = attrString(root, 'DropPattern')
      .split(',')
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .toList();
  if (dropPattern.isEmpty || dropPattern.every((n) => n <= 0)) dropPattern = const [1];
  final modelHeight = attrDouble(root, 'ModelHeight', fallback: 1);

  // Cycle the drop pattern into a list of per-location pixel counts totalling
  // totalNodes pixels overall (a location can be a bare point, when its count
  // is 1, or a whole vertical drop otherwise).
  final locationCounts = <int>[];
  var used = 0;
  var patIdx = 0;
  while (used < totalNodes) {
    final take = math.min(dropPattern[patIdx % dropPattern.length], totalNodes - used);
    locationCounts.add(take);
    used += take;
    patIdx++;
  }

  // ModelHeight's exact real-world meaning is unconfirmed (only two real
  // samples were available: "1"/"-1", both on drops 1 pixel deep, where it
  // makes no visible difference either way), so its magnitude is ignored —
  // only its sign is used, for direction. Drop length instead scales with
  // the gap between stakes (confirmed against a real "Pixel_Stakes" example,
  // `DropPattern="5"`, evenly spaced along its line): each drop reaches 60%
  // of the way to the next one, tall enough to read clearly as a vertical
  // tick without the drops of neighboring stakes visually merging together.
  final avgLocationSpacing =
      locationCounts.length > 1 ? totalLen / (locationCounts.length - 1) : totalLen;
  final maxDropCount = locationCounts.fold(1, (m, c) => math.max(m, c));
  final dropSpanTarget = avgLocationSpacing * 0.6;
  final dropSpacing = maxDropCount > 1 ? dropSpanTarget / (maxDropCount - 1) : dropSpanTarget;
  final dropSign = modelHeight < 0 ? -1.0 : 1.0;

  var counter = 1;
  for (var i = 0; i < locationCounts.length; i++) {
    final t = locationCounts.length > 1 ? i / (locationCounts.length - 1) : 0.0;
    final base = pointAtDistance(t * totalLen);
    final dropCount = locationCounts[i];
    for (var d = 0; d < dropCount; d++) {
      final y = base.y + dropSign * dropSpacing * d;
      // y negated: same y-up -> y-down flip used across this module.
      nodes.add(WiredNode(node: counter++, x: base.x, y: -y));
    }
  }

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Poly Line'),
    displayAs: 'Poly Line',
    nodes: nodes,
  );
}
