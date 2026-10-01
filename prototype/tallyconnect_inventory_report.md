# TallyConnect Prototype - Complete Functional Inventory (1:1 Flutter Rebuild Reference)

Generated: 01-Oct-2026 13:04:17

Main Source: D:\Tallyconnect_UI\prototype\TallyConnect_App_Source.jsx (1167 lines)
HTML: D:\Tallyconnect_UI\prototype\app_prototype\app_index.html (312KB)
Markup: D:\Tallyconnect_UI\prototype\app_prototype_markup.html

This is a comprehensive specification for rebuilding the exact UI/UX in Flutter.

---

## 1. NAVIGATION MODEL

### 1.1 Bottom Navigation Tabs (line 79)
TABS = [
1. {k:'home', t:'Home', ic:'home'}
2. {k:'outHub', t:'Dues', ic:'rupeeC'} 
3. {k:'team', t:'Team', ic:'team'}
4. {k:'activity', t:'Activity', ic:'activity'}
5. {k:'reports', t:'Reports', ic:'chart'}
]

- Total 5 tabs, positioned left-to-right
- Icons use custom SVG paths (IC object)
- Bottom tab bar is glass styled with animated pill

### 1.2 Screens Hiding Bottom Navigation
NO_TAB (line 80): ['login','forgot','flow','createWs','manageWs','billDetail','partyDetail','actDetail','entryDetail','newEntry']
- These screens take full viewport, no bottom tab bar

FLOWLIKE (line 81): ['flow','createWs','manageWs','billDetail','partyDetail','entryDetail']  
- Flow-like transitions (forward/back directional animations)

### 1.3 Screen Titles Map (line 82)
TITLES = {
  home:'Home', notifs:'Alerts', createWs:'Workspace', manageWs:'Workspaces',
  newEntry:'New Entry', flow:'Entry', vHub:'Vouchers', vList:'Vouchers',
  entryDetail:'Entry', outHub:'Dues', outList:'Dues', billDetail:'Bill',
  items:'Items', party:'Party', partyDetail:'Party', reports:'Reports',
  report:'Reports', activity:'Activity', actDetail:'Activity', team:'Team',
  settings:'Settings', companies:'Companies', billing:'Plans', refer:'Refer',
  help:'Help', login:'Log in', forgot:'Log in'
}

### 1.4 Navigation Stack & Transitions
- History stack maintained: history: [] array (state.history)
- Direction tracking: dir is 'fwd' or 'bk' for slide animations
- go(s, extra): pushes current screen to history, navigates to s with dir='fwd'
- back(): pops from history, sets dir='bk'. If empty, goes to home (tab 0). Special case forgot->login
- jump(s): for starting at specific screen; if tab, uses selectTab; else resets history
- Screen classes: scr for normal screens, homeScr for home, lowCls for flow-like
- Transitions use CSS keyframes: inF (30px right slide in), inB (30px left slide in)


### 1.5 Bottom Navigation Pill (Animated)
- State: pillL (left), pillW (width), pillT (transition), pillS (scale transform)
- 5 tabs, each 70px wide, 6px left offset. Tab positions by order array.
- When switching tabs: initial pill animates width+left+scaleY(.84) in 200ms, then springs back with cubic-bezier(.26,1.55,.44,1) over 620ms
- Tab reordering: draggable tabs (tdrag). Long press/dwell to select tab while hovering? (armDwell, hb/hover bubble)
- tabOrder array persists in localStorage 'tc-liquid-tabs' (default [0,1,2,3,4])
- Dragging tab updates order, pill follows

### 1.6 Drawer / Side Menu
- Triggered via openMenu() -> sets overlay:'menu'
- Contents from menu.acct:
  - Companies (building, go:companies)
  - Sales Team (team, go:team) 
  - Reports (chart, go:reports)
  - Settings (gear, go:settings)
  - Alerts (bell, go:notifs, count: unread)
  - Workspaces (grid, go:manageWs)
  - Refer a friend (gift, go:refer)
- Also includes: Profile section (avatar W, name workk72002, email workk72002@gmail.com), Plan (Enterprise, billing), Support (help, version 19.6.2), Change password, Log out
- Slides in from left (animation slideL .42s cubic-bezier(.2,.95,.25,1))
- Scrim overlay on click closes

### 1.7 Hamburger Menu
- Top-left on most screens (home, vHub, reports, activity, etc.)
- Opens side drawer


## 2. ALL SCREENS - Complete Breakdown

### 2.1 Login Screen (login)
Route: 'login' | NO_TAB | Not FLOWLIKE | Title 'Log in'
State: loggedIn=false, showPass toggle

**Header:**
- App logo mark (rupeeC icon in gradient circle)
- Brand: 'TallyConnect' (Tally + Connect split)
- H1: 'Welcome back'
- Sub: 'Log in to see your business'

**Form:**
- Username/email field: label 'Username or email', icon person, placeholder 'e.g. workk72002', autocomplete username
- Password field: label 'Password', icon lock, type toggle (showPass), eye icon, placeholder 'Enter your password', autocomplete current-password
- 'Forgot password?' link (bottom right) -> goes to 'forgot'

**Actions:**
- Primary button: 'Log In' + arrow icon -> doLogin() sets loggedIn true, tab 0, navigates home
- 'or' divider
- Help card: 'Need help logging in?' with subtext, chevron -> nav.help (goes to help screen)

**Footer:** 'Version 19.6.2'

### 2.2 Forgot Password (forgot)
NO_TAB. Back to login. Title 'Log in' (from TITLES)

**UI:**
- Top nav: back button 'Log in'
- Header icon: key in circle (color acc)
- H1: 'Forgot password?'
- Subtext explaining email reset

**State notSent (default true):**
- Email field: label 'Email address', icon mail, placeholder 'name@example.com', type email
- Primary button: 'Send link' + send icon -> sendReset() sets forgotSent true

**State forgotSent (true):**
- Success card with checkmark circle
- 'Check your email' title
- 'We sent a link. Open it to set a new password.'
- Button 'Back to Log in' -> back to login

### 2.3 Home Dashboard (home)
Default tab. Has bottom nav. Title 'Home'

**Top Header:**
- Hamburger (menu) opens drawer
- Brand 'TallyConnect' center
- Search icon (openSearch)
- Alerts bell (nav.notifs) with unread dot if hasUnread>0

