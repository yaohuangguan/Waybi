import 'safety_camera.dart';

enum CameraKind {
  spotSpeed,
  averageSpeed,
  redLight,
  dualRedLightSpeed,
  busLane,
  other,
}

extension CameraKindLabel on CameraKind {
  String get label => switch (this) {
    CameraKind.spotSpeed => 'Spot speed',
    CameraKind.averageSpeed => 'Average speed',
    CameraKind.redLight => 'Red light',
    CameraKind.dualRedLightSpeed => 'Red light + speed',
    CameraKind.busLane => 'Bus / transit lane',
    CameraKind.other => 'Other',
  };

  String localizedLabel(String language) {
    if (language != 'zh') return label;
    return switch (this) {
      CameraKind.spotSpeed => '定点测速',
      CameraKind.averageSpeed => '区间测速',
      CameraKind.redLight => '闯红灯',
      CameraKind.dualRedLightSpeed => '闯红灯 + 测速',
      CameraKind.busLane => '公交 / 专用车道',
      CameraKind.other => '其他',
    };
  }

  static CameraKind fromCamera(SafetyCamera camera) => fromType(camera.type);

  static CameraKind fromType(String cameraType) {
    final type = cameraType.toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ');
    if (type.contains('average') ||
        type.contains('point to point') ||
        type.contains('p2p')) {
      return CameraKind.averageSpeed;
    }
    if (type.contains('red') && type.contains('speed')) {
      return CameraKind.dualRedLightSpeed;
    }
    if (type.contains('bus lane') ||
        type.contains('transit lane') ||
        type.contains('special vehicle lane') ||
        type.contains('svl')) {
      return CameraKind.busLane;
    }
    if (type.contains('red light') || type.contains('redlight')) {
      return CameraKind.redLight;
    }
    if (type.contains('spot speed') || type.contains('speed')) {
      return CameraKind.spotSpeed;
    }
    return CameraKind.other;
  }

  String cameraLabel(String language) => switch (this) {
    CameraKind.spotSpeed => language == 'zh' ? '定点测速摄像头' : 'Speed camera',
    CameraKind.averageSpeed =>
      language == 'zh' ? '区间测速摄像头' : 'Average-speed camera',
    CameraKind.redLight => language == 'zh' ? '闯红灯摄像头' : 'Red-light camera',
    CameraKind.dualRedLightSpeed =>
      language == 'zh' ? '闯红灯及测速摄像头' : 'Red-light + speed camera',
    CameraKind.busLane => language == 'zh' ? '专用车道摄像头' : 'Bus-lane camera',
    CameraKind.other => language == 'zh' ? '安全摄像头' : 'Safety camera',
  };
}

enum BaseMapStyle { standard, satellite, terrain, hybrid }

class MapLayerSettings {
  const MapLayerSettings({
    this.cameras = true,
    this.spotSpeed = true,
    this.averageSpeed = true,
    this.redLight = true,
    this.dualRedLightSpeed = true,
    this.busLane = true,
    this.other = true,
    this.alertSpotSpeed = true,
    this.alertAverageSpeed = true,
    this.alertRedLight = true,
    this.alertDualRedLightSpeed = true,
    this.alertBusLane = true,
    this.alertOther = false,
    this.traffic = true,
    this.roadEvents = true,
    this.style = BaseMapStyle.standard,
  });

  final bool cameras;
  final bool spotSpeed;
  final bool averageSpeed;
  final bool redLight;
  final bool dualRedLightSpeed;
  final bool busLane;
  final bool other;

  final bool alertSpotSpeed;
  final bool alertAverageSpeed;
  final bool alertRedLight;
  final bool alertDualRedLightSpeed;
  final bool alertBusLane;
  final bool alertOther;

  final bool traffic;
  final bool roadEvents;
  final BaseMapStyle style;

  bool shows(SafetyCamera camera) {
    if (!cameras) return false;
    return switch (CameraKindLabel.fromCamera(camera)) {
      CameraKind.spotSpeed => spotSpeed,
      CameraKind.averageSpeed => averageSpeed,
      CameraKind.redLight => redLight,
      CameraKind.dualRedLightSpeed => dualRedLightSpeed,
      CameraKind.busLane => busLane,
      CameraKind.other => other,
    };
  }

  bool alerts(SafetyCamera camera) =>
      switch (CameraKindLabel.fromCamera(camera)) {
        CameraKind.spotSpeed => alertSpotSpeed,
        CameraKind.averageSpeed => alertAverageSpeed,
        CameraKind.redLight => alertRedLight,
        CameraKind.dualRedLightSpeed => alertDualRedLightSpeed,
        CameraKind.busLane => alertBusLane,
        CameraKind.other => alertOther,
      };

  String get markerSignature =>
      '$cameras:$spotSpeed:$averageSpeed:$redLight:$dualRedLightSpeed:$busLane:$other';

  MapLayerSettings copyWith({
    bool? cameras,
    bool? spotSpeed,
    bool? averageSpeed,
    bool? redLight,
    bool? dualRedLightSpeed,
    bool? busLane,
    bool? other,
    bool? alertSpotSpeed,
    bool? alertAverageSpeed,
    bool? alertRedLight,
    bool? alertDualRedLightSpeed,
    bool? alertBusLane,
    bool? alertOther,
    bool? traffic,
    bool? roadEvents,
    BaseMapStyle? style,
  }) => MapLayerSettings(
    cameras: cameras ?? this.cameras,
    spotSpeed: spotSpeed ?? this.spotSpeed,
    averageSpeed: averageSpeed ?? this.averageSpeed,
    redLight: redLight ?? this.redLight,
    dualRedLightSpeed: dualRedLightSpeed ?? this.dualRedLightSpeed,
    busLane: busLane ?? this.busLane,
    other: other ?? this.other,
    alertSpotSpeed: alertSpotSpeed ?? this.alertSpotSpeed,
    alertAverageSpeed: alertAverageSpeed ?? this.alertAverageSpeed,
    alertRedLight: alertRedLight ?? this.alertRedLight,
    alertDualRedLightSpeed:
        alertDualRedLightSpeed ?? this.alertDualRedLightSpeed,
    alertBusLane: alertBusLane ?? this.alertBusLane,
    alertOther: alertOther ?? this.alertOther,
    traffic: traffic ?? this.traffic,
    roadEvents: roadEvents ?? this.roadEvents,
    style: style ?? this.style,
  );
}
