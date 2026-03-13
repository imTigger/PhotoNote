# Photo Note - Development Progress

## Project Overview
A Flutter-based photo-centric daily note-taking app for Android with local SQLite storage.

## Current Status: ✅ Working Demo with Full CRUD + Batch Operations

### Completed Features

#### Core Functionality
- **Folder-based navigation**: Home screen shows folders, tap to view photos inside
- **Multi-photo upload**: Camera or gallery selection with immediate dialog
- **Batch tagging**: Apply tags to all photos in current upload batch (orange chips)
- **Per-photo tags**: Add/remove tags individually for each photo (blue chips)
- **Per-photo comments**: Add/delete timestamped comments
- **Photo management**: Move photos between folders, delete photos
- **Folder management**: Create/delete folders (with cascade delete of photos)
- **Tag management**: Create/delete tags globally, add/remove from photos
- **Search/Filter**: Filter photos by tags within each folder (folder-specific tags only)
- **Quick add from folder**: FAB in folder view pre-selects current folder

#### Photo Detail Screen Features
- View full-size photo
- Add/remove tags with inline input
- Move photo to different folder
- Add/delete comments
- All changes persist immediately

#### Add Photos Workflow
- Select camera or gallery immediately on FAB tap
- Choose folder (applies to all photos in batch)
- Add batch tags (applies to all photos - orange chips)
- Step through each photo to add:
  - Per-photo tags (blue chips)
  - Comments
- Combined tags (batch + per-photo) saved to each photo

#### Database (SQLite)
- Folders table with cascade delete
- Photos table with folder relationship
- Tags table with many-to-many relationship to photos
- Comments table with photo relationship
- Full CRUD operations for all entities
- Folder-specific tag queries for filtering

#### UI Screens
1. **Home Screen**: Folder list with photo counts, FAB for new photos
2. **Folder Photos Screen**: Photo grid with folder-specific tag filtering, delete folder, FAB for quick add
3. **Add Photos Screen**: Multi-photo workflow with batch tags + per-photo tags/comments
4. **Photo Detail Screen**: Full photo management (tags, comments, folder)

### Technical Stack
- Flutter 3.41.4
- SQLite (sqflite package)
- Image picker for camera and gallery
- Local file storage for images
- Android SDK 36 / API 36
- Kotlin 2.1.0
- Gradle 8.11.1
- Android Gradle Plugin 8.9.1

### Build Configuration
- Target: Android (API 21+)
- Compile SDK: 36
- NDK: 27.0.12077973
- Successfully builds APK
- Hot reload enabled in debug mode

### Fixed Issues
1. **Gradle version compatibility**: Updated from 8.3 → 8.11.1
2. **Android Gradle Plugin**: Updated from 8.1.0 → 8.9.1
3. **Kotlin version**: Updated from 1.9.0 → 2.1.0
4. **Missing Android resources**: Generated launcher icons and theme files
5. **Folder dropdown bug**: Fixed duplicate Folder objects (multiple instances)
6. **Tags workflow**: Changed from batch-only to batch + per-photo tagging
7. **Preselected folder dropdown**: Match folder by ID from loaded list

### Testing Status
- ✅ App builds successfully
- ✅ APK generated
- ✅ Running on Pixel 9 Pro (Android 16)
- ⏳ Testing batch tagging and folder pre-selection

## Use Case Example (Implemented)
Comparing potato chip brands:
1. Open "Food" folder → Tap + button (folder pre-selected)
2. Choose "Take Photo" or "Choose from Gallery"
3. Photos load with "Food" folder already selected
4. Add batch tags: "snacks", "chips" (applies to all 3 photos - orange)
5. Step through each photo:
   - Photo A: Add tag "salty" (blue) + Comment: "Rich aromatic cheese"
   - Photo B: Add tag "bland" (blue) + Comment: "Stale and tasteless"
   - Photo C: No additional tags + No comment
6. Save all → Each photo has: folder "Food" + batch tags + individual tags + comments
7. Later: Open "Food" folder → Filter by "chips" tag → Review notes
8. Edit: Tap photo → Add/remove tags, move to another folder, delete comments

## Project Structure
```
lib/
├── main.dart                      # App entry point
├── models/
│   ├── folder.dart               # Folder data model
│   ├── photo.dart                # Photo data model
│   ├── tag.dart                  # Tag data model
│   └── comment.dart              # Comment data model
├── services/
│   └── database_service.dart     # SQLite operations with full CRUD
└── screens/
    ├── home_screen.dart          # Folder list + FAB
    ├── folder_photos_screen.dart # Photo grid + folder-specific tags + FAB
    ├── add_photos_screen.dart    # Multi-photo upload with batch + per-photo tags
    └── photo_detail_screen.dart  # Full photo management
```

## Database Operations
- **Folders**: Create, Read, Delete (cascade)
- **Photos**: Create, Read, Update (folder), Delete
- **Tags**: Create, Read, Delete, Add to photo, Remove from photo, Get by folder
- **Comments**: Create, Read, Delete

## UI/UX Features
- Batch tags shown with orange background
- Per-photo tags shown with blue background
- Folder-specific tag filtering (only shows relevant tags)
- Unused tags automatically hidden (no manual cleanup needed)
- FAB in both home and folder views
- Pre-selected folder when adding from folder view
- Confirmation dialogs for destructive actions
- Real-time updates after all operations

## Known Limitations (By Design)
- No backend integration (local storage only)
- No user authentication (planned for future)
- No cloud sync (planned for future)
- No folder sharing (planned for future)
- Single user mode
- Username hardcoded as "User"

## Next Steps (Future Backend Integration)
1. User authentication with email verification
2. Cloud photo storage
3. Folder sharing between users
4. Real-time sync across devices
5. Backend API design and implementation
6. Photo editing (crop, rotate, filters)
7. Export notes as PDF
8. Backup/restore functionality
9. Search across all folders
10. Bulk operations (multi-select photos)

## Development Notes
- App uses local SQLite database for all data persistence
- Photos stored as file paths on device
- All operations are synchronous with local database
- Cascade delete implemented for folders → photos → comments/tags
- Tag system allows reuse across photos
- Batch tags + per-photo tags combined when saving
- Folder pre-selection uses ID matching to avoid dropdown errors

## Running the App
```bash
# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Build APK
flutter build apk

# Hot reload (when running)
Press 'r' in terminal
```

## Last Updated
2026-03-13
