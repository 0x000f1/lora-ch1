import 'package:app/db_service.dart';
import 'package:app/logger.dart';
import 'package:flutter/material.dart';
import 'package:app/private_page.dart';
import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:app/widgets.dart';

class PrivateChatPage extends StatefulWidget {
  final PeerDevice device;

  const PrivateChatPage({super.key, required this.device});

  @override
  State<PrivateChatPage> createState() => _PrivatePageState();
}

class _PrivatePageState extends State<PrivateChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription? _dataSub;

  final List<DbMessage> _messages = [];

  Future<void> _loadMessages() async {
    final stored = await getPrivateMessages(widget.device.mac);
    if (mounted) {
      setState(() {
        _messages.addAll(stored);
      });
      _scrollToBottom();
    }
  }

  Future<void> _initializeChat() async {
    await _loadMessages();
    await markPrivateMessagesAsRead(widget.device.mac);
    await refreshUnreadCount();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
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
  void initState() {
    super.initState();
    _initializeChat();
    _dataSub = dataStream.listen((rawMsg) async {
      if (mounted) {
        final parts = rawMsg.split(';');

        if (parts.length >= 7) {
          final senderMac = parts[0];
          final targetMac = parts[3];
          final timeStamp =
              int.tryParse(parts[7]) ??
              (DateTime.now().millisecondsSinceEpoch ~/ 1000);
          final payload = parts.sublist(9).join(';');
          AppLogger.log("CHAT", rawMsg);
          if (senderMac == widget.device.mac && targetMac != "FFFFFFFF") {
            AppLogger.log(
              "CHAT",
              "Recieved private message from ${widget.device.name}",
            );
            setState(() {
              _messages.add(
                DbMessage(
                  peerMac: widget.device.mac,
                  senderName: widget.device.name,
                  content: payload,
                  isMe: false,
                  timestamp: timeStamp,
                  isBroadcast: false,
                ),
              );
            });
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                // build messages in reverse so scrollcontroller can jump to bottom while loading messages
                final msg = _messages[_messages.length - 1 - index];
                return ChatBubble(
                  text: msg.content,
                  senderName: msg.isMe ? "Me" : widget.device.name,
                  isMe: msg.isMe,
                  timeStamp: msg.timestamp,
                  status: msg.status,
                );
              },
            ),
          ),

          ChatInput(
            controller: _controller,
            bottomPadding: 16,
            onSend: () async {
              final outMsg = _controller.text;
              if (outMsg.isEmpty) return;

              _controller.clear();

              AppLogger.log(
                "CHAT",
                "Sent private message to ${widget.device.name}",
              );
              final outMessage = DbMessage(
                peerMac: widget.device.mac,
                senderName: "Me",
                content: outMsg,
                isMe: true,
                timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                isBroadcast: false,
                status: 'sent',
              );

              final messageId = await InsertMessage(outMessage);

              if (!mounted) return;

              setState(() {
                _messages.add(outMessage);
              });

              bool success = await sendPrivateMsg(widget.device.mac, outMsg);

              if (!mounted) return;

              setState(() {
                outMessage.status = success ? 'delivered' : 'failed';
              });

              await markMessageDelivery(messageId, success);
            },
          ),
        ],
      ),
    );
  }
}
