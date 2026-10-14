import 'dart:math';

import '../models/event.dart';
import '../models/quote.dart';
import '../models/story.dart';

/// A one-tap question made from a quote or story the user has seen.
class Quiz {
  const Quiz({
    required this.itemId,
    required this.category,
    required this.question,
    required this.subject,
    required this.options,
    required this.answer,
    this.explanation = '',
  });

  final String itemId;
  final String category;
  final String question;

  /// What the question is about: the quote text or the story title.
  final String subject;
  final List<String> options;

  /// Index of the right option.
  final int answer;

  /// Shown after answering: what happened and why.
  final String explanation;
}

/// Builds questions from the collection itself, so every quote and story
/// can be quizzed without writing questions by hand.
class QuizGenerator {
  QuizGenerator(
    List<Quote> quotes,
    List<Story> stories, [
    List<HistoryEvent> events = const [],
  ]) : _events = events,
       _eventsById = {for (final e in events) e.id: e},
       _quotes = {for (final q in quotes) q.id: q},
       _stories = {for (final s in stories) s.id: s},
       _namesByCategory = _names(quotes),
       _lessonsByKind = _lessons(stories),
       _history = [
         for (final s in stories)
           if (s.kind == StoryKind.history && s.year != null) s,
       ];

  final List<HistoryEvent> _events;
  final Map<String, HistoryEvent> _eventsById;
  final Map<String, Quote> _quotes;
  final Map<String, Story> _stories;
  final Map<String, List<String>> _namesByCategory;
  final Map<String, List<String>> _lessonsByKind;
  final List<Story> _history;

  static Map<String, List<String>> _names(List<Quote> quotes) {
    final m = <String, Set<String>>{};
    for (final q in quotes) {
      (m[q.category] ??= {}).add(q.speaker ?? q.author);
    }
    return {for (final e in m.entries) e.key: e.value.toList()};
  }

  static Map<String, List<String>> _lessons(List<Story> stories) {
    final m = <String, List<String>>{};
    for (final s in stories) {
      (m[_lessonPool(s)] ??= []).add(s.lesson);
    }
    return m;
  }

  static String _lessonPool(Story s) =>
      s.kind == StoryKind.study ? 'study' : 'story';

  /// A question about the quote or story with [id], or null when there is
  /// not enough material for wrong answers.
  Quiz? forId(String id, Random random) {
    final q = _quotes[id];
    if (q != null) return _forQuote(q, random);
    final s = _stories[id];
    if (s != null) return _forStory(s, random);
    final e = _eventsById[id];
    return e == null ? null : _forEvent(e, random);
  }

  /// "When did this happen?" (other events' dates, far enough apart that
  /// the question tests the era) or "What happened on this day?" (other
  /// events of roughly the same time).
  Quiz? _forEvent(HistoryEvent e, Random random) {
    final gap = e.year >= 1900
        ? 8
        : e.year >= 1500
        ? 30
        : 100;
    if (random.nextBool()) {
      final wrong = _distinct(
        [
          for (final o in _events)
            if ((o.year - e.year).abs() >= gap) o.dateLabel,
        ],
        e.dateLabel,
        2,
        random,
      );
      if (wrong.length == 2) {
        return _build(
          e.id,
          e.category,
          'When did this happen?',
          e.title,
          e.dateLabel,
          wrong,
          random,
          explanation: _explain(e),
        );
      }
    }
    final wrong = _distinct(
      [
        for (final o in _events)
          if (o.id != e.id && (o.year - e.year).abs() <= gap * 4) o.title,
      ],
      e.title,
      2,
      random,
    );
    if (wrong.length < 2) return null;
    return _build(
      e.id,
      e.category,
      'What happened on ${e.dateLabel}?',
      // The countries as a hint; the place often names the event.
      e.countries.take(3).join(', '),
      e.title,
      wrong,
      random,
      explanation: _explain(e),
    );
  }

  static String _explain(HistoryEvent e) => [
    '${e.dateLabel}${e.place.isEmpty ? '' : ', ${e.place}'}.',
    e.summary,
    if (e.reason.isNotEmpty) 'Why: ${e.reason}',
  ].join(' ');

  Quiz? _forQuote(Quote q, Random random) {
    final right = q.speaker ?? q.author;
    final wrong = _distinct(
      _namesByCategory[q.category] ?? const [],
      right,
      3,
      random,
    );
    if (wrong.length < 2) return null;
    return _build(
      q.id,
      q.category,
      'Who said this?',
      '"${q.text}"',
      right,
      wrong,
      random,
    );
  }

  Quiz? _forStory(Story s, Random random) {
    if (s.kind == StoryKind.history && random.nextBool()) {
      final when = _forDate(s, random);
      if (when != null) return when;
    }
    final question = switch (s.kind) {
      StoryKind.study => 'What did this study show?',
      StoryKind.history => 'What does this episode teach?',
      StoryKind.story => 'What is the lesson of this story?',
    };
    final wrong = _distinct(
      _lessonsByKind[_lessonPool(s)] ?? const [],
      s.lesson,
      2,
      random,
    );
    if (wrong.length < 2) return null;
    return _build(s.id, s.category, question, s.title, s.lesson, wrong, random);
  }

  /// "When did this happen?" with dates at least a century away, so the
  /// question tests the era rather than the exact year.
  Quiz? _forDate(Story s, Random random) {
    final year = s.year;
    if (year == null || s.date.isEmpty) return null;
    final others = [
      for (final h in _history)
        if ((h.year! - year).abs() >= 100) h.date,
    ];
    final wrong = _distinct(others, s.date, 2, random);
    if (wrong.length < 2) return null;
    return _build(
      s.id,
      s.category,
      'When did this happen?',
      s.title,
      s.date,
      wrong,
      random,
    );
  }

  static List<String> _distinct(
    List<String> pool,
    String right,
    int n,
    Random random,
  ) {
    final picked = <String>{};
    for (var tries = 0; picked.length < n && tries < n * 20; tries++) {
      if (pool.isEmpty) break;
      final c = pool[random.nextInt(pool.length)];
      if (c != right) picked.add(c);
    }
    return picked.toList();
  }

  static Quiz _build(
    String id,
    String category,
    String question,
    String subject,
    String right,
    List<String> wrong,
    Random random, {
    String explanation = '',
  }) {
    final options = [right, ...wrong]..shuffle(random);
    return Quiz(
      explanation: explanation,
      itemId: id,
      category: category,
      question: question,
      subject: subject,
      options: options,
      answer: options.indexOf(right),
    );
  }
}
