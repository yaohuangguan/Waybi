import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:waybi_mobile/data/place_details_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/companion_search_prompt.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: WaybiTheme.lightFor('zh'),
      home: const _Preview(),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  LocationMarkerStyle marker = LocationMarkerStyle.dog;
  final place = const PlaceSummary(
    name: 'Sky Tower',
    location: GeoPoint(-36.8485, 174.7622),
    address:
        'Victoria Street West, Auckland Central, Auckland 1010, New Zealand',
    category: 'attraction',
    reference: ProviderReference('osm', 'gallery'),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 18,
            left: 16,
            right: 16,
            child: Column(
              children: [
                CompanionSearchPrompt(
                  marker: marker,
                  language: 'zh',
                  onSearch: (_) {},
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: PlaceDetailsContent(
              selectedPlace: place,
              details: PlaceDetails.fromJson({
                'name': place.name,
                'address': place.address,
                'primaryType': place.category,
                'photos': [
                  {
                    'url': 'https://upload.wikimedia.org/wikipedia/commons/f/f8/01_Auckland_New_Zealand-1000137.jpg',
                    'attribution': 'QFSE Media \u00b7 CC BY-SA 3.0 nz',
                    'sourceUrl': 'https://commons.wikimedia.org/wiki/File:01_Auckland_New_Zealand-1000137.jpg',
                    'licenseUrl': 'https://creativecommons.org/licenses/by-sa/3.0/nz/deed.en',
                  },
                ],
              }),
              detailsLoading: false,
              detailsError: null,
              routeBusy: false,
              isFavorite: false,
              onClose: () {},
              onNavigate: () {},
              onFavorite: () {},
              onReview: () {},
              language: 'zh',
            ),
          ),
        ],
      ),
    ),
  );
}
