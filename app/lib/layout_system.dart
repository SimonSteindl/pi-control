import 'package:flutter/material.dart';

enum PiLayoutStyle { aurora, commandCenter, compact, classic }

@immutable
class PiDesignTokens extends ThemeExtension<PiDesignTokens> {
  final PiLayoutStyle style;
  final double pagePadding;
  final double sectionGap;
  final double radius;
  final bool dense;

  const PiDesignTokens({
    required this.style,
    required this.pagePadding,
    required this.sectionGap,
    required this.radius,
    required this.dense,
  });

  @override
  PiDesignTokens copyWith({
    PiLayoutStyle? style,
    double? pagePadding,
    double? sectionGap,
    double? radius,
    bool? dense,
  }) => PiDesignTokens(
    style: style ?? this.style,
    pagePadding: pagePadding ?? this.pagePadding,
    sectionGap: sectionGap ?? this.sectionGap,
    radius: radius ?? this.radius,
    dense: dense ?? this.dense,
  );

  @override
  PiDesignTokens lerp(covariant PiDesignTokens? other, double t) {
    if (other == null) return this;
    return PiDesignTokens(
      style: t < .5 ? style : other.style,
      pagePadding: pagePadding + (other.pagePadding - pagePadding) * t,
      sectionGap: sectionGap + (other.sectionGap - sectionGap) * t,
      radius: radius + (other.radius - radius) * t,
      dense: t < .5 ? dense : other.dense,
    );
  }
}

extension PiDesignContext on BuildContext {
  PiDesignTokens get piDesign =>
      Theme.of(this).extension<PiDesignTokens>() ??
      const PiDesignTokens(
        style: PiLayoutStyle.aurora,
        pagePadding: 18,
        sectionGap: 14,
        radius: 24,
        dense: false,
      );
}

extension PiLayoutStyleDetails on PiLayoutStyle {
  String get storageKey => name;

  String get label => switch (this) {
    PiLayoutStyle.aurora => 'Aurora',
    PiLayoutStyle.commandCenter => 'Command Center',
    PiLayoutStyle.compact => 'Kompakt',
    PiLayoutStyle.classic => 'Klassisch',
  };

  String get description => switch (this) {
    PiLayoutStyle.aurora => 'Großzügig, farbig und modern',
    PiLayoutStyle.commandCenter =>
      'Desktop-Seitenleiste wie ein Server-Cockpit',
    PiLayoutStyle.compact => 'Mehr Informationen auf weniger Platz',
    PiLayoutStyle.classic => 'Ruhig, flach und besonders übersichtlich',
  };

  IconData get icon => switch (this) {
    PiLayoutStyle.aurora => Icons.auto_awesome_rounded,
    PiLayoutStyle.commandCenter => Icons.dns_rounded,
    PiLayoutStyle.compact => Icons.view_compact_alt_rounded,
    PiLayoutStyle.classic => Icons.dashboard_outlined,
  };

  bool get ownsNavigation =>
      this == PiLayoutStyle.commandCenter || this == PiLayoutStyle.compact;
}

PiLayoutStyle piLayoutStyleFromKey(String? value) {
  return PiLayoutStyle.values.firstWhere(
    (style) => style.storageKey == value,
    orElse: () => PiLayoutStyle.commandCenter,
  );
}

