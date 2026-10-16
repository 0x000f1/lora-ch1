import 'dart:async';

import 'package:app/core/logger.dart';
import 'package:app/services/notification_service.dart';
import 'package:app/ui/private_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';

import 'services/ble_service.dart';
import 'services/db_service.dart';
import 'ui/private_page.dart';
import 'ui/settings_page.dart';
import 'core/theme.dart';
import 'ui/bt_sheet.dart';
import 'ui/broadcast_page.dart';
import 'services/unread_service.dart';

// lets code outside of widget navigate (on notification tap)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey();
Future<void> main() async {
  //debugPaintSizeEnabled = true; // see layout bounds in debug mode

  // needed because plugins are used before runApp
  WidgetsFlutterBinding.ensureInitialized();

  await initNotifications();
  await requestNotificationPermission();
  setupNotificationListener();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      theme: appTheme,
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  // late: will be initialized before first use (in initState())
  late TabController tabController;
  int currentPage = 0;

  StreamSubscription<String>? _notificationSubscription;

  @override
  void initState() {
    super.initState();

    initConnectionListener();
    tabController = TabController(length: 2, vsync: this);
    tabController.animation!.addListener(() {
      if (tabController.index != currentPage) {
        changePage(tabController.index);
      }
    });

    // listen to notification taps and open
    _notificationSubscription = notificationTapStream.stream.listen((String peerMac) async {
      _openChat(peerMac);
    });

    // check if app was launched from notification
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final peerMac = await getLaunchNotificationPeerMac();
      // open chat for the peer if a payload was found
      if (peerMac != null) _openChat(peerMac);
    });

    refreshUnreadCount();
  }

  Future<void> _openChat(String peerMac) async {
    AppLogger.log("NOTIF", "Attempting to open chat for mac: $peerMac");
    if (activeChatMac == peerMac) {
      AppLogger.log("NOTIF", "Canceled. Chat is already open");
      return;
    }
    final peers = await getSavedPeers();
    final matches = peers.where((peer) => peer.mac == peerMac);
    if (matches.isEmpty) {
      AppLogger.log("NOTIF", "Canceled. Peer $peerMac not found");
      return;
    }
    
    // change background UI to private tab
    if(tabController.index != 0) {
      tabController.animateTo(0);
    }
    
    AppLogger.log("NOTIF", "Navigation started to Private Chat for peer $peerMac");
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => PrivateChatPage(device: PeerDevice.fromDb(matches.first)),
      ),
    );
  }

  void changePage(int newPage) async {
    setState(() {
      currentPage = newPage;
    });
    if (newPage == 1) {
      await markBroadcastMessagesAsRead();
      await refreshUnreadCount();
    }
  }

  @override
  void dispose() {
    tabController.dispose();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Widget buildBatteryIndicator(int level) {
    final (icon, color) = switch (level) {
      <= 10 => (Icons.battery_alert_rounded, Colors.redAccent),
      <= 14 => (Icons.battery_1_bar_sharp, Colors.white),
      <= 28 => (Icons.battery_2_bar_rounded, Colors.white),
      <= 42 => (Icons.battery_3_bar_rounded, Colors.white),
      <= 57 => (Icons.battery_4_bar_rounded, Colors.white),
      <= 71 => (Icons.battery_5_bar_rounded, Colors.white),
      <= 85 => (Icons.battery_6_bar_rounded, Colors.white),
      <= 100 => (Icons.battery_full_rounded, Colors.white),
      _ => (Icons.battery_charging_full_rounded, Colors.white),
    };

    return Row(
      children: [
        if (level <= 100) Text("$level%", style: TextStyle(fontSize: 13)),
        const SizedBox(width: 2),
        Icon(icon, color: color, size: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("BT Mesh Chat"),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: isDeviceConnected,
            builder: (context, isConnected, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isConnected)
                    ValueListenableBuilder<int>(
                      valueListenable: batteryLevel,
                      builder: (context, bat, child) {
                        return buildBatteryIndicator(bat);
                      },
                    ),

                  if (isConnected)
                    IconButton(
                      icon: Icon(Icons.settings),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) {
                              final devices = FlutterBluePlus.connectedDevices;
                              final deviceName = devices.isNotEmpty
                                  ? devices.first.platformName
                                  : "Unknown";

                              return SettingsPage(deviceName: deviceName);
                            },
                          ),
                        );
                      },
                    ),

                  IconButton(
                    icon: Icon(
                      isConnected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_rounded,
                    ),
                    onPressed: () => showBTSheet(context),
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
        ],
      ),
      body: BottomBar(
        hideOnScroll: false,
        borderRadius: BorderRadius.circular(25),
        width: MediaQuery.of(context).size.width * 0.55,
        barColor: colors.surfaceContainer,

        body: (context, controller) => TabBarView(
          controller: tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            //const Center(child: Text("Private Chats")),
            PrivatePage(scrollController: controller),
            BroadcastPage(scrollController: controller, isActive: currentPage == 1),
          ],
        ),
        child: TabBar(
          labelColor: colors.surfaceContainer,
          dividerHeight: 0,
          controller: tabController,
          indicatorAnimation: TabIndicatorAnimation.elastic,
          indicatorPadding: EdgeInsetsGeometry.symmetric(horizontal: -4, vertical: 7),
          indicator: BoxDecoration(
            color: colors.onPrimaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          tabs: [
            SizedBox(
              height: 55,
              width: 55,
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: unreadPrivateCount,
                  builder: (context, count, child) {
                    return Badge(
                      isLabelVisible: count > 0,
                      backgroundColor: Colors.red.shade300,
                      label: Text("$count"),
                      child: ImageIcon(AssetImage('assets/icons/private.png'), size: 35),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              height: 55,
              width: 55,
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: unreadBroadcastCount,
                  builder: (context, count, child) {
                    return Badge(
                      isLabelVisible: count > 0,
                      backgroundColor: Colors.red.shade300,
                      label: Text("$count"),
                      child: ImageIcon(AssetImage('assets/icons/broadcast.png'), size: 35),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
