import 'package:sentry_flutter/sentry_flutter.dart';

import 'config.dart';

/// Send diagnostic types and stack locations, never form values or API bodies.
SentryEvent privacyFilteredEvent(SentryEvent event) {
  final safe = <String, dynamic>{
    'event_id': event.eventId.toString(),
    if (event.timestamp != null)
      'timestamp': event.timestamp!.toIso8601String(),
    'platform': 'dart',
    'release': 'dressly@1.0.0+1',
    'environment': AppConfig.environment,
    'exception': {
      'values': [
        for (final exception in event.exceptions ?? <SentryException>[])
          {
            'type': exception.type ?? 'Error',
            'value': exception.type ?? 'Error',
            if (exception.stackTrace != null)
              'stacktrace': {
                'frames': [
                  for (final frame in exception.stackTrace!.frames)
                    {
                      for (final entry in frame.toJson().entries)
                        if ([
                          'filename',
                          'function',
                          'lineno',
                          'colno',
                          'in_app',
                        ].contains(entry.key))
                          entry.key: entry.value,
                    },
                ],
              },
          },
      ],
    },
  };
  return SentryEvent.fromJson(safe);
}

Future<void> runWithErrorTracking(void Function() runner) async {
  const dsn = String.fromEnvironment('SENTRY_DSN');
  if (dsn.isEmpty) {
    runner();
    return;
  }
  await SentryFlutter.init((options) {
    options.dsn = dsn;
    options.environment = AppConfig.environment;
    options.release = 'dressly@1.0.0+1';
    options.sendDefaultPii = false;
    options.attachScreenshot = false;
    // ignore: experimental_member_use
    options.attachViewHierarchy =
        false; // Explicit privacy setting in pinned SDK.
    options.tracesSampleRate = 0;
    options.maxBreadcrumbs = 20;
    options.beforeSend = (event, _) => privacyFilteredEvent(event);
    options.beforeBreadcrumb = (breadcrumb, _) => breadcrumb == null
        ? null
        : Breadcrumb(
            category: breadcrumb.category,
            type: breadcrumb.type,
            level: breadcrumb.level,
            timestamp: breadcrumb.timestamp,
          );
  }, appRunner: runner);
}
