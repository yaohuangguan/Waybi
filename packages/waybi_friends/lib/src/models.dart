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
  });

  final String destinationId;
  final DateTime departedAt;
  final DateTime returnAt;
  final List<String> itemIds;

  Map<String, dynamic> toJson() => {
    'destinationId': destinationId,
    'departedAt': departedAt.toIso8601String(),
    'returnAt': returnAt.toIso8601String(),
    'itemIds': itemIds,
  };

  factory ActiveJourney.fromJson(Map<String, dynamic> json) => ActiveJourney(
    destinationId: json['destinationId'] as String,
    departedAt: DateTime.parse(json['departedAt'] as String),
    returnAt: DateTime.parse(json['returnAt'] as String),
    itemIds: List<String>.from(json['itemIds'] as List? ?? const []),
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
  });

  final String id;
  final String destinationId;
  final DateTime returnedAt;
  final List<String> itemIds;
  final String title;
  final String story;
  final String souvenir;
  final String? souvenirId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'destinationId': destinationId,
    'returnedAt': returnedAt.toIso8601String(),
    'itemIds': itemIds,
    'title': title,
    'story': story,
    'souvenir': souvenir,
    'souvenirId': souvenirId,
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
