import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ui/prop_icons.dart';
import 'layout_map.dart';
import 'layout_store.dart';

/// Longest side (in rasterized pixels) the exported map image is scaled to,
/// balancing print sharpness against a reasonable file size/render time even
/// for a very large layout.
const int _kTargetLongestSide = 2400;

/// Builds a one-page, image-based PDF of the Layout Preview tab's site map —
/// unlike [ReportPdf]'s tables, this is a raster export (there's no vector
/// "PDF canvas" equivalent to `dart:ui`'s `Canvas` readily available here),
/// rendered at a fixed target resolution via a plain [ui.PictureRecorder]
/// rather than mounting the on-screen widget tree, so it always captures the
/// whole map regardless of the current pan/zoom.
class PreviewPdf {
  static Future<Uint8List> build(
    PdfPageFormat format,
    LayoutStore store, {
    String? group,
  }) async {
    final props = group == null
        ? store.props
        : store.props.where((p) => p.layoutGroup == group).toList();
    final map = buildLayoutMap(props);
    final pngBytes = await _rasterize(map);

    final doc = pw.Document(title: 'xLights Layout Preview');
    final image = pw.MemoryImage(pngBytes);
    final landscape = map.canvasWidth >= map.canvasHeight;
    final pageFormat = (landscape ? format.landscape : format.portrait).copyWith(
      marginTop: 24,
      marginBottom: 24,
      marginLeft: 24,
      marginRight: 24,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> _rasterize(LayoutMap map) async {
    final scale = (_kTargetLongestSide / math.max(map.canvasWidth, map.canvasHeight))
        .clamp(0.5, 4.0);
    final pixelW = (map.canvasWidth * scale).round();
    final pixelH = (map.canvasHeight * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
      ui.Offset.zero & ui.Size(map.canvasWidth, map.canvasHeight),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    for (final g in map.placed) {
      final paint = ui.Paint()
        ..color = ui.Color.fromRGBO(0, 0, 0, g.prop.isAssigned ? 0.9 : 0.35)
        ..strokeWidth = g.dotSize
        ..strokeCap = ui.StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, g.canvasPoints, paint);
    }

    const iconSize = 28.0;
    for (final p in map.iconOnly) {
      final center = map.toCanvas(p.worldPosX, p.worldPosY);
      final rect = ui.Rect.fromCenter(center: center, width: iconSize, height: iconSize);
      if (p.isAssigned) {
        paintPropShapeIcon(canvas, rect, p.shape);
      } else {
        // Group-opacity trick: saveLayer's paint alpha scales everything
        // drawn before the matching restore(), same as the Opacity widget.
        canvas.saveLayer(rect.inflate(2), ui.Paint()..color = const ui.Color.fromARGB(115, 0, 0, 0));
        paintPropShapeIcon(canvas, rect, p.shape);
        canvas.restore();
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelW, pixelH);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
