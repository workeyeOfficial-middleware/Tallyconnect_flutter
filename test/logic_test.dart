// Logic tests against the prototype's behaviour (Main.dc.html).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallyconnect_ui/app/app_state.dart';
import 'package:tallyconnect_ui/core/design/tc_color_math.dart';
import 'package:tallyconnect_ui/core/design/tc_palette.dart';
import 'package:tallyconnect_ui/core/storage/local_storage.dart';
import 'package:tallyconnect_ui/core/utils/format.dart';
import 'package:tallyconnect_ui/data/mock/mock_data.dart';
import 'package:tallyconnect_ui/data/models/models.dart';

AppController make({String start = 'home', LocalStorage? store}) =>
    AppController(store: store ?? LocalStorage.memory(), startScreen: start);

void main() {
  group('format (inr / inr2 / fdate / initials)', () {
    test('Indian grouping and minus sign', () {
      expect(inr(348690), '₹3,48,690');
      expect(inr(918490), '₹9,18,490');
      expect(inr(1234567), '₹12,34,567');
      expect(inr(999), '₹999');
      expect(inr(-12000), '−₹12,000');
      expect(inr(0), '₹0');
    });
    test('two decimals', () {
      expect(inr2(85), '₹85.00');
      expect(inr2(100.3), '₹100.30');
    });
    test('dates and initials', () {
      expect(fdate('2026-09-26'), '26 Sep 2026');
      expect(fdate(''), '—');
      expect(initials('shree'), 'S');
    });
  });

  group('mock data matches the prototype', () {
    test('totals', () {
      expect(kVouchers.length, 21);
      expect(kVouchers.fold<int>(0, (int s, Voucher v) => s + v.amt), 918490);
      expect(kRecv.fold<int>(0, (int s, Bill b) => s + b.amt), 348690);
      expect(kPayb.fold<int>(0, (int s, Bill b) => s + b.amt), 126850);
      expect(
        kItems.fold<int>(0, (int s, Item x) => s + x.stock * x.rate),
        245760,
      );
      expect(kParties.length, 14);
      expect(kShortcuts.length, 10);
      expect(kSums.length, 8);
      expect(kReports.length, 8);
      expect(kNotifs.length, 6);
      expect(kActs.length, 10);
    });
  });

  group('colour engine', () {
    test('hex ↔ hsv round trip', () {
      final List<int> q = hex2hsv('#8C1D3F');
      expect(
        hsv2hex(q[0].toDouble(), q[1].toDouble(), q[2].toDouble()),
        isIn(<String>['#8C1D3F', '#8C1D3E', '#8C1E3F']),
      );
    });
    test('makeTheme accent is readable on #F2F4FA', () {
      for (final String hex in kQuickSwatches) {
        for (int i = 0; i < kCombos.length; i++) {
          final GeneratedTheme t = makeTheme(hex, i);
          expect(
            contrastOf(colorHex(t.acc), '#F2F4FA'),
            greaterThanOrEqualTo(4.8),
            reason: '$hex combo $i',
          );
        }
      }
    });
    test('accent validation per look', () {
      expect(okAccent('aurora', 'berry'), isTrue);
      expect(okAccent('aurora', 'teal'), isFalse);
      expect(okAccent('mint', 'look'), isTrue);
    });
    test(
      'root cascade: accent class overrides look accent, photo boosts glass',
      () {
        final TcPalette a = resolvePalette(preset: 'aurora', accent: 'indigo');
        expect(colorHex(a.acc), '#4338CA');
        final TcPalette ph = resolvePalette(
          preset: 'aurora',
          wallK: 'photo',
          photoPath: '/x.jpg',
          photoLum: .2,
        );
        expect(ph.gb, .2);
        expect(ph.photoDark, isTrue);
        final TcPalette g = resolvePalette(preset: 'aurora', glass: 64);
        expect(g.g, closeTo(.6, 1e-9));
      },
    );
  });

  group('navigation (go / back / selectTab)', () {
    test('go pushes history; back pops; empty back returns to Home', () {
      final AppController c = make();
      c.go('items');
      c.go('report', <String, Object?>{'report': 'stock'});
      expect(c.history, <String>['home', 'items']);
      expect(c.report, 'stock');
      expect(c.backLabel, 'Items');
      c.back();
      expect(c.screen, 'items');
      expect(c.dir, 'bk');
      c.back();
      c.back();
      expect(c.screen, 'home');
      c.dispose();
    });
    test('tab screens clear history and keep the tab bar', () {
      final AppController c = make();
      c.go('settings');
      c.go('team');
      expect(c.screen, 'team');
      expect(c.history, isEmpty);
      expect(c.tab, 2);
      expect(c.showTabs, isTrue);
      c.go('flow');
      expect(c.showTabs, isFalse);
      c.dispose();
    });
    test('forgot with no history goes back to login', () {
      final AppController c = make(start: 'login');
      c.goForgot();
      c.history = <String>[];
      c.back();
      expect(c.screen, 'login');
      c.dispose();
    });
  });

  group('home pages: pin / hide / unhide', () {
    test('default page = newEntry + workspace shortcuts + money', () {
      final AppController c = make();
      expect(c.curPages(), <List<String>>[
        <String>[
          'newEntry',
          'items',
          'party',
          'vouchers',
          'outstanding',
          'reports',
          'settings',
          'money',
        ],
      ]);
      c.dispose();
    });
    test('hide stores a snapshot; unhide restores the exact position', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController c = make(store: s);
      c.hideWidget('vouchers');
      expect(c.curPages().first.contains('vouchers'), isFalse);
      expect(c.hidList().single.id, 'vouchers');
      expect(c.toast, 'Card hidden');
      c.restoreHidden(<String>['vouchers']);
      expect(c.curPages().first, <String>[
        'newEntry',
        'items',
        'party',
        'vouchers',
        'outstanding',
        'reports',
        'settings',
        'money',
      ]);
      expect(c.hidList(), isEmpty);
      expect(c.toast, 'Card unhidden');
      // persisted under the prototype key
      expect(s.load<Object?>(LocalStorage.kPages, null), isNotNull);
      c.dispose();
    });
    test('pin moves the card to the front of page 1 after other pins', () {
      final AppController c = make();
      c.togglePin('reports');
      expect(c.curPages().first.first, 'reports');
      c.togglePin('party');
      expect(c.curPages().first.take(2), <String>['reports', 'party']);
      expect(c.pinned, <String>['reports', 'party']);
      c.togglePin('party');
      expect(c.pinned, <String>['reports']);
      expect(c.toast, 'Unpinned');
      c.dispose();
    });
    test('cleanPages keeps page 0 and pages holding hidden cards', () {
      final AppController c = make();
      final (List<List<String>>, List<HiddenCard>) r = c.cleanPages(
        <List<String>>[
          <String>['a'],
          <String>[],
          <String>[],
          <String>['b'],
        ],
        <HiddenCard>[
          HiddenCard('x', 2, 0, <String>['x']),
        ],
      );
      expect(r.$1, <List<String>>[
        <String>['a'],
        <String>[],
        <String>['b'],
      ]);
      expect(r.$2.single.page, 1);
      c.dispose();
    });
  });

  group('customisable lists', () {
    test('pinned first, then saved order, hidden removed, unhide restores', () {
      final AppController c = make();
      c.updPref('reports', (ListPref p) {
        p.pinned.add('stock');
        p.hidden.add('top');
        p.order = <String>['day', 'exp'];
      });
      final ({List<Report> rows, int hidden, VoidCallback unhide}) v = c
          .listView<Report>('reports', kReports, (Report r) => r.id);
      expect(v.rows.first.id, 'stock');
      expect(v.rows[1].id, 'day');
      expect(v.rows[2].id, 'exp');
      expect(v.rows.any((Report r) => r.id == 'top'), isFalse);
      expect(v.hidden, 1);
      v.unhide();
      expect(
        c.listView<Report>('reports', kReports, (Report r) => r.id).hidden,
        0,
      );
      c.dispose();
    });
  });

  group('entry flow', () {
    test('GST totals of the initial sales lines', () {
      final AppController c = make();
      final ({int sub, int gst, int total}) t = c.totals(c.lines['sales']!);
      expect(t.sub, 1850 * 2 + 34 * 100 + 520 * 10);
      expect(t.gst, (t.sub * .18).round());
      expect(t.total, t.sub + t.gst);
      c.dispose();
    });
    test('journal balance and mode → account rule', () {
      final AppController c = make();
      expect(c.drSum, 120000);
      expect(c.crSum, 120000);
      c.updJl(1, (JLine j) => j.copyWith(amt: 100000));
      expect(c.drSum == c.crSum, isFalse);
      c.startFlow('receipt');
      c.setMode('cash');
      expect(c.form['rAcc'], 'Cash in hand');
      c.setMode('upi');
      expect(c.form['rAcc'], 'HDFC Bank – Current');
      c.dispose();
    });
    test('save adds a waiting activity entry and returns Home', () {
      final AppController c = make();
      c.startFlow('sales');
      expect(c.screen, 'flow');
      c.saveFlow(false);
      expect(c.screen, 'home');
      expect(c.acts.first.no, 'Sales 11');
      expect(c.acts.first.status, 'wait');
      expect(c.toast, 'Saved! It will reach Tally by itself');
      c.dispose();
    });
    test('new item uses discounted rate and chosen unit / GST', () {
      final AppController c = make();
      c.startFlow('purchase');
      c.form.addAll(<String, String>{
        'niName': 'Pipe',
        'niQty': '3',
        'niRate': '100',
        'niDisc': '10',
      });
      c.niUnit = 'BOX';
      c.niGst = 12;
      c.addNewItem();
      final Line l = c.lines['purchase']!.last;
      expect(l.rate, 90);
      expect(l.qty, 3);
      expect(l.unit, 'box');
      expect(l.gst, 12);
      c.dispose();
    });
  });

  group('workspaces, team, theme persistence', () {
    test(
      'saving a workspace without money cards defaults to To get / To give',
      () {
        final AppController c = make();
        c.goCreateWs();
        c.form['wsName'] = 'Desk';
        c.wsSel = <String>['items'];
        c.saveWs();
        expect(c.wsList.last.sums, <String>['toGet', 'toGive']);
        expect(c.screen, 'manageWs');
        c.dispose();
      },
    );
    test('invite adds a pending member', () {
      final AppController c = make();
      c.form['iEmail'] = 'ravi@example.com';
      c.sendInvite();
      expect(c.team.last.st, 'pending');
      expect(c.team.last.name, 'ravi');
      c.dispose();
    });
    test('look, accent and tab order survive a restart', () {
      final LocalStorage s = LocalStorage.memory();
      final AppController a = make(store: s);
      a.pickLook('mint');
      a.pickAccent('forest');
      s.save(LocalStorage.kTabs, <int>[4, 3, 2, 1, 0]);
      a.dispose();
      final AppController b = make(store: s);
      expect(b.preset, 'mint');
      expect(b.accent, 'forest');
      expect(b.tabOrder, <int>[4, 3, 2, 1, 0]);
      b.dispose();
    });
  });
}
