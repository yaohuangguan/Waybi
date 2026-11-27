import 'dart:ui';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Composites a translucent [foreground] over an opaque [background].
Color over(Color foreground, Color background) =>
    Color.alphaBlend(foreground, background);
