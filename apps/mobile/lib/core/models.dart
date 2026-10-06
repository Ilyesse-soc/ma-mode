/// Domain models mirroring the API contract (no codegen — explicit and stable).
library;

class User {
  const User({
    required this.id,
    required this.firstName,
    required this.email,
    required this.mannequinPresentation,
    required this.emailVerified,
    this.onboardingSteps = const ['profile', 'preferences', 'consents'],
  });

  final String id;
  final String firstName;
  final String email;
  final String mannequinPresentation; // male | female
  final bool emailVerified;
  final List<String> onboardingSteps;
  String? get pendingOnboardingStep => !onboardingSteps.contains('preferences')
      ? 'preferences'
      : !onboardingSteps.contains('consents')
      ? 'consents'
      : null;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    firstName: json['first_name'] as String,
    email: json['email'] as String,
    mannequinPresentation: json['mannequin_presentation'] as String,
    emailVerified: json['email_verified'] as bool? ?? false,
    onboardingSteps:
        (json['onboarding_steps'] as List?)?.cast<String>() ??
        const ['profile', 'preferences', 'consents'],
  );
}

class GarmentCategory {
  const GarmentCategory({
    required this.id,
    required this.slug,
    required this.label,
    required this.group,
  });

  final int id;
  final String slug;
  final String label;
  final String group;

  factory GarmentCategory.fromJson(Map<String, dynamic> json) =>
      GarmentCategory(
        id: json['id'] as int,
        slug: json['slug'] as String,
        label: json['label'] as String,
        group: json['group'] as String,
      );
}

class GarmentImage {
  const GarmentImage({
    required this.id,
    required this.contentType,
    required this.isPrimary,
    this.downloadUrl,
    this.kind = 'garment',
  });

  final String id;
  final String contentType;
  final bool isPrimary;
  final String? downloadUrl;
  final String kind;

  factory GarmentImage.fromJson(Map<String, dynamic> json) => GarmentImage(
    id: json['id'] as String,
    contentType: json['content_type'] as String,
    isPrimary: json['is_primary'] as bool? ?? false,
    downloadUrl: json['download_url'] as String?,
    kind: json['image_kind'] as String? ?? 'garment',
  );
}

class Garment {
  const Garment({
    required this.id,
    required this.name,
    required this.color,
    required this.category,
    this.brand,
    this.size,
    this.material,
    this.warmthLevel = 3,
    this.waterproof = false,
    this.windproof = false,
    this.styles = const [],
    this.reference,
    this.season = 'all',
    this.notes,
    this.visualLevel = 'generic',
    this.images = const [],
    this.productImageUrl,
    this.importMetadata,
  });

  final String id;
  final String name;
  final String color;
  String get colorLabel =>
      const {
        'black': 'Noir',
        'white': 'Blanc',
        'grey': 'Gris',
        'gray': 'Gris',
        'blue': 'Bleu',
        'light_blue': 'Bleu clair',
        'navy': 'Marine',
        'beige': 'Beige',
        'camel': 'Camel',
        'brown': 'Marron',
        'cream': 'Crème',
        'green': 'Vert',
        'olive': 'Kaki',
        'red': 'Rouge',
        'yellow': 'Jaune',
        'orange': 'Orange',
        'purple': 'Violet',
        'pink': 'Rose',
        'silver': 'Argenté',
        'gold': 'Doré',
        'unknown': 'À préciser',
      }[color.toLowerCase().replaceAll(' ', '_')] ??
      color;
  final GarmentCategory category;
  final String? brand;
  final String? size;
  final String? material;
  final int warmthLevel;
  final bool waterproof;
  final bool windproof;
  final List<String> styles;
  final String? reference;
  final String season;
  final String? notes;
  final String visualLevel; // generic | approximate | exact
  final List<GarmentImage> images;
  final String? productImageUrl;
  final Map<String, dynamic>? importMetadata;
  String? get brandLabel => brand == null
      ? null
      : importMetadata?['brand_status'] == 'unverified'
      ? '$brand (supposée)'
      : brand;
  List<String> get displayImageUrls {
    final photos =
        images
            .where((i) => i.kind == 'garment' && i.downloadUrl != null)
            .toList()
          ..sort(
            (a, b) => (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0),
          );
    return [...photos.map((i) => i.downloadUrl!), ?productImageUrl];
  }

