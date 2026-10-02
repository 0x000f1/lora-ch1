import 'package:flutter/material.dart';
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

class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final double bottomPadding;

  const ChatInput({super.key, required this.controller, required this.onSend, this.bottomPadding = 16.0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "Message",
                hintStyle: const TextStyle(color: Colors.black),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blue.shade800,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: onSend,
            ),
          ),
        ],
      ),
    );
  }
}
