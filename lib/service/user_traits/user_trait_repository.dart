import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:town_pass/service/user_traits/trait_aggregator.dart';
import 'package:town_pass/service/user_traits/user_trait.dart';

/// 使用者特徵的本機資料庫（SQLite，存在手機上，不上傳）。
///
/// 只存「觀察」（哪個特徵、可信度、來源、證據雜湊、時間），不存問句原文；
/// 綜合後的特徵由 [TraitAggregator] 即時計算，規則改了不需要搬資料。
class UserTraitRepository {
  UserTraitRepository._(this._db);

  static const String fileName = 'user_traits.db';
  static const String table = 'trait_observations';
  static const int schemaVersion = 1;

  /// 超過這麼久的觀察在開啟時刪除（衰減後也幾乎沒有權重了）。
  static const Duration retention = Duration(days: 365);

  final Database _db;

  static Future<UserTraitRepository>? _shared;

  /// App 共用的資料庫（第一次呼叫時開啟）。
  static Future<UserTraitRepository> shared() => _shared ??= () async {
        final String path = p.join(await getDatabasesPath(), fileName);
        return open(databaseFactory, path);
      }();

  /// 指定資料庫工廠與路徑開啟（測試用 sqflite_common_ffi 與 [inMemoryDatabasePath]）。
  static Future<UserTraitRepository> open(DatabaseFactory factory, String path, {DateTime? now}) async {
    final Database db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $table (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              dimension TEXT NOT NULL,
              value TEXT NOT NULL,
              confidence REAL NOT NULL,
              source TEXT NOT NULL,
              evidence_key TEXT NOT NULL,
              detail TEXT,
              model TEXT,
              observed_at INTEGER NOT NULL
            )''');
          await db.execute('CREATE INDEX idx_${table}_trait ON $table (dimension, value)');
          await db.execute('CREATE INDEX idx_${table}_time ON $table (observed_at)');
        },
      ),
    );
    final UserTraitRepository repository = UserTraitRepository._(db);
    await repository._prune(now ?? DateTime.now());
    return repository;
  }

  Future<void> add(Iterable<TraitObservation> observations) async {
    if (observations.isEmpty) return;
    final Batch batch = _db.batch();
    for (final TraitObservation observation in observations) {
      batch.insert(table, {
        'dimension': observation.dimension.name,
        'value': observation.value,
        'confidence': observation.confidence,
        'source': observation.source.name,
        'evidence_key': observation.evidenceKey,
        'detail': observation.detail,
        'model': observation.model,
        'observed_at': observation.observedAt.millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<TraitObservation>> observations() async {
    final List<Map<String, Object?>> rows = await _db.query(table, orderBy: 'observed_at');
    final List<TraitObservation> result = [];
    for (final Map<String, Object?> row in rows) {
      final TraitDimension? dimension = TraitDimension.byName(row['dimension']! as String);
      final String value = row['value']! as String;
      final TraitSource? source = TraitSource.values.where((s) => s.name == row['source']).firstOrNull;
      // 舊版本留下、現在已不允許的值直接略過（例如之後刪掉某個類別）
      if (dimension == null || source == null || !dimension.allows(value)) continue;
      result.add(TraitObservation(
        dimension: dimension,
        value: value,
        confidence: (row['confidence']! as num).toDouble(),
        source: source,
        evidenceKey: row['evidence_key']! as String,
        detail: row['detail'] as String?,
        model: row['model'] as String?,
        observedAt: DateTime.fromMillisecondsSinceEpoch(row['observed_at']! as int),
      ));
    }
    return result;
  }

  /// 綜合後的使用者特徵，依可信度由高到低；[minConfidence] 可只取夠可信的（推薦建議用
  /// [TraitAggregator.confidentThreshold]）。
  Future<List<UserTrait>> traits({DateTime? now, double minConfidence = 0}) async {
    final List<UserTrait> all = TraitAggregator.aggregate(await observations(), now: now ?? DateTime.now());
    return all.where((trait) => trait.confidence >= minConfidence).toList();
  }

  /// 清除全部資料（之後若要提供「清除」功能可直接使用）。
  Future<void> clear() => _db.delete(table);

  /// 刪掉某個證據鍵的所有觀察（設定類訊號改選時，用新的取代舊的）。
  Future<void> removeEvidence(String evidenceKey) =>
      _db.delete(table, where: 'evidence_key = ?', whereArgs: [evidenceKey]);

  Future<void> close() => _db.close();

  Future<void> _prune(DateTime now) async {
    final int removed = await _db.delete(
      table,
      where: 'observed_at < ?',
      whereArgs: [now.subtract(retention).millisecondsSinceEpoch],
    );
    if (removed > 0) debugPrint('[使用者特徵] 刪除 $removed 筆超過 ${retention.inDays} 天的觀察');
  }
}
