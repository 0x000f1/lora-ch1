import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static void log(String category, String message) {
    if (kDebugMode) {
      final formattedTime = DateTime.now().toString().substring(11, 19);
      debugPrint("[LOGGER][$category][$formattedTime] -> $message");
    }
  }
}

class LogCoordinate {
  const LogCoordinate(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.senderUser,
    required this.receiverUser,
    required this.seqNumber,
    required this.rssi,
    required this.snr,
    required this.rtt,
    required this.environment,
    required this.distance,
    required this.senderLat,
    required this.senderLon,
    required this.receiverLat,
    required this.receiverLon,
    required this.battery,
  });

  final String timestamp;
  final String senderUser;
  final String receiverUser;
  final String seqNumber;
  final String rssi;
  final String snr;
  final String rtt;
  final String environment;
  final String distance;
  final String senderLat;
  final String senderLon;
  final String receiverLat;
  final String receiverLon;
  final String battery;

  Map<String, dynamic> toJson() => {
    'Timestamp': timestamp,
    'Sender User': senderUser,
    'Receiver User': receiverUser,
    'Seq Number': seqNumber,
    'RSSI (dBm)': rssi,
    'SNR (dB)': snr,
    'RTT (ms)': rtt,
    'Environment': environment,
    'Distance (m)': distance,
    'Sender Lat': senderLat,
    'Sender Lon': senderLon,
    'Receiver Lat': receiverLat,
    'Receiver Lon': receiverLon,
    'Battery (%)': battery,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    timestamp: '${json['Timestamp'] ?? ''}',
    senderUser: '${json['Sender User'] ?? ''}',
    receiverUser: '${json['Receiver User'] ?? ''}',
    seqNumber: '${json['Seq Number'] ?? ''}',
    rssi: '${json['RSSI (dBm)'] ?? ''}',
    snr: '${json['SNR (dB)'] ?? ''}',
    rtt: '${json['RTT (ms)'] ?? ''}',
    environment: '${json['Environment'] ?? ''}',
    distance: '${json['Distance (m)'] ?? ''}',
    senderLat: '${json['Sender Lat'] ?? ''}',
    senderLon: '${json['Sender Lon'] ?? ''}',
    receiverLat: '${json['Receiver Lat'] ?? ''}',
    receiverLon: '${json['Receiver Lon'] ?? ''}',
    battery: '${json['Battery (%)'] ?? ''}',
  );
}

final Map<String, LogCoordinate> logNeighborLocations = {};
LogCoordinate? currentLogLocation;

void updateLogNeighborLocation(String mac, double latitude, double longitude) {
  logNeighborLocations[mac] = LogCoordinate(latitude, longitude);
}

void updateCurrentLogLocation(double latitude, double longitude) {
  currentLogLocation = LogCoordinate(latitude, longitude);
}

class LogManager {
  static const labels = [
    'Timestamp',
    'Sender User',
    'Receiver User',
    'Seq Number',
    'RSSI (dBm)',
    'SNR (dB)',
    'RTT (ms)',
    'Environment',
    'Distance (m)',
    'Sender Lat',
    'Sender Lon',
    'Receiver Lat',
    'Receiver Lon',
    'Battery (%)',
  ];

  static const _ioTimeout = Duration(seconds: 3);
  static Future<void> _writeQueue = Future<void>.value();

  static Future<Directory> _directory() async {
    final base = await getApplicationSupportDirectory().timeout(_ioTimeout);
    final directory = Directory(path.join(base.path, 'lora_logs'));
    await directory.create(recursive: true).timeout(_ioTimeout);
    return directory;
  }

  static Future<File> _stateFile() async {
    final directory = await _directory();
    return File(path.join(directory.path, '.current'));
  }

