import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Cube"`: a wireframe box (its 12
/// edges) in an isometric-style projection so the depth axis stays visible
/// in a flat 2D preview, sized by `Width`/`Height`/`Depth`.
///
/// Unverified against a real Cube export (none was available in this
/// project's fixtures) — attribute names fall back to the legacy
/// `parm1`/`parm2`/`parm3` slots the way every other simple box-parameter
/// shape in this codebase does, but xLights' actual CubeModel attributes
/// haven't been confirmed against this.
WiredModel buildCube(XmlElement root) {
  final width = math.max(1, attrInt(root, 'Width', parmFallback: 'parm1', fallback: 10));
  final height = math.max(1, attrInt(root, 'Height', parmFallback: 'parm2', fallback: 10));
  final depth = math.max(1, attrInt(root, 'Depth', parmFallback: 'parm3', fallback: 10));

  // Isometric-ish projection: (x, y, z) -> (x + z*cos(30deg)*0.5, y + z*sin(30deg)*0.5).
  const depthAngle = math.pi / 6;
  final dcos = math.cos(depthAngle) * 0.5, dsin = math.sin(depthAngle) * 0.5;
  ({double x, double y}) project(double x, double y, double z) =>
      (x: x + z * dcos, y: y + z * dsin);

  final w = width.toDouble(), h = height.toDouble(), d = depth.toDouble();
  final c000 = (x: 0.0, y: 0.0, z: 0.0);
  final c100 = (x: w, y: 0.0, z: 0.0);
  final c010 = (x: 0.0, y: h, z: 0.0);
  final c001 = (x: 0.0, y: 0.0, z: d);
  final c110 = (x: w, y: h, z: 0.0);
  final c101 = (x: w, y: 0.0, z: d);
  final c011 = (x: 0.0, y: h, z: d);
  final c111 = (x: w, y: h, z: d);

  // Roughly one pixel per unit length along each edge, so bigger cubes get
  // proportionally denser outlines instead of a fixed, arbitrary count.
  final perEdge = math.max(2, ((width + height + depth) / 3).round());

  final nodes = <WiredNode>[];
  var counter = 1;
  void edge(({double x, double y, double z}) a, ({double x, double y, double z}) b) {
    for (var i = 0; i < perEdge; i++) {
      final t = perEdge > 1 ? i / (perEdge - 1) : 0.0;
      final p = project(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      );
      // y negated: same y-up -> y-down flip used across this module.
      nodes.add(WiredNode(node: counter++, x: p.x, y: -p.y));
    }
  }

  // Bottom face, top face, then the four verticals joining them.
  edge(c000, c100);
  edge(c100, c110);
  edge(c110, c010);
  edge(c010, c000);
  edge(c001, c101);
  edge(c101, c111);
  edge(c111, c011);
  edge(c011, c001);
  edge(c000, c001);
  edge(c100, c101);
  edge(c110, c111);
  edge(c010, c011);

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Cube'),
    displayAs: 'Cube',
    nodes: nodes,
  );
}