**Company Bar (clickable):**
- Building icon in circle
- Company name (from COMPANIES, default 'gi' -> 'GI Apr 25-26' shown as companyName split)
- Status: 'Tally Connected' with live dot + laptop icon
- 'Synced 2 min ago' 
- Chevron down -> openCompany() sheet

**Pager (Liquid Pages):**
- Horizontal scroll snap, pages array per workspace
- Page 0 title: 'What would you like to do?'
- Other pages: 'Page N'
- Dots navigation at bottom (if >1 page)
- Drag-to-reorder widgets within/between pages (editing mode)
- Edge swipe zones (left/right) to flip pages while dragging widget

**Page Widgets:**
1. 'newEntry' widget (wide, hero card on page 0)
   - Hero: '+' icon circle, 'New Entry' title, 'Record a sale, purchase, money in or out', chevron -> go('newEntry')
   - Quick actions grid (4): Sale (bag, flow sales), Purchase (cart), Money In (in), Money Out (out)

2. 'money' widget (wide)
   - 'Money summary' header + 'Sample data' badge
   - 2x2 grid of SUMS cards: To get, To give, Money in, Money out (each shows icon, title, subtitle, amount with cls)
   - Background colors via SUMBG mapping
   - Tapping runs m.go (navigation)

3. Tile widgets for each feat in workspace: Items, Party, Vouchers, Outstanding/Dues, Reports, Settings (based on T mapping)
   - Each: icon in circle, title, subtitle
   - If customize/editing mode: shows +/− badge to hide/show
   - Tapping: if flow type -> startFlow(), else go(to)

**Home State Features:**
- editing mode (enterEdit/doneEdit/cancelEdit) - rearranges widgets
- Pinned widgets (pin to top of page 0)
- Hidden widgets (moved to hidden panel per page)
- Context menu (long press) on widgets: Pin/Unpin, Open, Drag, Hide
- Drag & drop with ghost widget, edge auto-flip, drop zones


### 2.4 Notifications (notifs)
Title 'Alerts', back to previous. Has unread count.

**Header:**
- Back button + label
- Refresh icon
- H1 'Alerts', sub shows unreadTxt

**Filters:**
- Segmented control: All / Unread
- 'Mark all read' button

**List:**
- Each notification: icon (by type), title, body text, time, unread dot if unread
- Tapping marks as read and runs go action
- Context menu support (pinned/hidden via list prefs)
- Empty state: 'You have read everything.'

**Notification items (NOTIFS array):**
n1: Payment received (in, receipt) - ₹25,000 from Mehta Electricals RCT-0003, 10min ago, unread -> vList receipt/month
n2: Sent to Tally (sync, activity) - 12 entries to GI Apr 25-26, 1hr ago, unread -> activity
n3: Invite accepted (team) - Priya Shah joined, yesterday, unread -> team
n4: Payment due soon (out, payment) - ₹48,380 to Kiran Steel due 29 Sep, yesterday -> outList pay/all
n5: New join request (userPlus, party) - Sunita Rao wants to join, 23 Sep -> team
n6: Plan renewal (card, acc) - Enterprise renews 31 Mar 2027, 20 Sep -> billing

### 2.5 Create Workspace (createWs) - FLOWLIKE
Full screen flow, back/cancel

**Header:** Back, title 'Make a workspace', Reset button

**Form:**
- Workspace name field: icon grid, placeholder 'e.g. Sales Desk'

**Tabs (segmented):** Shortcuts (N) / Money cards (N)

**Chosen section:** shows selected items with - button to remove
**Available section:** grid of unselected items with + button to add

**Features available (FEATS = all T keys):** items, party, vouchers, outstanding, reports, settings, sales, purchase, moneyIn, moneyOut
**Sums available (SUMK):** all SUMS keys

**Footer:** Cancel, Save workspace (disabled if no name or no shortcuts)

**Behavior:** Creating new adds to wsList; editing existing pre-fills

### 2.6 Manage Workspaces (manageWs) - FLOWLIKE
Lists all workspaces (WS array + custom)

**Each workspace card:**
- Icon grid, name, meta (shortcuts count + sums count + builtin/custom)
- 'Shortcuts:' comma list, 'Money cards:' comma list
- If active: 'In use' badge
- If not active: 'Use' button -> switches activeWs, resets to home
- If custom (not builtin): Edit and Delete buttons

**Footer:** 'Make a new workspace' -> goes to createWs (clears form)

**Default workspaces:**
def (Default Home): feats [items,party,vouchers,outstanding,reports,settings], sums [toGet,toGive,mIn,mOut], builtin
sd (Sales Desk): feats [sales,moneyIn,party,vouchers,outstanding,reports], sums [toGet,sales,mIn,cash]
me (Month-end Closing): feats [moneyOut,purchase,vouchers,outstanding,reports,settings], sums [cash,bank,toGive,mOut]

### 2.7 New Entry Hub (newEntry)
NO_TAB. Title 'New Entry', back to previous

**Header:** Back to backLabel
**Title:** 'New Entry', sub 'What do you want to write down?'

**Entry tiles (2x2 grid):**
1. Sale - sold goods, bag icon color sales -> flow 'sales'
2. Purchase - bought goods, cart color purchase -> 'purchase'  
3. Money In - came to you, in color receipt -> 'receipt'
4. Money Out - went out, out color payment -> 'payment'

**Bottom row:** Adjustment (Journal) - book icon color journal -> flow 'journal'

**Info:** note about going back at any step, nothing sent until Save


### 2.8 Entry Flow Wizard (flow) - FLOWLIKE, multi-step
Dynamic based on flow.type. cfg from FT[type]. Steps vary by type.

**Flow Types (FT config):**
sales: steps [Details, Items, Payment, Check], partyLabel Customer (list c), items true, noLabel 'Bill no.', amtLabel 'Money received now', balLabel 'Still to get', draft true
purchase: [Details, Items, Payment, Check], partyLabel 'Supplier (you bought from)', list s, items true, noLabel 'Bill no.', amtLabel 'Money paid now', balLabel 'Still to pay', draft true
receipt: [Details, How paid, Check], partyLabel 'Received from', list c, noLabel 'Receipt no.', amtLabel 'Amount received', accLabel 'Put money into'
payment: [Details, How paid, Check], partyLabel 'Paid to', list s, noLabel 'Payment no.', amtLabel 'Amount paid', accLabel 'Paid from'
journal: [Details, Accounts, Check], partyLabel 'Main account', noLabel 'Entry no.'

