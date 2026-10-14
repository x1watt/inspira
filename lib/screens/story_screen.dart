import 'package:flutter/material.dart';

import '../models/category.dart';
import '../models/story.dart';
import '../widgets/story_card.dart';

class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key, required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(QuoteCategory.byId(story.category).label)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: StoryCard(story: story),
          ),
        ),
      ),
    );
  }
}
