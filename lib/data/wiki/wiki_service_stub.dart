import 'wiki_service.dart';

/// The web build: the offline database is not kept in the browser. (The
/// hosted copy, read in place with the zx web engine, comes later:
/// docs/plan-wiki-hosting.md.)
class _Unsupported extends WikiService {
  @override
  WikiStatus get status => WikiStatus.unsupported;
  @override
  int get downloaded => 0;
  @override
  int get total => 0;
  @override
  int get received => 0;
  @override
  String? get error => null;
  @override
  Future<void> download() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> delete() async {}
  @override
  Future<List<WikiFact>> onThisDay(
    int month,
    int day, {
    int limit = 30,
  }) async => const [];
  @override
  Future<WikiArticle?> article(String title) async => null;
}

WikiService createWikiService() => _Unsupported();
