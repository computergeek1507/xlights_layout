import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/prop.dart';
import '../services/layout_map.dart';
import '../services/layout_store.dart';
import 'model_preview_dialog.dart';
import 'prop_icons.dart';

/// A top-down map of every prop's actual pixel layout, positioned where it
/// sits in xLights' own Layout tab. Each model's real dot pattern is drawn
/// (via [buildLayoutMap]) when its geometry and world placement are known;
/// models with no renderable pixel geometry (DMX fixtures, Poly Line,
/// unsupported shapes) fall back to the small glyph used elsewhere in the
/// app. Pan/zoom is handled by [InteractiveViewer].
class LayoutPreviewTab extends StatefulWidget {
  const LayoutPreviewTab({super.key, required this.store});

  final LayoutStore store;

  @override
  State<LayoutPreviewTab> createState() => LayoutPreviewTabState();
}

class LayoutPreviewTabState extends State<LayoutPreviewTab> {
  final _viewer = TransformationController();
  String? _group;
  bool _fitted = false;

  static const double _iconSize = 28;

  /// The prop group currently shown (the selected preview/`LayoutGroup`, or
  /// null when the file has none) — read by the print action so it can
  /// export exactly what's on screen.
  String? get selectedGroup => _groups.contains(_group) ? _group : (_groups.isNotEmpty ? _groups.first : null);

  List<String> get _groups {
    final seen = <String>{};
    for (final p in widget.store.props) {
      if (p.layoutGroup.isNotEmpty) seen.add(p.layoutGroup);
    }
    final list = seen.toList()..sort();
    return list;
  }

  List<XProp> _propsInGroup(String? group) {
    final props = widget.store.props;
    if (group == null) return props;
    return props.where((p) => p.layoutGroup == group).toList();
  }

  void _fitToView(Size viewport, Rect bounds) {
    final scaleX = viewport.width / bounds.width;
    final scaleY = viewport.height / bounds.height;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.05, 4.0);
    final dx = (viewport.width - bounds.width * scale) / 2 - bounds.left * scale;
    final dy = (viewport.height - bounds.height * scale) / 2 - bounds.top * scale;
    _viewer.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final group = selectedGroup;
    if (group != _group) {
      _group = group;
      _fitted = false;
    }
    final props = _propsInGroup(group);

    return Column(
      children: [
        if (groups.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Text('Preview:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: group,
                  items: [
                    for (final g in groups) DropdownMenuItem(value: g, child: Text(g)),
                  ],
                  onChanged: (v) => setState(() {
                    _group = v;
                    _fitted = false;
                  }),
                ),
              ],
            ),
          ),
        Expanded(
          child: props.isEmpty
              ? const Center(child: Text('No positioned models in this preview.'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                    final map = buildLayoutMap(props);

                    if (!_fitted) {
                      _fitted = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _fitToView(
                            viewport,
                            Rect.fromLTWH(0, 0, map.canvasWidth, map.canvasHeight),
                          );
                        }
                      });
                    }

                    final theme = Theme.of(context);
                    return Stack(
                      children: [
                        InteractiveViewer(
                          transformationController: _viewer,
                          constrained: false,
                          minScale: 0.05,
                          maxScale: 6,
                          boundaryMargin: const EdgeInsets.all(400),
                          child: SizedBox(
                            width: map.canvasWidth,
                            height: map.canvasHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLowest,
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _LayoutDotsPainter(
                                        placed: map.placed,
                                        dotColor: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  for (final g in map.placed)
                                    Positioned(
                                      left: g.canvasLeft,
                                      top: g.canvasTop,
                                      width: g.canvasRight - g.canvasLeft,
                                      height: g.canvasBottom - g.canvasTop,
                                      child: _HitRegion(prop: g.prop),
                                    ),
                                  for (final p in map.iconOnly)
                                    Positioned(
                                      left: map.toCanvas(p.worldPosX, p.worldPosY).dx - _iconSize / 2,
                                      top: map.toCanvas(p.worldPosX, p.worldPosY).dy - _iconSize / 2,
                                      child: _IconMarker(prop: p, size: _iconSize),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: FloatingActionButton.small(
                            heroTag: 'fit-preview',
                            tooltip: 'Fit to view',
                            onPressed: () => _fitToView(
                              viewport,
                              Rect.fromLTWH(0, 0, map.canvasWidth, map.canvasHeight),
                            ),
                            child: const Icon(Icons.fit_screen),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }
}

class _LayoutDotsPainter extends CustomPainter {
  _LayoutDotsPainter({required this.placed, required this.dotColor});

  final List<PlacedGeometry> placed;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final g in placed) {
      final paint = Paint()
        ..color = dotColor.withValues(alpha: g.prop.isAssigned ? 0.95 : 0.4)
        ..strokeWidth = g.dotSize
        ..strokeCap = StrokeCap.round;
      canvas.drawPoints(ui.PointMode.points, g.canvasPoints, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutDotsPainter old) =>
      old.placed != placed || old.dotColor != dotColor;
}

String _tooltipText(XProp prop) {
  final subtitle = prop.isAssigned
      ? '${prop.displayAs} · ${prop.controllerName} ${prop.connectionLabel}'
      : '${prop.displayAs} · not assigned';
  return '${prop.name}\n$subtitle';
}

/// Invisible tap target laid over a dot-cloud prop's bounding box (the dots
/// themselves are drawn by the shared [_LayoutDotsPainter] beneath).
class _HitRegion extends StatelessWidget {
  const _HitRegion({required this.prop});

  final XProp prop;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltipText(prop),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showModelPreview(context, prop),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Fallback marker for props with no renderable pixel geometry.
class _IconMarker extends StatelessWidget {
  const _IconMarker({required this.prop, required this.size});

  final XProp prop;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltipText(prop),
      child: GestureDetector(
        onTap: () => showModelPreview(context, prop),
        child: Opacity(
          opacity: prop.isAssigned ? 1.0 : 0.45,
          child: PropShapeIcon(prop.shape, size: size),
        ),
      ),
    );
  }
}
