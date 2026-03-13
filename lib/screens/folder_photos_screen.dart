import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../services/thumbnail_cache.dart';
import '../models/folder.dart';
import '../models/tag.dart';
import 'photo_detail_screen.dart';
import 'add_photos_screen.dart';

class FolderPhotosScreen extends StatefulWidget {
  final Folder folder;

  const FolderPhotosScreen({
    super.key,
    required this.folder,
  });

  @override
  State<FolderPhotosScreen> createState() => _FolderPhotosScreenState();
}

class _FolderPhotosScreenState extends State<FolderPhotosScreen> {
  List<Map<String, dynamic>> _photos = [];
  List<Tag> _allTags = [];
  List<String> _selectedTags = [];
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  // Selection mode
  bool _isSelectionMode = false;
  final Set<int> _selectedPhotoIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final tags = await DatabaseService.instance.getTagsInFolder(widget.folder.id!);
    final photos = _selectedTags.isEmpty
        ? await DatabaseService.instance.getPhotosByFolder(widget.folder.id!)
        : await DatabaseService.instance.searchPhotosByTagsInFolder(
            widget.folder.id!,
            _selectedTags,
          );

    setState(() {
      _allTags = tags;
      _photos = photos;
      _isLoading = false;
    });
  }

  void _toggleTag(String tagName) {
    setState(() {
      if (_selectedTags.contains(tagName)) {
        _selectedTags.remove(tagName);
      } else {
        _selectedTags.add(tagName);
      }
    });
    _loadData();
  }

  void _toggleSelection(int photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
        if (_selectedPhotoIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  void _enterSelectionMode(int photoId) {
    setState(() {
      _isSelectionMode = true;
      _selectedPhotoIds.add(photoId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedPhotoIds.clear();
    });
  }

  Future<void> _batchDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photos'),
        content: Text('Delete ${_selectedPhotoIds.length} selected photos?\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (var photoId in _selectedPhotoIds) {
        await DatabaseService.instance.deletePhoto(photoId);
      }
      _exitSelectionMode();
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${_selectedPhotoIds.length} photos')),
        );
      }
    }
  }

  Future<void> _batchAddTag() async {
    final controller = TextEditingController();
    final tagName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Tag to ${_selectedPhotoIds.length} Photos'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tag name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (tagName != null && tagName.trim().isNotEmpty) {
      // Get or create tag
      var tag = await DatabaseService.instance.getTagByName(tagName.trim());
      if (tag == null) {
        final id = await DatabaseService.instance.createTag(Tag(name: tagName.trim()));
        tag = Tag(id: id, name: tagName.trim());
      }

      // Add tag to all selected photos
      for (var photoId in _selectedPhotoIds) {
        await DatabaseService.instance.addTagsToPhoto(photoId, [tag.id!]);
      }

      _exitSelectionMode();
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added tag "$tagName" to ${_selectedPhotoIds.length} photos')),
        );
      }
    }
  }

  Future<void> _renameFolder() async {
    final controller = TextEditingController(text: widget.folder.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && newName != widget.folder.name) {
      await DatabaseService.instance.renameFolder(widget.folder.id!, newName.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to "$newName"')),
        );
        // Pop back to refresh the folder list
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _deleteFolder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Delete "${widget.folder.name}" and all its photos?\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.instance.deleteFolder(widget.folder.id!);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
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
            builder: (context) => AddPhotosScreen(
              initialImages: images,
              preselectedFolder: widget.folder,
            ),
          ),
        );
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _exitSelectionMode();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isSelectionMode
              ? '${_selectedPhotoIds.length} selected'
              : widget.folder.name),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                )
              : null,
          actions: _isSelectionMode
              ? [
                  IconButton(
                    icon: const Icon(Icons.label),
                    tooltip: 'Add Tag',
                    onPressed: _batchAddTag,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete',
                    onPressed: _batchDelete,
                  ),
                ]
              : [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Rename Folder',
                    onPressed: _renameFolder,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete Folder',
                    onPressed: _deleteFolder,
                  ),
                ],
        ),
        body: Column(
          children: [
            if (_allTags.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _allTags.length,
                  itemBuilder: (context, index) {
                    final tag = _allTags[index];
                    final isSelected = _selectedTags.contains(tag.name);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(tag.name),
                        selected: isSelected,
                        onSelected: (_) => _toggleTag(tag.name),
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _photos.isEmpty
                      ? Center(
                          child: Text(
                            _selectedTags.isEmpty
                                ? 'No photos in this folder'
                                : 'No photos match selected tags',
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _photos.length,
                          itemBuilder: (context, index) {
                          final photo = _photos[index];
                          final photoId = photo['id'] as int;
                          final isSelected = _selectedPhotoIds.contains(photoId);

                          return GestureDetector(
                            onTap: () async {
                              if (_isSelectionMode) {
                                _toggleSelection(photoId);
                              } else {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PhotoDetailScreen(
                                      photoId: photoId,
                                      imagePath: photo['imagePath'],
                                      allPhotos: _photos,
                                      currentIndex: index,
                                    ),
                                  ),
                                );
                                _loadData();
                              }
                            },
                            onLongPress: () {
                              if (!_isSelectionMode) {
                                _enterSelectionMode(photoId);
                              }
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: FutureBuilder<File?>(
                                    future: ThumbnailCache.instance.getThumbnail(photo['imagePath']),
                                    builder: (context, snapshot) {
                                      File imageFile;

                                      if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                                        imageFile = snapshot.data!;
                                      } else {
                                        ThumbnailCache.instance.generateThumbnail(photo['imagePath']);
                                        imageFile = File(photo['imagePath']);
                                      }

                                      return Image.file(
                                        imageFile,
                                        fit: BoxFit.cover,
                                        cacheWidth: 400,
                                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                          if (wasSynchronouslyLoaded) return child;
                                          return AnimatedOpacity(
                                            opacity: frame == null ? 0 : 1,
                                            duration: const Duration(milliseconds: 300),
                                            child: frame == null
                                                ? Container(
                                                    color: Colors.grey.shade200,
                                                    child: Center(
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.grey.shade400,
                                                      ),
                                                    ),
                                                  )
                                                : child,
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey.shade300,
                                            child: Icon(
                                              Icons.broken_image,
                                              color: Colors.grey.shade600,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                if (_isSelectionMode)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.blue.withOpacity(0.3)
                                            : Colors.black.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                if (_isSelectionMode)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.blue : Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected ? Colors.blue : Colors.grey,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        isSelected ? Icons.check : null,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                if (!_isSelectionMode && photo['reaction'] != null)
                                  Positioned(
                                    bottom: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.2),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        photo['reaction'],
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
        ),
        floatingActionButton: _isSelectionMode
            ? null
            : FloatingActionButton(
                onPressed: _showImageSourceDialog,
                child: const Icon(Icons.add_a_photo),
              ),
      ),
    );
  }
}
