import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import '../services/database_service.dart';
import '../models/folder.dart';
import 'folder_photos_screen.dart';
import 'add_photos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Folder> _folders = [];
  Map<int, int> _folderPhotoCounts = {};
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    final folders = await DatabaseService.instance.getAllFolders();

    final photoCounts = <int, int>{};
    for (var folder in folders) {
      final photos = await DatabaseService.instance.getPhotosByFolder(folder.id!);
      photoCounts[folder.id!] = photos.length;
    }

    setState(() {
      _folders = folders;
      _folderPhotoCounts = photoCounts;
      _isLoading = false;
    });
  }

  Future<void> _showImageSourceDialog() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Photos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      List<XFile> images = [];
      if (source == ImageSource.camera) {
        final image = await _picker.pickImage(source: ImageSource.camera);
        if (image != null) {
          images = [image];
        }
      } else {
        images = await _picker.pickMultiImage();
      }

      if (images.isNotEmpty && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddPhotosScreen(initialImages: images),
          ),
        );
        _loadFolders();
      }
    }
  }

  Future<void> _exportData() async {
    try {
      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Exporting data...'),
            ],
          ),
        ),
      );

      // Create temporary directory for backup
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupDir = Directory('${tempDir.path}/PhotoNote_Backup_$timestamp');
      await backupDir.create(recursive: true);

      // Copy database file
      final dbPath = await DatabaseService.instance.getDatabasePath();
      final dbFile = File(dbPath);
      final dbBytes = await dbFile.readAsBytes();
      await File('${backupDir.path}/photo_note.db').writeAsBytes(dbBytes);

      // Create photos directory in backup
      final photosBackupDir = Directory('${backupDir.path}/photos');
      await photosBackupDir.create();

      // Get all photos from database
      final folders = await DatabaseService.instance.getAllFolders();
      int photoCount = 0;
      for (var folder in folders) {
        final photos = await DatabaseService.instance.getPhotosByFolder(folder.id!);
        for (var photo in photos) {
          final photoFile = File(photo['imagePath']);
          if (await photoFile.exists()) {
            final fileName = photoFile.path.split('/').last;
            final photoBytes = await photoFile.readAsBytes();
            await File('${photosBackupDir.path}/$fileName').writeAsBytes(photoBytes);
            photoCount++;
          }
        }
      }

      // Create zip file with flat structure
      final zipFilePath = '${tempDir.path}/PhotoNote_Backup_$timestamp.zip';
      final encoder = ZipFileEncoder();
      encoder.create(zipFilePath);

      // Add database file at root level
      encoder.addFile(File('${backupDir.path}/photo_note.db'), 'photo_note.db');

      // Add photos directory
      final photosFiles = await photosBackupDir.list().toList();
      for (var entity in photosFiles) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          encoder.addFile(entity, 'photos/$fileName');
        }
      }

      encoder.close();

      // Read zip file bytes
      final zipFile = File(zipFilePath);
      final zipBytes = await zipFile.readAsBytes();

      // Let user choose where to save the zip file
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup file',
        fileName: 'PhotoNote_Backup_$timestamp.zip',
        bytes: zipBytes,
      );

      // Clean up temp files
      await backupDir.delete(recursive: true);
      await zipFile.delete();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        if (outputPath != null) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Export Successful'),
              content: Text('Exported $photoCount photos and database to:\nPhotoNote_Backup_$timestamp.zip'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Export Failed'),
            content: Text('Error: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _importData() async {
    try {
      // Let user select the backup zip file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select PhotoNote backup file',
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final pickedFile = result.files.first;
      if (pickedFile.path == null) {
        throw Exception('Could not access selected file');
      }

      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Importing data...'),
            ],
          ),
        ),
      );

      // Read zip file
      final zipFile = File(pickedFile.path!);
      final zipBytes = await zipFile.readAsBytes();

      // Extract to temporary directory
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/restore_temp');
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      // Decode and extract zip
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File('${extractDir.path}/$filename');
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }

      // Check if database file exists at root level
      final backupDbFile = File('${extractDir.path}/photo_note.db');
      if (!await backupDbFile.exists()) {
        throw Exception('Database file not found in backup');
      }

      // Read database file
      final dbBytes = await backupDbFile.readAsBytes();

      // Get app's document directory for photos
      final appDocDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDocDir.path}/photos');
      await photosDir.create(recursive: true);

      // Copy photos from backup (they're in photos/ subdirectory)
      final photosBackupDir = Directory('${extractDir.path}/photos');
      int photoCount = 0;
      if (await photosBackupDir.exists()) {
        final photoFiles = await photosBackupDir.list().toList();
        for (var entity in photoFiles) {
          if (entity is File) {
            final fileName = entity.path.split('/').last;
            final targetFile = File('${photosDir.path}/$fileName');
            // Skip if file already exists
            if (!await targetFile.exists()) {
              final photoBytes = await entity.readAsBytes();
              await targetFile.writeAsBytes(photoBytes);
              photoCount++;
            }
          }
        }
      }

      // Close database and wait to ensure it's fully closed
      await DatabaseService.instance.close();
      await Future.delayed(const Duration(milliseconds: 500));

      // Get database path
      final dbPath = await DatabaseService.instance.getDatabasePath();
      final dbFile = File(dbPath);

      // Delete old database file if it exists
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      // Write database bytes to target location
      await dbFile.writeAsBytes(dbBytes);

      // Reinitialize database
      await DatabaseService.instance.database;

      // Update all photo paths to point to the new location
      await DatabaseService.instance.updateAllPhotoPaths(photosDir.path);

      // Clean up temp files
      await extractDir.delete(recursive: true);

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Successful'),
            content: Text('Restored database and $photoCount photos successfully.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadFolders(); // Reload data
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if open
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Failed'),
            content: Text('Error: $e\n\nMake sure you selected a valid PhotoNote backup zip file.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Note'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') {
                _exportData();
              } else if (value == 'import') {
                _importData();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.upload_file),
                    SizedBox(width: 8),
                    Text('Export'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 8),
                    Text('Import'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? const Center(
                  child: Text(
                    'No folders yet\nTap + to add photos',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _folders.length,
                  itemBuilder: (context, index) {
                    final folder = _folders[index];
                    final photoCount = _folderPhotoCounts[folder.id] ?? 0;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(
                            Icons.folder,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        title: Text(
                          folder.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          '$photoCount ${photoCount == 1 ? 'photo' : 'photos'}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final deleted = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FolderPhotosScreen(
                                folder: folder,
                              ),
                            ),
                          );
                          if (deleted == true || mounted) {
                            _loadFolders();
                          }
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showImageSourceDialog,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
