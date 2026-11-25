import 'dart:convert';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';

enum TransportModeCode(
  final String wireName,
  final String displayNameRu,
  final String shortLabelRu,
  final double defaultCo2GramsPerMeter,
) {
  bus('bus', 'Автобус / электробус', 'Автобус', 0.08200),
  metro('metro', 'Метро / МЦК / МЦД', 'Метро', 0.02800),
  tram('tram', 'Трамвай', 'Трамвай', 0.03500),
  personalCar('personal_car', 'Мой автомобиль', 'Мой авто', 0.19200),
  carCompact('car_compact', 'Авто (компакт B-класс)', 'Компакт', 0.14500),
  carSedan('car_sedan', 'Авто (седан C/D-класс)', 'Седан', 0.19200),
  carSuv('car_suv', 'Авто (кроссовер / SUV)', 'Кроссовер', 0.25500),
  carEv('car_ev', 'Электромобиль (РФ сеть)', 'Электро', 0.05800);

  int get co2GramsPerKmRounded => (defaultCo2GramsPerMeter * 1000).round();

  static TransportModeCode fromWire(String? raw) => switch (raw) {
    'bus' => .bus,
    'metro' => .metro,
    'tram' => .tram,
    'personal_car' => .personalCar,
    'car_compact' => .carCompact,
    'car_sedan' => .carSedan,
    'car_suv' => .carSuv,
    'car_ev' => .carEv,
    _ => .bus,
  };
}

enum TrackPointMotionClass(final String wireName) {
  unknown('unknown'),
  walking('walking'),
  indoorPacing('indoor_pacing'),
  vehicleSuspected('vehicle_suspected'),
  stationary('stationary');

  static TrackPointMotionClass fromWire(String? raw) => switch (raw) {
    'walking' => .walking,
    'indoor_pacing' => .indoorPacing,
    'vehicle_suspected' => .vehicleSuspected,
    'stationary' => .stationary,
    _ => .unknown,
  };
}

enum WasteFractionCode(final String wireName, final String labelRu) {
  plastic('plastic', 'Пластик'),
  glass('glass', 'Стекло'),
  paper('paper', 'Бумага'),
  metal('metal', 'Металл'),
  tetraPak('tetra_pak', 'Тетрапак'),
  batteries('batteries', 'Батарейки'),
  electronics('electronics', 'Электроника'),
  clothes('clothes', 'Одежда'),
  hazardous('hazardous', 'Опасные'),
  caps('caps', 'Крышечки'),
  mixedRecyclables('mixed_recyclables', 'Фандоматы'),
  generalBin('general_bin', 'Урны');

  static WasteFractionCode? tryFromWire(String? raw) => switch (raw) {
    'plastic' => .plastic,
    'glass' => .glass,
    'paper' => .paper,
    'metal' => .metal,
    'tetra_pak' => .tetraPak,
    'batteries' => .batteries,
    'electronics' => .electronics,
    'clothes' => .clothes,
    'hazardous' => .hazardous,
    'caps' => .caps,
    'mixed_recyclables' => .mixedRecyclables,
    'general_bin' => .generalBin,
    _ => null,
  };

  static WasteFractionCode fromWire(String? raw) =>
      tryFromWire(raw) ?? .generalBin;
}

enum WastePointStatus(final String wireName, final String labelRu) {
  active('active', 'Работает'),
  unverified('unverified', 'Не проверено'),
  temporarilyClosed('temporarily_closed', 'Временно закрыт'),
  removed('removed', 'Удалён');

  static WastePointStatus fromWire(String? raw) => switch (raw) {
    'active' => .active,
    'unverified' => .unverified,
    'temporarily_closed' => .temporarilyClosed,
    'removed' => .removed,
    _ => .unverified,
  };
}

enum ReportType(
  final String wireName,
  final String labelRu,
  final double trustDelta,
) {
  confirmWorking('confirm_working', '✓ Работает', 10.0),
  overflowing('overflowing', '⚠ Переполнен', -8.0),
  missingBin('missing_bin', '✕ Закрыт / Нет бака', -25.0),
  wrongFractions('wrong_fractions', '≠ Неверные фракции', -15.0),
  inaccessible('inaccessible', 'Нет доступа', -12.0),
  photoUpdate('photo_update', 'Обновить фото', 5.0);

  static ReportType fromWire(String? raw) => switch (raw) {
    'confirm_working' => .confirmWorking,
    'overflowing' => .overflowing,
    'missing_bin' => .missingBin,
    'wrong_fractions' => .wrongFractions,
    'inaccessible' => .inaccessible,
    'photo_update' => .photoUpdate,
    _ => .confirmWorking,
  };
}

