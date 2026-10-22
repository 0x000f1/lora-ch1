// neighbor handling: GET_NEI polling, parsing, saving peers to db and key requests

import 'dart:async';
import 'package:app/core/color_utils.dart';
import 'package:app/core/constants.dart';
import 'package:app/services/ble_transport.dart';
import 'package:app/services/device_commands.dart';
import 'package:flutter/foundation.dart';

import 'package:app/core/logger.dart';
import 'package:app/services/ble_service.dart';
import 'package:app/services/db_service.dart';
import 'package:app/services/encryption_service.dart';

class PeerDevice {
  final String mac;
  final String rssi;
  final String name;
  final int timeStamp;
  final String colorHex;


  const PeerDevice({
    required this.mac,
    required this.rssi,
    required this.name,
    required this.timeStamp,
    required this.colorHex,
  });

  PeerDevice.fromDb(DbPeer peer)
    : mac = peer.mac,
      name = peer.name,
      colorHex = peer.colorHex ?? '0088FF',
      rssi = peer.rssi ?? '-100',
      timeStamp = peer.lastSeen ?? 0;
}

final ValueNotifier<List<PeerDevice>> neighbors = ValueNotifier([]);

StreamSubscription? _neighborSub;
Timer? _refreshTimer;

void startNeighborProcessing() {
  if (_neighborSub != null) return;

  loadSavedPeers();
  sendOnControlChar("GET_NEI");

  // get neighbors every 30 seconds
  _refreshTimer = Timer.periodic(Duration(seconds: 30), (_) {
    sendOnControlChar("GET_NEI");
    neighbors.value = List.of(neighbors.value);
  });

  _neighborSub = controlStream.listen(_handleNeiPacket);
}

void _handleNeiPacket(String rawMsg) async {
  if (!rawMsg.startsWith("NEI")) return;

  final data = rawMsg.substring(4, rawMsg.length);
  if (data == "NO_NEI") {
    await loadSavedPeers();
    return;
  }

  final Map<String, PeerDevice> deviceMap = {for (var d in neighbors.value) d.mac: d};

  final parts = data.split("|");
  for (var part in parts) {
    if (part.isEmpty) return;
    final deviceData = part.split(';');
    if (deviceData.length < 7) return;
    AppLogger.log("MESH", "Parsed device data: $deviceData");
    final mac = deviceData[0];
    
    // remove delimiters 
    final rawName = deviceData[1];
    String name = rawName.replaceAll(RegExp(r'[;|]'), '').trim();
    name = name.length > 16 ? name.substring(0,16) : (name.isEmpty ? "Unknown" : name);
    
    // validate hex before saving
    final rawColorHex = deviceData[2];
    final colorHex = hexToColor(rawColorHex) != null ? rawColorHex : '0088FF';
    final rssi = deviceData[3];
    int timeStamp = int.tryParse(deviceData[4]) ?? 0;
    if (timeStamp < minValidUnixStamp) {
      timeStamp = 0;
    }
    await savePeer(
      DbPeer(mac: mac, name: name, colorHex: colorHex, rssi: rssi, lastSeen: timeStamp),
    );

    await checkAndRequestKey(mac);

    // add/update devices
    deviceMap[mac] = PeerDevice(
      mac: mac,
      rssi: rssi,
      name: name,
      timeStamp: timeStamp,
      colorHex: colorHex,
    );

    final Map<String, int?> lastMessageTime = {};
    for (final device in deviceMap.values) {
      lastMessageTime[device.mac] = await getLastMessageTimeFromPeer(device.mac);
    }

    // remove current device from the list, if it was previously connected to the phone
    final sortedDevices = deviceMap.values
        .where((device) => device.mac != myDeviceId.value)
        .toList();

    sortedDevices.sort((a, b) {
      final aTime = lastMessageTime[a.mac] ?? 0;
      final bTime = lastMessageTime[b.mac] ?? 0;
      return bTime.compareTo(aTime);
    });

    neighbors.value = sortedDevices;
  }
}

Future<void> loadSavedPeers() async {
  final savedPeers = await getSavedPeers();

  neighbors.value = savedPeers
      // remove my device if it was previously connected
      .where((peer) => peer.mac != myDeviceId.value)
      .map(
        (peer) => PeerDevice(
          mac: peer.mac,
          name: peer.name,
          colorHex: peer.colorHex ?? '0088FF',
          rssi: peer.rssi ?? '-100',
          timeStamp: peer.lastSeen ?? 0,
        ),
      )
      .toList();
}

void stopNeighborProcessing() {
  _refreshTimer?.cancel();
  _refreshTimer = null;
  
  _neighborSub?.cancel();
  _neighborSub = null;
}