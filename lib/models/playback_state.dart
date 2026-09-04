class PlaybackState {
  final String trackId;
  final String trackName;
  final String artistName;
  final String? albumImageUrl;
  final int durationMs;
  final bool isPlaying;
  final int progressMs;

  const PlaybackState({
    required this.trackId,
    required this.trackName,
    required this.artistName,
    required this.albumImageUrl,
    required this.durationMs,
    required this.isPlaying,
    required this.progressMs,
  });

  static PlaybackState? parse(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>?;
    final id = item?['id'] as String?;
    if (item == null || id == null) return null;

    final artists = (item['artists'] as List?)
        ?.map((artist) => artist['name'] as String?)
        .whereType<String>()
        .toList();
    final images = item['album']?['images'] as List?;

    return PlaybackState(
      trackId: id,
      trackName: item['name'] as String? ?? '',
      artistName: artists?.join(', ') ?? '',
      albumImageUrl: (images != null && images.isNotEmpty)
          ? images.first['url'] as String?
          : null,
      durationMs: (item['duration_ms'] as num?)?.toInt() ?? 0,
      isPlaying: json['is_playing'] as bool? ?? false,
      progressMs: (json['progress_ms'] as num?)?.toInt() ?? 0,
    );
  }

  PlaybackState copyWith({bool? isPlaying, int? progressMs}) {
    return PlaybackState(
      trackId: trackId,
      trackName: trackName,
      artistName: artistName,
      albumImageUrl: albumImageUrl,
      durationMs: durationMs,
      isPlaying: isPlaying ?? this.isPlaying,
      progressMs: progressMs ?? this.progressMs,
    );
  }

  bool sameDisplayAs(PlaybackState? other) {
    return other != null &&
        other.trackId == trackId &&
        other.trackName == trackName &&
        other.artistName == artistName &&
        other.albumImageUrl == albumImageUrl &&
        other.durationMs == durationMs &&
        other.isPlaying == isPlaying;
  }
}
