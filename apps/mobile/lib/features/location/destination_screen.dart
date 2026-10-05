import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/widgets/app_widgets.dart';

class Place {
  const Place(this.label, this.latitude, this.longitude, {this.id});
  final String label;
  final double latitude, longitude;
  final String? id;
  factory Place.fromJson(Map<String, dynamic> data) => Place(
    data['label'] as String,
    (data['latitude'] as num).toDouble(),
    (data['longitude'] as num).toDouble(),
    id: data['id'] as String?,
  );
}

const cityPlaces = [
  Place('Poissy, Yvelines', 48.9295, 2.0453),
  Place('Paris, France', 48.8566, 2.3522),
  Place('Lille, France', 50.6292, 3.0573),
  Place('Lyon, France', 45.7640, 4.8357),
  Place('Marseille, France', 43.2965, 5.3698),
  Place('Bordeaux, France', 44.8378, -0.5792),
  Place('Nantes, France', 47.2184, -1.5536),
  Place('Bruxelles, Belgique', 50.8503, 4.3517),
  Place('Londres, Royaume-Uni', 51.5074, -0.1278),
];

final placesProvider = FutureProvider<List<Place>>((ref) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  try {
    final response = await ref.watch(apiClientProvider).dio.get('/locations');
    return (response.data as List)
        .map((e) => Place.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
});

class DestinationScreen extends ConsumerStatefulWidget {
  const DestinationScreen({super.key, this.select = false});
  final bool select;
  @override
  ConsumerState<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends ConsumerState<DestinationScreen> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController(),
      _latitude = TextEditingController(),
      _longitude = TextEditingController();
  String _search = '';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _save(Place place) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/locations',
            data: {
              'label': place.label,
              'latitude': place.latitude,
              'longitude': place.longitude,
            },
          );
      ref.invalidate(placesProvider);
      if (!mounted) return;
      if (widget.select) {
        Navigator.of(context).pop(place);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Destination enregistrée')),
        );
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Place place) async {
    try {
      await ref.read(apiClientProvider).dio.delete('/locations/${place.id}');
      ref.invalidate(placesProvider);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.select ? 'Choisir un lieu' : 'Mes destinations'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Rechercher une ville',
          ),
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
        ),
        const SizedBox(height: 20),
        const Text('Destinations enregistrées'),
        ref
            .watch(placesProvider)
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => AppErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(placesProvider),
              ),
              data: (places) => Column(
                children: [
                  if (places.isEmpty)
                    const ListTile(
                      title: Text('Aucune destination enregistrée'),
                    ),
                  for (final place in places.where(
                    (p) => p.label.toLowerCase().contains(_search),
                  ))
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(place.label),
                      onTap: widget.select
                          ? () => Navigator.of(context).pop(place)
                          : null,
                      trailing: IconButton(
                        tooltip: 'Supprimer la destination',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(place),
                      ),
                    ),
                ],
              ),
            ),
        const SizedBox(height: 16),
        const Text('Villes'),
        for (final place in cityPlaces.where(
          (p) => p.label.toLowerCase().contains(_search),
        ))
          ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(place.label),
            trailing: Icon(widget.select ? Icons.chevron_right : Icons.add),
            onTap: _busy
                ? null
                : () => widget.select
                      ? Navigator.of(context).pop(place)
                      : _save(place),
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Autre lieu : saisir les coordonnées'),
          children: [
            Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'Ville ou lieu',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Lieu requis' : null,
                  ),
                  const SizedBox(height: 12),
                  for (final entry in [
                    (_latitude, 'Latitude', 90.0),
                    (_longitude, 'Longitude', 180.0),
                  ]) ...[
                    TextFormField(
                      controller: entry.$1,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(labelText: entry.$2),
                      validator: (v) {
                        final number = double.tryParse(
                          (v ?? '').replaceAll(',', '.'),
                        );
                        return number == null ||
                                !number.isFinite ||
                                number.abs() > entry.$3
                            ? 'Coordonnée invalide'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (!_form.currentState!.validate()) return;
                            final place = Place(
                              _label.text.trim(),
                              double.parse(_latitude.text.replaceAll(',', '.')),
                              double.parse(
                                _longitude.text.replaceAll(',', '.'),
                              ),
                            );
                            widget.select
                                ? Navigator.of(context).pop(place)
                                : _save(place);
                          },
                    child: Text(
                      widget.select ? 'Utiliser ce lieu' : 'Enregistrer',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
