import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../models/wired_model.dart';
import 'geometry_attrs.dart';

/// Builds a [WiredModel] for `DisplayAs="Window Frame"`: a rectangle traced
/// around its own perimeter — up the left side, across the top, down the
/// right side, then across the bottom — sized by `TopNodes`/`SideNodes`/
/// `BottomNodes` (matching the node-count formula in node_calc.dart:
/// `2*Side + Top + Bottom`). [ModelPreviewPainter] draws plain unordered
/// dots, so unlike a real wiring diagram the exact xLights wiring order
/// (which corner it starts/ends at) doesn't need to match here — only the
/// spatial outline does.
WiredModel buildWindowFrame(XmlElement root) {
  final sideNodes = attrInt(root, 'SideNodes', parmFallback: 'parm2');
  final topNodes = attrInt(root, 'TopNodes', parmFallback: 'parm1');
  final bottomNodes = attrInt(root, 'BottomNodes', parmFallback: 'parm3');

  final width = math.max(topNodes, math.max(bottomNodes, 1)) - 1;
  final height = math.max(sideNodes - 1, 1);

  List<({double x, double y})> edge(
    double x0, double y0, double x1, double y1, int count) {
    if (count <= 0) return const [];
    if (count == 1) return [(x: x0, y: y0)];
    return [
      for (var i = 0; i < count; i++)
        (x: x0 + (x1 - x0) * i / (count - 1), y: y0 + (y1 - y0) * i / (count - 1)),
    ];
  }

  final points = <({double x, double y})>[
    ...edge(0, 0, 0, height.toDouble(), sideNodes), // left, bottom -> top
    ...edge(0, height.toDouble(), width.toDouble(), height.toDouble(), topNodes), // top, left -> right
    ...edge(width.toDouble(), height.toDouble(), width.toDouble(), 0, sideNodes), // right, top -> bottom
    ...edge(width.toDouble(), 0, 0, 0, bottomNodes), // bottom, right -> left
  ];

  final nodes = <WiredNode>[
    for (var i = 0; i < points.length; i++)
      // y negated: xLights' convention is y-up, this canvas draws y-down —
      // same flip applied by every other geometry builder in this module.
      WiredNode(node: i + 1, x: points[i].x, y: -points[i].y),
  ];

  return WiredModel.fromNodes(
    name: attrString(root, 'name', fallback: 'Window Frame'),
    displayAs: 'Window Frame',
    nodes: nodes,
  );
}
