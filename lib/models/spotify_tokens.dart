class SpotifyTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  static SpotifyTokens? fromTokenResponse(
    Map<String, dynamic> json, {
    String? previousRefreshToken,
  }) {
    final accessToken = json['access_token'] as String?;
    final refreshToken =
        json['refresh_token'] as String? ?? previousRefreshToken;
    if (accessToken == null || refreshToken == null) return null;

    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return SpotifyTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  bool isExpired({Duration margin = const Duration(seconds: 60)}) {
    return DateTime.now().isAfter(expiresAt.subtract(margin));
  }
}
