import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/platform_ui.dart';
import '../core/theme.dart';
import '../models/anime_content.dart';
import '../services/animeon_api.dart';
import '../services/hentai_iran_api.dart';
import '../widgets/ambient_background.dart';
import '../widgets/brand_mark.dart';
import '../widgets/browsable_shelf.dart';
import '../widgets/content_art.dart';
import '../widgets/pressable.dart';

typedef HentaiOpenContent = Future<void> Function(AnimeContent item, String tag);

class HentaiSectionPage extends StatefulWidget {
  const HentaiSectionPage({
    super.key,
    required this.api,
    required this.onOpen,
    required this.hentaiHistory,
    required this.onOpenHentaiHistory,
    required this.onClearHentaiHistory,
    required this.hentaiFavorites,
    required this.onOpenHentaiFavorites,
    required this.onToggleHentaiFavorite,
  });
  final HentaiIranApi api;
  final HentaiOpenContent onOpen;
  final List<AnimeContent> hentaiHistory;
  final VoidCallback onOpenHentaiHistory;
  final Future<void> Function() onClearHentaiHistory;
  final List<AnimeContent> hentaiFavorites;
  final VoidCallback onOpenHentaiFavorites;
  final void Function(AnimeContent item, bool selected) onToggleHentaiFavorite;

  @override
  State<HentaiSectionPage> createState() => _HentaiSectionPageState();
}

class _HentaiSectionPageState extends State<HentaiSectionPage> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int value) {
    if (value == _index) return;
    setState(() => _index = value);
    if (!_pageController.hasClients) return;
    _pageController.jumpToPage(value);
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HentaiSearchPage(
          api: widget.api,
          initialQuery: '',
          onOpen: widget.onOpen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HentaiHomeTab(
        api: widget.api,
        onOpen: widget.onOpen,
        onGo: _goToPage,
      ),
      _HentaiArchiveTab(api: widget.api, onOpen: widget.onOpen),
      _HentaiTermsTab(
        api: widget.api,
        taxonomy: HentaiIranApi.taxonomyGenre,
        title: 'ژانرها',
        onOpen: widget.onOpen,
      ),
      _HentaiTermsTab(
        api: widget.api,
        taxonomy: HentaiIranApi.taxonomyStudio,
        title: 'استودیوها',
        onOpen: widget.onOpen,
      ),
      _HentaiTermsTab(
        api: widget.api,
        taxonomy: HentaiIranApi.taxonomyTag,
        title: 'برچسب‌ها',
        onOpen: widget.onOpen,
      ),
      _HentaiBlogTab(api: widget.api),
    ];
    return Scaffold(
      extendBody: true,
      drawer: _HentaiSectionDrawer(
        selected: _index,
        select: (i) {
          Navigator.pop(context);
          final ctx = context;
          Future<void>.delayed(const Duration(milliseconds: 220), () {
            if (ctx.mounted) _goToPage(i);
          });
        },
        onBack: () {
          Navigator.pop(context);
          final ctx = context;
          Future<void>.delayed(const Duration(milliseconds: 220), () {
            if (ctx.mounted) Navigator.maybePop(ctx);
          });
        },
        onHistory: widget.onOpenHentaiHistory,
        historyCount: widget.hentaiHistory.length,
        onFavorites: widget.onOpenHentaiFavorites,
        favoritesCount: widget.hentaiFavorites.length,
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'منوی هنتای',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(
                size: 42,
                gradientColors: [Color(0xFFEF4444), Color(0xFF991B1B)],
                accent: Color(0xFFEF4444),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: .5),
                  ),
                ),
                child: const Text(
                  '+۱۸',
                  style: TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        titleSpacing: 0,
        backgroundColor: const Color(0xFF450A0A),
        actions: [
          IconButton(
            tooltip: 'علاقه‌مندی‌های +۱۸',
            onPressed: widget.onOpenHentaiFavorites,
            icon: Badge(
              isLabelVisible: widget.hentaiFavorites.isNotEmpty,
              label: Text('${widget.hentaiFavorites.length}'),
              child: const Icon(Icons.favorite_rounded),
            ),
          ),
          IconButton(
            tooltip: 'بازدیدشده‌های +۱۸',
            onPressed: widget.onOpenHentaiHistory,
            icon: Badge(
              isLabelVisible: widget.hentaiHistory.isNotEmpty,
              label: Text('${widget.hentaiHistory.length}'),
              child: const Icon(Icons.history_rounded),
            ),
          ),
          IconButton(
            tooltip: 'جستجوی +۱۸',
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: pages,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: isLargeScreenDevice
          ? null
          : _HentaiBottomNav(index: _index, onSelected: _goToPage),
    );
  }
}

class _HentaiBottomNav extends StatelessWidget {
  const _HentaiBottomNav({required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'خانه'),
    (icon: Icons.video_library_rounded, label: 'انیمه‌ها'),
    (icon: Icons.category_rounded, label: 'ژانرها'),
    (icon: Icons.factory_rounded, label: 'استودیوها'),
    (icon: Icons.sell_rounded, label: 'برچسب‌ها'),
    (icon: Icons.article_rounded, label: 'وبلاگ'),
  ];

