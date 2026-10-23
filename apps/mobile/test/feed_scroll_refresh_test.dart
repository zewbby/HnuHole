import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import 'package:hnuhole_mobile/src/design_system/telegram_theme.dart';
import 'package:hnuhole_mobile/src/navigation/app_navigation.dart';
import 'package:hnuhole_mobile/src/navigation/feed_chrome.dart';
import 'package:hnuhole_mobile/src/navigation/primary_tabs.dart';
import 'package:hnuhole_mobile/src/posts/feed_refresh.dart';

import 'feed_ui_test.dart' as feed;

const _listKey = ValueKey('production-feed');
const _headerKey = ValueKey('feed-header-visibility');
const _boundary = ValueKey('scroll-refresh-render');

Widget _screen(
  feed.FeedFixture f, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool reduceMotion = false,
  GlobalKey<PrimaryTabsState>? tabsKey,
  (String?, int) window = ('test-account', 1),
  double keyboardHeight = 0,
}) => MaterialApp(
  theme: HhTelegramTheme.create(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: EdgeInsets.only(top: 24, bottom: keyboardHeight > 0 ? 0 : 24),
      viewInsets: EdgeInsets.only(bottom: keyboardHeight),
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduceMotion,
    ),
    child: child!,
  ),
  home: RepaintBoundary(
    key: _boundary,
    child: PrimaryTabs(
      key: tabsKey,
      window: window,
      onSelected: (destination) => tabsKey?.currentState?.select(destination),
      builders: {
        AppDestination.home: (_) => FeedScreen(
          showNavigation: false,
          controller: f.controller,
          channels: feed.channels,
          composeChannel: feed.channels.first,
          onManageIdentities: () async {},
          onAuthenticationRequired: () {},
        ),
        for (final destination in AppDestination.values.skip(1))
          destination: (_) => Scaffold(
            body: SafeArea(
              top: false,
              child: ColoredBox(
                key: ValueKey('tab-safe:${destination.name}'),
                color: Colors.grey,
                child: Center(child: Text('tab:${destination.name}')),
              ),
            ),
          ),
      },
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

ScrollController _scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byKey(_listKey)).controller!;

void _longFeed(feed.FeedFixture f) {
  f.api.items = [
    feed.post(),
    for (var i = 1; i < 30; i++)
      feed.post(id: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
  ];
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/feed-scroll-refresh-render');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  test(
    'reading intent ignores jitter, reveals sooner, and locks during refresh',
    () {
      final c = FeedChromeController();
      addTearDown(c.dispose);
      c.scroll(20, 20);
      c.scroll(15, 35);
      expect(c.visible, isTrue);
      c.scroll(2, 37);
      expect(c.visible, isFalse);
      c.beginDrag();
      c.scroll(-5, 32);
      expect(c.visible, isFalse);
      c.scroll(-10, 22);
      expect(c.visible, isTrue);
      c.refreshing(true);
      c.scroll(100, 200);
      expect(c.visible, isTrue);
      c.refreshing(false);
      c.scroll(50, 250);
      expect(c.visible, isFalse);
      c.scroll(0, 0);
      expect(c.visible, isTrue);
    },
  );

  testWidgets(
    'real drags hide both bars, reverse restores in place, one compose',
    (tester) async {
      await _phone(tester);
      final f = await feed.FeedFixture.create();
      addTearDown(f.dispose);
      _longFeed(f);
      final tabs = GlobalKey<PrimaryTabsState>();
      await tester.pumpWidget(_screen(f, tabsKey: tabs));
      await tester.pumpAndSettle();
      final original = tester.state(find.byType(FeedScreen));
      final originalViewport = tester.getSize(find.byKey(_listKey));
      final headerHeight = tester.getSize(find.byKey(_headerKey)).height;
      expect(headerHeight, greaterThan(100));
      expect(find.byType(HhAppNavigation), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-compose')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('feed-compose'))).dx,
        195,
      );
      await tester.drag(find.byKey(_listKey), const Offset(0, -300));
      await tester.pumpAndSettle();
      final readingOffset = _scroll(tester).offset;
      expect(readingOffset, greaterThan(100));
      expect(tester.getSize(find.byKey(_headerKey)).height, 0);
      expect(
        tester.getSize(find.byKey(_listKey)).height,
        greaterThan(originalViewport.height),
      );
      expect(
        find.byKey(const ValueKey('destination:home')).hitTestable(),
        findsNothing,
      );
      final compose = find.byKey(const ValueKey('feed-compose'));
      expect(compose, findsOneWidget);
      expect(tester.getCenter(compose).dx, greaterThan(300));
      expect(
        tester.getBottomRight(compose).dy,
        lessThanOrEqualTo(844 - 24 - 16),
      );
      // An inertial update or programmatic change away from the top does not
      // reveal the bars; a deliberate reverse drag does, before reaching top.
      _scroll(tester).jumpTo(readingOffset + 40);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_headerKey)).height, 0);
      await tester.drag(find.byKey(_listKey), const Offset(0, 70));
      await tester.pumpAndSettle();
      expect(_scroll(tester).offset, greaterThan(0));
      expect(tester.getSize(find.byKey(_headerKey)).height, headerHeight);
      expect(
        find.byKey(const ValueKey('destination:home')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getCenter(compose).dx, 195);
      final retainedOffset = _scroll(tester).offset;
      await tester.tap(find.byKey(const ValueKey('destination:personal')));
      await tester.pumpAndSettle();
      expect(find.text('tab:personal'), findsOneWidget);
      expect(find.byType(HhAppNavigation, skipOffstage: false), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('destination:home')));
      await tester.pumpAndSettle();
      expect(
        identical(tester.state(find.byType(FeedScreen)), original),
        isTrue,
      );
      expect(_scroll(tester).offset, retainedOffset);
      expect(
        f.api.calls.where((call) => call.startsWith('feed:')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'short pull cancels; horizontal gestures never hide chrome or refresh',
    (tester) async {
      await _phone(tester);
      final f = await feed.FeedFixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(_screen(f));
      await tester.pumpAndSettle();
      final baseline = tester.getSize(find.byKey(_headerKey)).height;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_listKey)),
      );
      await gesture.moveBy(const Offset(0, 35));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(_headerKey)).height,
        greaterThan(baseline),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_headerKey)).height, baseline);
      await tester.drag(find.byKey(_listKey), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_headerKey)).height, baseline);
      expect(
        f.api.calls.where((call) => call.startsWith('feed:')),
        hasLength(1),
      );
      expect(
        find.byKey(const ValueKey('feed-refresh-glyph-highlight')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final empty in [false, true]) {
    testWidgets(
      'armed pull reverses and cancels without hiding chrome (empty=$empty)',
      (tester) async {
        await _phone(tester);
        final f = await feed.FeedFixture.create();
        addTearDown(f.dispose);
        if (empty) {
          f.api.items = [];
        } else {
          _longFeed(f);
        }
        await tester.pumpWidget(_screen(f));
        await tester.pumpAndSettle();
        final baseline = tester.getSize(find.byKey(_headerKey)).height;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_listKey)),
        );
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
        await gesture.moveBy(Offset(0, empty ? 440 : 220));
        await tester.pump();
        expect(
          tester.getSize(find.byKey(_headerKey)).height,
          greaterThan(baseline + 60),
        );
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<Align>(find.byKey(_headerKey)).heightFactor, 1);
        await gesture.moveBy(const Offset(0, -130));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<Align>(find.byKey(_headerKey)).heightFactor, 1);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          f.api.calls.where((call) => call.startsWith('feed:')),
          hasLength(1),
        );
        expect(tester.getSize(find.byKey(_headerKey)).height, baseline);
        if (!empty) {
          await tester.drag(find.byKey(_listKey), const Offset(0, -150));
          await tester.pumpAndSettle();
          expect(tester.widget<Align>(find.byKey(_headerKey)).heightFactor, 0);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final cancelPointer in [false, true]) {
    testWidgets(
      'reversed pull can rearm; pointer cancellation never refreshes ($cancelPointer)',
      (tester) async {
        await _phone(tester);
        final f = await feed.FeedFixture.create();
        addTearDown(f.dispose);
        f.api.items = [];
        await tester.pumpWidget(_screen(f));
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(_listKey)),
        );
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 220));
        await tester.pump();
        await gesture.moveBy(const Offset(0, -210));
        await tester.pump();
        expect(
          f.api.calls.where((call) => call.startsWith('feed:')),
          hasLength(1),
        );
        await gesture.moveBy(const Offset(0, 180));
        await tester.pump();
        expect(
          f.api.calls.where((call) => call.startsWith('feed:')),
          hasLength(1),
        );
        if (cancelPointer) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(
          f.api.calls.where((call) => call.startsWith('feed:')),
          hasLength(cancelPointer ? 1 : 2),
        );
        expect(tester.widget<Align>(find.byKey(_headerKey)).heightFactor, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('empty feed can refresh, rapid compose taps open one picker', (
    tester,
  ) async {
    await _phone(tester);
    final f = await feed.FeedFixture.create();
    addTearDown(f.dispose);
    f.api.items = [];
    await tester.pumpWidget(_screen(f));
    await tester.pumpAndSettle();
    expect(find.text('暂无可显示的帖子'), findsOneWidget);
    await tester.drag(find.byKey(_listKey), const Offset(0, 280));
    await tester.pumpAndSettle();
    expect(f.api.calls.where((call) => call.startsWith('feed:')), hasLength(2));
    expect(
      find.byKey(const ValueKey('feed-refresh-glyph-highlight')),
      findsNothing,
    );
    final compose = tester.widget<IconButton>(
      find.byKey(const ValueKey('feed-compose')),
    );
    compose.onPressed!();
    compose.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('channel-options')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('channel-options')), findsNothing);
    expect(find.byKey(_listKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'pull grows face, rebound retains rows, single flight, failure and retry',
    (tester) async {
      await _phone(tester);
      final f = await feed.FeedFixture.create();
      addTearDown(f.dispose);
      f.api.cursor = 'saved-next-page';
      await tester.pumpWidget(_screen(f));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('post:${feed.postId}'));
      final original = tester.element(item);
      final baseline = tester.getSize(find.byKey(_headerKey)).height;
      f.api.pageWait = Completer();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_listKey)),
      );
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 180));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(_headerKey)).height,
        greaterThan(baseline + 40),
      );
      final mark = tester.widget<Text>(
        find.byKey(const ValueKey('feed-smile-text')),
      );
      expect(mark.data, ':)');
      expect(mark.style!.fontFamily, 'Roboto');
      expect(mark.style!.letterSpacing, lessThan(1));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(find.byKey(_headerKey)).height, baseline);
      expect(
        find.byKey(const ValueKey('feed-refresh-glyph-highlight')),
        findsOneWidget,
      );
      expect(identical(tester.element(item), original), isTrue);
      expect(f.controller.timelineCursor, 'saved-next-page');
      await tester.drag(find.byKey(_listKey), const Offset(0, 250));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        f.api.calls.where((call) => call.startsWith('feed:')),
        hasLength(2),
      );
      f.api.pageWait!.completeError(
        const PostFailure(kind: PostFailureKind.transport),
      );
      await tester.pumpAndSettle();
      expect(identical(tester.element(item), original), isTrue);
      expect(f.controller.timelineCursor, 'saved-next-page');
      expect(
        find.byKey(const ValueKey('feed-refresh-glyph-highlight')),
        findsNothing,
      );
      expect(find.text('暂时无法加载帖子，请重试。'), findsOneWidget);
      f.api.pageWait = null;
      await tester.drag(find.byKey(_listKey), const Offset(0, 280));
      await tester.pumpAndSettle();
      expect(f.controller.timelineError, isNull);
      expect(
        find.byKey(const ValueKey('feed-refresh-glyph-highlight')),
        findsNothing,
      );
      expect(
        f.api.calls.where((call) => call.startsWith('feed:')),
        hasLength(3),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'root snackbars avoid navigation and peer tabs consume safe inset once',
    (tester) async {
      await _phone(tester);
      final f = await feed.FeedFixture.create();
      addTearDown(f.dispose);
      final tabs = GlobalKey<PrimaryTabsState>();
      await tester.pumpWidget(_screen(f, tabsKey: tabs));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('feed-search')));
      await tester.pumpAndSettle();
      final nav = find.byType(HhAppNavigation);
      expect(
        tester.getBottomRight(find.byType(SnackBar)).dy,
        lessThanOrEqualTo(tester.getTopLeft(nav).dy + 1),
      );
      await tester.tap(
        find.byKey(const ValueKey('destination:directMessages')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('tab-safe:directMessages')),
            )
            .dy,
        tester.getTopLeft(nav).dy,
      );
      expect(find.byType(HhAppNavigation, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'window replacement owns fresh chrome while old refresh completes',
    (tester) async {
      await _phone(tester);
      final f = await feed.FeedFixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(_screen(f));
      await tester.pumpAndSettle();
      final old = FeedChromeScope.maybeOf(
        tester.element(find.byType(FeedScreen)),
      );
      f.api.pageWait = Completer();
      await tester.drag(find.byKey(_listKey), const Offset(0, 280));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(_screen(f, window: ('new-window', 2)));
      await tester.pump(const Duration(milliseconds: 400));
      final chrome = FeedChromeScope.maybeOf(
        tester.element(find.byType(FeedScreen)),
      )!;
      expect(identical(chrome, old), isFalse);
      expect(chrome.visible, isTrue);
      chrome.scroll(100, 100);
      expect(chrome.visible, isFalse);
      f.api.pageWait!.complete(
        feed.reply(PostsPage(items: f.api.items, nextCursor: null)),
      );
      await tester.pumpAndSettle();
      expect(chrome.visible, isFalse);
      expect(find.byKey(const ValueKey('feed-compose')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('nested home and peer scaffolds consume keyboard insets once', (
    tester,
  ) async {
    await _phone(tester);
    final f = await feed.FeedFixture.create();
    addTearDown(f.dispose);
    final tabs = GlobalKey<PrimaryTabsState>();
    await tester.pumpWidget(_screen(f, tabsKey: tabs));
    await tester.pumpAndSettle();
    final fullListHeight = tester.getSize(find.byKey(_listKey)).height;
    await tester.pumpWidget(_screen(f, tabsKey: tabs, keyboardHeight: 300));
    await tester.pumpAndSettle();
    expect(fullListHeight - tester.getSize(find.byKey(_listKey)).height, 300);
    await tester.tap(find.byKey(const ValueKey('destination:directMessages')));
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('tab-safe:directMessages'));
    expect(tester.getBottomRight(content).dy, 844 - 300);
    await tester.pumpWidget(_screen(f, tabsKey: tabs));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(content).dy,
      tester.getTopLeft(find.byType(HhAppNavigation)).dy,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving during pending refresh ignores late completion', (
    tester,
  ) async {
    await _phone(tester);
    final f = await feed.FeedFixture.create();
    addTearDown(f.dispose);
    await tester.pumpWidget(_screen(f));
    await tester.pumpAndSettle();
    f.api.pageWait = Completer();
    await tester.drag(find.byKey(_listKey), const Offset(0, 280));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox());
    f.api.pageWait!.complete(
      feed.reply(PostsPage(items: [], nextCursor: null)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading highlight stays inside the stationary glyph and respects reduced motion',
    (tester) async {
      final loader = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      await loader.load();
      final key = GlobalKey();
      Widget mark({required bool loading, bool reduceMotion = false}) =>
          MaterialApp(
            theme: HhTelegramTheme.create(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: FeedSmileMark(pull: 0, loading: loading),
                ),
              ),
            ),
          );
      Future<List<int>> pixels() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        return tester
            .runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final bytes = data!.buffer.asUint8List().toList();
              image.dispose();
              return bytes;
            })
            .then((value) => value!);
      }

      await tester.pumpWidget(mark(loading: false));
      final idle = await pixels();
      await tester.pumpWidget(mark(loading: true));
      final first = await pixels();
      await tester.pump(const Duration(milliseconds: 275));
      final second = await pixels();
      expect(second, isNot(equals(first)));
      for (var i = 3; i < idle.length; i += 4) {
        if (idle[i] == 0) {
          expect(
            first[i],
            0,
            reason: 'loading must not draw outside the glyph',
          );
          expect(
            second[i],
            0,
            reason: 'the glyph must not rotate or grow while loading',
          );
        }
      }
      await tester.pumpWidget(mark(loading: true, reduceMotion: true));
      final reduced = await pixels();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await pixels(), equals(reduced));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('real-font light/dark, immersive, pull and loading renders', (
    tester,
  ) async {
    await _phone(tester);
    for (final asset in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
      final loader = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/$asset'));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final chinese = FontLoader('HhNotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'));
    await chinese.load();
    final f = await feed.FeedFixture.create();
    addTearDown(f.dispose);
    _longFeed(f);
    await tester.pumpWidget(_screen(f));
    await tester.pumpAndSettle();
    await _capture(tester, 'light-expanded');
    await tester.drag(find.byKey(_listKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    await _capture(tester, 'light-immersive');
    _scroll(tester).jumpTo(0);
    await tester.pumpAndSettle();
    f.api.pageWait = Completer();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_listKey)),
    );
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump();
    await _capture(tester, 'light-pull');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const ValueKey('feed-refresh-glyph-highlight')),
      findsOneWidget,
    );
    await _capture(tester, 'light-loading');
    await tester.pump(const Duration(milliseconds: 275));
    await _capture(tester, 'light-loading-next');
    f.api.pageWait!.complete(
      feed.reply(PostsPage(items: f.api.items, nextCursor: null)),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _screen(f, brightness: Brightness.dark, scale: 1.8, reduceMotion: true),
    );
    await tester.pumpAndSettle();
    await _capture(tester, 'dark-large-text');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
