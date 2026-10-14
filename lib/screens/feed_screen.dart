import 'dart:collection';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/feed_engine.dart';
import '../data/progress_store.dart';
import '../data/quiz_generator.dart';
import '../models/category.dart';
import '../widgets/confetti.dart';
import '../theme.dart';
import '../widgets/feed_pages.dart';

/// The home feed: full-screen cards, swipe up for the next one.
///
/// Reading earns XP (a quote read for 4 seconds, a story read for 12 or
/// opened), quizzes earn more, and the daily goal keeps the streak alive.
/// What the user lingers on, likes or skips steers the mix.
/// Widest the feed gets; wider screens show black on both sides.
const maxFeedWidth = 560.0;

class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    this.active = true,
    this.quizOnly = false,
    this.random,
    this.now,
  });

  /// False while another tab is shown; reading time then stops counting.
  final bool active;

  /// The Quiz tab: the same feed with a question on every card.
  final bool quizOnly;

  /// For tests.
  final Random? random;
  final DateTime Function()? now;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const _quoteReadXp = 2;
  static const _storyReadXp = 5;
  static const _quoteDwell = Duration(seconds: 4);
  static const _storyDwell = Duration(seconds: 12);
  static const _quickSkip = Duration(milliseconds: 1500);

  final _pages = PageController();
  final _focus = FocusNode(debugLabel: 'feed');
  FeedEngine? _engine;
  int _index = 0;

  /// Furthest page shown; cards up to here are never replanned.
  int _furthest = 0;

  /// Overscroll gathered at the end of a story's text, see [_onInnerScroll].
  double _pull = 0;
  bool _handedOff = false;
  DateTime? _shownAt;
  final _rewarded = <int>{};
  final _opened = <int>{};
  final _celebrations = Queue<Milestone>();
  int _burstKey = 0;
  String? _burstText;
  Offset? _heartAt;
  int _heartKey = 0;

  ProgressStore get _progress => AppScope.of(context).progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_engine != null) return;
    final scope = AppScope.of(context);
    _engine = FeedEngine(
      quotes: scope.repository,
      stories: scope.stories,
      progress: scope.progress,
      quizzes: QuizGenerator(scope.repository.quotes, scope.stories.stories),
      random: widget.random,
      quizOnly: widget.quizOnly,
    );
    _show(0);
  }

  @override
  void didUpdateWidget(FeedScreen old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) {
      _settle(_index);
    } else if (!old.active && widget.active) {
      _shownAt = _now();
      _focus.requestFocus();
    }
  }

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void dispose() {
    _pages.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? _idOf(FeedCard card) => switch (card) {
    QuoteFeedCard(:final quote) => quote.id,
    StoryFeedCard(:final story) => story.id,
    QuizFeedCard() => null,
  };

  void _show(int index) {
    _index = index;
    _furthest = max(_furthest, index);
    final card = _engine!.cardAt(index);
    if (_idOf(card) case final id?) _progress.markSeen(id);
    _shownAt = _now();
    _precache(index + 1);
    _precache(index + 2);
  }

  void _precache(int index) {
    final scope = AppScope.of(context);
    final art = switch (_engine!.cardAt(index)) {
      QuoteFeedCard(:final quote) => scope.images.artForQuote(quote),
      StoryFeedCard(:final story) => scope.images.artForStory(story),
      QuizFeedCard() => null,
    };
    if (art != null) {
      precacheImage(AssetImage(art.asset), context, onError: (_, _) {});
    }
  }

  /// Rewards and feed signals for the page being left.
  void _settle(int index) {
    final shown = _shownAt;
    if (shown == null) return;
    _shownAt = null;
    final dwell = _now().difference(shown);
    final card = _engine!.cardAt(index);
    if (card is QuizFeedCard) return;
    final story = card is StoryFeedCard;
    final read =
        dwell >= (story ? _storyDwell : _quoteDwell) || _opened.contains(index);
    if (read) {
      _progress.nudge(card.category, card.kind, 0.1);
      _engine!.steer(card, 1.3, keep: _furthest);
      if (_rewarded.add(index)) {
        _award(story ? _storyReadXp : _quoteReadXp, card.category);
      }
    } else if (dwell < _quickSkip) {
      _progress.nudge(card.category, card.kind, -0.05);
      _engine!.steer(card, 0.7, keep: _furthest);
    }
  }

  void _onPageChanged(int index) {
    _furthest = max(_furthest, index);
    _settle(_index);
    _show(index);
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    const step = Duration(milliseconds: 300);
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown ||
          LogicalKeyboardKey.space ||
          LogicalKeyboardKey.pageDown:
        _pages.nextPage(duration: step, curve: Curves.easeOut);
      case LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.pageUp:
        _pages.previousPage(duration: step, curve: Curves.easeOut);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _award(int xp, String category) {
    if (xp <= 0) return;
    final milestones = _progress.award(xp, category);
    setState(() {
      _burstText = '+$xp XP';
      _burstKey++;
      _celebrations.addAll(milestones);
    });
    if (milestones.isNotEmpty) HapticFeedback.heavyImpact();
  }

  /// A like counts for good (affinity) and right now: the next cards
  /// lean to the same category and kind.
  void _like(FeedCard card) {
    _progress.nudge(card.category, card.kind, 0.5);
    _engine!.steer(card, 4, keep: _furthest);
    _precache(_index + 1);
    _precache(_index + 2);
  }

  /// A story that scrolls inside its card hands the drag back to the feed
  /// when pulled past its end (next card) or its top (previous card).
  bool _onInnerScroll(ScrollNotification n) {
    if (n.depth == 0) return false;
    if (n is OverscrollNotification && n.dragDetails != null) {
      _pull += n.overscroll;
      if (!_handedOff && _pull.abs() > 48) {
        _handedOff = true;
        const step = Duration(milliseconds: 300);
        _pull > 0
            ? _pages.nextPage(duration: step, curve: Curves.easeOut)
            : _pages.previousPage(duration: step, curve: Curves.easeOut);
      }
    } else if (n is ScrollEndNotification || n is ScrollStartNotification) {
      _pull = 0;
      _handedOff = false;
    }
    return false;
  }

  void _onDoubleTap(TapDownDetails d) {
    final card = _engine!.cardAt(_index);
    final id = _idOf(card);
    if (id == null) return;
    final favorites = AppScope.of(context).favorites;
    if (!favorites.contains(id)) {
      favorites.toggle(id);
      _like(card);
    }
    HapticFeedback.lightImpact();
    setState(() {
      final box = context.findRenderObject() as RenderBox?;
      _heartAt = box?.globalToLocal(d.globalPosition) ?? d.localPosition;
      _heartKey++;
    });
  }

  Widget _page(int index) {
    final card = _engine!.cardAt(index);
    return switch (card) {
      QuoteFeedCard(:final quote, :final header) => QuoteFeedPage(
        quote: quote,
        header: header,
        onLike: () => _like(card),
        onDoubleTap: _onDoubleTap,
      ),
      StoryFeedCard(:final story) => StoryFeedPage(
        story: story,
        onLike: () => _like(card),
        onOpened: () => _opened.add(index),
        onDoubleTap: _onDoubleTap,
      ),
      QuizFeedCard(:final quiz, :final review) => QuizFeedPage(
        quiz: quiz,
        review: review,
        onAnswer: (correct) {
          final xp = _progress.answerQuiz(quiz.itemId, correct: correct);
          _award(xp, quiz.category);
          return xp;
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: blackTheme(),
      child: ColoredBox(
        color: Colors.black,
        // Phone-width column on wide screens (web, desktop), as on TikTok
        // web; full width on phones.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxFeedWidth),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Desktop: drag with the mouse too, and arrow keys or space.
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                  child: Focus(
                    focusNode: _focus,
                    autofocus: widget.active,
                    onKeyEvent: _onKey,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onInnerScroll,
                      child: PageView.builder(
                        controller: _pages,
                        scrollDirection: Axis.vertical,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, i) => _page(i),
                      ),
                    ),
                  ),
                ),
                if (_heartAt case final at?)
                  _HeartBurst(key: ValueKey(_heartKey), at: at),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(child: _Hud()),
                ),
                if (_burstText case final text?)
                  Positioned(
                    top: 0,
                    right: 16,
                    child: SafeArea(
                      child: _XpBurst(key: ValueKey(_burstKey), text: text),
                    ),
                  ),
                if (_celebrations.isNotEmpty)
                  _Celebration(
                    key: ValueKey(_celebrations.first),
                    milestone: _celebrations.first,
                    onDone: () => setState(_celebrations.removeFirst),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Streak, daily goal ring and combo, always on top of the feed.
class _Hud extends StatelessWidget {
  const _Hud();

  @override
  Widget build(BuildContext context) {
    final progress = AppScope.of(context).progress;
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        final goal = progress.dailyGoal;
        final today = progress.todayXp;
        final done = progress.goalReachedToday;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _Pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 22,
                      color: done ? Colors.orangeAccent : Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${progress.currentStreak}',
                      style: TextStyle(
                        color: done ? Colors.orangeAccent : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (progress.combo >= 2)
                _Pill(
                  child: Text(
                    'Combo x${progress.combo}',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const Spacer(),
              _Pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        value: (today / goal).clamp(0.0, 1.0),
                        strokeWidth: 4,
                        backgroundColor: Colors.white24,
                        color: done ? Colors.greenAccent : Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$today / $goal XP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

/// "+10 XP" floating up from the goal ring.
class _XpBurst extends StatelessWidget {
  const _XpBurst({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t < 0.7 ? 1 : (1 - t) / 0.3,
        child: Transform.translate(
          offset: Offset(0, 56 - 24 * t),
          child: Transform.scale(scale: 0.8 + 0.4 * sin(t * pi), child: child),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.amberAccent,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
        ),
      ),
    );
  }
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst({super.key, required this.at});

  final Offset at;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: at.dx - 60,
      top: at.dy - 60,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          builder: (context, t, _) => Opacity(
            opacity: t < 0.6 ? 1 : (1 - t) / 0.4,
            child: Transform.scale(
              scale: 0.5 + 0.9 * Curves.elasticOut.transform(min(1, t * 1.6)),
              child: const Icon(
                Icons.favorite,
                size: 120,
                color: Colors.redAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen celebration with confetti for goals and level ups.
class _Celebration extends StatelessWidget {
  const _Celebration({
    super.key,
    required this.milestone,
    required this.onDone,
  });

  final Milestone milestone;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (milestone) {
      GoalReached(:final streak) => (
        Icons.local_fire_department_rounded,
        'Daily goal reached!',
        streak == 1
            ? 'Day 1 of your streak. Come back tomorrow to make it 2.'
            : '$streak day streak. Today is safe; come back tomorrow '
                  'to keep it going.',
      ),
      LevelUp(:final category, :final level) => (
        QuoteCategory.byId(category).icon,
        '${QuoteCategory.byId(category).label} level $level',
        'You keep learning about '
            '${QuoteCategory.byId(category).label.toLowerCase()}. '
            'The next level unlocks at '
            '${ProgressStore.levelStart(level + 1)} XP.',
      ),
    };
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: onDone,
          child: const ColoredBox(color: Color(0xAA000000)),
        ),
        const Confetti(),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, s, child) =>
                Transform.scale(scale: s, child: child),
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 64, color: Colors.orangeAccent),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onDone,
                      child: const Text('Keep going'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
