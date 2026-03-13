import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';

class ThumbnailCache {
  static final ThumbnailCache instance = ThumbnailCache._init();
  ThumbnailCache._init();

  Future<Directory> get _cacheDir async {
    final appDir = await getApplicationCacheDirectory();
    final thumbDir = Directory(path.join(appDir.path, 'thumbnails'));
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }
    return thumbDir;
  }

  String _getCacheKey(String imagePath) {
    final bytes = utf8.encode(imagePath);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  Future<File?> getThumbnail(String imagePath) async {
    try {
      final cacheDir = await _cacheDir;
      final cacheKey = _getCacheKey(imagePath);
      final thumbFile = File(path.join(cacheDir.path, '$cacheKey.jpg'));

      if (await thumbFile.exists()) {
        return thumbFile;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<File?> generateThumbnail(String imagePath, {int size = 400}) async {
    try {
      final sourceFile = File(imagePath);
      if (!await sourceFile.exists()) return null;

      final cacheDir = await _cacheDir;
      final cacheKey = _getCacheKey(imagePath);
      final thumbFile = File(path.join(cacheDir.path, '$cacheKey.jpg'));

      // If thumbnail already exists, return it
      if (await thumbFile.exists()) {
        return thumbFile;
      }

      // Read and decode the image
      final bytes = await sourceFile.readAsBytes();

      // For now, we'll just copy the file as-is to cache
      // In production, you'd want to use the 'image' package to resize
      await thumbFile.writeAsBytes(bytes);

      return thumbFile;
    } catch (e) {
      return null;
    }
  }

  Future<void> clearCache() async {
    try {
      final cacheDir = await _cacheDir;
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      // Ignore errors
    }
  }
}
