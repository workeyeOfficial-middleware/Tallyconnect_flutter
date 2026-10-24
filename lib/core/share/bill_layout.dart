// What a bill / invoice PDF shows (NEW feature). Saved per user and company
// on this phone; a share can use a changed copy without saving it. The
// standard layout prints exactly what bills printed before.
library;

class BillLayout {
  const BillLayout({
    this.showLogo = true,
    this.showSeller = true,
    this.showPartyCity = true,
    this.showDue = true,
    this.showItems = true,
    this.showHsn = true,
    this.showQtyRate = true,
    this.showAccounts = true,
    this.showTaxes = true,
    this.showAmountBox = true,
    this.showEinvoice = true,
    this.showNote = true,
    this.showSignature = true,
    this.showFooter = true,
    this.seller = '',
    this.terms = '',
  });

  /// Company logo at the top (when one is uploaded).
  final bool showLogo;

  /// Address / GSTIN lines under the company name ([seller]).
  final bool showSeller;
  final bool showPartyCity, showDue;

  /// Item table, and its HSN / Qty and Rate columns.
  final bool showItems, showHsn, showQtyRate;

  /// Dr / Cr accounts of the voucher.
  final bool showAccounts;

  /// Subtotal and tax rows above the total.
  final bool showTaxes;

  /// "Amount: ₹…" strip under the total.
  final bool showAmountBox;
  final bool showEinvoice, showNote, showSignature;

  /// "Made with TallyConnect" line.
  final bool showFooter;

  /// Address / GSTIN / phone typed by the user, one per line.
  final String seller;

  /// Terms, bank details or a thank-you line printed at the bottom.
  final String terms;

  static const BillLayout standard = BillLayout();

  static const int kMaxText = 600;

  List<String> get sellerLines => seller
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .take(6)
      .toList();

  /// Switches by key (the settings sheet's rows).
  static const List<(String, String)> kFields = <(String, String)>[
    ('logo', 'Company logo'),
    ('seller', 'Address / GSTIN lines'),
    ('city', 'Party place'),
    ('due', 'Due date'),
    ('items', 'Item table'),
    ('hsn', 'HSN column'),
    ('qtyRate', 'Qty and rate columns'),
    ('accounts', 'Accounts (Dr / Cr)'),
    ('taxes', 'Subtotal and taxes'),
    ('amountBox', 'Amount strip'),
    ('einvoice', 'E-invoice QR and IRN'),
    ('note', 'Notes about the data'),
    ('signature', 'Authorised signatory'),
    ('footer', '"Made with TallyConnect"'),
  ];

  bool on(String k) => switch (k) {
    'logo' => showLogo,
    'seller' => showSeller,
    'city' => showPartyCity,
    'due' => showDue,
    'items' => showItems,
    'hsn' => showHsn,
    'qtyRate' => showQtyRate,
    'accounts' => showAccounts,
    'taxes' => showTaxes,
    'amountBox' => showAmountBox,
    'einvoice' => showEinvoice,
    'note' => showNote,
    'signature' => showSignature,
    'footer' => showFooter,
    _ => false,
  };

  BillLayout toggled(String k) => copyWith(<String, bool>{k: !on(k)});

  BillLayout copyWith([
    Map<String, bool> f = const <String, bool>{},
    String? seller,
    String? terms,
  ]) => BillLayout(
    showLogo: f['logo'] ?? showLogo,
    showSeller: f['seller'] ?? showSeller,
    showPartyCity: f['city'] ?? showPartyCity,
    showDue: f['due'] ?? showDue,
    showItems: f['items'] ?? showItems,
    showHsn: f['hsn'] ?? showHsn,
    showQtyRate: f['qtyRate'] ?? showQtyRate,
    showAccounts: f['accounts'] ?? showAccounts,
    showTaxes: f['taxes'] ?? showTaxes,
    showAmountBox: f['amountBox'] ?? showAmountBox,
    showEinvoice: f['einvoice'] ?? showEinvoice,
    showNote: f['note'] ?? showNote,
    showSignature: f['signature'] ?? showSignature,
    showFooter: f['footer'] ?? showFooter,
    seller: _cut(seller ?? this.seller),
    terms: _cut(terms ?? this.terms),
  );

  static String _cut(String s) =>
      s.length > kMaxText ? s.substring(0, kMaxText) : s;

  Map<String, Object?> toJson() => <String, Object?>{
    for (final (String, String) f in kFields) f.$1: on(f.$1),
    'sellerText': seller,
    'terms': terms,
  };

  /// Unknown / missing values keep the standard layout.
  factory BillLayout.fromJson(Object? o) {
    if (o is! Map) return standard;
    return standard.copyWith(
      <String, bool>{
        for (final (String, String) f in kFields)
          if (o[f.$1] is bool) f.$1: o[f.$1]! as bool,
      },
      o['sellerText'] is String ? o['sellerText']! as String : '',
      o['terms'] is String ? o['terms']! as String : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BillLayout &&
      seller == other.seller &&
      terms == other.terms &&
      kFields.every(((String, String) f) => on(f.$1) == other.on(f.$1));

  @override
  int get hashCode => Object.hash(
    seller,
    terms,
    Object.hashAll(<bool>[for (final (String, String) f in kFields) on(f.$1)]),
  );
}
