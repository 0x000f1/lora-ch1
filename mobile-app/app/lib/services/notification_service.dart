import 'dart:async';

import 'package:app/core/constants.dart';
import 'package:app/services/ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app/core/logger.dart';

// plugin for local notifications
final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

// mac of the private chat that is currently open
String? activeChatMac;

// tracks if app is currently visible, or in the background
bool _isAppInForeground = true;

// listens to app lifecycle changes (foreground/background)
AppLifecycleListener? _lifecycleListener;

// incoming, processed messages
StreamSubscription<String>? _messageSub;

// stream to forward notification tap events
StreamController<String> notificationTapStream = StreamController<String>.broadcast();

const int _connectionNotificationId = 1;

const _connectionChannel = AndroidNotificationDetails(
  'connection_channel',
  'Device connection',
  channelDescription: "Shown while app is still connected to the device",
  importance: .low,
  priority: .low,
  ongoing: true,
);

const _messageChannel = AndroidNotificationDetails(
  'chat_channel',
  'Chat messages',
  channelDescription: 'Incoming private messages.',
  importance: Importance.max,
  priority: Priority.high,
);

Future<void> initNotifications() async {
  const androidInitializationSettings = AndroidInitializationSettings("@mipmap/ic_launcher");

  final initializationSettings = InitializationSettings(android: androidInitializationSettings);

  await _plugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (response) {
      final peerMac = response.payload;
      if (peerMac != null) {
        // send the tapped peer's MAC to the stream so the UI can navigate there
        notificationTapStream.add(peerMac);
      }
    },
  );

  _lifecycleListener ??= AppLifecycleListener(
    onStateChange: (state) => _isAppInForeground = state == AppLifecycleState.resumed,
  );
}

Future<void> requestNotificationPermission() async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<String?> getLaunchNotificationPeerMac() async {
  // check if app was started by a notification
  final details = await _plugin.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp ?? false) {
    // return private mac for notification, or broadcast 
    return details!.notificationResponse?.payload;
  }
  return null;
}

// keeps app process alive while device is connected
Future<void> _startConnectionService() async {
  try {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.startForegroundService(
          id: _connectionNotificationId,
          title: 'Connected to LoRa device',
          body: 'Receiving messages in background',
          notificationDetails: _connectionChannel,
          foregroundServiceTypes: {.foregroundServiceTypeConnectedDevice},
        );
  } catch (e) {
    AppLogger.log("NOTIF", "Could not start foreground service: $e");
  }
}

Future<void> _stopConnectionService() async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.stopForegroundService();
}

void _onConnectionChanged() {
  if (isDeviceConnected.value) {
    _startConnectionService();
  } else {
    _stopConnectionService();
  }
}

int _notificationId(String peerMac) {
  // unique id for broadcast messages
  if (peerMac == "BROADCAST") return 999;

  // 32 bit integer needed for id
  return int.tryParse(peerMac, radix: 16)?.toSigned(32) ?? 0;
}

Future<void> _showNotification(String peerMac, String title, String body) async {
  const platformDetails = NotificationDetails(android: _messageChannel);

  await _plugin.show(
    id: _notificationId(peerMac),
    title: title,
    body: body,
    notificationDetails: platformDetails,
    payload: peerMac,
  );
}

// remove notification when the user opens that chat
Future<void> cancelChatNotification(String peerMac) {
  return _plugin.cancel(id: _notificationId(peerMac));
}

// listens to finished messages (assambled, decrypted, saved)
void setupNotificationListener() {
  // dont subscribe more then once
  if (_messageSub != null) return;
  _messageSub = dataStream.listen(_onMessage);
  isDeviceConnected.addListener(_onConnectionChanged);
}

Future<void> _onMessage(String rawMsg) async {
  final parts = rawMsg.split(';');
  if (parts.length < 7) return;
  final senderMac = parts[0];
  final senderUser = parts[1];
  final targetMac = parts[3];
  final payload = parts.sublist(6).join(';');

  // handle broadcast notifications seperately,
  // only send broadcast notification if the broadcast tab is
  // hidden when private chat is open with a peer
  if (targetMac == broadcastMac) {
    if (!_isAppInForeground || activeChatMac != null) {
      await _showNotification("BROADCAST", "Broadcast: $senderUser", payload);
    }
    return;
  }

  // only skip it while the user is looking at this chat
  if (_isAppInForeground && activeChatMac == senderMac) return;
  await _showNotification(senderMac, senderUser, payload);
}
