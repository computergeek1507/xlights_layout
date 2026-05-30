import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/prop.dart';

/// A small black-box glyph representing a prop's shape, echoing the icons used
/// by the original alexthepunk.com layout tool.
class PropShapeIcon extends StatelessWidget {
  const PropShapeIcon(this.shape, {super.key, this.size = 22});

  final PropShape shape;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
      ),
      child: CustomPaint(painter: _ShapePainter(shape)),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.shape);

  final PropShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = Colors.white;
    final w = size.width;
    final h = size.height;
    final pad = w * 0.18;

    switch (shape) {
      case PropShape.arch:
        final rect = Rect.fromLTRB(pad, pad, w - pad, h + (h - pad));
        canvas.drawArc(rect, math.pi, math.pi, false, stroke);
        break;
      case PropShape.line:
      case PropShape.polyLine:
      case PropShape.other:
        canvas.drawLine(Offset(pad, h - pad), Offset(w - pad, pad), stroke);
        break;
      case PropShape.windowFrame:
        canvas.drawRect(Rect.fromLTRB(pad, pad, w - pad, h - pad), stroke);
        break;
      case PropShape.circle:
        canvas.drawCircle(Offset(w / 2, h / 2), (w - 2 * pad) / 2, stroke);
        canvas.drawCircle(Offset(w / 2, h / 2), (w - 2 * pad) / 4, stroke);
        break;
      case PropShape.tree:
        final path = Path()
          ..moveTo(w / 2, pad)
          ..lineTo(w - pad, h - pad)
          ..lineTo(pad, h - pad)
          ..close();
        canvas.drawPath(path, stroke);
        break;
      case PropShape.matrix:
        _drawGrid(canvas, size, fill, cols: 5, rows: 5);
        break;
      case PropShape.custom:
        _drawGrid(canvas, size, fill, cols: 4, rows: 4, dotted: true);
        break;
      case PropShape.star:
        _drawStar(canvas, size, stroke);
        break;
    }
  }

  void _drawGrid(Canvas canvas, Size size, Paint fill,
      {required int cols, required int rows, bool dotted = false}) {
    final pad = size.width * 0.16;
    final cw = (size.width - 2 * pad) / cols;
    final ch = (size.height - 2 * pad) / rows;
    final r = math.min(cw, ch) * 0.28;
    for (var c = 0; c < cols; c++) {
      for (var row = 0; row < rows; row++) {
        if (dotted && (c + row).isOdd) continue;
        final cx = pad + cw * (c + 0.5);
        final cy = pad + ch * (row + 0.5);
        canvas.drawCircle(Offset(cx, cy), r, fill);
      }
    }
  }

  void _drawStar(Canvas canvas, Size size, Paint stroke) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width * 0.36;
    final inner = outer * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) => oldDelegate.shape != shape;
}
