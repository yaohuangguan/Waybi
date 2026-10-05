import 'models.dart';

enum SouvenirKind {
  letter,
  map,
  scroll,
  cookie,
  bun,
  shell,
  glass,
  feather,
  ticket,
  button,
  acorn,
  clover,
  twig,
  stone,
  leaf,
  flower,
  vial,
  stamp,
  token,
  fern,
  keepsake,
  eiffel,
  croissant,
  torii,
  mochi,
  bigBen,
  tea,
  liberty,
  pretzel,
  hollywood,
  palm,
  skyTower,
  pavlova,
  operaHouse,
  koala,
  orientalPearl,
  dumpling,
  shenzhen,
  greatWall,
  palace,
  teaScroll,
}

class SouvenirItem {
  const SouvenirItem(
    this.id,
    this.name,
    this.chineseName,
    this.kind,
    this.destinationId,
    this.legacyName,
  );
  final String id, name, chineseName, destinationId, legacyName;
  final SouvenirKind kind;
  String get asset =>
      'packages/waybi_friends/assets/souvenirs/${kind.name}.png';
}

const souvenirItems = <SouvenirItem>[
  SouvenirItem(
    'tiny-shell',
    'Tiny shell',
    '小贝壳',
    SouvenirKind.shell,
    'mission_bay',
    'a tiny shell',
  ),
  SouvenirItem(
    'sea-glass',
    'Sea-glass pebble',
    '海玻璃石',
    SouvenirKind.glass,
    'mission_bay',
    'a smooth sea-glass pebble',
  ),
  SouvenirItem(
    'sandy-feather',
    'Sandy feather',
    '沾着细沙的羽毛',
    SouvenirKind.feather,
    'mission_bay',
    'a sandy feather',
  ),
  SouvenirItem(
    'ferry-ticket',
    'Ferry ticket',
    '渡轮票',
    SouvenirKind.ticket,
    'devonport',
    'a ferry ticket corner',
  ),
  SouvenirItem(
    'blue-button',
    'Little blue button',
    '蓝色小纽扣',
    SouvenirKind.button,
    'devonport',
    'a little blue button',
  ),
  SouvenirItem(
    'harbour-map',
    'Folded harbour map',
    '折叠港湾地图',
    SouvenirKind.map,
    'devonport',
    'a folded harbour map',
  ),
  SouvenirItem(
    'acorn-cap',
    'Acorn cap',
    '橡果帽',
    SouvenirKind.acorn,
    'cornwall_park',
    'an acorn cap',
  ),
  SouvenirItem(
    'pressed-clover',
    'Pressed clover leaf',
    '压干的三叶草',
    SouvenirKind.clover,
    'cornwall_park',
    'a pressed clover leaf',
  ),
  SouvenirItem(
    'fallen-twig',
    'Small fallen twig',
    '落下的小枝条',
    SouvenirKind.twig,
    'cornwall_park',
    'a small fallen twig',
  ),
  SouvenirItem(
    'skyline-scroll',
    'Skyline sketch scroll',
    '天际线手绘卷轴',
    SouvenirKind.scroll,
    'mt_eden',
    'a sketch of the skyline',
  ),
  SouvenirItem(
    'volcanic-pebble',
    'Volcanic pebble',
    '火山石',
    SouvenirKind.stone,
    'mt_eden',
    'a grey volcanic pebble',
  ),
  SouvenirItem(
    'windswept-leaf',
    'Windswept leaf',
    '风中的树叶',
    SouvenirKind.leaf,
    'mt_eden',
    'a windswept leaf',
  ),
  SouvenirItem(
    'striped-shell',
    'Striped shell',
    '花纹贝壳',
    SouvenirKind.shell,
    'takapuna',
    'a striped shell',
  ),
  SouvenirItem(
    'driftwood',
    'Tiny driftwood stick',
    '小小漂流木',
    SouvenirKind.twig,
    'takapuna',
    'a tiny driftwood stick',
  ),
  SouvenirItem(
    'postage-stamp',
    'Postcard stamp',
    '明信片邮票',
    SouvenirKind.stamp,
    'takapuna',
    'a postcard stamp',
  ),
  SouvenirItem(
    'ferry-token',
    'Ferry token',
    '渡轮代币',
    SouvenirKind.token,
    'waiheke',
    'a ferry token',
  ),
  SouvenirItem(
    'dried-flower',
    'Dried flower',
    '干花',
    SouvenirKind.flower,
    'waiheke',
    'a dried flower',
  ),
  SouvenirItem(
    'island-map',
    'Little island map',
    '小岛地图',
    SouvenirKind.map,
    'waiheke',
    'a little island map',
  ),
  SouvenirItem(
    'black-sand',
    'Black-sand vial',
    '黑沙小瓶',
    SouvenirKind.vial,
    'piha',
    'a black-sand vial',
  ),
  SouvenirItem(
    'fern-tip',
    'Fern tip',
    '蕨叶',
    SouvenirKind.fern,
    'piha',
    'a fern tip',
  ),
  SouvenirItem(
    'dark-stone',
    'Smooth dark stone',
    '深色圆石',
    SouvenirKind.stone,
    'piha',
    'a smooth dark stone',
  ),
  SouvenirItem(
    'waybi-letter',
    'A letter from Waybi',
    'Waybi 的信',
    SouvenirKind.letter,
    '',
    '',
  ),
  SouvenirItem(
    'berry-cookie',
    'Berry cookie',
    '莓果饼干',
    SouvenirKind.cookie,
    '',
    '',
  ),
  SouvenirItem(
    'honey-bun',
    'Little honey bun',
    '蜂蜜小面包',
    SouvenirKind.bun,
    '',
    '',
  ),
];

