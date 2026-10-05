import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models.dart';
import 'network/api_client.dart';
import 'network/token_storage.dart';
import '../features/location/location_controller.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(tokenStorageProvider),
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).expireSession(),
  ),
);

/// Auth state: unknown (boot) → authenticated / guest.
enum AuthStatus { unknown, authenticated, guest }

class AuthState {
  const AuthState({required this.status, this.user});

  final AuthStatus status;
  final User? user;
}

class AuthController extends Notifier<AuthState> {
  Future<void> expireSession() async {
    ref.read(apiClientProvider).invalidateSession();
    for (final name in ['wardrobe_cache', 'recommendations_cache']) {
      if (Hive.isBoxOpen(name)) await Hive.box<String>(name).clear();
    }
    ref.invalidate(wardrobeProvider);
    ref.invalidate(locationControllerProvider);
    state = const AuthState(status: AuthStatus.guest);
  }

  @override
  AuthState build() {
    _bootstrap();
    return const AuthState(status: AuthStatus.unknown);
  }

  Future<void> _bootstrap() async {
    final tokens = ref.read(tokenStorageProvider);
    final access = await tokens.readAccess();
    if (access == null) {
      state = const AuthState(status: AuthStatus.guest);
      return;
    }
    try {
      final user = await _fetchMe();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException {
      state = const AuthState(status: AuthStatus.guest);
    }
  }

  Future<User> _fetchMe() async {
    final dio = ref.read(apiClientProvider).dio;
    try {
      final resp = await dio.get('/me');
      return User.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> login(String email, String password) async {
    await expireSession();
    final dio = ref.read(apiClientProvider).dio;
    try {
      final resp = await dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      await ref
          .read(tokenStorageProvider)
          .save(
            access: resp.data['access_token'] as String,
            refresh: resp.data['refresh_token'] as String,
          );
      final user = await _fetchMe();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> register({
    required String firstName,
    required String email,
    required String password,
    required String mannequinPresentation,
  }) async {
    final dio = ref.read(apiClientProvider).dio;
    try {
      final resp = await dio.post(
        '/auth/register',
        data: {
          'first_name': firstName,
          'email': email,
          'password': password,
          'mannequin_presentation': mannequinPresentation,
        },
      );
      if (resp.statusCode == 202) {
        state = const AuthState(status: AuthStatus.guest);
        return;
      }
      await ref
          .read(tokenStorageProvider)
          .save(
            access: resp.data['access_token'] as String,
            refresh: resp.data['refresh_token'] as String,
          );
      final user = await _fetchMe();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> refreshProfile() async {
    final user = await _fetchMe();
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> completeOnboardingStep(String step) async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .put('/me/onboarding', data: {'step': step});
      state = AuthState(
        status: AuthStatus.authenticated,
        user: User.fromJson((response.data as Map).cast<String, dynamic>()),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> logout() async {
    ref.read(apiClientProvider).invalidateSession();
    final tokens = ref.read(tokenStorageProvider);
    final refresh = await tokens.readRefresh();
    if (refresh != null) {
      try {
        await ref
            .read(apiClientProvider)
            .dio
            .post('/auth/logout', data: {'refresh_token': refresh});
      } on DioException {
        // Best effort — local cleanup happens regardless.
      }
    }
    await tokens.clear();
    await Hive.box<String>('wardrobe_cache').clear();
    await Hive.box<String>('recommendations_cache').clear();
    ref.invalidate(locationControllerProvider);
    state = const AuthState(status: AuthStatus.guest);
  }

  Future<void> deleteAccount(String password) async {
    final dio = ref.read(apiClientProvider).dio;
    try {
      await dio.delete('/me', data: {'password': password});
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
    await ref.read(tokenStorageProvider).clear();
    ref.read(apiClientProvider).invalidateSession();
    await Hive.box<String>('wardrobe_cache').clear();
    await Hive.box<String>('recommendations_cache').clear();
    ref.invalidate(locationControllerProvider);
    state = const AuthState(status: AuthStatus.guest);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Wardrobe repository with offline cache (Hive).
class WardrobeRepository {
  WardrobeRepository(this._client);

  final ApiClient _client;
  static const _cacheKey = 'garments';

  Future<List<Garment>> listGarments({bool forceRefresh = false}) async {
    final box = Hive.box<String>('wardrobe_cache');
    if (!forceRefresh) {
      final cached = box.get(_cacheKey);
      if (cached != null) {
        _refreshInBackground();
        return _decode(cached);
      }
    }
    return _fetchAndCache();
  }

  Future<void> _refreshInBackground() async {
    try {
      await _fetchAndCache();
    } catch (_) {
      /* offline — cache stays */
    }
  }

  Future<List<Garment>> _fetchAndCache() async {
    final generation = _client.sessionGeneration;
    try {
      final items = <Garment>[];
      var page = 1;
      while (true) {
        final resp = await _client.dio.get(
          '/garments',
          queryParameters: {'page_size': 100, 'page': page},
        );
        final batch = (resp.data['items'] as List)
            .map((e) => Garment.fromJson(e as Map<String, dynamic>))
            .toList();
        items.addAll(batch);
        if (batch.isEmpty || items.length >= (resp.data['total'] as int)) break;
        page++;
      }
      if (generation == _client.sessionGeneration) {
        await Hive.box<String>('wardrobe_cache').put(
          _cacheKey,
          jsonEncode(items.map((g) => g.toCacheJson()).toList()),
        );
      }
      return items;
    } on DioException catch (e) {
      final cached = Hive.box<String>('wardrobe_cache').get(_cacheKey);
      if (cached != null &&
          e.response == null &&
          generation == _client.sessionGeneration) {
        return _decode(cached);
      }
      throw ApiException.fromDio(e);
    }
  }

  List<Garment> _decode(String raw) => (jsonDecode(raw) as List)
      .map((e) => Garment.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<Garment> createGarment(Map<String, dynamic> payload) async {
    try {
      final resp = await _client.dio.post('/garments', data: payload);
      await Hive.box<String>('wardrobe_cache').delete(_cacheKey);
      return Garment.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> deleteGarment(String id) async {
    try {
      await _client.dio.delete('/garments/$id');
      await Hive.box<String>('wardrobe_cache').delete(_cacheKey);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Garment> getGarment(String id) async {
    try {
      final response = await _client.dio.get('/garments/$id');
      return Garment.fromJson(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Garment> updateGarment(String id, Map<String, dynamic> payload) async {
    try {
      final response = await _client.dio.patch('/garments/$id', data: payload);
      final garment = Garment.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      await Hive.box<String>('wardrobe_cache').delete(_cacheKey);
      return garment;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<GarmentCategory>> categories() async {
    try {
      final resp = await _client.dio.get('/garment-categories');
      return (resp.data as List)
          .map((e) => GarmentCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, List<String>>> silhouetteMap() async {
    try {
      final resp = await _client.dio.get('/garment-categories/silhouette-map');
      return (resp.data as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as List).cast<String>()),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final wardrobeRepositoryProvider = Provider<WardrobeRepository>(
  (ref) => WardrobeRepository(ref.watch(apiClientProvider)),
);

final wardrobeProvider = FutureProvider<List<Garment>>((ref) {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  return ref.watch(wardrobeRepositoryProvider).listGarments(forceRefresh: true);
});
