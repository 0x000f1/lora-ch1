import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// https://pub.dev/packages/flutter_floating_bottom_bar
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'theme.dart';
import 'bt_sheet.dart';
import 'broadcast_page.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: appTheme, home: const HomePage());
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
    tabController = TabController(length: 2, vsync: this);
    tabController.animation!.addListener(
      () {
        final value = tabController.animation!.value.round();
        if (value != currentPage) {
            changePage(value);
        }
      }
    );
    super.initState();
  }

  void changePage(int newPage){
    setState(() {
      currentPage = newPage;
    });
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("BT Mesh Chat"),
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth_rounded),
            
            onPressed: () => showBTSheet(context),
          ),
        ],
        
      ),
      body: BottomBar(
        borderRadius: BorderRadius.circular(25),
        width: MediaQuery.of(context).size.width * 0.55,
        barColor: Colors.grey.shade200,

        body: (context, controller) => TabBarView(
          controller: tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const Center(child: Text("Private Chats")),
            BroadcastPage(scrollController: controller),
          ],

        ),
        child: TabBar(
          indicatorAnimation: TabIndicatorAnimation.elastic,
          indicatorPadding: EdgeInsetsGeometry.only(top: 7, bottom: 7),
          indicator: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(20),
          ),
          unselectedLabelColor: Colors.blue.shade800,
          labelColor: Colors.blue.shade800,
          controller: tabController,
          tabs: [
            SizedBox(
              height: 55,
              width: 55,
              child: Center(
                child: ImageIcon(
                  AssetImage('assets/icons/private.png'),
                  size: 35,
                ),
              ),
            ),
            SizedBox(

              height: 55,
              width: 55,
              child: Center(
                child: ImageIcon(
                  AssetImage('assets/icons/broadcast.png'),
                  size: 35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
