import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:hidden_eleven/app/config.dart';
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';
import 'package:hidden_eleven/features/admin/models/admin_models.dart';

/// Thrown when the server rejects admin credentials (HTTP 401).
class AdminAuthException implements Exception {
  AdminAuthException([this.message = 'Admin authentication required']);
  final String message;
  @override
  String toString() => message;
}

/// Test-only seam: every `_get`/`_put`/`_post`/`_delete` call below uses this
/// client if set, falling back to plain `http.get`/`http.put`/etc. (a fresh
/// client per call, today's exact behavior) when null. Lets a widget test
/// intercept an admin tab's save/load calls with `package:http/testing.dart`'s
/// `MockClient` without any other behavior change — production code never
/// sets this, so the real app is byte-identical to before.
@visibleForTesting
http.Client? debugHttpClient;

// ── Base URL ──────────────────────────────────────────────────────────────────

String get _base {
  final ws = AppConfig.socketUrl;
  return ws.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
}

Uri _uri(String path) => Uri.parse('$_base/api/admin$path');

// ── HTTP helpers ──────────────────────────────────────────────────────────────

// `ngrok-skip-browser-warning` makes ngrok's free tier serve the real API

Future<Map<String, String>> _buildHeaders({
  bool withAuth = false,
  bool json = false,
}) async {
  final headers = <String, String>{'ngrok-skip-browser-warning': 'true'};
  if (json) headers['Content-Type'] = 'application/json';
  if (withAuth) {
    final token = await AdminAuthService.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
  }
  return headers;
}

Future<dynamic> _get(String path, {bool auth = false}) async {
  final headers = await _buildHeaders(withAuth: auth);
  final res = debugHttpClient != null
      ? await debugHttpClient!.get(_uri(path), headers: headers)
      : await http.get(_uri(path), headers: headers);
  _check(res);
  return _decode(res);
}

Future<dynamic> _post(String path, Map<String, dynamic> body) async {
  final headers = await _buildHeaders(withAuth: true, json: true);
  final res = debugHttpClient != null
      ? await debugHttpClient!.post(
          _uri(path),
          headers: headers,
          body: jsonEncode(body),
        )
      : await http.post(_uri(path), headers: headers, body: jsonEncode(body));
  _check(res);
  return _decode(res);
}

Future<dynamic> _put(String path, Map<String, dynamic> body) async {
  final headers = await _buildHeaders(withAuth: true, json: true);
  final res = debugHttpClient != null
      ? await debugHttpClient!.put(
          _uri(path),
          headers: headers,
          body: jsonEncode(body),
        )
      : await http.put(_uri(path), headers: headers, body: jsonEncode(body));
  _check(res);
  return _decode(res);
}

Future<void> _delete(String path) async {
  final headers = await _buildHeaders(withAuth: true);
  final res = debugHttpClient != null
      ? await debugHttpClient!.delete(_uri(path), headers: headers)
      : await http.delete(_uri(path), headers: headers);
  if (res.statusCode != 204 && res.statusCode >= 300) {
    _check(res);
  }
}

/// Decodes a JSON response, but first guards against an HTML/interstitial body
/// (e.g. the ngrok warning page) being parsed as JSON — which would otherwise
/// throw an opaque FormatException.
dynamic _decode(http.Response res) {
  final body = res.body.trimLeft();
  if (body.startsWith('<') ||
      (res.headers['content-type']?.contains('text/html') ?? false)) {
    throw Exception(
      'Expected JSON but received an HTML page (likely an ngrok/proxy '
      'interstitial). Reload the tunnel page once and retry.',
    );
  }
  return jsonDecode(res.body);
}

/// Infers the image MIME type from a filename's extension so the server's
/// FileTypeValidator receives the correct Content-Type on the multipart part.
MediaType _mimeFromFilename(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
    'png' => MediaType('image', 'png'),
    'webp' => MediaType('image', 'webp'),
    'gif' => MediaType('image', 'gif'),
    'svg' => MediaType('image', 'svg+xml'),
    _ => MediaType('image', 'png'),
  };
}

Future<dynamic> _uploadFile(
  String path,
  Uint8List bytes,
  String filename,
) async {
  final request = http.MultipartRequest('POST', _uri(path));
  final headers = await _buildHeaders(withAuth: true);
  request.headers.addAll(headers);
  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: _mimeFromFilename(filename),
    ),
  );
  final streamed = await request.send();
  final response = await http.Response.fromStream(streamed);
  _check(response);
  return _decode(response);
}

