import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../app_scope.dart';
import '../data/place_index.dart';
import '../data/wiki/tiles.dart';
import '../data/wiki/wiki_service.dart';
import '../data/wiki_place_repository.dart';
import '../models/story.dart';
import '../widgets/event_details.dart';
import '../widgets/person_sheet.dart';
import 'story_screen.dart';

/// Historical tourism: events, stories and, with the offline Wikipedia,
/// about a million places of Wikipedia (castles, churches, museums,
/// monuments, nature, towns) on a map around the user, with the closest
/// ones listed by distance. Tap one to read it and get directions.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.focus,
    this.locate = true,
    this.tiles = true,
  });

  /// Id of an event or story to center on and open.
  final String? focus;

  /// Ask for the user's position on open; false in tests.
  final bool locate;

  /// Load map tiles from the network; false in tests.
  final bool tiles;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _world = LatLng(35, 10);
  static const _streets = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Esri World Imagery, with Esri's place names and borders on top.
  static const _satellite =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _labels =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  final _map = MapController();
  Timer? _debounce;
  LatLng? _me;
  bool _locating = false;

  /// Plain street map first; the button in the app bar switches to
  /// satellite pictures for detail on the ground.
  bool _satelliteView = false;
  String? _locationError;
  List<MapPlace> _visible = const [];
  List<(MapPlace, double)> _near = const [];
  late final PlaceIndex _index = AppScope.of(context).places;
  late final WikiService? _wiki = AppScope.of(context).wiki;
  MapPlace? _focus;

  /// The category shown ([MapPlace.cat]); all when null.
  String? _only;

  /// Numbers the places file's queries, so a slow answer for a view the
  /// user already left is dropped.
  int _query = 0;

  /// From this zoom on, the markers come from the places file (at most
  /// [cellsInBox]'s 400 tiles of zoom 12); below it, from the app's own
  /// events and stories and the bundled Wikipedia events.
  static const _fileZoom = 10.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.focus != null && _focus == null) {
      for (final p in _index.places) {
        if (p.id == widget.focus) _focus = p;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _onReady() {
    _refresh();
    if (_focus case final f?) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(f));
    } else if (widget.locate) {
      _locate();
    }
  }

  /// Markers in view and the list of closest places; after the map stops
  /// moving, not on every frame of a drag.
  void _onMapEvent(MapEvent _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _refresh);
  }

  void _refresh() {
    if (!mounted) return;
    final cam = _map.camera;
    final b = cam.visibleBounds;
    final from = _me ?? cam.center;
    final file = _wiki?.placesReady ?? false;
    // One marker per 44 px square: 256 px tiles cover 360 degrees at
    // zoom 0.
    final cell = 44 * 360 / (256 * pow(2, cam.zoom));
    setState(() {
      _visible = _index.inBox(
        b.south,
        b.west,
        b.north,
        b.east,
        cell: cell,
        wiki: !file || cam.zoom < _fileZoom,
        only: _only,
      );
      _near = _index.nearest(
        from.latitude,
        from.longitude,
        wiki: !file,
        only: _only,
      );
    });
    if (file) _fromFile(b, cam.zoom, from, cell);
  }

  /// Adds the places file's places to the markers and the list, in the
  /// background (zx's worker isolate).
  Future<void> _fromFile(
    LatLngBounds b,
    double zoom,
    LatLng from,
    double cell,
  ) async {
    final wiki = _wiki!, only = _only, query = ++_query;
    // the list: the 5 by 5 tiles of zoom 12 around (about 30 km a side)
    var near = await wiki.placesIn(
      // a category is rarer: 7 by 7 tiles, about 40 km a side
      cellsAround(from.latitude, from.longitude, only == null ? 2 : 3),
      cat: only,
    );
    var inView = const <WikiPlace>[];
    final cells = zoom >= _fileZoom
        ? cellsInBox(b.south, b.west, b.north, b.east)
        : null;
    if (cells != null) {
      // a zoom 12 tile is 256 / 2^(12 - zoom) px wide: its best known
      // places, about one per 64 px square of it
      final side = 256 / pow(2, 12 - zoom) / 64;
      inView = await wiki.placesIn(
        cells,
        perCell: (side * side).ceil().clamp(1, 16),
        cat: only,
      );
    }
    if (!mounted || query != _query) return;
    // "All" leaves the towns out (the base map names them); the Towns
    // chip shows them
    bool keep(WikiPlace w) => only != null || w.cat != 'settlement';
    inView = inView.where(keep).toList();
    near = near.where(keep).toList();
    setState(() {
      if (cells != null) {
        _visible = PlaceIndex.pick(
          [..._visible, for (final w in inView) MapPlace.wiki(w)],
          b.south,
          b.west,
          b.north,
          b.east,
          cell: cell,
        );
      }
      _near = PlaceIndex.closest(
        [for (final (p, _) in _near) p, for (final w in near) MapPlace.wiki(w)],
        from.latitude,
        from.longitude,
        limit: 100,
      );
    });
  }

  void _filter(String? only) {
    _only = only;
    _refresh();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    String? error;
    LatLng? me;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        error = 'Location is turned off on this device.';
      } else {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          error = 'Allow location to see places near you.';
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 20),
            ),
          );
          me = LatLng(pos.latitude, pos.longitude);
        }
      }
    } catch (_) {
      // No location plugin (Linux), timeout or a browser refusal.
      error = 'Your location is not available here.';
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _locationError = error;
      if (me != null) _me = me;
    });
    if (me != null) _map.move(me, 11);
    _refresh();
  }

  void _open(MapPlace p) {
    _map.move(
      LatLng(p.lat, p.lon),
      _map.camera.zoom < 11 ? 11 : _map.camera.zoom,
    );
    final me = _me;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlaceSheet(
        place: p,
        wiki: _wiki,
        km: me == null
            ? null
            : PlaceIndex.km(me.latitude, me.longitude, p.lat, p.lon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _focus;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            tooltip: _satelliteView ? 'Map view' : 'Satellite view',
            icon: Icon(
              _satelliteView ? Icons.map_outlined : Icons.satellite_alt_rounded,
            ),
            onPressed: () => setState(() => _satelliteView = !_satelliteView),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: f != null ? LatLng(f.lat, f.lon) : _world,
              initialZoom: f != null ? 12 : 3,
              minZoom: 2,
              maxZoom: 18,
              onMapReady: _onReady,
              onMapEvent: _onMapEvent,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (widget.tiles)
                TileLayer(
                  key: ValueKey(_satelliteView),
                  urlTemplate: _satelliteView ? _satellite : _streets,
                  maxNativeZoom: 19,
                  userAgentPackageName: 'com.x1watt.inspira',
                ),
              if (widget.tiles && _satelliteView)
                TileLayer(
                  urlTemplate: _labels,
                  maxNativeZoom: 19,
                  userAgentPackageName: 'com.x1watt.inspira',
                ),
              MarkerLayer(
                markers: [
                  for (final p in _visible)
                    Marker(
                      point: LatLng(p.lat, p.lon),
                      width: 34,
                      height: 34,
                      child: _PlaceMarker(place: p, onTap: () => _open(p)),
                    ),
                  if (_me case final me?)
                    Marker(
                      point: me,
                      width: 22,
                      height: 22,
                      child: const _MeDot(),
                    ),
                ],
              ),
              // At the top: the list sheet covers the bottom of the map.
              SimpleAttributionWidget(
                alignment: Alignment.topLeft,
                source: Text(
                  _satelliteView
                      ? 'Esri, Maxar, Earthstar Geographics'
                      : 'OpenStreetMap contributors',
                ),
                onTap: () => openLink(
                  context,
                  _satelliteView
                      ? 'https://www.esri.com/en-us/legal/terms/full-master-agreement'
                      : 'https://www.openstreetmap.org/copyright',
                ),
              ),
            ],
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.36,
            minChildSize: 0.1,
            maxChildSize: 0.85,
            builder: (context, scroll) => _NearList(
              scroll: scroll,
              near: _near,
              only: _only,
              onFilter: _filter,
              file: _wiki?.placesReady ?? false,
              fromMe: _me != null,
              locating: _locating,
              error: _locationError,
              onLocate: _locate,
              onOpen: _open,
            ),
          ),
        ],
      ),
    );
  }
}

