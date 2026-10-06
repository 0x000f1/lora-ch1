import 'dart:async';
import 'dart:developer';
import 'package:app/ble_service.dart';
import 'package:app/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:app/widgets.dart';
import 'package:app/db_service.dart';

class BroadcastPage extends StatefulWidget {
  final BluetoothDevice? device;
  final ScrollController scrollController;

  const BroadcastPage({super.key, this.device, required this.scrollController});

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final TextEditingController _controller = TextEditingController();

  // connection listener
  StreamSubscription? _connectionSub;
  // data listener
  StreamSubscription? _dataSub;

  final List<DbMessage> _messages = [];

  Future<void> _loadMessages() async {
    // load every broadcast message from database
    final stored = await getBroadcastMessage();
    if (mounted) {
      setState(() {
        _messages.addAll(stored);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMessages();

    _connectionSub = FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
      if (mounted) {
        // redraw on connect or disconnect
        setState(() {});
      }
    });

    _dataSub = dataStream.listen((rawMsg) async {
      if (mounted) {
        // sent from ble stream with fragment info removed:
        // SENDER_MAC;SENDER_USERNAME;COLOR_HEX;TARGET_MAC;TIMESTAMP;RSSI;PAYLOAD
        final parts = rawMsg.split(';');

        if (parts.length >= 7 && parts[3] == 'FFFFFFFF') {
          AppLogger.log("CHAT", "Recieved broadcast message: $rawMsg");
          final senderUsername = parts[1];
          // use internal time if parsing fails
          final timeStamp = int.tryParse(parts[4]) ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
          // join message in case there is ';' in it
          final payload = parts.sublist(6).join(';');

          setState(() {
            _messages.add(
              DbMessage(
                senderName: senderUsername,
                content: payload,
                isMe: false,
                timestamp: timeStamp,
                isBroadcast: true,
              ),
            );
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _dataSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return ChatBubble(
                text: msg.content,
                senderName: msg.senderName,
                isMe: msg.isMe,
                timeStamp: msg.timestamp,
              );
            },
          ),
        ),

        _buildInputField(),
      ],
    );
  }

  Widget _buildInputField() {
    return ChatInput(
      controller: _controller,
      bottomPadding: 90.0,
      onSend: () async {
        final outMsg = _controller.text;
        if (outMsg.isNotEmpty) {
          sendBroadcastMsg(outMsg);
          
          final outgoingMessage = DbMessage(
            senderName: "Me",
            content: outMsg,
            isMe: true,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            isBroadcast: true,
          );
          
          await InsertMessage(outgoingMessage);

          setState(() {
            _messages.add(outgoingMessage);
          });
        }
        _controller.clear();
      },
    );
  }
}