  @override
  Widget build(BuildContext context) {
    final iconsOnly = Platform.isAndroid;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF24252B),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            children: List.generate(_items.length, (itemIndex) {
              final item = _items[itemIndex];
              final selected = itemIndex == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: item.label,
                  child: InkWell(
                    onTap: () => onSelected(itemIndex),
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFEF4444).withValues(alpha: .92)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFEF4444).withValues(
                                    alpha: .28,
                                  ),
                                  blurRadius: 14,
                                ),
                              ]
                            : null,
                      ),
                      child: iconsOnly
                          ? Icon(
                              item.icon,
                              size: 22,
                              color: selected ? Colors.black : Colors.white70,
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: animation,
                                          child: child,
                                        ),
                                      ),
                                  child: selected
                                      ? Padding(
                                          key: ValueKey(itemIndex),
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          child: Icon(
                                            item.icon,
                                            size: 22,
                                            color: Colors.black,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                Flexible(
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.black
                                          : Colors.white70,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ drawer

class _HentaiSectionDrawer extends StatelessWidget {
  const _HentaiSectionDrawer({
    required this.selected,
    required this.select,
    required this.onBack,
    required this.onHistory,
    required this.historyCount,
    required this.onFavorites,
    required this.favoritesCount,
  });

  final int selected;
  final ValueChanged<int> select;
  final VoidCallback onBack;
  final VoidCallback onHistory;
  final int historyCount;
  final VoidCallback onFavorites;
  final int favoritesCount;

  static const _navItems = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'خانه'),
    (icon: Icons.video_library_rounded, label: 'انیمه‌ها'),
    (icon: Icons.category_rounded, label: 'ژانرها'),
    (icon: Icons.factory_rounded, label: 'استودیوها'),
    (icon: Icons.sell_rounded, label: 'برچسب‌ها'),
    (icon: Icons.article_rounded, label: 'وبلاگ'),
  ];

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: AnimeColors.surface,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF991B1B), Color(0xFF450A0A)],
              ),
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.explicit_rounded, color: Colors.white, size: 36),
                SizedBox(height: 8),
                Text(
                  'هنتای ایران',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'محتوای مخصوص افراد بالای ۱۸ سال',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Material(
            color: AnimeColors.orange.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(18),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: AnimeColors.orange.withValues(alpha: .35),
                ),
              ),
              leading: const Icon(
                Icons.arrow_back_rounded,
                color: AnimeColors.orange,
              ),
              title: const Text(
                'بازگشت به انیمه‌های عادی',
                style: TextStyle(
                  color: AnimeColors.orange,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                await Future<void>.delayed(const Duration(milliseconds: 220));
                onBack();
              },
            ),
          ),
          const SizedBox(height: 18),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            leading: const Icon(Icons.history_rounded),
            title: const Text('بازدیدشده‌های +۱۸'),
            trailing: historyCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$historyCount',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : null,
            onTap: () async {
              Navigator.pop(context);
              await Future<void>.delayed(const Duration(milliseconds: 220));
              onHistory();
            },
          ),
          const SizedBox(height: 6),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            leading: const Icon(Icons.favorite_rounded),
            title: const Text('علاقه‌مندی‌های +۱۸'),
            trailing: favoritesCount > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$favoritesCount',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : null,
            onTap: () async {
              Navigator.pop(context);
              await Future<void>.delayed(const Duration(milliseconds: 220));
              onFavorites();
            },
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
            child: Text(
              'منوی بخش',
              style: const TextStyle(
                color: AnimeColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var i = 0; i < _navItems.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                selected: i == selected,
                selectedTileColor: const Color(0xFFEF4444).withValues(alpha: .14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: Icon(
                  _navItems[i].icon,
                  color: i == selected
                      ? const Color(0xFFEF4444)
                      : AnimeColors.muted,
                ),
                title: Text(_navItems[i].label),
                onTap: () => select(i),
              ),
            ),
          ],
          const Divider(height: 28),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'پخش و دانلود با همان پلیر و دانلودر برنامه انجام می‌شود.',
              style: TextStyle(color: AnimeColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

// -------------------------------------------------------------------- home

class _HentaiHomeTab extends StatefulWidget {
  const _HentaiHomeTab({
    required this.api,
    required this.onOpen,
    required this.onGo,
  });
  final HentaiIranApi api;
  final HentaiOpenContent onOpen;
  final ValueChanged<int> onGo;

  @override
  State<_HentaiHomeTab> createState() => _HentaiHomeTabState();
}

class _HentaiHomeTabState extends State<_HentaiHomeTab> {
  late Future<HentaiHome> _future = widget.api.home();

  Future<void> _reload() async {
    final next = widget.api.home();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  void _pushHtmlList(
    String title,
    Future<List<AnimeContent>> Function() loader,
  ) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _HentaiHtmlListPage(title: title, loader: loader, onOpen: widget.onOpen),
      ),
    );
  }

  void _pushTerm(HentaiSection section) {
    Navigator.push<void>(
      context,
      slideUpRoute(
        _HentaiTermResultsPage(
          api: widget.api,
          taxonomy: section.taxonomy,
          termId: section.termId,
          title: section.title,
          onOpen: widget.onOpen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _reload,
    child: FutureBuilder<HentaiHome>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFEF4444)),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _HentaiError(
            error: snapshot.error,
            retry: _reload,
          );
        }
        final home = snapshot.data!;
        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _ShelfHeader(
                title: 'آخرین بروزرسانی‌ها',
                onAll: () => widget.onGo(1),
              ),
            ),
            SliverToBoxAdapter(
              child: _HentaiPosterRow(
                items: home.latest,
                heroPrefix: 'hhome-latest-',
                onOpen: widget.onOpen,
              ),
            ),
            if (home.popular.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _ShelfHeader(
                  title: 'پربازدیدترین‌ها',
                  onAll: () => _pushHtmlList(
                    'پربازدیدترین‌ها',
                    () => widget.api.popular(limit: 48),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _HentaiPosterRow(
                  items: home.popular,
                  heroPrefix: 'hhome-popular-',
                  onOpen: widget.onOpen,
                ),
              ),
            ],
            if (home.newestByYear.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _ShelfHeader(
                  title: 'جدیدترین بر اساس سال انتشار',
                  onAll: () => _pushHtmlList(
                    'جدیدترین بر اساس سال انتشار',
                    () => widget.api.newestByYear(limit: 48),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _HentaiPosterRow(
                  items: home.newestByYear,
                  heroPrefix: 'hhome-year-',
                  onOpen: widget.onOpen,
                ),
              ),
            ],
            if (home.random.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _ShelfHeader(
                  title: 'پیشنهاد امروز',
                  onAll: () => _pushHtmlList(
                    'هنتای رندوم',
                    () => widget.api.randomTitles(limit: 48),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _HentaiPosterRow(
                  items: home.random,
                  heroPrefix: 'hhome-random-',
                  onOpen: widget.onOpen,
                ),
              ),
            ],
            for (final section in home.genreSections) ...[
              SliverToBoxAdapter(
                child: _ShelfHeader(
                  title: section.title,
                  onAll: () => _pushTerm(section),
                ),
              ),
              SliverToBoxAdapter(
                child: _HentaiPosterRow(
                  items: section.items,
                  heroPrefix: 'hhome-${section.id}-',
                  onOpen: widget.onOpen,
                ),
              ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
          ],
        );
      },
    ),
  );
}

