import 'package:flutter/material.dart';
import '../models.dart';
import 'app_widgets.dart';

class GarmentVisual extends StatelessWidget {
  const GarmentVisual({super.key, required this.garment});
  final Garment garment;
  @override
  Widget build(BuildContext context) {
    final urls = garment.displayImageUrls;
    Widget fallback() => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Semantics(
        label: 'Illustration de catégorie : ${garment.category.label}',
        child: CustomPaint(
          size: const Size(100, 120),
          painter: GarmentIllustration(
            garment.category.group,
            garment.category.slug,
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
    Widget image(int index) => index >= urls.length
        ? fallback()
        : Image.network(
            urls[index],
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 600,
            semanticLabel: garment.name,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            loadingBuilder: (_, child, loading) =>
                loading == null ? child : const AppSkeleton(),
            errorBuilder: (_, _, _) => image(index + 1),
          );
    return image(0);
  }
}

class GarmentCard extends StatelessWidget {
  const GarmentCard({
    super.key,
    required this.garment,
    required this.onTap,
    this.selected = false,
    this.compact = false,
  });
  final Garment garment;
  final VoidCallback? onTap;
  final bool selected, compact;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Choisir ${garment.name}',
      child: Material(
        color: theme.cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 4 : 12),
                  child: GarmentVisual(garment: garment),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 6 : 12,
                  4,
                  compact ? 6 : 12,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (garment.brand?.isNotEmpty == true)
                      Text(
                        garment.brand!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      garment.name,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: compact
                          ? theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            )
                          : theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      compact
                          ? garment.colorLabel
                          : '${garment.category.label} · ${garment.colorLabel}${selected ? ' · Choisi' : ''}',
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GarmentIllustration extends CustomPainter {
  const GarmentIllustration(this.group, this.slug, this.color);
  final String group, slug;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 120);
    final paint = Paint()
      ..color = color.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (group == 'bottom') {
      path.moveTo(27, 20);
      path.lineTo(73, 20);
      path.lineTo(79, 105);
      path.lineTo(55, 105);
      path.lineTo(50, 53);
      path.lineTo(45, 105);
      path.lineTo(21, 105);
      path.close();
      canvas.drawLine(const Offset(27, 30), const Offset(73, 30), paint);
    } else if (group == 'shoes') {
      path.moveTo(13, 68);
      path.lineTo(19, 40);
      path.lineTo(36, 48);
      path.lineTo(48, 62);
      path.lineTo(78, 74);
      path.quadraticBezierTo(91, 77, 89, 91);
      path.lineTo(14, 91);
      path.close();
      canvas.drawLine(const Offset(16, 83), const Offset(87, 83), paint);
      for (var x = 40.0; x < sixty; x += 7) {
        canvas.drawLine(Offset(x, 61), Offset(x - 8, 72), paint);
      }
    } else if (group == 'top') {
      path.moveTo(34, 20);
      path.lineTo(18, 28);
      path.lineTo(6, 47);
      path.lineTo(24, 57);
      path.lineTo(29, 48);
      path.lineTo(29, 101);
      path.lineTo(71, 101);
      path.lineTo(71, 48);
      path.lineTo(76, 57);
      path.lineTo(94, 47);
      path.lineTo(82, 28);
      path.lineTo(66, 20);
      path.quadraticBezierTo(50, 42, 34, 20);
      path.close();
      if (slug != 'tshirt') {
        canvas.drawLine(const Offset(50, 35), const Offset(50, 99), paint);
      }
    } else {
      canvas.drawOval(const Rect.fromLTWH(25, 35, 50, 50), paint);
      canvas.drawLine(const Offset(35, 60), const Offset(65, 60), paint);
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  static const sixty = 61.0;
  @override
  bool shouldRepaint(GarmentIllustration old) =>
      old.group != group || old.slug != slug || old.color != color;
}
