import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/country_flags.dart';
import '../core/library_store.dart';
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
import 'detail_screen.dart';
import 'download_manager_screen.dart';
import 'hentai_section.dart';
import 'settings_screen.dart';
import 'update_screen.dart';

/// Opens a content item along with its source card's Hero [tag] so the
/// cover flies into the detail popup (and back on close).
typedef OpenContent = Future<void> Function(AnimeContent item, String tag);

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.email,
    required this.onLogout,
    required this.api,
  });
  final String email;
  final Future<void> Function() onLogout;
  final AnimeOnApi api;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _store = LibraryStore();
  final _hentaiApi = HentaiIranApi();
  late final PageController _pageController;
  final Map<String, AnimeContent> _favorites = {};
  final Map<String, AnimeContent> _hentaiFavorites = {};
  final List<AnimeContent> _history = [];
  final List<AnimeContent> _hentaiHistory = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _restore();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final values = await Future.wait([
      _store.favorites(),
      _store.hentaiFavorites(),
      _store.history(),
      _store.hentaiHistory(),
    ]);
    if (!mounted) return;
    // Strict separation by isHentai + one-time migration of legacy entries
    // that were stored in the normal keys before the split.
    List<AnimeContent> dedup(List<AnimeContent> items) {
      final seen = <String>{};
      return items.where((item) => seen.add(item.id)).toList();
    }

    final favNormal = <String, AnimeContent>{};
    final favHentai = <String, AnimeContent>{};
    for (final item
        in values[0].where((i) => !AnimeOnApi.isPromotionalContent(i))) {
      (item.isHentai ? favHentai : favNormal)[item.id] = item;
    }
    for (final item
        in values[1].where((i) => !AnimeOnApi.isPromotionalContent(i))) {
      (item.isHentai ? favHentai : favNormal)[item.id] = item;
    }
    final histNormal = dedup([
      ...values[2].where(
        (i) => !i.isHentai && !AnimeOnApi.isPromotionalContent(i),
      ),
      ...values[3].where(
        (i) => !i.isHentai && !AnimeOnApi.isPromotionalContent(i),
      ),
    ]);
    final histHentai = dedup([
      ...values[3].where(
        (i) => i.isHentai && !AnimeOnApi.isPromotionalContent(i),
      ),
      ...values[2].where(
        (i) => i.isHentai && !AnimeOnApi.isPromotionalContent(i),
      ),
    ]);
    setState(() {
      _favorites.addEntries(favNormal.entries);
      _hentaiFavorites.addEntries(favHentai.entries);
      _history.addAll(histNormal);
      _hentaiHistory.addAll(histHentai);
    });
    // Persist the cleaned-up split only when legacy mixed entries exist,
    // so the migration runs once instead of on every launch.
    final needsMigration =
        values[0].any((item) => item.isHentai) ||
        values[2].any((item) => item.isHentai);
    if (needsMigration) {
      unawaited(_store.saveFavorites(favNormal.values));
      unawaited(_store.saveHentaiFavorites(favHentai.values));
      unawaited(_store.saveHistory(histNormal));
      unawaited(_store.saveHentaiHistory(histHentai));
    }
  }

  Future<void> _open(AnimeContent item, String tag) async {
    setState(() {
      if (item.isHentai) {
        _hentaiHistory.removeWhere((old) => old.id == item.id);
        _hentaiHistory.insert(0, item);
      } else {
        _history.removeWhere((old) => old.id == item.id);
        _history.insert(0, item);
      }
    });
    unawaited(
      item.isHentai ? _store.addToHentaiHistory(item) : _store.addToHistory(item),
    );
    final ContentApi sourceApi = item.isHentai ? _hentaiApi : widget.api;
    final favoriteMap = item.isHentai ? _hentaiFavorites : _favorites;
    DetailScreen detail() => DetailScreen(
      content: item,
      api: sourceApi,
      heroTag: tag,
      isFavorite: favoriteMap.containsKey(item.id),
      onFavoriteChanged: (selected) {
        setState(() {
          if (selected) {
            favoriteMap[item.id] = item;
          } else {
            favoriteMap.remove(item.id);
          }
        });
        unawaited(
          item.isHentai
              ? _store.saveHentaiFavorites(_hentaiFavorites.values)
              : _store.saveFavorites(_favorites.values),
        );
      },
    );
    if (isDesktopWindow) {
      // Desktop: detail opens as a large modal. Outside taps must NOT
      // close it (barrierDismissible: false); the back arrow closes it.
      await showDesktopPopup<void>(context, detail());
      return;
    }
    await Navigator.push<void>(
      context,
      slideUpRoute(detail(), durationMs: 520),
    );
  }

  void _select(int value) {
    Navigator.maybePop(context);
    _goToPage(value);
  }

  void _goToPage(int value) {
    if (value == _index) return;
    setState(() => _index = value);
    if (!_pageController.hasClients) return;
    if (isDesktopWindow) {
      _pageController.jumpToPage(value);
    } else {
      _pageController.animateToPage(
        value,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _push(Widget page) {
    Navigator.maybePop(context);
    Navigator.push<void>(context, slideUpRoute(page));
  }

  void _openSearch() => _push(_SearchPage(api: widget.api, onOpen: _open));
  Future<void> _openHentai() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('hentai_age_confirmed') ?? false)) {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
              SizedBox(width: 8),
              Text('هشدار محتوای +۱۸'),
            ],
          ),
          content: const Text(
            'این بخش فقط برای افراد بالای ۱۸ سال ساخته شده است و شامل محتوای بزرگسالان می‌شود. با ورود، مسئولیت استفاده بر عهده شماست.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Color(0xFFB91C3C)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأیید می‌کنم +۱۸ هستم'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await prefs.setBool('hentai_age_confirmed', true);
    }
    if (!(prefs.getBool('hentai_vpn_warned') ?? false)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: Color(0xFFF97316)),
              SizedBox(width: 8),
              Text('اتصال VPN'),
            ],
          ),
          content: const Text(
            'برای تماشا و دانلود در بخش هنتای باید VPN روشن باشد.\n\nتوجه: VPN در انیمه‌های عادی کار نمی‌کند؛ برای انیمه‌های معمولی باید VPN خاموش باشد.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('فهمیدم'),
            ),
          ],
        ),
      );
      await prefs.setBool('hentai_vpn_warned', true);
    }
    if (mounted) {
      _push(
        HentaiSectionPage(
          api: _hentaiApi,
          onOpen: (item, tag) => _open(item, tag),
          hentaiHistory: _hentaiHistory,
          onOpenHentaiHistory: () => _openHentaiHistory(),
          onClearHentaiHistory: () async {
            await _store.clearHentaiHistory();
            if (mounted) setState(() { _hentaiHistory.clear(); });
          },
          hentaiFavorites: _hentaiFavorites.values.toList(),
          onOpenHentaiFavorites: () => _openHentaiFavorites(),
          onToggleHentaiFavorite: (item, selected) {
            setState(() {
              if (selected) {
                _hentaiFavorites[item.id] = item;
              } else {
                _hentaiFavorites.remove(item.id);
              }
            });
            unawaited(_store.saveHentaiFavorites(_hentaiFavorites.values));
          },
        ),
      );
    }
  }

  void _openHentaiHistory() => _push(
    _SavedPage(
      title: 'بازدیدشده‌های +۱۸',
      emptyText: 'هنوز عنوانی از بخش +۱۸ باز نکرده‌ای',
      emptyIcon: Icons.history_rounded,
      items: _hentaiHistory,
      onOpen: _open,
      onClear: () async {
        await _store.clearHentaiHistory();
        if (mounted) setState(() { _hentaiHistory.clear(); });
      },
    ),
  );

  void _openHentaiFavorites() => _push(
    _SavedPage(
      title: 'علاقه‌مندی‌های +۱۸',
      emptyText: 'هنوز چیزی به علاقه‌مندی‌های +۱۸ اضافه نکرده‌ای',
      emptyIcon: Icons.favorite_outline_rounded,
      items: _hentaiFavorites.values.toList(),
      onOpen: _open,
      onClear: () async {
        _hentaiFavorites.clear();
        await _store.saveHentaiFavorites([]);
        if (mounted) setState(() {});
      },
    ),
  );

  void _openHistory() => _push(
    _SavedPage(
      title: 'بازدیدشده‌ها',
      emptyText: 'هنوز عنوانی باز نکرده‌ای',
      emptyIcon: Icons.history_rounded,
      items: _history,
      onOpen: _open,
      onClear: () async {
        await _store.clearHistory();
        if (mounted) setState(() { _history.clear(); });
      },
    ),
  );

  void _openFavorites() => _push(
    _SavedPage(
      title: 'علاقه‌مندی‌ها',
      emptyText: 'هنوز چیزی به علاقه‌مندی‌ها اضافه نکرده‌ای',
      emptyIcon: Icons.favorite_outline_rounded,
      items: _favorites.values.toList(),
      onOpen: _open,
      onClear: () async {
        _favorites.clear();
        await _store.saveFavorites([]);
        if (mounted) setState(() {});
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomePage(api: widget.api, onOpen: _open),
      _CatalogPage(
        key: const ValueKey('movies'),
        api: widget.api,
        kind: ContentKind.movie,
        title: 'فیلم‌ها',
        onOpen: _open,
      ),
      _CatalogPage(
        key: const ValueKey('series'),
        api: widget.api,
        kind: ContentKind.series,
        title: 'سریال‌ها',
        onOpen: _open,
      ),
      _SavedBody(
        title: 'علاقه‌مندی‌ها',
        emptyText: 'هنوز چیزی به علاقه‌مندی‌ها اضافه نکرده‌ای',
        emptyIcon: Icons.favorite_outline_rounded,
        items: _favorites.values.toList(),
        onOpen: _open,
        heroPrefix: 'fav-',
      ),
    ];
    return Scaffold(
      extendBody: true,
      drawer: _MenuDrawer(
        email: widget.email,
        selected: _index,
        select: _select,
        search: _openSearch,
        history: _openHistory,
        downloads: () => _push(const DownloadManagerScreen()),
        settings: () => _push(const SettingsScreen()),
        updates: () => _push(const UpdateScreen()),
        genres: () =>
            _push(_GroupsPage(api: widget.api, country: false, onOpen: _open)),
        countries: () =>
            _push(_GroupsPage(api: widget.api, country: true, onOpen: _open)),
        hentai: _openHentai,
        logout: () async {
          Navigator.maybePop(context);
          await widget.onLogout();
        },
      ),
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                search: _openSearch,
                history: _openHistory,
                favorites: _openFavorites,
              ),
              if (isAndroidTv)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      for (final (index, label) in [
                        'خانه',
                        'فیلم‌ها',
                        'سریال‌ها',
                        'علاقه‌مندی‌ها',
                      ].indexed)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: ChoiceChip(
                            autofocus: index == 0,
                            label: Text(label),
                            selected: _index == index,
                            onSelected: (_) => _goToPage(index),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: isLargeScreenDevice
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                  onPageChanged: (value) {
                    if (_index != value) setState(() => _index = value);
                  },
                  children: pages,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: isLargeScreenDevice
          ? null
          : _AnimatedBottomNav(index: _index, onSelected: _goToPage),
    );
  }
}