class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({required this.title, required this.onAll});
  final String title;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton.icon(
          onPressed: onAll,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: const Text('مشاهده همه'),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ archive

class _HentaiArchiveTab extends StatefulWidget {
  const _HentaiArchiveTab({required this.api, required this.onOpen});
  final HentaiIranApi api;
  final HentaiOpenContent onOpen;

  @override
  State<_HentaiArchiveTab> createState() => _HentaiArchiveTabState();
}

class _HentaiArchiveTabState extends State<_HentaiArchiveTab> {
  final _items = <AnimeContent>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  HentaiFilter _filter = const HentaiFilter();
  HentaiSort _sort = HentaiSort.newest;
  int _page = 0;
  bool _loading = false;
  bool _more = true;
  String? _error;
  String _appliedSearch = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 450) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_appliedSearch != value.trim()) _load(reset: true);
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!_more && !reset)) return;
    if (reset) {
      _page = 0;
      _more = true;
      _items.clear();
      _appliedSearch = _search.text.trim();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.api.anime(
        page: _page + 1,
        search: _appliedSearch.isEmpty ? null : _appliedSearch,
        filter: _filter,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        for (final item in next) {
          if (!_items.any((old) => old.id == item.id)) _items.add(item);
        }
        _more = next.isNotEmpty;
      });
    } on AnimeOnApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_ArchiveSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HentaiFilterSheet(
        api: widget.api,
        initialFilter: _filter,
        initialSort: _sort,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _filter = result.filter;
        _sort = result.sort;
      });
      await _load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: SearchBar(
          controller: _search,
          hintText: 'جست‌وجو در آرشیو انیمه‌ها…',
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (_search.text.isNotEmpty)
              IconButton(
                tooltip: 'پاک کردن',
                onPressed: () {
                  _search.clear();
                  _load(reset: true);
                },
                icon: const Icon(Icons.close_rounded),
              ),
            IconButton(
              tooltip: 'فیلترها و مرتب‌سازی',
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: _filter.activeCount > 0,
                label: Text('${_filter.activeCount}'),
                child: const Icon(Icons.tune_rounded),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() {});
            _onSearchChanged(value);
          },
          onSubmitted: (_) => _load(reset: true),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          children: [
            _sortChip(),
            const SizedBox(width: 8),
            if (_filter.isEmpty && _appliedSearch.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'همه انیمه‌ها',
                  style: TextStyle(color: AnimeColors.muted),
                ),
              ),
            if (!_filter.isEmpty)
              ActionChip(
                label: Text('${_filter.activeCount} فیلتر فعال — پاکسازی'),
                onPressed: () {
                  setState(() => _filter = const HentaiFilter());
                  _load(reset: true);
                },
              ),
          ],
        ),
      ),
      if (_loading && _items.isEmpty)
        const Expanded(
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFEF4444)),
          ),
        )
      else if (_error != null && _items.isEmpty)
        Expanded(child: _HentaiError(error: _error, retry: () => _load(reset: true)))
      else if (_items.isEmpty)
        const Expanded(
          child: _HentaiEmpty(
            icon: Icons.video_library_outlined,
            message: 'عنوانی با این فیلتر پیدا نشد',
          ),
        )
      else
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              gridDelegate: _hentaiGrid(context),
              itemCount: _items.length + (_more || _loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= _items.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final tag = 'harchive-${_items[i].id}-$i';
                return Pressable(
                  onTap: () => widget.onOpen(_items[i], tag),
                  child: Hero(
                    tag: tag,
                    transitionOnUserGestures: true,
                    child: ContentArt(content: _items[i]),
                  ),
                );
              },
            ),
          ),
        ),
    ],
  );

  Widget _sortChip() => PopupMenuButton<HentaiSort>(
    initialValue: _sort,
    onSelected: (value) {
      setState(() => _sort = value);
      _load(reset: true);
    },
    itemBuilder: (_) => [
      for (final sort in HentaiSort.values)
        PopupMenuItem(value: sort, child: Text(sort.label)),
    ],
    child: Chip(
      label: Text('مرتب‌سازی: ${_sort.label}'),
      avatar: const Icon(Icons.sort_rounded, size: 18),
    ),
  );
}