**Header:** Back/cancel, icon+title+subtitle by type, help

**Stepper:** shows steps with dots (done/cur/todo), checkmarks when done

#### Step 0 - Details (all types)
Common fields vary:
- no (Bill/Receipt/Payment/Entry no.) - editable
- date (date picker, default sDate '2026-09-26')
- party (select from poolFor(list), tap opens pick sheet; + button to add new party for non-journal)
- purchase only: Seller's bill no. (pSupInv)
- receipt/payment only: Against which bill? (ref) optional
- amount (if not items type): editable number
- items types: Pay by date (due)
- note (textarea)

#### Step 1 - Items (sales/purchase only)
- Search item button -> opens item picker sheet
- Items list with each line: name, rate×qty+unit+GST, amount, quantity stepper (-/+, min 1), delete
- Totals: Before GST (sub), GST, Bill total
- 'Add item' dash button

#### Step 2 - Payment/How paid
**For sales/purchase (has items, step 2):**
- Payment mode selector: Cash/Bank/UPI/Cheque/Other (5 modes from MODES)
- Amount received/paid now (editable) - defaults from total or form value
- Totals: Bill total, Still to get/pay (bal = total - payAmt, red if >0 warning style, green if settled)
- Payment note (optional)

**For receipt/payment (no items, step 1 of 2 becomes How paid):**
- Payment mode selector (affects bank/ref fields, sets acc default)
- If mode != Cash: Bank name, Reference/UTR no.
- Put money into / Paid from (account picker) - defaults based on mode (Cash in hand vs bank)
- Amount shown

**For journal (step 1):**
- Dr/Cr summary cards (Goes to Dr, Comes from Cr) with amounts
- Balance indicator: 'Matched' green if equal>0, else 'Not matching' warning with difference
- Journal lines list: each shows side toggle (Dr<->Cr), account name+group, amount input, delete
- 'Add account' button opens ledger picker
- Must be balanced (drSum==crSum && >0) to proceed

#### Step last (Check/Summary)
Hero card: type icon, entry no, total amount, subtitle with dates
'Ready to send to Tally' green banner
Sections (editable via 'Change'): Details, Items (if any), Payment/How paid/Accounts
Footer: Back/Cancel, Save (primary) or Draft (if cfg.draft true)

**Save behavior:**
- saveFlow(false): creates new entry in acts array with status 'wait', id 'n'+timestamp, time 'Just now', fresh true. Navigates to home (tab 0). After 5 seconds status becomes 'ok', time still 'Just now'
- saveFlow(true): just says 'Draft saved on this phone' and goes home
- retry(id): sets status 'wait' with note 'Trying again…', after 1600ms becomes 'ok'


### 2.9 Vouchers Hub/List (vHub, vList)
vHub - main vouchers screen, bottom nav. Shows summary cards + recent
vList - filtered list view (param: v.mode 'month'/'recent'/'receipt'/'payment'/'bill'/'adjust')

**vHub Top/Header:**
- Hamburger menu
- Title 'Vouchers'
- Search button

**Summary cards (3 wide):** 
- Sales (KIND.sales) - ₹124,530, +8.4% vs last month
- Purchases (purchase) - ₹92,840
- Payments/Receipts combined or 'Net cash' - ₹31,690

**Quick filters:** All, Sales, Purchases, Receipts, Payments

**Recent entries section:** list of recent vouchers, 'View all' -> vList recent

**vList:**
- Back to vHub
- Title varies by mode (Vouchers/Receipts/Payments/Bills/Adjustments)
- Filter chips by type
- Each row: icon by kind, title (party/name), voucher no/date, amount (red/green by type), status badge (ok/wait) if present
- Tapping -> go('entryDetail') with entry id

### 2.10 Entry Detail (entryDetail) - FLOWLIKE
Full details of a voucher/entry

**Header:** Back, Edit button (if draft?), Share/More

**Hero card:**
- Icon by kind (sales/purchase/receipt/payment/journal)
- Type label, voucher no/date, total amount, status (Synced/Waiting/Failed)

**Sections:**
- Details: Party, Date, Due date (if any), Reference, Notes
- Items (if items present): each line qty×rate, GST, amount
- Totals: Subtotal, GST, Discount, Total, Paid, Balance
- Payment: Mode, Account, Bank/Ref, Paid on
- Accounts (journal): Dr/Cr table with accounts

**Actions:** Duplicate, Delete, Print/share (PDF concept), Retry (if failed/wait)

### 2.11 Bill Detail (billDetail) - FLOWLIKE
Outstanding bill specific view
- Header back, title 'Bill'
- Bill info, party, amounts, due date
- Payments history
- Actions: Record payment, Send reminder, Edit

### 2.12 Party/Party Detail (party, partyDetail)
party: list of parties (PARTIES), search, filter by customer/supplier
partyDetail: per party - profile, outstanding balance (to get/to give), bills, recent entries

### 2.13 Outstanding/Dues (outHub, outList)
outHub: summary - Total to get, Total to give, Overdue, Next due (from SUMS/derived)
outList: list by mode (pay/get/all/month), group by party or by due date

### 2.14 Reports (reports, report) - bottom nav
reports: grid of report cards (REPORTS array)
report: individual report view (charts/ tables)


### 2.15 Activity (activity) - bottom nav, title 'Activity'
Timeline of sync/activity (ACTS array)
**Header:** Hamburger, title, filter (All/Syncs/Edits/Invites)
Each item: icon, title, body, time, status badge (ok/wait/error). Tappable to relevant screen.

### 2.16 Team (team) - bottom nav
TEAM array: members with role, status (pending/active/inactive), email, initials
Actions: Invite member, Manage roles

### 2.17 Settings (settings)
Sections:
- Profile (edit name/email, avatar)
- Workspaces (manageWs)
- Companies (companies list -> switch)
- Appearance/Look (go to look-customize? may exist)
- Data & Sync (Tally connection, sync now, auto-sync)
- Billing (plans)
- Help & FAQ (help/FAQs)
- About (version)
- Logout

