import 'dart:math';

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:app/theme.dart';

// SEPERATE FILE FOR WIDGETS THAT BOTH BROADCAST AND PRIVATE PAGE USES
class ChatBubble extends StatelessWidget {
  final String text;
  final String senderName;
  final bool isMe;
  final int timeStamp;
  final String? status;

  const ChatBubble({
    super.key,
    required this.text,
    required this.senderName,
    required this.isMe,
    required this.timeStamp,
    required this.status,
  });

  String _formatTime(int epochSeconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  Widget _buildStatusIcon() {
    if (!isMe) return const SizedBox.shrink();

    IconData icon;
    Color color = Colors.grey;

    switch (status) {
      // message sent, and peer didnt recieve it yet
      case 'sent':
        icon = Icons.check_rounded;
        color = Colors.black;
        break;
      // message sent, and either peer failed to recieve it, or BLE failed to send it
      // on broadcast messages, this only fails if BLE failed to send it
      case 'failed':
        icon = Icons.error_outline_rounded;
        color = Colors.red;
        break;
      // messege sent, and peer recieved it
      // on broadcast messages, this is set by default if BLE sends it
      case 'delivered':
      default:
        icon = Icons.done_all_rounded;
        color = Colors.black;
        break;
    }

    return Icon(icon, size: 12, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(timeStamp);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.all(12),
            decoration: msgDecoration(context, isMe),
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(text, style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          if (timeStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusIcon(),
                  Text(
                    timeStr,
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ChatInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final double bottomPadding;

  const ChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.bottomPadding = 16.0,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  int _byteCount = 0;
  static const int maxBytes =
      960; // max size of one message (4 full 240 byte fragments)

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateByteCount);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateByteCount);
    super.dispose();
  }

  void _updateByteCount() {
    final bytes = utf8.encode(widget.controller.text).length;
    if (bytes != _byteCount) {
      setState(() {
        _byteCount = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOverLimit = _byteCount > maxBytes;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: widget.bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  decoration: InputDecoration(
                    hintText: "Message",
                    filled: false,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    counter: Text(
                      "$_byteCount/$maxBytes",
                      style: TextStyle(
                        fontSize: 10,
                        color: isOverLimit ? Colors.red : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  CircleAvatar(
                    backgroundColor: isOverLimit || _byteCount == 0
                        ? Colors.grey
                        : Colors.blue.shade800,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, size: 20),
                      onPressed: isOverLimit || _byteCount == 0
                          ? null
                          : widget.onSend,
                    ),
                  ),
                  const SizedBox(height: 12,)
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
