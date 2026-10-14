import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../data/image_repository.dart';
import '../data/quiz_generator.dart';
import '../data/stable_hash.dart';
import '../models/category.dart';
import '../models/quote.dart';
import '../models/story.dart';
import '../screens/category_screen.dart';
import '../screens/quote_screen.dart';
import '../screens/story_list_screen.dart';
import '../screens/story_screen.dart';
import 'art_background.dart';
import 'item_actions.dart';
import 'person_sheet.dart';
import 'story_card.dart';

/// Space kept free at the top for the streak and goal bar.
const _hudHeight = 64.0;

/// Width of the action rail on the right.
const _railWidth = 50.0;

TextStyle? _quoteStyle(BuildContext context, int length) {
  final t = Theme.of(context).textTheme;
  final base = length < 120
      ? t.headlineMedium
      : length < 260
      ? t.headlineSmall
      : length < 450
      ? t.titleLarge
      : t.titleMedium;
  return base?.copyWith(
    color: Colors.white,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );
}

/// Background, readable content at the bottom, action rail on the right
/// and the image credit; the frame every feed page shares.
class _FeedFrame extends StatelessWidget {
  const _FeedFrame({
    required this.art,
    required this.seed,
    required this.content,
    this.rail,
    this.onDoubleTap,
    this.scroll = false,
  });

  final ArtImage? art;
  final int seed;
  final Widget content;
  final Widget? rail;

  /// Long content (a full story) scrolls inside its panel instead of
  /// shrinking; the feed turns the page when it is pulled past either end.
  final bool scroll;

  /// Double tap on the picture (not on buttons) likes the card.
  final GestureTapDownCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final credit = art?.credit ?? '';
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTapDown: onDoubleTap,
          onDoubleTap: onDoubleTap == null ? null : () {},
          child: ArtBackground(art: art, seed: seed),
        ),
        SafeArea(
          child: Padding(
            // Narrow side margins in portrait, where width is scarce.
            padding: EdgeInsets.fromLTRB(
              portrait ? 8 : 20,
              _hudHeight,
              rail == null ? (portrait ? 8 : 20) : _railWidth,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content sits at the bottom. Short content shrinks to fit
                // instead of scrolling, so a vertical drag always reaches
                // the feed; long content scrolls only when it overflows.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.bottomLeft,
                      child: scroll
                          ? _panel(
                              c.maxWidth,
                              // The bottom edge fades out, a hint that
                              // the text goes on.
                              ShaderMask(
                                blendMode: BlendMode.dstIn,
                                shaderCallback: (r) => LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: const [
                                    Colors.white,
                                    Colors.transparent,
                                  ],
                                  stops: [1 - 28 / max(r.height, 56), 1],
                                ).createShader(r),
                                child: SingleChildScrollView(
                                  // Clamping: overscroll at the ends is
                                  // what turns the page (FeedScreen).
                                  physics: const ClampingScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    28,
                                  ),
                                  child: content,
                                ),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: _panel(
                                c.maxWidth,
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: content,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                if (credit.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Image: $credit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (rail != null)
          Positioned(right: 2, bottom: 24, child: SafeArea(child: rail!)),
      ],
    );
  }
}

/// Dimmed panel: the picture stays visible around and through it, the text
/// stays readable.
Widget _panel(double width, Widget child) => SizedBox(
  width: width,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: child,
    ),
  ),
);

/// The TikTok style column of actions: who, like, copy, share, details.
class FeedRail extends StatelessWidget {
  const FeedRail({
    super.key,
    required this.id,
    required this.person,
    required this.shareText,
    required this.onLike,
    required this.onPerson,
    required this.onDetails,
  });

