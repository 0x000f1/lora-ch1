import 'dart:convert';
import 'package:app/constants.dart';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  // x25519 algorithm used for key exchange
  static final X25519 _keyAlgorithm = X25519();
  
  // aes-256 algorithm used for encrypting data
  static final AesGcm _cipherAlgorithm = AesGcm.with256bits();

  // generate public and private key (32bytes) on first setup
  static Future<SimpleKeyPair> generateKeyPair() async {
    return await _keyAlgorithm.newKeyPair();
  }

  // get base64 public key from SimplePublicKey object
  static Future<String> exportPublicKey(SimplePublicKey publicKey) async {
    return base64Encode(publicKey.bytes);
  }

  // get base64 private key from SimpleKeyPair object
  static Future<String> exportPrivateKey(SimpleKeyPair keyPair) async {
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return base64Encode(privateKeyBytes);
  }
  
  // convert peer's base64 public key into SimplePublicKey object
  static Future<SimplePublicKey> importPublicKey(String base64Key) async {
    final bytes = base64Decode(base64Key);
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  // import local key pair into memory from storage
  static Future<SimpleKeyPair> importKeyPair(
    String base64PrivateKey,
    String base64PublicKey,
  ) async {
    final privBytes = base64Decode(base64PrivateKey);
    final pubBytes = base64Decode(base64PublicKey);
    final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.x25519);

    return SimpleKeyPairData(privBytes, publicKey: publicKey, type: KeyPairType.x25519);
  }
  
  // calculate shared key from peer's public key and own private key
  static Future<SecretKey> deriveSharedSecret(
    SimpleKeyPair myKeyPair,
    SimplePublicKey peerPublicKey,
  ) async {
    return await _keyAlgorithm.sharedSecretKey(keyPair: myKeyPair, remotePublicKey: peerPublicKey);
  }
  
  // encrypt payload with shared key 
  static Future<String> encryptMessage(String plainText, SecretKey sharedKey) async {
    // convert payload into utf8 bytes
    final clearBytes = utf8.encode(plainText);
    // encrypt using aes algorithm
    final secretBox = await _cipherAlgorithm.encrypt(clearBytes, secretKey: sharedKey);
    // final encrypted payload: 12 byte nonce + encrypted text + 16 byte tag (mac) 
    final combined = <int>[...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
    return base64Encode(combined);
  }
  
  // decrypt encrypted base 64 encrypted payload into plain text
  static Future<String> decryptMessage(String base64Payload, SecretKey sharedKey) async {
    final rawBytes = base64Decode(base64Payload);
    // check if payload is too short or corrupted
    if (rawBytes.length < encryptionMetaBytes) {
      throw ArgumentError("Ciphertext payload too short");
    }
    
    // unpack encrypted payload
    final nonce = rawBytes.sublist(0, 12);
    final mac = rawBytes.sublist(rawBytes.length - 16);
    final cipherText = rawBytes.sublist(12, rawBytes.length - 16);
  
    // pass arguments into secretbox for decrypting in next step
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));

    // decrypt using shared key with aes algorithm
    final clearBytes = await _cipherAlgorithm.decrypt(secretBox, secretKey: sharedKey);

    return utf8.decode(clearBytes);
  }
}