ThemeData buildPiLayoutTheme(
  ThemeData base,
  PiLayoutStyle style,
  Color accent,
) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  );
  final (
    background,
    surface,
    radius,
    elevation,
    pagePadding,
    gap,
  ) = switch (style) {
    PiLayoutStyle.aurora => (
      const Color(0xFF07111F),
      const Color(0xFF101D30),
      26.0,
      0.0,
      20.0,
      16.0,
    ),
    PiLayoutStyle.commandCenter => (
      const Color(0xFF070B12),
      const Color(0xFF101827),
      20.0,
      0.0,
      22.0,
      15.0,
    ),
    PiLayoutStyle.compact => (
      const Color(0xFF0B0E13),
      const Color(0xFF151920),
      10.0,
      0.0,
      12.0,
      8.0,
    ),
    PiLayoutStyle.classic => (
      const Color(0xFF101318),
      const Color(0xFF1B2028),
      16.0,
      1.0,
      16.0,
      12.0,
    ),
  };

  final dense = style == PiLayoutStyle.compact;
  final border = BorderSide(color: Colors.white.withValues(alpha: 0.08));
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -1.1,
        height: 1.05,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.7,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.35,
      ),
    ),
    extensions: [
      PiDesignTokens(
        style: style,
        pagePadding: pagePadding,
        sectionGap: gap,
        radius: radius,
        dense: dense,
      ),
    ],
    cardTheme: CardThemeData(
      color: surface,
      elevation: elevation,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: style == PiLayoutStyle.aurora
              ? scheme.primary.withValues(alpha: 0.12)
              : style == PiLayoutStyle.commandCenter
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0B1220),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius * .62),
        borderSide: border,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius * .62),
        borderSide: border,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius * .62),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 16,
        vertical: dense ? 11 : 15,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, dense ? 42 : 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius * .6),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, dense ? 40 : 46),
        side: border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius * .6),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: surface,
      selectedColor: scheme.primaryContainer,
      side: border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius * .5),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius * .58),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF202A3B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius * .55),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.primary.withValues(alpha: .12),
      circularTrackColor: scheme.primary.withValues(alpha: .12),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.white.withValues(alpha: .07),
      indicatorColor: scheme.primary,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius * .8),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: scheme.primary.withValues(alpha: .22),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w800,
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: style == PiLayoutStyle.compact ? 66 : 76,
      backgroundColor: surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.22),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class PiPageSurface extends StatelessWidget {
  final Widget child;

  const PiPageSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = context.piDesign;
    if (tokens.style != PiLayoutStyle.aurora &&
        tokens.style != PiLayoutStyle.commandCenter) {
      return child;
    }
    final primary = Theme.of(context).colorScheme.primary;
    final glow = tokens.style == PiLayoutStyle.commandCenter ? .085 : .13;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.82, -1.05),
          radius: 1.35,
          colors: [
            primary.withValues(alpha: glow),
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
      ),
      child: child,
    );
  }
}

class PiNavigationItem {
  final String keyName;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const PiNavigationItem({
    required this.keyName,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class PiLayoutFrame extends StatelessWidget {
  final PiLayoutStyle style;
  final int selectedIndex;
  final List<PiNavigationItem> items;
  final ValueChanged<int> onSelected;
  final Widget child;

  const PiLayoutFrame({
    super.key,
    required this.style,
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (style == PiLayoutStyle.commandCenter) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              children: [
                _PiTopNavigation(
                  items: items,
                  selectedIndex: selectedIndex,
                  onSelected: onSelected,
                  compact: false,
                ),
                Expanded(child: child),
              ],
            );
          }
          final extended = constraints.maxWidth >= 1050;
          return Row(
            children: [
              NavigationRail(
                extended: extended,
                minExtendedWidth: 218,
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                groupAlignment: -0.78,
                backgroundColor: const Color(0xFF0A111D),
                indicatorColor: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.24),
                leading: Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 22),
                  child: extended
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.developer_board_rounded),
                            SizedBox(width: 10),
                            Text(
                              'PI CONTROL',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        )
                      : const Icon(Icons.developer_board_rounded),
                ),
                destinations: [
                  for (final item in items)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(item.label),
                    ),
                ],
              ),
              VerticalDivider(
                width: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              Expanded(child: child),
            ],
          );
        },
      );
    }

    if (style == PiLayoutStyle.compact) {
      return Column(
        children: [
          _PiTopNavigation(
            items: items,
            selectedIndex: selectedIndex,
            onSelected: onSelected,
            compact: true,
          ),
          Expanded(child: child),
        ],
      );
    }

    return child;
  }
}

class PiBottomNavigation extends StatelessWidget {
  final PiLayoutStyle style;
  final int selectedIndex;
  final List<PiNavigationItem> items;
  final ValueChanged<int> onSelected;