int _readInt(Object? raw, [int fallback = 0]) => switch (raw) {
  final int v => v,
  final num v => v.toInt(),
  _ => fallback,
};

double _readDouble(Object? raw, [double fallback = 0.0]) => switch (raw) {
  final double v => v,
  final num v => v.toDouble(),
  _ => fallback,
};

bool _readBool(Object? raw, [bool fallback = false]) => switch (raw) {
  final bool v => v,
  final num v => v.toInt() != 0,
  _ => fallback,
};

List<WasteFractionCode> _parseFractions(Object? raw) => switch (raw) {
  final List<Object?> items =>
    items
        .whereType<String>()
        .map(WasteFractionCode.tryFromWire)
        .whereType<WasteFractionCode>()
        .toList(),
  final String csv =>
    csv
        .split(',')
        .map((s) => WasteFractionCode.tryFromWire(s.trim()))
        .whereType<WasteFractionCode>()
        .toList(),
  _ => const <WasteFractionCode>[],
};

List<T> _parseList<T>(
  Object? raw,
  Result<T, AppError> Function(Map<String, Object?>) parser,
) {
  if (raw is! List<Object?>) return <T>[];
  final out = <T>[];
  for (final item in raw) {
    if (item is Map<String, Object?>) {
      final value = parser(item).valueOrNull;
      if (value != null) out.add(value);
    }
  }
  return out;
}

final class const LatLonPair({
  required final double lat,
  required final double lon,
}) {
  static Result<LatLonPair, AppError> fromJson(Map<String, Object?> json) =>
      switch (json) {
        {'lat': final num lat, 'lon': final num lon} => Ok(
          LatLonPair(lat: lat.toDouble(), lon: lon.toDouble()),
        ),
        _ => Err(AppError.fromCode('VALIDATION_ERROR')),
      };

  Map<String, Object?> toJson() => <String, Object?>{'lat': lat, 'lon': lon};
}

