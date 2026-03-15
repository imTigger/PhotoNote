import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/database_service.dart';
import '../models/folder.dart';
import '../models/photo.dart';
import '../models/tag.dart';
import '../models/comment.dart';

class AddPhotosScreen extends StatefulWidget {
  final List<XFile>? initialImages;
  final Folder? preselectedFolder;

  const AddPhotosScreen({
    super.key,
    this.initialImages,
    this.preselectedFolder,
  });

  @override
  State<AddPhotosScreen> createState() => _AddPhotosScreenState();
}

class _AddPhotosScreenState extends State<AddPhotosScreen> {
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedImages = [];
  List<Folder> _folders = [];
  Folder? _selectedFolder;
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _batchTagController = TextEditingController();
  final List<String> _batchTags = [];
  int _currentPhotoIndex = 0;
  final Map<int, String> _photoComments = {};
  final Map<int, List<String>> _photoTags = {};
  final Map<int, String?> _photoReactions = {};
  final TextEditingController _commentController = TextEditingController();
  bool _isProcessing = false;

  static const List<String> _availableReactions = ['👍🏻', '👎🏻', '✅', '❌', '🤣', '😍'];

  @override
  void initState() {
    super.initState();
    if (widget.initialImages != null) {
      _selectedImages = widget.initialImages!;
    }
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final folders = await DatabaseService.instance.getAllFolders();
    setState(() {
      _folders = folders;
      // If we have a preselected folder, find it in the loaded list by ID
      if (widget.preselectedFolder != null) {
        _selectedFolder = _folders.firstWhere(
          (f) => f.id == widget.preselectedFolder!.id,
          orElse: () => _folders.isNotEmpty ? _folders.first : widget.preselectedFolder!,
        );
      }
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
      if (source == ImageSource.camera) {
        await _takePhoto();
      } else {
        await _pickImages();
      }
    }
  }

  Future<void> _takePhoto() async {
    final image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImages = [..._selectedImages, image];
      });
    }
  }

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage();
    setState(() {
      _selectedImages = [..._selectedImages, ...images];
    });
  }

  void _addBatchTag() {
    final tag = _batchTagController.text.trim();
    if (tag.isNotEmpty && !_batchTags.contains(tag)) {
      setState(() {
        _batchTags.add(tag);
        _batchTagController.clear();
      });
    }
  }

  void _removeBatchTag(String tag) {
    setState(() {
      _batchTags.remove(tag);
    });
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    final currentTags = _photoTags[_currentPhotoIndex] ?? [];
    if (tag.isNotEmpty && !currentTags.contains(tag)) {
      setState(() {
        _photoTags[_currentPhotoIndex] = [...currentTags, tag];
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    final currentTags = _photoTags[_currentPhotoIndex] ?? [];
    setState(() {
      _photoTags[_currentPhotoIndex] = currentTags.where((t) => t != tag).toList();
    });
  }

  void _setReaction(String reaction) {
    setState(() {
      final currentReaction = _photoReactions[_currentPhotoIndex];
      if (currentReaction == reaction) {
        // Remove reaction if tapping the same one
        _photoReactions[_currentPhotoIndex] = null;
      } else {
        _photoReactions[_currentPhotoIndex] = reaction;
      }
    });
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final folder = Folder(
        name: result,
        createdAt: DateTime.now(),
      );
      final id = await DatabaseService.instance.createFolder(folder);
      await _loadFolders();
      setState(() {
        _selectedFolder = _folders.firstWhere((f) => f.id == id);
      });
    }
  }

  void _saveCurrentPhotoData() {
    final comment = _commentController.text.trim();
    if (comment.isNotEmpty) {
      _photoComments[_currentPhotoIndex] = comment;
    }
  }

  void _nextPhoto() {
    _saveCurrentPhotoData();
    if (_currentPhotoIndex < _selectedImages.length - 1) {
      setState(() {
        _currentPhotoIndex++;
        _commentController.text = _photoComments[_currentPhotoIndex] ?? '';
      });
    }
  }

  void _previousPhoto() {
    _saveCurrentPhotoData();
    if (_currentPhotoIndex > 0) {
      setState(() {
        _currentPhotoIndex--;
        _commentController.text = _photoComments[_currentPhotoIndex] ?? '';
      });
    }
  }

  Future<void> _saveAll() async {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a folder')),
      );
      return;
    }

    _saveCurrentPhotoData();
    setState(() => _isProcessing = true);

    try {
      for (var i = 0; i < _selectedImages.length; i++) {
        // Copy photo to permanent storage
        final permanentPath = await DatabaseService.instance.copyPhotoToPermanentStorage(
          _selectedImages[i].path,
        );

        final photo = Photo(
          imagePath: permanentPath,
          folderId: _selectedFolder!.id!,
          createdAt: DateTime.now(),
        );
        final photoId = await DatabaseService.instance.createPhoto(photo);

        // Save reaction if set
        final reaction = _photoReactions[i];
        if (reaction != null) {
          await DatabaseService.instance.updatePhotoReaction(photoId, reaction);
        }

        // Combine batch tags and per-photo tags
        final allTags = <String>{..._batchTags, ...(_photoTags[i] ?? [])}.toList();

        if (allTags.isNotEmpty) {
          final tagIds = <int>[];
          for (var tagName in allTags) {
            var tag = await DatabaseService.instance.getTagByName(tagName);
            if (tag == null) {
              final id = await DatabaseService.instance.createTag(Tag(name: tagName));
              tagIds.add(id);
            } else {
              tagIds.add(tag.id!);
            }
          }
          await DatabaseService.instance.addTagsToPhoto(photoId, tagIds);
        }

        final commentText = _photoComments[i];
        if (commentText != null && commentText.isNotEmpty) {
          final comment = Comment(
            photoId: photoId,
            text: commentText,
            username: 'User',
            createdAt: DateTime.now(),
          );
          await DatabaseService.instance.createComment(comment);
        }
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Photos'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showImageSourceDialog,
                    icon: const Icon(Icons.add_a_photo),
                    label: Text(_selectedImages.isEmpty
                        ? 'Add Photos'
                        : '${_selectedImages.length} photos selected'),
                  ),
                  if (_selectedImages.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Folder (for all photos):', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<Folder>(
                            isExpanded: true,
                            value: _selectedFolder,
                            hint: const Text('Select folder'),
                            items: _folders.map((folder) {
                              return DropdownMenuItem(
                                value: folder,
                                child: Text(folder.name),
                              );
                            }).toList(),
                            onChanged: (folder) {
                              setState(() => _selectedFolder = folder);
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: _createNewFolder,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Tags (for all photos):', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _batchTagController,
                            decoration: const InputDecoration(
                              hintText: 'Add tag to all photos',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _addBatchTag(),
                          ),
                        ),
                        IconButton(
                          onPressed: _addBatchTag,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_batchTags.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        children: _batchTags.map((tag) {
                          return Chip(
                            label: Text(tag),
                            backgroundColor: Colors.orange.shade100,
                            onDeleted: () => _removeBatchTag(tag),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      'Photo ${_currentPhotoIndex + 1} of ${_selectedImages.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Image.file(
                      File(_selectedImages[_currentPhotoIndex].path),
                      height: 200,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    const Text('Reaction:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _availableReactions.map((reaction) {
                        final isSelected = _photoReactions[_currentPhotoIndex] == reaction;
                        return GestureDetector(
                          onTap: () => _setReaction(reaction),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue.shade100 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              reaction,
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Tags (for this photo only):', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagController,
                            decoration: const InputDecoration(
                              hintText: 'Add tag',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _addTag(),
                          ),
                        ),
                        IconButton(
                          onPressed: _addTag,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if ((_photoTags[_currentPhotoIndex] ?? []).isNotEmpty)
                      Wrap(
                        spacing: 8,
                        children: (_photoTags[_currentPhotoIndex] ?? []).map((tag) {
                          return Chip(
                            label: Text(tag),
                            onDeleted: () => _removeTag(tag),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'Comment (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: _currentPhotoIndex > 0 ? _previousPhoto : null,
                          child: const Text('Previous'),
                        ),
                        ElevatedButton(
                          onPressed: _saveAll,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          child: const Text('Save All'),
                        ),
                        if (_currentPhotoIndex < _selectedImages.length - 1)
                          ElevatedButton(
                            onPressed: _nextPhoto,
                            child: const Text('Next'),
                          )
                        else
                          const SizedBox(width: 80), // Placeholder for alignment
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    _batchTagController.dispose();
    _commentController.dispose();
    super.dispose();
  }
}
