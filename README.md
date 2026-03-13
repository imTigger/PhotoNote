# Photo Note

A photo-centric daily note taking app built with Flutter.

## Features

- **Folders**: Organize photos into folders (one folder per photo)
- **Tags**: Add multiple tags to photos for easy searching
- **Comments**: Add timestamped comments to each photo
- **Search**: Filter photos by tags
- **Local Storage**: All data stored locally using SQLite

## Use Case Example

Taking notes on potato chip brands:
1. Take photos of 3 different chip packages
2. Select folder "Food" and add tags "snacks" and "chips" to all
3. Add individual comments to each photo
4. Later, search by "chips" tag to review your notes

## Setup

### Prerequisites
- Flutter SDK (3.0.0 or higher)
- Android Studio or VS Code with Flutter extensions
- Android device or emulator (API level 21+)

### Installation

1. Install dependencies:
```bash
flutter pub get
```

2. Run the app:
```bash
flutter run
```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── folder.dart
│   ├── photo.dart
│   ├── tag.dart
│   └── comment.dart
├── services/
│   └── database_service.dart # SQLite database operations
└── screens/
    ├── home_screen.dart      # Main photo grid with tag filters
    ├── add_photos_screen.dart # Multi-photo upload workflow
    └── photo_detail_screen.dart # Photo view with comments
```

## Database Schema

- **folders**: id, name, createdAt
- **photos**: id, imagePath, folderId, createdAt
- **tags**: id, name
- **photo_tags**: photoId, tagId (many-to-many)
- **comments**: id, photoId, text, username, createdAt

## Future Backend Integration

Currently uses local SQLite storage. Backend features to add:
- User authentication (email verification)
- Cloud photo storage
- Folder sharing between users
- Real-time sync across devices

## Permissions

The app requires the following Android permissions:
- Camera access
- Photo library access (read/write)
