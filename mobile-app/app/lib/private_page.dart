import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:flutter/material.dart';
import 'package:app/private_chat.dart';

class PeerDevice {
  final String mac;
  final String rssi;
  final String name;
  final int timeStamp;

  const PeerDevice({
    required this.mac,
    required this.rssi,
    required this.name,
    required this.timeStamp,
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
  @override
  void initState() {
    super.initState();
    sendOnControlChar("GET_NEI");

    // "subscribe" to control stream in ble_service.dart to listen to GET_NEI response
    // NEI|MAC;NEI_USERNAME;RSSI;TIMESTAMP|MAC;etc...
    // or NEI|NO_NEI for empty neighbors list
    _controlSub = controlStream.listen((rawMsg) {
      if (mounted) {
        // only check for responses starting with NEI
        if (!rawMsg.startsWith("NEI")) return;
        debugPrint("rawMSG = $rawMsg");

        // remove NEI flag from the beginning
        rawMsg = rawMsg.substring(4, rawMsg.length);

        // store devices in a map for up to 10 minutes
        final Map<String, PeerDevice> deviceMap = {
          for (var d in _devices) d.mac: d,
        };

        final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        const ttlLimit = 600; // timeout after 10 minutes

        // Split message after recieving it
        final parts = rawMsg.split('|');
        for (var part in parts) {
          if (part.isEmpty) continue;
          final deviceData = part.split(';');
          // check if data is impact and bypass NO_NEI response
          if (deviceData.length > 3) {
            debugPrint("Device data: $deviceData");
            final mac = deviceData[0];
            final name = deviceData[1];
            final rssi = deviceData[2];

            int timeStamp = int.tryParse(deviceData[3]) ?? 0;
            if (timeStamp < 1000000000) {
              timeStamp = 0; // if its unsynced, treat it as unknown
            }

            // add/update devices
            deviceMap[mac] = PeerDevice(
              mac: mac,
              rssi: rssi,
              name: name,
              timeStamp: timeStamp,
            );
          }
        }

        // remove devices older then 10 minutes
        deviceMap.removeWhere((mac, device) {
          if (device.timeStamp == 0) return false;
          return (currentTime - device.timeStamp) > ttlLimit;
        });

        setState(() {
          _devices.clear();
          _devices.addAll(deviceMap.values);
        });
      }
    });
  }

  @override
  void dispose() {
    _controlSub?.cancel();
    debugPrint("Control sub canceled");
    super.dispose();
  }

  String _formatLastSeen(int timeStamp) {
    if (timeStamp == 0) return "Unknown";
    final lastSeenTime = DateTime.fromMillisecondsSinceEpoch(timeStamp * 1000);
    final difference = DateTime.now().difference(lastSeenTime);

    if (difference.inMinutes < 1) {
      return "Just now";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes}m ago";
    } else {
      return "${difference.inHours}h ago";
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
                  return ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PrivateChatPage(device: device),
                        ),
                      );
                    },
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade800,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Row(
                      children: [
                        getSignalIconFromRssi(device.rssi, device.timeStamp),
                        Text(
                          device.name,
                          style: TextStyle(color: Colors.black),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      "Last Seen: ${_formatLastSeen(device.timeStamp)}",
                      style: TextStyle(color: Colors.black, fontSize: 11),
                    ),
                  );
                },
              )
            // scrollable widget needed for pull to refresh
            : ListView(
                controller: widget.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 200),
                  Center(
                    child: Text(
                      "No Neighbors",
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
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
    return const Icon(
      Icons.signal_cellular_nodata_rounded,
      color: Colors.black,
      size: 16,
    );
  }

  double rssi = double.tryParse(rssiStr) ?? -100;
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
