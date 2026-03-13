class Photo {
  final int? id;
  final String imagePath;
  final int folderId;
  final DateTime createdAt;

  Photo({
    this.id,
    required this.imagePath,
    required this.folderId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'folderId': folderId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Photo.fromMap(Map<String, dynamic> map) {
    return Photo(
      id: map['id'],
      imagePath: map['imagePath'],
      folderId: map['folderId'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
