import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Client-side end-to-end encryption for direct messages ONLY. Nothing
/// else in the app (tracks, playlists, bios, notifications, ...) goes
/// through this — see [YandexStorageApiService]'s Messages section for
/// the only place this is used.
///
/// Design:
/// - Each ACCOUNT (not just each device) gets its own permanent X25519
///   keypair, generated the first time it's needed and cached under a
///   key scoped by account id — so logging into two different accounts
///   on the same physical device (e.g. testing sender + recipient on
///   one phone) still gives each account its own distinct identity key,
///   exactly as if they were on separate devices. The private key is
///   written to the platform Keystore/Keychain via
///   [FlutterSecureStorage] and never leaves the device. The public key
///   is safe to publish — [YandexStorageApiService] stores it on the
///   account's own row (`e2ee_pubkey`) so others can encrypt to it.
/// - Per-conversation key: ECDH(myPrivate, theirPublic) -> shared
///   secret -> HKDF-SHA256 -> 256-bit AES key. Both sides derive the
///   same key without it ever crossing the network.
/// - Each message gets its own random 96-bit nonce and is sealed with
///   AES-256-GCM (authenticated — tampering is detected as a decrypt
///   failure, not silently accepted).
/// - Stored/transmitted form: `e2ee:v1:<nonce_b64>:<ciphertext+tag_b64>`.
///   The backend (and anyone who only has server-side access to the
///   bucket) sees only this opaque string, never the plaintext.
///
/// NOTE — known limitation, out of scope for now: an account logged in
/// on two different devices will have two different keypairs (one per
/// device, whichever logged in most recently wins the `e2ee_pubkey`
/// slot), so only the most-recently-active device can decrypt new
/// messages. Fine for this app's single-device-per-account usage; true
/// multi-device support needs a key-fanout scheme, not just this.
class E2EEService {
  E2EEService._();
  static final instance = E2EEService._();

  final _secureStorage = const FlutterSecureStorage();
  final _algorithm = X25519();
  final _aead = AesGcm.with256bits();

  // Keyed by account id, so switching accounts on one device never
  // reuses another account's identity key.
  final _keyPairCache = <String, SimpleKeyPair>{};
  final _publicKeyCache = <String, String>{};

  /// Prefix marking a `DirectMessage.text` value as E2EE ciphertext
  /// rather than legacy/plain text.
  static const prefix = 'e2ee:v1:';

  String _seedStorageKey(String accountId) => 'e2ee_x25519_seed_$accountId';

  Future<SimpleKeyPair> _loadOrCreateKeyPair(String accountId) async {
    final cached = _keyPairCache[accountId];
    if (cached != null) return cached;

    final storageKey = _seedStorageKey(accountId);
    final storedSeed = await _secureStorage.read(key: storageKey);
    late final SimpleKeyPair keyPair;
    if (storedSeed != null) {
      keyPair = await _algorithm.newKeyPairFromSeed(base64Decode(storedSeed));
    } else {
      keyPair = await _algorithm.newKeyPair();
      final seed = await keyPair.extractPrivateKeyBytes();
      await _secureStorage.write(key: storageKey, value: base64Encode(seed));
    }
    _keyPairCache[accountId] = keyPair;
    _publicKeyCache[accountId] = base64Encode((await keyPair.extractPublicKey()).bytes);
    return keyPair;
  }

  /// [accountId]'s X25519 public key on this device, base64-encoded.
  /// Safe to publish — it's the whole point of a public key.
  Future<String> publicKeyBase64(String accountId) async {
    await _loadOrCreateKeyPair(accountId);
    return _publicKeyCache[accountId]!;
  }

  Future<SecretKey> _sharedKeyFor(String accountId, String otherPartyPublicKeyBase64) async {
    final keyPair = await _loadOrCreateKeyPair(accountId);
    final theirPublicKey = SimplePublicKey(
      base64Decode(otherPartyPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: theirPublicKey,
    );
    final sharedBytes = await sharedSecret.extractBytes();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      info: utf8.encode('harmony-dm-e2ee-v1'),
    );
  }

  bool isEncrypted(String text) => text.startsWith(prefix);

  /// Encrypts [plainText] as [accountId] (the current user), so only
  /// the holder of the private key matching [otherPartyPublicKeyBase64]
  /// can read it back. Returns the opaque string to store in
  /// [DirectMessage.text].
  Future<String> encrypt({
    required String accountId,
    required String plainText,
    required String otherPartyPublicKeyBase64,
  }) async {
    final key = await _sharedKeyFor(accountId, otherPartyPublicKeyBase64);
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(utf8.encode(plainText), secretKey: key, nonce: nonce);
    final payload = base64Encode(box.cipherText + box.mac.bytes);
    return '$prefix${base64Encode(nonce)}:$payload';
  }

  /// Decrypts a value previously produced by [encrypt], as [accountId]
  /// (the current user — either side of the conversation, reading back
  /// their own sent message or an incoming one; ECDH(myPriv, theirPub)
  /// == ECDH(theirPriv, myPub) so the same call shape works either way).
  /// Returns a placeholder instead of throwing if the payload is
  /// malformed or the key doesn't match, so one bad row can't crash the
  /// whole thread.
  Future<String> decrypt({
    required String accountId,
    required String stored,
    required String otherPartyPublicKeyBase64,
  }) async {
    if (!isEncrypted(stored)) return stored;
    try {
      final rest = stored.substring(prefix.length);
      final sepIndex = rest.indexOf(':');
      final nonce = base64Decode(rest.substring(0, sepIndex));
      final combined = base64Decode(rest.substring(sepIndex + 1));
      const macLength = 16;
      final macBytes = combined.sublist(combined.length - macLength);
      final cipherBytes = combined.sublist(0, combined.length - macLength);
      final key = await _sharedKeyFor(accountId, otherPartyPublicKeyBase64);
      final clear = await _aead.decrypt(
        SecretBox(cipherBytes, nonce: nonce, mac: Mac(macBytes)),
        secretKey: key,
      );
      return utf8.decode(clear);
    } catch (_) {
      return '\u{1F512} Encrypted message unavailable on this device';
    }
  }
}
