// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, BookRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isAvailableLocallyMeta =
      const VerificationMeta('isAvailableLocally');
  @override
  late final GeneratedColumn<bool> isAvailableLocally = GeneratedColumn<bool>(
    'is_available_locally',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_available_locally" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sha256,
    title,
    author,
    description,
    mediaType,
    filePath,
    coverPath,
    isAvailableLocally,
    isDeleted,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('is_available_locally')) {
      context.handle(
        _isAvailableLocallyMeta,
        isAvailableLocally.isAcceptableOrUnknown(
          data['is_available_locally']!,
          _isAvailableLocallyMeta,
        ),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      isAvailableLocally: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_available_locally'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class BookRecord extends DataClass implements Insertable<BookRecord> {
  final String id;
  final String sha256;
  final String title;
  final String? author;
  final String? description;
  final String mediaType;
  final String? filePath;
  final String? coverPath;
  final bool isAvailableLocally;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  const BookRecord({
    required this.id,
    required this.sha256,
    required this.title,
    this.author,
    this.description,
    required this.mediaType,
    this.filePath,
    this.coverPath,
    required this.isAvailableLocally,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sha256'] = Variable<String>(sha256);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['media_type'] = Variable<String>(mediaType);
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['is_available_locally'] = Variable<bool>(isAvailableLocally);
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      sha256: Value(sha256),
      title: Value(title),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      mediaType: Value(mediaType),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      isAvailableLocally: Value(isAvailableLocally),
      isDeleted: Value(isDeleted),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookRecord(
      id: serializer.fromJson<String>(json['id']),
      sha256: serializer.fromJson<String>(json['sha256']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      description: serializer.fromJson<String?>(json['description']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      isAvailableLocally: serializer.fromJson<bool>(json['isAvailableLocally']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sha256': serializer.toJson<String>(sha256),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'description': serializer.toJson<String?>(description),
      'mediaType': serializer.toJson<String>(mediaType),
      'filePath': serializer.toJson<String?>(filePath),
      'coverPath': serializer.toJson<String?>(coverPath),
      'isAvailableLocally': serializer.toJson<bool>(isAvailableLocally),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BookRecord copyWith({
    String? id,
    String? sha256,
    String? title,
    Value<String?> author = const Value.absent(),
    Value<String?> description = const Value.absent(),
    String? mediaType,
    Value<String?> filePath = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    bool? isAvailableLocally,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BookRecord(
    id: id ?? this.id,
    sha256: sha256 ?? this.sha256,
    title: title ?? this.title,
    author: author.present ? author.value : this.author,
    description: description.present ? description.value : this.description,
    mediaType: mediaType ?? this.mediaType,
    filePath: filePath.present ? filePath.value : this.filePath,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    isAvailableLocally: isAvailableLocally ?? this.isAvailableLocally,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookRecord copyWithCompanion(BooksCompanion data) {
    return BookRecord(
      id: data.id.present ? data.id.value : this.id,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      description: data.description.present
          ? data.description.value
          : this.description,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      isAvailableLocally: data.isAvailableLocally.present
          ? data.isAvailableLocally.value
          : this.isAvailableLocally,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookRecord(')
          ..write('id: $id, ')
          ..write('sha256: $sha256, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('mediaType: $mediaType, ')
          ..write('filePath: $filePath, ')
          ..write('coverPath: $coverPath, ')
          ..write('isAvailableLocally: $isAvailableLocally, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sha256,
    title,
    author,
    description,
    mediaType,
    filePath,
    coverPath,
    isAvailableLocally,
    isDeleted,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookRecord &&
          other.id == this.id &&
          other.sha256 == this.sha256 &&
          other.title == this.title &&
          other.author == this.author &&
          other.description == this.description &&
          other.mediaType == this.mediaType &&
          other.filePath == this.filePath &&
          other.coverPath == this.coverPath &&
          other.isAvailableLocally == this.isAvailableLocally &&
          other.isDeleted == this.isDeleted &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BooksCompanion extends UpdateCompanion<BookRecord> {
  final Value<String> id;
  final Value<String> sha256;
  final Value<String> title;
  final Value<String?> author;
  final Value<String?> description;
  final Value<String> mediaType;
  final Value<String?> filePath;
  final Value<String?> coverPath;
  final Value<bool> isAvailableLocally;
  final Value<bool> isDeleted;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.filePath = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.isAvailableLocally = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String sha256,
    required String title,
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    required String mediaType,
    this.filePath = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.isAvailableLocally = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sha256 = Value(sha256),
       title = Value(title),
       mediaType = Value(mediaType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookRecord> custom({
    Expression<String>? id,
    Expression<String>? sha256,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? description,
    Expression<String>? mediaType,
    Expression<String>? filePath,
    Expression<String>? coverPath,
    Expression<bool>? isAvailableLocally,
    Expression<bool>? isDeleted,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sha256 != null) 'sha256': sha256,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (description != null) 'description': description,
      if (mediaType != null) 'media_type': mediaType,
      if (filePath != null) 'file_path': filePath,
      if (coverPath != null) 'cover_path': coverPath,
      if (isAvailableLocally != null)
        'is_available_locally': isAvailableLocally,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? sha256,
    Value<String>? title,
    Value<String?>? author,
    Value<String?>? description,
    Value<String>? mediaType,
    Value<String?>? filePath,
    Value<String?>? coverPath,
    Value<bool>? isAvailableLocally,
    Value<bool>? isDeleted,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      sha256: sha256 ?? this.sha256,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      mediaType: mediaType ?? this.mediaType,
      filePath: filePath ?? this.filePath,
      coverPath: coverPath ?? this.coverPath,
      isAvailableLocally: isAvailableLocally ?? this.isAvailableLocally,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (isAvailableLocally.present) {
      map['is_available_locally'] = Variable<bool>(isAvailableLocally.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('sha256: $sha256, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('mediaType: $mediaType, ')
          ..write('filePath: $filePath, ')
          ..write('coverPath: $coverPath, ')
          ..write('isAvailableLocally: $isAvailableLocally, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookshelvesTable extends Bookshelves
    with TableInfo<$BookshelvesTable, BookshelfRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookshelvesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES bookshelves (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentId,
    name,
    sortOrder,
    isDeleted,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookshelves';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookshelfRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookshelfRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookshelfRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookshelvesTable createAlias(String alias) {
    return $BookshelvesTable(attachedDatabase, alias);
  }
}

class BookshelfRecord extends DataClass implements Insertable<BookshelfRecord> {
  final String id;
  final String? parentId;
  final String name;
  final int sortOrder;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  const BookshelfRecord({
    required this.id,
    this.parentId,
    required this.name,
    required this.sortOrder,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BookshelvesCompanion toCompanion(bool nullToAbsent) {
    return BookshelvesCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      sortOrder: Value(sortOrder),
      isDeleted: Value(isDeleted),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookshelfRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookshelfRecord(
      id: serializer.fromJson<String>(json['id']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BookshelfRecord copyWith({
    String? id,
    Value<String?> parentId = const Value.absent(),
    String? name,
    int? sortOrder,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BookshelfRecord(
    id: id ?? this.id,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookshelfRecord copyWithCompanion(BookshelvesCompanion data) {
    return BookshelfRecord(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookshelfRecord(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    parentId,
    name,
    sortOrder,
    isDeleted,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookshelfRecord &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.isDeleted == this.isDeleted &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BookshelvesCompanion extends UpdateCompanion<BookshelfRecord> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<bool> isDeleted;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BookshelvesCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookshelvesCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
    required String name,
    this.sortOrder = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookshelfRecord> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<bool>? isDeleted,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookshelvesCompanion copyWith({
    Value<String>? id,
    Value<String?>? parentId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<bool>? isDeleted,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BookshelvesCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookshelvesCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookshelfEntriesTable extends BookshelfEntries
    with TableInfo<$BookshelfEntriesTable, BookshelfEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookshelfEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookshelfIdMeta = const VerificationMeta(
    'bookshelfId',
  );
  @override
  late final GeneratedColumn<String> bookshelfId = GeneratedColumn<String>(
    'bookshelf_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES bookshelves (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookshelfId,
    bookId,
    sortOrder,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookshelf_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookshelfEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bookshelf_id')) {
      context.handle(
        _bookshelfIdMeta,
        bookshelfId.isAcceptableOrUnknown(
          data['bookshelf_id']!,
          _bookshelfIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_bookshelfIdMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookshelfId, bookId};
  @override
  BookshelfEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookshelfEntry(
      bookshelfId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bookshelf_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookshelfEntriesTable createAlias(String alias) {
    return $BookshelfEntriesTable(attachedDatabase, alias);
  }
}

class BookshelfEntry extends DataClass implements Insertable<BookshelfEntry> {
  final String bookshelfId;
  final String bookId;
  final int sortOrder;
  final DateTime updatedAt;
  const BookshelfEntry({
    required this.bookshelfId,
    required this.bookId,
    required this.sortOrder,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bookshelf_id'] = Variable<String>(bookshelfId);
    map['book_id'] = Variable<String>(bookId);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BookshelfEntriesCompanion toCompanion(bool nullToAbsent) {
    return BookshelfEntriesCompanion(
      bookshelfId: Value(bookshelfId),
      bookId: Value(bookId),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookshelfEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookshelfEntry(
      bookshelfId: serializer.fromJson<String>(json['bookshelfId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookshelfId': serializer.toJson<String>(bookshelfId),
      'bookId': serializer.toJson<String>(bookId),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BookshelfEntry copyWith({
    String? bookshelfId,
    String? bookId,
    int? sortOrder,
    DateTime? updatedAt,
  }) => BookshelfEntry(
    bookshelfId: bookshelfId ?? this.bookshelfId,
    bookId: bookId ?? this.bookId,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookshelfEntry copyWithCompanion(BookshelfEntriesCompanion data) {
    return BookshelfEntry(
      bookshelfId: data.bookshelfId.present
          ? data.bookshelfId.value
          : this.bookshelfId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookshelfEntry(')
          ..write('bookshelfId: $bookshelfId, ')
          ..write('bookId: $bookId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookshelfId, bookId, sortOrder, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookshelfEntry &&
          other.bookshelfId == this.bookshelfId &&
          other.bookId == this.bookId &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt);
}

class BookshelfEntriesCompanion extends UpdateCompanion<BookshelfEntry> {
  final Value<String> bookshelfId;
  final Value<String> bookId;
  final Value<int> sortOrder;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BookshelfEntriesCompanion({
    this.bookshelfId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookshelfEntriesCompanion.insert({
    required String bookshelfId,
    required String bookId,
    this.sortOrder = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookshelfId = Value(bookshelfId),
       bookId = Value(bookId),
       updatedAt = Value(updatedAt);
  static Insertable<BookshelfEntry> custom({
    Expression<String>? bookshelfId,
    Expression<String>? bookId,
    Expression<int>? sortOrder,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookshelfId != null) 'bookshelf_id': bookshelfId,
      if (bookId != null) 'book_id': bookId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookshelfEntriesCompanion copyWith({
    Value<String>? bookshelfId,
    Value<String>? bookId,
    Value<int>? sortOrder,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BookshelfEntriesCompanion(
      bookshelfId: bookshelfId ?? this.bookshelfId,
      bookId: bookId ?? this.bookId,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookshelfId.present) {
      map['bookshelf_id'] = Variable<String>(bookshelfId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookshelfEntriesCompanion(')
          ..write('bookshelfId: $bookshelfId, ')
          ..write('bookId: $bookId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExcerptsTable extends Excerpts
    with TableInfo<$ExcerptsTable, ExcerptRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExcerptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorMeta = const VerificationMeta(
    'locator',
  );
  @override
  late final GeneratedColumn<String> locator = GeneratedColumn<String>(
    'locator',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quoteMeta = const VerificationMeta('quote');
  @override
  late final GeneratedColumn<String> quote = GeneratedColumn<String>(
    'quote',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('yellow'),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    locator,
    quote,
    note,
    color,
    isDeleted,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'excerpts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExcerptRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('locator')) {
      context.handle(
        _locatorMeta,
        locator.isAcceptableOrUnknown(data['locator']!, _locatorMeta),
      );
    } else if (isInserting) {
      context.missing(_locatorMeta);
    }
    if (data.containsKey('quote')) {
      context.handle(
        _quoteMeta,
        quote.isAcceptableOrUnknown(data['quote']!, _quoteMeta),
      );
    } else if (isInserting) {
      context.missing(_quoteMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExcerptRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExcerptRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator'],
      )!,
      quote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quote'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ExcerptsTable createAlias(String alias) {
    return $ExcerptsTable(attachedDatabase, alias);
  }
}

class ExcerptRecord extends DataClass implements Insertable<ExcerptRecord> {
  final String id;
  final String bookId;
  final String locator;
  final String quote;
  final String? note;
  final String color;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ExcerptRecord({
    required this.id,
    required this.bookId,
    required this.locator,
    required this.quote,
    this.note,
    required this.color,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['locator'] = Variable<String>(locator);
    map['quote'] = Variable<String>(quote);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['color'] = Variable<String>(color);
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ExcerptsCompanion toCompanion(bool nullToAbsent) {
    return ExcerptsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      locator: Value(locator),
      quote: Value(quote),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      color: Value(color),
      isDeleted: Value(isDeleted),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ExcerptRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExcerptRecord(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      locator: serializer.fromJson<String>(json['locator']),
      quote: serializer.fromJson<String>(json['quote']),
      note: serializer.fromJson<String?>(json['note']),
      color: serializer.fromJson<String>(json['color']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'locator': serializer.toJson<String>(locator),
      'quote': serializer.toJson<String>(quote),
      'note': serializer.toJson<String?>(note),
      'color': serializer.toJson<String>(color),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ExcerptRecord copyWith({
    String? id,
    String? bookId,
    String? locator,
    String? quote,
    Value<String?> note = const Value.absent(),
    String? color,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ExcerptRecord(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    locator: locator ?? this.locator,
    quote: quote ?? this.quote,
    note: note.present ? note.value : this.note,
    color: color ?? this.color,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ExcerptRecord copyWithCompanion(ExcerptsCompanion data) {
    return ExcerptRecord(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locator: data.locator.present ? data.locator.value : this.locator,
      quote: data.quote.present ? data.quote.value : this.quote,
      note: data.note.present ? data.note.value : this.note,
      color: data.color.present ? data.color.value : this.color,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExcerptRecord(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('quote: $quote, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    locator,
    quote,
    note,
    color,
    isDeleted,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExcerptRecord &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.locator == this.locator &&
          other.quote == this.quote &&
          other.note == this.note &&
          other.color == this.color &&
          other.isDeleted == this.isDeleted &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ExcerptsCompanion extends UpdateCompanion<ExcerptRecord> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> locator;
  final Value<String> quote;
  final Value<String?> note;
  final Value<String> color;
  final Value<bool> isDeleted;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ExcerptsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.locator = const Value.absent(),
    this.quote = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExcerptsCompanion.insert({
    required String id,
    required String bookId,
    required String locator,
    required String quote,
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       locator = Value(locator),
       quote = Value(quote),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ExcerptRecord> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? locator,
    Expression<String>? quote,
    Expression<String>? note,
    Expression<String>? color,
    Expression<bool>? isDeleted,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (locator != null) 'locator': locator,
      if (quote != null) 'quote': quote,
      if (note != null) 'note': note,
      if (color != null) 'color': color,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExcerptsCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? locator,
    Value<String>? quote,
    Value<String?>? note,
    Value<String>? color,
    Value<bool>? isDeleted,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ExcerptsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      locator: locator ?? this.locator,
      quote: quote ?? this.quote,
      note: note ?? this.note,
      color: color ?? this.color,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locator.present) {
      map['locator'] = Variable<String>(locator.value);
    }
    if (quote.present) {
      map['quote'] = Variable<String>(quote.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExcerptsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('quote: $quote, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, BookmarkRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorMeta = const VerificationMeta(
    'locator',
  );
  @override
  late final GeneratedColumn<String> locator = GeneratedColumn<String>(
    'locator',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    locator,
    title,
    note,
    isDeleted,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookmarkRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('locator')) {
      context.handle(
        _locatorMeta,
        locator.isAcceptableOrUnknown(data['locator']!, _locatorMeta),
      );
    } else if (isInserting) {
      context.missing(_locatorMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookmarkRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookmarkRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class BookmarkRecord extends DataClass implements Insertable<BookmarkRecord> {
  final String id;
  final String bookId;
  final String locator;
  final String? title;
  final String? note;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  const BookmarkRecord({
    required this.id,
    required this.bookId,
    required this.locator,
    this.title,
    this.note,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['locator'] = Variable<String>(locator);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(id),
      bookId: Value(bookId),
      locator: Value(locator),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      isDeleted: Value(isDeleted),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BookmarkRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookmarkRecord(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      locator: serializer.fromJson<String>(json['locator']),
      title: serializer.fromJson<String?>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'locator': serializer.toJson<String>(locator),
      'title': serializer.toJson<String?>(title),
      'note': serializer.toJson<String?>(note),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BookmarkRecord copyWith({
    String? id,
    String? bookId,
    String? locator,
    Value<String?> title = const Value.absent(),
    Value<String?> note = const Value.absent(),
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BookmarkRecord(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    locator: locator ?? this.locator,
    title: title.present ? title.value : this.title,
    note: note.present ? note.value : this.note,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BookmarkRecord copyWithCompanion(BookmarksCompanion data) {
    return BookmarkRecord(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locator: data.locator.present ? data.locator.value : this.locator,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookmarkRecord(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    locator,
    title,
    note,
    isDeleted,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookmarkRecord &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.locator == this.locator &&
          other.title == this.title &&
          other.note == this.note &&
          other.isDeleted == this.isDeleted &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BookmarksCompanion extends UpdateCompanion<BookmarkRecord> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> locator;
  final Value<String?> title;
  final Value<String?> note;
  final Value<bool> isDeleted;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.locator = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String id,
    required String bookId,
    required String locator,
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       locator = Value(locator),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookmarkRecord> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? locator,
    Expression<String>? title,
    Expression<String>? note,
    Expression<bool>? isDeleted,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (locator != null) 'locator': locator,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarksCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? locator,
    Value<String?>? title,
    Value<String?>? note,
    Value<bool>? isDeleted,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BookmarksCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      locator: locator ?? this.locator,
      title: title ?? this.title,
      note: note ?? this.note,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locator.present) {
      map['locator'] = Variable<String>(locator.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingProgressesTable extends ReadingProgresses
    with TableInfo<$ReadingProgressesTable, ReadingProgressRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorMeta = const VerificationMeta(
    'locator',
  );
  @override
  late final GeneratedColumn<String> locator = GeneratedColumn<String>(
    'locator',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    locator,
    progress,
    chapterTitle,
    page,
    deviceId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progresses';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('locator')) {
      context.handle(
        _locatorMeta,
        locator.isAcceptableOrUnknown(data['locator']!, _locatorMeta),
      );
    } else if (isInserting) {
      context.missing(_locatorMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    } else if (isInserting) {
      context.missing(_progressMeta);
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  ReadingProgressRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressRecord(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      ),
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReadingProgressesTable createAlias(String alias) {
    return $ReadingProgressesTable(attachedDatabase, alias);
  }
}

class ReadingProgressRecord extends DataClass
    implements Insertable<ReadingProgressRecord> {
  final String bookId;
  final String locator;
  final double progress;
  final String? chapterTitle;
  final int? page;
  final String deviceId;
  final DateTime updatedAt;
  const ReadingProgressRecord({
    required this.bookId,
    required this.locator,
    required this.progress,
    this.chapterTitle,
    this.page,
    required this.deviceId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['locator'] = Variable<String>(locator);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || chapterTitle != null) {
      map['chapter_title'] = Variable<String>(chapterTitle);
    }
    if (!nullToAbsent || page != null) {
      map['page'] = Variable<int>(page);
    }
    map['device_id'] = Variable<String>(deviceId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReadingProgressesCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressesCompanion(
      bookId: Value(bookId),
      locator: Value(locator),
      progress: Value(progress),
      chapterTitle: chapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterTitle),
      page: page == null && nullToAbsent ? const Value.absent() : Value(page),
      deviceId: Value(deviceId),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReadingProgressRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressRecord(
      bookId: serializer.fromJson<String>(json['bookId']),
      locator: serializer.fromJson<String>(json['locator']),
      progress: serializer.fromJson<double>(json['progress']),
      chapterTitle: serializer.fromJson<String?>(json['chapterTitle']),
      page: serializer.fromJson<int?>(json['page']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'locator': serializer.toJson<String>(locator),
      'progress': serializer.toJson<double>(progress),
      'chapterTitle': serializer.toJson<String?>(chapterTitle),
      'page': serializer.toJson<int?>(page),
      'deviceId': serializer.toJson<String>(deviceId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReadingProgressRecord copyWith({
    String? bookId,
    String? locator,
    double? progress,
    Value<String?> chapterTitle = const Value.absent(),
    Value<int?> page = const Value.absent(),
    String? deviceId,
    DateTime? updatedAt,
  }) => ReadingProgressRecord(
    bookId: bookId ?? this.bookId,
    locator: locator ?? this.locator,
    progress: progress ?? this.progress,
    chapterTitle: chapterTitle.present ? chapterTitle.value : this.chapterTitle,
    page: page.present ? page.value : this.page,
    deviceId: deviceId ?? this.deviceId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReadingProgressRecord copyWithCompanion(ReadingProgressesCompanion data) {
    return ReadingProgressRecord(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locator: data.locator.present ? data.locator.value : this.locator,
      progress: data.progress.present ? data.progress.value : this.progress,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      page: data.page.present ? data.page.value : this.page,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressRecord(')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('progress: $progress, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('page: $page, ')
          ..write('deviceId: $deviceId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    locator,
    progress,
    chapterTitle,
    page,
    deviceId,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressRecord &&
          other.bookId == this.bookId &&
          other.locator == this.locator &&
          other.progress == this.progress &&
          other.chapterTitle == this.chapterTitle &&
          other.page == this.page &&
          other.deviceId == this.deviceId &&
          other.updatedAt == this.updatedAt);
}

class ReadingProgressesCompanion
    extends UpdateCompanion<ReadingProgressRecord> {
  final Value<String> bookId;
  final Value<String> locator;
  final Value<double> progress;
  final Value<String?> chapterTitle;
  final Value<int?> page;
  final Value<String> deviceId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReadingProgressesCompanion({
    this.bookId = const Value.absent(),
    this.locator = const Value.absent(),
    this.progress = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.page = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressesCompanion.insert({
    required String bookId,
    required String locator,
    required double progress,
    this.chapterTitle = const Value.absent(),
    this.page = const Value.absent(),
    required String deviceId,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       locator = Value(locator),
       progress = Value(progress),
       deviceId = Value(deviceId),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingProgressRecord> custom({
    Expression<String>? bookId,
    Expression<String>? locator,
    Expression<double>? progress,
    Expression<String>? chapterTitle,
    Expression<int>? page,
    Expression<String>? deviceId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (locator != null) 'locator': locator,
      if (progress != null) 'progress': progress,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (page != null) 'page': page,
      if (deviceId != null) 'device_id': deviceId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressesCompanion copyWith({
    Value<String>? bookId,
    Value<String>? locator,
    Value<double>? progress,
    Value<String?>? chapterTitle,
    Value<int?>? page,
    Value<String>? deviceId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingProgressesCompanion(
      bookId: bookId ?? this.bookId,
      locator: locator ?? this.locator,
      progress: progress ?? this.progress,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      page: page ?? this.page,
      deviceId: deviceId ?? this.deviceId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locator.present) {
      map['locator'] = Variable<String>(locator.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressesCompanion(')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('progress: $progress, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('page: $page, ')
          ..write('deviceId: $deviceId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingProgressHistoryTable extends ReadingProgressHistory
    with TableInfo<$ReadingProgressHistoryTable, ReadingProgressHistoryRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorMeta = const VerificationMeta(
    'locator',
  );
  @override
  late final GeneratedColumn<String> locator = GeneratedColumn<String>(
    'locator',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    bookId,
    locator,
    progress,
    chapterTitle,
    page,
    deviceId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressHistoryRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('locator')) {
      context.handle(
        _locatorMeta,
        locator.isAcceptableOrUnknown(data['locator']!, _locatorMeta),
      );
    } else if (isInserting) {
      context.missing(_locatorMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    } else if (isInserting) {
      context.missing(_progressMeta);
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  ReadingProgressHistoryRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressHistoryRecord(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      ),
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReadingProgressHistoryTable createAlias(String alias) {
    return $ReadingProgressHistoryTable(attachedDatabase, alias);
  }
}

class ReadingProgressHistoryRecord extends DataClass
    implements Insertable<ReadingProgressHistoryRecord> {
  final String operationId;
  final String bookId;
  final String locator;
  final double progress;
  final String? chapterTitle;
  final int? page;
  final String deviceId;
  final DateTime updatedAt;
  const ReadingProgressHistoryRecord({
    required this.operationId,
    required this.bookId,
    required this.locator,
    required this.progress,
    this.chapterTitle,
    this.page,
    required this.deviceId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['book_id'] = Variable<String>(bookId);
    map['locator'] = Variable<String>(locator);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || chapterTitle != null) {
      map['chapter_title'] = Variable<String>(chapterTitle);
    }
    if (!nullToAbsent || page != null) {
      map['page'] = Variable<int>(page);
    }
    map['device_id'] = Variable<String>(deviceId);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReadingProgressHistoryCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressHistoryCompanion(
      operationId: Value(operationId),
      bookId: Value(bookId),
      locator: Value(locator),
      progress: Value(progress),
      chapterTitle: chapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterTitle),
      page: page == null && nullToAbsent ? const Value.absent() : Value(page),
      deviceId: Value(deviceId),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReadingProgressHistoryRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressHistoryRecord(
      operationId: serializer.fromJson<String>(json['operationId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      locator: serializer.fromJson<String>(json['locator']),
      progress: serializer.fromJson<double>(json['progress']),
      chapterTitle: serializer.fromJson<String?>(json['chapterTitle']),
      page: serializer.fromJson<int?>(json['page']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'bookId': serializer.toJson<String>(bookId),
      'locator': serializer.toJson<String>(locator),
      'progress': serializer.toJson<double>(progress),
      'chapterTitle': serializer.toJson<String?>(chapterTitle),
      'page': serializer.toJson<int?>(page),
      'deviceId': serializer.toJson<String>(deviceId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReadingProgressHistoryRecord copyWith({
    String? operationId,
    String? bookId,
    String? locator,
    double? progress,
    Value<String?> chapterTitle = const Value.absent(),
    Value<int?> page = const Value.absent(),
    String? deviceId,
    DateTime? updatedAt,
  }) => ReadingProgressHistoryRecord(
    operationId: operationId ?? this.operationId,
    bookId: bookId ?? this.bookId,
    locator: locator ?? this.locator,
    progress: progress ?? this.progress,
    chapterTitle: chapterTitle.present ? chapterTitle.value : this.chapterTitle,
    page: page.present ? page.value : this.page,
    deviceId: deviceId ?? this.deviceId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReadingProgressHistoryRecord copyWithCompanion(
    ReadingProgressHistoryCompanion data,
  ) {
    return ReadingProgressHistoryRecord(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locator: data.locator.present ? data.locator.value : this.locator,
      progress: data.progress.present ? data.progress.value : this.progress,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      page: data.page.present ? data.page.value : this.page,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressHistoryRecord(')
          ..write('operationId: $operationId, ')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('progress: $progress, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('page: $page, ')
          ..write('deviceId: $deviceId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    bookId,
    locator,
    progress,
    chapterTitle,
    page,
    deviceId,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressHistoryRecord &&
          other.operationId == this.operationId &&
          other.bookId == this.bookId &&
          other.locator == this.locator &&
          other.progress == this.progress &&
          other.chapterTitle == this.chapterTitle &&
          other.page == this.page &&
          other.deviceId == this.deviceId &&
          other.updatedAt == this.updatedAt);
}

class ReadingProgressHistoryCompanion
    extends UpdateCompanion<ReadingProgressHistoryRecord> {
  final Value<String> operationId;
  final Value<String> bookId;
  final Value<String> locator;
  final Value<double> progress;
  final Value<String?> chapterTitle;
  final Value<int?> page;
  final Value<String> deviceId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReadingProgressHistoryCompanion({
    this.operationId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.locator = const Value.absent(),
    this.progress = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.page = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressHistoryCompanion.insert({
    required String operationId,
    required String bookId,
    required String locator,
    required double progress,
    this.chapterTitle = const Value.absent(),
    this.page = const Value.absent(),
    required String deviceId,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       bookId = Value(bookId),
       locator = Value(locator),
       progress = Value(progress),
       deviceId = Value(deviceId),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingProgressHistoryRecord> custom({
    Expression<String>? operationId,
    Expression<String>? bookId,
    Expression<String>? locator,
    Expression<double>? progress,
    Expression<String>? chapterTitle,
    Expression<int>? page,
    Expression<String>? deviceId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (bookId != null) 'book_id': bookId,
      if (locator != null) 'locator': locator,
      if (progress != null) 'progress': progress,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (page != null) 'page': page,
      if (deviceId != null) 'device_id': deviceId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressHistoryCompanion copyWith({
    Value<String>? operationId,
    Value<String>? bookId,
    Value<String>? locator,
    Value<double>? progress,
    Value<String?>? chapterTitle,
    Value<int?>? page,
    Value<String>? deviceId,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingProgressHistoryCompanion(
      operationId: operationId ?? this.operationId,
      bookId: bookId ?? this.bookId,
      locator: locator ?? this.locator,
      progress: progress ?? this.progress,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      page: page ?? this.page,
      deviceId: deviceId ?? this.deviceId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locator.present) {
      map['locator'] = Variable<String>(locator.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressHistoryCompanion(')
          ..write('operationId: $operationId, ')
          ..write('bookId: $bookId, ')
          ..write('locator: $locator, ')
          ..write('progress: $progress, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('page: $page, ')
          ..write('deviceId: $deviceId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOperationsTable extends SyncOperations
    with TableInfo<$SyncOperationsTable, SyncOperationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appliedAtMeta = const VerificationMeta(
    'appliedAt',
  );
  @override
  late final GeneratedColumn<DateTime> appliedAt = GeneratedColumn<DateTime>(
    'applied_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    deviceId,
    entityType,
    entityId,
    kind,
    payloadJson,
    occurredAt,
    appliedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOperationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('applied_at')) {
      context.handle(
        _appliedAtMeta,
        appliedAt.isAcceptableOrUnknown(data['applied_at']!, _appliedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  SyncOperationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOperationRecord(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      ),
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      appliedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}applied_at'],
      ),
    );
  }

  @override
  $SyncOperationsTable createAlias(String alias) {
    return $SyncOperationsTable(attachedDatabase, alias);
  }
}

class SyncOperationRecord extends DataClass
    implements Insertable<SyncOperationRecord> {
  final String operationId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String kind;
  final String? payloadJson;
  final DateTime occurredAt;
  final DateTime? appliedAt;
  const SyncOperationRecord({
    required this.operationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.kind,
    this.payloadJson,
    required this.occurredAt,
    this.appliedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['device_id'] = Variable<String>(deviceId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    if (!nullToAbsent || appliedAt != null) {
      map['applied_at'] = Variable<DateTime>(appliedAt);
    }
    return map;
  }

  SyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return SyncOperationsCompanion(
      operationId: Value(operationId),
      deviceId: Value(deviceId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      kind: Value(kind),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
      occurredAt: Value(occurredAt),
      appliedAt: appliedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(appliedAt),
    );
  }

  factory SyncOperationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOperationRecord(
      operationId: serializer.fromJson<String>(json['operationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      kind: serializer.fromJson<String>(json['kind']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      appliedAt: serializer.fromJson<DateTime?>(json['appliedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'kind': serializer.toJson<String>(kind),
      'payloadJson': serializer.toJson<String?>(payloadJson),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'appliedAt': serializer.toJson<DateTime?>(appliedAt),
    };
  }

  SyncOperationRecord copyWith({
    String? operationId,
    String? deviceId,
    String? entityType,
    String? entityId,
    String? kind,
    Value<String?> payloadJson = const Value.absent(),
    DateTime? occurredAt,
    Value<DateTime?> appliedAt = const Value.absent(),
  }) => SyncOperationRecord(
    operationId: operationId ?? this.operationId,
    deviceId: deviceId ?? this.deviceId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    kind: kind ?? this.kind,
    payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
    occurredAt: occurredAt ?? this.occurredAt,
    appliedAt: appliedAt.present ? appliedAt.value : this.appliedAt,
  );
  SyncOperationRecord copyWithCompanion(SyncOperationsCompanion data) {
    return SyncOperationRecord(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      kind: data.kind.present ? data.kind.value : this.kind,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      appliedAt: data.appliedAt.present ? data.appliedAt.value : this.appliedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationRecord(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('appliedAt: $appliedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    deviceId,
    entityType,
    entityId,
    kind,
    payloadJson,
    occurredAt,
    appliedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOperationRecord &&
          other.operationId == this.operationId &&
          other.deviceId == this.deviceId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.kind == this.kind &&
          other.payloadJson == this.payloadJson &&
          other.occurredAt == this.occurredAt &&
          other.appliedAt == this.appliedAt);
}

class SyncOperationsCompanion extends UpdateCompanion<SyncOperationRecord> {
  final Value<String> operationId;
  final Value<String> deviceId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> kind;
  final Value<String?> payloadJson;
  final Value<DateTime> occurredAt;
  final Value<DateTime?> appliedAt;
  final Value<int> rowid;
  const SyncOperationsCompanion({
    this.operationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.kind = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.appliedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOperationsCompanion.insert({
    required String operationId,
    required String deviceId,
    required String entityType,
    required String entityId,
    required String kind,
    this.payloadJson = const Value.absent(),
    required DateTime occurredAt,
    this.appliedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       deviceId = Value(deviceId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       kind = Value(kind),
       occurredAt = Value(occurredAt);
  static Insertable<SyncOperationRecord> custom({
    Expression<String>? operationId,
    Expression<String>? deviceId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? kind,
    Expression<String>? payloadJson,
    Expression<DateTime>? occurredAt,
    Expression<DateTime>? appliedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (deviceId != null) 'device_id': deviceId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (kind != null) 'kind': kind,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (appliedAt != null) 'applied_at': appliedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOperationsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? deviceId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? kind,
    Value<String?>? payloadJson,
    Value<DateTime>? occurredAt,
    Value<DateTime?>? appliedAt,
    Value<int>? rowid,
  }) {
    return SyncOperationsCompanion(
      operationId: operationId ?? this.operationId,
      deviceId: deviceId ?? this.deviceId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      kind: kind ?? this.kind,
      payloadJson: payloadJson ?? this.payloadJson,
      occurredAt: occurredAt ?? this.occurredAt,
      appliedAt: appliedAt ?? this.appliedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (appliedAt.present) {
      map['applied_at'] = Variable<DateTime>(appliedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('appliedAt: $appliedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuditEventsTable extends AuditEvents
    with TableInfo<$AuditEventsTable, AuditEventRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _callerMeta = const VerificationMeta('caller');
  @override
  late final GeneratedColumn<String> caller = GeneratedColumn<String>(
    'caller',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parametersJsonMeta = const VerificationMeta(
    'parametersJson',
  );
  @override
  late final GeneratedColumn<String> parametersJson = GeneratedColumn<String>(
    'parameters_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultMeta = const VerificationMeta('result');
  @override
  late final GeneratedColumn<String> result = GeneratedColumn<String>(
    'result',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    caller,
    action,
    parametersJson,
    result,
    occurredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditEventRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('caller')) {
      context.handle(
        _callerMeta,
        caller.isAcceptableOrUnknown(data['caller']!, _callerMeta),
      );
    } else if (isInserting) {
      context.missing(_callerMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('parameters_json')) {
      context.handle(
        _parametersJsonMeta,
        parametersJson.isAcceptableOrUnknown(
          data['parameters_json']!,
          _parametersJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parametersJsonMeta);
    }
    if (data.containsKey('result')) {
      context.handle(
        _resultMeta,
        result.isAcceptableOrUnknown(data['result']!, _resultMeta),
      );
    } else if (isInserting) {
      context.missing(_resultMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditEventRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditEventRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      caller: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caller'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      parametersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parameters_json'],
      )!,
      result: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
    );
  }

  @override
  $AuditEventsTable createAlias(String alias) {
    return $AuditEventsTable(attachedDatabase, alias);
  }
}

class AuditEventRecord extends DataClass
    implements Insertable<AuditEventRecord> {
  final String id;
  final String caller;
  final String action;
  final String parametersJson;
  final String result;
  final DateTime occurredAt;
  const AuditEventRecord({
    required this.id,
    required this.caller,
    required this.action,
    required this.parametersJson,
    required this.result,
    required this.occurredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['caller'] = Variable<String>(caller);
    map['action'] = Variable<String>(action);
    map['parameters_json'] = Variable<String>(parametersJson);
    map['result'] = Variable<String>(result);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    return map;
  }

  AuditEventsCompanion toCompanion(bool nullToAbsent) {
    return AuditEventsCompanion(
      id: Value(id),
      caller: Value(caller),
      action: Value(action),
      parametersJson: Value(parametersJson),
      result: Value(result),
      occurredAt: Value(occurredAt),
    );
  }

  factory AuditEventRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditEventRecord(
      id: serializer.fromJson<String>(json['id']),
      caller: serializer.fromJson<String>(json['caller']),
      action: serializer.fromJson<String>(json['action']),
      parametersJson: serializer.fromJson<String>(json['parametersJson']),
      result: serializer.fromJson<String>(json['result']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'caller': serializer.toJson<String>(caller),
      'action': serializer.toJson<String>(action),
      'parametersJson': serializer.toJson<String>(parametersJson),
      'result': serializer.toJson<String>(result),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
    };
  }

  AuditEventRecord copyWith({
    String? id,
    String? caller,
    String? action,
    String? parametersJson,
    String? result,
    DateTime? occurredAt,
  }) => AuditEventRecord(
    id: id ?? this.id,
    caller: caller ?? this.caller,
    action: action ?? this.action,
    parametersJson: parametersJson ?? this.parametersJson,
    result: result ?? this.result,
    occurredAt: occurredAt ?? this.occurredAt,
  );
  AuditEventRecord copyWithCompanion(AuditEventsCompanion data) {
    return AuditEventRecord(
      id: data.id.present ? data.id.value : this.id,
      caller: data.caller.present ? data.caller.value : this.caller,
      action: data.action.present ? data.action.value : this.action,
      parametersJson: data.parametersJson.present
          ? data.parametersJson.value
          : this.parametersJson,
      result: data.result.present ? data.result.value : this.result,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventRecord(')
          ..write('id: $id, ')
          ..write('caller: $caller, ')
          ..write('action: $action, ')
          ..write('parametersJson: $parametersJson, ')
          ..write('result: $result, ')
          ..write('occurredAt: $occurredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, caller, action, parametersJson, result, occurredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditEventRecord &&
          other.id == this.id &&
          other.caller == this.caller &&
          other.action == this.action &&
          other.parametersJson == this.parametersJson &&
          other.result == this.result &&
          other.occurredAt == this.occurredAt);
}

class AuditEventsCompanion extends UpdateCompanion<AuditEventRecord> {
  final Value<String> id;
  final Value<String> caller;
  final Value<String> action;
  final Value<String> parametersJson;
  final Value<String> result;
  final Value<DateTime> occurredAt;
  final Value<int> rowid;
  const AuditEventsCompanion({
    this.id = const Value.absent(),
    this.caller = const Value.absent(),
    this.action = const Value.absent(),
    this.parametersJson = const Value.absent(),
    this.result = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuditEventsCompanion.insert({
    required String id,
    required String caller,
    required String action,
    required String parametersJson,
    required String result,
    required DateTime occurredAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       caller = Value(caller),
       action = Value(action),
       parametersJson = Value(parametersJson),
       result = Value(result),
       occurredAt = Value(occurredAt);
  static Insertable<AuditEventRecord> custom({
    Expression<String>? id,
    Expression<String>? caller,
    Expression<String>? action,
    Expression<String>? parametersJson,
    Expression<String>? result,
    Expression<DateTime>? occurredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (caller != null) 'caller': caller,
      if (action != null) 'action': action,
      if (parametersJson != null) 'parameters_json': parametersJson,
      if (result != null) 'result': result,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuditEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? caller,
    Value<String>? action,
    Value<String>? parametersJson,
    Value<String>? result,
    Value<DateTime>? occurredAt,
    Value<int>? rowid,
  }) {
    return AuditEventsCompanion(
      id: id ?? this.id,
      caller: caller ?? this.caller,
      action: action ?? this.action,
      parametersJson: parametersJson ?? this.parametersJson,
      result: result ?? this.result,
      occurredAt: occurredAt ?? this.occurredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (caller.present) {
      map['caller'] = Variable<String>(caller.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (parametersJson.present) {
      map['parameters_json'] = Variable<String>(parametersJson.value);
    }
    if (result.present) {
      map['result'] = Variable<String>(result.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditEventsCompanion(')
          ..write('id: $id, ')
          ..write('caller: $caller, ')
          ..write('action: $action, ')
          ..write('parametersJson: $parametersJson, ')
          ..write('result: $result, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $BookshelvesTable bookshelves = $BookshelvesTable(this);
  late final $BookshelfEntriesTable bookshelfEntries = $BookshelfEntriesTable(
    this,
  );
  late final $ExcerptsTable excerpts = $ExcerptsTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $ReadingProgressesTable readingProgresses =
      $ReadingProgressesTable(this);
  late final $ReadingProgressHistoryTable readingProgressHistory =
      $ReadingProgressHistoryTable(this);
  late final $SyncOperationsTable syncOperations = $SyncOperationsTable(this);
  late final $AuditEventsTable auditEvents = $AuditEventsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    bookshelves,
    bookshelfEntries,
    excerpts,
    bookmarks,
    readingProgresses,
    readingProgressHistory,
    syncOperations,
    auditEvents,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'bookshelves',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookshelves', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'bookshelves',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookshelf_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookshelf_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('excerpts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookmarks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('reading_progresses', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('reading_progress_history', kind: UpdateKind.delete),
      ],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      required String id,
      required String sha256,
      required String title,
      Value<String?> author,
      Value<String?> description,
      required String mediaType,
      Value<String?> filePath,
      Value<String?> coverPath,
      Value<bool> isAvailableLocally,
      Value<bool> isDeleted,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<String> id,
      Value<String> sha256,
      Value<String> title,
      Value<String?> author,
      Value<String?> description,
      Value<String> mediaType,
      Value<String?> filePath,
      Value<String?> coverPath,
      Value<bool> isAvailableLocally,
      Value<bool> isDeleted,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, BookRecord> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BookshelfEntriesTable, List<BookshelfEntry>>
  _bookshelfEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookshelfEntries,
    aliasName: 'books__id__bookshelf_entries__book_id',
  );

  $$BookshelfEntriesTableProcessedTableManager get bookshelfEntriesRefs {
    final manager = $$BookshelfEntriesTableTableManager(
      $_db,
      $_db.bookshelfEntries,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _bookshelfEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExcerptsTable, List<ExcerptRecord>>
  _excerptsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.excerpts,
    aliasName: 'books__id__excerpts__book_id',
  );

  $$ExcerptsTableProcessedTableManager get excerptsRefs {
    final manager = $$ExcerptsTableTableManager(
      $_db,
      $_db.excerpts,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_excerptsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookmarksTable, List<BookmarkRecord>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: 'books__id__bookmarks__book_id',
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ReadingProgressesTable,
    List<ReadingProgressRecord>
  >
  _readingProgressesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.readingProgresses,
        aliasName: 'books__id__reading_progresses__book_id',
      );

  $$ReadingProgressesTableProcessedTableManager get readingProgressesRefs {
    final manager = $$ReadingProgressesTableTableManager(
      $_db,
      $_db.readingProgresses,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingProgressesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ReadingProgressHistoryTable,
    List<ReadingProgressHistoryRecord>
  >
  _readingProgressHistoryRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.readingProgressHistory,
        aliasName: 'books__id__reading_progress_history__book_id',
      );

  $$ReadingProgressHistoryTableProcessedTableManager
  get readingProgressHistoryRefs {
    final manager = $$ReadingProgressHistoryTableTableManager(
      $_db,
      $_db.readingProgressHistory,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingProgressHistoryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isAvailableLocally => $composableBuilder(
    column: $table.isAvailableLocally,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> bookshelfEntriesRefs(
    Expression<bool> Function($$BookshelfEntriesTableFilterComposer f) f,
  ) {
    final $$BookshelfEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookshelfEntries,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelfEntriesTableFilterComposer(
            $db: $db,
            $table: $db.bookshelfEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> excerptsRefs(
    Expression<bool> Function($$ExcerptsTableFilterComposer f) f,
  ) {
    final $$ExcerptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.excerpts,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExcerptsTableFilterComposer(
            $db: $db,
            $table: $db.excerpts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readingProgressesRefs(
    Expression<bool> Function($$ReadingProgressesTableFilterComposer f) f,
  ) {
    final $$ReadingProgressesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingProgresses,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingProgressesTableFilterComposer(
            $db: $db,
            $table: $db.readingProgresses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readingProgressHistoryRefs(
    Expression<bool> Function($$ReadingProgressHistoryTableFilterComposer f) f,
  ) {
    final $$ReadingProgressHistoryTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressHistory,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressHistoryTableFilterComposer(
                $db: $db,
                $table: $db.readingProgressHistory,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isAvailableLocally => $composableBuilder(
    column: $table.isAvailableLocally,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<bool> get isAvailableLocally => $composableBuilder(
    column: $table.isAvailableLocally,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> bookshelfEntriesRefs<T extends Object>(
    Expression<T> Function($$BookshelfEntriesTableAnnotationComposer a) f,
  ) {
    final $$BookshelfEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookshelfEntries,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelfEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.bookshelfEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> excerptsRefs<T extends Object>(
    Expression<T> Function($$ExcerptsTableAnnotationComposer a) f,
  ) {
    final $$ExcerptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.excerpts,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExcerptsTableAnnotationComposer(
            $db: $db,
            $table: $db.excerpts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> readingProgressesRefs<T extends Object>(
    Expression<T> Function($$ReadingProgressesTableAnnotationComposer a) f,
  ) {
    final $$ReadingProgressesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgresses,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressesTableAnnotationComposer(
                $db: $db,
                $table: $db.readingProgresses,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> readingProgressHistoryRefs<T extends Object>(
    Expression<T> Function($$ReadingProgressHistoryTableAnnotationComposer a) f,
  ) {
    final $$ReadingProgressHistoryTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressHistory,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressHistoryTableAnnotationComposer(
                $db: $db,
                $table: $db.readingProgressHistory,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          BookRecord,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (BookRecord, $$BooksTableReferences),
          BookRecord,
          PrefetchHooks Function({
            bool bookshelfEntriesRefs,
            bool excerptsRefs,
            bool bookmarksRefs,
            bool readingProgressesRefs,
            bool readingProgressHistoryRefs,
          })
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<bool> isAvailableLocally = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                sha256: sha256,
                title: title,
                author: author,
                description: description,
                mediaType: mediaType,
                filePath: filePath,
                coverPath: coverPath,
                isAvailableLocally: isAvailableLocally,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sha256,
                required String title,
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                required String mediaType,
                Value<String?> filePath = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<bool> isAvailableLocally = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                sha256: sha256,
                title: title,
                author: author,
                description: description,
                mediaType: mediaType,
                filePath: filePath,
                coverPath: coverPath,
                isAvailableLocally: isAvailableLocally,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BooksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                bookshelfEntriesRefs = false,
                excerptsRefs = false,
                bookmarksRefs = false,
                readingProgressesRefs = false,
                readingProgressHistoryRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (bookshelfEntriesRefs) db.bookshelfEntries,
                    if (excerptsRefs) db.excerpts,
                    if (bookmarksRefs) db.bookmarks,
                    if (readingProgressesRefs) db.readingProgresses,
                    if (readingProgressHistoryRefs) db.readingProgressHistory,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (bookshelfEntriesRefs)
                        await $_getPrefetchedData<
                          BookRecord,
                          $BooksTable,
                          BookshelfEntry
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookshelfEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookshelfEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (excerptsRefs)
                        await $_getPrefetchedData<
                          BookRecord,
                          $BooksTable,
                          ExcerptRecord
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._excerptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).excerptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookmarksRefs)
                        await $_getPrefetchedData<
                          BookRecord,
                          $BooksTable,
                          BookmarkRecord
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readingProgressesRefs)
                        await $_getPrefetchedData<
                          BookRecord,
                          $BooksTable,
                          ReadingProgressRecord
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readingProgressesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readingProgressesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readingProgressHistoryRefs)
                        await $_getPrefetchedData<
                          BookRecord,
                          $BooksTable,
                          ReadingProgressHistoryRecord
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readingProgressHistoryRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readingProgressHistoryRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      BookRecord,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (BookRecord, $$BooksTableReferences),
      BookRecord,
      PrefetchHooks Function({
        bool bookshelfEntriesRefs,
        bool excerptsRefs,
        bool bookmarksRefs,
        bool readingProgressesRefs,
        bool readingProgressHistoryRefs,
      })
    >;
typedef $$BookshelvesTableCreateCompanionBuilder =
    BookshelvesCompanion Function({
      required String id,
      Value<String?> parentId,
      required String name,
      Value<int> sortOrder,
      Value<bool> isDeleted,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$BookshelvesTableUpdateCompanionBuilder =
    BookshelvesCompanion Function({
      Value<String> id,
      Value<String?> parentId,
      Value<String> name,
      Value<int> sortOrder,
      Value<bool> isDeleted,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$BookshelvesTableReferences
    extends BaseReferences<_$AppDatabase, $BookshelvesTable, BookshelfRecord> {
  $$BookshelvesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BookshelvesTable _parentIdTable(_$AppDatabase db) =>
      db.bookshelves.createAlias('bookshelves__parent_id__bookshelves__id');

  $$BookshelvesTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$BookshelvesTableTableManager(
      $_db,
      $_db.bookshelves,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$BookshelfEntriesTable, List<BookshelfEntry>>
  _bookshelfEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookshelfEntries,
    aliasName: 'bookshelves__id__bookshelf_entries__bookshelf_id',
  );

  $$BookshelfEntriesTableProcessedTableManager get bookshelfEntriesRefs {
    final manager = $$BookshelfEntriesTableTableManager(
      $_db,
      $_db.bookshelfEntries,
    ).filter((f) => f.bookshelfId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _bookshelfEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BookshelvesTableFilterComposer
    extends Composer<_$AppDatabase, $BookshelvesTable> {
  $$BookshelvesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BookshelvesTableFilterComposer get parentId {
    final $$BookshelvesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.bookshelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelvesTableFilterComposer(
            $db: $db,
            $table: $db.bookshelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> bookshelfEntriesRefs(
    Expression<bool> Function($$BookshelfEntriesTableFilterComposer f) f,
  ) {
    final $$BookshelfEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookshelfEntries,
      getReferencedColumn: (t) => t.bookshelfId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelfEntriesTableFilterComposer(
            $db: $db,
            $table: $db.bookshelfEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookshelvesTableOrderingComposer
    extends Composer<_$AppDatabase, $BookshelvesTable> {
  $$BookshelvesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BookshelvesTableOrderingComposer get parentId {
    final $$BookshelvesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.bookshelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelvesTableOrderingComposer(
            $db: $db,
            $table: $db.bookshelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookshelvesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookshelvesTable> {
  $$BookshelvesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BookshelvesTableAnnotationComposer get parentId {
    final $$BookshelvesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.bookshelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelvesTableAnnotationComposer(
            $db: $db,
            $table: $db.bookshelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> bookshelfEntriesRefs<T extends Object>(
    Expression<T> Function($$BookshelfEntriesTableAnnotationComposer a) f,
  ) {
    final $$BookshelfEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookshelfEntries,
      getReferencedColumn: (t) => t.bookshelfId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelfEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.bookshelfEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookshelvesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookshelvesTable,
          BookshelfRecord,
          $$BookshelvesTableFilterComposer,
          $$BookshelvesTableOrderingComposer,
          $$BookshelvesTableAnnotationComposer,
          $$BookshelvesTableCreateCompanionBuilder,
          $$BookshelvesTableUpdateCompanionBuilder,
          (BookshelfRecord, $$BookshelvesTableReferences),
          BookshelfRecord,
          PrefetchHooks Function({bool parentId, bool bookshelfEntriesRefs})
        > {
  $$BookshelvesTableTableManager(_$AppDatabase db, $BookshelvesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookshelvesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookshelvesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookshelvesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookshelvesCompanion(
                id: id,
                parentId: parentId,
                name: name,
                sortOrder: sortOrder,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> parentId = const Value.absent(),
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookshelvesCompanion.insert(
                id: id,
                parentId: parentId,
                name: name,
                sortOrder: sortOrder,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookshelvesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({parentId = false, bookshelfEntriesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (bookshelfEntriesRefs) db.bookshelfEntries,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (parentId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.parentId,
                                    referencedTable:
                                        $$BookshelvesTableReferences
                                            ._parentIdTable(db),
                                    referencedColumn:
                                        $$BookshelvesTableReferences
                                            ._parentIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (bookshelfEntriesRefs)
                        await $_getPrefetchedData<
                          BookshelfRecord,
                          $BookshelvesTable,
                          BookshelfEntry
                        >(
                          currentTable: table,
                          referencedTable: $$BookshelvesTableReferences
                              ._bookshelfEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BookshelvesTableReferences(
                                db,
                                table,
                                p0,
                              ).bookshelfEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookshelfId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BookshelvesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookshelvesTable,
      BookshelfRecord,
      $$BookshelvesTableFilterComposer,
      $$BookshelvesTableOrderingComposer,
      $$BookshelvesTableAnnotationComposer,
      $$BookshelvesTableCreateCompanionBuilder,
      $$BookshelvesTableUpdateCompanionBuilder,
      (BookshelfRecord, $$BookshelvesTableReferences),
      BookshelfRecord,
      PrefetchHooks Function({bool parentId, bool bookshelfEntriesRefs})
    >;
typedef $$BookshelfEntriesTableCreateCompanionBuilder =
    BookshelfEntriesCompanion Function({
      required String bookshelfId,
      required String bookId,
      Value<int> sortOrder,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$BookshelfEntriesTableUpdateCompanionBuilder =
    BookshelfEntriesCompanion Function({
      Value<String> bookshelfId,
      Value<String> bookId,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$BookshelfEntriesTableReferences
    extends
        BaseReferences<_$AppDatabase, $BookshelfEntriesTable, BookshelfEntry> {
  $$BookshelfEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BookshelvesTable _bookshelfIdTable(_$AppDatabase db) => db.bookshelves
      .createAlias('bookshelf_entries__bookshelf_id__bookshelves__id');

  $$BookshelvesTableProcessedTableManager get bookshelfId {
    final $_column = $_itemColumn<String>('bookshelf_id')!;

    final manager = $$BookshelvesTableTableManager(
      $_db,
      $_db.bookshelves,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookshelfIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('bookshelf_entries__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookshelfEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $BookshelfEntriesTable> {
  $$BookshelfEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BookshelvesTableFilterComposer get bookshelfId {
    final $$BookshelvesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookshelfId,
      referencedTable: $db.bookshelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelvesTableFilterComposer(
            $db: $db,
            $table: $db.bookshelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookshelfEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $BookshelfEntriesTable> {
  $$BookshelfEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BookshelvesTableOrderingComposer get bookshelfId {
    final $$BookshelvesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookshelfId,
      referencedTable: $db.bookshelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelvesTableOrderingComposer(
            $db: $db,
            $table: $db.bookshelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookshelfEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookshelfEntriesTable> {
  $$BookshelfEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BookshelvesTableAnnotationComposer get bookshelfId {
    final $$BookshelvesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookshelfId,
      referencedTable: $db.bookshelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookshelvesTableAnnotationComposer(
            $db: $db,
            $table: $db.bookshelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookshelfEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookshelfEntriesTable,
          BookshelfEntry,
          $$BookshelfEntriesTableFilterComposer,
          $$BookshelfEntriesTableOrderingComposer,
          $$BookshelfEntriesTableAnnotationComposer,
          $$BookshelfEntriesTableCreateCompanionBuilder,
          $$BookshelfEntriesTableUpdateCompanionBuilder,
          (BookshelfEntry, $$BookshelfEntriesTableReferences),
          BookshelfEntry,
          PrefetchHooks Function({bool bookshelfId, bool bookId})
        > {
  $$BookshelfEntriesTableTableManager(
    _$AppDatabase db,
    $BookshelfEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookshelfEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookshelfEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookshelfEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookshelfId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookshelfEntriesCompanion(
                bookshelfId: bookshelfId,
                bookId: bookId,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookshelfId,
                required String bookId,
                Value<int> sortOrder = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookshelfEntriesCompanion.insert(
                bookshelfId: bookshelfId,
                bookId: bookId,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookshelfEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookshelfId = false, bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookshelfId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookshelfId,
                                referencedTable:
                                    $$BookshelfEntriesTableReferences
                                        ._bookshelfIdTable(db),
                                referencedColumn:
                                    $$BookshelfEntriesTableReferences
                                        ._bookshelfIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$BookshelfEntriesTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$BookshelfEntriesTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookshelfEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookshelfEntriesTable,
      BookshelfEntry,
      $$BookshelfEntriesTableFilterComposer,
      $$BookshelfEntriesTableOrderingComposer,
      $$BookshelfEntriesTableAnnotationComposer,
      $$BookshelfEntriesTableCreateCompanionBuilder,
      $$BookshelfEntriesTableUpdateCompanionBuilder,
      (BookshelfEntry, $$BookshelfEntriesTableReferences),
      BookshelfEntry,
      PrefetchHooks Function({bool bookshelfId, bool bookId})
    >;
typedef $$ExcerptsTableCreateCompanionBuilder =
    ExcerptsCompanion Function({
      required String id,
      required String bookId,
      required String locator,
      required String quote,
      Value<String?> note,
      Value<String> color,
      Value<bool> isDeleted,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ExcerptsTableUpdateCompanionBuilder =
    ExcerptsCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> locator,
      Value<String> quote,
      Value<String?> note,
      Value<String> color,
      Value<bool> isDeleted,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ExcerptsTableReferences
    extends BaseReferences<_$AppDatabase, $ExcerptsTable, ExcerptRecord> {
  $$ExcerptsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('excerpts__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExcerptsTableFilterComposer
    extends Composer<_$AppDatabase, $ExcerptsTable> {
  $$ExcerptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quote => $composableBuilder(
    column: $table.quote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExcerptsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExcerptsTable> {
  $$ExcerptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quote => $composableBuilder(
    column: $table.quote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExcerptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExcerptsTable> {
  $$ExcerptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get locator =>
      $composableBuilder(column: $table.locator, builder: (column) => column);

  GeneratedColumn<String> get quote =>
      $composableBuilder(column: $table.quote, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExcerptsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExcerptsTable,
          ExcerptRecord,
          $$ExcerptsTableFilterComposer,
          $$ExcerptsTableOrderingComposer,
          $$ExcerptsTableAnnotationComposer,
          $$ExcerptsTableCreateCompanionBuilder,
          $$ExcerptsTableUpdateCompanionBuilder,
          (ExcerptRecord, $$ExcerptsTableReferences),
          ExcerptRecord,
          PrefetchHooks Function({bool bookId})
        > {
  $$ExcerptsTableTableManager(_$AppDatabase db, $ExcerptsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExcerptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExcerptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExcerptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> locator = const Value.absent(),
                Value<String> quote = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExcerptsCompanion(
                id: id,
                bookId: bookId,
                locator: locator,
                quote: quote,
                note: note,
                color: color,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String locator,
                required String quote,
                Value<String?> note = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ExcerptsCompanion.insert(
                id: id,
                bookId: bookId,
                locator: locator,
                quote: quote,
                note: note,
                color: color,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExcerptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$ExcerptsTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$ExcerptsTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ExcerptsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExcerptsTable,
      ExcerptRecord,
      $$ExcerptsTableFilterComposer,
      $$ExcerptsTableOrderingComposer,
      $$ExcerptsTableAnnotationComposer,
      $$ExcerptsTableCreateCompanionBuilder,
      $$ExcerptsTableUpdateCompanionBuilder,
      (ExcerptRecord, $$ExcerptsTableReferences),
      ExcerptRecord,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$BookmarksTableCreateCompanionBuilder =
    BookmarksCompanion Function({
      required String id,
      required String bookId,
      required String locator,
      Value<String?> title,
      Value<String?> note,
      Value<bool> isDeleted,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$BookmarksTableUpdateCompanionBuilder =
    BookmarksCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> locator,
      Value<String?> title,
      Value<String?> note,
      Value<bool> isDeleted,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$BookmarksTableReferences
    extends BaseReferences<_$AppDatabase, $BookmarksTable, BookmarkRecord> {
  $$BookmarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('bookmarks__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get locator =>
      $composableBuilder(column: $table.locator, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarksTable,
          BookmarkRecord,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (BookmarkRecord, $$BookmarksTableReferences),
          BookmarkRecord,
          PrefetchHooks Function({bool bookId})
        > {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> locator = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion(
                id: id,
                bookId: bookId,
                locator: locator,
                title: title,
                note: note,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String locator,
                Value<String?> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion.insert(
                id: id,
                bookId: bookId,
                locator: locator,
                title: title,
                note: note,
                isDeleted: isDeleted,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookmarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$BookmarksTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$BookmarksTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarksTable,
      BookmarkRecord,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (BookmarkRecord, $$BookmarksTableReferences),
      BookmarkRecord,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ReadingProgressesTableCreateCompanionBuilder =
    ReadingProgressesCompanion Function({
      required String bookId,
      required String locator,
      required double progress,
      Value<String?> chapterTitle,
      Value<int?> page,
      required String deviceId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReadingProgressesTableUpdateCompanionBuilder =
    ReadingProgressesCompanion Function({
      Value<String> bookId,
      Value<String> locator,
      Value<double> progress,
      Value<String?> chapterTitle,
      Value<int?> page,
      Value<String> deviceId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ReadingProgressesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReadingProgressesTable,
          ReadingProgressRecord
        > {
  $$ReadingProgressesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reading_progresses__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingProgressesTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressesTable> {
  $$ReadingProgressesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressesTable> {
  $$ReadingProgressesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressesTable> {
  $$ReadingProgressesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get locator =>
      $composableBuilder(column: $table.locator, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressesTable,
          ReadingProgressRecord,
          $$ReadingProgressesTableFilterComposer,
          $$ReadingProgressesTableOrderingComposer,
          $$ReadingProgressesTableAnnotationComposer,
          $$ReadingProgressesTableCreateCompanionBuilder,
          $$ReadingProgressesTableUpdateCompanionBuilder,
          (ReadingProgressRecord, $$ReadingProgressesTableReferences),
          ReadingProgressRecord,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingProgressesTableTableManager(
    _$AppDatabase db,
    $ReadingProgressesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingProgressesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingProgressesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> locator = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String?> chapterTitle = const Value.absent(),
                Value<int?> page = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressesCompanion(
                bookId: bookId,
                locator: locator,
                progress: progress,
                chapterTitle: chapterTitle,
                page: page,
                deviceId: deviceId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String locator,
                required double progress,
                Value<String?> chapterTitle = const Value.absent(),
                Value<int?> page = const Value.absent(),
                required String deviceId,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressesCompanion.insert(
                bookId: bookId,
                locator: locator,
                progress: progress,
                chapterTitle: chapterTitle,
                page: page,
                deviceId: deviceId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReadingProgressesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$ReadingProgressesTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$ReadingProgressesTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingProgressesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressesTable,
      ReadingProgressRecord,
      $$ReadingProgressesTableFilterComposer,
      $$ReadingProgressesTableOrderingComposer,
      $$ReadingProgressesTableAnnotationComposer,
      $$ReadingProgressesTableCreateCompanionBuilder,
      $$ReadingProgressesTableUpdateCompanionBuilder,
      (ReadingProgressRecord, $$ReadingProgressesTableReferences),
      ReadingProgressRecord,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ReadingProgressHistoryTableCreateCompanionBuilder =
    ReadingProgressHistoryCompanion Function({
      required String operationId,
      required String bookId,
      required String locator,
      required double progress,
      Value<String?> chapterTitle,
      Value<int?> page,
      required String deviceId,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReadingProgressHistoryTableUpdateCompanionBuilder =
    ReadingProgressHistoryCompanion Function({
      Value<String> operationId,
      Value<String> bookId,
      Value<String> locator,
      Value<double> progress,
      Value<String?> chapterTitle,
      Value<int?> page,
      Value<String> deviceId,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ReadingProgressHistoryTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReadingProgressHistoryTable,
          ReadingProgressHistoryRecord
        > {
  $$ReadingProgressHistoryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reading_progress_history__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingProgressHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressHistoryTable> {
  $$ReadingProgressHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressHistoryTable> {
  $$ReadingProgressHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressHistoryTable> {
  $$ReadingProgressHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locator =>
      $composableBuilder(column: $table.locator, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressHistoryTable,
          ReadingProgressHistoryRecord,
          $$ReadingProgressHistoryTableFilterComposer,
          $$ReadingProgressHistoryTableOrderingComposer,
          $$ReadingProgressHistoryTableAnnotationComposer,
          $$ReadingProgressHistoryTableCreateCompanionBuilder,
          $$ReadingProgressHistoryTableUpdateCompanionBuilder,
          (
            ReadingProgressHistoryRecord,
            $$ReadingProgressHistoryTableReferences,
          ),
          ReadingProgressHistoryRecord,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingProgressHistoryTableTableManager(
    _$AppDatabase db,
    $ReadingProgressHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressHistoryTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReadingProgressHistoryTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReadingProgressHistoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> locator = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String?> chapterTitle = const Value.absent(),
                Value<int?> page = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressHistoryCompanion(
                operationId: operationId,
                bookId: bookId,
                locator: locator,
                progress: progress,
                chapterTitle: chapterTitle,
                page: page,
                deviceId: deviceId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String bookId,
                required String locator,
                required double progress,
                Value<String?> chapterTitle = const Value.absent(),
                Value<int?> page = const Value.absent(),
                required String deviceId,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressHistoryCompanion.insert(
                operationId: operationId,
                bookId: bookId,
                locator: locator,
                progress: progress,
                chapterTitle: chapterTitle,
                page: page,
                deviceId: deviceId,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReadingProgressHistoryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$ReadingProgressHistoryTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$ReadingProgressHistoryTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingProgressHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressHistoryTable,
      ReadingProgressHistoryRecord,
      $$ReadingProgressHistoryTableFilterComposer,
      $$ReadingProgressHistoryTableOrderingComposer,
      $$ReadingProgressHistoryTableAnnotationComposer,
      $$ReadingProgressHistoryTableCreateCompanionBuilder,
      $$ReadingProgressHistoryTableUpdateCompanionBuilder,
      (ReadingProgressHistoryRecord, $$ReadingProgressHistoryTableReferences),
      ReadingProgressHistoryRecord,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$SyncOperationsTableCreateCompanionBuilder =
    SyncOperationsCompanion Function({
      required String operationId,
      required String deviceId,
      required String entityType,
      required String entityId,
      required String kind,
      Value<String?> payloadJson,
      required DateTime occurredAt,
      Value<DateTime?> appliedAt,
      Value<int> rowid,
    });
typedef $$SyncOperationsTableUpdateCompanionBuilder =
    SyncOperationsCompanion Function({
      Value<String> operationId,
      Value<String> deviceId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> kind,
      Value<String?> payloadJson,
      Value<DateTime> occurredAt,
      Value<DateTime?> appliedAt,
      Value<int> rowid,
    });

class $$SyncOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get appliedAt =>
      $composableBuilder(column: $table.appliedAt, builder: (column) => column);
}

class $$SyncOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOperationsTable,
          SyncOperationRecord,
          $$SyncOperationsTableFilterComposer,
          $$SyncOperationsTableOrderingComposer,
          $$SyncOperationsTableAnnotationComposer,
          $$SyncOperationsTableCreateCompanionBuilder,
          $$SyncOperationsTableUpdateCompanionBuilder,
          (
            SyncOperationRecord,
            BaseReferences<
              _$AppDatabase,
              $SyncOperationsTable,
              SyncOperationRecord
            >,
          ),
          SyncOperationRecord,
          PrefetchHooks Function()
        > {
  $$SyncOperationsTableTableManager(
    _$AppDatabase db,
    $SyncOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<DateTime?> appliedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOperationsCompanion(
                operationId: operationId,
                deviceId: deviceId,
                entityType: entityType,
                entityId: entityId,
                kind: kind,
                payloadJson: payloadJson,
                occurredAt: occurredAt,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String deviceId,
                required String entityType,
                required String entityId,
                required String kind,
                Value<String?> payloadJson = const Value.absent(),
                required DateTime occurredAt,
                Value<DateTime?> appliedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOperationsCompanion.insert(
                operationId: operationId,
                deviceId: deviceId,
                entityType: entityType,
                entityId: entityId,
                kind: kind,
                payloadJson: payloadJson,
                occurredAt: occurredAt,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOperationsTable,
      SyncOperationRecord,
      $$SyncOperationsTableFilterComposer,
      $$SyncOperationsTableOrderingComposer,
      $$SyncOperationsTableAnnotationComposer,
      $$SyncOperationsTableCreateCompanionBuilder,
      $$SyncOperationsTableUpdateCompanionBuilder,
      (
        SyncOperationRecord,
        BaseReferences<
          _$AppDatabase,
          $SyncOperationsTable,
          SyncOperationRecord
        >,
      ),
      SyncOperationRecord,
      PrefetchHooks Function()
    >;
typedef $$AuditEventsTableCreateCompanionBuilder =
    AuditEventsCompanion Function({
      required String id,
      required String caller,
      required String action,
      required String parametersJson,
      required String result,
      required DateTime occurredAt,
      Value<int> rowid,
    });
typedef $$AuditEventsTableUpdateCompanionBuilder =
    AuditEventsCompanion Function({
      Value<String> id,
      Value<String> caller,
      Value<String> action,
      Value<String> parametersJson,
      Value<String> result,
      Value<DateTime> occurredAt,
      Value<int> rowid,
    });

class $$AuditEventsTableFilterComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caller => $composableBuilder(
    column: $table.caller,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parametersJson => $composableBuilder(
    column: $table.parametersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caller => $composableBuilder(
    column: $table.caller,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parametersJson => $composableBuilder(
    column: $table.parametersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditEventsTable> {
  $$AuditEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get caller =>
      $composableBuilder(column: $table.caller, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get parametersJson => $composableBuilder(
    column: $table.parametersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );
}

class $$AuditEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditEventsTable,
          AuditEventRecord,
          $$AuditEventsTableFilterComposer,
          $$AuditEventsTableOrderingComposer,
          $$AuditEventsTableAnnotationComposer,
          $$AuditEventsTableCreateCompanionBuilder,
          $$AuditEventsTableUpdateCompanionBuilder,
          (
            AuditEventRecord,
            BaseReferences<_$AppDatabase, $AuditEventsTable, AuditEventRecord>,
          ),
          AuditEventRecord,
          PrefetchHooks Function()
        > {
  $$AuditEventsTableTableManager(_$AppDatabase db, $AuditEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> caller = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> parametersJson = const Value.absent(),
                Value<String> result = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuditEventsCompanion(
                id: id,
                caller: caller,
                action: action,
                parametersJson: parametersJson,
                result: result,
                occurredAt: occurredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String caller,
                required String action,
                required String parametersJson,
                required String result,
                required DateTime occurredAt,
                Value<int> rowid = const Value.absent(),
              }) => AuditEventsCompanion.insert(
                id: id,
                caller: caller,
                action: action,
                parametersJson: parametersJson,
                result: result,
                occurredAt: occurredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditEventsTable,
      AuditEventRecord,
      $$AuditEventsTableFilterComposer,
      $$AuditEventsTableOrderingComposer,
      $$AuditEventsTableAnnotationComposer,
      $$AuditEventsTableCreateCompanionBuilder,
      $$AuditEventsTableUpdateCompanionBuilder,
      (
        AuditEventRecord,
        BaseReferences<_$AppDatabase, $AuditEventsTable, AuditEventRecord>,
      ),
      AuditEventRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$BookshelvesTableTableManager get bookshelves =>
      $$BookshelvesTableTableManager(_db, _db.bookshelves);
  $$BookshelfEntriesTableTableManager get bookshelfEntries =>
      $$BookshelfEntriesTableTableManager(_db, _db.bookshelfEntries);
  $$ExcerptsTableTableManager get excerpts =>
      $$ExcerptsTableTableManager(_db, _db.excerpts);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$ReadingProgressesTableTableManager get readingProgresses =>
      $$ReadingProgressesTableTableManager(_db, _db.readingProgresses);
  $$ReadingProgressHistoryTableTableManager get readingProgressHistory =>
      $$ReadingProgressHistoryTableTableManager(
        _db,
        _db.readingProgressHistory,
      );
  $$SyncOperationsTableTableManager get syncOperations =>
      $$SyncOperationsTableTableManager(_db, _db.syncOperations);
  $$AuditEventsTableTableManager get auditEvents =>
      $$AuditEventsTableTableManager(_db, _db.auditEvents);
}
