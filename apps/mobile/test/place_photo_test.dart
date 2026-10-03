import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';

void main() {
  test('independent photos keep their direct URL and license credits', () {
    final details = PlaceDetails.fromJson({
      'photos': [
        {
          'url': 'https://upload.wikimedia.org/example.jpg',
          'attribution': 'Photographer · CC BY-SA 4.0',
          'sourceUrl': 'https://commons.wikimedia.org/wiki/File:Example.jpg',
          'licenseUrl': 'https://creativecommons.org/licenses/by-sa/4.0/',
        },
        {},
      ],
    });
    expect(details.photos, hasLength(1));
    expect(
      details.photos.single.url,
      'https://upload.wikimedia.org/example.jpg',
    );
    expect(details.photos.single.attribution, contains('CC BY-SA'));
    expect(details.photos.single.sourceUrl, contains('commons.wikimedia.org'));
    final googlePhoto = PlacePhoto.fromJson({'name': 'places/test/photos/one'});
    expect(Uri.parse(googlePhoto.url).path, '/api/place-photo');
    expect(
      Uri.parse(googlePhoto.url).queryParameters['name'],
      googlePhoto.name,
    );
  });
}
