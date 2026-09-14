import 'dart:ui';

import '../models/prop.dart';
import 'world_placement.dart';

const double kLayoutMapMargin = 60;
const double _minHitPad = 8;

/// One prop's dots already converted to canvas (child-space) pixel
/// coordinates, plus its canvas-space bounding box for hit-testing/tooltips.
class PlacedGeometry {
  PlacedGeometry({
    required this.prop,
    required this.canvasPoints,
    required this.dotSize,
    required this.canvasLeft,
    required this.canvasTop,
    required this.canvasRight,
    required this.canvasBottom,
  });

  final XProp prop;
  final List<Offset> canvasPoints;
  final double dotSize;
  final double canvasLeft, canvasTop, canvasRight, canvasBottom;
}

/// A set of props laid out on one shared canvas: real pixel geometry for
/// props [buildWorldPlacedModel] can place, plus the anchor point for
/// everything else (drawn as a fallback glyph by the caller).
class LayoutMap {
  LayoutMap({
    required this.placed,
    required this.iconOnly,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.minX,
    required this.maxY,
  });

  final List<PlacedGeometry> placed;
  final List<XProp> iconOnly;
  final double canvasWidth, canvasHeight;
  final double minX, maxY;

  /// World (x, Y-up) -> canvas (x, y-down) pixel coordinates, for an
  /// icon-only prop's single anchor point.
  Offset toCanvas(double worldX, double worldY) =>
      Offset(kLayoutMapMargin + (worldX - minX), kLayoutMapMargin + (maxY - worldY));
}

double dotSizeFor(int nodeCount) {
  if (nodeCount > 4000) return 1.0;
  if (nodeCount > 800) return 1.5;
  if (nodeCount > 150) return 2.2;
  return 3.2;
}

/// Builds the shared canvas layout for [props]: each model's real pixel
/// geometry positioned in world space (see [buildWorldPlacedModel]) mapped
/// onto one Y-down canvas sized to fit everything with a margin, or — for
/// props with no renderable geometry — just their anchor point, left for the
/// caller to draw a fallback glyph at. Used by both the on-screen Layout
/// Preview tab and its PDF export so they stay in sync.
LayoutMap buildLayoutMap(List<XProp> props) {
  final placedRaw = <(XProp, WorldPlacedModel)>[];
  final iconOnly = <XProp>[];
  for (final p in props) {
    final wp = buildWorldPlacedModel(p);
    if (wp != null) {
      placedRaw.add((p, wp));
    } else {
      iconOnly.add(p);
    }
  }

  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final (_, wp) in placedRaw) {
    minX = minX < wp.minX ? minX : wp.minX;
    minY = minY < wp.minY ? minY : wp.minY;
    maxX = maxX > wp.maxX ? maxX : wp.maxX;
    maxY = maxY > wp.maxY ? maxY : wp.maxY;
  }
  for (final p in iconOnly) {
    minX = minX < p.worldPosX ? minX : p.worldPosX;
    minY = minY < p.worldPosY ? minY : p.worldPosY;
    maxX = maxX > p.worldPosX ? maxX : p.worldPosX;
    maxY = maxY > p.worldPosY ? maxY : p.worldPosY;
  }
  if (minX > maxX) {
    minX = 0;
    maxX = 1;
    minY = 0;
    maxY = 1;
  }
  final canvasW = (maxX - minX).clamp(1, double.infinity) + kLayoutMapMargin * 2;
  final canvasH = (maxY - minY).clamp(1, double.infinity) + kLayoutMapMargin * 2;

  Offset toCanvas(double wx, double wy) =>
      Offset(kLayoutMapMargin + (wx - minX), kLayoutMapMargin + (maxY - wy));

  final placed = <PlacedGeometry>[
    for (final (p, wp) in placedRaw)
      PlacedGeometry(
        prop: p,
        canvasPoints: [for (final pt in wp.points) toCanvas(pt.dx, pt.dy)],
        dotSize: dotSizeFor(wp.points.length),
        canvasLeft: kLayoutMapMargin + (wp.minX - minX) - _minHitPad,
        canvasTop: kLayoutMapMargin + (maxY - wp.maxY) - _minHitPad,
        canvasRight: kLayoutMapMargin + (wp.maxX - minX) + _minHitPad,
        canvasBottom: kLayoutMapMargin + (maxY - wp.minY) + _minHitPad,
      ),
  ];

  return LayoutMap(
    placed: placed,
    iconOnly: iconOnly,
    canvasWidth: canvasW,
    canvasHeight: canvasH,
    minX: minX,
    maxY: maxY,
  );
}
