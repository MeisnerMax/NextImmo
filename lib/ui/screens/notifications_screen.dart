import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/notification.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: FutureBuilder<List<NotificationRecord>>(
        future: ref
            .read(notificationsRepositoryProvider)
            .listNotifications(unreadOnly: _unreadOnly),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FilterChip(
                    label: const Text('Unread only'),
                    selected: _unreadOnly,
                    onSelected: (selected) {
                      setState(() {
                        _unreadOnly = selected;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await ref
                          .read(notificationsRepositoryProvider)
                          .markAllRead();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    child: const Text('Mark all read'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child:
                    notifications.isEmpty
                        ? const Center(child: Text('No notifications.'))
                        : ListView.builder(
                          itemCount: notifications.length,
                          itemBuilder: (context, index) {
                            final item = notifications[index];
                            return Card(
                              child: ListTile(
                                title: Text(
                                  item.message,
                                  style: TextStyle(
                                    fontWeight:
                                        item.isRead
                                            ? FontWeight.w500
                                            : FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item.kind} | ${item.entityType}:${item.entityId}'
                                  ' | ${DateTime.fromMillisecondsSinceEpoch(item.createdAt).toIso8601String()}',
                                ),
                                trailing:
                                    item.isRead
                                        ? const Text('Read')
                                        : TextButton(
                                          onPressed: () async {
                                            await ref
                                                .read(
                                                  notificationsRepositoryProvider,
                                                )
                                                .markRead(item.id);
                                            if (mounted) {
                                              setState(() {});
                                            }
                                          },
                                          child: const Text('Mark read'),
                                        ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          );
        },
      ),
    );
  }
}
