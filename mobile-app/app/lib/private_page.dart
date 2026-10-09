import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:app/logger.dart';
import 'package:flutter/material.dart';
import 'package:app/private_chat.dart';
import 'package:app/db_service.dart';

Color hexToColor(String hex) {
  return Color(int.parse("FF$hex", radix: 16));
}

class PeerDevice {
  final String mac;
  final String rssi;
  final String name;
  final int timeStamp;
  final String colorHex;

  final double? latitude;
  final double? longitude;

  const PeerDevice({
    required this.mac,
    required this.rssi,
    required this.name,
    required this.timeStamp,
    required this.colorHex,
    this.latitude,
    this.longitude,
  });
}

class PrivatePage extends StatefulWidget {
  final ScrollController scrollController;
  const PrivatePage({super.key, required this.scrollController});

  @override
  State<PrivatePage> createState() => _PrivatePageState();
}

class _PrivatePageState extends State<PrivatePage> {
  final List<PeerDevice> _devices = [];
  StreamSubscription? _controlSub;

  Future<void> _loadSavedPeers() async {
    final savedPeers = await getSavedPeers();
    if (!mounted) return;

    setState(() {
      _devices.clear();
      _devices.addAll(
        savedPeers.map(
          (peer) => PeerDevice(
            mac: peer.mac,
            name: peer.name,
            colorHex: peer.colorHex ?? '0088FF',
            rssi: peer.rssi ?? '-100',
            timeStamp: peer.lastSeen ?? 0,
          ),
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSavedPeers();
    sendOnControlChar("GET_NEI");

    // "subscribe" to control stream in ble_service.dart to listen to GET_NEI response
    // NEI|MAC;NEI_USERNAME;COLOR_HEX;RSSI;TIMESTAMP|MAC2;...
    // or NEI|NO_NEI for empty neighbors list
    _controlSub = controlStream.listen((rawMsg) async {
      if (mounted) {
        // only check for responses starting with NEI
        if (!rawMsg.startsWith("NEI")) return;
        AppLogger.log("MESH", "Raw GET_NEI response: $rawMsg");

        // remove NEI flag from the beginning
        rawMsg = rawMsg.substring(4, rawMsg.length);
        if (rawMsg == "NO_NEI") {
          await _loadSavedPeers();
          return;
        }

        // store devices in a map for up to 10 minutes
        final Map<String, PeerDevice> deviceMap = {for (var d in _devices) d.mac: d};

        // Split message after recieving it
        final parts = rawMsg.split('|');
        for (var part in parts) {
          if (part.isEmpty) continue;
          final deviceData = part.split(';');
          // check if data is impact and bypass NO_NEI response
          if (deviceData.length >= 7) {
            AppLogger.log("MESH", "Parsed device data: $deviceData");
            final mac = deviceData[0];
            final name = deviceData[1];
            final colorHex = deviceData[2];
            final rssi = deviceData[3];
            int timeStamp = int.tryParse(deviceData[4]) ?? 0;
            if (timeStamp < 1000000000) {
              timeStamp = 0; // if its unsynced, treat it as unknown
            }
            final latitude = double.tryParse(deviceData[5]) ?? 0;
            final longitude = double.tryParse(deviceData[6]) ?? 0;

            await savePeer(DbPeer(mac: mac, name: name, colorHex: colorHex, rssi: rssi, lastSeen: timeStamp));

            // add/update devices
            deviceMap[mac] = PeerDevice(
              mac: mac,
              rssi: rssi,
              name: name,
              colorHex: colorHex,
              timeStamp: timeStamp,
              latitude: latitude,
              longitude: longitude,
            );
          }
        }

        // get the last message sent/recieved for each peer
        final Map<String, int?> lastMessageTime = {};
        for (final device in _devices) {
          lastMessageTime[device.mac] = await getLastMessageTimeFromPeer(device.mac);
        }

        // sort them by last message sent
        final sortedDevices = deviceMap.values.toList();
        sortedDevices.sort((a, b) {
          final aTime = lastMessageTime[a.mac] ?? 0;
          final bTime = lastMessageTime[b.mac] ?? 0;
          return bTime.compareTo(aTime);
        });

        setState(() {
          _devices.clear();
          _devices.addAll(sortedDevices);
        });
      }
    });
  }

  @override
  void dispose() {
    _controlSub?.cancel();
    AppLogger.log("BLE", "Control subscription canceled");
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // pull to refresh to get neighbors
      body: RefreshIndicator(
        onRefresh: () async {
          await sendOnControlChar("GET_NEI");
          // delayed to show loading animation and recieve neighbors data
          await Future.delayed(const Duration(seconds: 1));
        },
        child: _devices.isNotEmpty
            ? ListView.builder(
                controller: widget.scrollController,
                // required for pull to refresh
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ValueListenableBuilder<bool>(
                    valueListenable: isDeviceConnected,
                    builder: (context, isConnected, child) {
                      return ListTile(
                        onTap: isConnected
                            ? () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => PrivateChatPage(device: device)),
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
                            Text(device.name, style: TextStyle(color: isConnected ? Colors.white : Colors.grey)),
                          ],
                        ),
                        subtitle: Text(
                          "Last Seen: ${_formatLastSeen(device.timeStamp)}",
                          style: TextStyle(color: isConnected ? Colors.white : Colors.grey, fontSize: 11),
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
                controller: widget.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text("No Neighbors")),
                ],
              ),
      ),
    );
  }
}

// get signal strenght from rssi or no signal icon from timestamp for outdates devices
Widget getSignalIconFromRssi(String rssiStr, int timeStamp) {
  final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  const hardwareTtl = 120; // 2 minute ttl on firmware

  // device is considered offline if its missing for more then 2 minteutes
  bool isOffline = ((currentTime - timeStamp) > hardwareTtl);

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