### 2.18 Other Screens Referenced
- help: Help/Support, FAQS array
- refer: Referral program
- companies: COMPANIES picker/switcher (building icon)
- look/customize: theme customization (may be look sheet or screen)
- items: ITEMS list + add/edit
- billing: subscription plans

### 2.19 Hidden Cards Sheet
Triggered from home when editing + has hidden widgets: 'Hidden cards' sheet slides up (up animation), shows widgets in Hidden list for current page, can restore/unhide

### 2.20 Company Picker Sheet
openCompany() - bottom sheet: lists COMPANIES, shows current with check, 'Add company', 'Manage' -> companies. Slides up.

### 2.21 Context Menu (cmenu)
Generic context menu (positioned absolutely): options depend on context (widget: Pin/Unpin, Open, Drag, Hide; list row: similar). Shows list with icons/text.

### 2.22 Search Overlay
openSearch() - full overlay (fade+rise), search field, recent searches, results. 


## 3. DATA LAYER - Arrays (lines 96–260)

All arrays defined in TallyConnect_App_Source.jsx. Field names as-is.

### 3.1 SUMS (lines 96–103) - Money Summary Cards
6 items (default):
s0 k='toGet', t:'To get', sub:'Money customers owe you', amt:124530, cls:'g30'
s1 k='toGive', t:'To give', sub:'Money you owe others', amt:48380, cls:'g30' 
s2 k='mIn', t:'Money in', sub:'Last 30 days', amt:215340, cls:'g40'
s3 k='mOut', t:'Money out', sub:'Last 30 days', amt:183410, cls:'g40'
s4 k='cash', t:'Cash on hand', sub:'Till today', amt:42830, cls:'g50'
s5 k='bank', t:'Bank balance', sub:'Across accounts', amt:87210, cls:'g50'

SUMBG map for home: toGet=#F6E6EB, toGive=#F6E6EB, mIn=#F1F5FF, mOut=#F1F5FF, cash=#F5F1FF, bank=#F5F1FF

### 3.2 KIND (lines 105–109) - Voucher Types
sales: {c:'#6D9BF5', bg:'#F1F5FF', i:'bag'}, purchase: {c:'#7CB664', bg:'#F4F9F2', i:'cart'}, receipt: {c:'#6BBF7E', bg:'#F2F9F4', i:'in'}, payment: {c:'#E89A3C', bg:'#FFF7EE', i:'out'}, journal: {c:'#9A7BFF', bg:'#F7F3FF', i:'book'}

### 3.3 VOUCH (lines 111–124) - Recent Vouchers
v1 (receipt): id v1, k:'receipt', t:'RCPT-0003', p:'Mehta Electricals', amt:25000, date:'26 Sep', syn:true, no:'RCPT-0003', go:'receipt', ref:'n12', time:'10 min ago'
v2 (sale): id v2, k:'sales', t:'BILL-0104', p:'Royal Mart', amt:42640, date:'25 Sep', syn:true, no:'BILL-0104', go:'sales', ref:'n14'
v3 (payment): id v3, k:'payment', t:'PAY-0007', p:'Kiran Steel', amt:48380, date:'23 Sep', syn:true, no:'PAY-0007', go:'payment', ref:'n13'
v4 (purchase): id v4, k:'purchase', t:'PBN-0058', p:'Kiran Steel', amt:38420, date:'22 Sep', syn:true, no:'PBN-0058', go:'purchase', ref:'n15'
v5 (sale): id v5, k:'sales', t:'BILL-0103', p:'Mehta Electricals', amt:18300, date:'21 Sep', syn:true, no:'BILL-0103', go:'sales'
v6 (journal): id v6, k:'journal', t:'JV-0005', p:'Adjustment', amt:6200, date:'20 Sep', syn:true, no:'JV-0005', go:'journal'

### 3.4 RECV/PAYB (lines 126–132) - Outstanding
RECV (To Get): 4 items - Royal Mart 42640 due 30 Sep, Mehta Electricals 18300 due 15 Oct, etc.
PAYB (To Pay): 2 items - Kiran Steel 48380 due 29 Sep, Prime Packaging 15040 due 10 Oct

### 3.5 PARTIES (lines 134–143)
8 parties: Mehta Electricals (cust, 43300 bal get), Royal Mart (cust, 42640), Apex Traders (cust, 9500), Sunita Rao (cust,0), Kiran Steel (sup,48380 give), Prime Packaging (sup,15040), Sharma Agencies (sup,0), Metro Hardware (sup,0)
Fields: id, n, t(c/s/both), mob, email, balGet, balGive, addr, gst

### 3.6 ITEMS (lines 145–155)
7 items: LED Bulb 9W (₹85, 4.5% GST, unit pc, stk 420), Copper Wire 1.5sq (₹32, 12%, m, 860), Switch Modular (₹65, 18%, pc, 240), PVC Pipe 1.5 (₹28, 18%, m, 520), Nut Bolt Set (₹12, 12%, box, 380), Packing Tape (₹24, 12%, roll, 620), Delivery Charge (₹0, 0%, svc, ∞)
Fields: id, n, r(rate), gst%, unit, stk(stock)


### 3.7 SALES9 (lines 157–165) - Sales Analytics
9 monthly sale data points for charts (Sep:124530, Aug:115240, etc.)
Fields: m (month), v (value), g (growth%)

### 3.8 LEDGERS (lines 167–176)
8 ledger accounts: Sales, Purchases, Cash in Hand, HDFC Bank, Petty Cash, Rent, Salaries, Electricity, Purchase Returns, Sales Returns, Print & Stationery, Freight & Cartage (12 actual)
Fields: id, n, g(group), t(c/d)

### 3.9 ACCOUNTS (lines 178–184) - Bank/Cash Accounts for payment mode
acct-cash: Cash in Hand, isCash:true
acct-hdfc: HDFC Bank - 4021
acct-icici: ICICI Bank - 8823  
acct-sbi: SBI - 1134
acct-neo: Neo Bank
acct-kotak: Kotak Mahindra
Fields: id, n, sub, cash

### 3.10 COMPANIES (lines 186–193)
5 companies: gi (GI Apr 25-26, default), gc (Global Corp), dt (DesignTech), sams (Samsung India), tcs (TCS)
Fields: id, n, t(trust name), tan, pan, gstin, fy

