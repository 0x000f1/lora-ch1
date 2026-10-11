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
final _dataStreamController = StreamController<String>.broadcast();

// stream for finished messages
Stream<String> get dataStream => _dataStreamController.stream;

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
  
  final processed = await processIncomingAssambledMessage(assambled);
  
  await _saveIncomingMessageToDb(processed);
  _dataStreamController.add(processed);
  
}

Future<void> _saveIncomingMessageToDb(String rawMsg) async {
  final parts = rawMsg.split(';');
  if (parts.length >= 7) {
    final senderMac = parts[0];
    final senderUser = parts[1];
    final targetMac = parts[3];
    final timeStamp = int.tryParse(parts[4]) ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final payload = parts.sublist(6).join(';');
    final isBroadcast = targetMac == broadcastMac;

    final message = DbMessage(
      peerMac: isBroadcast ? null : senderMac,
      senderName: senderUser,
      content: payload,
      isMe: false,
      timestamp: timeStamp,
      isBroadcast: isBroadcast,
      isRead: false,
    );
    await InsertMessage(message);
    await refreshUnreadCount();
  }
}

Future<String> processIncomingAssambledMessage(String assambled) async {
  final parts = assambled.split(';');
  if (parts.length < 7) return assambled;
  
  final senderMac = parts[0];
  final targetMac = parts[3];
  final isBroadcast = targetMac == broadcastMac;
  
  if(isBroadcast) {
    return assambled;
  }
  
  final encryptedPayload = parts.sublist(6).join(';');
  AppLogger.log("ENC", "Recieved encrypted message: $encryptedPayload");
  final decryptedText = await decryptIncomingPayload(senderMac, encryptedPayload);
  final prefix = parts.sublist(0, 6).join(';');
  
  return "$prefix;$decryptedText";
  
}

// returns true if a message got an ack_ok response, false otherwise
Future<bool> _sendFragmentWithAck(String packet, String targetMac, int payloadBytes) async {
  // 3,5 seconds + 50ms/byte maximum timeout
  final timeout = Duration(milliseconds: 3500 + (payloadBytes * 50));

  // start stream before sending data
  final ackFuture = rawDataStream
      .firstWhere((msg) => msg.startsWith("ACK_OK;$targetMac") || msg.startsWith("ERR_TIMEOUT;$targetMac"))
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

Future<bool> _sendMessage(String targetMac, String msg) async {
  final fragments = splitMessage(msg);
  final isBroadcast = targetMac == broadcastMac;

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
      AppLogger.log("BLE", "ACK timeout for message: $msg");
      return false;
    }
  }

  AppLogger.log("CHAT", "Sent message: $msg");
  return true;
}

Future<bool> sendBroadcastMsg(String msg) async {
  bool success = await _sendMessage(broadcastMac, msg);
  AppLogger.log("CHAT", "Sent broadcast message $msg");
  return success;
}

Future<bool> sendPrivateMsg(String targetMac, String msg) async {
  final encryptedPayload = await encryptOutgoingPayload(targetMac, msg);
  
  if(encryptedPayload == null) {
    AppLogger.log("CHAT", "Cannot send private message to $targetMac: ecnryption failed");
    return false;
  }
  
  bool success = await _sendMessage(targetMac, encryptedPayload);
  AppLogger.log("CHAT", "Sent private message $encryptedPayload ($msg) to $targetMac");
  return success;
}