class _AnimatedBottomNav extends StatelessWidget {
  const _AnimatedBottomNav({required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'خانه'),
    (icon: Icons.movie_rounded, label: 'فیلم‌ها'),
    (icon: Icons.video_collection_rounded, label: 'سریال‌ها'),
    (icon: Icons.favorite_rounded, label: 'علاقه‌مندی‌ها'),
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
                            ? AnimeColors.orange.withValues(alpha: .92)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: AnimeColors.orange.withValues(
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.search,
    required this.history,
    required this.favorites,
  });
  final VoidCallback search;
  final VoidCallback history;
  final VoidCallback favorites;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
    child: SizedBox(
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'منوی اصلی',
                onPressed: Scaffold.of(context).openDrawer,
                icon: const Icon(Icons.menu_rounded, size: 30),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'علاقه‌مندی‌ها',
                onPressed: favorites,
                icon: const Icon(Icons.favorite_rounded, size: 28),
              ),
              IconButton(
                tooltip: 'بازدیدشده‌ها',
                onPressed: history,
                icon: const Icon(Icons.history_rounded, size: 28),
              ),
              IconButton(
                tooltip: 'جست‌وجو',
                onPressed: search,
                icon: const Icon(Icons.search_rounded, size: 30),
              ),
            ],
          ),
          const IgnorePointer(child: BrandMark(size: 42)),
        ],
      ),
    ),
  );
}

