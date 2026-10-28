import 'dart:convert';

enum ProxyAuthType {
  none('None'),
  bearer('Bearer token'),
  basic('Username and password');

  const ProxyAuthType(this.label);

  /// Mostrata nel dialogo, quindi in inglese come il resto dell'interfaccia.
  final String label;
}

/// Come presentarsi al proxy dei testi, per chi lo mette dietro un reverse
/// proxy con autenticazione (per esempio l'auth_basic di nginx).
class ProxyAuth {
  const ProxyAuth.none()
    : type = ProxyAuthType.none,
      token = '',
      username = '',
      password = '';

  const ProxyAuth.bearer(this.token)
    : type = ProxyAuthType.bearer,
      username = '',
      password = '';

  const ProxyAuth.basic(this.username, this.password)
    : type = ProxyAuthType.basic,
      token = '';

  final ProxyAuthType type;
  final String token;
  final String username;
  final String password;

  /// Il valore dell'header `Authorization`, o `null` se non va mandato.
  String? get header => switch (type) {
    ProxyAuthType.none => null,
    ProxyAuthType.bearer => 'Bearer $token',
    ProxyAuthType.basic =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  String toJson() => jsonEncode({
    'type': type.name,
    'token': token,
    'username': username,
    'password': password,
  });

  /// Un valore che non si riconosce vale come "nessuna autenticazione", la
  /// stessa polarita' di `LyricsTextSize.fromName`.
  static ProxyAuth fromJson(String? raw) {
    if (raw == null) return const ProxyAuth.none();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return switch (json['type']) {
      'bearer' => ProxyAuth.bearer(json['token'] as String? ?? ''),
      'basic' => ProxyAuth.basic(
        json['username'] as String? ?? '',
        json['password'] as String? ?? '',
      ),
      _ => const ProxyAuth.none(),
    };
  }
}
