import 'package:flutter/material.dart';

const activityOptions = [
  ('everyday', 'Tous les jours', Icons.wb_sunny_outlined),
  ('work', 'Travail', Icons.work_outline),
  ('sport', 'Sport', Icons.sports_outlined),
  ('evening', 'Soirée', Icons.nightlife_outlined),
  ('travel', 'Voyage', Icons.flight_outlined),
  ('school', 'École', Icons.school_outlined),
  ('restaurant', 'Restaurant', Icons.restaurant_outlined),
  ('date', 'Rendez-vous', Icons.favorite_outline),
  ('formal_event', 'Événement chic', Icons.celebration_outlined),
  ('other', 'Autre', Icons.more_horiz),
];

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key, required this.selected});
  final String selected;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activité')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text('Choisis l’activité pour laquelle tu veux une tenue.'),
        ),
        for (final activity in activityOptions)
          Card(
            child: ListTile(
              leading: Icon(activity.$3),
              title: Text(activity.$2),
              selected: selected == activity.$1,
              trailing: selected == activity.$1
                  ? const Icon(Icons.check)
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(activity.$1),
            ),
          ),
      ],
    ),
  );
}
