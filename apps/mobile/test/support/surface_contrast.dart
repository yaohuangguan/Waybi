import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

/// The colour a [Text] is actually painted with (after DefaultTextStyle).
Color paintedTextColor(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  return paragraph.text.style!.color!;
}

/// The nearest opaque surface behind [finder]: a Material, ColoredBox or
/// BoxDecoration colour, composited over the scaffold when translucent.
Color surfaceBehind(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  final layers = <Color>[];
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    Color? colour;
    if (widget is Material && widget.type != MaterialType.transparency) {
      colour = widget.color ?? Theme.of(ancestor).colorScheme.surface;
    } else if (widget is ColoredBox) {
      colour = widget.color;
    } else if (widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color != null) {
      colour = (widget.decoration as BoxDecoration).color;
    } else if (widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color != null) {
      colour = (widget.decoration as BoxDecoration).color;
    }
    if (colour != null && colour.a > 0) {
      layers.add(colour);
      if (colour.a >= 1) return false;
    }
    return true;
  });
  var result = Theme.of(element).scaffoldBackgroundColor;
  for (final layer in layers.reversed) {
    result = over(layer, result);
  }
  return result;
}

/// Expects every text matched by [finder] to reach [minimum] contrast.
void expectReadable(
  WidgetTester tester,
  Finder finder, {
  double minimum = 4.5,
  String? reason,
}) {
  for (final element in finder.evaluate()) {
    final single = find.byElementPredicate((e) => e == element);
    final fg = paintedTextColor(tester, single);
    final bg = surfaceBehind(tester, single);
    final text = (element.widget as Text).data ?? '';
    expect(
      contrastRatio(over(fg, bg), bg),
      greaterThanOrEqualTo(minimum),
      reason: '${reason ?? ''} "$text" $fg on $bg',
    );
  }
}
