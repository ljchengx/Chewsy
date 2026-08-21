import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Restaurants extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  TextColumn get alias => text().nullable()();
  TextColumn get locationNote => text().nullable()();
  BoolColumn get isHomeMade => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MealRecords extends Table {
  TextColumn get id => text()();
  TextColumn get restaurantId => text().references(Restaurants, #id)();
  TextColumn get verdict => text()();
  TextColumn get scene => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get eatenAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get contentHash => text()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MealItems extends Table {
  TextColumn get id => text()();
  TextColumn get recordId => text().references(MealRecords, #id)();
  TextColumn get name => text()();
  TextColumn get verdict => text()();
  IntColumn get intensity => integer().nullable()();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  TextColumn get category => text().withDefault(const Constant('reason'))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {normalizedName},
  ];
}

class RecordTags extends Table {
  TextColumn get recordId => text().references(MealRecords, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column<Object>> get primaryKey => {recordId, tagId};
}

class MediaAssets extends Table {
  TextColumn get id => text()();
  TextColumn get recordId => text().references(MealRecords, #id)();
  TextColumn get relativePath => text()();
  TextColumn get thumbnailPath => text()();
  TextColumn get sha256 => text()();
  TextColumn get mimeType => text()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get byteSize => integer()();
  TextColumn get state => text().withDefault(const Constant('ready'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RecordRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get recordId => text().references(MealRecords, #id)();
  IntColumn get revision => integer()();
  TextColumn get contentHash => text()();
  TextColumn get snapshotJson => text()();
  DateTimeColumn get changedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {recordId, revision},
  ];
}

class Drafts extends Table {
  TextColumn get id => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ImportJobs extends Table {
  TextColumn get id => text()();
  TextColumn get backupId => text()();
  TextColumn get state => text()();
  TextColumn get stagingPath => text()();
  TextColumn get rollbackPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ImportHistory extends Table {
  TextColumn get backupId => text()();
  DateTimeColumn get importedAt => dateTime()();
  TextColumn get resultDigest => text()();

  @override
  Set<Column<Object>> get primaryKey => {backupId};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Restaurants,
    MealRecords,
    MealItems,
    Tags,
    RecordTags,
    MediaAssets,
    RecordRevisions,
    Drafts,
    ImportJobs,
    ImportHistory,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor})
    : super(executor ?? driftDatabase(name: 'chewsy'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 1) {
        await m.createAll();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
