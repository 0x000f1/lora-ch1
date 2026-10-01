import 'package:flutter/material.dart';
import 'package:app/theme.dart';

// SEPERATE FILE FOR WIDGETS THAT BOTH BROADCAST AND PRIVATE PAGE USES
class ChatBubble extends StatelessWidget {
  final String text;
  final String senderName;
  final bool isMe;

  const ChatBubble({
    super.key,
    required this.text,
    required this.senderName,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: msgDecoration(isMe),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              senderName,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 11,
              ),
            ),
            Text(
              text,
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatInput extends StatelessWidget {
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
              onPressed: onSend,
            ),
          ),
        ],
      ),
    );
  }
}