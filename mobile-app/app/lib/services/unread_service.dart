// global state manager for unread messages to notify UI

import 'package:app/services/db_service.dart';
import 'package:flutter/foundation.dart';

// total number of unread private messages from all peers
final ValueNotifier<int> unreadPrivateCount = ValueNotifier(0);
// total number of unread broadcast messages
final ValueNotifier<int> unreadBroadcastCount = ValueNotifier(0);
// trigger to notify listeners
final ValueNotifier<int> unreadUpdateTrigger = ValueNotifier(0);


Future<void> refreshUnreadCount() async {
  // query database for unread counts
  unreadPrivateCount.value = await getTotalUnreadPrivateCount();
  unreadBroadcastCount.value = await getUnreadBroadcastCount();
  // increment to trigger listeners
  unreadUpdateTrigger.value++;
}