final class const DailyActivitySummary({
  required final String id,
  required final String activityDate,
  required final int rawSensorSteps,
  required final int validatedSteps,
  required final int strideLengthCm,
  required final double totalStepDistanceM,
  required final double allocatedGpsDistanceM,
  required final double unallocatedStepDistanceM,
  required final int allocatedCo2SavedGrams,
  required final int autoDefaultCo2SavedGrams,
  required final int totalCo2SavedGrams,
  required final int pointsAwardedForDay,
  required final int pointsDeltaApplied,
  required final int pointsBalance,
  required final bool isAutoCalculated,
  required final bool antifraudFlagged,
  final String? antifraudReason,
  final String? lastSyncedAt,
}) {
  factory emptyForDate(
    String activityDate, {
    int strideLengthCm = 74,
    int pointsBalance = 0,
  }) => DailyActivitySummary(
    id: 'local-$activityDate',
    activityDate: activityDate,
    rawSensorSteps: 0,
    validatedSteps: 0,
    strideLengthCm: strideLengthCm,
    totalStepDistanceM: 0.0,
    allocatedGpsDistanceM: 0.0,
    unallocatedStepDistanceM: 0.0,
    allocatedCo2SavedGrams: 0,
    autoDefaultCo2SavedGrams: 0,
    totalCo2SavedGrams: 0,
    pointsAwardedForDay: 0,
    pointsDeltaApplied: 0,
    pointsBalance: pointsBalance,
    isAutoCalculated: true,
    antifraudFlagged: false,
  );

  static Result<DailyActivitySummary, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final id = json['id'];
    final date = json['activity_date'];
    if (id is! String || date is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      DailyActivitySummary(
        id: id,
        activityDate: date,
        rawSensorSteps: _readInt(json['raw_sensor_steps']),
        validatedSteps: _readInt(json['validated_steps']),
        strideLengthCm: _readInt(json['stride_length_cm'], 74),
        totalStepDistanceM: _readDouble(json['total_step_distance_m']),
        allocatedGpsDistanceM: _readDouble(json['allocated_gps_distance_m']),
        unallocatedStepDistanceM: _readDouble(
          json['unallocated_step_distance_m'],
        ),
        allocatedCo2SavedGrams: _readInt(json['allocated_co2_saved_grams']),
        autoDefaultCo2SavedGrams: _readInt(
          json['auto_default_co2_saved_grams'],
        ),
        totalCo2SavedGrams: _readInt(json['total_co2_saved_grams']),
        pointsAwardedForDay: _readInt(json['points_awarded_for_day']),
        pointsDeltaApplied: _readInt(json['points_delta_applied']),
        pointsBalance: _readInt(json['points_balance']),
        isAutoCalculated: _readBool(json['is_auto_calculated'], true),
        antifraudFlagged: _readBool(json['antifraud_flagged']),
        antifraudReason: json['antifraud_reason'] as String?,
        lastSyncedAt: json['last_synced_at'] as String?,
      ),
    );
  }

  static Result<DailyActivitySummary, AppError> fromSqliteRow(
    Map<String, Object?> row, {
    int pointsBalance = 0,
  }) {
    final date = row['activity_date'];
    if (date is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final syncedMs = row['last_synced_at_ms'];
    final syncedIso = syncedMs is int
        ? DateTime.fromMillisecondsSinceEpoch(
            syncedMs,
            isUtc: true,
          ).toIso8601String()
        : null;
    return Ok(
      DailyActivitySummary(
        id: 'local-$date',
        activityDate: date,
        rawSensorSteps: _readInt(row['raw_sensor_steps']),
        validatedSteps: _readInt(row['validated_steps']),
        strideLengthCm: _readInt(row['stride_length_cm'], 74),
        totalStepDistanceM: _readDouble(row['total_step_distance_m']),
        allocatedGpsDistanceM: _readDouble(row['allocated_gps_distance_m']),
        unallocatedStepDistanceM: _readDouble(
          row['unallocated_step_distance_m'],
        ),
        allocatedCo2SavedGrams: _readInt(row['allocated_co2_saved_grams']),
        autoDefaultCo2SavedGrams: _readInt(row['auto_default_co2_saved_grams']),
        totalCo2SavedGrams: _readInt(row['total_co2_saved_grams']),
        pointsAwardedForDay: _readInt(row['points_awarded_for_day']),
        pointsDeltaApplied: 0,
        pointsBalance: pointsBalance,
        isAutoCalculated: _readBool(row['is_auto_calculated'], true),
        antifraudFlagged: false,
        lastSyncedAt: syncedIso,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'activity_date': activityDate,
    'raw_sensor_steps': rawSensorSteps,
    'validated_steps': validatedSteps,
    'stride_length_cm': strideLengthCm,
    'total_step_distance_m': totalStepDistanceM,
    'allocated_gps_distance_m': allocatedGpsDistanceM,
    'unallocated_step_distance_m': unallocatedStepDistanceM,
    'allocated_co2_saved_grams': allocatedCo2SavedGrams,
    'auto_default_co2_saved_grams': autoDefaultCo2SavedGrams,
    'total_co2_saved_grams': totalCo2SavedGrams,
    'points_awarded_for_day': pointsAwardedForDay,
    'points_delta_applied': pointsDeltaApplied,
    'points_balance': pointsBalance,
    'is_auto_calculated': isAutoCalculated,
    'antifraud_flagged': antifraudFlagged,
    if (antifraudReason != null) 'antifraud_reason': antifraudReason,
    if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
  };
}

final class const GpsTrackPointClassified({
  required final int seqNo,
  required final String recordedAt,
  required final double lat,
  required final double lon,
  required final double accuracyM,
  required final double speedMps,
  required final int cumulativeSteps,
  required final int deltaSteps,
  required final double deltaDistanceM,
  required final TrackPointMotionClass motionClass,
}) {
  static Result<GpsTrackPointClassified, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final recordedAt = json['recorded_at'];
    if (recordedAt is! String ||
        json['seq_no'] is! num ||
        json['lat'] is! num ||
        json['lon'] is! num) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      GpsTrackPointClassified(
        seqNo: _readInt(json['seq_no']),
        recordedAt: recordedAt,
        lat: _readDouble(json['lat']),
        lon: _readDouble(json['lon']),
        accuracyM: _readDouble(json['accuracy_m']),
        speedMps: _readDouble(json['speed_mps']),
        cumulativeSteps: _readInt(json['cumulative_steps']),
        deltaSteps: _readInt(json['delta_steps']),
        deltaDistanceM: _readDouble(json['delta_distance_m']),
        motionClass: TrackPointMotionClass.fromWire(
          json['motion_class'] as String?,
        ),
      ),
    );
  }

  static Result<GpsTrackPointClassified, AppError> fromSqliteRow(
    Map<String, Object?> row,
  ) {
    final ms = row['recorded_at_ms'];
    if (ms is! int || row['seq_no'] is! num) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final recordedAtIso = DateTime.fromMillisecondsSinceEpoch(
      ms,
      isUtc: true,
    ).toIso8601String();
    return Ok(
      GpsTrackPointClassified(
        seqNo: _readInt(row['seq_no']),
        recordedAt: recordedAtIso,
        lat: _readDouble(row['lat']),
        lon: _readDouble(row['lon']),
        accuracyM: _readDouble(row['accuracy_m']),
        speedMps: _readDouble(row['speed_mps']),
        cumulativeSteps: _readInt(row['cumulative_steps']),
        deltaSteps: _readInt(row['delta_steps']),
        deltaDistanceM: _readDouble(row['delta_distance_m']),
        motionClass: TrackPointMotionClass.fromWire(
          row['motion_class'] as String?,
        ),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'seq_no': seqNo,
    'recorded_at': recordedAt,
    'lat': lat,
    'lon': lon,
    'accuracy_m': accuracyM,
    'speed_mps': speedMps,
    'cumulative_steps': cumulativeSteps,
    'delta_steps': deltaSteps,
    'delta_distance_m': deltaDistanceM,
    'motion_class': motionClass.wireName,
  };
}

final class const RouteSegmentAllocationItem({
  required final String id,
  required final String idempotencyKey,
  required final int startSeqNo,
  required final int endSeqNo,
  required final double segmentDistanceM,
  required final int segmentSteps,
  required final TransportModeCode replacedTransportMode,
  required final double appliedCo2GPerMeter,
  required final double confidenceFactor,
  required final bool isAutoCalculated,
  required final int co2SavedGrams,
  required final List<LatLonPair> coordinates,
}) {
  static Result<RouteSegmentAllocationItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final id = json['id'];
    final key = json['idempotency_key'];
    final rawCoords = json['coordinates'];
    if (id is! String || key is! String || rawCoords is! List<Object?>) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      RouteSegmentAllocationItem(
        id: id,
        idempotencyKey: key,
        startSeqNo: _readInt(json['start_seq_no']),
        endSeqNo: _readInt(json['end_seq_no']),
        segmentDistanceM: _readDouble(json['segment_distance_m']),
        segmentSteps: _readInt(json['segment_steps']),
        replacedTransportMode: TransportModeCode.fromWire(
          json['replaced_transport_mode'] as String?,
        ),
        appliedCo2GPerMeter: _readDouble(json['applied_co2_g_per_meter']),
        confidenceFactor: _readDouble(json['confidence_factor'], 1.0),
        isAutoCalculated: _readBool(json['is_auto_calculated']),
        co2SavedGrams: _readInt(json['co2_saved_grams']),
        coordinates: _decodeCoordinateMaps(rawCoords),
      ),
    );
  }

  static Result<RouteSegmentAllocationItem, AppError> fromSqliteRow(
    Map<String, Object?> row,
  ) {
    final id = row['id'];
    final key = row['idempotency_key'];
    final polyRaw = row['polyline_json'];
    if (id is! String || key is! String || polyRaw is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      RouteSegmentAllocationItem(
        id: id,
        idempotencyKey: key,
        startSeqNo: _readInt(row['start_seq_no']),
        endSeqNo: _readInt(row['end_seq_no']),
        segmentDistanceM: _readDouble(row['segment_distance_m']),
        segmentSteps: _readInt(row['segment_steps']),
        replacedTransportMode: TransportModeCode.fromWire(
          row['replaced_transport_mode'] as String?,
        ),
        appliedCo2GPerMeter: _readDouble(row['applied_co2_g_per_meter']),
        confidenceFactor: _readDouble(row['confidence_factor'], 1.0),
        isAutoCalculated: _readBool(row['is_auto_calculated']),
        co2SavedGrams: _readInt(row['co2_saved_grams']),
        coordinates: _decodeSqlitePolyline(polyRaw),
      ),
    );
  }

  static List<LatLonPair> _decodeCoordinateMaps(List<Object?> raw) {
    final out = <LatLonPair>[];
    for (final item in raw) {
      if (item is Map<String, Object?>) {
        final pair = LatLonPair.fromJson(item).valueOrNull;
        if (pair != null) out.add(pair);
      }
    }
    return out;
  }

  static List<LatLonPair> _decodeSqlitePolyline(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return const <LatLonPair>[];
      final out = <LatLonPair>[];
      for (final item in decoded) {
        if (item case [final num lat, final num lon]) {
          out.add(LatLonPair(lat: lat.toDouble(), lon: lon.toDouble()));
        } else if (item is Map<String, Object?>) {
          final pair = LatLonPair.fromJson(item).valueOrNull;
          if (pair != null) out.add(pair);
        }
      }
      return out;
    } on FormatException {
      return const <LatLonPair>[];
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'idempotency_key': idempotencyKey,
    'start_seq_no': startSeqNo,
    'end_seq_no': endSeqNo,
    'segment_distance_m': segmentDistanceM,
    'segment_steps': segmentSteps,
    'replaced_transport_mode': replacedTransportMode.wireName,
    'applied_co2_g_per_meter': appliedCo2GPerMeter,
    'confidence_factor': confidenceFactor,
    'is_auto_calculated': isAutoCalculated,
    'co2_saved_grams': co2SavedGrams,
    'coordinates': coordinates.map((c) => c.toJson()).toList(),
  };
}

