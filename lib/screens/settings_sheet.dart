import 'package:flutter/material.dart';

import '../core/audio.dart';
import '../core/save.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Settings bottom sheet: sound/music/haptics toggles, line theme picker
/// (unlock with coins), reset progress with confirmation.
Future<void> showSettingsSheet(BuildContext context) async {
  GameAudio.play('open');
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final save = GameSave.instance;
    return Container(
      margin: const EdgeInsets.only(top: 24),
      decoration: const BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.paperDark,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Settings', textAlign: TextAlign.center,
                  style: AppTheme.display(26)),
              const SizedBox(height: 16),
              _toggle('Sound effects', Icons.volume_up_rounded, save.soundOn,
                  (v) => setState(() {
                        save.setSoundOn(v);
                        GameAudio.applySettings(sound: v, music: save.musicOn);
                        if (v) GameAudio.play('confirm');
                      })),
              _toggle('Music', Icons.music_note_rounded, save.musicOn,
                  (v) => setState(() {
                        save.setMusicOn(v);
                        GameAudio.applySettings(
                            sound: save.soundOn, music: v);
                      })),
              _toggle('Haptics', Icons.vibration_rounded, save.hapticsOn,
                  (v) => setState(() => save.setHapticsOn(v))),
              const SizedBox(height: 18),
              Text('Arrow style', style: AppTheme.title(17)),
              const SizedBox(height: 10),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: LineTheme.all.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final t = LineTheme.all[i];
                    final unlocked = save.unlockedThemes.contains(t.id);
                    final selected = save.themeId == t.id;
                    return GestureDetector(
                      onTap: () => _onThemeTap(t, unlocked),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 92,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.blue.withAlpha(26)
                              : AppTheme.paper,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected ? AppTheme.blue : AppTheme.paperDark,
                            width: selected ? 2.5 : 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 44,
                              height: 10,
                              decoration: BoxDecoration(
                                color: t.line,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: t.glow
                                    ? [BoxShadow(color: t.line.withAlpha(120), blurRadius: 10)]
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Icon(Icons.play_arrow_rounded,
                                size: 26, color: t.head),
                            const SizedBox(height: 2),
                            Text(
                              t.name,
                              style: AppTheme.body(13,
                                  w: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            unlocked
                                ? (selected
                                    ? const Icon(Icons.check_circle_rounded,
                                        size: 16, color: AppTheme.blue)
                                    : const SizedBox(height: 16))
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('${t.price}',
                                          style: AppTheme.body(12,
                                              color: AppTheme.inkSoft)),
                                      const Icon(Icons.bolt_rounded,
                                          size: 14, color: AppTheme.gold),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              JuicyButton(
                color: AppTheme.red,
                height: 52,
                onPressed: () => _confirmReset(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.restart_alt_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text('Reset progress',
                        style: AppTheme.title(16, color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Stars ${save.totalStars} · Coins ${save.coins} · Unlocked level ${save.maxLevel}',
                textAlign: TextAlign.center,
                style: AppTheme.body(13, color: AppTheme.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle(
      String label, IconData icon, bool value, ValueChanged<bool> onChange) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AppTheme.ink),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTheme.title(16))),
          Switch.adaptive(
            value: value,
            activeColor: AppTheme.blue,
            onChanged: onChange,
          ),
        ],
      ),
    );
  }

  void _onThemeTap(LineTheme t, bool unlocked) {
    final save = GameSave.instance;
    if (unlocked) {
      save.setThemeId(t.id);
      GameAudio.play('confirm');
      setState(() {});
      return;
    }
    if (save.coins >= t.price) {
      save.addCoins(-t.price);
      save.unlockTheme(t.id);
      save.setThemeId(t.id);
      GameAudio.playSynth('unlock');
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.ink,
            content: Text('${t.name} unlocked!',
                style: AppTheme.body(14, color: Colors.white)),
            duration: const Duration(milliseconds: 1400),
          ),
        );
      }
    } else {
      GameAudio.play('close');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.ink,
            content: Text('Need ${t.price - save.coins} more coins — win levels to earn!',
                style: AppTheme.body(14, color: Colors.white)),
            duration: const Duration(milliseconds: 1400),
          ),
        );
      }
    }
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Reset everything?', style: AppTheme.display(20)),
        content: Text(
          'Progress, stars and coins will be wiped. Arrow styles you bought stay yours.',
          style: AppTheme.body(14, color: AppTheme.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTheme.title(15)),
          ),
          TextButton(
            onPressed: () {
              GameSave.instance.resetAll();
              GameAudio.play('close');
              Navigator.pop(ctx);
              setState(() {});
            },
            child:
                Text('Reset', style: AppTheme.title(15, color: AppTheme.red)),
          ),
        ],
      ),
    );
  }
}