class _MenuDrawer extends StatelessWidget {
  const _MenuDrawer({
    required this.email,
    required this.selected,
    required this.select,
    required this.search,
    required this.history,
    required this.genres,
    required this.countries,
    required this.logout,
    required this.downloads,
    required this.settings,
    required this.updates,
    required this.hentai,
  });
  final String email;
  final int selected;
  final ValueChanged<int> select;
  final VoidCallback search;
  final VoidCallback history;
  final VoidCallback genres;
  final VoidCallback countries;
  final VoidCallback logout;
  final VoidCallback downloads;
  final VoidCallback settings;
  final VoidCallback updates;
  final VoidCallback hentai;

  @override
  Widget build(BuildContext context) => Drawer(
    width: MediaQuery.sizeOf(context).width.clamp(290, 360).toDouble(),
    backgroundColor: AnimeColors.surface,
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
        children: [
          const Center(child: BrandMark(size: 82)),
          const SizedBox(height: 12),
          Text(
            email,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: AnimeColors.muted),
          ),
          const SizedBox(height: 18),
          _label('جست‌وجو و مرور'),
          _tile(Icons.manage_search_rounded, 'جست‌وجوی پیشرفته', search),
          _tile(Icons.theater_comedy_rounded, 'دسته‌بندی فیلم‌ها', genres),
          const Divider(height: 24),
          _label('کتابخانه'),
          _tile(Icons.home_rounded, 'صفحه اصلی', () => select(0), index: 0),
          _tile(Icons.history_rounded, 'بازدیدشده‌ها', history),
          _tile(Icons.movie_rounded, 'فیلم‌ها', () => select(1), index: 1),
          _tile(
            Icons.video_collection_rounded,
            'سریال‌ها',
            () => select(2),
            index: 2,
          ),
          _tile(
            Icons.favorite_rounded,
            'علاقه‌مندی‌ها',
            () => select(3),
            index: 3,
          ),
          _tile(Icons.flag_rounded, 'کشورها', countries),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF7F1D1D).withValues(alpha: .32),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: .55),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: _tile(
                Icons.explicit_rounded,
                'هنتای ایران  •  +۱۸',
                hentai,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _label('ابزارهای برنامه'),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AnimeColors.orange.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AnimeColors.orange.withValues(alpha: .22),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    _tile(
                      Icons.download_for_offline_rounded,
                      'مدیریت دانلودها',
                      downloads,
                      tool: true,
                    ),
                    _toolDivider(),
                    _tile(Icons.tune_rounded, 'تنظیمات', settings, tool: true),
                    _toolDivider(),
                    _tile(
                      Icons.system_update_alt_rounded,
                      'به‌روزرسانی برنامه',
                      updates,
                      tool: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 24),
          _tile(Icons.logout_rounded, 'خروج از حساب کاربری', logout),
        ],
      ),
    ),
  );

  Widget _label(String label) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
    child: Text(
      label,
      style: const TextStyle(
        color: AnimeColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _toolDivider() => Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: AnimeColors.orange.withValues(alpha: .14),
  );

  Widget _tile(
    IconData icon,
    String label,
    VoidCallback tap, {
    int? index,
    bool tool = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      selected: index == selected,
      selectedTileColor: AnimeColors.orange.withValues(alpha: .14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: Icon(
        icon,
        color: index == selected || tool
            ? AnimeColors.orange
            : AnimeColors.muted,
      ),
      title: Text(label),
      trailing: tool ? const Icon(Icons.chevron_left_rounded, size: 20) : null,
      onTap: tap,
    ),
  );
}

class _HomePage extends StatefulWidget {
  const _HomePage({required this.api, required this.onOpen});
  final AnimeOnApi api;
  final OpenContent onOpen;
  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  late Future<HomeCatalog> _future = widget.api.home();

  Future<void> _reload() async {
    final next = widget.api.home();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder displays the failure. Do not leak it from a tap/refresh.
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HomeCatalog>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _HomeLoadingSkeleton();
      }
      if (snapshot.hasError || snapshot.data == null) {
        return _ErrorState(retry: _reload, error: snapshot.error);
      }
      final data = snapshot.data!;
      final seenIds = <String>{};
      final featured =
          (data.featured.isEmpty
                  ? [...data.series, ...data.movies]
                  : data.featured)
              .where((item) => seenIds.add(item.id))
              .toList(growable: false);
      return RefreshIndicator(
        onRefresh: _reload,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (featured.isNotEmpty)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: 0,
                  child: _Featured(items: featured, onOpen: widget.onOpen),
                ),
              ),
            SliverToBoxAdapter(
              child: _SectionEntrance(
                index: 1,
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    const _SectionTitle('آخرین سریال‌ها'),
                    _PosterRow(
                      items: data.series,
                      onOpen: widget.onOpen,
                      heroPrefix: 'hseries-',
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionEntrance(
                index: 2,
                child: Column(
                  children: [
                    const SizedBox(height: 26),
                    const _SectionTitle('آخرین فیلم‌ها'),
                    _PosterRow(
                      items: data.movies,
                      onOpen: widget.onOpen,
                      heroPrefix: 'hmovies-',
                    ),
                  ],
                ),
              ),
            ),
            for (var index = 0; index < data.sections.length; index++)
              SliverToBoxAdapter(
                child: _SectionEntrance(
                  index: index + 3,
                  child: Column(
                    children: [
                      const SizedBox(height: 26),
                      _SectionTitle(data.sections[index].title),
                      _PosterRow(
                        items: data.sections[index].items,
                        onOpen: widget.onOpen,
                        heroPrefix: 'home-${data.sections[index].id}-',
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
          ],
        ),
      );
    },
  );
}

class _SectionEntrance extends StatefulWidget {
  const _SectionEntrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_SectionEntrance> createState() => _SectionEntranceState();
}

class _SectionEntranceState extends State<_SectionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, .055),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    if (isDesktopWindow) {
      _controller.value = 1;
      return;
    }
    _start();
  }

  Future<void> _start() async {
    await Future<void>.delayed(
      Duration(milliseconds: (widget.index * 75).clamp(0, 450).toInt()),
    );
    if (mounted) await _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: SlideTransition(position: _offset, child: widget.child),
  );
}