const _kindStyle = {
  'event': (Icons.today_rounded, Color(0xFFFFB300), 'Event'),
  'history': (Icons.account_balance_rounded, Color(0xFF42A5F5), 'History'),
  'study': (Icons.science_rounded, Color(0xFF66BB6A), 'Study'),
  'story': (Icons.auto_stories_rounded, Color(0xFFAB47BC), 'Story'),
};

/// Wikipedia places, by [WikiPlace.cat].
const _catStyle = {
  'event': (Icons.history_edu_rounded, Color(0xFFFF8A65), 'Event'),
  'castle': (Icons.castle_rounded, Color(0xFFD7CCC8), 'Castle or palace'),
  'religious': (Icons.church_rounded, Color(0xFF80CBC4), 'Church or temple'),
  'museum': (Icons.museum_rounded, Color(0xFFF48FB1), 'Museum'),
  'monument': (Icons.fort_rounded, Color(0xFFFFE082), 'Monument or site'),
  'building': (Icons.home_work_rounded, Color(0xFFB0BEC5), 'Building'),
  'nature': (Icons.landscape_rounded, Color(0xFFA5D6A7), 'Nature'),
  'settlement': (Icons.location_city_rounded, Color(0xFF90A4AE), 'Town'),
};

(IconData, Color, String) _style(MapPlace p) => p.wiki != null
    ? _catStyle[p.cat] ?? _catStyle['event']!
    : _kindStyle[p.kind]!;

