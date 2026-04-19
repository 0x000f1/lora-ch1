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

  final List<ChatMessage> _messages = [];
  // connection listener
  StreamSubscription? _connectionSub;
  // data listener
  StreamSubscription? _dataSub;


  void initState() {
    super.initState();
    _connectionSub = FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
      setState(() {});
    });

    _dataSub = dataStream.listen((rawMsg) {
      if(mounted) {
        final parts = rawMsg.split(';');

        if (parts.length >= 5){
          final senderMac = parts[0];
          // join message in case there is ';' in it
          final payload = parts.sublist(4).join(';'); 

          setState(() {
            _messages.add(ChatMessage(text: payload, isMe: false));
          });
        }
      }
    });

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
                final text = _controller.text;
                if (text.isNotEmpty) {
                  sendBroadcastMsg(text);

                  setState(() {
                    _messages.add(ChatMessage(text: text, isMe: true));
                  });
                }
                _controller.clear();


              },
            ),
          ),
        ],
      ),
    );
  }
}