### 3.11 FT (lines 195–201) - Flow Type Config
5 flow types (sales, purchase, receipt, payment, journal) with cfg properties as documented in 2.8

### 3.12 MODES (lines 203–208) - Payment Modes
cash: Cash, sub 'Money in hand', i:'cash'
bank: Bank, sub 'Transfer/NEFT', i:'bank'
upi: UPI, sub 'GPay, PhonePe etc', i:'upi'
cheque: Cheque, sub 'By cheque', i:'cheque'
other: Other, sub 'Anything else', i:'dots'

### 3.13 FORM (lines 210–217) - Entry Form Init
f: {no:'', date:'2026-09-26', party:'', r:'', amt:'', payAmt:'', mode:'cash', acc:'acct-cash', bank:'', note:'', items:[], lines:[], dr:'', cr:''}
subtotal, gst, total computed

### 3.14 NOTIFS (lines 219–230) - 6 notifications
As documented in 2.4

### 3.15 ACTS (lines 232–241) - Activity Feed  
8-10 activity items with status, time, icon, type, navigation target

### 3.16 TEAM (lines 243–250)
4-5 team members: user 'U1', name 'workk72002', role 'Owner', initials 'RK', status 'active'
Others: Priya Shah (Sales Incharge, active), Arjun Mehta (Storekeeper, active), Sunita Rao (pending), Karan Bose (inactive)

### 3.17 WS (lines 252–257) - Workspaces
def (Default Home): builtin
sd (Sales Desk): builtin  
me (Month-end Closing): builtin

### 3.18 FAQS (lines 259–264)
5-6 FAQ questions/answers

### 3.19 REPORTS (lines 266–273)
6-8 report cards: Sales Summary, Purchase Summary, Party Outstanding, Item Movement, Cash Flow, P&L, GST Summary


## 4. LOCALSTORAGE & PERSISTENCE

### 4.1 Keys Used
- 'tc-liquid-pages-v2' - Widget layout per workspace (pages array with widget ordering)
- 'tc-liquid-tabs' - Tab order array
- 'tc-liquid-page-v2' - Current page index (per workspace)
- 'tc-liquid-pinned' - Pinned widgets list per workspace
- 'tc-liquid-lists' - List view preferences (order, hidden items, sort)
- 'tc-liquid-hidden-v2' - Hidden widgets per workspace/page
- 'tc-liquid-preset' - Saved layout preset
- 'tc-liquid-look' - Theme/accent customization
- 'tc-company' - Current active company
- 'tc-ws' - Active workspace

### 4.2 State Variables
loggedIn, tab, tabOrder, pages, pageIdx, pinned, hidden, listPrefs, preset, look
loggedState, user, wname, wsForm, wsShortcuts, wsSums
s (current screen), history, dir, extra, overlay, sheet, cmenu, toast
v (voucher view params), f (form data), step, editId
sDate, showPass, forgotSent, editing, dragKey, ghost, dragPage

### 4.3 Handlers
- doLogin() - sets loggedIn, navs home
- sendReset() - forgotSent
- go(s, extra) - push stack
- back() - pop stack
- jump(s) - direct nav
- selectTab(i) - switch tab, set pill animation
- startFlow(type) - init form for type
- next() / prev() - wizard nav
- saveFlow(draft) - save entry
- retry(id) - retry failed sync
- hide(key) / pin(key) / unpin(key) - widget management
- pageAdd() / pageDel() - liquid pages management
- lBegin/lMove/lEnd - list drag handlers
- openSheet(name) / closeSheet() - bottom sheet
- openMenu() / closeMenu() - drawer
- openCmenu(x, y, opts) / closeCmenu() - context menu
- openSearch() / closeSearch() - search
- openCompany() - company picker


## 5. COMPONENTS & WIDGETS

### 5.1 Core Reusable Components
- **Card** (.glass) - glass morphism card with gradient overlay, shadow
- **Tile** (.tap .gcard) - touchable card with hover/press states
- **ICO** (.ico) - icon container (sm/xs sizes), gradient bg, inset icon shape
- **I** (.i icon) - SVG icon (s/xs/l/xl/fat sizes)
- **Nav** (.nav) - header row (back/hamburger, title, actions)
- **CBtn** (.cbtn) - circular button (46px, sm=40px)
- **PBtn** (.pbtn) - pill button (46px height)
- **Row** (.row .mrow) - list row layouts
- **Num** (.num) - formatted number display
- **Badge** (.bdg) - status/type badge
- **SegCtrl** (.seg) - segmented control
- **Chip** (.chip) - filter chip
- **Sheet** (.sheet) - bottom sheet (slideL/up animation)
- **Menu/Drawer** (.drawer) - side menu (slideL)
- **Cmenu** (.cmenu) - context menu popup
- **Toast** (.toast) - toast notification
- **Empty** (.empty) - empty state placeholder
- **Fab** (.fab) - floating action button

### 5.2 Home Widget Components
- **NewEntryWidget** (.hero) - hero card with quick actions
- **MoneySummaryWidget** - 2x2 grid of SUMS
- **TileWidget** - icon+title+subtitle for each feature
- **Pager** - horizontal scroll-snap pager with dots
- **DragGhost** - floating widget during drag
- **HiddenSheet** - hidden widgets management sheet

### 5.3 Flow Components
- **Stepper** (.stepper) - step dots with labels
- **FormField** (.field) - labeled input
- **PartyPick** - party selector with add button
- **ItemLine** - item line editor (name, qty stepper, rate, amount, delete)
- **ItemPick** - item picker sheet
- **ModeSelector** - payment mode buttons
- **AccountPick** - bank/cash account selector
- **LedgerPick** - ledger account picker (journal)
- **DrCrLine** - journal line (side toggle, account, amount)
- **TotalBar** - totals display (sub, GST, total, paid, balance)
- **SummaryCard** (.sumcard) - check step summary

### 5.4 List Components
- **VoucherRow** - icon+party+no/date+amount
- **PartyRow** - avatar+name+balance
- **ItemRow** - name+rate+stock
- **ActRow** - icon+title+time+status
- **NotifRow** - icon+title+body+time
- **TeamRow** - avatar+name+role+status
- **ReportCard** - icon+title+sub


