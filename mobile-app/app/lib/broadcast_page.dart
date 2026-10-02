import 'dart:async';
import 'dart:developer';
import 'package:app/ble_service.dart';
import 'package:app/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:app/widgets.dart';

class ChatMessage {
  final String text;
  final bool isMe;
  final String senderName;
  final int timestamp;

  ChatMessage({required this.text, required this.isMe, required this.senderName, required this.timestamp});
}

class BroadcastPage extends StatefulWidget {
  final BluetoothDevice? device;
  final ScrollController scrollController;

  const BroadcastPage({super.key, this.device, required this.scrollController});

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final TextEditingController _controller = TextEditingController();

  final List<ChatMessage> _messages = [];
  // connection listener
  StreamSubscription? _connectionSub;
  // data listener
  StreamSubscription? _dataSub;

  @override
  void initState() {
    super.initState();
    _connectionSub = FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
      if (mounted) {
        // redraw on connect or disconnect
        setState(() {});
      }
    });

    _dataSub = dataStream.listen((rawMsg) {
      if (mounted) {
        // SENDER_MAC;SENDER_USERNAME;COLOR_HEX;TARGET_MAC;CURRENT_FRAGMENT;TOTAL_FRAGMENTS;TIMESTAMP;RSSI;PAYLOAD
        final parts = rawMsg.split(';');

        if (parts.length >= 9) {
          AppLogger.log("CHAT", "Recieved broadcast message: $rawMsg");
          final senderUsername = parts[1];
          // use internal time if parsing fails
          final timeStamp = int.tryParse(parts[6]) ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
          // join message in case there is ';' in it
          final payload = parts.sublist(8).join(';');

          setState(() {
            _messages.add(ChatMessage(text: payload, isMe: false, senderName: senderUsername, timestamp: timeStamp));
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
              return ChatBubble(text: msg.text, senderName: msg.senderName, isMe: msg.isMe, timeStamp: msg.timestamp);
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
      onSend: () {
        final text = _controller.text;
        if (text.isNotEmpty) {
          sendBroadcastMsg(text);

          setState(() {
            _messages.add(
              ChatMessage(
                text: text,
                isMe: true,
                senderName: "Me",
                timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              ),
            );
          });
        }
        _controller.clear();
      },
    );
  }
}
