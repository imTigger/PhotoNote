class Comment {
  final int? id;
  final int photoId;
  final String text;
  final String username;
  final DateTime createdAt;

  Comment({
    this.id,
    required this.photoId,
    required this.text,
    required this.username,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'photoId': photoId,
      'text': text,
      'username': username,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Comment.fromMap(Map<String, dynamic> map) {
    return Comment(
      id: map['id'],
      photoId: map['photoId'],
      text: map['text'],
      username: map['username'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}