/// The map's filter: label, [MapPlace.cat], and whether only the offline
/// places file has it.
const _filters = [
  ('All', null, false),
  ('Events', 'event', false),
  ('Castles', 'castle', true),
  ('Churches', 'religious', true),
  ('Museums', 'museum', true),
  ('Monuments', 'monument', true),
  ('Buildings', 'building', true),
  ('Nature', 'nature', true),
  ('Towns', 'settlement', true),
  ('Stories', 'story', false),
];

class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker({required this.place, required this.onTap});

  final MapPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _style(place);
    return Tooltip(
      message: place.title,
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: '$label: ${place.title}',
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
            ),
            child: Icon(icon, size: 17, color: Colors.black),
          ),
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.blueAccent,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
    ),
  );
}

String _distance(double km) => km < 1
    ? '${(km * 1000).round()} m'
    : km < 10
    ? '${km.toStringAsFixed(1)} km'
    : '${km.round()} km';

/// The closest places, under the map.
class _NearList extends StatelessWidget {
  const _NearList({
    required this.scroll,
    required this.near,
    required this.only,
    required this.onFilter,
    required this.file,
    required this.fromMe,
    required this.locating,
    required this.error,
    required this.onLocate,
    required this.onOpen,
  });

  final ScrollController scroll;
  final List<(MapPlace, double)> near;
  final String? only;
  final void Function(String?) onFilter;