class _HomeLoadingSkeleton extends StatefulWidget {
  const _HomeLoadingSkeleton();

  @override
  State<_HomeLoadingSkeleton> createState() => _HomeLoadingSkeletonState();
}

class _HomeLoadingSkeletonState extends State<_HomeLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final color = Color.lerp(
        AnimeColors.surface,
        AnimeColors.surfaceHigh,
        Curves.easeInOut.transform(_controller.value),
      )!;
      // Mirror the loaded layout so the skeleton looks complete on wide
      // desktop windows: featured banner (340 + dots) and poster rows
      // (230 x 148) with enough items to fill the row width.
      final rowWidth = MediaQuery.sizeOf(context).width - 36;
      final rowCount = ((rowWidth / (148 + 12)).ceil()).clamp(4, 12).toInt();
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 100),
        children: [
          _SkeletonBox(height: 340, color: color, radius: 32),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => Container(
                width: i == 0 ? 24 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          for (var section = 0; section < 3; section++) ...[
            SizedBox(height: section == 0 ? 24 : 26),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _SkeletonBox(height: 22, width: 150, color: color),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 230,
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                itemCount: rowCount,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, _) => _SkeletonBox(
                  height: 230,
                  width: 148,
                  color: color,
                  radius: 24,
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.height,
    required this.color,
    this.width = double.infinity,
    this.radius = 12,
  });

  final double height;
  final double width;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _Featured extends StatefulWidget {
  const _Featured({required this.items, required this.onOpen});
  final List<AnimeContent> items;
  final OpenContent onOpen;
  @override
  State<_Featured> createState() => _FeaturedState();
}

class _FeaturedState extends State<_Featured> {
  late final PageController _controller;
  Timer? _autoPlayTimer;
  int _page = 0;

  int get _count => widget.items.length.clamp(0, 12);

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: .9);
    _restartAutoPlay();
  }

  @override
  void didUpdateWidget(covariant _Featured oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _count) _page = 0;
    _restartAutoPlay();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartAutoPlay() {
    _autoPlayTimer?.cancel();
    if (_count < 2 || isAndroidTv) return;
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted ||
          !_controller.hasClients ||
          !TickerMode.valuesOf(context).enabled ||
          ModalRoute.of(context)?.isCurrent == false ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _goTo((_page + 1) % _count, restartTimer: false);
    });
  }

  void _goTo(int target, {bool restartTimer = true}) {
    if (_count < 2 || !_controller.hasClients) return;
    final normalized = (target + _count) % _count;
    _controller.animateToPage(
      normalized,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubicEmphasized,
    );
    if (restartTimer) _restartAutoPlay();
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Column(
      children: [
        SizedBox(
          height: isAndroidTv ? 250 : 340,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                  overscroll: false,
                ),
                child: Listener(
                  onPointerDown: (_) => _restartAutoPlay(),
                  child: PageView.builder(
                    controller: _controller,
                    physics: const BouncingScrollPhysics(),
                    padEnds: true,
                    itemCount: count,
                    onPageChanged: (value) {
                      setState(() => _page = value);
                      _restartAutoPlay();
                    },
                    itemBuilder: (_, index) => AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final current =
                            _controller.hasClients &&
                                _controller.position.hasContentDimensions
                            ? (_controller.page ?? _page.toDouble())
                            : _page.toDouble();
                        final distance = (current - index).abs().clamp(
                          0.0,
                          1.0,
                        );
                        return Opacity(
                          opacity: 1 - (distance * .28),
                          child: Transform.scale(
                            scale: 1 - (distance * .055),
                            child: child,
                          ),
                        );
                      },
                      child: _FeaturedCard(
                        item: widget.items[index],
                        onOpen: widget.onOpen,
                      ),
                    ),
                  ),
                ),
              ),
              if (count > 1) ...[
                Positioned(
                  left: 22,
                  child: _SliderArrow(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'اسلاید بعدی',
                    onTap: () => _goTo(_page + 1),
                  ),
                ),
                Positioned(
                  right: 22,
                  child: _SliderArrow(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'اسلاید قبلی',
                    onTap: () => _goTo(_page - 1),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            count,
            (i) => InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _goTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                width: i == _page ? 24 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _page ? AnimeColors.orange : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: i == _page
                      ? [
                          BoxShadow(
                            color: AnimeColors.orange.withValues(alpha: .45),
                            blurRadius: 9,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item, required this.onOpen});
  final AnimeContent item;
  final OpenContent onOpen;

  @override
  Widget build(BuildContext context) {
    final tag = 'featured-${item.id}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Pressable(
        onTap: () => onOpen(item, tag),
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
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          [
                            '${item.year}',
                            item.kindLabel,
                            if (item.rating > 0) 'IMDB: ${item.ratingLabel}',
                          ].join(' · '),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    iconSize: 34,
                    onPressed: () => onOpen(item, tag),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderArrow extends StatelessWidget {
  const _SliderArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .56),
    shape: const CircleBorder(),
    elevation: 8,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 34),
    ),
  );
}

