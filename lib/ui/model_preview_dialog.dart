import 'package:flutter/material.dart';

import '../models/prop.dart';
import '../services/model_geometry.dart';
import '../widgets/model_preview_painter.dart';

/// Opens a shape-preview dialog for [prop], or a snackbar explaining why one
/// isn't available (DMX fixtures, and shapes this viewer doesn't render yet).
void showModelPreview(BuildContext context, XProp prop) {
  final model = buildWiredModelPreview(prop.element);
  if (model == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No shape preview available for "${prop.name}".')),
    );
    return;
  }

  showDialog(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(prop.name, style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Text(
                  '${prop.displayAs} · ${model.nodes.length} px',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: ModelPreviewPainter(
                          model: model,
                          dotColor: theme.colorScheme.primary,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
