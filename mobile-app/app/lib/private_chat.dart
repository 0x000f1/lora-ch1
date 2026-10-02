import 'package:app/logger.dart';
import 'package:flutter/material.dart';
import 'package:app/private_page.dart';
import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:app/widgets.dart';

class PrivateMessage {
  final String text;
  final bool isMe;

  PrivateMessage({required this.text, required this.isMe});
}

// temporary list for storing messages before database is implemented
final List<PrivateMessage> _messages = [];

class PrivateChatPage extends StatefulWidget {
  final PeerDevice device;

  const PrivateChatPage({super.key, required this.device});

  @override
  State<PrivateChatPage> createState() => _PrivatePageState();
}

class _PrivatePageState extends State<PrivateChatPage> {
  final TextEditingController _controller = TextEditingController();
  StreamSubscription? _dataSub;

  @override
  void initState() {
    super.initState();
    _dataSub = dataStream.listen((rawMsg) {
      if (mounted) {
        //SENDER_MAC;SENDER_USERNAME;COLOR_HEX;TARGET_MAC;CURRENT_FRAGMENT;TOTAL_FRAGMENTS;TIMESTAMP;RSSI;PAYLOAD
        final parts = rawMsg.split(';');
        if (parts.length >= 8) {
          final senderMac = parts[0];
          final targetMac = parts[3];
          final payload = parts.sublist(8).join(';');
          if (senderMac == widget.device.mac && targetMac != "FFFFFFFF") {
            AppLogger.log("CHAT", "Recieved private message from ${widget.device.name}");
            setState(() {
              _messages.add(PrivateMessage(text: payload, isMe: false));
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return ChatBubble(
                  text: msg.text,
                  senderName: msg.isMe ? "Me" : widget.device.name,
                  isMe: msg.isMe,
                );
              },
            ),
          ),

          ChatInput(
            controller: _controller,
            bottomPadding: 16,
            onSend: () {
              final text = _controller.text;
              if (text.isNotEmpty) {
                sendPrivateMsg(widget.device.mac, text);
                AppLogger.log("CHAT", "Sent private message to ${widget.device.name}");

                setState(() {
                  _messages.add(PrivateMessage(text: text, isMe: true));
                });
              }
              _controller.clear();
            },
          ),
        ],
      ),
    );
  }
}