  factory Garment.fromJson(Map<String, dynamic> json) => Garment(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    category: GarmentCategory.fromJson(
      json['category'] as Map<String, dynamic>,
    ),
    brand: json['brand'] as String?,
    size: json['size'] as String?,
    material: json['material'] as String?,
    warmthLevel: json['warmth_level'] as int? ?? 3,
    waterproof: json['waterproof'] as bool? ?? false,
    windproof: json['windproof'] as bool? ?? false,
    styles: (json['styles'] as List?)?.cast<String>() ?? const [],
    reference: json['reference'] as String?,
    season: json['season'] as String? ?? 'all',
    notes: json['notes'] as String?,
    visualLevel: json['visual_representation_level'] as String? ?? 'generic',
    productImageUrl: json['product_image_url'] as String?,
    importMetadata: (json['import_metadata'] as Map?)?.cast<String, dynamic>(),
    images: ((json['images'] as List?) ?? const [])
        .map((e) => GarmentImage.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'name': name,
    'color': color,
    'category': {
      'id': category.id,
      'slug': category.slug,
      'label': category.label,
      'group': category.group,
    },
    'brand': brand,
    'size': size,
    'material': material,
    'reference': reference,
    'season': season,
    'notes': notes,
    'warmth_level': warmthLevel,
    'waterproof': waterproof,
    'windproof': windproof,
    'styles': styles,
    'visual_representation_level': visualLevel,
    if (importMetadata != null)
      'import_metadata': {
        for (final key in const [
          'source_type',
          'save_mode',
          'exact_match',
          'fallback_mode',
          'brand_status',
        ])
          if (importMetadata!.containsKey(key)) key: importMetadata![key],
      },
    'images': images
        .map(
          (image) => {
            'id': image.id,
            'content_type': image.contentType,
            'is_primary': image.isPrimary,
            'image_kind': image.kind,
            // Signed bearer URLs must never persist in the offline cache.
          },
        )
        .toList(),
  };
}

class OutfitProposal {
  const OutfitProposal({
    required this.rank,
    required this.score,
    required this.garmentIds,
    required this.explanations,
    required this.breakdown,
  });

  final int rank;
  final double score;
  final List<String> garmentIds;
  final List<String> explanations;
  final Map<String, dynamic> breakdown;

  factory OutfitProposal.fromJson(Map<String, dynamic> json) => OutfitProposal(
    rank: json['rank'] as int,
    score: (json['score'] as num).toDouble(),
    garmentIds: (json['garment_ids'] as List).cast<String>(),
    explanations: (json['explanations'] as List).cast<String>(),
    breakdown: (json['breakdown'] as Map).cast<String, dynamic>(),
  );
}

class Recommendation {
  const Recommendation({
    required this.id,
    required this.proposals,
    required this.weatherSummary,
    this.originLabel,
    this.destinationLabel,
    required this.activity,
  });

  final String id;
  final List<OutfitProposal> proposals;
  final Map<String, dynamic> weatherSummary;
  final String? originLabel;
  final String? destinationLabel;
  final String activity;

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
    id: json['id'] as String,
    proposals: ((json['proposals'] as List?) ?? const [])
        .map((e) => OutfitProposal.fromJson(e as Map<String, dynamic>))
        .toList(),
    weatherSummary: (json['weather_summary'] as Map).cast<String, dynamic>(),
    originLabel: json['origin_label'] as String?,
    destinationLabel: json['destination_label'] as String?,
    activity: json['activity'] as String? ?? 'everyday',
  );
}

class WeatherPoint {
  const WeatherPoint({
    required this.timestamp,
    required this.temperatureC,
    required this.feelsLikeC,
    required this.precipProbability,
    required this.windKmh,
    required this.condition,
  });

  final int timestamp;
  final double temperatureC;
  final double feelsLikeC;
  final double precipProbability;
  final double windKmh;
  final String condition;

  factory WeatherPoint.fromJson(Map<String, dynamic> json) => WeatherPoint(
    timestamp: json['timestamp'] as int,
    temperatureC: (json['temperature_c'] as num).toDouble(),
    feelsLikeC: (json['feels_like_c'] as num).toDouble(),
    precipProbability: (json['precip_probability'] as num).toDouble(),
    windKmh: (json['wind_kmh'] as num).toDouble(),
    condition: json['condition'] as String,
  );
}

class WeatherReport {
  const WeatherReport({required this.current, required this.hourly});

  final WeatherPoint current;
  final List<WeatherPoint> hourly;

  factory WeatherReport.fromJson(Map<String, dynamic> json) => WeatherReport(
    current: WeatherPoint.fromJson(json['current'] as Map<String, dynamic>),
    hourly: ((json['hourly'] as List?) ?? const [])
        .map((e) => WeatherPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
