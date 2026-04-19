import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:app/bt_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'theme.dart';

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

  final List<ChatMessage> _messages = [
    ChatMessage(text: "Message", isMe: false),
    ChatMessage(text: "Reply", isMe: true),
    ChatMessage(text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit", isMe: false),
    ChatMessage(text: "sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", isMe: false),
  ];



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
    // placeholder until device is connected
    String deviceName = "device";
    
    if (chars.length == 2) {
      deviceName = chars[0].device.platformName;
    }
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: msgDecoration(msg.isMe),
        child: Column(
          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              deviceName,
              style: TextStyle(
                color: msg.isMe ? Colors.white : Colors.black87,
                fontSize: 8,
                ),
            ),
            Text(
              msg.text,
              style: TextStyle(color: msg.isMe ? Colors.white : Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "Message",
                hintStyle: TextStyle(color: Colors.black),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blue.shade800,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: () {
                debugPrint("Send button pressed ${_controller.text}");
              },
            ),
          ),
        ],
      ),
    );
  }
}
