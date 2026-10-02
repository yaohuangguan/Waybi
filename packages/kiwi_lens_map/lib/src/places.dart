import 'geometry.dart';

class ProviderReference {
  const ProviderReference(this.provider, this.id);

  final String provider;
  final String id;
}

enum PlaceKind { poi, address, coordinate }

class PlaceSummary {
  const PlaceSummary({
    required this.name,
    required this.location,
    this.address = '',
    this.category = '',
    this.kind = PlaceKind.poi,
    this.reference,
  });

  final String name;
  final GeoPoint location;
  final String address;
  final String category;
  final PlaceKind kind;
  final ProviderReference? reference;
}

class PlaceCandidate {
  const PlaceCandidate({
    required this.name,
    this.address = '',
    this.category = '',
    this.kind = PlaceKind.poi,
    this.location,
    this.reference,
  });

  final String name;
  final String address;
  final String category;
  final PlaceKind kind;
  final GeoPoint? location;
  final ProviderReference? reference;

  String get secondaryAddress => placeSecondaryAddress(name, address);

  PlaceSummary toPlace(GeoPoint resolvedLocation) => PlaceSummary(
    name: name,
    location: resolvedLocation,
    address: secondaryAddress,
    category: category,
    kind: kind,
    reference: reference,
  );
}

String placeSecondaryAddress(String name, String address) {
  final trimmed = address.trim();
  final prefix = '${name.trim()},';
  if (trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
    return trimmed.substring(prefix.length).trim();
  }
  return trimmed;
}
