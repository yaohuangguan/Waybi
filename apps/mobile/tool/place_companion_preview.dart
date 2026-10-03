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
    name: 'Auckland Art Gallery Toi o Tāmaki',
    location: GeoPoint(-36.8514, 174.7663),
    address:
        'Wellesley Street East, Auckland Central, Auckland 1010, New Zealand',
    category: 'art_gallery',
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
                  onTap: () {},
                ),
                const SizedBox(height: 20),
                SegmentedButton<LocationMarkerStyle>(
                  segments: const [
                    ButtonSegment(
                      value: LocationMarkerStyle.kiwi,
                      label: Text('Waybi'),
                    ),
                    ButtonSegment(
                      value: LocationMarkerStyle.cat,
                      label: Text('Clover'),
                    ),
                    ButtonSegment(
                      value: LocationMarkerStyle.dog,
                      label: Text('Sett'),
                    ),
                  ],
                  selected: {marker},
                  onSelectionChanged: (value) =>
                      setState(() => marker = value.single),
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
