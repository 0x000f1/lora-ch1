import 'dart:async';
import 'dart:convert';
import 'package:app/services/ble_transport.dart';
import 'package:flutter/material.dart';

import 'package:app/ui/private_chat.dart';
import 'package:app/services/ble_service.dart';
import 'package:app/core/logger.dart';
import 'package:app/services/db_service.dart';
import 'package:app/services/unread_service.dart';
import 'package:app/core/color_utils.dart';
import 'package:app/services/neighbor_service.dart';

class PrivatePage extends StatelessWidget {
  const PrivatePage({super.key, required this.scrollController});
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // pull to refresh to get neighbors
      body: ValueListenableBuilder(
        valueListenable: neighbors,
        builder: (context, devices, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await sendOnControlChar("GET_NEI");
              // delayed to show loading animation and recieve neighbors data
              await Future.delayed(const Duration(seconds: 1));
            },
            child: devices.isNotEmpty
                ? ListView.builder(
                    controller: scrollController,
                    // required for pull to refresh
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ValueListenableBuilder<bool>(
                        valueListenable: isDeviceConnected,
                        builder: (context, isConnected, child) {
                          return ListTile(
                            onTap: isConnected
                                ? () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PrivateChatPage(device: device),
                                      ),
                                    );
                                    // only refresh unread count after returning from private chat page
                                    await refreshUnreadCount();
                                  }
                                : null,
                            leading: CircleAvatar(
                              backgroundColor: hexToColor(device.colorHex),
                              child: const Icon(Icons.person, color: Colors.white),
                            ),
                            title: Row(
                              children: [
                                getSignalIconFromRssi(device.rssi, device.timeStamp),
                                Text(
                                  device.name,
                                  style: TextStyle(color: isConnected ? Colors.white : Colors.grey),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              "Last Seen: ${_formatLastSeen(device.timeStamp)}",
                              style: TextStyle(
                                color: isConnected ? Colors.white : Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                            trailing: ValueListenableBuilder<int>(
                              valueListenable: unreadUpdateTrigger,
                              builder: (context, _, _) {
                                return FutureBuilder<int>(
                                  future: getUnreadPrivateCountForPeer(device.mac),
                                  builder: (context, snapshot) {
                                    final count = snapshot.data ?? 0;
                                    return Badge(
                                      isLabelVisible: count > 0,
                                      label: Text('$count'),
                                      backgroundColor: Colors.red.shade300,
                                    );
                                  },
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  )
                // scrollable widget needed for pull to refresh
                : ListView(
                    controller: scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text("No Neighbors")),
                    ],
                  ),
          );
        }
      ),
    );
  }
}

// get signal strenght from rssi or no signal icon from timestamp for outdates devices
Widget getSignalIconFromRssi(String rssiStr, int timeStamp) {
  final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // mark user unreachable, if it was not seen for more then 60 seconds (2 heartbeats on hardware)
  const ttl = 60;

  // device is considered offline if its missing for more then 2 minteutes
  bool isOffline = ((currentTime - timeStamp) > ttl);

  if (isOffline) {
    return const Icon(Icons.signal_cellular_nodata_rounded, color: Colors.grey, size: 16);
  }

  double rssi = double.tryParse(rssiStr) ?? -100;
  AppLogger.log("[MESH]", "RSSI Value: $rssiStr");
  IconData iconData;
  Color iconColor;

  if (rssi >= -90) {
    iconData = Icons.signal_cellular_alt_rounded;
    iconColor = Colors.green;
  } else if (rssi >= -110) {
    iconData = Icons.signal_cellular_alt_2_bar_rounded;
    iconColor = Colors.orange;
  } else {
    iconData = Icons.signal_cellular_alt_1_bar_rounded;
    iconColor = Colors.red;
  }

  return Icon(iconData, size: 20, color: iconColor);
}

String _formatLastSeen(int timeStamp) {
    if (timeStamp == 0) return "Unknown";
    final lastSeenTime = DateTime.fromMillisecondsSinceEpoch(timeStamp * 1000);
    final difference = DateTime.now().difference(lastSeenTime);

    if (difference.inSeconds < 30) {
      return "Just now";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes}m ago";
    } else if (difference.inHours < 24) {
      return "${difference.inHours}h ago";
    } else {
      return "${difference.inDays}d ago";
    }
  }
