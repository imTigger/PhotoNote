import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'screens/home_screen.dart';
import 'screens/add_photos_screen.dart';
import 'services/database_service.dart';
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.instance.database;
  runApp(const PhotoNoteApp());
}

class PhotoNoteApp extends StatefulWidget {
  const PhotoNoteApp({super.key});

  @override
  State<PhotoNoteApp> createState() => _PhotoNoteAppState();
}

class _PhotoNoteAppState extends State<PhotoNoteApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription? _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();

    // Handle shared images when app is already running
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedImages(value);
      }
    }, onError: (err) {
      debugPrint("Error receiving shared media: $err");
    });

    // Handle shared images when app is opened via share
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedImages(value);
      }
      // Clear the initial shared media to prevent it from being processed again
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleSharedImages(List<SharedMediaFile> sharedFiles) {
    // Convert SharedMediaFile to XFile
    final images = sharedFiles
        .where((file) => file.type == SharedMediaType.image)
        .map((file) => XFile(file.path))
        .toList();

    if (images.isNotEmpty) {
      // Navigate to AddPhotosScreen with pre-selected images
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => AddPhotosScreen(initialImages: images),
        ),
      );
    }
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Photo Note',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
