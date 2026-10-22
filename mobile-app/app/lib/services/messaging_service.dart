// messaging logic, ACK handling and database sync of messages

import 'dart:async';
import 'dart:convert';

import 'package:app/core/constants.dart';
import 'package:app/services/db_service.dart';
import 'package:app/core/logger.dart';
import 'package:app/services/ble_transport.dart';
import 'package:app/services/encryption_service.dart';
import 'package:app/services/message_fragmenter.dart';
import 'package:app/services/unread_service.dart';

// finished messages (assambed, decryped and saved)
final _messageStreamController = StreamController<DbMessage>.broadcast();

// trigger to notify UI to refresh chat when old messages are decrypted
final _messageUpdateStreamController = StreamController<void>.broadcast();
Stream<void> get messageUpdateStream => _messageUpdateStreamController.stream;

// stream for finished messages
Stream<DbMessage> get dataStream => _messageStreamController.stream;

StreamSubscription<String>? _rawDataSub;

// starts processing raw packets
void startMessageProcessing() {
  _rawDataSub ??= rawDataStream.listen(_handleRawPacket);
}

Future<void> _handleRawPacket(String rawMsg) async {
  AppLogger.log("RX", "raw packet (${utf8.encode(rawMsg).length} bytes): $rawMsg");

  // ACK and timeout handled in _sendFragmentWithAck
  if (rawMsg.startsWith("ACK_OK") || rawMsg.startsWith("ERR_TIMEOUT")) return;

  // KEY_REQ and KEY_RESP
  if (rawMsg.startsWith("KEY_REQ") || rawMsg.startsWith("KEY_RESP")) {
    await handleKeyExchangePacket(rawMsg);
    return;
  }

  final assambled = handleIncomingFragments(rawMsg);
  if (assambled == null) return;


  final savedMessage = await _saveIncomingMessageToDb(assambled);
  if (savedMessage == null) return;

  _messageStreamController.add(savedMessage);
}

// processes and saves incoming message, stores ciphertext if decryption fails
Future<DbMessage?> _saveIncomingMessageToDb(String rawMsg) async {
  final parts = rawMsg.split(';');
  if (parts.length < 7) return null;

  final senderMac = parts[0];
  final senderUser = parts[1];
  final targetMac = parts[3];
  
  // if timestamp is too low (failed to set), use device time
  int timeStamp = int.tryParse(parts[4]) ?? 0;
  if (timeStamp < minValidUnixStamp) {
    timeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }
  
  final payload = parts.sublist(6).join(';');
  final isBroadcast = targetMac == broadcastMac;

  // get decrypted text or fallback to storing raw payload with undecryptable state
  final (content, ciphertext, state) = await processIncomingAssambledMessage(
    senderMac,
    targetMac,
    payload,
  );

  final message = DbMessage(
    peerMac: isBroadcast ? null : senderMac,
    senderName: senderUser,
    content: content,
    isMe: false,
    timestamp: timeStamp,
    isBroadcast: isBroadcast,
    isRead: false,
    ciphertext: ciphertext,
    state: state,
  );

  await insertMessage(message);
  await refreshUnreadCount();

  return message;
}

// attempts to decrypt payload, returns record with content, raw ciphertext, and state
Future<(String content, String? ciphertext, String state)> processIncomingAssambledMessage(
  String senderMac,
  String targetMac,
  String payload,
) async {
  if (targetMac == broadcastMac) {
    return (payload, null, 'ok');
  }

  try {
    final decryptedText = await decryptIncomingPayload(senderMac, payload);
    return (decryptedText, null, 'ok');
  } catch (e) {
    return ('', payload, 'undecryptable');
  }
}

// retries decryption for failed messages when a new key arrives
Future<void> retryUndecryptableMessages(String peerMac) async {
  final messages = await getUndecryptableMessages(peerMac);
  bool updatedAny = false;
  
  for (var msg in messages) {
    if(msg.ciphertext == null || msg.id == null) continue;
    try {
      final clearText = await decryptIncomingPayload(peerMac, msg.ciphertext!);
      await updateMessageContent(msg.id!, clearText, 'ok');
      updatedAny = true;
    } catch (e) {
      // keep as undecryptable
    }

  }
  
  // notify UI to refresh messages when any were successfully decrypted
  if(updatedAny) {
    _messageUpdateStreamController.add(null);
  }
}