  const PiBottomNavigation({
    super.key,
    required this.style,
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useScrollableNavigation =
            constraints.maxWidth < 560 && items.length > 4;
        final bar = useScrollableNavigation
            ? _PiScrollableBottomNavigation(
                items: items,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              )
            : NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                destinations: [
                  for (final item in items)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                ],
              );

        final bottomBar = style == PiLayoutStyle.aurora
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: bar,
                ),
              )
            : bar;
        return SafeArea(top: false, child: bottomBar);
      },
    );
  }
}

class _PiTopNavigation extends StatelessWidget {
  final List<PiNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool compact;

  const _PiTopNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0C1421),
      child: SizedBox(
        height: compact ? 52 : 64,
        child: ListView.separated(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 7 : 8,
          ),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => SizedBox(width: compact ? 6 : 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final selected = index == selectedIndex;
            if (compact) {
              return FilterChip(
                selected: selected,
                showCheckmark: false,
                avatar: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 18,
                ),
                label: Text(item.label),
                onSelected: (_) => onSelected(index),
                visualDensity: VisualDensity.compact,
              );
            }
            return ChoiceChip(
              selected: selected,
              showCheckmark: false,
              avatar: Icon(selected ? item.selectedIcon : item.icon, size: 19),
              label: Text(item.label),
              onSelected: (_) => onSelected(index),
              visualDensity: VisualDensity.standard,
            );
          },
        ),
      ),
    );
  }
}

class _PiScrollableBottomNavigation extends StatefulWidget {
  final List<PiNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _PiScrollableBottomNavigation({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  State<_PiScrollableBottomNavigation> createState() =>
      _PiScrollableBottomNavigationState();
}

class _PiScrollableBottomNavigationState
    extends State<_PiScrollableBottomNavigation> {
  late final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _PiScrollableBottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final target = (widget.selectedIndex * 76.0).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        );
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 68,
      child: Material(
        color:
            Theme.of(context).navigationBarTheme.backgroundColor ??
            colors.surface,
        child: ListView.separated(
          controller: _controller,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          scrollDirection: Axis.horizontal,
          itemCount: widget.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final selected = index == widget.selectedIndex;
            return SizedBox(
              width: 68,
              child: Semantics(
                button: true,
                selected: selected,
                label: item.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onSelected(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.primary.withValues(alpha: .20)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          selected ? item.selectedIcon : item.icon,
                          size: 20,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class PiLayoutOptionCard extends StatelessWidget {
  final PiLayoutStyle style;
  final bool selected;
  final VoidCallback onTap;

  const PiLayoutOptionCard({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: 0.55),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _LayoutPreview(style: style, selected: selected),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    style.label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    style.description,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

class _LayoutPreview extends StatelessWidget {
  final PiLayoutStyle style;
  final bool selected;

  const _LayoutPreview({required this.style, required this.selected});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final line = selected ? primary : Colors.white54;
    Widget block({double? width, double? height}) => Container(
      width: width,
      height: height ?? 5,
      decoration: BoxDecoration(
        color: line.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(4),
      ),
    );

    return Container(
      width: 68,
      height: 52,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF080D15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line.withValues(alpha: .25)),
      ),
      child: switch (style) {
        PiLayoutStyle.commandCenter => Row(
          children: [
            Container(width: 13, color: line.withValues(alpha: .28)),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                children: [
                  block(),
                  const SizedBox(height: 5),
                  block(height: 22),
                ],
              ),
            ),
          ],
        ),
        PiLayoutStyle.compact => Column(
          children: [
            block(height: 8),
            const SizedBox(height: 4),
            Expanded(child: block()),
          ],
        ),
        PiLayoutStyle.classic => Column(
          children: [
            block(height: 7),
            const SizedBox(height: 5),
            Expanded(child: block()),
            const SizedBox(height: 4),
            block(height: 7),
          ],
        ),
        PiLayoutStyle.aurora => Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, primary.withValues(alpha: .22)],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
            const SizedBox(height: 5),
            block(height: 7),
          ],
        ),
      },
    );
  }
}