void _check(http.Response res) {
  if (res.statusCode == 401) {
    throw AdminAuthException();
  }
  if (res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
}

// ── AdminApi ──────────────────────────────────────────────────────────────────

abstract final class AdminApi {
  /// Probes admin access. Succeeds when authenticated or when the server does
  /// not require a key (local dev). Throws [AdminAuthException] on 401.
  static Future<void> verifyAdminAccess() async {
    await _get('/players', auth: true);
  }

  /// Converts a stored relative asset path (e.g. /assets/players/photos/x.png)
  /// to a full HTTP URL. Absolute URLs are passed through unchanged.
  static String resolveAssetUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$_base$path';
  }

  /// Returns a URL safe for use with Image.network in Flutter web.
  /// External URLs (non-server) are routed through the NestJS proxy so that
  /// CDNs without CORS headers (e.g. cdn.sofifa.net) can be previewed.
  static String proxyImageUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith(_base)) return url; // already on our server
    if (!url.startsWith('http')) return url; // relative — shouldn't happen
    return '$_base/api/admin/proxy/image?url=${Uri.encodeComponent(url)}';
  }

  // ── Players ─────────────────────────────────────────────────────────────────

  static Future<List<AdminPlayer>> getPlayers() async {
    final data = await _get('/players', auth: true) as List<dynamic>;
    return data
        .map((e) => AdminPlayer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminPlayer> createPlayer(Map<String, dynamic> dto) async {
    final data = await _post('/players', dto);
    return AdminPlayer.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminPlayer> updatePlayer(
    String id,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/players/$id', dto);
    return AdminPlayer.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deletePlayer(String id) => _delete('/players/$id');

  static Future<AdminPlayer> uploadPlayerPhoto(
    String id,
    Uint8List bytes,
    String filename,
  ) async {
    final data = await _uploadFile('/upload/player-photo/$id', bytes, filename);
    return AdminPlayer.fromJson(data as Map<String, dynamic>);
  }

  // ── Clubs ────────────────────────────────────────────────────────────────────

  static Future<List<AdminClub>> getClubs() async {
    final data = await _get('/clubs', auth: true) as List<dynamic>;
    return data
        .map((e) => AdminClub.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminClub> createClub(Map<String, dynamic> dto) async {
    final data = await _post('/clubs', dto);
    return AdminClub.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminClub> updateClub(
    String slug,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/clubs/$slug', dto);
    return AdminClub.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteClub(String slug) => _delete('/clubs/$slug');

  static Future<AdminClub> uploadClubLogo(
    String slug,
    Uint8List bytes,
    String filename,
  ) async {
    final data = await _uploadFile('/upload/club-logo/$slug', bytes, filename);
    return AdminClub.fromJson(data as Map<String, dynamic>);
  }

  // ── Nations ──────────────────────────────────────────────────────────────────

  static Future<List<AdminNation>> getNations() async {
    final data = await _get('/nations', auth: true) as List<dynamic>;
    return data
        .map((e) => AdminNation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminNation> createNation(Map<String, dynamic> dto) async {
    final data = await _post('/nations', dto);
    return AdminNation.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminNation> updateNation(
    String slug,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/nations/$slug', dto);
    return AdminNation.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteNation(String slug) => _delete('/nations/$slug');

  static Future<AdminNation> uploadNationFlag(
    String slug,
    Uint8List bytes,
    String filename,
  ) async {
    final data = await _uploadFile(
      '/upload/nation-flag/$slug',
      bytes,
      filename,
    );
    return AdminNation.fromJson(data as Map<String, dynamic>);
  }

  // ── Leagues ──────────────────────────────────────────────────────────────────

  static Future<List<AdminLeague>> getLeagues() async {
    final data = await _get('/leagues') as List<dynamic>;
    return data
        .map((e) => AdminLeague.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminLeague> createLeague(Map<String, dynamic> dto) async {
    final data = await _post('/leagues', dto);
    return AdminLeague.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminLeague> updateLeague(
    String slug,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/leagues/$slug', dto);
    return AdminLeague.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteLeague(String slug) => _delete('/leagues/$slug');

  static Future<AdminLeague> uploadLeagueLogo(
    String slug,
    Uint8List bytes,
    String filename,
  ) async {
    final data = await _uploadFile(
      '/upload/league-logo/$slug',
      bytes,
      filename,
    );
    return AdminLeague.fromJson(data as Map<String, dynamic>);
  }

  // ── League bundles ─────────────────────────────────────────────────────────

  static Future<List<AdminLeagueBundle>> getLeagueBundles() async {
    final data = await _get('/league-bundles') as List<dynamic>;
    return data
        .map((e) => AdminLeagueBundle.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Host picker — active bundles only, with league preview.
  static Future<List<ActiveLeagueBundle>> getActiveLeagueBundles() async {
    final data = await _get('/league-bundles/active') as List<dynamic>;
    return data
        .map((e) => ActiveLeagueBundle.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminLeagueBundle> createLeagueBundle(
    Map<String, dynamic> dto,
  ) async {
    final data = await _post('/league-bundles', dto);
    return AdminLeagueBundle.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminLeagueBundle> updateLeagueBundle(
    String id,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/league-bundles/$id', dto);
    return AdminLeagueBundle.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminLeagueBundle> duplicateLeagueBundle(String id) async {
    final data = await _post('/league-bundles/$id/duplicate', const {});
    return AdminLeagueBundle.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteLeagueBundle(String id) =>
      _delete('/league-bundles/$id');

  // ── Formations ─────────────────────────────────────────────────────────────────

  static Future<List<AdminFormation>> getFormations() async {
    final data = await _get('/formations') as List<dynamic>;
    return data
        .map((e) => AdminFormation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminFormation> createFormation(
    Map<String, dynamic> dto,
  ) async {
    final data = await _post('/formations', dto);
    return AdminFormation.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminFormation> updateFormation(
    String slug,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/formations/$slug', dto);
    return AdminFormation.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteFormation(String slug) =>
      _delete('/formations/$slug');

  // ── Card tiers ─────────────────────────────────────────────────────────────────

  static Future<List<AdminCardTier>> getCardTiers() async {
    final data = await _get('/card-tiers') as List<dynamic>;
    return data
        .map((e) => AdminCardTier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminCardTier> createCardTier(Map<String, dynamic> dto) async {
    final data = await _post('/card-tiers', dto);
    return AdminCardTier.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminCardTier> updateCardTier(
    String slug,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/card-tiers/$slug', dto);
    return AdminCardTier.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteCardTier(String slug) =>
      _delete('/card-tiers/$slug');

  // ── Abilities ────────────────────────────────────────────────────────────────

  static Future<List<AdminAbility>> getAbilities() async {
    final data = await _get('/abilities') as List<dynamic>;
    return data
        .map((e) => AdminAbility.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminAbility> updateAbility(
    String type,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/abilities/$type', dto);
    return AdminAbility.fromJson(data as Map<String, dynamic>);
  }

  // ── Scoring config ───────────────────────────────────────────────────────────

  static Future<AdminScoringConfigFile> getScoringConfig() async {
    final data = await _get('/scoring-config', auth: true);
    return AdminScoringConfigFile.fromJson(data as Map<String, dynamic>);
  }

  /// `values` is the full nested ScoringConfigValues shape (not a partial
  /// diff) — the tab always sends every field back on save, matching how it
  /// always holds a full local copy of the current draft.
  static Future<AdminScoringConfigVersion> saveScoringConfigDraft(
    Map<String, dynamic> values,
  ) async {
    final data = await _put('/scoring-config/draft', values);
    return AdminScoringConfigVersion.fromJson(data as Map<String, dynamic>);
  }

  /// Throws on validation failure (400) — the thrown Exception's message
  /// contains the raw JSON error body; see ScoringTab's error parsing.
  static Future<AdminScoringConfigFile> publishScoringConfig({
    String? note,
  }) async {
    final data = await _post('/scoring-config/publish', {'note': ?note});
    return AdminScoringConfigFile.fromJson(data as Map<String, dynamic>);
  }

  // ── Tournament awards config ─────────────────────────────────────────────────

  static Future<AdminTournamentAwardsConfigFile>
  getTournamentAwardsConfig() async {
    final data = await _get('/tournament-awards-config', auth: true);
    return AdminTournamentAwardsConfigFile.fromJson(
      data as Map<String, dynamic>,
    );
  }

  /// `values` is the full TournamentAwardsConfigValues shape (not a partial
  /// diff) — same convention as saveScoringConfigDraft above.
  static Future<AdminTournamentAwardsConfigVersion>
  saveTournamentAwardsConfigDraft(Map<String, dynamic> values) async {
    final data = await _put('/tournament-awards-config/draft', values);
    return AdminTournamentAwardsConfigVersion.fromJson(
      data as Map<String, dynamic>,
    );
  }

  /// Throws on validation failure (400) — see ScoringTab's error parsing
  /// pattern (_extractErrorMessages), reused as-is by the Tournament Awards
  /// tab.
  static Future<AdminTournamentAwardsConfigFile> publishTournamentAwardsConfig({
    String? note,
  }) async {
    final data = await _post('/tournament-awards-config/publish', {
      'note': ?note,
    });
    return AdminTournamentAwardsConfigFile.fromJson(
      data as Map<String, dynamic>,
    );
  }

  // ── Backups ───────────────────────────────────────────────────────────────────

  static Future<AdminBackupStatus> getBackupStatus() async {
    final data = await _get('/backup', auth: true);
    return AdminBackupStatus.fromJson(data as Map<String, dynamic>);
  }

  /// Runs a backup right now (in addition to the server's own daily cron)
  /// and returns its resulting status.
  static Future<AdminBackupStatus> runBackupNow() async {
    final data = await _post('/backup', const {});
    return AdminBackupStatus.fromJson(data as Map<String, dynamic>);
  }

  /// Fetches the current backup archive's raw bytes for a browser download.
  static Future<Uint8List> downloadBackup() async {
    final headers = await _buildHeaders(withAuth: true);
    final res = debugHttpClient != null
        ? await debugHttpClient!.get(_uri('/backup/download'), headers: headers)
        : await http.get(_uri('/backup/download'), headers: headers);
    _check(res);
    return res.bodyBytes;
  }

  // ── Guide sections (Instructions / Game Guide) ────────────────────────────────

  static Future<List<AdminGuideSection>> getGuideSections() async {
    final data = await _get('/guide-sections') as List<dynamic>;
    return data
        .map((e) => AdminGuideSection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminGuideSection> updateGuideSection(
    String key,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/guide-sections/$key', dto);
    return AdminGuideSection.fromJson(data as Map<String, dynamic>);
  }

  // ── FAQ ────────────────────────────────────────────────────────────────────────

  static Future<List<AdminFaqItem>> getFaqItems() async {
    final data = await _get('/faq') as List<dynamic>;
    return data
        .map((e) => AdminFaqItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminFaqItem> createFaqItem(Map<String, dynamic> dto) async {
    final data = await _post('/faq', dto);
    return AdminFaqItem.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminFaqItem> updateFaqItem(
    String id,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/faq/$id', dto);
    return AdminFaqItem.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteFaqItem(String id) => _delete('/faq/$id');

  // ── Quick tips ───────────────────────────────────────────────────────────────

  static Future<List<AdminQuickTip>> getQuickTips() async {
    final data = await _get('/quick-tips') as List<dynamic>;
    return data
        .map((e) => AdminQuickTip.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminQuickTip> createQuickTip(Map<String, dynamic> dto) async {
    final data = await _post('/quick-tips', dto);
    return AdminQuickTip.fromJson(data as Map<String, dynamic>);
  }

  static Future<AdminQuickTip> updateQuickTip(
    String id,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/quick-tips/$id', dto);
    return AdminQuickTip.fromJson(data as Map<String, dynamic>);
  }

  static Future<void> deleteQuickTip(String id) => _delete('/quick-tips/$id');

  // ── Context help (in-app "?" dialogs) ─────────────────────────────────────────

  static Future<List<AdminContextHelp>> getContextHelp() async {
    final data = await _get('/context-help') as List<dynamic>;
    return data
        .map((e) => AdminContextHelp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<AdminContextHelp> updateContextHelp(
    String key,
    Map<String, dynamic> dto,
  ) async {
    final data = await _put('/context-help/$key', dto);
    return AdminContextHelp.fromJson(data as Map<String, dynamic>);
  }

  // ── Assets ───────────────────────────────────────────────────────────────────

  static Future<Map<String, List<String>>> getAssets() async {
    final data = await _get('/assets', auth: true) as Map<String, dynamic>;
    return data.map((k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()));
  }

  static String assetUrl(String relativePath) => '$_base/assets/$relativePath';

  // ── Health / Metrics ─────────────────────────────────────────────────────────

  static Uri _rootUri(String path) => Uri.parse('$_base$path');

  static Future<String> getHealth() async {
    final headers = await _buildHeaders();
    final res = debugHttpClient != null
        ? await debugHttpClient!.get(_rootUri('/health'), headers: headers)
        : await http.get(_rootUri('/health'), headers: headers);
    if (res.statusCode == 503) return 'shutting_down';
    _check(res);
    final data = _decode(res);
    return data['status'] as String? ?? 'unknown';
  }

  static Future<Map<String, dynamic>> getMetrics() async {
    final headers = await _buildHeaders(withAuth: true);
    final res = await http.get(_rootUri('/metrics'), headers: headers);
    _check(res);
    return _decode(res) as Map<String, dynamic>;
  }
}