class _ArchiveSelection {
  const _ArchiveSelection({required this.filter, required this.sort});
  final HentaiFilter filter;
  final HentaiSort sort;
}

class _HentaiFilterSheet extends StatefulWidget {
  const _HentaiFilterSheet({
    required this.api,
    required this.initialFilter,
    required this.initialSort,
  });
  final HentaiIranApi api;
  final HentaiFilter initialFilter;
  final HentaiSort initialSort;

  @override
  State<_HentaiFilterSheet> createState() => _HentaiFilterSheetState();
}

class _HentaiFilterSheetState extends State<_HentaiFilterSheet> {
  late HentaiFilter _filter = widget.initialFilter;
  late HentaiSort _sort = widget.initialSort;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .86,
    builder: (_, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'فیلتر آرشیو (مثل سایت)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => setState(
                () => _filter = const HentaiFilter(),
              ),
              child: const Text('پاکسازی همه'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'مرتب‌سازی',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final sort in HentaiSort.values)
              ChoiceChip(
                label: Text(sort.label),
                selected: _sort == sort,
                onSelected: (_) => setState(() => _sort = sort),
              ),
          ],
        ),
        _termSelector(
          title: 'ژانرها',
          taxonomy: HentaiIranApi.taxonomyGenre,
          selectedId: _filter.genreId,
          onSelected: (id) => setState(
            () => _filter = HentaiFilter(
              genreId: id,
              tagId: _filter.tagId,
              studioId: _filter.studioId,
              statusId: _filter.statusId,
              censorId: _filter.censorId,
              yearId: _filter.yearId,
              subtitleId: _filter.subtitleId,
            ),
          ),
        ),
        _termSelector(
          title: 'استودیو',
          taxonomy: HentaiIranApi.taxonomyStudio,
          selectedId: _filter.studioId,
          onSelected: (id) => setState(
            () => _filter = HentaiFilter(
              genreId: _filter.genreId,
              tagId: _filter.tagId,
              studioId: id,
              statusId: _filter.statusId,
              censorId: _filter.censorId,
              yearId: _filter.yearId,
              subtitleId: _filter.subtitleId,
            ),
          ),
        ),
        _termSelector(
          title: 'وضعیت',
          taxonomy: HentaiIranApi.taxonomyStatus,
          selectedId: _filter.statusId,
          onSelected: (id) => setState(
            () => _filter = HentaiFilter(
              genreId: _filter.genreId,
              tagId: _filter.tagId,
              studioId: _filter.studioId,
              statusId: id,
              censorId: _filter.censorId,
              yearId: _filter.yearId,
              subtitleId: _filter.subtitleId,
            ),
          ),
        ),
        _termSelector(
          title: 'سانسور',
          taxonomy: HentaiIranApi.taxonomyCensor,
          selectedId: _filter.censorId,
          onSelected: (id) => setState(
            () => _filter = HentaiFilter(
              genreId: _filter.genreId,
              tagId: _filter.tagId,
              studioId: _filter.studioId,
              statusId: _filter.statusId,
              censorId: id,
              yearId: _filter.yearId,
              subtitleId: _filter.subtitleId,
            ),
          ),
        ),
        _termSelector(
          title: 'سال ساخت',
          taxonomy: HentaiIranApi.taxonomyYear,
          selectedId: _filter.yearId,
          onSelected: (id) => setState(
            () => _filter = HentaiFilter(
              genreId: _filter.genreId,
              tagId: _filter.tagId,
              studioId: _filter.studioId,
              statusId: _filter.statusId,
              censorId: _filter.censorId,
              yearId: id,
              subtitleId: _filter.subtitleId,
            ),
          ),
        ),
        _termSelector(
          title: 'برچسب‌ها',
          taxonomy: HentaiIranApi.taxonomyTag,
          selectedId: _filter.tagId,
          onSelected: (id) => setState(
            () => _filter = HentaiFilter(
              genreId: _filter.genreId,
              tagId: id,
              studioId: _filter.studioId,
              statusId: _filter.statusId,
              censorId: _filter.censorId,
              yearId: _filter.yearId,
              subtitleId: _filter.subtitleId,
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ArchiveSelection(filter: _filter, sort: _sort),
          ),
          child: const Text('اعمال فیلترها'),
        ),
      ],
    ),
  );

  Widget _termSelector({
    required String title,
    required String taxonomy,
    required String? selectedId,
    required ValueChanged<String?> onSelected,
  }) =>
      ExpansionTile(
        title: Text(title),
        children: [
          FutureBuilder<List<HentaiTerm>>(
            future: widget.api.terms(taxonomy),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final terms = snapshot.data ?? const <HentaiTerm>[];
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('همه'),
                    selected: selectedId == null,
                    onSelected: (_) => onSelected(null),
                  ),
                  for (final term in terms.take(60))
                    ChoiceChip(
                      label: Text('${term.name} (${term.count})'),
                      selected: selectedId == term.id,
                      onSelected: (_) => onSelected(term.id),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      );
}

// ------------------------------------------------------------- term grids

class _HentaiTermsTab extends StatefulWidget {
  const _HentaiTermsTab({
    required this.api,
    required this.taxonomy,
    required this.title,
    required this.onOpen,
  });
  final HentaiIranApi api;
  final String taxonomy;
  final String title;
  final HentaiOpenContent onOpen;

  @override
  State<_HentaiTermsTab> createState() => _HentaiTermsTabState();
}

class _HentaiTermsTabState extends State<_HentaiTermsTab> {
  late Future<List<HentaiTerm>> _future = widget.api.terms(widget.taxonomy);
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = widget.api.terms(widget.taxonomy);
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'جست‌وجو در ${widget.title}…',
            filled: true,
            fillColor: const Color(0xFF7F1D1D).withValues(alpha: .18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<HentaiTerm>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFEF4444)),
                );
              }
              if (snapshot.hasError) {
                return _HentaiError(
                  error: snapshot.error,
                  retry: _reload,
                );
              }
              final terms =
                  (snapshot.data ?? const <HentaiTerm>[]).where((t) {
                    if (_query.isEmpty) return true;
                    return t.name.contains(_query);
                  }).toList();
              if (terms.isEmpty) {
                return const _HentaiEmpty(
                  icon: Icons.category_outlined,
                  message: 'موردی پیدا نشد',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 600
                      ? 4
                      : 2,
                  childAspectRatio: 1.55,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: terms.length,
                itemBuilder: (_, i) {
                  final term = terms[i];
                  final accent =
                      _termAccents[i % _termAccents.length];
                  return Pressable(
                    onTap: () => Navigator.push<void>(
                      context,
                      slideUpRoute(
                        _HentaiTermResultsPage(
                          api: widget.api,
                          taxonomy: widget.taxonomy,
                          termId: term.id,
                          title: term.name,
                          onOpen: widget.onOpen,
                        ),
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            accent.withValues(alpha: .26),
                            AnimeColors.surfaceHigh,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: accent.withValues(alpha: .38),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${term.count}',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              term.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    ],
  );
}

const _termAccents = <Color>[
  Color(0xFFFF7A1A),
  Color(0xFF8D6BFF),
  Color(0xFF3FD8D4),
  Color(0xFFFF4F6D),
  Color(0xFF4ADE80),
  Color(0xFFFBBF24),
  Color(0xFFF472B6),
  Color(0xFF60A5FA),
];

class _HentaiTermResultsPage extends StatefulWidget {
  const _HentaiTermResultsPage({
    required this.api,
    required this.taxonomy,
    required this.termId,
    required this.title,
    required this.onOpen,
  });
  final HentaiIranApi api;
  final String taxonomy;
  final String termId;
  final String title;
  final HentaiOpenContent onOpen;

  @override
  State<_HentaiTermResultsPage> createState() =>
      _HentaiTermResultsPageState();
}

class _HentaiTermResultsPageState extends State<_HentaiTermResultsPage> {
  final _items = <AnimeContent>[];
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 450) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!_more && !reset)) return;
    if (reset) {
      _page = 0;
      _more = true;
      _items.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.api.byTerm(
        widget.taxonomy,
        widget.termId,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        for (final item in next) {
          if (!_items.any((old) => old.id == item.id)) _items.add(item);
        }
        _more = next.isNotEmpty;
      });
    } on AnimeOnApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: AmbientBackground(
      child: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _error != null
          ? _HentaiError(error: _error, retry: () => _load(reset: true))
          : _items.isEmpty
          ? const _HentaiEmpty(
              icon: Icons.video_library_outlined,
              message: 'عنوانی در این بخش ثبت نشده است',
            )
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                gridDelegate: _hentaiGrid(context),
                itemCount: _items.length + (_more ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _items.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tag = 'hterm-${widget.termId}-${_items[i].id}';
                  return Pressable(
                    onTap: () => widget.onOpen(_items[i], tag),
                    child: Hero(
                      tag: tag,
                      transitionOnUserGestures: true,
                      child: ContentArt(content: _items[i]),
                    ),
                  );
                },
              ),
            ),
    ),
  );
}

