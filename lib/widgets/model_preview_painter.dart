import 'package:flutter/material.dart';

import '../models/wired_model.dart';

/// Draws a [WiredModel]'s pixels as plain dots, fitted and centered in the
/// canvas — a shape preview, not a wiring diagram, so no connecting path or
/// node-order markers are drawn (see WiringCanvas in xmodel_wiring_viewer for
/// that version).
class ModelPreviewPainter extends CustomPainter {
  final WiredModel model;
  final Color dotColor;
  final Color backgroundColor;

  ModelPreviewPainter({
    required this.model,
    required this.dotColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    final nodes = model.nodes;
    if (nodes.isEmpty) return;

    const margin = 20.0;
    final availW = size.width - margin * 2;
    final availH = size.height - margin * 2;
    final scaleW = availW / model.width;
    final scaleH = availH / model.height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    if (scale.isNaN || scale.isInfinite || scale <= 0) return;

    final drawnW = model.width * scale;
    final drawnH = model.height * scale;
    final originX = (size.width - drawnW) / 2;
    final originY = (size.height - drawnH) / 2;

    final dotRadius = nodes.length > 400 ? 1.5 : (nodes.length > 150 ? 2.5 : 4.0);
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = dotColor;

    for (final n in nodes) {
      final x = originX + (n.x - model.minX) * scale;
      final y = originY + (n.y - model.minY) * scale;
      canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ModelPreviewPainter old) =>
      old.model != model || old.dotColor != dotColor || old.backgroundColor != backgroundColor;
}