final class const RouteSegmentAllocationInput({
  required final String idempotencyKey,
  required final int startSeqNo,
  required final int endSeqNo,
  required final TransportModeCode replacedTransportMode,
}) {
  static Result<RouteSegmentAllocationInput, AppError> fromJson(
    Map<String, Object?> json,
  ) => switch (json) {
    {
      'idempotency_key': final String key,
      'start_seq_no': final num startSeq,
      'end_seq_no': final num endSeq,
      'replaced_transport_mode': final String mode,
    } =>
      Ok(
        RouteSegmentAllocationInput(
          idempotencyKey: key,
          startSeqNo: startSeq.toInt(),
          endSeqNo: endSeq.toInt(),
          replacedTransportMode: TransportModeCode.fromWire(mode),
        ),
      ),
    _ => Err(AppError.fromCode('VALIDATION_ERROR')),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'idempotency_key': idempotencyKey,
    'start_seq_no': startSeqNo,
    'end_seq_no': endSeqNo,
    'replaced_transport_mode': replacedTransportMode.wireName,
  };
}

final class const DailyActivityDetail({
  required final DailyActivitySummary summary,
  required final bool isEditable,
  required final double totalGpsWalkingDistanceM,
  required final List<GpsTrackPointClassified> trackPoints,
  required final List<RouteSegmentAllocationItem> allocations,
  required final int co2DeltaAppliedGrams,
}) {
  static Result<DailyActivityDetail, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final summaryRaw = json['summary'];
    if (summaryRaw is! Map<String, Object?>) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final summaryRes = DailyActivitySummary.fromJson(summaryRaw);
    final summary = summaryRes.valueOrNull;
    if (summary == null) {
      return Err(
        summaryRes.errorOrNull ?? AppError.fromCode('VALIDATION_ERROR'),
      );
    }
    return Ok(
      DailyActivityDetail(
        summary: summary,
        isEditable: _readBool(json['is_editable']),
        totalGpsWalkingDistanceM: _readDouble(
          json['total_gps_walking_distance_m'],
        ),
        trackPoints: _parseList(
          json['track_points'],
          GpsTrackPointClassified.fromJson,
        ),
        allocations: _parseList(
          json['allocations'],
          RouteSegmentAllocationItem.fromJson,
        ),
        co2DeltaAppliedGrams: _readInt(json['co2_delta_applied_grams']),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'summary': summary.toJson(),
    'is_editable': isEditable,
    'total_gps_walking_distance_m': totalGpsWalkingDistanceM,
    'track_points': trackPoints.map((p) => p.toJson()).toList(),
    'allocations': allocations.map((a) => a.toJson()).toList(),
    'co2_delta_applied_grams': co2DeltaAppliedGrams,
  };
}

final class const WastePointMapItem({
  required final String id,
  required final String title,
  final String? addressText,
  required final List<WasteFractionCode> acceptedFractions,
  required final double lat,
  required final double lon,
  required final WastePointStatus status,
  required final double trustScore,
  required final int confirmationsCount,
  required final int issuesCount,
}) {
  static Result<WastePointMapItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String ||
        title is! String ||
        json['lat'] is! num ||
        json['lon'] is! num) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      WastePointMapItem(
        id: id,
        title: title,
        addressText: json['address_text'] as String?,
        acceptedFractions: _parseFractions(json['accepted_fractions']),
        lat: _readDouble(json['lat']),
        lon: _readDouble(json['lon']),
        status: WastePointStatus.fromWire(json['status'] as String?),
        trustScore: _readDouble(json['trust_score'], 50.0),
        confirmationsCount: _readInt(json['confirmations_count']),
        issuesCount: _readInt(json['issues_count']),
      ),
    );
  }

  static Result<WastePointMapItem, AppError> fromSqliteRow(
    Map<String, Object?> row,
  ) {
    final id = row['id'];
    final title = row['title'];
    if (id is! String ||
        title is! String ||
        row['lat'] is! num ||
        row['lon'] is! num) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      WastePointMapItem(
        id: id,
        title: title,
        addressText: row['address_text'] as String?,
        acceptedFractions: _parseFractions(row['accepted_fractions_csv']),
        lat: _readDouble(row['lat']),
        lon: _readDouble(row['lon']),
        status: WastePointStatus.fromWire(row['status'] as String?),
        trustScore: _readDouble(row['trust_score'], 50.0),
        confirmationsCount: _readInt(row['confirmations_count']),
        issuesCount: _readInt(row['issues_count']),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (addressText != null) 'address_text': addressText,
    'accepted_fractions': acceptedFractions.map((f) => f.wireName).toList(),
    'lat': lat,
    'lon': lon,
    'status': status.wireName,
    'trust_score': trustScore,
    'confirmations_count': confirmationsCount,
    'issues_count': issuesCount,
  };
}