// returns true if a message got an ack_ok response, false otherwise
Future<bool> _sendFragmentWithAck(String packet, String targetMac, int payloadBytes) async {
  // 3,5 seconds + 50ms/byte maximum timeout
  final timeout = Duration(milliseconds: 3500 + (payloadBytes * 100));

  // start stream before sending data
  final ackFuture = rawDataStream
      .firstWhere(
        (msg) => msg.startsWith("ACK_OK;$targetMac") || msg.startsWith("ERR_TIMEOUT;$targetMac"),
      )
      .timeout(timeout);

  await sendOnDataChar(packet);

  try {
    final response = await ackFuture;
    AppLogger.log("BLE", "Response to fragment: $response");
    return response.startsWith("ACK_OK");
  } catch (e) {
    AppLogger.log("BLE", "No response to fragment within ${timeout.inMilliseconds} ms: $e");
    return false;
  }
}

// null while no message is being sent
Completer<void>? _currentSend;

// send every fragment, one at a time
Future<bool> _sendMessage(String targetMac, String msg) async {
  // wait until another message is being sent
  while (_currentSend != null) {
    await _currentSend!.future;
  }

  // mark send as busy
  _currentSend = Completer<void>();
  try {
    return await _sendFragments(targetMac, msg);
  } finally {
    final done = _currentSend!;
    _currentSend = null;
    done.complete();
  }
}

// splits the message and sends every fragment
// returns true if every fragment got an ACK
// false means the message may still arrived, but device didn't recieve ACK
Future<bool> _sendFragments(String targetMac, String msg) async {
  final fragments = splitMessage(msg);
  final isBroadcast = targetMac == broadcastMac;

  // turns false if one fragment didnt confirm with ACK, but keep sending after
  bool allAcked = true;

  for (int i = 0; i < fragments.length; i++) {
    final payload = fragments[i];
    final packet = "$targetMac;${i + 1};${fragments.length};$payload";

    AppLogger.log("BLE", "Sending fragment ${i + 1}/${fragments.length} ($payload)");

    if (isBroadcast) {
      // no ACK on broadcast so treat it as delivered if BLE sends it
      final success = await sendOnDataChar(packet);
      if (!success) {
        AppLogger.log("BLE", "Failed to send broadcast fragment ${i + 1}/${fragments.length}");
        return false;
      }
      continue;
    }

    // send every packet with a seperate ACK check
    final payloadBytes = utf8.encode(payload).length;
    final ackReceived = await _sendFragmentWithAck(packet, targetMac, payloadBytes);

    if (ackReceived) {
      AppLogger.log("BLE", "ACK recieved for fragment ${i + 1}/${fragments.length}");
    }

    if (!ackReceived) {
      AppLogger.log("BLE", "No ACK for fragment ${i + 1}/${fragments.length}.");
      allAcked = false;
    }
  }

  AppLogger.log("CHAT", "Sent message: $msg");
  return allAcked;
}

// sends a broadcast message (no ACK, not encrypted)
Future<bool> sendBroadcastMsg(String msg) async {
  bool success = await _sendMessage(broadcastMac, msg);
  AppLogger.log("CHAT", "Sent broadcast message $msg");
  return success;
}

// encrypts and sends a private message to peer
Future<bool> sendPrivateMsg(String targetMac, String msg) async {
  final encryptedPayload = await encryptOutgoingPayload(targetMac, msg);

  // no key for this peer yet
  if (encryptedPayload == null) {
    AppLogger.log("CHAT", "Cannot send private message to $targetMac: ecnryption failed");
    return false;
  }

  bool success = await _sendMessage(targetMac, encryptedPayload);
  AppLogger.log("CHAT", "Sent private message $encryptedPayload ($msg) to $targetMac");
  return success;
}
