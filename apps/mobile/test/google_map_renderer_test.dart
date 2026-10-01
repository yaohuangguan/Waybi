import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/providers/google_map_renderer.dart';

void main() {
  test('POI tap cancels a pending blank-map dismissal', () {
    final arbiter = MapTapArbiter();
    final now = DateTime(2026, 10, 1, 12);
    final blankRevision = arbiter.markBlankCandidate();

    arbiter.markPlaceTap(now.add(const Duration(milliseconds: 40)));

    expect(
      arbiter.shouldCommitBlank(
        blankRevision,
        now.add(const Duration(milliseconds: 180)),
      ),
      isFalse,
    );
  });

  test('blank callback immediately after a POI tap is suppressed', () {
    final arbiter = MapTapArbiter();
    final now = DateTime(2026, 10, 1, 12);

    arbiter.markPlaceTap(now);
    final blankRevision = arbiter.markBlankCandidate();

    expect(
      arbiter.shouldCommitBlank(
        blankRevision,
        now.add(const Duration(milliseconds: 180)),
      ),
      isFalse,
    );
    expect(
      arbiter.shouldCommitBlank(
        blankRevision,
        now.add(const Duration(milliseconds: 400)),
      ),
      isTrue,
    );
  });

  test('ordinary blank-map tap is still committed', () {
    final arbiter = MapTapArbiter();
    final revision = arbiter.markBlankCandidate();

    expect(
      arbiter.shouldCommitBlank(revision, DateTime(2026, 10, 1, 12)),
      isTrue,
    );
  });
}
