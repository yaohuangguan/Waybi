/// Native map styling keeps road names, traffic, and provider attribution.
const kiwiMapStyleLight = '''[
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f4f8e9"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#d8edb4"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9dfdc"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#e1ecad"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#35502b"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f8fbef"}]}
]''';

const kiwiMapStyleDark = '''[
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#1b2b17"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#2f4526"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#142a29"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#48503a"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#6c7845"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#dfebcb"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1b2b17"}]}
]''';
