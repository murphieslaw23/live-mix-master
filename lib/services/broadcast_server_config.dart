import 'reliability_models.dart';

enum BroadcastProtocol { icecast, shoutcast, webhook, obsHttpOverlay }
enum BroadcastValidationIssue { invalidTimeout, invalidRetryCount, invalidBackoff, invalidHost, invalidPort, invalidMount, invalidWebhook, invalidOverlayPath }

class BroadcastServerConfig {
  const BroadcastServerConfig({required this.protocol, this.host = 'localhost', this.port = 8000, this.mountPoint = '/live', this.adminUser = 'admin', this.adminPassword = '', this.webhookUrl, this.timeout = const Duration(seconds: 4), this.maxRetries = 2, this.initialBackoff = const Duration(milliseconds: 100), this.maxBackoff = const Duration(seconds: 30), this.allowHttpWebhook = false, this.overlayFilePath});
  final BroadcastProtocol protocol;
  final String host;
  final int port;
  final String mountPoint;
  final String adminUser;
  final String adminPassword;
  final Uri? webhookUrl;
  final Duration timeout;
  final int maxRetries;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final bool allowHttpWebhook;
  final String? overlayFilePath;
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');

  BroadcastValidationIssue? get validationIssue {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 60)) return BroadcastValidationIssue.invalidTimeout;
    if (maxRetries < 0 || maxRetries > 5) return BroadcastValidationIssue.invalidRetryCount;
    if (initialBackoff.isNegative || maxBackoff <= Duration.zero || maxBackoff > const Duration(seconds: 30) || initialBackoff > maxBackoff) return BroadcastValidationIssue.invalidBackoff;
    switch (protocol) {
      case BroadcastProtocol.icecast:
      case BroadcastProtocol.shoutcast:
        if (!_validHost(host)) return BroadcastValidationIssue.invalidHost;
        if (port < 1 || port > 65535) return BroadcastValidationIssue.invalidPort;
        if (protocol == BroadcastProtocol.icecast && (mountPoint.isEmpty || mountPoint.length > 1024 || mountPoint != mountPoint.trim() || RegExp(r'[\s\x00-\x1f\x7f?#\\]').hasMatch(mountPoint) || mountPoint.contains('://') || mountPoint.startsWith('//'))) return BroadcastValidationIssue.invalidMount;
        try {
          Uri(scheme: 'http', host: _host, port: port, path: protocol == BroadcastProtocol.icecast ? '/admin/metadata' : '/admin.cgi');
        } catch (_) { return BroadcastValidationIssue.invalidHost; }
        break;
      case BroadcastProtocol.webhook:
        final url = webhookUrl;
        if (url == null || (url.scheme != 'https' && !(allowHttpWebhook && url.scheme == 'http')) || !_validHost(url.host) || url.port < 1 || url.port > 65535 || url.userInfo.isNotEmpty || url.hasFragment || _controls.hasMatch(url.path)) return BroadcastValidationIssue.invalidWebhook;
        break;
      case BroadcastProtocol.obsHttpOverlay:
        final path = overlayFilePath;
        if (path != null && (path.trim().isEmpty || path.contains(String.fromCharCode(0)))) return BroadcastValidationIssue.invalidOverlayPath;
        break;
    }
    return null;
  }

  ServiceFailureCode? get validationFailure => validationIssue == null ? null : ServiceFailureCode.invalidConfiguration;
  String get _host => host.startsWith('[') && host.endsWith(']') ? host.substring(1, host.length - 1) : host;

  static bool _validHost(String value) {
    if (value.isEmpty || value != value.trim() || value.length > 253 || RegExp(r'[\s/@?#%\\\x00-\x1f\x7f]').hasMatch(value)) return false;
    var candidate = value;
    if (candidate.startsWith('[') || candidate.endsWith(']')) {
      if (!candidate.startsWith('[') || !candidate.endsWith(']')) return false;
      candidate = candidate.substring(1, candidate.length - 1);
      if (!candidate.contains(':')) return false;
    }
    try {
      if (candidate.contains(':')) { Uri.parseIPv6Address(candidate); return true; }
      if (RegExp(r'^[0-9.]+$').hasMatch(candidate)) { Uri.parseIPv4Address(candidate); return true; }
      final label = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
      return candidate.split('.').every(label.hasMatch);
    } catch (_) { return false; }
  }

  Duration retryDelay(int completedAttempt) {
    if (validationIssue != null || completedAttempt < 1 || completedAttempt > maxRetries) throw ArgumentError('Invalid broadcast retry configuration');
    final micros = initialBackoff.inMicroseconds * (1 << (completedAttempt - 1));
    return Duration(microseconds: micros > maxBackoff.inMicroseconds ? maxBackoff.inMicroseconds : micros);
  }

  Uri buildMetadataUri(String song) {
    if (validationIssue != null) throw ArgumentError('Invalid broadcast configuration');
    switch (protocol) {
      case BroadcastProtocol.icecast:
        return Uri(scheme: 'http', host: _host, port: port, path: '/admin/metadata', queryParameters: {'mount': mountPoint.startsWith('/') ? mountPoint : '/$mountPoint', 'mode': 'updinfo', 'song': song, 'charset': 'UTF-8'});
      case BroadcastProtocol.shoutcast:
        return Uri(scheme: 'http', host: _host, port: port, path: '/admin.cgi', queryParameters: {'mode': 'updinfo', 'pass': adminPassword, 'song': song});
      case BroadcastProtocol.webhook: return webhookUrl!;
      case BroadcastProtocol.obsHttpOverlay: throw ArgumentError('Overlay has no metadata URI');
    }
  }
}
