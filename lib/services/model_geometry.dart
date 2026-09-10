import 'package:xml/xml.dart';

import '../models/wired_model.dart';
import 'geometry/arches_geometry.dart';
import 'geometry/circle_geometry.dart';
import 'geometry/custom_grid.dart';
import 'geometry/matrix_geometry.dart';
import 'geometry/single_line_geometry.dart';
import 'geometry/spinner_geometry.dart';
import 'geometry/star_geometry.dart';
import 'geometry/tree_geometry.dart';

typedef _Builder = WiredModel Function(XmlElement);

final Map<String, _Builder> _nativeGeometries = {
  'matrix': buildMatrix,
  'vert matrix': buildMatrix,
  'horiz matrix': buildMatrix,
  'single line': buildSingleLine,
  'arches': buildArches,
  'circle': buildCircle,
  'star': buildStar,
  'spinner': buildSpinner,
};

/// Builds a [WiredModel] shape preview from a `<model>` element parsed out of
/// `xlights_rgbeffects.xml`. Ported from xmodel_wiring_viewer's importer,
/// dropping the file-unwrapping logic (the caller already has the right
/// element) and returning null instead of throwing for shapes with no
/// renderable pixel geometry (DMX fixtures, unsupported shapes, or a Custom
/// model with no grid data), so the UI can just skip offering a preview.
WiredModel? buildWiredModelPreview(XmlElement root) {
  final name = root.getAttribute('name') ?? 'Model';
  final displayAs = (root.getAttribute('DisplayAs') ?? '').toLowerCase();

  if (displayAs == 'custom') {
    final grid = _importCustomGrid(root);
    if (grid == null) return null;
    return WiredModel.fromCustomGrid(grid, name: name);
  }

  final builder = displayAs.startsWith('tree') ? buildTree : _nativeGeometries[displayAs];
  if (builder == null) return null;

  try {
    final model = builder(root);
    return model.nodes.isEmpty ? null : model;
  } catch (_) {
    return null;
  }
}

CustomGrid? _importCustomGrid(XmlElement root) {
  final width = int.tryParse(root.getAttribute('CustomWidth') ?? '') ?? 0;
  final height = int.tryParse(root.getAttribute('CustomHeight') ?? '') ?? 0;

  final compressed = root.getAttribute('CustomModelCompressed');
  if (compressed != null && compressed.trim().isNotEmpty) {
    final grid = CustomGrid.fromCompressed(compressed, width: width, height: height);
    if (grid.cells.isNotEmpty) return grid;
  }

  final legacy = root.getAttribute('CustomModel');
  if (legacy != null && legacy.trim().isNotEmpty) {
    final grid = CustomGrid.fromLegacyGrid(legacy);
    if (grid.cells.isNotEmpty) return grid;
  }

  return null;
}
