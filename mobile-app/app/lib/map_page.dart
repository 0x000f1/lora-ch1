import 'dart:async';

import 'package:app/ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

const _mapStoreName = 'hajduszoboszlo_map';
const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _mapUserAgent = 'com.te.ceged.lora_tracker';
const _defaultCenter = LatLng(47.4480, 21.4000);

bool offlineMapAvailable = false;

Future<void> initializeOfflineMap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FMTCObjectBoxBackend().initialise();
    await const FMTCStore(_mapStoreName).manage.create();
    offlineMapAvailable = true;
  } catch (error, stackTrace) {
    debugPrint('Offline map initialization failed: $error\n$stackTrace');
  }
}

class MapNeighbor {
  const MapNeighbor({
    required this.name,
    required this.colorHex,
    required this.location,
  });

  final String name;
  final String colorHex;
  final LatLng location;

  Color get color {
    final value = int.tryParse(colorHex.replaceFirst('#', ''), radix: 16);
    return Color(0xFF000000 | (value ?? 0x607D8B));
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _mapController = MapController();
  final _neighbors = <MapNeighbor>[];
  StreamSubscription<String>? _controlSubscription;
  LatLng? _myLocation;
  bool _isLocating = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _errorMessage;
  late final FMTCTileProvider? _tileProvider;

  @override
  void initState() {
    super.initState();
    _tileProvider = offlineMapAvailable
        ? FMTCTileProvider(
            stores: const {_mapStoreName: BrowseStoreStrategy.readUpdateCreate},
            loadingStrategy: BrowseLoadingStrategy.cacheFirst,
          )
        : null;
    _controlSubscription = controlStream.listen(_handleNeighborsMessage);
    isDeviceConnected.addListener(_handleConnectionChanged);
    _loadLocation();
    if (isDeviceConnected.value) {
      sendOnControlChar('GET_NEI');
    }
  }

  @override
  void dispose() {
    _controlSubscription?.cancel();
    isDeviceConnected.removeListener(_handleConnectionChanged);
    super.dispose();
  }

  void _handleConnectionChanged() {
    if (isDeviceConnected.value) sendOnControlChar('GET_NEI');
  }

  void _handleNeighborsMessage(String rawMessage) {
    if (!mounted || !rawMessage.startsWith('NEI|')) return;

    final parsed = <MapNeighbor>[];
    for (final entry in rawMessage.substring(4).split('|')) {
      final fields = entry.split(';');
      if (fields.length < 7) continue;

      final latitude = double.tryParse(fields[5]);
      final longitude = double.tryParse(fields[6]);
      if (latitude == null || longitude == null) continue;
      if (latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }

      parsed.add(
        MapNeighbor(
          name: fields[1],
          colorHex: fields[2],
          location: LatLng(latitude, longitude),
        ),
      );
    }
    setState(() {
      _neighbors
        ..clear()
        ..addAll(parsed);
    });
  }

  Future<void> _loadLocation() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('A helymeghatározás ki van kapcsolva.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('A helymeghatározási engedély nem érhető el.');
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final location = LatLng(position.latitude, position.longitude);
      setState(() => _myLocation = location);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(location, 14);
      });
    } catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _downloadMap() async {
    if (!offlineMapAvailable || _isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _errorMessage = null;
    });

    try {
      final region = RectangleRegion(
        LatLngBounds(LatLng(47.4100, 21.3600), LatLng(47.4700, 21.4500)),
      );
      final downloadableRegion = region.toDownloadable(
        minZoom: 12,
        maxZoom: 16,
        options: TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: _mapUserAgent,
        ),
      );
      final result = const FMTCStore(_mapStoreName).download.startForeground(
        region: downloadableRegion,
        skipExistingTiles: true,
      );

      await for (final progress in result.downloadProgress) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress.percentageProgress / 100);
      }
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A térkép offline használatra elmentve.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'A térkép letöltése sikertelen: $error';
        });
      }
    }
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    if (_myLocation != null) {
      markers.add(
        Marker(
          point: _myLocation!,
          width: 50,
          height: 50,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 35),
        ),
      );
    }
    for (final neighbor in _neighbors) {
      markers.add(
        Marker(
          point: neighbor.location,
          width: 130,
          height: 70,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: neighbor.color, width: 2),
                ),
                child: Text(
                  neighbor.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.location_on, color: neighbor.color, size: 35),
            ],
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 14,
            minZoom: 12,
            maxZoom: 16,
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: _mapUserAgent,
              tileProvider: _tileProvider,
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'my-location',
                onPressed: _isLocating ? null : _loadLocation,
                child: _isLocating
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.my_location),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'download-map',
                onPressed: offlineMapAvailable ? _downloadMap : null,
                child: const Icon(Icons.download),
              ),
            ],
          ),
        ),
        if (_isDownloading)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Térkép letöltése offline használathoz...'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress),
                  ],
                ),
              ),
            ),
          ),
        if (_errorMessage != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              color: Colors.red.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_errorMessage!),
              ),
            ),
          ),
      ],
    );
  }
}