## 6. INTERACTIONS & ANIMATIONS

### 6.1 Touch Feedback
- .tap:active - scale(.955), 120ms
- .tap:hover - translateY(-2px) scale(1.02), shadow increase, icon lift
- .tap::after - glass sheen overlay on hover/active
- Ripple-like effect via ::after gradient

### 6.2 Screen Transitions
- inF: 30px from right, .42s cubic-bezier(.2,.85,.2,1)
- inB: 30px from left, .42s cubic-bezier(.2,.85,.2,1)
- up: bottom sheet slide up, .42s
- slideL: drawer slide from left, .42s
- fade: overlay fade .3s
- pop: toast/center popup, .3s with scale
- rise: search overlay, .3s with translateY

### 6.3 Nav Pill Animation
- Initial: width+left+scaleY(.84) in 200ms ease
- Spring: cubic-bezier(.26,1.55,.44,1) over 620ms
- Transitions left/width/top with spring physics

### 6.4 Widget Drag & Drop
- Long press to start drag (300ms dwell)
- Ghost widget follows pointer (position:fixed, transform translate)
- Original dims (opacity .3)
- Edge zones: 60px from left/right = auto-flip page after 600ms
- Drop zones highlight on hover
- Snap: widget animates to target position
- Page dots update on flip

### 6.5 List Drag (lBegin/lMove/lEnd)
- Drag handle appears on hover
- Row follows pointer, others shift up/down
- Auto-scroll near edges
- Drop position indicator (blue line)
- Reorder animation: gap animation 200ms

### 6.6 Context Menu (cmenu)
- Opens at tap position, with pop animation
- Items stack with 30ms stagger
- Tap outside closes (fade out .2s)
- Auto-reposition if near screen edge

### 6.7 Bottom Sheets
- Slide up from bottom (transform translateY(100%) to 0)
- Scrim fades in simultaneously
- .42s cubic-bezier(.2,.95,.25,1)
- Close: slide back down, .32s ease-in
- Sheets: Company picker, Item picker, Party picker, Account picker, Ledger picker, Hidden cards, Search results

### 6.8 Drawer
- Slide in from left, .42s cubic-bezier(.2,.95,.25,1)
- Scrim opacity 0 to .4
- Menu items have hover glow effect
- Body scroll locked

### 6.9 Context Animations
- Toast: pop from top (-16px, scale .94 to 1)
- Loading/Orb: drift 16s infinite alternate (translate+scale)
- Icons: hover bounce (translateY -2px, scale 1.07)
- Tab pill: spring with overshoot

### 6.10 Feedback
- Success: green accent + check icon
- Warning: orange accent + alert icon
- Error: red accent + x icon
- Info: blue accent + info icon
- Haptic-like: button press scale + shadow reduction

### 6.11 Empty States
- Icon in dashed circle
- Title (muted)
- Subtext (muted2)
- Optional action button

### 6.12 Loading/Sync States
- Status badge: 'Synced' (green), 'Waiting' (orange), 'Failed' (red)
- Animated dot pulse for live status
- Company bar: 'Tally Connected' with pulsing green dot
- 'Syncing...' with spinner when active

### 6.13 Skeleton/Shimmer
- Not explicitly present in prototype; loading simulated with static states


## 7. DESIGN TOKENS & STYLING

### 7.1 Color Palette (CSS vars from .root)
--acc: #8C1D3F (primary maroon)
--ink: #0E1B33 (text primary)
--ink2: #3F4B68 (text secondary)
--ink3: #58647F (text tertiary)
--gt: 255,255,255 (glass tint)
--navy: #1B2D5B (navy)
--navy2: #2A4584
--navy3: #172A55
--acc2: #A42A52 (accent hover)
--acc3: #6E1531 (accent dark)
--g: .6 (default glass opacity)

### 7.2 Glass Opacity Scale
g20, g30, g40, g50, g60, g70, g80, g90, g100 classes

### 7.3 Typography
- Font: 'Figtree', -apple-system, system-ui
- Weights: 400 (normal), 600 (semibold), 700 (bold), 800 (extrabold)
- Sizes: 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32

### 7.4 Spacing
- Screen padding: 28px top, 16px sides, 36px bottom
- Card gap: 10-12px
- Component padding: 12-16px
- Border radius: 12, 14, 16, 18, 20, 22, 23, 28px

### 7.5 Shadows
- Card: 0 14px 34px -16px rgba(27,45,91,.24)
- Icon: 0 8px 18px -9px rgba(27,45,91,.32)
- Hover: 0 20px 36px -16px rgba(27,45,91,.34)

### 7.6 Viewport
- Fixed 390×844 (iPhone 14 Pro)
- App fills viewport, overflow hidden
- Screens scroll individually

### 7.7 Wallpaper
- Wall gradient with orbs (drift animation)
- Light theme (default)
- Theme customizable via look sheet

### 7.8 Icon System
- Custom SVG paths (IC object)
- 22px base size, stroke-width 1.9
- Variants: s(18), xs(15), l(28), xl(34), fat(stroke 3.2)
- Stroke: currentColor, round caps/joins

### 7.9 Safe Areas
- Top: ~47px (status bar)
- Bottom: ~34px (home indicator)
- Screen padding accounts for these

### 7.10 Accent Customization
- Custom accent color picker in look sheet
- Accent applies to: primary buttons, active tab, links, icons
- Live preview of custom accent
- Reset to default option

---

## 8. KEY BEHAVIORS & INTERACTIONS

### 8.1 Login Flow
1. User enters username/email + password
2. Clicks 'Log In' -> doLogin()
3. Sets loggedIn=true, tab=0, navigates home
4. No validation (prototype always succeeds)

### 8.2 Entry Creation Flow
1. Tap 'New Entry' widget or tile
2. Choose type (Sale/Purchase/Money In/Money Out/Adjustment)
3. Wizard opens with step 0 (Details)
4. Fill required fields (no/date/party/amount)
5. Next to step 1 (Items for sales/purchase, or Payment for receipt/payment, or Accounts for journal)
6. Next to final step (Check/Summary)
7. Review entries
8. Save -> creates entry, returns to home
9. Entry appears in Activity with 'Waiting' status
10. After 5 seconds becomes 'Synced' (green)
11. Optional: Save as Draft

