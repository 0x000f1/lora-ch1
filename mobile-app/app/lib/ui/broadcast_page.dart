import 'dart:async';
import 'package:app/services/messaging_service.dart';
import 'package:flutter/material.dart';

import 'package:app/services/unread_service.dart';
import 'package:app/ui/widgets.dart';
import 'package:app/core/logger.dart';
import 'package:app/services/db_service.dart';
import 'package:app/services/ble_service.dart';

class BroadcastPage extends StatefulWidget {
  final bool isActive;

  const BroadcastPage({super.key, required this.isActive});

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final TextEditingController _controller = TextEditingController();

  final ScrollController _scrollController = ScrollController();

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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
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
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[_messages.length - 1 - index];
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

        await insertMessage(outgoingMessage);

        if (!mounted) return;

        setState(() {
          _messages.add(outgoingMessage);
        });
        _scrollToBottom();
      },
    );
  }
}