// ------------------------------------------------------------ html shelves

class _HentaiHtmlListPage extends StatefulWidget {
  const _HentaiHtmlListPage({
    required this.title,
    required this.loader,
    required this.onOpen,
  });
  final String title;
  final Future<List<AnimeContent>> Function() loader;
  final HentaiOpenContent onOpen;

  @override
  State<_HentaiHtmlListPage> createState() => _HentaiHtmlListPageState();
}

class _HentaiHtmlListPageState extends State<_HentaiHtmlListPage> {
  late Future<List<AnimeContent>> _future = widget.loader();

  Future<void> _reload() async {
    final next = widget.loader();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: AmbientBackground(
      child: FutureBuilder<List<AnimeContent>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _HentaiError(error: snapshot.error, retry: _reload);
          }
          final items = snapshot.data ?? const <AnimeContent>[];
          if (items.isEmpty) {
            return const _HentaiEmpty(
              icon: Icons.video_library_outlined,
              message: 'عنوانی پیدا نشد',
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: _hentaiGrid(context),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final tag = 'hhtml-${items[i].id}-$i';
                return Pressable(
                  onTap: () => widget.onOpen(items[i], tag),
                  child: Hero(
                    tag: tag,
                    transitionOnUserGestures: true,
                    child: ContentArt(content: items[i]),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
}

// ------------------------------------------------------------------ search

class HentaiSearchPage extends StatefulWidget {
  const HentaiSearchPage({
    super.key,
    required this.api,
    required this.initialQuery,
    required this.onOpen,
  });
  final HentaiIranApi api;
  final String initialQuery;
  final HentaiOpenContent onOpen;

  @override
  State<HentaiSearchPage> createState() => HentaiSearchPageState();
}

class HentaiSearchPageState extends State<HentaiSearchPage> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<AnimeContent> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.trim().length >= 2) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.api.latest(search: query);
      if (mounted) setState(() => _results = found);
    } on AnimeOnApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('جست‌وجو در هنتای ایران')),
    body: AmbientBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SearchBar(
              controller: _controller,
              autoFocus: widget.initialQuery.trim().isEmpty,
              hintText: 'نام انیمه را بنویس… (حداقل ۲ حرف)',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _controller.clear();
                      setState(() => _results = []);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: (v) {
                setState(() {});
                _changed(v);
              },
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: AnimeColors.coral),
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? _HentaiEmpty(
                    icon: _controller.text.trim().length < 2
                        ? Icons.manage_search_rounded
                        : Icons.search_off_rounded,
                    message: _controller.text.trim().length < 2
                        ? 'حداقل دو حرف وارد کن'
                        : 'نتیجه‌ای پیدا نشد',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: _hentaiGrid(context),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final tag = 'hsearch-${_results[i].id}';
                      return Pressable(
                        onTap: () => widget.onOpen(_results[i], tag),
                        child: Hero(
                          tag: tag,
                          transitionOnUserGestures: true,
                          child: ContentArt(content: _results[i]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

// -------------------------------------------------------------------- blog

class _HentaiBlogTab extends StatefulWidget {
  const _HentaiBlogTab({required this.api});
  final HentaiIranApi api;

  @override
  State<_HentaiBlogTab> createState() => _HentaiBlogTabState();
}

class _HentaiBlogTabState extends State<_HentaiBlogTab> {
  final _items = <HentaiPost>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  int _page = 0;
  bool _loading = false;
  bool _more = true;
  String? _error;
  String _applied = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 450) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!_more && !reset)) return;
    if (reset) {
      _page = 0;
      _more = true;
      _items.clear();
      _applied = _search.text.trim();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.api.posts(
        page: _page + 1,
        search: _applied.isEmpty ? null : _applied,
      );
      if (!mounted) return;
      setState(() {
        _page++;
        for (final post in next) {
          if (!_items.any((old) => old.id == post.id)) _items.add(post);
        }
        _more = next.isNotEmpty;
      });
    } on AnimeOnApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: TextField(
          controller: _search,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 500),
              () => _load(reset: true),
            );
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'جست‌وجو در وبلاگ…',
            filled: true,
            fillColor: const Color(0xFF7F1D1D).withValues(alpha: .18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      Expanded(
        child: _items.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty && _error != null
            ? _HentaiError(error: _error, retry: () => _load(reset: true))
            : _items.isEmpty
            ? const _HentaiEmpty(
                icon: Icons.article_outlined,
                message: 'نوشته‌ای پیدا نشد',
              )
            : RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: _items.length + (_more ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final post = _items[i];
                    return Pressable(
                      onTap: () => Navigator.push<void>(
                        context,
                        slideUpRoute(_HentaiPostPage(post: post)),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AnimeColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            if (post.imageUrl != null)
                              ClipRRect(
                                borderRadius:
                                    const BorderRadiusDirectional.horizontal(
                                      start: Radius.circular(19),
                                    ),
                                child: Image.network(
                                  post.imageUrl!,
                                  width: 110,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const SizedBox(
                                    width: 110,
                                    height: 120,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      post.excerpt.isEmpty
                                          ? post.content
                                          : post.excerpt,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AnimeColors.muted,
                                        fontSize: 12,
                                        height: 1.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    ],
  );
}

class _HentaiPostPage extends StatelessWidget {
  const _HentaiPostPage({required this.post});
  final HentaiPost post;

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(post.link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('وبلاگ هنتای ایران'),
      actions: [
        IconButton(
          tooltip: 'مشاهده در سایت',
          onPressed: _openExternal,
          icon: const Icon(Icons.open_in_new_rounded),
        ),
      ],
    ),
    body: AmbientBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(
            post.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (post.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            post.content.isEmpty ? post.excerpt : post.content,
            style: const TextStyle(height: 2),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ shared

SliverGridDelegateWithFixedCrossAxisCount _hentaiGrid(BuildContext context) =>
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
      childAspectRatio: .67,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );

class _HentaiFeatured extends StatefulWidget {
  const _HentaiFeatured({required this.items, required this.onOpen});
  final List<AnimeContent> items;
  final HentaiOpenContent onOpen;

  @override
  State<_HentaiFeatured> createState() => _HentaiFeaturedState();
}

class _HentaiFeaturedState extends State<_HentaiFeatured> {
  late final PageController _controller = PageController(viewportFraction: .9);
  Timer? _timer;
  int _page = 0;

  int get _count => widget.items.length.clamp(0, 12);

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (_count < 2 || isAndroidTv) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_controller.hasClients) return;
      _go((_page + 1) % _count, restart: false);
    });
  }

  void _go(int target, {bool restart = true}) {
    if (_count < 2 || !_controller.hasClients) return;
    _controller.animateToPage(
      (target + _count) % _count,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubicEmphasized,
    );
    if (restart) _restart();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: isAndroidTv ? 250 : 340,
        child: PageView.builder(
          controller: _controller,
          itemCount: _count,
          onPageChanged: (v) {
            setState(() => _page = v);
            _restart();
          },
          itemBuilder: (_, index) {
            final item = widget.items[index];
            final tag = 'hfeatured-${item.id}';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Pressable(
                onTap: () => widget.onOpen(item, tag),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ContentArt(
                      content: item,
                      imageUrl: item.backdropUrl ?? item.imageUrl,
                      orientation: ArtworkOrientation.landscape,
                      borderRadius: 32,
                      showTitle: false,
                    ),
                    Positioned(
                      right: 22,
                      left: 22,
                      bottom: 22,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                Text(
                                  [
                                    if (item.year > 0) '${item.year}',
                                    if (item.studio.isNotEmpty) item.studio,
                                    '+۱۸',
                                  ].join(' · '),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filled(
                            iconSize: 34,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFB91C3C),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => widget.onOpen(item, tag),
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          _count,
          (i) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _go(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              width: i == _page ? 24 : 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == _page
                    ? const Color(0xFFEF4444)
                    : Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _HentaiPosterRow extends StatelessWidget {
  const _HentaiPosterRow({
    required this.items,
    required this.onOpen,
    required this.heroPrefix,
  });
  final List<AnimeContent> items;
  final HentaiOpenContent onOpen;
  final String heroPrefix;

  @override
  Widget build(BuildContext context) => BrowsableShelf(
    showNavigation: isLargeScreenDevice,
    itemCount: items.length,
    itemBuilder: (_, i) {
      final tag = '$heroPrefix${items[i].id}';
      return Pressable(
        onTap: () => onOpen(items[i], tag),
        child: Hero(
          tag: tag,
          transitionOnUserGestures: true,
          child: SizedBox(width: 148, child: ContentArt(content: items[i])),
        ),
      );
    },
  );
}

class _HentaiError extends StatelessWidget {
  const _HentaiError({required this.retry, this.error});
  final FutureOr<void> Function() retry;
  final Object? error;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 56, color: AnimeColors.muted),
        const SizedBox(height: 12),
        const Text('دریافت اطلاعات انجام نشد'),
        if (error is AnimeOnApiException)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              (error! as AnimeOnApiException).message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AnimeColors.muted),
            ),
          ),
        const SizedBox(height: 10),
        FilledButton.tonal(onPressed: retry, child: const Text('تلاش دوباره')),
      ],
    ),
  );
}

class _HentaiEmpty extends StatelessWidget {
  const _HentaiEmpty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 60, color: AnimeColors.muted),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: AnimeColors.muted)),
      ],
    ),
  );
}
