import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Minimal AWS Signature V4 signer, just enough to talk to Yandex Object
/// Storage's S3-compatible API directly from the app (GetObject/PutObject
/// on a single bucket, path-style addressing). No AWS SDK dependency.
///
/// Yandex Object Storage docs confirm the same S3 request-signing and
/// conditional-write (If-Match / If-None-Match) semantics as AWS S3, which
/// is what this class and [YandexStorageApiService] rely on.
class YandexSigV4 {
  YandexSigV4({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.region,
    required this.host,
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String region;
  final String host; // e.g. storage.yandexcloud.net
  static const _service = 's3';

  /// Builds signed headers for a path-style S3 request.
  /// [canonicalPath] must start with '/' and already be URI-encoded
  /// per-segment (e.g. '/my-bucket/media/audio/abc.mp3').
  Map<String, String> signedHeaders({
    required String method,
    required String canonicalPath,
    required List<int> body,
    Map<String, String> extraHeaders = const {},
  }) {
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = _dateStamp(now);
    final payloadHash = sha256.convert(body).toString();

    final headers = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      ...extraHeaders,
    };

    final sortedHeaderNames = headers.keys.map((k) => k.toLowerCase()).toList()..sort();
    final canonicalHeaders =
        sortedHeaderNames.map((k) => '$k:${headers[_originalKey(headers, k)]!.trim()}\n').join();
    final signedHeaderNames = sortedHeaderNames.join(';');

    final canonicalRequest = [
      method,
      canonicalPath,
      '', // no query string for the requests this service makes
      canonicalHeaders,
      signedHeaderNames,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/$_service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _deriveSigningKey(dateStamp);
    final signature = Hmac(sha256, signingKey).convert(utf8.encode(stringToSign)).toString();

    final authorization = 'AWS4-HMAC-SHA256 '
        'Credential=$accessKeyId/$credentialScope, '
        'SignedHeaders=$signedHeaderNames, '
        'Signature=$signature';

    return {
      ...headers,
      'Authorization': authorization,
    };
  }

  String _originalKey(Map<String, String> headers, String lowerKey) {
    return headers.keys.firstWhere((k) => k.toLowerCase() == lowerKey);
  }

  List<int> _deriveSigningKey(String dateStamp) {
    List<int> hmac(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    final kDate = hmac(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, _service);
    final kSigning = hmac(kService, 'aws4_request');
    return kSigning;
  }

  String _amzDate(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  String _dateStamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}';
  }
}
