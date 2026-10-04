import 'dart:math';

import 'models.dart';
import 'souvenirs.dart';

const travelItems = <TravelItem>[
  TravelItem(
    id: 'camera',
    name: 'Tiny camera',
    emoji: '📷',
    note: 'Waybi notices the small things.',
  ),
  TravelItem(
    id: 'snack',
    name: 'Seed sandwich',
    emoji: '🥪',
    note: 'A journey is nicer with lunch.',
  ),
  TravelItem(
    id: 'umbrella',
    name: 'Yellow umbrella',
    emoji: '☂️',
    note: 'For weather that changes its mind.',
  ),
  TravelItem(
    id: 'toy',
    name: "Sett's ball",
    emoji: '🎾',
    note: 'Sett insists it brings luck.',
  ),
];

const destinations = <Destination>[
  Destination(
    id: 'mission_bay',
    name: 'Mission Bay',
    area: 'Auckland',
    emoji: '🌊',
    memory: 'a windy stretch of water and a bench warm from the afternoon sun',
    souvenirs: ['a tiny shell', 'a smooth sea-glass pebble', 'a sandy feather'],
  ),
  Destination(
    id: 'devonport',
    name: 'Devonport',
    area: 'Auckland',
    emoji: '⛴️',
    memory: 'a ferry wake, old villas, and a hill that made the whole city look small',
    souvenirs: [
      'a ferry ticket corner',
      'a little blue button',
      'a folded harbour map',
    ],
  ),
  Destination(
    id: 'cornwall_park',
    name: 'Cornwall Park',
    area: 'Auckland',
    emoji: '🌳',
    memory: 'long grass moving like waves while sheep watched from a polite distance',
    souvenirs: ['an acorn cap', 'a pressed clover leaf', 'a small fallen twig'],
  ),
  Destination(
    id: 'mt_eden',
    name: 'Maungawhau / Mt Eden',
    area: 'Auckland',
    emoji: '⛰️',
    memory:
        'a quiet crater, a big sky, and rooftops stretching in every direction',
    souvenirs: [
      'a sketch of the skyline',
      'a grey volcanic pebble',
      'a windswept leaf',
    ],
  ),
  Destination(
    id: 'takapuna',
    name: 'Takapuna Beach',
    area: 'Auckland',
    emoji: '🏖️',
    memory: 'bright water, dog footprints, and Rangitoto sitting patiently offshore',
    souvenirs: [
      'a striped shell',
      'a tiny driftwood stick',
      'a postcard stamp',
    ],
  ),
  Destination(
    id: 'waiheke',
    name: 'Waiheke Island',
    area: 'Hauraki Gulf',
    emoji: '🏝️',
    memory: 'a ferry ride, quiet coves, and roads curling between green hills',
    souvenirs: ['a ferry token', 'a dried flower', 'a little island map'],
  ),
  Destination(
    id: 'piha',
    name: 'Piha',
    area: 'Waitākere',
    emoji: '🌅',
    memory:
        'black sand, a roaring sea, and Lion Rock glowing just before evening',
    souvenirs: ['a black-sand vial', 'a fern tip', 'a smooth dark stone'],
  ),
];

const waybiHomeLines = <String>[
  'Waybi is watching the weather.',
  'Waybi keeps looking at the little backpack.',
  'Waybi drew a road that goes off the page.',
  'Waybi is wondering what is beyond the window.',
  'Waybi says there is always time for a small journey.',
];

const cloverLines = <String>[
  'Clover has claimed the warmest patch of sunlight.',
  'Clover is pretending not to watch Waybi pack.',
  'Clover found a box. The box belongs to Clover now.',
  'Clover moved to the windowsill without explanation.',
  'Clover is asleep on something important.',
  'Clover heard the rain first.',
];

const settLines = <String>[
  "Sett found a sock. Nobody knows whose sock it is.",
  'Sett has been waiting by the door for exactly twelve seconds.',
  "Sett thinks Waybi's backpack needs a tennis ball.",
  'Sett did one lap of the room for no reason.',
  'Sett is very sure dinner should happen early.',
  'Sett is guarding the rug from absolutely nothing.',
];

const awayLines = <String>[
  'Clover checked the window, then acted like it never happened.',
  'Sett is listening for tiny footsteps in the hallway.',
  'The house feels a little bigger when Waybi is away.',
  "Clover is sleeping on Waybi's side of the sofa.",
  'Sett brought a toy to the door and left it there.',
];

Destination destinationById(String id) =>
    destinations.firstWhere((destination) => destination.id == id);

TravelItem itemById(String id) =>
    travelItems.firstWhere((item) => item.id == id);

class JourneyEngine {
  JourneyEngine([Random? random]) : _random = random ?? Random();

  final Random _random;

  ActiveJourney start(List<String> itemIds, {DateTime? at}) {
    final destination = destinations[_random.nextInt(destinations.length)];
    final minutes = 2 + _random.nextInt(7);
    final now = at ?? DateTime.now();

    return ActiveJourney(
      destinationId: destination.id,
      departedAt: now,
      returnAt: now.add(Duration(minutes: minutes)),
      itemIds: List.unmodifiable(itemIds),
    );
  }

  JourneyMemory finish(ActiveJourney active, {DateTime? at}) {
    final returnedAt = at ?? DateTime.now();
    final destination = destinationById(active.destinationId);
    final packed = active.itemIds.map(itemById).toList();
    final hasCamera = active.itemIds.contains('camera');
    final hasSnack = active.itemIds.contains('snack');
    final hasUmbrella = active.itemIds.contains('umbrella');
    final hasToy = active.itemIds.contains('toy');

    final details = <String>[
      if (hasCamera)
        'Waybi stopped twice to take pictures of things nobody else noticed.',
      if (hasSnack) 'Lunch disappeared somewhere along the way.',
      if (hasUmbrella) 'It rained for a little while, which made the umbrella feel very clever.',
      if (hasToy) "Sett's ball came too. Waybi will not explain why.",
      if (packed.isEmpty)
        'Waybi left with almost nothing and somehow that felt right.',
    ];

    final ending = [
      'On the way home, Waybi took the long route.',
      'Waybi waited until the light changed before heading back.',
      'The trip was small, but it felt like a real adventure.',
      'Waybi came home tired in the good way.',
    ][_random.nextInt(4)];

    final choices = souvenirsForDestination(destination.id);
    final weighted = [
      ...choices,
      if (hasCamera)
        ...choices.where(
          (item) =>
              item.kind == SouvenirKind.map ||
              item.kind == SouvenirKind.scroll ||
              item.kind == SouvenirKind.stamp,
        ),
      if (hasSnack)
        ...choices.where(
          (item) =>
              item.kind == SouvenirKind.cookie || item.kind == SouvenirKind.bun,
        ),
    ];
    final souvenir = weighted[_random.nextInt(weighted.length)];

    return JourneyMemory(
      id: '${active.departedAt.microsecondsSinceEpoch}-${active.destinationId}',
      destinationId: destination.id,
      returnedAt: returnedAt,
      itemIds: active.itemIds,
      title: 'A little trip to ${destination.name}',
      story:
          'Today Waybi found ${destination.memory}. ${details[_random.nextInt(details.length)]} $ending',
      souvenir: souvenir.name,
      souvenirId: souvenir.id,
    );
  }

  String ambient({required bool waybiAway}) {
    final pool = waybiAway
        ? [...awayLines, ...cloverLines, ...settLines]
        : [...waybiHomeLines, ...cloverLines, ...settLines];
    return pool[_random.nextInt(pool.length)];
  }
}
