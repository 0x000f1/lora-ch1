// encryption logic, key exchange, and payload decryption

import 'package:app/services/ble_service.dart';
import 'package:app/services/ble_transport.dart';
import 'package:app/services/crypto.dart';
import 'package:app/services/db_service.dart';
import 'package:app/core/logger.dart';
import 'package:cryptography/cryptography.dart';

import 'package:app/services/messaging_service.dart';

SimpleKeyPair? _myKeyPair;
Future<SimpleKeyPair>? _initFuture;

// returns our public key as base64
Future<String> _myPublicKeyBase64() async {
  final keyPair = await getOrInitMyKeyPair();
  final myPubKey = await keyPair.extractPublicKey();
  return CryptoService.exportPublicKey(myPubKey);
}

// derives shared key from out private and peer's public key
Future<SecretKey> _deriveSharedSecret(String peerPubKeyBase64) async {
  final myKeyPair = await getOrInitMyKeyPair();
  final peerPublicKey = await CryptoService.importPublicKey(peerPubKeyBase64);
  return CryptoService.deriveSharedSecret(myKeyPair, peerPublicKey);
}

// get keypair, or init keypair on first launch
Future<SimpleKeyPair> getOrInitMyKeyPair() async {
  // return if keypair is already in memory
  if (_myKeyPair != null) return _myKeyPair!;

  // store running task in future, if it already exists, wait for it finish to prevent conflicts
  _initFuture ??= _loadOrGenerateKeys();
  return await _initFuture!;
}

Future<SimpleKeyPair> _loadOrGenerateKeys() async {
  // get keys from database
  final savedKeys = await getMyKeys();

  if (savedKeys != null) {
    // store in memory from base64 public and private key
    _myKeyPair = await CryptoService.importKeyPair(
      savedKeys['private_key']!,
      savedKeys['public_key']!,
    );
  } else {
    // on first launch generate new keypair
    _myKeyPair = await CryptoService.generateKeyPair();

    // extract public key from new keypair
    final pubKey = await _myKeyPair!.extractPublicKey();

    // convert both keys into base64
    final privBase64 = await CryptoService.exportPrivateKey(_myKeyPair!);
    final pubBase64 = await CryptoService.exportPublicKey(pubKey);

    // save new keys into database
    await saveMyKeys(privBase64, pubBase64);
  }

  return _myKeyPair!;
}

// keep track of last request to not send a request to a device with no user (and no key)
final Map<String, int> _lastKeyRequestTime = {};

Future<void> checkAndRequestKey(String neighborMac) async {
  final existingKey = await getPeerPublicKey(neighborMac);

  if (existingKey != null) return;

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final lastRequest = _lastKeyRequestTime[neighborMac] ?? 0;

  // if last request was less then 3 minutes ago, dont send a new one
  if (now - lastRequest < 180) return;

  _lastKeyRequestTime[neighborMac] = now;

  await _sendKeyExchange("KEY_REQ", neighborMac, await _myPublicKeyBase64());
}

// send a key exchange packet KEY_REQ/KEY_RESP;TARGETMAC;PUBLIC_KEY
Future<bool> _sendKeyExchange(String type, String targetMac, String pubBase64) async {
  final packet = "$type;$targetMac;$pubBase64";
  AppLogger.log("ENC", "Sending $type to $targetMac");
  return await sendOnDataChar(packet);
}

Future<void> handleKeyExchangePacket(String rawMsg) async {
  final parts = rawMsg.split(';');
  if (parts.length < 3) return;

  final type = parts[0];
  final senderMac = parts[1];
  final pubKey = parts[2];

  if (pubKey.isEmpty) return;

  final existingKey = await getPeerPublicKey(senderMac);

  if (existingKey != null && existingKey != pubKey) {
    AppLogger.log("ENC", "Key changed for $senderMac. Inserting warning");

    final warningMsg = DbMessage(
      peerMac: senderMac,
      senderName: 'System',
      content: "[Warning] Device may have changed to a different user.",
      isMe: true,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      isBroadcast: false,
      isRead: true,
      status: 'system',
    );
    await insertMessage(warningMsg);
    notifyMessagesUpdated();
  }

  if (type == 'KEY_REQ') {
    await savePeerPublicKey(senderMac, pubKey);
    await _sendKeyExchange("KEY_RESP", senderMac, await _myPublicKeyBase64());
    AppLogger.log("ENC", "Saved key from $senderMac and sent KEY_RESP");
    return;
  }

  if (type == "KEY_RESP") {
    await savePeerPublicKey(senderMac, pubKey);
    AppLogger.log("ENC", "Saved key from $senderMac");
  }
}

Future<String?> encryptOutgoingPayload(String targetMac, String payload) async {
  final peerPubKeyBase64 = await getPeerPublicKey(targetMac);

  if (peerPubKeyBase64 == null) {
    AppLogger.log("ENC", "Missing public key for $targetMac, requesting key...");
    await checkAndRequestKey(targetMac);
    return null;
  }
  try {
    final sharedSecret = await _deriveSharedSecret(peerPubKeyBase64);
    return await CryptoService.encryptMessage(payload, sharedSecret);
  } catch (e) {
    AppLogger.log("ENC", "Encryption error for $targetMac: $e");
    return null;
  }
}

Future<String?> decryptIncomingPayload(String senderMac, String encryptedPayload) async {
  try {
    final peerPubKeyBase64 = await getPeerPublicKey(senderMac);
    if (peerPubKeyBase64 == null) {
      AppLogger.log("ENC", "No public key for $senderMac to decrypt");
      throw Exception("Key is missing");
    }
    final sharedSecret = await _deriveSharedSecret(peerPubKeyBase64);
    return await CryptoService.decryptMessage(encryptedPayload, sharedSecret);
  } catch (e) {
    AppLogger.log("ENC", "Decrypting error from $senderMac: $e");
    try {
      await _sendKeyExchange("KEY_REQ", senderMac, await _myPublicKeyBase64());
    } catch (_) {}
    
    return null;
  }
}