const regionalSouvenirs = <SouvenirItem>[
  SouvenirItem(
    'fr-eiffel',
    'Eiffel Tower postcard',
    '埃菲尔铁塔明信片',
    SouvenirKind.eiffel,
    'FR',
    '',
  ),
  SouvenirItem(
    'fr-croissant',
    'Butter croissant',
    '黄油可颂',
    SouvenirKind.croissant,
    'FR',
    '',
  ),
  SouvenirItem(
    'jp-torii',
    'Torii travel postcard',
    '鸟居旅行明信片',
    SouvenirKind.torii,
    'JP',
    '',
  ),
  SouvenirItem(
    'jp-mochi',
    'Sakura mochi',
    '樱花麻薯',
    SouvenirKind.mochi,
    'JP',
    '',
  ),
  SouvenirItem(
    'gb-big-ben',
    'London clocktower postcard',
    '伦敦钟楼明信片',
    SouvenirKind.bigBen,
    'GB',
    '',
  ),
  SouvenirItem(
    'gb-tea',
    'Afternoon tea tin',
    '下午茶小茶罐',
    SouvenirKind.tea,
    'GB',
    '',
  ),
  SouvenirItem(
    'us-liberty',
    'New York harbour postcard',
    '纽约港明信片',
    SouvenirKind.liberty,
    'US',
    '',
  ),
  SouvenirItem(
    'us-pretzel',
    'New York pretzel',
    '纽约椒盐脆饼',
    SouvenirKind.pretzel,
    'US',
    '',
  ),
  SouvenirItem(
    'us-hollywood',
    'Los Angeles travel ticket',
    '洛杉矶旅行票',
    SouvenirKind.hollywood,
    'US',
    '',
  ),
  SouvenirItem(
    'us-palm',
    'California palm postcard',
    '加州棕榈明信片',
    SouvenirKind.palm,
    'US',
    '',
  ),
  SouvenirItem(
    'nz-sky-tower',
    'Auckland skyline postcard',
    '奥克兰天空塔明信片',
    SouvenirKind.skyTower,
    'NZ',
    '',
  ),
  SouvenirItem(
    'nz-pavlova',
    'Pavlova cake',
    '帕芙洛娃蛋糕',
    SouvenirKind.pavlova,
    'NZ',
    '',
  ),
  SouvenirItem(
    'au-opera',
    'Sydney harbour postcard',
    '悉尼歌剧院明信片',
    SouvenirKind.operaHouse,
    'AU',
    '',
  ),
  SouvenirItem(
    'au-koala',
    'Koala keepsake',
    '考拉小摆件',
    SouvenirKind.koala,
    'AU',
    '',
  ),
  SouvenirItem(
    'cn-shanghai',
    'Shanghai skyline scroll',
    '上海天际线卷轴',
    SouvenirKind.orientalPearl,
    'CN',
    '',
  ),
  SouvenirItem(
    'cn-dumpling',
    'Little dumpling basket',
    '小笼包蒸笼',
    SouvenirKind.dumpling,
    'CN',
    '',
  ),
  SouvenirItem(
    'cn-shenzhen',
    'Shenzhen skyline postcard',
    '深圳天际线明信片',
    SouvenirKind.shenzhen,
    'CN',
    '',
  ),
  SouvenirItem(
    'cn-great-wall',
    'Great Wall sketch',
    '长城手绘图',
    SouvenirKind.greatWall,
    'CN',
    '',
  ),
  SouvenirItem(
    'cn-palace',
    'Beijing palace postcard',
    '北京宫殿明信片',
    SouvenirKind.palace,
    'CN',
    '',
  ),
  SouvenirItem(
    'cn-tea-scroll',
    'Tea journey scroll',
    '茶香旅行卷轴',
    SouvenirKind.teaScroll,
    'CN',
    '',
  ),
];

List<SouvenirItem> souvenirsForCountry(String? code) {
  final local = regionalSouvenirs
      .where((item) => item.destinationId == code?.toUpperCase())
      .toList(growable: false);
  return local.isNotEmpty
      ? local
      : souvenirItems
            .where((item) => item.destinationId.isEmpty)
            .toList(growable: false);
}

List<SouvenirItem> souvenirsForDestination(String id) => souvenirItems
    .where((item) => item.destinationId.isEmpty || item.destinationId == id)
    .toList(growable: false);

SouvenirItem souvenirForMemory(JourneyMemory memory) {
  for (final item in [...souvenirItems, ...regionalSouvenirs]) {
    if (item.id == memory.souvenirId ||
        item.legacyName == memory.souvenir ||
        item.name == memory.souvenir) {
      return item;
    }
  }
  return SouvenirItem(
    'legacy:${memory.souvenir}',
    memory.souvenir,
    memory.souvenir,
    SouvenirKind.keepsake,
    memory.destinationId,
    memory.souvenir,
  );
}