  /// The offline places file is on the device.
  final bool file;
  final bool fromMe;
  final bool locating;
  final String? error;
  final VoidCallback onLocate;
  final void Function(MapPlace) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fromMe ? 'Near you' : 'Near the map center',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (locating)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        TextButton.icon(
                          onPressed: onLocate,
                          icon: const Icon(Icons.my_location),
                          label: const Text('My location'),
                        ),
                    ],
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final (label, cat, fileOnly) in _filters)
                        if (file || !fileOnly)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(label),
                              visualDensity: VisualDensity.compact,
                              selected: only == cat,
                              onSelected: (_) => onFilter(cat),
                            ),
                          ),
                    ],
                  ),
                ),
                if (!file)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Download the offline Wikipedia in Me for about a '
                      'million more places: castles, churches, museums, '
                      'monuments, nature and towns, each with its article.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                if (near.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nothing of this kind nearby.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: near.length,
            itemBuilder: (context, i) {
              final (p, km) = near[i];
              final (icon, color, label) = _style(p);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.black, size: 20),
                ),
                title: Text(p.title, maxLines: 2),
                subtitle: Text(
                  [label, p.subtitle].where((t) => t.isNotEmpty).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(_distance(km)),
                onTap: () => onOpen(p),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// What happened at a place, with directions.
class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet({
    required this.place,
    required this.wiki,
    required this.km,
  });

  final MapPlace place;
  final WikiService? wiki;

  /// From the user, when their position is known.
  final double? km;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  /// The article's lead from the offline Wikipedia; one query per sheet.
  late final Future<WikiArticle?>? _article = switch ((
    widget.place.wiki,
    widget.wiki,
  )) {
    (final w?, final wiki?) when wiki.articlesReady || wiki.placesReady =>
      wiki.placeArticle(w),
    _ => null,
  };

  MapPlace get place => widget.place;
  double? get km => widget.km;

  static const _body = TextStyle(
    color: Colors.white,
    fontSize: 16,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final event = place.event, story = place.story, wiki = place.wiki;
    final art = event != null
        ? scope.images.artForEvent(event)
        : story != null
        ? scope.images.artForStory(story)
        : null;
    final directions =
        'https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lon}';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (art != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                art.asset,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => openLink(context, directions),
                icon: const Icon(Icons.directions_rounded),
                label: Text(
                  km == null ? 'Directions' : 'Directions, ${_distance(km!)}',
                ),
              ),
              if (story != null)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoryScreen(story: story),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_full_rounded),
                  label: const Text('Open'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (event != null)
            EventDetails(
              event: event,
              nowYear: DateTime.now().year,
              mapLink: false,
            )
          else if (story != null)
            ..._story(context, story)
          else
            ..._wiki(context, wiki!),
        ],
      ),
    );
  }

  List<Widget> _wiki(BuildContext context, WikiPlace w) {
    final (icon, color, label) = _style(place);
    final note = TextStyle(color: Colors.white54, fontSize: 12);
    return [
      Text(
        w.title,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [label, w.yearLabel].where((t) => t.isNotEmpty).join(', '),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_article case final article?)
        FutureBuilder<WikiArticle?>(
          future: article,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final lead = snap.data?.lead.trim() ?? '';
            if (lead.isEmpty) {
              return const Text(
                'This article is not in the offline Wikipedia.',
                style: _body,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in lead.split('\n'))
                  if (p.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(p.trim(), style: _body),
                    ),
              ],
            );
          },
        )
      else
        const Text(
          'Download the offline Wikipedia in Me to read about it here.',
          style: _body,
        ),
      if (w.approximate)
        Text('The place is approximate: only the area is known.', style: note),
      const SizedBox(height: 8),
      Text(
        'Text from Wikipedia (CC BY-SA 4.0); place from Wikidata, Wikipedia '
        'and GeoNames.',
        style: note,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => openLink(context, w.url),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Whole article on wikipedia.org'),
        ),
      ),
    ];
  }

  List<Widget> _story(BuildContext context, Story s) => [
    Text(
      s.title,
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 4),
    Text(
      [s.date, s.place].where((t) => t.isNotEmpty).join(', '),
      style: const TextStyle(color: Colors.white70, fontSize: 13),
    ),
    const SizedBox(height: 12),
    for (final p in s.text.split('\n\n')) ...[
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
            s.lesson,
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
  ];
}
