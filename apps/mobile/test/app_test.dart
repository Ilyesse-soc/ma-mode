import 'package:alamode/core/models.dart';
import 'package:alamode/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppEmptyState renders title, message and action', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppEmptyState(
            icon: Icons.checkroom_outlined,
            title: 'Vide',
            message: 'Aucune pièce',
            actionLabel: 'Ajouter',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('Vide'), findsOneWidget);
    expect(find.text('Aucune pièce'), findsOneWidget);
    await tester.tap(find.text('Ajouter'));
    expect(tapped, isTrue);
  });

  test('Garment.fromJson parses the API contract', () {
    final garment = Garment.fromJson({
      'id': 'g1',
      'name': 'T-shirt blanc',
      'color': 'white',
      'category': {
        'id': 8,
        'slug': 'tshirt',
        'label': 'T-shirt',
        'group': 'top',
      },
      'warmth_level': 2,
      'waterproof': false,
      'windproof': false,
      'styles': ['casual'],
      'visual_representation_level': 'generic',
      'images': const [],
    });
    expect(garment.category.slug, 'tshirt');
    expect(garment.category.group, 'top');
    expect(garment.visualLevel, 'generic');
  });

  test('OutfitProposal.fromJson parses engine output', () {
    final proposal = OutfitProposal.fromJson({
      'rank': 1,
      'score': 0.82,
      'garment_ids': ['g1', 'g2'],
      'explanations': ['Risque de pluie de 70 %'],
      'breakdown': {'rain_score': 1.0},
    });
    expect(proposal.garmentIds, hasLength(2));
    expect(proposal.score, closeTo(0.82, 0.001));
  });
}
