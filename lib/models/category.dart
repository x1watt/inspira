import 'package:flutter/material.dart';

class QuoteCategory {
  const QuoteCategory(this.id, this.label, this.icon, this.blurb);

  final String id;
  final String label;
  final IconData icon;
  final String blurb;

  static const all = <QuoteCategory>[
    QuoteCategory(
      'relations',
      'Relations',
      Icons.handshake_outlined,
      'Friendship, trust, kindness and how to treat people',
    ),
    QuoteCategory(
      'leadership',
      'Leadership',
      Icons.flag_outlined,
      'Command, example, duty and the use of power',
    ),
    QuoteCategory(
      'team',
      'Team',
      Icons.groups_outlined,
      'Unity, cooperation and working together',
    ),
    QuoteCategory(
      'family',
      'Family',
      Icons.family_restroom_outlined,
      'Parents, children, marriage and home',
    ),
    QuoteCategory(
      'strategy',
      'Strategy',
      Icons.route_outlined,
      'Planning, timing, foresight and conflict',
    ),
  ];

  static QuoteCategory byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.first);
}