final class const WastePointsBboxResponse({
  required final String attributionBannerRu,
  required final int totalReturned,
  required final List<WastePointMapItem> points,
}) {
  static const String defaultAttributionBannerRu =
      '© Участники OpenStreetMap (ODbL 1.0) · data.mos.ru · Муниципальные реестры';

  static Result<WastePointsBboxResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final rawPoints = json['points'];
    if (rawPoints is! List<Object?>) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final points = _parseList(rawPoints, WastePointMapItem.fromJson);
    return Ok(
      WastePointsBboxResponse(
        attributionBannerRu:
            json['attribution_banner_ru'] as String? ??
            defaultAttributionBannerRu,
        totalReturned: _readInt(json['total_returned'], points.length),
        points: points,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'attribution_banner_ru': attributionBannerRu,
    'total_returned': totalReturned,
    'points': points.map((p) => p.toJson()).toList(),
  };
}

final class const LinkedSourceRecordItem({
  required final String sourceRecordId,
  required final String sourceType,
  required final String externalRecordId,
  required final String licenseName,
  required final double matchDistanceM,
}) {
  static Result<LinkedSourceRecordItem, AppError> fromJson(
    Map<String, Object?> json,
  ) => switch (json) {
    {
      'source_record_id': final String id,
      'source_type': final String type,
      'external_record_id': final String extId,
      'license_name': final String license,
      'match_distance_m': final num dist,
    } =>
      Ok(
        LinkedSourceRecordItem(
          sourceRecordId: id,
          sourceType: type,
          externalRecordId: extId,
          licenseName: license,
          matchDistanceM: dist.toDouble(),
        ),
      ),
    _ => Err(AppError.fromCode('VALIDATION_ERROR')),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'source_record_id': sourceRecordId,
    'source_type': sourceType,
    'external_record_id': externalRecordId,
    'license_name': licenseName,
    'match_distance_m': matchDistanceM,
  };
}

final class const WastePointReportItem({
  required final String id,
  required final ReportType reportType,
  final String? comment,
  required final double distanceToPointM,
  required final double trustDelta,
  required final String createdAt,
}) {
  static Result<WastePointReportItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final id = json['id'];
    final createdAt = json['created_at'];
    if (id is! String || createdAt is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      WastePointReportItem(
        id: id,
        reportType: ReportType.fromWire(json['report_type'] as String?),
        comment: json['comment'] as String?,
        distanceToPointM: _readDouble(json['distance_to_point_m']),
        trustDelta: _readDouble(json['trust_delta']),
        createdAt: createdAt,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'report_type': reportType.wireName,
    if (comment != null) 'comment': comment,
    'distance_to_point_m': distanceToPointM,
    'trust_delta': trustDelta,
    'created_at': createdAt,
  };
}

final class const WastePointDetail({
  required final String id,
  required final String title,
  final String? addressText,
  final String? operatorName,
  final String? openingHours,
  required final List<WasteFractionCode> acceptedFractions,
  required final double lat,
  required final double lon,
  required final WastePointStatus status,
  required final double trustScore,
  required final int confirmationsCount,
  required final int issuesCount,
  required final String attributionText,
  final String? lastVerifiedAt,
  required final List<LinkedSourceRecordItem> sources,
  required final List<WastePointReportItem> recentReports,
  required final String updatedAt,
}) {
  static Result<WastePointDetail, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      WastePointDetail(
        id: id,
        title: title,
        addressText: json['address_text'] as String?,
        operatorName: json['operator_name'] as String?,
        openingHours: json['opening_hours'] as String?,
        acceptedFractions: _parseFractions(json['accepted_fractions']),
        lat: _readDouble(json['lat']),
        lon: _readDouble(json['lon']),
        status: WastePointStatus.fromWire(json['status'] as String?),
        trustScore: _readDouble(json['trust_score'], 50.0),
        confirmationsCount: _readInt(json['confirmations_count']),
        issuesCount: _readInt(json['issues_count']),
        attributionText:
            json['attribution_text'] as String? ??
            WastePointsBboxResponse.defaultAttributionBannerRu,
        lastVerifiedAt: json['last_verified_at'] as String?,
        sources: _parseList(json['sources'], LinkedSourceRecordItem.fromJson),
        recentReports: _parseList(
          json['recent_reports'],
          WastePointReportItem.fromJson,
        ),
        updatedAt: json['updated_at'] as String? ?? '',
      ),
    );
  }

  static Result<WastePointDetail, AppError> fromSqliteRow(
    Map<String, Object?> row,
  ) {
    final id = row['id'];
    final title = row['title'];
    if (id is! String || title is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final verifiedMs = row['last_verified_at_ms'];
    final cachedMs = _readInt(row['cached_at_ms']);
    return Ok(
      WastePointDetail(
        id: id,
        title: title,
        addressText: row['address_text'] as String?,
        operatorName: row['operator_name'] as String?,
        openingHours: row['opening_hours'] as String?,
        acceptedFractions: _parseFractions(row['accepted_fractions_csv']),
        lat: _readDouble(row['lat']),
        lon: _readDouble(row['lon']),
        status: WastePointStatus.fromWire(row['status'] as String?),
        trustScore: _readDouble(row['trust_score'], 50.0),
        confirmationsCount: _readInt(row['confirmations_count']),
        issuesCount: _readInt(row['issues_count']),
        attributionText:
            row['attribution_text'] as String? ??
            WastePointsBboxResponse.defaultAttributionBannerRu,
        lastVerifiedAt: verifiedMs is int
            ? DateTime.fromMillisecondsSinceEpoch(
                verifiedMs,
                isUtc: true,
              ).toIso8601String()
            : null,
        sources: const <LinkedSourceRecordItem>[],
        recentReports: const <WastePointReportItem>[],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          cachedMs,
          isUtc: true,
        ).toIso8601String(),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    if (addressText != null) 'address_text': addressText,
    if (operatorName != null) 'operator_name': operatorName,
    if (openingHours != null) 'opening_hours': openingHours,
    'accepted_fractions': acceptedFractions.map((f) => f.wireName).toList(),
    'lat': lat,
    'lon': lon,
    'status': status.wireName,
    'trust_score': trustScore,
    'confirmations_count': confirmationsCount,
    'issues_count': issuesCount,
    'attribution_text': attributionText,
    if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
    'sources': sources.map((s) => s.toJson()).toList(),
    'recent_reports': recentReports.map((r) => r.toJson()).toList(),
    'updated_at': updatedAt,
  };
}

final class const WastePointReportCreatedResponse({
  required final WastePointReportItem report,
  required final double updatedTrustScore,
  required final WastePointStatus updatedStatus,
  required final int pointsRewarded,
}) {
  static Result<WastePointReportCreatedResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final reportRaw = json['report'];
    if (reportRaw is! Map<String, Object?>) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final reportRes = WastePointReportItem.fromJson(reportRaw);
    final report = reportRes.valueOrNull;
    if (report == null) {
      return Err(
        reportRes.errorOrNull ?? AppError.fromCode('VALIDATION_ERROR'),
      );
    }
    return Ok(
      WastePointReportCreatedResponse(
        report: report,
        updatedTrustScore: _readDouble(json['updated_trust_score']),
        updatedStatus: WastePointStatus.fromWire(
          json['updated_status'] as String?,
        ),
        pointsRewarded: _readInt(json['points_rewarded']),
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'report': report.toJson(),
    'updated_trust_score': updatedTrustScore,
    'updated_status': updatedStatus.wireName,
    'points_rewarded': pointsRewarded,
  };
}

final class const SuggestWastePointRequest({
  required final String title,
  final String? addressText,
  final String? operatorName,
  final String? openingHours,
  required final List<WasteFractionCode> acceptedFractions,
  required final double lat,
  required final double lon,
  final String? comment,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    if (addressText case final String v when v.isNotEmpty) 'address_text': v,
    if (operatorName case final String v when v.isNotEmpty) 'operator_name': v,
    if (openingHours case final String v when v.isNotEmpty) 'opening_hours': v,
    'accepted_fractions': acceptedFractions.map((f) => f.wireName).toList(),
    'lat': lat,
    'lon': lon,
    if (comment case final String v when v.isNotEmpty) 'comment': v,
  };
}

abstract interface class MapActivityRepository() {
  Stream<DailyActivitySummary> watchDailySummary(String activityDate);
  Future<Result<DailyActivitySummary, AppError>> getTodaySummary();
  Future<Result<DailyActivitySummary, AppError>> syncDailySteps({
    required String activityDate,
    required int rawSensorSteps,
    bool manualRefresh = false,
  });
  Future<Result<DailyActivityDetail, AppError>> getDailyActivityDetail(
    String activityDate,
  );
  Future<Result<DailyActivityDetail, AppError>> saveRouteAllocations({
    required String activityDate,
    required List<RouteSegmentAllocationInput> allocations,
  });
  Future<Result<DailyActivityDetail, AppError>> deleteRouteAllocation({
    required String activityDate,
    required String allocationId,
  });
  Future<Result<WastePointsBboxResponse, AppError>> queryWastePoints({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    required int zoom,
    List<WasteFractionCode> fractions = const <WasteFractionCode>[],
  });
  Future<Result<WastePointDetail, AppError>> getWastePointDetail(
    String pointId,
  );
  Future<Result<WastePointReportCreatedResponse, AppError>>
  submitWastePointReport({
    required String pointId,
    required ReportType reportType,
    String? comment,
    required double userLat,
    required double userLon,
  });
  Future<Result<WastePointDetail, AppError>> suggestWastePoint(
    SuggestWastePointRequest req,
  );
  Future<void> setGpsTrackingEnabled(bool enabled, {int? intervalSeconds});
  Stream<({double lat, double lon, double accuracy})> get currentPositionStream;
  Future<({double lat, double lon, double accuracy})?>
  getLastKnownOrCurrentPosition();
}