### 8.3 Widget Customization
1. Long press home screen to enter edit mode
2. Widgets lift, show drag handles
3. Drag to reorder or move to different page
4. Tap widget to open context menu
5. Choose Pin (moves to top), Hide (moves to hidden), or Open
6. Long press to add new page
7. Tap done to save layout

### 8.4 Liquid Pages
1. Horizontal swipe between pages
2. Page dots at bottom
3. Each page can have different widgets
4. Add/remove pages in edit mode
5. Drag widgets between pages
6. Page layout persists per workspace

### 8.5 Tab Reordering
1. Long press any bottom tab
2. Drag to new position
3. Pill animates to follow
4. Order persists in localStorage
5. Tap to switch (pill springs to target)

### 8.6 Context Menu (cmenu)
1. Long press or right-click any list item/widget
2. Context menu appears at tap position
3. Options: Open, Pin, Hide, Delete (context-dependent)
4. Tap outside to dismiss
5. Menu repositions near edges

### 8.7 Voucher List Drag
1. Hover over voucher row shows drag handle
2. Drag handle to reorder
3. Rows shift smoothly
4. Auto-scroll near top/bottom edges
5. New position saves immediately

### 8.8 Company Switching
1. Tap company bar on home
2. Bottom sheet opens with company list
3. Current company has checkmark
4. Tap different company to switch
5. 'Add company' option available
6. Company data reloads

### 8.9 Party Picker
1. Tap party field in entry form
2. Bottom sheet with party list + search
3. Filter by Customer/Supplier
4. '+' button to add new party inline
5. Tap party to select, sheet closes

### 8.10 Item Picker
1. Tap 'Add item' in sales/purchase flow
2. Bottom sheet with item list + search
3. Shows stock, rate, GST%
4. Tap item to add to form
5. Can add multiple items

### 8.11 Payment Mode Selection
1. In payment step, 5 mode buttons (Cash/Bank/UPI/Cheque/Other)
2. Selected mode highlighted
3. Mode determines account picker default
4. Non-cash modes show bank/ref fields
5. Account picker opens as bottom sheet

### 8.12 Journal Balance Validation
1. Dr/Cr cards show totals
2. If not matching: red warning, difference shown
3. Save disabled until balanced
4. Add/remove Dr/Cr lines
5. Toggle side per line

### 8.13 Notification Actions
1. Tap notification to mark read + navigate
2. Unread dot indicator
3. 'Mark all read' clears badges
4. Filter: All/Unread tabs

### 8.14 Search
1. Tap search icon on any screen
2. Full overlay with search field
3. Real-time filter across relevant data
4. Recent searches stored
5. Results grouped by type

### 8.15 Sync Status
1. Activity shows sync timeline
2. 'Waiting' -> 'Synced' after 5 seconds (simulated)
3. Failed entries can be retried
4. Company bar shows 'Synced X min ago'

### 8.16 Toasts
- Save confirmation: 'Saved. Sent to Tally.'
- Draft: 'Draft saved on this phone'
- Validation: 'Fill party and amount'
- Error: 'Something went wrong'
- Duration: 2.5 seconds, auto-dismiss

### 8.17 Bottom Sheet Interaction
1. Tap trigger to open
2. Sheet slides up from bottom
3. Scrim overlay, tap to dismiss
4. Sheet has handle bar (grabbable)
5. Content scrollable if overflow
6. Close button in header

### 8.18 Theme Customization (look)
1. Settings -> Appearance
2. Accent color grid (8 colors)
3. Custom color picker
4. Glass opacity slider (g20-g100)
5. Live preview card
6. Reset button
7. Saves to localStorage

---

## 9. VALIDATION RULES

### 9.1 Entry Form
- no: Required, auto-generated if empty
- date: Required
- party: Required for all types except journal
- amt: Required and > 0
- For sales/purchase with items: total computed from items
- For journal: drSum == crSum && > 0

### 9.2 Workspace
- name: Required, non-empty
- shortcuts: At least 1
- sums: At least 1
- Save disabled if validation fails

### 9.3 Company
- name: Required
- gstin: Must be 15 chars alphanumeric
- pan: Must be 10 chars
- tan: 4 chars

### 9.4 Item
- name: Required
- rate: Required, >= 0
- gst: 0-28%
- unit: Required
- stock: >= 0

### 9.5 Party
- name: Required
- type: c/s/both
- mobile: 10 digits
- email: Valid email format
- gstin: 15 chars

---

## 10. ACCESSIBILITY

### 10.1 Focus States
- .tap:focus-visible - 3px outline rgba(38,64,124,.45)
- .inp:focus-visible - 3px outline, offset 2px

### 10.2 ARIA Labels
- Icon buttons: aria-label with action name
- Form fields: aria-label with field name
- Tab buttons: role='tab', aria-selected
- Modal sheets: role='dialog', aria-modal

### 10.3 Tap Targets
- Minimum 44×44px
- Icon buttons: 46×46px
- List rows: min-height 56px
- Tab bar: 70px height

### 10.4 Screen Reader
- Buttons have descriptive labels
- Inputs have placeholder + label
- Status badges have text
- Images have alt text (icons)

---

## 11. BREAKPOINTS & RESPONSIVE

### 11.1 Primary Viewport
- Fixed 390×844 (iPhone 14 Pro)
- App does not scale with browser, maintains fixed dimensions

### 11.2 Overflow
- .scr: overflow-y auto, overflow-x hidden
- Scrollbar hidden (::-webkit-scrollbar display:none)
- Bottom padding 100px on tab screens (.scr.wt)
- Mask gradient at bottom for fade effect

### 11.3 Orientation
- Not explicitly handled, fixed portrait

---

## 12. ASSETS & ICONS

### 12.1 Icon System
- All icons are inline SVG paths (no external files)
- IC object maps icon names to path data
- 50+ icons defined
- Stroke-based design, 1.9px default

### 12.2 Logo
- Brand: 'TallyConnect' with split color (Tally=ink, Connect=acc)
- App mark: rupeeC icon in gradient circle

### 12.3 Avatars
- Initials-based circles with color
- Random pastel background
- 38px (xs), 44px (sm), 56px (default)

### 12.4 Fonts
- Figtree from Google Fonts
- Fallback: -apple-system, system-ui, sans-serif

