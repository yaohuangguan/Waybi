/// Keep map colors geographic: neutral built-up areas, blue water and natural parks.
/// Kiwi Lime belongs to the controls and route accents rather than a map-wide tint.
const kiwiMapStyleLight = '''[
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#f4f4f2"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#b8d7eb"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#f5e8c8"}]}
]''';

const kiwiMapStyleDark = '''[
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#20252b"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#283b32"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#182e43"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#46505b"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#6b6658"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#d9dfe4"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#20252b"}]}
]''';
