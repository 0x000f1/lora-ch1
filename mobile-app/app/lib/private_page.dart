import 'dart:async';

import 'package:app/ble_service.dart';
import 'package:flutter/material.dart';

class PeerDevice {
  final String mac;
  final String rssi;
  final String name;

  const PeerDevice({required this.mac, required this.rssi, required this.name});
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

    // "subscribe" to control stream in ble_service.dart
    _controlSub = controlStream.listen((rawMsg) {
      if (mounted) {
        if (rawMsg.contains("BAT") || rawMsg == "GET_NEI") return;
        final List<PeerDevice> parsedDevices = [];
        if (rawMsg == "NO_NEI") {
          setState(() {
            _devices.clear();
          });
          return;
        }
        final parts = rawMsg.split('|');
        for (var part in parts) {
          if (part.isEmpty) continue;
          final deviceData = part.split(';');
          if (deviceData.isNotEmpty) {
            print("Device data: $deviceData");
            final mac = deviceData[0];
            final rssi = deviceData[1];
            final name = "lora-ch-${mac.substring(mac.length - 4)}";
            parsedDevices.add(PeerDevice(mac: mac, rssi: rssi, name: name));
          }
        }
        setState(() {
          _devices.clear();
          _devices.addAll(parsedDevices);
        });
      }
    });
  }

  @override
  void dispose() {
    _controlSub?.cancel();
    print("Control sub canceled");
    super.dispose();
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
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade800,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(
                      device.name,
                      style: TextStyle(color: Colors.black),
                    ),
                    subtitle: Text(
                      device.rssi,
                      style: TextStyle(color: Colors.black),
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
