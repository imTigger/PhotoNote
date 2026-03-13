import 'package:flutter/material.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../models/comment.dart';
import '../models/tag.dart';
import '../models/folder.dart';
import '../models/photo.dart';

class PhotoDetailScreen extends StatefulWidget {
  final int photoId;
  final String imagePath;
  final List<Map<String, dynamic>>? allPhotos;
  final int? currentIndex;

  const PhotoDetailScreen({
    super.key,
    required this.photoId,
    required this.imagePath,
    this.allPhotos,
    this.currentIndex,
  });

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  List<Comment> _comments = [];
  List<Tag> _tags = [];
  List<Folder> _folders = [];
  Photo? _photo;
  late String _currentImagePath;
  late int _currentPhotoId;
  late int _currentIndex;
  String? _currentReaction;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;

  static const List<String> _availableReactions = ['👍🏻', '👎🏻', '✅', '❌', '🤣', '😍'];

  @override
  void initState() {
    super.initState();
    _currentImagePath = widget.imagePath;
    _currentPhotoId = widget.photoId;
    _currentIndex = widget.currentIndex ?? 0;
    _loadData();
  }

  void _navigateToPhoto(int newIndex) {
    if (widget.allPhotos == null || newIndex < 0 || newIndex >= widget.allPhotos!.length) {
      return;
    }

    final newPhoto = widget.allPhotos![newIndex];
    setState(() {
      _currentIndex = newIndex;
      _currentPhotoId = newPhoto['id'];
      _currentImagePath = newPhoto['imagePath'];
      _isLoading = true;
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final comments = await DatabaseService.instance.getPhotoComments(_currentPhotoId);
    final tags = await DatabaseService.instance.getPhotoTags(_currentPhotoId);
    final folders = await DatabaseService.instance.getAllFolders();
    final photo = await DatabaseService.instance.getPhotoById(_currentPhotoId);
    final photoData = await DatabaseService.instance.getPhotoWithReaction(_currentPhotoId);

    setState(() {
      _comments = comments;
      _tags = tags;
      _folders = folders;
      _photo = photo;
      _currentReaction = photoData?['reaction'];
      _isLoading = false;
    });
  }

  Future<void> _setReaction(String reaction) async {
    if (_currentReaction == reaction) {
      // Remove reaction if tapping the same one
      await DatabaseService.instance.updatePhotoReaction(_currentPhotoId, null);
      setState(() => _currentReaction = null);
    } else {
      await DatabaseService.instance.updatePhotoReaction(_currentPhotoId, reaction);
      setState(() => _currentReaction = reaction);
    }
  }

  Future<void> _replacePhoto() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace Photo'),
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
      final XFile? newImage = await _picker.pickImage(source: source);

      if (newImage != null) {
        // Copy new photo to permanent storage
        final newPermanentPath = await DatabaseService.instance.copyPhotoToPermanentStorage(
          newImage.path,
        );

        // Delete old photo file
        try {
          final oldFile = File(_currentImagePath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (e) {
          // Ignore deletion errors
        }

        // Update database
        await DatabaseService.instance.updatePhotoPath(widget.photoId, newPermanentPath);

        // Update UI
        setState(() {
          _currentImagePath = newPermanentPath;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo replaced successfully')),
          );
        }
      }
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final comment = Comment(
      photoId: widget.photoId,
      text: text,
      username: 'User',
      createdAt: DateTime.now(),
    );

    await DatabaseService.instance.createComment(comment);
    _commentController.clear();
    _loadData();
  }

  Future<void> _deleteComment(Comment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text('Delete this comment?'),
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
      await DatabaseService.instance.deleteComment(comment.id!);
      _loadData();
    }
  }

  Future<void> _addTag() async {
    final tagName = _tagController.text.trim();
    if (tagName.isEmpty) return;

    if (_tags.any((t) => t.name == tagName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tag already exists on this photo')),
      );
      return;
    }

    var tag = await DatabaseService.instance.getTagByName(tagName);
    if (tag == null) {
      final id = await DatabaseService.instance.createTag(Tag(name: tagName));
      tag = Tag(id: id, name: tagName);
    }

    await DatabaseService.instance.addTagsToPhoto(widget.photoId, [tag.id!]);
    _tagController.clear();
    _loadData();
  }

  Future<void> _removeTag(Tag tag) async {
    await DatabaseService.instance.removeTagFromPhoto(widget.photoId, tag.id!);
    _loadData();
  }

  Future<void> _changeFolder() async {
    if (_photo == null) return;

    final selectedFolder = await showDialog<Folder>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _folders.length,
            itemBuilder: (context, index) {
              final folder = _folders[index];
              final isCurrentFolder = folder.id == _photo!.folderId;
              return ListTile(
                leading: Icon(
                  Icons.folder,
                  color: isCurrentFolder ? Colors.blue : Colors.grey,
                ),
                title: Text(
                  folder.name,
                  style: TextStyle(
                    fontWeight: isCurrentFolder ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: isCurrentFolder ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () => Navigator.pop(context, folder),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedFolder != null && selectedFolder.id != _photo!.folderId) {
      await DatabaseService.instance.updatePhotoFolder(widget.photoId, selectedFolder.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to ${selectedFolder.name}')),
        );
      }
      _loadData();
    }
  }

  Future<void> _deletePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Delete this photo and all its comments?\nThis cannot be undone.'),
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
      await DatabaseService.instance.deletePhoto(widget.photoId);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, y h:mm a').format(dateTime);
  }

  void _showFullscreenPhoto() async {
    final newIndex = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _FullscreenPhotoViewer(
          allPhotos: widget.allPhotos,
          initialIndex: _currentIndex,
        ),
      ),
    );

    // Update to the photo that was being viewed in the lightbox
    if (newIndex != null && newIndex != _currentIndex) {
      _navigateToPhoto(newIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_camera),
            tooltip: 'Replace Photo',
            onPressed: _replacePhoto,
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_move),
            tooltip: 'Move to Folder',
            onPressed: _changeFolder,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete Photo',
            onPressed: _deletePhoto,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo section - tap to open fullscreen zoom, swipe to navigate
                  GestureDetector(
                    onTap: _showFullscreenPhoto,
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity == null) return;
                      if (details.primaryVelocity! < -300) {
                        // Swipe left → next photo
                        _navigateToPhoto(_currentIndex + 1);
                      } else if (details.primaryVelocity! > 300) {
                        // Swipe right → previous photo
                        _navigateToPhoto(_currentIndex - 1);
                      }
                    },
                    child: Image.file(
                        File(_currentImagePath),
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                          if (wasSynchronouslyLoaded) return child;

                          if (frame == null) {
                            return Container(
                              height: MediaQuery.of(context).size.height * 0.4,
                              color: Colors.grey.shade200,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Loading photo...',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return AnimatedOpacity(
                            opacity: 1,
                            duration: const Duration(milliseconds: 300),
                            child: child,
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade300,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  // Reactions, tags, and comments section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _availableReactions.map((reaction) {
                        final isSelected = _currentReaction == reaction;
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
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _tagController,
                                decoration: const InputDecoration(
                                  hintText: 'Add tag',
                                  border: OutlineInputBorder(),
                                  isDense: true,
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
                        if (_tags.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            children: _tags.map((tag) {
                              return Chip(
                                label: Text(tag.name),
                                backgroundColor: Colors.blue.shade100,
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () => _removeTag(tag),
                              );
                            }).toList(),
                          )
                        else
                          const Text(
                            'No tags yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Comments',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_comments.isEmpty)
                          const Text('No comments yet')
                        else
                          ..._comments.map((comment) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Text(
                                                comment.username,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _formatDateTime(comment.createdAt),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 20),
                                          color: Colors.red,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _deleteComment(comment),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(comment.text),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                decoration: const InputDecoration(
                                  hintText: 'Add a comment',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _addComment,
                              icon: const Icon(Icons.send),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _tagController.dispose();
    super.dispose();
  }
}

class _FullscreenPhotoViewer extends StatefulWidget {
  final List<Map<String, dynamic>>? allPhotos;
  final int initialIndex;

  const _FullscreenPhotoViewer({
    required this.allPhotos,
    required this.initialIndex,
  });

  @override
  State<_FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<_FullscreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allPhotos == null || widget.allPhotos!.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Text('No photos available', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            Navigator.pop(context, _currentIndex);
          }
        },
        child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.allPhotos!.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final photo = widget.allPhotos![index];
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    File(photo['imagePath']),
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context, _currentIndex),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${widget.allPhotos!.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
