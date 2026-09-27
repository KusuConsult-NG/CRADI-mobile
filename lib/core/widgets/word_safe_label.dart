import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A label that never breaks a word in half.
///
/// Flutter's [Text] wraps at word boundaries, but when a *single* word is
/// wider than the line it breaks that word mid-character ("Pendin/g"). In a
/// narrow column — the dashboard stat cards at 320 px, or any locale whose
/// word for the same thing is longer — that is what the user sees.
///
/// This lays the text out at whatever width its widest word needs (never less
/// than the space available, so short labels still wrap normally at word
/// boundaries), then scales the result down to fit. The result: the label
/// fits, wraps between words, or shrinks — but is never cut through a word.
class WordSafeLabel extends StatelessWidget {
  const WordSafeLabel(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign,
    this.alignment = Alignment.centerLeft,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  /// Where the (possibly scaled-down) label sits in the space available.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(
      context,
    ).style.merge(style ?? const TextStyle());

    return LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(
          text,
          style: effectiveStyle,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
        if (!constraints.maxWidth.isFinite || constraints.maxWidth <= 0) {
          return label;
        }

        final textScaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        var widestWord = 0.0;
        for (final word in text.split(RegExp(r'\s+'))) {
          if (word.isEmpty) continue;
          final painter = TextPainter(
            text: TextSpan(text: word, style: effectiveStyle),
            textDirection: direction,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          widestWord = math.max(widestWord, painter.width);
          painter.dispose();
        }

        final layoutWidth = math.max(constraints.maxWidth, widestWord);
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: SizedBox(width: layoutWidth, child: label),
        );
      },
    );
  }
}