class _CatalogPage extends StatefulWidget {
  const _CatalogPage({
    super.key,
    required this.api,
    required this.kind,
    required this.title,
    required this.onOpen,
  });
  final AnimeOnApi api;
  final ContentKind kind;
  final String title;
  final OpenContent onOpen;
  @override
  State<_CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<_CatalogPage> {
  final items = <AnimeContent>[];
  final scroll = ScrollController();
  int page = 0;
  bool loading = false;
  bool more = true;
  String? error;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 450) _load();
    });
    _load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (loading || (!more && !reset)) return;
    if (reset) {
      page = 0;
      more = true;
      items.clear();
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.api.catalog(kind: widget.kind, page: page + 1);
      if (!mounted) return;
      setState(() {
        page++;
        items.addAll(next.where((e) => !items.any((old) => old.id == e.id)));
        more = next.isNotEmpty;
      });
    } on AnimeOnApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => _load(reset: true),
    child: CustomScrollView(
      controller: scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: _PageTitle(widget.title)),
        if (items.isEmpty && loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty && error != null)
          SliverFillRemaining(child: _ErrorState(retry: _load))
        else
          _ContentGrid(
            items: items,
            onOpen: widget.onOpen,
            heroPrefix: widget.kind == ContentKind.movie
                ? 'movies-'
                : 'series-',
          ),
        if (items.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, bottomListGap),
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : error != null
                    ? TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('تلاش دوباره'),
                      )
                    : !more
                    ? const Text(
                        'همه عنوان‌ها نمایش داده شد',
                        style: TextStyle(color: AnimeColors.muted),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    ),
  );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.api, required this.onOpen});
  final AnimeOnApi api;
  final OpenContent onOpen;
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final controller = TextEditingController();
  Timer? debounce;
  ContentKind? kind;
  List<AnimeContent> results = [];
  bool loading = false;
  String? error;

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void changed(String value) {
    debounce?.cancel();
    setState(() {
      error = null;
      if (value.trim().length < 2) results = [];
    });
    if (value.trim().length >= 2) {
      debounce = Timer(const Duration(milliseconds: 420), search);
    }
  }

  Future<void> search() async {
    final query = controller.text.trim();
    if (query.length < 2) return;
    setState(() => loading = true);
    try {
      final found = await widget.api.search(query);
      if (mounted && query == controller.text.trim()) {
        setState(() => results = found);
      }
    } on AnimeOnApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = kind == null
        ? results
        : results.where((item) => item.kind == kind).toList();
    return _InnerScaffold(
      title: 'جست‌وجوی پیشرفته',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: SearchBar(
              controller: controller,
              autoFocus: true,
              hintText: 'نام فیلم یا سریال را بنویس…',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (controller.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      controller.clear();
                      setState(() => results = []);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: changed,
              onSubmitted: (_) => search(),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              children: [
                ChoiceChip(
                  label: const Text('همه'),
                  selected: kind == null,
                  onSelected: (_) => setState(() => kind = null),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('فیلم‌ها'),
                  selected: kind == ContentKind.movie,
                  onSelected: (_) => setState(() => kind = ContentKind.movie),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('سریال‌ها'),
                  selected: kind == ContentKind.series,
                  onSelected: (_) => setState(() => kind = ContentKind.series),
                ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: const TextStyle(color: AnimeColors.coral),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    icon: controller.text.length < 2
                        ? Icons.manage_search_rounded
                        : Icons.search_off_rounded,
                    message: controller.text.length < 2
                        ? 'حداقل دو حرف وارد کن'
                        : 'نتیجه‌ای پیدا نشد',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: _grid(context),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final tag = 'search-${filtered[i].id}';
                      return Pressable(
                        onTap: () => widget.onOpen(filtered[i], tag),
                        child: Hero(
                          tag: tag,
                          transitionOnUserGestures: true,
                          createRectTween: smoothHeroRectTween,
                          flightShuttleBuilder: portraitHeroFlightShuttle,
                          child: ContentArt(content: filtered[i]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Distinct accent per card so genres are visually distinguishable.
const _groupAccents = <Color>[
  Color(0xFFFF7A1A),
  Color(0xFF8D6BFF),
  Color(0xFF3FD8D4),
  Color(0xFFFF4F6D),
  Color(0xFF4ADE80),
  Color(0xFFFBBF24),
  Color(0xFFF472B6),
  Color(0xFF60A5FA),
  Color(0xFF2DD4BF),
  Color(0xFFF87171),
  Color(0xFFA3E635),
  Color(0xFFE879F9),
];

class _GroupsPage extends StatefulWidget {
  const _GroupsPage({
    required this.api,
    required this.country,
    required this.onOpen,
  });
  final AnimeOnApi api;
  final bool country;
  final OpenContent onOpen;
  @override
  State<_GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<_GroupsPage> {
  late Future<List<CatalogGroup>> future = widget.country
      ? widget.api.countriesWithContent()
      : widget.api.genres();

  Future<void> _reload() async {
    final next = widget.country
        ? widget.api.countriesWithContent()
        : widget.api.genres();
    setState(() {
      future = next;
    });
    try {
      await next;
    } catch (_) {
      // The original future remains available to FutureBuilder's error UI.
    }
  }

  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: widget.country ? 'کشورها' : 'دسته‌بندی فیلم‌ها',
    child: FutureBuilder<List<CatalogGroup>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (widget.country) ...[
                  const SizedBox(height: 16),
                  const Text('در حال بررسی کشورهای دارای محتوا…'),
                ],
              ],
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(retry: _reload, error: snapshot.error);
        }
        final groups = snapshot.data!;
        if (groups.isEmpty) {
          return const _EmptyState(
            icon: Icons.flag_outlined,
            message: 'در حال حاضر کشوری با محتوای قابل نمایش نیست',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
            childAspectRatio: widget.country ? .92 : 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: groups.length,
          itemBuilder: (_, i) {
            final group = groups[i];
            final accent = _groupAccents[i % _groupAccents.length];
            return Pressable(
              onTap: () => Navigator.push<void>(
                context,
                slideUpRoute(
                  _GroupResultsPage(
                    api: widget.api,
                    group: group,
                    country: widget.country,
                    onOpen: widget.onOpen,
                  ),
                ),
              ),
              child: widget.country
                  ? _CountryCard(group: group)
                  : _GenreCard(group: group, accent: accent),
            );
          },
        );
      },
    ),
  );
}

class _GenreCard extends StatelessWidget {
  const _GenreCard({required this.group, required this.accent});
  final CatalogGroup group;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [accent.withValues(alpha: .26), AnimeColors.surfaceHigh],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: accent.withValues(alpha: .38)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(Icons.auto_awesome_rounded, color: accent, size: 24),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            group.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.group});
  final CatalogGroup group;

  @override
  Widget build(BuildContext context) {
    final flag = countryFlagAsset(group.name);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AnimeColors.surfaceHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(21),
              ),
              child: flag == null
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AnimeColors.surface, Color(0xFF232838)],
                        ),
                      ),
                      child: Icon(
                        Icons.public_rounded,
                        color: AnimeColors.cyan,
                        size: 44,
                      ),
                    )
                  : Image.asset(
                      flag,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AnimeColors.surface, Color(0xFF232838)],
                          ),
                        ),
                        child: Icon(
                          Icons.public_rounded,
                          color: AnimeColors.cyan,
                          size: 44,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(
              group.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupResultsPage extends StatefulWidget {
  const _GroupResultsPage({
    required this.api,
    required this.group,
    required this.country,
    required this.onOpen,
  });
  final AnimeOnApi api;
  final CatalogGroup group;
  final bool country;
  final OpenContent onOpen;
  @override
  State<_GroupResultsPage> createState() => _GroupResultsPageState();
}

class _GroupResultsPageState extends State<_GroupResultsPage> {
  late Future<List<AnimeContent>> future = widget.api.catalogByGroup(
    group: widget.group,
    country: widget.country,
  );

  Future<void> _reload() async {
    final next = widget.api.catalogByGroup(
      group: widget.group,
      country: widget.country,
    );
    setState(() {
      future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder owns presentation of loading failures.
    }
  }

  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: widget.group.name,
    child: FutureBuilder<List<AnimeContent>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(retry: _reload, error: snapshot.error);
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const _EmptyState(
            icon: Icons.movie_filter_outlined,
            message: 'عنوانی در این بخش ثبت نشده است',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: _grid(context),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final tag = 'group-${items[i].id}';
            return Pressable(
              onTap: () => widget.onOpen(items[i], tag),
              child: Hero(
                tag: tag,
                transitionOnUserGestures: true,
                createRectTween: smoothHeroRectTween,
                flightShuttleBuilder: portraitHeroFlightShuttle,
                child: ContentArt(content: items[i]),
              ),
            );
          },
        );
      },
    ),
  );
}

