import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/folder.dart';
import '../models/photo.dart';
import '../models/tag.dart';
import '../models/comment.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('photonote.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add reaction column to photos table
      await db.execute('ALTER TABLE photos ADD COLUMN reaction TEXT');
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        imagePath TEXT NOT NULL,
        folderId INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        reaction TEXT,
        FOREIGN KEY (folderId) REFERENCES folders (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE photo_tags (
        photoId INTEGER NOT NULL,
        tagId INTEGER NOT NULL,
        PRIMARY KEY (photoId, tagId),
        FOREIGN KEY (photoId) REFERENCES photos (id) ON DELETE CASCADE,
        FOREIGN KEY (tagId) REFERENCES tags (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE comments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        photoId INTEGER NOT NULL,
        text TEXT NOT NULL,
        username TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (photoId) REFERENCES photos (id) ON DELETE CASCADE
      )
    ''');
  }

  // Folder operations
  Future<int> createFolder(Folder folder) async {
    final db = await database;
    return await db.insert('folders', folder.toMap());
  }

  Future<List<Folder>> getAllFolders() async {
    final db = await database;
    final result = await db.query('folders', orderBy: 'name ASC');
    return result.map((map) => Folder.fromMap(map)).toList();
  }

  Future<void> renameFolder(int folderId, String newName) async {
    final db = await database;
    await db.update(
      'folders',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }

  Future<void> deleteFolder(int folderId) async {
    final db = await database;
    // Delete all photos in this folder (cascade)
    final photos = await db.query('photos', where: 'folderId = ?', whereArgs: [folderId]);
    for (var photo in photos) {
      await deletePhoto(photo['id'] as int);
    }
    // Delete the folder
    await db.delete('folders', where: 'id = ?', whereArgs: [folderId]);
  }

  // Tag operations
  Future<int> createTag(Tag tag) async {
    final db = await database;
    return await db.insert('tags', tag.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<Tag?> getTagByName(String name) async {
    final db = await database;
    final result = await db.query('tags', where: 'name = ?', whereArgs: [name]);
    if (result.isEmpty) return null;
    return Tag.fromMap(result.first);
  }

  Future<List<Tag>> getAllTags() async {
    final db = await database;
    final result = await db.query('tags', orderBy: 'name ASC');
    return result.map((map) => Tag.fromMap(map)).toList();
  }

  Future<List<Tag>> getTagsInFolder(int folderId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT tags.*
      FROM tags
      INNER JOIN photo_tags ON tags.id = photo_tags.tagId
      INNER JOIN photos ON photo_tags.photoId = photos.id
      WHERE photos.folderId = ?
      ORDER BY tags.name ASC
    ''', [folderId]);
    return result.map((map) => Tag.fromMap(map)).toList();
  }

  Future<void> deleteTag(int tagId) async {
    final db = await database;
    // Delete all photo-tag associations
    await db.delete('photo_tags', where: 'tagId = ?', whereArgs: [tagId]);
    // Delete the tag
    await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
  }

  // Photo operations
  Future<int> createPhoto(Photo photo) async {
    final db = await database;
    return await db.insert('photos', photo.toMap());
  }

  Future<String> copyPhotoToPermanentStorage(String sourcePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(join(appDir.path, 'photos'));
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      final sourceFile = File(sourcePath);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${basename(sourcePath)}';
      final destPath = join(photosDir.path, fileName);

      await sourceFile.copy(destPath);
      return destPath;
    } catch (e) {
      // If copy fails, return original path as fallback
      return sourcePath;
    }
  }

  Future<void> deletePhoto(int photoId) async {
    final db = await database;
    // Delete all comments for this photo
    await db.delete('comments', where: 'photoId = ?', whereArgs: [photoId]);
    // Delete all tag associations
    await db.delete('photo_tags', where: 'photoId = ?', whereArgs: [photoId]);
    // Delete the photo
    await db.delete('photos', where: 'id = ?', whereArgs: [photoId]);
  }

  Future<void> updateAllPhotoPaths(String newPhotosDirectory) async {
    final db = await database;
    final photos = await db.query('photos');

    for (var photo in photos) {
      final oldPath = photo['imagePath'] as String;
      final fileName = oldPath.split('/').last;
      final newPath = '$newPhotosDirectory/$fileName';

      await db.update(
        'photos',
        {'imagePath': newPath},
        where: 'id = ?',
        whereArgs: [photo['id']],
      );
    }
  }

  Future<void> addTagsToPhoto(int photoId, List<int> tagIds) async {
    final db = await database;
    for (var tagId in tagIds) {
      await db.insert('photo_tags', {'photoId': photoId, 'tagId': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> removeTagFromPhoto(int photoId, int tagId) async {
    final db = await database;
    await db.delete(
      'photo_tags',
      where: 'photoId = ? AND tagId = ?',
      whereArgs: [photoId, tagId],
    );
  }

  Future<void> updatePhotoFolder(int photoId, int newFolderId) async {
    final db = await database;
    await db.update(
      'photos',
      {'folderId': newFolderId},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  Future<void> updatePhotoPath(int photoId, String newPath) async {
    final db = await database;
    await db.update(
      'photos',
      {'imagePath': newPath},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  Future<void> updatePhotoReaction(int photoId, String? reaction) async {
    final db = await database;
    await db.update(
      'photos',
      {'reaction': reaction},
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  Future<List<Tag>> getPhotoTags(int photoId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT tags.* FROM tags
      INNER JOIN photo_tags ON tags.id = photo_tags.tagId
      WHERE photo_tags.photoId = ?
    ''', [photoId]);
    return result.map((map) => Tag.fromMap(map)).toList();
  }

  Future<List<Map<String, dynamic>>> searchPhotosByTags(List<String> tagNames) async {
    final db = await database;
    final placeholders = List.filled(tagNames.length, '?').join(',');
    final result = await db.rawQuery('''
      SELECT DISTINCT photos.*, folders.name as folderName
      FROM photos
      INNER JOIN folders ON photos.folderId = folders.id
      INNER JOIN photo_tags ON photos.id = photo_tags.photoId
      INNER JOIN tags ON photo_tags.tagId = tags.id
      WHERE tags.name IN ($placeholders)
      ORDER BY photos.createdAt DESC
    ''', tagNames);
    return result;
  }

  Future<List<Map<String, dynamic>>> getAllPhotosWithFolder() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT photos.*, folders.name as folderName
      FROM photos
      INNER JOIN folders ON photos.folderId = folders.id
      ORDER BY photos.createdAt DESC
    ''');
    return result;
  }

  Future<Photo?> getPhotoById(int photoId) async {
    final db = await database;
    final result = await db.query('photos', where: 'id = ?', whereArgs: [photoId]);
    if (result.isEmpty) return null;
    return Photo.fromMap(result.first);
  }

  Future<Map<String, dynamic>?> getPhotoWithReaction(int photoId) async {
    final db = await database;
    final result = await db.query('photos', where: 'id = ?', whereArgs: [photoId]);
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<List<Map<String, dynamic>>> getPhotosByFolder(int folderId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT photos.*, folders.name as folderName
      FROM photos
      INNER JOIN folders ON photos.folderId = folders.id
      WHERE photos.folderId = ?
      ORDER BY photos.createdAt DESC
    ''', [folderId]);
    return result;
  }

  Future<List<Map<String, dynamic>>> searchPhotosByTagsInFolder(
    int folderId,
    List<String> tagNames,
  ) async {
    final db = await database;
    final placeholders = List.filled(tagNames.length, '?').join(',');
    final result = await db.rawQuery('''
      SELECT DISTINCT photos.*, folders.name as folderName
      FROM photos
      INNER JOIN folders ON photos.folderId = folders.id
      INNER JOIN photo_tags ON photos.id = photo_tags.photoId
      INNER JOIN tags ON photo_tags.tagId = tags.id
      WHERE photos.folderId = ? AND tags.name IN ($placeholders)
      ORDER BY photos.createdAt DESC
    ''', [folderId, ...tagNames]);
    return result;
  }

  // Comment operations
  Future<int> createComment(Comment comment) async {
    final db = await database;
    return await db.insert('comments', comment.toMap());
  }

  Future<List<Comment>> getPhotoComments(int photoId) async {
    final db = await database;
    final result = await db.query(
      'comments',
      where: 'photoId = ?',
      whereArgs: [photoId],
      orderBy: 'createdAt DESC',
    );
    return result.map((map) => Comment.fromMap(map)).toList();
  }

  Future<void> deleteComment(int commentId) async {
    final db = await database;
    await db.delete('comments', where: 'id = ?', whereArgs: [commentId]);
  }

  // Helper methods for backup/restore
  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'photonote.db');
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
