import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ads.dart';
import '../core/audio.dart';
import '../core/save.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Paged level grid (50 per page) with stars, locks and current-level pulse.
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  final PageController _pager = PageController();
  int _page = 0;
  static const int perPage = 50;
  final int totalPages = (1000 + perPage - 1) ~/ perPage;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _jumpToCurrent() {
    final current = GameSave.instance.maxLevel;
    final p = ((current - 1) ~/ perPage).clamp(0, totalPages - 1);
    _pager.jumpToPage(p);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
  }

  @override
  Widget build(BuildContext context) {
    final save = GameSave.instance;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  RoundIcon(
                    icon: Icons.arrow_back_rounded,
                    onTap: () {
                      GameAudio.play('close');
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Levels', style: AppTheme.display(24)),
                        Text(
                          '${save.totalStars} / 3000 stars',
                          style: AppTheme.body(13, color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SavedCoinPill(),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: totalPages,
                onPageChanged: (p) {
                  setState(() => _page = p);
                  GameAudio.play('open');
                },
                itemBuilder: (context, p) {
                  final start = p * perPage + 1;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: perPage,
                    itemBuilder: (context, i) {
                      final level = start + i;
                      if (level > 1000) return const SizedBox();
                      return _LevelCell(level: level);
                    },
                  );
                },
              ),
            ),
            _PagerDots(
              count: totalPages,
              current: _page,
              onPage: (p) => _pager.animateToPage(
                p,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              ),
            ),
            const AdBanner(),
          ],
        ),
      ),
    );
  }
}

class _LevelCell extends StatefulWidget {
  const _LevelCell({required this.level});

  final int level;

  @override
  State<_LevelCell> createState() => _LevelCellState();
}

class _LevelCellState extends State<_LevelCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.94,
    upperBound: 1.04,
  );

  @override
  void initState() {
    super.initState();
    final save = GameSave.instance;
    if (widget.level == save.maxLevel) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final save = GameSave.instance;
    final unlocked = widget.level <= save.maxLevel;
    final stars = save.starsAt(widget.level);
    final isCurrent = widget.level == save.maxLevel;

    return ScaleTransition(
      scale: _pulse,
      child: GestureDetector(
        onTap: unlocked
            ? () {
                GameAudio.play('confirm');
                Navigator.pushNamed(context, '/game', arguments: widget.level);
              }
            : () {
                GameAudio.play('close');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.ink,
                    content: Text('Clear level ${save.maxLevel} first!',
                        style: AppTheme.body(14, color: Colors.white)),
                    duration: const Duration(milliseconds: 1200),
                  ),
                );
              },
        child: Container(
          decoration: BoxDecoration(
            color: unlocked
                ? (isCurrent ? AppTheme.blue : AppTheme.white)
                : AppTheme.paperDark,
            borderRadius: BorderRadius.circular(16),
            boxShadow: unlocked
                ? const [
                    BoxShadow(
                        color: Color(0x1E241E33),
                        offset: Offset(0, 3),
                        blurRadius: 6)
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              unlocked
                  ? Text('${widget.level}',
                      style: AppTheme.display(20,
                          color: isCurrent ? Colors.white : AppTheme.ink))
                  : const Icon(Icons.lock_rounded,
                      size: 20, color: Color(0xFFB9AFA4)),
              const SizedBox(height: 2),
              SizedBox(
                height: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int s = 0; s < 3; s++)
                      Icon(
                        Icons.star_rounded,
                        size: 12,
                        color: s < stars
                            ? AppTheme.gold
                            : (unlocked
                                ? const Color(0xFFE3DACE)
                                : const Color(0xFFDDD5C9)),
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

class _PagerDots extends StatelessWidget {
  const _PagerDots({required this.count, required this.current, required this.onPage});

  final int count;
  final int current;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    // compact window of dots
    const window = 7;
    int start = (current - window ~/ 2).clamp(0, math.max(0, count - window));
    int end = math.min(count, start + window);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: start > 0 ? () => onPage(0) : null,
            icon: const Icon(Icons.first_page_rounded, size: 20),
          ),
          for (int p = start; p < end; p++)
            GestureDetector(
              onTap: () => onPage(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: p == current ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p == current ? AppTheme.blue : const Color(0xFFD8CFC4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          IconButton(
            onPressed: end < count ? () => onPage(count - 1) : null,
            icon: const Icon(Icons.last_page_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
