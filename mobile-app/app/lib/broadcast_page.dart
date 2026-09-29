import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:app/bt_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'theme.dart';
import 'package:app/widgets.dart';

class ChatMessage {
  final String text;
  final bool isMe;

  ChatMessage({required this.text, required this.isMe});
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
    _connectionSub = FlutterBluePlus.events.onConnectionStateChanged.listen((
      event,
    ) {
      if (mounted) {
        // redraw on connect or disconnect
        setState(() {});
      }
    });

    _dataSub = dataStream.listen((rawMsg) {
      if (mounted) {
        // SENDER_MAC;SENDER_USERNAME;TARGET_MAC;CURRENT_FRAGMENT;TOTAL_FRAGMENTS;TIMESTAMP;RSSI;PAYLOAD
        final parts = rawMsg.split(';');

        if (parts.length >= 5) {
          print("Recieved message: $rawMsg");
          final senderUsername = parts[1];
          // join message in case there is ';' in it
          final payload = parts.sublist(7).join(';');

          setState(() {
            _messages.add(ChatMessage(text: payload, isMe: false));
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
              return _buildMsgBubble(msg);
            },
          ),
        ),

        _buildInputField(),
      ],
    );
  }

  Widget _buildMsgBubble(ChatMessage msg) {
    String deviceName = "device";

    if (chars.length == 2) {
      deviceName = chars[0].device.platformName;
    }

    return ChatBubble(
      text: msg.text,
      senderName: msg.isMe ? "Me" : "Other User",
      isMe: msg.isMe,
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
            _messages.add(ChatMessage(text: text, isMe: true));
          });
        }
        _controller.clear();
      },
    );
  }
}
