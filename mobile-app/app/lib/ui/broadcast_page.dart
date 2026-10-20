import 'dart:async';
import 'package:flutter/material.dart';

import 'package:app/services/unread_service.dart';
import 'package:app/ui/widgets.dart';
import 'package:app/core/logger.dart';
import 'package:app/services/db_service.dart';
import 'package:app/services/ble_service.dart';

class BroadcastPage extends StatefulWidget {
  final ScrollController scrollController;
  final bool isActive;

  const BroadcastPage({
    super.key,
    required this.scrollController,
    required this.isActive,
  });

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final TextEditingController _controller = TextEditingController();

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

    _dataSub = dataStream.listen((DbMessage msg) async {
      if (mounted) {
        if (msg.isBroadcast) {
          setState(() {
            _messages.add(msg);
          });
          
          if (widget.isActive) {
            await markBroadcastMessagesAsRead();
            await refreshUnreadCount();
          }
        }
      }
    });
  }

  @override
  void dispose() {
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
                status: msg.status,
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
      isBroadcast: true,
      onSend: () async {
        final outMsg = _controller.text;
        if (outMsg.isEmpty) return;

        _controller.clear();

        final success = await sendBroadcastMsg(outMsg);

        final outgoingMessage = DbMessage(
          senderName: "Me",
          content: outMsg,
          isMe: true,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          isBroadcast: true,
          status: success ? 'delivered' : 'failed',
        );

        await InsertMessage(outgoingMessage);

        if (!mounted) return;

        setState(() {
          _messages.add(outgoingMessage);
        });
      },
    );
  }
}
