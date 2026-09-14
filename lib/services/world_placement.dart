import 'dart:math' as math;
import 'dart:ui';

import '../models/prop.dart';
import 'model_geometry.dart';

/// A model's actual pixel layout, transformed into its preview's world-space
/// (same units/orientation as `WorldPosX`/`WorldPosY`) so the Layout Preview
/// tab can draw the real dot pattern instead of a generic shape glyph.
class WorldPlacedModel {
  WorldPlacedModel({required this.points, required this.minX, required this.minY, required this.maxX, required this.maxY});

  /// Pixel positions in world space (Y-up, like `WorldPosY`).
  final List<Offset> points;
  final double minX, minY, maxX, maxY;
}

/// Builds [prop]'s pixel layout positioned/scaled/rotated into world space,
/// approximating how xLights' own Layout tab places it. Three placement
/// conventions, picked by which attributes are present on the model's XML
/// element:
///
/// - Two-point models (Arches, Single Line — anything xLights positions with
///   a second drag handle at `X2`/`Y2`): the local shape from
///   [buildWiredModelPreview] (whose x axis already runs 0..width) is
///   stretched uniformly and rotated so it exactly spans the segment from
///   `(WorldPosX, WorldPosY)` to `(WorldPosX+X2, WorldPosY+Y2)`.
/// - Poly Line (has `PointData`): its local shape already traces the
///   absolute path the user drew, anchored at local origin, so `WorldPosX/Y`
///   places that origin directly (not the shape's center, unlike the next
///   case) — `ScaleX`/`ScaleY` are still a direct multiplier.
/// - Scale/rotate models (Matrix, Custom, Circle, Star, Tree, Window Frame,
///   Sphere, Cube — anything with `ScaleX`/`ScaleY`): `WorldPosX/Y` is the
///   shape's center; the local bounding box (built in the same "pixel index"
///   units xLights itself uses, confirmed against several model types in a
///   real export) is scaled by `ScaleX`/`ScaleY` and rotated by `RotateZ`
///   about that center.
///
/// Best-effort: xLights' exact internal transform isn't public, so this is
/// reverse-engineered from real exported coordinates rather than source, and
/// a rotated model's handedness isn't verified against a real sample. Returns
/// null when there's no renderable pixel geometry or placement data (DMX
/// fixtures, unsupported shapes) — same cases [buildWiredModelPreview]
/// already returns null for.
WorldPlacedModel? buildWorldPlacedModel(XProp prop) {
  final local = buildWiredModelPreview(prop.element);
  if (local == null || local.nodes.isEmpty) return null;

  final root = prop.element;
  final worldX = prop.worldPosX;
  final worldY = prop.worldPosY;

  final x2Attr = root.getAttribute('X2');
  if (x2Attr != null) {
    final x2 = double.tryParse(x2Attr) ?? 0;
    final y2 = double.tryParse(root.getAttribute('Y2') ?? '') ?? 0;
    final length = math.sqrt(x2 * x2 + y2 * y2);
    if (length <= 0) return null;
    final localWidth = local.width <= 0 ? 1.0 : local.width;
    final scale = length / localWidth;
    final ux = x2 / length, uy = y2 / length; // unit vector along the segment
    final wx = -uy, wy = ux; // perpendicular unit vector

    return _placed([
      for (final n in local.nodes)
        () {
          // Every geometry builder in model_geometry.dart negates its local y
          // to suit the popup preview's plain y-down screen canvas; undo that
          // here so it lines up with world space's y-up convention (this
          // file applies its own y-down flip when mapping to canvas pixels).
          final ly = -n.y;
          return Offset(
            worldX + n.x * scale * ux + ly * scale * wx,
            worldY + n.x * scale * uy + ly * scale * wy,
          );
        }(),
    ]);
  }

  // Poly Line stores its own absolute path in `PointData` (local coordinates
  // relative to local origin, not necessarily starting at (0,0) — a chained
  // segment's PointData can start well away from it), so unlike the
  // scale/rotate branch below, `WorldPosX/Y` anchors that local origin
  // directly rather than the shape's center. `ScaleX`/`ScaleY` are a direct
  // multiplier here too (confirmed against a real file: two chained Poly
  // Line segments meant to sit end-to-end only line up under a direct
  // multiplier, not a /100 percentage).
  if (root.getAttribute('PointData') != null) {
    final scaleX = double.tryParse(root.getAttribute('ScaleX') ?? '') ?? 1;
    final scaleY = double.tryParse(root.getAttribute('ScaleY') ?? '') ?? scaleX;
    final rotateZ = double.tryParse(root.getAttribute('RotateZ') ?? '') ?? 0;
    final theta = rotateZ * math.pi / 180.0;
    final cosT = math.cos(theta), sinT = math.sin(theta);

    return _placed([
      for (final n in local.nodes)
        _rotatedPoint(
          dx: n.x * scaleX,
          dy: -n.y * scaleY,
          cosT: cosT,
          sinT: sinT,
          worldX: worldX,
          worldY: worldY,
        ),
    ]);
  }

  final scaleXAttr = root.getAttribute('ScaleX');
  if (scaleXAttr != null) {
    final scaleX = double.tryParse(scaleXAttr) ?? 1;
    final scaleY = double.tryParse(root.getAttribute('ScaleY') ?? '') ?? scaleX;
    final rotateZ = double.tryParse(root.getAttribute('RotateZ') ?? '') ?? 0;
    final theta = rotateZ * math.pi / 180.0;
    final cosT = math.cos(theta), sinT = math.sin(theta);
    final centerX = local.minX + local.width / 2;
    final centerY = local.minY + local.height / 2;

    return _placed([
      for (final n in local.nodes)
        _rotatedPoint(
          dx: (n.x - centerX) * scaleX,
          // Undo the geometry builders' baked-in y-down flip (see the
          // two-point branch above) before rotating/placing in world space.
          dy: -(n.y - centerY) * scaleY,
          cosT: cosT,
          sinT: sinT,
          worldX: worldX,
          worldY: worldY,
        ),
    ]);
  }

  return null;
}

Offset _rotatedPoint({
  required double dx,
  required double dy,
  required double cosT,
  required double sinT,
  required double worldX,
  required double worldY,
}) {
  final rx = dx * cosT - dy * sinT;
  final ry = dx * sinT + dy * cosT;
  return Offset(worldX + rx, worldY + ry);
}

WorldPlacedModel _placed(List<Offset> points) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in points) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  return WorldPlacedModel(points: points, minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}