### 12.5 Images
- No external images
- All visuals are CSS/SVG generated

---

## 13. ERROR & EDGE CASES

### 13.1 Empty States
- No vouchers: 'Nothing here yet'
- No parties: 'Add your first customer or supplier'
- No items: 'Create items to speed up billing'
- No notifications: 'You have read everything'
- No reports: 'Record some entries first'
- No outstanding: 'All clear! Nothing pending'

### 13.2 Error Messages
- Validation: 'Fill all required fields'
- Network: 'Cannot reach Tally. Check connection.'
- Sync fail: 'Could not send to Tally'
- Invalid GSTIN: 'Enter valid 15-character GSTIN'
- Invalid mobile: 'Enter 10-digit mobile number'

### 13.3 Confirm Dialogs
- Delete entry: 'Delete this entry? This cannot be undone.'
- Delete party: 'Remove this party?'
- Logout: 'Log out of TallyConnect?'
- Reset layout: 'Reset all pages to default?'

### 13.4 Success Toasts
- Entry saved: 'Saved. Sent to Tally.'
- Draft saved: 'Draft saved on this phone'
- Workspace created: 'Workspace created'
- Company added: 'Company connected'
- Item created: 'Item added'
- Party added: 'Party added'

---

## 14. KEYBOARD & INPUT

### 14.1 Supported Input Types
- text (default)
- email
- password (with toggle)
- number (amount, qty, rate)
- date (custom picker, not native)
- textarea (notes)

### 14.2 Input Behavior
- Auto-focus on first field
- Enter key moves to next field
- Tab order follows visual order
- Amount fields: numeric keyboard, decimal allowed
- Date fields: custom calendar picker
- Search: debounced real-time filter

### 14.3 Validation Feedback
- Border color changes on error
- Error text below field
- Shake animation on invalid submit
- Auto-scroll to first error

---

## 15. MODAL & OVERLAY STACKING

### 15.1 Z-Index Order (back to front)
1. Screen content: z 0
2. Bottom nav: z 50
3. Scrim/overlay: z 100
4. Bottom sheet: z 110
5. Context menu: z 120
6. Toast: z 200
7. Search overlay: z 150

### 15.2 Overlay Types
- Scrim (semi-transparent black, .4 opacity)
- Bottom sheet (glass, rounded top, handle)
- Context menu (pop, absolute position)
- Toast (top, glass, auto-dismiss)
- Search (full screen, glass)
- Confirm dialog (centered, glass, buttons)

### 15.3 Interaction Rules
- Only one overlay at a time
- Opening new closes previous
- Tap scrim dismisses
- ESC key closes (desktop)
- Back button closes overlay before screen

---

## 16. PERSISTENT STATE

### 16.1 Saved on Every Change
- Tab order
- Page layout (per workspace)
- Widget pin/hide state
- Active page index
- Active workspace
- Active company
- Theme/accent customization

### 16.2 Session Only (not persisted)
- Current screen + history stack
- Form data (entry wizard)
- Open overlays
- Search query
- Scroll position

### 16.3 Reset Options
- Reset layout (restores default pages/widgets)
- Reset all (clears localStorage)
- Logout (clears auth state only)

---

## 17. COMPONENT LIBRARY SUMMARY

### 17.1 Atoms
- I (icon)
- ICO (icon container)
- CBtn (circular button)
- PBtn (pill button)
- Chip
- Badge
- Dot
- Divider

### 17.2 Molecules
- Nav (header)
- Card (glass)
- Tile (touchable card)
- Row (list item)
- Field (input)
- SegCtrl (segmented control)
- Stepper (wizard steps)

### 17.3 Organisms
- Screen (page container)
- TabBar (bottom nav)
- Drawer (side menu)
- Sheet (bottom sheet)
- Cmenu (context menu)
- Toast (notification)
- Search (overlay)
- Pager (page carousel)
- Form (entry form)
- List (virtualized rows)

### 17.4 Templates
- LoginTemplate
- HomeTemplate (with widgets)
- FlowTemplate (wizard)
- ListTemplate (vouchers/parties/items)
- DetailTemplate (entry/bill/party)
- SettingsTemplate

---

## 18. KEY TECHNICAL NOTES FOR FLUTTER PORT

### 18.1 State Management
- Single state object with all app state
- React useState, no Redux/Context
- For Flutter: use ChangeNotifier/Provider or Riverpod

### 18.2 Navigation
- Custom stack (history array)
- No named routes, just screen key switch
- For Flutter: Navigator with custom PageTransitions, or custom stack

### 18.3 Persistence
- localStorage for all persistent state
- JSON.stringify/parse
- For Flutter: SharedPreferences or Hive

### 18.4 Animations
- CSS keyframes -> Flutter AnimationController + Tween
- cubic-bezier easing -> Curves.easeOutCubic etc
- Spring physics -> Curves.elasticOut

### 18.5 Icons
- SVG paths -> CustomPainter or flutter_svg package
- 50+ icons need to be recreated
- Stroke-based, scalable

### 18.6 Glass Morphism
- BackdropFilter (Flutter has built-in)
- Blur 26px, saturate 185%
- Border 1px rgba(255,255,255,.8)
- Border radius 22px

### 18.7 Gestures
- Tap, long press, drag, swipe
- Edge swipe for page flip
- Bottom sheet drag-to-dismiss
- Drawer swipe-to-open (edge)

### 18.8 Performance
- 60fps animations
- Lazy load large lists
- Memoize heavy computations
- Debounce search

---

## CRITICAL FILES REFERENCE

All paths relative to D:\Tallyconnect_UI\prototype\:

1. **TallyConnect_App_Source.jsx** (1167 lines) - Main logic
2. **app_prototype\app_index.html** (312KB) - Full UI/HTML
3. **app_prototype_markup.html** - Reference markup
4. **app_styles.css** - All styles
5. **TallyConnect_DesignLanguage_Source.jsx** - Design system
6. **design_language\design_index.html** - Design tokens
7. **Main.dc.html** - Alternate view
8. **page_1_02c14e41.html** - Page 1
9. **page_2_1670b517.html** - Page 2
10. **unpacked.html** - Unpacked version

---

Report generated. This covers all major aspects of the app for a 1:1 Flutter rebuild.

