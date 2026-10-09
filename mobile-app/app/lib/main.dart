import 'package:app/ble_service.dart';
import 'package:app/db_service.dart';
import 'package:app/private_page.dart';
import 'package:app/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// https://pub.dev/packages/flutter_floating_bottom_bar
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'theme.dart';
import 'bt_sheet.dart';
import 'broadcast_page.dart';
import 'map_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeOfflineMap();
  //debugPaintSizeEnabled = true; // see layout bounds in debug mode
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // late: will be initialized before first use (in initState())
  late TabController tabController;
  int currentPage = 0;

  @override
  void initState() {
    super.initState();

    initConnectionListener();
    tabController = TabController(length: 3, vsync: this);
    tabController.animation!.addListener(() {
      if (tabController.index != currentPage) {
        changePage(tabController.index);
      }
    });

    refreshUnreadCount();
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
    super.dispose();
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
                        return Row(
                          children: [
                            Text("$bat%"),
                            const SizedBox(width: 4),
                            Icon(
                              bat > 20
                                  ? Icons.battery_full_rounded
                                  : Icons.battery_alert_rounded,
                            ),
                          ],
                        );
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
                      isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_rounded,
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
            BroadcastPage(
              scrollController: controller,
              isActive: currentPage == 1,
            ),
            const MapPage(),
          ],
        ),
        child: TabBar(
          labelColor: colors.surfaceContainer,
          dividerHeight: 0,
          controller: tabController,
          indicatorAnimation: TabIndicatorAnimation.elastic,
          indicatorPadding: EdgeInsetsGeometry.symmetric(
            horizontal: -4,
            vertical: 7,
          ),
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
                      child: ImageIcon(
                        AssetImage('assets/icons/private.png'),
                        size: 35,
                      ),
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
                      child: ImageIcon(
                        AssetImage('assets/icons/broadcast.png'),
                        size: 35,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(
              height: 55,
              width: 55,
              child: Center(child: Icon(Icons.map_outlined, size: 35)),
            ),
          ],
        ),
      ),
    );
  }
}