  final String id;
  final String? person;
  final String shareText;
  final VoidCallback onLike;
  final VoidCallback? onPerson;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final avatar = scope.images.avatarFor(person);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (person != null)
          _RailButton(
            label: '',
            onTap: onPerson,
            child: CircleAvatar(
              radius: 19,
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: 17.5,
                backgroundColor: Colors.blueGrey.shade700,
                foregroundImage: avatar == null ? null : AssetImage(avatar),
                child: Text(
                  _initials(person!),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ListenableBuilder(
          listenable: scope.favorites,
          builder: (context, _) {
            final fav = scope.favorites.contains(id);
            return _RailButton(
              label: fav ? 'Saved' : 'Like',
              onTap: () {
                if (!fav) onLike();
                scope.favorites.toggle(id);
              },
              child: Icon(
                fav ? Icons.favorite : Icons.favorite_border,
                size: 27,
                color: fav ? Colors.redAccent : Colors.white,
              ),
            );
          },
        ),
        _RailButton(
          label: 'Copy',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: shareText));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Copied')));
          },
          child: const Icon(Icons.copy_rounded, size: 23, color: Colors.white),
        ),
        if (canShare)
          _RailButton(
            label: 'Share',
            onTap: () => SharePlus.instance.share(ShareParams(text: shareText)),
            child: const Icon(
              Icons.reply_rounded,
              size: 27,
              color: Colors.white,
            ),
          ),
        _RailButton(
          label: 'More',
          onTap: onDetails,
          child: const Icon(
            Icons.info_outline_rounded,
            size: 24,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  static String _initials(String name) => name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && w[0].toUpperCase() == w[0])
      .take(2)
      .map((w) => w[0])
      .join();
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.label, required this.child, this.onTap});

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Column(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 12)],
              ),
              child: child,
            ),
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class QuoteFeedPage extends StatelessWidget {
  const QuoteFeedPage({
    super.key,
    required this.quote,
    required this.onLike,
    this.onDoubleTap,
    this.header,
  });

  final Quote quote;
  final String? header;
  final VoidCallback onLike;
  final GestureTapDownCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final category = QuoteCategory.byId(quote.category);
    final person = quote.speaker ?? quote.author;
    return _FeedFrame(
      art: scope.images.artForQuote(quote),
      seed: stableHash(quote.id),
      onDoubleTap: onDoubleTap,
      rail: FeedRail(
        id: quote.id,
        person: person,
        shareText: quote.toShareText(),
        onLike: onLike,
        onPerson: () => showPersonSheet(
          context,
          person,
          browseLabel: 'All quotes by $person',
          onBrowse: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CategoryScreen(initialQuery: person),
            ),
          ),
        ),
        onDetails: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => QuoteScreen(quote: quote))),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(category.icon, header ?? category.label),
          const SizedBox(height: 14),
          Text(
            '"${quote.text}"',
            style: _quoteStyle(context, quote.text.length),
          ),
          const SizedBox(height: 16),
          Text(
            quote.byline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            quote.citation,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class StoryFeedPage extends StatelessWidget {
  const StoryFeedPage({
    super.key,
    required this.story,
    required this.onLike,
    required this.onOpened,
    this.onDoubleTap,
  });

  static const _body = TextStyle(
    color: Colors.white,
    fontSize: 16.5,
    height: 1.5,
  );

  final Story story;
  final VoidCallback onLike;
  final GestureTapDownCallback? onDoubleTap;

  /// Called when the story's detail page is opened (counts as reading).
  final VoidCallback onOpened;

  static IconData _kindIcon(StoryKind k) => storyKindIcon(k);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final category = QuoteCategory.byId(story.category);
    final paragraphs = story.text.split('\n\n');
    final person = story.people.isEmpty
        ? null
        : story.people.split(',').first.split(' and ').first.trim();
    return _FeedFrame(
      art: scope.images.artForStory(story),
      seed: stableHash(story.id),
      onDoubleTap: onDoubleTap,
      rail: FeedRail(
        id: story.id,
        person: story.kind == StoryKind.story ? null : person,
        shareText: story.toShareText(),
        onLike: onLike,
        onPerson: person == null
            ? null
            : () => showPersonSheet(
                context,
                person,
                browseLabel: 'Stories about $person',
                // In a story the person is a figure in it, not its author.
                wikiLabel: 'Read about this person on Wikipedia',
                onBrowse: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StoryListScreen(initialQuery: person),
                  ),
                ),
              ),
        onDetails: () {
          onOpened();
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => StoryScreen(story: story)));
        },
      ),
      scroll: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(_kindIcon(story.kind), story.kind.label),
              _Chip(category.icon, category.label),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            story.title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          if (story.date.isNotEmpty || story.location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  story.date,
                  story.location,
                ].where((s) => s.isNotEmpty).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          // The whole story, right on the card.
          for (final p in paragraphs) ...[
            Text(p, style: _body),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.lightbulb, color: Colors.amber, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  story.lesson,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A question with big answer buttons and instant feedback.
class QuizFeedPage extends StatefulWidget {
  const QuizFeedPage({
    super.key,
    required this.quiz,
    required this.review,
    required this.onAnswer,
  });

  final Quiz quiz;
  final bool review;

  /// Returns the XP earned, shown on the page.
  final int Function(bool correct) onAnswer;

  @override
  State<QuizFeedPage> createState() => _QuizFeedPageState();
}

class _QuizFeedPageState extends State<QuizFeedPage> {
  int? _picked;
  int _xp = 0;

  void _pick(int i) {
    if (_picked != null) return;
    final correct = i == widget.quiz.answer;
    correct ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    final xp = widget.onAnswer(correct);
    setState(() {
      _picked = i;
      _xp = xp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quiz;
    final scope = AppScope.of(context);
    final quote = scope.repository.byId(q.itemId);
    final story = scope.stories.byId(q.itemId);
    final event = scope.events.byId(q.itemId);
    final art = quote != null
        ? scope.images.artForQuote(quote)
        : story != null
        ? scope.images.artForStory(story)
        : event != null
        ? scope.images.artForEvent(event)
        : null;
    final picked = _picked;
    final right = picked != null && picked == q.answer;
    return _FeedFrame(
      art: art,
      seed: stableHash(q.itemId) + 1,
      // The explanation after an answer can make it tall; scroll rather
      // than shrink the text.
      scroll: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(
            widget.review ? Icons.replay_rounded : Icons.bolt_rounded,
            widget.review ? 'Review' : 'Quick check',
          ),
          const SizedBox(height: 12),
          Text(
            q.question,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            q.subject,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < q.options.length; i++)
            _OptionButton(
              text: q.options[i],
              state: picked == null
                  ? _OptionState.open
                  : i == q.answer
                  ? _OptionState.right
                  : i == picked
                  ? _OptionState.wrong
                  : _OptionState.dimmed,
              onTap: () => _pick(i),
            ),
          if (picked != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    right
                        ? Icons.check_circle_rounded
                        : Icons.replay_circle_filled_rounded,
                    color: right ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      right
                          ? 'Correct! +$_xp XP. Swipe up for more.'
                          : 'Not quite. It will come back soon so it '
                                'sticks. Swipe up for more.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (picked != null && q.explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                q.explanation,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _OptionState { open, right, wrong, dimmed }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (state) {
      _OptionState.open => (
        Colors.white.withValues(alpha: 0.12),
        Colors.white54,
      ),
      _OptionState.right => (
        Colors.green.withValues(alpha: 0.55),
        Colors.greenAccent,
      ),
      _OptionState.wrong => (
        Colors.red.withValues(alpha: 0.5),
        Colors.redAccent,
      ),
      _OptionState.dimmed => (
        Colors.white.withValues(alpha: 0.05),
        Colors.white24,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        width: double.infinity,
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: state == _OptionState.open ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
