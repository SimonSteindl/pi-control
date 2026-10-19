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
    orElse: () => PiLayoutStyle.aurora,
  );
}

ThemeData buildPiLayoutTheme(
  ThemeData base,
  PiLayoutStyle style,
  Color accent,
) {
  // Pi-Control redesign preview: a quieter graphite canvas, warm orange focus,
  // high-contrast typography, and one consistent component language.
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: const Color(0xFF15181E),
  ).copyWith(
    primary: accent,
    secondary: const Color(0xFFFFB36B),
    tertiary: const Color(0xFF65D6C4),
    surface: const Color(0xFF15181E),
    surfaceContainerLowest: const Color(0xFF0C0E12),
    surfaceContainerLow: const Color(0xFF111419),
    surfaceContainer: const Color(0xFF171B21),
    surfaceContainerHigh: const Color(0xFF1D222A),
    surfaceContainerHighest: const Color(0xFF252B34),
    outline: const Color(0xFF343B46),
    outlineVariant: const Color(0xFF2A3039),
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
      const Color(0xFF0B0D11),
      const Color(0xFF15181E),
      22.0,
      0.0,
      18.0,
      16.0,
    ),
    PiLayoutStyle.commandCenter => (
      const Color(0xFF0B0D11),
      const Color(0xFF15181E),
      18.0,
      0.0,
      22.0,
      15.0,
    ),
    PiLayoutStyle.compact => (
      const Color(0xFF0B0D11),
      const Color(0xFF14171C),
      14.0,
      0.0,
      12.0,
      9.0,
    ),
    PiLayoutStyle.classic => (
      const Color(0xFF0D0F13),
      const Color(0xFF171A20),
      16.0,
      0.0,
      16.0,
      12.0,
    ),
  };

  final dense = style == PiLayoutStyle.compact;
  final border = const BorderSide(color: Color(0xFF2A3039));
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: border,
  );
  final textTheme = base.textTheme.apply(
    bodyColor: const Color(0xFFE8EBF0),
    displayColor: const Color(0xFFF7F8FA),
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
    textTheme: textTheme.copyWith(
      displayLarge: textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w900, letterSpacing: -1.5, height: 1.0,
      ),
      headlineLarge: textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w900, letterSpacing: -1.0, height: 1.05,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900, letterSpacing: -0.7,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800, letterSpacing: -0.4,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800, letterSpacing: -0.25,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.42),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.42),
      bodySmall: textTheme.bodySmall?.copyWith(
        color: const Color(0xFFA4ACB8), height: 1.35,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
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
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF292F38), thickness: 1, space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: const Color(0xFFF7F8FA), fontWeight: FontWeight.w800,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: const Color(0xFF535C68),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius + 4)),
        side: border,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0E1116),
      hintStyle: const TextStyle(color: Color(0xFF7E8794)),
      labelStyle: const TextStyle(color: Color(0xFFB7BEC8)),
      prefixIconColor: const Color(0xFF9CA5B1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: border,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: border,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 16, vertical: dense ? 11 : 15,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: const Color(0xFF17100A),
        disabledBackgroundColor: accent.withValues(alpha: .28),
        minimumSize: Size(0, dense ? 42 : 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE8EBF0),
        minimumSize: Size(0, dense ? 40 : 46),
        side: border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFFFA34D),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xFF1A1F26),
      selectedColor: accent.withValues(alpha: .18),
      side: border,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
      iconColor: const Color(0xFFA8B0BC),
      titleTextStyle: textTheme.titleMedium,
      subtitleTextStyle: textTheme.bodySmall,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF252B34),
      contentTextStyle: const TextStyle(color: Color(0xFFF7F8FA)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: accent.withValues(alpha: .15),
      circularTrackColor: accent.withValues(alpha: .15),
    ),
    tabBarTheme: const TabBarThemeData(
      dividerColor: Color(0xFF292F38),
      indicatorColor: Color(0xFFFF7900),
      labelColor: Color(0xFFFFA34D),
      unselectedLabelColor: Color(0xFF929BA8),
      labelStyle: TextStyle(fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: const Color(0xFF17100A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Color(0xFF111419),
      indicatorColor: Color(0x2EFF7900),
      selectedIconTheme: IconThemeData(color: Color(0xFFFFA34D)),
      selectedLabelTextStyle: TextStyle(
        color: Color(0xFFFFA34D), fontWeight: FontWeight.w800,
      ),
      unselectedIconTheme: IconThemeData(color: Color(0xFF8D96A3)),
      unselectedLabelTextStyle: TextStyle(color: Color(0xFF8D96A3)),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Color(0xFF0B0D11),
      foregroundColor: Color(0xFFF7F8FA),
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: style == PiLayoutStyle.compact ? 66 : 72,
      backgroundColor: const Color(0xFF111419),
      surfaceTintColor: Colors.transparent,
      indicatorColor: accent.withValues(alpha: .18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
        fontSize: 11,
        color: states.contains(WidgetState.selected) ? const Color(0xFFFFA34D) : const Color(0xFF8D96A3),
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? accent : const Color(0xFF8D96A3),
      )),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? accent : const Color(0xFF929BA8)),
      trackColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? accent.withValues(alpha: .38) : const Color(0xFF343B46)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? accent : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(Color(0xFF17100A)),
      side: const BorderSide(color: Color(0xFF535C68)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected) ? accent : const Color(0xFF929BA8)),
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
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              bottomBar,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF080D16),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.developer_board_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'PI CONTROL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'by Stoney22',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
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