  static String _safeName(String value) {
    final safe = value.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9_\- áéíóöőúüűÁÉÍÓÖŐÚÜŰ]'),
      '_',
    );
    return safe.isEmpty ? 'log' : safe;
  }

  static Future<String?> currentName() async {
    final file = await _stateFile().timeout(_ioTimeout);
    if (!await file.exists().timeout(_ioTimeout)) return null;
    final value = (await file.readAsString().timeout(_ioTimeout)).trim();
    return value.isEmpty ? null : value;
  }

  static Future<String> startNew(String requestedName) async {
    final name = _safeName(requestedName);
    final completer = Completer<String>();
    _writeQueue = _writeQueue
        .then((_) async {
          try {
            final directory = await _directory();
            final fileName =
                '$name-${DateTime.now().millisecondsSinceEpoch}.jsonl';
            final file = File(path.join(directory.path, fileName));
            await file.writeAsString('').timeout(_ioTimeout);
            final stateFile = await _stateFile().timeout(_ioTimeout);
            await stateFile.writeAsString(fileName).timeout(_ioTimeout);
            completer.complete(fileName);
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        })
        .catchError((error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        });
    return completer.future;
  }

  static Future<void> appendEntry(LogEntry entry) async {
    final completer = Completer<void>();
    _writeQueue = _writeQueue
        .then((_) async {
          try {
            final name = await currentName();
            if (name == null) {
              completer.complete();
              return;
            }
            final directory = await _directory();
            await File(path.join(directory.path, name))
                .writeAsString(
                  '${jsonEncode(entry.toJson())}\n',
                  mode: FileMode.append,
                  flush: true,
                )
                .timeout(_ioTimeout);
            completer.complete();
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        })
        .catchError((error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        });
    return completer.future;
  }

  static Future<void> appendIncoming({
    required String senderMac,
    required String senderUser,
    required String receiverUser,
    required String seqNumber,
    required String rssi,
    required String snr,
    required String packetTimestamp,
    required int battery,
  }) async {
    final name = await currentName();
    if (name == null) return;

    final sender = logNeighborLocations[senderMac];
    final receiver = currentLogLocation;
    final distance = sender != null && receiver != null
        ? _distanceMeters(sender, receiver).toStringAsFixed(2)
        : '';
    final entry = LogEntry(
      timestamp: _formatTimestamp(packetTimestamp),
      senderUser: senderUser,
      receiverUser: receiverUser,
      seqNumber: seqNumber,
      rssi: rssi,
      snr: snr,
      rtt: '',
      environment: name.replaceFirst(RegExp(r'-\d+\.jsonl$'), ''),
      distance: distance,
      senderLat: sender?.latitude.toString() ?? '',
      senderLon: sender?.longitude.toString() ?? '',
      receiverLat: receiver?.latitude.toString() ?? '',
      receiverLon: receiver?.longitude.toString() ?? '',
      battery: battery.toString(),
    );
    await appendEntry(entry);
  }

  static Future<List<LogEntry>> readCurrent() async {
    final name = await currentName();
    if (name == null) return [];
    final directory = await _directory();
    final file = File(path.join(directory.path, name));
    if (!await file.exists().timeout(_ioTimeout)) return [];
    final lines = await file.readAsLines().timeout(_ioTimeout);
    return lines.where((line) => line.trim().isNotEmpty).map((line) {
      return LogEntry.fromJson(jsonDecode(line) as Map<String, dynamic>);
    }).toList();
  }

  static String _formatTimestamp(String raw) {
    final seconds = int.tryParse(raw);
    final date = seconds == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return date.toLocal().toIso8601String();
  }

  static double _distanceMeters(LogCoordinate a, LogCoordinate b) {
    const earthRadius = 6371000.0;
    final lat1 = a.latitude * 3.141592653589793 / 180;
    final lat2 = b.latitude * 3.141592653589793 / 180;
    final dLat = lat2 - lat1;
    final dLon = (b.longitude - a.longitude) * 3.141592653589793 / 180;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadius * math.asin(math.sqrt(h));
  }
}
