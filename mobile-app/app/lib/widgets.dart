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

  const ChatBubble({
    super.key,
    required this.text,
    required this.senderName,
    required this.isMe,
    required this.timeStamp,
  });

  String _formatTime(int epochSeconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(timeStamp);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.all(12),
            decoration: msgDecoration(isMe),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(text, style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
              ],
            ),
          ),
          if (timeStr.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 10)),
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

  const ChatInput({super.key, required this.controller, required this.onSend, this.bottomPadding = 16.0});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  int _byteCount = 0;
  static const int maxBytes = 1024; // max size of one message
  static const int chunkSize = 240; // max size of one fragment

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
      padding: EdgeInsets.only(left: 16, right: 16, bottom: widget.bottomPadding),
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
                    hintStyle: const TextStyle(color: Colors.black),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    counter: Text(
                      "$_byteCount/$maxBytes",
                      style: TextStyle(fontSize: 10, color: isOverLimit ? Colors.red : Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: isOverLimit || _byteCount == 0 ? Colors.grey : Colors.blue.shade800,
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  onPressed: isOverLimit || _byteCount == 0 ? null : widget.onSend,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