class _SavedPage extends StatelessWidget {
  const _SavedPage({
    required this.title,
    required this.emptyText,
    required this.emptyIcon,
    required this.items,
    required this.onOpen,
    required this.onClear,
  });
  final String title;
  final String emptyText;
  final IconData emptyIcon;
  final List<AnimeContent> items;
  final OpenContent onOpen;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) => _InnerScaffold(
    title: title,
    actions: [
      if (items.isNotEmpty)
        IconButton(
          tooltip: 'پاک کردن تاریخچه',
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('پاک کردن تاریخچه؟'),
                content: const Text('فهرست عنوان‌های بازدیدشده پاک می‌شود.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('انصراف'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('پاک شود'),
                  ),
                ],
              ),
            );
            if (yes == true) {
              await onClear();
              if (context.mounted) Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
    ],
    child: _SavedBody(
      title: '',
      emptyText: emptyText,
      emptyIcon: emptyIcon,
      items: items,
      onOpen: onOpen,
      heroPrefix: 'hist-',
    ),
  );
}

class _SavedBody extends StatelessWidget {
  const _SavedBody({
    required this.title,
    required this.emptyText,
    required this.emptyIcon,
    required this.items,
    required this.onOpen,
    required this.heroPrefix,
  });
  final String title;
  final String emptyText;
  final IconData emptyIcon;
  final List<AnimeContent> items;
  final OpenContent onOpen;
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _EmptyState(icon: emptyIcon, message: emptyText);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        if (title.isNotEmpty) SliverToBoxAdapter(child: _PageTitle(title)),
        _ContentGrid(items: items, onOpen: onOpen, heroPrefix: heroPrefix),
        SliverToBoxAdapter(child: SizedBox(height: bottomListGap)),
      ],
    );
  }
}

