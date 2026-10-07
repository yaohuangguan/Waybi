import 'dart:convert';

import 'room_life.dart';

class TravelItem {
  const TravelItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.note,
  });

  final String id;
  final String name;
  final String emoji;
  final String note;
}

class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.area,
    required this.emoji,
    required this.memory,
    required this.souvenirs,
  });

  final String id;
  final String name;
  final String area;
  final String emoji;
  final String memory;
  final List<String> souvenirs;
}

class ActiveJourney {
  const ActiveJourney({
    required this.destinationId,
    required this.departedAt,
    required this.returnAt,
    required this.itemIds,
    this.traveller = FriendKind.waybi,
  });

  final String destinationId;
  final DateTime departedAt;
  final DateTime returnAt;
  final List<String> itemIds;
  final FriendKind traveller;

  Map<String, dynamic> toJson() => {
    'destinationId': destinationId,
    'departedAt': departedAt.toIso8601String(),
    'returnAt': returnAt.toIso8601String(),
    'itemIds': itemIds,
    'traveller': traveller.name,
  };

  factory ActiveJourney.fromJson(Map<String, dynamic> json) => ActiveJourney(
    destinationId: json['destinationId'] as String,
    departedAt: DateTime.parse(json['departedAt'] as String),
    returnAt: DateTime.parse(json['returnAt'] as String),
    itemIds: List<String>.from(json['itemIds'] as List? ?? const []),
    traveller: FriendKind.values.firstWhere(
      (kind) => kind.name == json['traveller'],
      orElse: () => FriendKind.waybi,
    ),
  );
}

class JourneyMemory {
  const JourneyMemory({
    required this.id,
    required this.destinationId,
    required this.returnedAt,
    required this.itemIds,
    required this.title,
    required this.story,
    required this.souvenir,
    this.souvenirId,
    this.traveller = FriendKind.waybi,
    this.titleZh,
    this.storyZh,
    this.destinationName,
    this.countryCode,
    this.sourceTripId,
  });

  final String id;
  final String destinationId;
  final DateTime returnedAt;
  final List<String> itemIds;
  final String title;
  final String story;
  final String souvenir;
  final String? souvenirId;
  final FriendKind traveller;
  final String? titleZh, storyZh, destinationName, countryCode, sourceTripId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'destinationId': destinationId,
    'returnedAt': returnedAt.toIso8601String(),
    'itemIds': itemIds,
    'title': title,
    'story': story,
    'souvenir': souvenir,
    'souvenirId': souvenirId,
    'traveller': traveller.name,
    'titleZh': titleZh,
    'storyZh': storyZh,
    'destinationName': destinationName,
    'countryCode': countryCode,
    'sourceTripId': sourceTripId,
  };

  factory JourneyMemory.fromJson(Map<String, dynamic> json) => JourneyMemory(
    id: json['id'] as String,
    destinationId: json['destinationId'] as String,
    returnedAt: DateTime.parse(json['returnedAt'] as String),
    itemIds: List<String>.from(json['itemIds'] as List? ?? const []),
    title: json['title'] as String,
    story: json['story'] as String,
    souvenir: json['souvenir'] as String,
    souvenirId: json['souvenirId'] as String?,
    traveller: FriendKind.values.firstWhere(
      (kind) => kind.name == json['traveller'],
      orElse: () => FriendKind.waybi,
    ),
    titleZh: json['titleZh'] as String?,
    storyZh: json['storyZh'] as String?,
    destinationName: json['destinationName'] as String?,
    countryCode: json['countryCode'] as String?,
    sourceTripId: json['sourceTripId'] as String?,
  );
}

class SavedGame {
  const SavedGame({
    this.activeJourney,
    this.roomLife,
    this.memories = const [],
    this.selectedItemIds = const [],
  });

  final ActiveJourney? activeJourney;
  final RoomLife? roomLife;
  final List<JourneyMemory> memories;
  final List<String> selectedItemIds;

  /// Restore memories without replacing an outing or room already in progress.
  SavedGame mergeArchive(SavedGame archive) {
    final ids = <String>{};
    final tripIds = <String>{};
    final combined = <JourneyMemory>[];
    for (final memory in [...memories, ...archive.memories]) {
      if (ids.contains(memory.id) ||
          (memory.sourceTripId != null &&
              tripIds.contains(memory.sourceTripId))) {
        continue;
      }
      ids.add(memory.id);
      if (memory.sourceTripId != null) tripIds.add(memory.sourceTripId!);
      combined.add(memory);
    }
    combined.sort((a, b) => b.returnedAt.compareTo(a.returnedAt));
    return SavedGame(
      activeJourney: activeJourney ?? archive.activeJourney,
      roomLife: roomLife ?? archive.roomLife,
      memories: combined,
      selectedItemIds: selectedItemIds,
    );
  }

  SavedGame copyWith({
    ActiveJourney? activeJourney,
    RoomLife? roomLife,
    bool clearActiveJourney = false,
    List<JourneyMemory>? memories,
    List<String>? selectedItemIds,
  }) {
    return SavedGame(
      activeJourney: clearActiveJourney
          ? null
          : activeJourney ?? this.activeJourney,
      roomLife: roomLife ?? this.roomLife,
      memories: memories ?? this.memories,
      selectedItemIds: selectedItemIds ?? this.selectedItemIds,
    );
  }

  String encode() => jsonEncode({
    'activeJourney': activeJourney?.toJson(),
    'roomLife': roomLife?.toJson(),
    'memories': memories.map((e) => e.toJson()).toList(),
    'selectedItemIds': selectedItemIds,
  });

  factory SavedGame.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return SavedGame(
      roomLife: json['roomLife'] == null
          ? null
          : RoomLife.fromJson(
              Map<String, dynamic>.from(json['roomLife'] as Map),
            ),
      activeJourney: json['activeJourney'] == null
          ? null
          : ActiveJourney.fromJson(
              Map<String, dynamic>.from(json['activeJourney'] as Map),
            ),
      memories: (json['memories'] as List? ?? const [])
          .map(
            (e) => JourneyMemory.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      selectedItemIds: List<String>.from(
        json['selectedItemIds'] as List? ?? const [],
      ),
    );
  }
}
