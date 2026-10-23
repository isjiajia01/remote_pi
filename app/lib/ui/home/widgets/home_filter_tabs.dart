import 'package:app/ui/core/interaction_feedback.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:flutter/cupertino.dart';

class HomeFilterTabs extends StatelessWidget {
  const HomeFilterTabs({
    super.key,
    required this.filter,
    required this.counts,
    required this.onSelected,
    this.stale = false,
  });
  final HomeFilter filter;
  final ({int all, int working, int online, int offline}) counts;
  final ValueChanged<HomeFilter> onSelected;
  final bool stale;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        _chip(context, HomeFilter.all, 'All', '${counts.all}'),
        _chip(
          context,
          HomeFilter.working,
          'Working',
          stale ? '–' : '${counts.working}',
        ),
        _chip(context, HomeFilter.online, 'Online', '${counts.online}'),
        _chip(context, HomeFilter.offline, 'Offline', '${counts.offline}'),
      ],
    ),
  );

  Widget _chip(
    BuildContext context,
    HomeFilter value,
    String label,
    String count,
  ) {
    final selected = filter == value;
    void select() {
      if (!selected) InteractionFeedback.selection();
      onSelected(value);
    }

    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        selected: selected,
        button: true,
        label: '$label $count',
        onTap: select,
        child: ExcludeSemantics(
          child: CupertinoButton(
            minimumSize: const Size(0, 44),
            padding: EdgeInsets.zero,
            onPressed: select,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              height: 32,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? c.ink : c.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.typo.footnote.copyWith(
                      color: selected ? c.bg : c.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    count,
                    style: context.typo.footnote.copyWith(
                      fontFeatures: AppTypography.tabularFigures,
                      color:
                          value == HomeFilter.working &&
                              counts.working > 0 &&
                              !stale
                          ? c.working
                          : selected
                          ? c.bg
                          : c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeFilterEmptyState extends StatelessWidget {
  const HomeFilterEmptyState({super.key, required this.filter, this.onShowAll});
  final HomeFilter filter;
  final VoidCallback? onShowAll;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            switch (filter) {
              HomeFilter.working => 'Nothing working right now',
              HomeFilter.offline => 'No offline agents',
              HomeFilter.online => 'No online agents',
              HomeFilter.all => 'No agents running',
            },
            style: context.typo.title2,
            textAlign: TextAlign.center,
          ),
          SecondaryButton(label: 'Show all', onPressed: onShowAll),
        ],
      ),
    ),
  );
}
