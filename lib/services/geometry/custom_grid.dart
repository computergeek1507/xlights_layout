/// One pixel placed on the integer Custom-model grid. [node] is the xLights
/// 1-based node number; [col]/[row] are 0-based grid coordinates.
///
/// Ported from ddp_viewer (C:\software\ddp_viewer\lib\models\custom_grid.dart),
/// which itself extended pixel_mapper's writer-only version with the inverse
/// parsers [CustomGrid.fromCompressed] / [CustomGrid.fromLegacyGrid].
class GridCell {
  final int node;
  final int col;
  final int row;

  const GridCell({required this.node, required this.col, required this.row});
}

/// A normalized xLights Custom model: a [width] x [height] grid holding placed
/// pixels. Undetected pixels are simply absent (xLights tolerates sparse grids).
class CustomGrid {
  final int width;
  final int height;
  final List<GridCell> cells;

  const CustomGrid({
    required this.width,
    required this.height,
    required this.cells,
  });

  static const CustomGrid empty = CustomGrid(width: 1, height: 1, cells: []);

  /// Parses the modern `CustomModelCompressed` attribute: `;`-separated triples
  /// `node,row,col` (an optional 4th `layer` field is ignored — we are 2D).
  /// [width]/[height] come from the model's `CustomWidth`/`CustomHeight`; if
  /// absent (<= 0) they are inferred from the maximum row/col seen.
  factory CustomGrid.fromCompressed(String value, {int width = 0, int height = 0}) {
    final cells = <GridCell>[];
    var maxCol = -1;
    var maxRow = -1;
    for (final triple in value.split(';')) {
      final t = triple.trim();
      if (t.isEmpty) continue;
      final parts = t.split(',');
      if (parts.length < 3) continue;
      final node = int.tryParse(parts[0].trim());
      final row = int.tryParse(parts[1].trim());
      final col = int.tryParse(parts[2].trim());
      if (node == null || row == null || col == null) continue;
      cells.add(GridCell(node: node, col: col, row: row));
      if (col > maxCol) maxCol = col;
      if (row > maxRow) maxRow = row;
    }
    return CustomGrid(
      width: width > 0 ? width : maxCol + 1,
      height: height > 0 ? height : maxRow + 1,
      cells: cells,
    );
  }

  /// Parses the legacy `CustomModel` grid string: rows separated by `;`,
  /// columns by `,`, empty cells blank. Multi-layer strings (separated by `|`)
  /// are flattened to their first layer. Width/height are inferred from the
  /// grid shape.
  factory CustomGrid.fromLegacyGrid(String value) {
    // Take the first layer only for 2D rendering.
    final layer = value.split('|').first;
    final rows = layer.split(';');
    final cells = <GridCell>[];
    var width = 0;
    for (var r = 0; r < rows.length; r++) {
      final colsText = rows[r].split(',');
      if (colsText.length > width) width = colsText.length;
      for (var c = 0; c < colsText.length; c++) {
        final cell = colsText[c].trim();
        if (cell.isEmpty) continue;
        final node = int.tryParse(cell);
        if (node == null) continue;
        cells.add(GridCell(node: node, col: c, row: r));
      }
    }
    return CustomGrid(width: width, height: rows.length, cells: cells);
  }
}
