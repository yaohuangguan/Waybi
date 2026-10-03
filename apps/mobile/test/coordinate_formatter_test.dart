import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/coordinate_formatter.dart';

void main() {
  test('formats map coordinates consistently for place cards', () {
    expect(formatCoordinate(-36.8485, 174.7633), '-36.84850, 174.76330');
  });
}