class _InnerScaffold extends StatelessWidget {
  const _InnerScaffold({
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: AmbientBackground(child: child),
  );
}

class _ContentGrid extends StatelessWidget {
  const _ContentGrid({
    required this.items,
    required this.onOpen,
    required this.heroPrefix,
  });
  final List<AnimeContent> items;
  final OpenContent onOpen;
  final String heroPrefix;
  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverGrid.builder(
      gridDelegate: _grid(context),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final tag = '$heroPrefix${items[i].id}';
        return Pressable(
          onTap: () => onOpen(items[i], tag),
          child: Hero(
            tag: tag,
            transitionOnUserGestures: true,
            createRectTween: smoothHeroRectTween,
            flightShuttleBuilder: portraitHeroFlightShuttle,
            child: ContentArt(content: items[i]),
          ),
        );
      },
    ),
  );
}

SliverGridDelegateWithFixedCrossAxisCount _grid(BuildContext context) =>
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
      childAspectRatio: .67,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );

class _PosterRow extends StatelessWidget {
  const _PosterRow({
    required this.items,
    required this.onOpen,
    required this.heroPrefix,
  });
  final List<AnimeContent> items;
  final OpenContent onOpen;
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
          createRectTween: smoothHeroRectTween,
          flightShuttleBuilder: portraitHeroFlightShuttle,
          child: SizedBox(width: 148, child: ContentArt(content: items[i])),
        ),
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
    child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.retry, this.error});
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

