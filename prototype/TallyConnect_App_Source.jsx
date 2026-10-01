
var IC = {
  home:'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z',
  rupeeC:'M12 2a10 10 0 1 0 0 20a10 10 0 1 0 0-20zM8.5 7.5h7M8.5 10.5h7M10.5 7.5c2.2 0 3.5 1.1 3.5 3s-1.3 3-3.5 3h-2l5 4.5',
  team:'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21v-1a6 6 0 0 1 12 0v1M16 3.2a4 4 0 0 1 0 7.6M22 21v-1a6 6 0 0 0-4-5.6',
  activity:'M3 12a9 9 0 1 0 2.6-6.4L3 8M3 3v5h5M12 7v5l3 2',
  chart:'M4 20h16M7 16v-5M12 16V6M17 16v-8',
  bag:'M5.5 8h13l-1 12.5h-11zM9 8V6.5a3 3 0 0 1 6 0V8M9.5 14l2 2 3.5-3.5',
  cart:'M3 4h2.2l2.3 11h10.3L20 8H6.3M9 20.5a1 1 0 1 0 0-2 1 1 0 0 0 0 2zM17 20.5a1 1 0 1 0 0-2 1 1 0 0 0 0 2z',
  person:'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.5 21a7.5 7.5 0 0 1 15 0',
  box:'M21 7.5 12 3 3 7.5v9L12 21l9-4.5zM3 7.5 12 12l9-4.5M12 12v9',
  gear:'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  receipt:'M6 2.5h12v19l-3-2-3 2-3-2-3 2zM9 7.5h6M9 11.5h6M9 15.5h3.5',
  in:'M12 3v11M7.5 9.5 12 14l4.5-4.5M4 15.5V18a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2.5',
  out:'M12 14V3M7.5 7.5 12 3l4.5 4.5M4 15.5V18a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2.5',
  book:'M5 4.5A2.5 2.5 0 0 1 7.5 2H19v17H7.5A2.5 2.5 0 0 0 5 21.5zM5 4.5v17M9 7h6M9 11h6',
  swap:'M4 8h15l-4-4M20 16H5l4 4',
  plus:'M12 5v14M5 12h14', minus:'M5 12h14',
  chevR:'M9 6l6 6-6 6', chevL:'M15 6l-6 6 6 6', chevD:'M6 9l6 6 6-6', chevU:'M6 15l6-6 6 6',
  arrow:'M5 12h14M13 6l6 6-6 6',
  menu:'M4 7h16M4 12h16M4 17h16',
  search:'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4',
  bell:'M6 8.5a6 6 0 0 1 12 0c0 6.5 2.5 8.5 2.5 8.5h-17S6 15 6 8.5M10.3 20.5a1.9 1.9 0 0 0 3.4 0',
  close:'M6 6l12 12M18 6 6 18', check:'M5 12.5 10 17.5 19 7',
  building:'M4 21V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v16M16 9h3a1 1 0 0 1 1 1v11M3 21h18M8 7h4M8 11h4M8 15h4',
  sync:'M20 11a8 8 0 0 0-14.9-3.5L4 9M4 4v5h5M4 13a8 8 0 0 0 14.9 3.5L20 15M20 20v-5h-5',
  trash:'M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3',
  lock:'M6 11h12v10H6zM8 11V7a4 4 0 0 1 8 0v4',
  mail:'M3.5 5.5h17v13h-17zM4 6.5l8 6.5 8-6.5',
  eye:'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  eyeOff:'M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3 3.9M6.6 6.6C3.9 8.4 2 12 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2',
  key:'M8 15.5a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7zM11.5 12H21M18 12v3M15 12v2',
  help:'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01',
  phone:'M5 3h4l2 5-2.5 1.5a11 11 0 0 0 6 6L16 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 5a2 2 0 0 1 2-2z',
  cash:'M2.5 6.5h19v11h-19zM12 14.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5zM6 10v4M18 10v4',
  bank:'M3 10 12 4l9 6M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20.5h18',
  upi:'M8 2h8a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zM13 6.5l-2.5 5.5h3.5L11.5 17.5',
  cheque:'M2.5 6h19v12h-19zM6 14h6M6 10h3M15.5 14h3',
  more:'M5 12h.01M12 12h.01M19 12h.01',
  dots:'M12 5.5v.01M12 12v.01M12 18.5v.01',
  calendar:'M4 6h16v15H4zM4 10.5h16M8 3v4M16 3v4',
  file:'M14 3H6v18h12V7zM14 3v4h4M9 13h6M9 17h6',
  share:'M12 3v12M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7',
  download:'M12 3v12M8 11l4 4 4-4M5 20h14',
  gift:'M4 11h16v10H4zM3 7.5h18V11H3zM12 7.5V21M12 7.5S11 3.5 8 3.5a2 2 0 0 0 0 4zM12 7.5s1-4 4-4a2 2 0 0 1 0 4z',
  card:'M3 6h18v12H3zM3 10h18M7 15h3',
  grid:'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z',
  sort:'M4 6h10M4 12h7M4 18h4M17 5v14M14 16l3 3 3-3',
  edit:'M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4',
  send:'M21 3 3 10.5l7 3 3 7.5zM10 13.5 21 3',
  chat:'M4 20l1.3-4A8 8 0 1 1 8 19z',
  trophy:'M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3',
  pie:'M21 12A9 9 0 1 1 12 3v9zM15 3.5A9 9 0 0 1 20.5 9H15z',
  userPlus:'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21a7 7 0 0 1 14 0M19 8v6M16 11h6',
  scan:'M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M7 12h10',
  info:'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 11v6M12 7.5h.01',
  logout:'M9 21H5V3h4M16 17l5-5-5-5M21 12H9',
  note:'M5 3h14v18H5zM8 8h8M8 12h8M8 16h5',
  laptop:'M5 5h14v10H5zM3 19h18',
  hash:'M5 9h14M5 15h14M10 3 8 21M16 3l-2 18',
  star:'M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3l-5.5 2.9 1-6.2L3 9.6l6.2-.9z',
  clock:'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 7v5l3 2',
  shield:'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z',
  xCircle:'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM9 9l6 6M15 9l-6 6',
  pin:'M9 3h6l-1 6 4 3v2h-5v7l-1 1-1-1v-7H5v-2l4-3z',
  move:'M12 3v18M3 12h18M12 3 9.5 5.5M12 3l2.5 2.5M12 21l-2.5-2.5M12 21l2.5-2.5M3 12l2.5-2.5M3 12l2.5 2.5M21 12l-2.5-2.5M21 12l-2.5 2.5',
  open:'M7 17 17 7M9 7h8v8',
  drop:'M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z',
  upload:'M12 16V4M7 9l5-5 5 5M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3'
};
var C = { sales:'var(--c-sales)', purchase:'var(--c-purchase)', receipt:'var(--c-receipt)', payment:'var(--c-payment)', journal:'var(--c-journal)', contra:'var(--c-contra)', items:'var(--c-items)', party:'var(--c-party)', vouchers:'var(--c-vouchers)', outstanding:'var(--c-outstanding)', reports:'var(--c-reports)', settings:'var(--c-settings)', team:'var(--c-team)', activity:'var(--c-activity)', navy:'var(--navy)', acc:'var(--acc)' };

function inr(n){ n = Number(n)||0; var neg = n<0; n = Math.round(Math.abs(n)); var s = String(n); var last3 = s.slice(-3), rest = s.slice(0,-3); if(rest){ rest = rest.replace(/\B(?=(\d{2})+(?!\d))/g, ','); } return (neg?'−':'')+'₹'+(rest?rest+','+last3:last3); }
function inr2(n){ n = Number(n)||0; var f = n.toFixed(2); var p = f.split('.'); return inr(Number(p[0])).replace('₹','₹')+'.'+p[1]; }
var MON = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function fdate(s){ if(!s) return '—'; var p = String(s).split('-'); if(p.length<3) return s; return p[2]+' '+MON[Number(p[1])-1]+' '+p[0]; }
function initials(n){ return String(n||'?').trim().charAt(0).toUpperCase(); }

var TABS = [ {k:'home', t:'Home', ic:'home'}, {k:'outHub', t:'Dues', ic:'rupeeC'}, {k:'team', t:'Team', ic:'team'}, {k:'activity', t:'Activity', ic:'activity'}, {k:'reports', t:'Reports', ic:'chart'} ];
var NO_TAB = ['login','forgot','flow','createWs','manageWs','billDetail','partyDetail','actDetail','entryDetail','newEntry'];
var FLOWLIKE = ['flow','createWs','manageWs','billDetail','partyDetail','entryDetail'];
var TITLES = { home:'Home', notifs:'Alerts', createWs:'Workspace', manageWs:'Workspaces', newEntry:'New Entry', flow:'Entry', vHub:'Vouchers', vList:'Vouchers', entryDetail:'Entry', outHub:'Dues', outList:'Dues', billDetail:'Bill', items:'Items', party:'Party', partyDetail:'Party', reports:'Reports', report:'Reports', activity:'Activity', actDetail:'Activity', team:'Team', settings:'Settings', companies:'Companies', billing:'Plans', refer:'Refer', help:'Help', login:'Log in', forgot:'Log in' };

var T = {
  items:{t:'Items', s:'Stock', ic:'box', c:C.items, to:'items'},
  party:{t:'Party', s:'Customers', ic:'person', c:C.party, to:'party'},
  vouchers:{t:'Vouchers', s:'All entries', ic:'receipt', c:C.vouchers, to:'vHub'},
  outstanding:{t:'Outstanding', s:'Money due', ic:'rupeeC', c:C.outstanding, to:'outHub'},
  reports:{t:'Reports', s:'Insights', ic:'chart', c:C.reports, to:'reports'},
  settings:{t:'Settings', s:'App setup', ic:'gear', c:C.settings, to:'settings'},
  sales:{t:'Sales', s:'New sale', ic:'bag', c:C.sales, flow:'sales'},
  purchase:{t:'Purchase', s:'New purchase', ic:'cart', c:C.purchase, flow:'purchase'},
  moneyIn:{t:'Money In', s:'Receipt', ic:'in', c:C.receipt, flow:'receipt'},
  moneyOut:{t:'Money Out', s:'Payment', ic:'out', c:C.payment, flow:'payment'}
};
var SUMS = {
  toGet:{t:'To get', s:'Others owe you', v:348690, ic:'in', c:C.receipt, cls:'amt in', go:['outList',{outKind:'recv',outFilter:'all'}]},
  toGive:{t:'To give', s:'You owe others', v:126850, ic:'out', c:C.payment, cls:'amt out', go:['outList',{outKind:'pay',outFilter:'all'}]},
  mIn:{t:'Money in', s:'This month', v:215000, ic:'in', c:C.receipt, cls:'amt', go:['vList',{vFilter:'receipt',vPeriod:'month'}]},
  mOut:{t:'Money out', s:'This month', v:98450, ic:'out', c:C.payment, cls:'amt', go:['vList',{vFilter:'payment',vPeriod:'month'}]},
  sales:{t:'Total sales', s:'This month', v:348690, ic:'bag', c:C.sales, cls:'amt', go:['vList',{vFilter:'sales',vPeriod:'month'}]},
  purch:{t:'Total purchase', s:'This month', v:126850, ic:'cart', c:C.purchase, cls:'amt', go:['vList',{vFilter:'purchase',vPeriod:'month'}]},
  cash:{t:'Cash in hand', s:'Cash balance', v:42300, ic:'cash', c:C.navy, cls:'amt', go:['vList',{vFilter:'contra',vPeriod:'month'}]},
  bank:{t:'Bank balance', s:'All banks', v:386900, ic:'bank', c:C.navy, cls:'amt', go:['vList',{vFilter:'contra',vPeriod:'month'}]}
};
var KIND = {
  sales:{t:'Sale', long:'Sale (Sales)', ic:'bag', c:C.sales, sign:1},
  purchase:{t:'Purchase', long:'Purchase', ic:'cart', c:C.purchase, sign:-1},
  receipt:{t:'Money In', long:'Money In (Receipt)', ic:'in', c:C.receipt, sign:1},
  payment:{t:'Money Out', long:'Money Out (Payment)', ic:'out', c:C.payment, sign:-1},
  journal:{t:'Adjustment', long:'Adjustment (Journal)', ic:'book', c:C.journal, sign:0},
  contra:{t:'Bank ↔ Cash', long:'Bank ↔ Cash (Contra)', ic:'swap', c:C.contra, sign:0}
};
var VOUCH = [
  {kind:'sales', party:'Mehta Electricals', no:'Sales 10', day:24, amt:84960},
  {kind:'sales', party:'Shree Balaji Traders', no:'Sales 9', day:21, amt:112100},
  {kind:'sales', party:'Om Sai Electricals', no:'Sales 8', day:17, amt:12980},
  {kind:'sales', party:'Patel Traders', no:'Sales 7', day:12, amt:24780},
  {kind:'sales', party:'Gupta Hardware Stores', no:'Sales 6', day:8, amt:68440},
  {kind:'sales', party:'Sai Enterprises', no:'Sales 5', day:3, amt:45430},
  {kind:'purchase', party:'Kiran Steel Industries', no:'PI-0005', day:23, amt:48380},
  {kind:'purchase', party:'Havells India Ltd', no:'PI-0004', day:19, amt:36580},
  {kind:'purchase', party:'Polycab Wires Pvt Ltd', no:'PI-0003', day:14, amt:24190},
  {kind:'purchase', party:'Anchor Electricals', no:'PI-0002', day:9, amt:11800},
  {kind:'purchase', party:'Finolex Cables', no:'PI-0001', day:2, amt:5900},
  {kind:'receipt', party:'Mehta Electricals', no:'RCT-0003', day:26, amt:25000},
  {kind:'receipt', party:'Gupta Hardware Stores', no:'RCT-0002', day:18, amt:125000},
  {kind:'receipt', party:'Patel Traders', no:'RCT-0001', day:5, amt:65000},
  {kind:'payment', party:'Kiran Steel Industries', no:'PAY-0003', day:22, amt:52000},
  {kind:'payment', party:'Havells India Ltd', no:'PAY-0002', day:15, amt:38000},
  {kind:'payment', party:'Mahalaxmi Transport', no:'PAY-0001', day:3, amt:8450},
  {kind:'journal', party:'Depreciation A/c', no:'JV-0002', day:25, amt:24500},
  {kind:'journal', party:'Rent A/c', no:'JV-0001', day:10, amt:35000},
  {kind:'contra', party:'Cash → HDFC Bank', no:'CN-0002', day:20, amt:50000},
  {kind:'contra', party:'ICICI Bank → Cash', no:'CN-0001', day:6, amt:20000}
];
var RECV = [
  {party:'Shree Balaji Traders', no:'Sales 9', bill:'21 Sep 2026', due:'06 Oct 2026', credit:'15 days', amt:112100, st:'ok', txt:'Due in 10 days', city:'Mumbai'},
  {party:'Mehta Electricals', no:'Sales 10', bill:'24 Sep 2026', due:'24 Oct 2026', credit:'30 days', amt:84960, st:'ok', txt:'Due in 28 days', city:'Pune'},
  {party:'Gupta Hardware Stores', no:'Sales 6', bill:'08 Sep 2026', due:'14 Sep 2026', credit:'6 days', amt:68440, st:'late', txt:'12 days late', city:'Jaipur'},
  {party:'Sai Enterprises', no:'Sales 5', bill:'03 Sep 2026', due:'08 Sep 2026', credit:'5 days', amt:45430, st:'late', txt:'18 days late', city:'Nashik'},
  {party:'Patel Traders', no:'Sales 7', bill:'12 Sep 2026', due:'27 Sep 2026', credit:'15 days', amt:24780, st:'soon', txt:'Due tomorrow', city:'Surat'},
  {party:'Om Sai Electricals', no:'Sales 8', bill:'17 Sep 2026', due:'02 Oct 2026', credit:'15 days', amt:12980, st:'soon', txt:'Due in 6 days', city:'Thane'}
];
var PAYB = [
  {party:'Kiran Steel Industries', no:'PI-0005', bill:'23 Sep 2026', due:'29 Sep 2026', credit:'6 days', amt:48380, st:'soon', txt:'Due in 3 days', city:'Ludhiana'},
  {party:'Havells India Ltd', no:'PI-0004', bill:'19 Sep 2026', due:'19 Oct 2026', credit:'30 days', amt:36580, st:'ok', txt:'Due in 23 days', city:'Noida'},
  {party:'Polycab Wires Pvt Ltd', no:'PI-0003', bill:'14 Sep 2026', due:'30 Sep 2026', credit:'16 days', amt:24190, st:'soon', txt:'Due in 4 days', city:'Mumbai'},
  {party:'Anchor Electricals', no:'PI-0002', bill:'09 Sep 2026', due:'21 Sep 2026', credit:'12 days', amt:11800, st:'late', txt:'5 days late', city:'Mumbai'},
  {party:'Finolex Cables', no:'PI-0001', bill:'02 Sep 2026', due:'16 Sep 2026', credit:'14 days', amt:5900, st:'late', txt:'10 days late', city:'Pune'}
];
var PARTIES = [
  {name:'Shree Balaji Traders', type:'c', city:'Mumbai', bal:112100},
  {name:'Mehta Electricals', type:'c', city:'Pune', bal:84960},
  {name:'Gupta Hardware Stores', type:'c', city:'Jaipur', bal:68440},
  {name:'Kiran Steel Industries', type:'s', city:'Ludhiana', bal:48380},
  {name:'Sai Enterprises', type:'c', city:'Nashik', bal:45430},
  {name:'Havells India Ltd', type:'s', city:'Noida', bal:36580},
  {name:'Patel Traders', type:'c', city:'Surat', bal:24780},
  {name:'Polycab Wires Pvt Ltd', type:'s', city:'Mumbai', bal:24190},
  {name:'Om Sai Electricals', type:'c', city:'Thane', bal:12980},
  {name:'Anchor Electricals', type:'s', city:'Mumbai', bal:11800},
  {name:'Finolex Cables', type:'s', city:'Pune', bal:5900},
  {name:'Mahalaxmi Transport', type:'s', city:'Mumbai', bal:0},
  {name:'Rajesh Hardware', type:'c', city:'Mumbai', bal:0},
  {name:'Laxmi Traders', type:'c', city:'Vapi', bal:0}
];
var ITEMS = [
  {name:'Havells FR Wire 1.5 sq mm (90 m)', stock:48, unit:'coil', rate:1850, st:'ok'},
  {name:'Polycab FR Wire 1.0 sq mm (90 m)', stock:36, unit:'coil', rate:1600, st:'ok'},
  {name:'Polycab LED Panel 18W', stock:120, unit:'pcs', rate:520, st:'ok'},
  {name:'Anchor Roma Switch 6A', stock:850, unit:'pcs', rate:34, st:'ok'},
  {name:'Havells MCB 32A DP', stock:8, unit:'pcs', rate:620, st:'low'},
  {name:'Crompton Ceiling Fan 1200 mm', stock:1, unit:'pcs', rate:3100, st:'low'},
  {name:'Supreme PVC Pipe 1 inch', stock:0, unit:'pcs', rate:85, st:'out'},
  {name:'Anchor Roma Socket 16A', stock:0, unit:'pcs', rate:96, st:'out'}
];
var SALES9 = [
  {name:'Polycab FR Wire 1.0 sq mm (90 m)', hsn:'8544', qty:'30 coil', rate:'₹1,600', amt:48000},
  {name:'Havells MCB 32A DP', hsn:'8536', qty:'40 pcs', rate:'₹620', amt:24800},
  {name:'Polycab LED Panel 18W', hsn:'9405', qty:'42 pcs', rate:'₹528.57', amt:22200}
];
var LEDGERS = [
  {t:'Salaries A/c', s:'Indirect Expenses'}, {t:'Salary Payable', s:'Current Liabilities'}, {t:'Rent A/c', s:'Indirect Expenses'},
  {t:'Depreciation A/c', s:'Indirect Expenses'}, {t:'Office Expenses A/c', s:'Indirect Expenses'}, {t:'Freight Charges', s:'Direct Expenses'}
];
var ACCOUNTS = [ {t:'HDFC Bank – Current', s:'Bank account'}, {t:'ICICI Bank – Current', s:'Bank account'}, {t:'Cash in hand', s:'Cash'} ];
var COMPANIES = [
  {id:'rs', name:'Rajlaxmi Solutions Private Limited - (From 1-Apr-2016)', sub:'Tally company · synced yesterday'},
  {id:'gi', name:'GI Apr 25-26', sub:'Tally company · synced 10:32 AM'},
  {id:'av', name:'Averlon3', sub:'Tally company · synced 22 Sep'}
];
var FT = {
  sales:{title:'New Sale', sub:'Sales bill', ic:'bag', c:C.sales, steps:['Details','Items','Payment','Check'], p:'s', partyLabel:'Customer', list:'c', items:true, noLabel:'Bill no.', amtLabel:'Money received now', balLabel:'Still to get', draft:true},
  purchase:{title:'New Purchase', sub:'Purchase bill', ic:'cart', c:C.purchase, steps:['Details','Items','Payment','Check'], p:'p', partyLabel:'Supplier (you bought from)', list:'s', items:true, noLabel:'Bill no.', amtLabel:'Money paid now', balLabel:'Still to pay', draft:true},
  receipt:{title:'Money In', sub:'Receipt', ic:'in', c:C.receipt, steps:['Details','How paid','Check'], p:'r', partyLabel:'Received from', list:'c', noLabel:'Receipt no.', amtLabel:'Amount received', accLabel:'Put money into'},
  payment:{title:'Money Out', sub:'Payment', ic:'out', c:C.payment, steps:['Details','How paid','Check'], p:'y', partyLabel:'Paid to', list:'s', noLabel:'Payment no.', amtLabel:'Amount paid', accLabel:'Paid from'},
  journal:{title:'Adjustment', sub:'Journal entry', ic:'book', c:C.journal, steps:['Details','Accounts','Check'], p:'j', partyLabel:'Main account', noLabel:'Entry no.'}
};
var MODES = [ {id:'cash', t:'Cash', ic:'cash'}, {id:'bank', t:'Bank', ic:'bank'}, {id:'upi', t:'UPI', ic:'upi'}, {id:'cheque', t:'Cheque', ic:'cheque'}, {id:'other', t:'Other', ic:'more'} ];
var FORM = {
  user:'', pass:'', fEmail:'', q:'', pq:'', pickQ:'', itemQ:'', partyQ:'', teamQ:'', wsName:'',
  sNo:'11', sDate:'2026-09-26', sParty:'Om Sai Electricals', sDue:'2026-10-11', sNote:'Order by phone – deliver today', sAmt:'5000', sPayNote:'Balance on 15-day credit',
  pNo:'PI-0006', pDate:'2026-09-26', pParty:'Polycab Wires Pvt Ltd', pSupInv:'PWPL/2627/0891', pDue:'2026-10-11', pNote:'Monthly stock refill', pAmt:'14160', pPayNote:'Paid in full',
  rNo:'RCT-0004', rDate:'2026-09-26', rParty:'Shree Balaji Traders', rAmt:'50000', rRef:'Against Sales 9', rNote:'Part payment by NEFT', rBank:'HDFC Bank', rUtr:'NEFT UTR HDFCN26269123', rAcc:'HDFC Bank – Current',
  yNo:'PAY-0004', yDate:'2026-09-26', yParty:'Havells India Ltd', yAmt:'36580', yRef:'Against PI-0004', yNote:'Full payment for MCB order', yBank:'ICICI Bank', yUtr:'RTGS ICICR52026092600417', yAcc:'ICICI Bank – Current',
  jNo:'JV-0003', jDate:'2026-09-26', jParty:'Salaries A/c', jNote:'Salary provision for September 2026',
  niName:'Supreme PVC Pipe 1 inch', niHsn:'', niDisc:'0', niQty:'1', niRate:'',
  iEmail:'', nuName:'', nuPhone:'', npName:'', npPhone:'', npCity:''
};
var NOTIFS = [
  {id:'n1', t:'Payment received', b:'₹25,000 from Mehta Electricals was saved as Money In RCT-0003.', time:'10 min ago', ic:'in', c:C.receipt, unread:true, go:['vList',{vFilter:'receipt',vPeriod:'month'}]},
  {id:'n2', t:'Sent to Tally', b:'12 entries from the app reached Tally for GI Apr 25-26.', time:'1 hr ago', ic:'sync', c:C.activity, unread:true, go:'activity'},
  {id:'n3', t:'Invite accepted', b:'Priya Shah joined your sales team.', time:'Yesterday', ic:'team', c:C.team, unread:true, go:'team'},
  {id:'n4', t:'Payment due soon', b:'₹48,380 to Kiran Steel Industries is due on 29 Sep.', time:'Yesterday', ic:'out', c:C.payment, unread:false, go:['outList',{outKind:'pay',outFilter:'all'}]},
  {id:'n5', t:'New join request', b:'Sunita Rao asked to join your team as Sales Rep.', time:'23 Sep', ic:'userPlus', c:C.party, unread:false, go:'team'},
  {id:'n6', t:'Plan renewal', b:'Your Enterprise plan renews on 31 Mar 2027.', time:'20 Sep', ic:'card', c:C.acc, unread:false, go:'billing'}
];
var ACTS = [
  {id:'a1', kind:'receipt', no:'RCT-0004', party:'Shree Balaji Traders', amt:50000, time:'11:05 AM', status:'fail', note:'Tally was closed on RAJESH-PC'},
  {id:'a2', kind:'sales', no:'Sales 11', party:'Om Sai Electricals', amt:14514, time:'10:58 AM', status:'wait'},
  {id:'a3', kind:'purchase', no:'PI-0006', party:'Polycab Wires Pvt Ltd', amt:14160, time:'10:51 AM', status:'wait'},
  {id:'a4', kind:'receipt', no:'RCT-0003', party:'Mehta Electricals', amt:25000, time:'10:32 AM', status:'ok'},
  {id:'a5', kind:'journal', no:'JV-0002', party:'Depreciation A/c', amt:24500, time:'25 Sep', status:'ok'},
  {id:'a6', kind:'sales', no:'Sales 10', party:'Mehta Electricals', amt:84960, time:'24 Sep', status:'ok'},
  {id:'a7', kind:'purchase', no:'PI-0005', party:'Kiran Steel Industries', amt:48380, time:'23 Sep', status:'ok'},
  {id:'a8', kind:'payment', no:'PAY-0003', party:'Kiran Steel Industries', amt:52000, time:'22 Sep', status:'ok'},
  {id:'a9', kind:'sales', no:'Sales 9', party:'Shree Balaji Traders', amt:112100, time:'21 Sep', status:'ok'},
  {id:'a10', kind:'contra', no:'CN-0002', party:'Cash → HDFC Bank', amt:50000, time:'20 Sep', status:'ok'}
];
var TEAM = [
  {id:'t1', name:'workk72002', email:'workk72002@gmail.com', role:'Sales Rep · Mumbai', st:'active'},
  {id:'t2', name:'Priya Shah', email:'priya.shah@example.com', role:'Sales Rep · Pune', st:'active'},
  {id:'t3', name:'Sunita Rao', email:'sunita.rao@example.com', role:'Sales Rep', st:'pending'},
  {id:'t4', name:'Amit Verma', email:'amit.verma@example.com', role:'Sales Rep · Jaipur', st:'off'}
];
var WS = [
  {id:'def', name:'Default Home', builtin:true, feats:['items','party','vouchers','outstanding','reports','settings'], sums:['toGet','toGive','mIn','mOut']},
  {id:'sd', name:'Sales Desk', feats:['sales','moneyIn','party','vouchers','outstanding','reports'], sums:['toGet','sales','mIn','cash']},
  {id:'me', name:'Month-end Closing', feats:['moneyOut','purchase','vouchers','outstanding','reports','settings'], sums:['cash','bank','toGive','mOut']}
];
var FAQS = [
  {q:'What is TallyConnect?', a:'TallyConnect is a mobile and web app that connects with your Tally ERP 9 / TallyPrime. Business owners, sales people and accountants can see reports, check party balances, look at stock and make entries from the phone.'},
  {q:'How do entries reach Tally?', a:'The TallyConnect app on your office computer sends new entries to Tally and brings back updates by itself, whenever Tally is open. You can see each entry in Activity.'},
  {q:'Is my data safe?', a:'Only people you add to your team can see your company data. [Add your security and data-storage details here.]'},
  {q:'Can I use more than one company?', a:'Yes. Tap the company name at the top of Home and pick another company.'}
];
var REPORTS = [
  {id:'top', cat:'sales', t:'Top customers', s:'Top 5 by money owed', ic:'trophy', c:C.acc},
  {id:'exp', cat:'accounts', t:'Expenses', s:'Direct and indirect', ic:'pie', c:C.payment},
  {id:'inC', cat:'party', t:'Quiet customers', s:'No sale in 60 days', ic:'person', c:C.party},
  {id:'inI', cat:'stock', t:'Items not moving', s:'Finished or not sold', ic:'box', c:C.items},
  {id:'day', cat:'accounts', t:'Day Book', s:'Every entry, day by day', ic:'calendar', c:C.navy},
  {id:'sreg', cat:'sales', t:'Sales list', s:'All sales this month', ic:'bag', c:C.sales},
  {id:'preg', cat:'accounts', t:'Purchase list', s:'All purchases this month', ic:'cart', c:C.purchase},
  {id:'stock', cat:'stock', t:'Stock summary', s:'Value of all items', ic:'box', c:C.items}
];

function loadJ(k, d){ try { var v = JSON.parse(window.localStorage.getItem(k) || 'null'); return (v===null || v===undefined) ? d : v; } catch(e){ return d; } }
function saveJ(k, v){ try { window.localStorage.setItem(k, JSON.stringify(v)); } catch(e){} }
function loadPages(){ var v = loadJ('tc-liquid-pages-v2', {}); return (v && typeof v==='object' && !Array.isArray(v)) ? v : {}; }
function savePages(v){ saveJ('tc-liquid-pages-v2', v); }
function loadOrder(){ var v = loadJ('tc-liquid-tabs', null); if(Array.isArray(v) && v.length===5 && [0,1,2,3,4].every(function(i){ return v.indexOf(i)>=0; })) return v; return [0,1,2,3,4]; }
var THEMES = [ {k:'aurora', t:'Aurora', a:'#8C1D3F', n:'var(--navy)'}, {k:'ocean', t:'Ocean', a:'#0B6A8F', n:'#133A63'}, {k:'emerald', t:'Emerald', a:'#0E7159', n:'#16423C'}, {k:'royal', t:'Royal', a:'#5A3DBF', n:'#26235F'}, {k:'terracotta', t:'Terracotta', a:'#A2462A', n:'#3A2C4A'}, {k:'graphite', t:'Graphite', a:'#3E4C63', n:'#1E2635'} ];
var LOOKS = [ {k:'aurora', t:'Aurora', s:'Maroon & navy · misty blue'}, {k:'ocean', t:'Ocean Breeze', s:'Calm blues'}, {k:'royal', t:'Royal Silk', s:'Violet on silk waves'}, {k:'sunrise', t:'Sunrise Clay', s:'Warm terracotta'}, {k:'mint', t:'Mint Ledger', s:'Fresh greens'}, {k:'pearl', t:'Pearl Graphite', s:'Quiet neutrals'}, {k:'prism', t:'Prism Indigo', s:'Soft rainbow glass'}, {k:'rose', t:'Rose Quartz', s:'Rose on lavender'} ];
var ACCENTS = [{k:'maroon', t:'Maroon', a:'#8C1D3F', b:'#6E1531', n:'#4A1428'}, {k:'berry', t:'Berry', a:'#A0306A', b:'#7C2352', n:'#4E1838'}, {k:'violet', t:'Violet', a:'#6D3FC4', b:'#5530A0', n:'#2E1F5E'}, {k:'indigo', t:'Indigo', a:'#4338CA', b:'#312A9E', n:'#1E1B4B'}, {k:'blue', t:'Royal Blue', a:'#1D4ED8', b:'#1A3FAE', n:'#172554'}, {k:'ocean', t:'Ocean', a:'#0B6A8F', b:'#07506D', n:'#133A63'}, {k:'teal', t:'Teal', a:'#0F766E', b:'#0B5953', n:'#133F3C'}, {k:'emerald', t:'Emerald', a:'#0E7159', b:'#0A5443', n:'#16423C'}, {k:'bronze', t:'Bronze', a:'#9A5B04', b:'#7A4703', n:'#3D2A12'}, {k:'terracotta', t:'Terracotta', a:'#A2462A', b:'#7E331C', n:'#4A2418'}, {k:'graphite', t:'Graphite', a:'#3E4C63', b:'#2B3647', n:'#1E2635'}];
ACCENTS = ACCENTS.concat([{k:'slate', t:'Slate', a:'#334E68', b:'#243B53', n:'#102A43'}, {k:'plum', t:'Plum', a:'#7A2E7A', b:'#5E215E', n:'#3A1638'}, {k:'clayrose', t:'Clay Rose', a:'#A0405A', b:'#7E2E44', n:'#4A1E2A'}, {k:'cocoa', t:'Cocoa', a:'#6B4A3A', b:'#52372A', n:'#2F2019'}, {k:'olive', t:'Olive', a:'#5F6B2E', b:'#4A5423', n:'#2A3014'}, {k:'forest', t:'Forest', a:'#2F6B3A', b:'#22522B', n:'#173320'}]);
var LOOKACC = { aurora:['berry','indigo','blue','graphite'], ocean:['blue','teal','slate','indigo'], royal:['indigo','berry','plum','graphite'], sunrise:['bronze','clayrose','cocoa','olive'], mint:['teal','forest','ocean','graphite'], pearl:['slate','blue','maroon','emerald'], prism:['violet','blue','berry','teal'], rose:['plum','maroon','violet','clayrose'] };
var LOOKSIG = { aurora:['Maroon','#8C1D3F','#6E1531'], ocean:['Ocean','#0B6A8F','#07506D'], royal:['Royal Violet','#5A3DBF','#43299A'], sunrise:['Terracotta','#A2462A','#7E331C'], mint:['Emerald','#0E7159','#0A5443'], pearl:['Graphite','#3E4C63','#2B3647'], prism:['Indigo','#4338CA','#312A9E'], rose:['Rose','#A0306A','#7C2352'] };
function clampN(x,a,b){ return Math.max(a, Math.min(b, x)); }
function hsl2rgb(h,s,l){ h=((h%360)+360)%360; s/=100; l/=100; var c=(1-Math.abs(2*l-1))*s, x=c*(1-Math.abs((h/60)%2-1)), m=l-c/2, r=0,g=0,b=0;
  if(h<60){r=c;g=x;} else if(h<120){r=x;g=c;} else if(h<180){g=c;b=x;} else if(h<240){g=x;b=c;} else if(h<300){r=x;b=c;} else {r=c;b=x;}
  return [(r+m)*255,(g+m)*255,(b+m)*255]; }
function rgb2hex(a){ return '#'+a.map(function(v){ return ('0'+Math.round(clampN(v,0,255)).toString(16)).slice(-2); }).join('').toUpperCase(); }
function hslx(h,s,l){ return rgb2hex(hsl2rgb(h,s,l)); }
function hex2rgb(h){ h=String(h||'').replace('#',''); if(h.length===3) h=h.split('').map(function(c){ return c+c; }).join(''); var n=parseInt(h,16)||0; return [(n>>16)&255,(n>>8)&255,n&255]; }
function rgb2hsl(a){ var r=a[0]/255,g=a[1]/255,b=a[2]/255, mx=Math.max(r,g,b), mn=Math.min(r,g,b), l=(mx+mn)/2, h=0, s=0, d=mx-mn;
  if(d){ s = l>.5 ? d/(2-mx-mn) : d/(mx+mn); h = mx===r ? ((g-b)/d + (g<b?6:0)) : mx===g ? (b-r)/d+2 : (r-g)/d+4; h*=60; }
  return [h, s*100, l*100]; }
function hsv2hex(h,s,v){ s/=100; v/=100; var f=function(n){ var k=(n+h/60)%6; return v - v*s*Math.max(0, Math.min(k, 4-k, 1)); }; return rgb2hex([f(5)*255, f(3)*255, f(1)*255]); }
function hex2hsv(hex){ var a=hex2rgb(hex), r=a[0]/255,g=a[1]/255,b=a[2]/255, mx=Math.max(r,g,b), mn=Math.min(r,g,b), d=mx-mn, h=0;
  if(d){ h = mx===r ? ((g-b)/d)%6 : mx===g ? (b-r)/d+2 : (r-g)/d+4; h*=60; if(h<0) h+=360; }
  return [Math.round(h), Math.round(mx? d/mx*100 : 0), Math.round(mx*100)]; }
function lumOf(a){ var c=a.map(function(v){ v/=255; return v<=.03928 ? v/12.92 : Math.pow((v+.055)/1.055, 2.4); }); return .2126*c[0]+.7152*c[1]+.0722*c[2]; }
function contrastOf(h1,h2){ var a=lumOf(hex2rgb(h1)), b=lumOf(hex2rgb(h2)); return (Math.max(a,b)+.05)/(Math.min(a,b)+.05); }
var COMBOS = [ {t:'Tonal', s:'One calm colour family', sh:0, cap:42}, {t:'Harmony', s:'Neighbour shades', sh:32, cap:40}, {t:'Contrast', s:'Opposite colour accents', sh:180, cap:34}, {t:'Balanced', s:'Three-way colour mix', sh:120, cap:30}, {t:'Business', s:'Quiet neutral greys', sh:0, cap:8} ];
function readable(h, s, L, bg, min){ var c=hslx(h,s,L); while(contrastOf(c,bg)<min && L>6){ L-=2; c=hslx(h,s,L); } return {c:c, L:L}; }
function makeTheme(hex, ci){
  var hs=rgb2hsl(hex2rgb(hex)), h=hs[0], grey=hs[1]<10, sa=grey ? hs[1] : clampN(hs[1], 38, 82), cb=COMBOS[ci]||COMBOS[0], BG='#F2F4FA';
  var a=readable(h, sa, 46, BG, 4.8), acc=a.c, acc2=hslx(h, sa, Math.min(a.L+11, 62)), acc3=hslx(h, sa, Math.max(a.L-10, 8));
  var h2=h+cb.sh, ss=grey ? hs[1] : Math.min(sa, cb.cap);
  var ink3=readable(h2, Math.min(ss,18), 42, BG, 4.8).c;
  var gtr=hsl2rgb(h, grey?0:55, 98.4).map(Math.round).join(',');
  var t2 = cb.sh===0 ? h+18 : h2, t3 = cb.sh===0 ? h-18 : (h+h2)/2+ (cb.sh===180 ? 90 : 0);
  var b1=hslx(h, grey?6:66, 87), b2=hslx(t2, grey?6:56, 89), b3=hslx(t3, grey?4:46, 91), top=hslx(h, grey?5:40, 96.6), bot=hslx(h2, grey?5:30, 93.6);
  var wall='radial-gradient(60% 38% at 12% 6%, '+b1+' 0%, '+b1+'00 70%), radial-gradient(55% 34% at 95% 24%, '+b2+' 0%, '+b2+'00 70%), radial-gradient(70% 40% at 80% 96%, '+b3+' 0%, '+b3+'00 70%), linear-gradient(180deg, '+top+' 0%, '+bot+' 100%)';
  return { '--acc':acc, '--acc2':acc2, '--acc3':acc3, '--navy':hslx(h2, ss, 20), '--navy2':hslx(h2, ss, 32), '--navy3':hslx(h2, ss, 14),
    '--ink':hslx(h2, Math.min(ss,28), 12), '--ink2':hslx(h2, Math.min(ss,22), 30), '--ink3':ink3, '--gt':gtr, '--wall':wall,
    '--o1':hslx(h, grey?6:60, 82), '--o2':hslx(t2, grey?6:50, 85), '--o3':hslx(t3, grey?4:44, 87) };
}
var THEME_KEYS = ['--acc','--acc2','--acc3','--navy','--navy2','--navy3','--ink','--ink2','--ink3','--gt','--wall','--o1','--o2','--o3'];
function okAccent(look, a){ return a==='look' || (LOOKACC[look]||[]).indexOf(a)>=0; }
var WALLS = [ {k:'aurora', t:'Aurora mist'}, {k:'ocean', t:'Ocean haze'}, {k:'lavender', t:'Lavender'}, {k:'sunrise', t:'Sunrise'}, {k:'mint', t:'Mint garden'}, {k:'pearl', t:'Pearl'}, {k:'silk', t:'Silk waves'}, {k:'prism', t:'Prism'}, {k:'dunes', t:'Dunes'} ];

class Component extends DCLogic {
  constructor(props){
    super(props);
    var p = props || {};
    var start = p.startScreen || 'login';
    var ti = TABS.findIndex(function(t){ return t.k===start; });
    this.state = {
      screen:start, history:[], dir:'fwd', loggedIn: start!=='login' && start!=='forgot',
      tab: ti<0?0:ti, pillL: 6+(ti<0?0:ti)*70, pillW:70, pillT:'none',
      overlay:null, company:'gi', glass: p.glassLevel || 60,
      pagesByWs: loadPages(), editing:false, snap:null, page: Number(loadJ('tc-liquid-page-v2', 0))||0, drag:null, edge:null, pillS:'none',
      tabOrder: loadOrder(), tdrag:null, armed:null, cmenu:null, pinned: loadJ('tc-liquid-pinned', []), listPrefs: loadJ('tc-liquid-lists', {}), ldrag:null, hovPos:0, hovOn:false, hiddenW: loadJ('tc-liquid-hidden-v2', {}), hidPage:0, flash:[], preset: loadJ('tc-liquid-preset', 'aurora'), accent: loadJ('tc-liquid-accent', 'look'), iconMode:'match', mode: loadJ('tc-liquid-mode', 'look'), custom: loadJ('tc-liquid-custom', {base:'#8C1D3F', combo:0}), cpHexTyping:null, wallK: loadJ('tc-liquid-wall', 'theme'), photo: loadJ('tc-liquid-photo', null), pendWall:null, pendPhoto:null,
      theme: (loadJ('tc-liquid-look', {}).theme) || 'aurora', wall: (loadJ('tc-liquid-look', {}).wall) || 'aurora',
      customize:false, hidden:[], hiddenDraft:[],
      wsList: WS.map(function(w){ return Object.assign({}, w); }), activeWs:'def', wsEdit:null, wsTab:'f', wsSel:[], wsSums:[],
      flow:{type:'sales', step:0},
      lines:{
        sales:[{name:'Havells FR Wire 1.5 sq mm (90 m)', rate:1850, qty:2, unit:'coil', gst:18},{name:'Anchor Roma Switch 6A', rate:34, qty:100, unit:'pcs', gst:18},{name:'Polycab LED Panel 18W', rate:520, qty:10, unit:'pcs', gst:18}],
        purchase:[{name:'Polycab LED Panel 18W', rate:440, qty:20, unit:'pcs', gst:18},{name:'Polycab FR Wire 1.0 sq mm (90 m)', rate:1600, qty:2, unit:'coil', gst:18}]
      },
      modes:{sales:'cash', purchase:'bank', receipt:'bank', payment:'bank'},
      jl:[{side:'Dr', name:'Salaries A/c', grp:'Indirect Expenses', amt:120000},{side:'Cr', name:'Salary Payable', grp:'Current Liabilities', amt:120000}],
      form: Object.assign({}, FORM),
      pick:null, npKey:null, extraParties:[],
      ni:{cat:'General', unit:'PCS', gst:18},
      vFilter:'all', vPeriod:'month', entry:null,
      outKind:'recv', outFilter:'all', bill:null, autoRemind:true,
      itemsFilter:'all', partyFilter:'all', partySort:'amt', party:'Shree Balaji Traders', partyTab:'summary',
      repCat:'all', report:'top',
      actFilter:'all', acts: ACTS.map(function(a){ return Object.assign({}, a); }), act:'a2',
      team: TEAM.map(function(t){ return Object.assign({}, t); }), teamFilter:'all', member:null,
      setTab:'profile', prefs:{pay:true, sync:true, due:true, team:true, wa:true}, yearly:true,
      faq:0, notifs: NOTIFS.map(function(n){ return Object.assign({}, n); }), nFilter:'all',
      showPass:false, forgotSent:false, pdf:null, zoom:100, toast:null
    };
    this.state.pillL = 6 + this.state.tabOrder.indexOf(this.state.tab)*70;
    this._seq = {};
    var hsv0 = hex2hsv(this.state.custom.base || '#8C1D3F'); this.state.cpH=hsv0[0]; this.state.cpS=hsv0[1]; this.state.cpV=hsv0[2]; this.state.cpExact=(this.state.custom.base||'#8C1D3F').toUpperCase();
    if(this.state.wallK==='photo' && !this.state.photo) this.state.wallK='theme';
    if(!okAccent(this.state.preset, this.state.accent)) this.state.accent='look';
  }
  componentWillUnmount(){ clearTimeout(this._t); clearTimeout(this._p); clearTimeout(this._lp); clearTimeout(this._et); clearTimeout(this._tlp); this.stopDrag(); }
  componentDidMount(){ if(this.state.screen==='home') this.restorePager(); var self=this; setTimeout(function(){ self.applyTheme(); }, 0); }
  applyTheme(){
    try {
      var root = (this._root && this._root.isConnected) ? this._root : document.querySelector('.root'); if(!root) return;
      var st=this.state, sig=[st.mode, st.custom.base, st.custom.combo, st.wallK, st.photo ? st.photo.url.length : 0, st.preset, st.accent].join('|');
      if(sig===this._sig && root===this._appliedRoot) return; this._sig=sig; this._appliedRoot=root;
      THEME_KEYS.forEach(function(k){ root.style.removeProperty(k); });
      if(st.mode==='custom'){ var v=makeTheme(st.custom.base, st.custom.combo); THEME_KEYS.forEach(function(k){ root.style.setProperty(k, v[k]); }); }
      if(st.wallK==='photo' && st.photo){ root.style.setProperty('--wall', 'url("'+st.photo.url+'") center / cover no-repeat'); }
      else if(st.wallK && st.wallK!=='theme'){ var t=document.createElement('div'); t.className='wp-'+st.wallK; t.style.display='none'; root.appendChild(t); var cs=getComputedStyle(t);
        ['--wall','--o1','--o2','--o3'].forEach(function(k){ var val=cs.getPropertyValue(k); if(val && val.trim()) root.style.setProperty(k, val.trim()); }); root.removeChild(t); }
    } catch(e){}
  }
  restorePager(){ var self=this; setTimeout(function(){ var pg=self.pagerEl(); if(!pg || !pg.clientWidth) return; var n=(self.state.pagesByWs[self.curWs().id]||self.defaultPages(self.curWs())).length; var i=Math.max(0, Math.min(self.state.page, n-1)); pg.scrollLeft = i*pg.clientWidth; if(i!==self.state.page) self.setState({page:i}); }, 60); }
  posOf(i){ return this.state.tabOrder.indexOf(i); }
  componentDidUpdate(prev, prevState){
    this.applyTheme();
    if(prevState && prevState.screen!=='home' && this.state.screen==='home'){ this._root=null; this.restorePager(); }
    if(prev.startScreen !== this.props.startScreen && this.props.startScreen){ this.jump(this.props.startScreen); }
    if(prev.glassLevel !== this.props.glassLevel && this.props.glassLevel){ this.setState({glass:this.props.glassLevel}); }
  }
  jump(s){
    var ti = TABS.findIndex(function(t){ return t.k===s; });
    if(ti>=0){ this.setState({loggedIn:true}); this.selectTab(ti); return; }
    this.setState({screen:s, history:[], overlay:null, dir:'fwd', loggedIn: s!=='login' && s!=='forgot', flow:{type:'sales', step:0}});
  }
  say(msg){ var self=this; this.setState({toast:msg}); clearTimeout(this._t); this._t = setTimeout(function(){ self.setState({toast:null}); }, 2600); }
  setF(k,v){ this.setState(function(p){ var f = Object.assign({}, p.form); f[k]=v; return {form:f}; }); }
  selectTab(i, extra){
    var self=this, cur=this.state.tab, w=70, a=6+this.posOf(cur)*w, b=6+this.posOf(i)*w;
    var base = Object.assign({tab:i, screen:TABS[i].k, history:[], overlay:null, dir: this.posOf(i)>=this.posOf(cur)?'fwd':'bk', customize:false, editing:false, drag:null, armed:null, cmenu:null}, extra||{});
    clearTimeout(this._p);
    if(i===cur){ this.setState(Object.assign(base, {pillL:b, pillW:w})); return; }
    this.setState(Object.assign(base, {pillL:Math.min(a,b), pillW:Math.abs(b-a)+w, pillS:'scaleY(.84)', pillT:'left .2s cubic-bezier(.4,0,.2,1), width .2s cubic-bezier(.4,0,.2,1), transform .2s ease-out'}));
    this._p = setTimeout(function(){ self.setState({pillL:b, pillW:w, pillS:'none', pillT:'left .62s cubic-bezier(.26,1.55,.44,1), width .62s cubic-bezier(.26,1.55,.44,1), transform .62s cubic-bezier(.26,1.8,.44,1)'}); }, 200);
  }
  go(s, extra){
    var ti = TABS.findIndex(function(t){ return t.k===s; });
    if(ti>=0){ this.selectTab(ti, extra); return; }
    this.setState(function(p){ return Object.assign({history:p.history.concat([p.screen]), screen:s, dir:'fwd', overlay:null, armed:null, cmenu:null}, extra||{}); });
  }
  run(a){ if(!a) return; if(typeof a==='string'){ this.go(a); return; } this.go(a[0], a[1]); }
  back(){
    if(!this.state.history.length){ if(this.state.screen==='forgot'){ this.setState({screen:'login', dir:'bk'}); return; } this.selectTab(0); return; }
    this.setState(function(p){ var h=p.history.slice(); var s=h.pop(); return {screen:s, history:h, dir:'bk', overlay:null}; });
  }
  startFlow(type, patch){
    if(patch){ this.setState(function(p){ return {form:Object.assign({}, p.form, patch)}; }); }
    this.go('flow', {flow:{type:type, step:0}});
  }
  totals(lines){ var sub=0, gst=0; (lines||[]).forEach(function(l){ var a=l.rate*l.qty; sub+=a; gst+=a*(l.gst||0)/100; }); sub=Math.round(sub); gst=Math.round(gst); return {sub:sub, gst:gst, total:sub+gst}; }
  partyPool(){ return PARTIES.concat(this.state.extraParties); }
  saveFlow(draft){
    var self=this, st=this.state, f=st.flow, cfg=FT[f.type], p=cfg.p, form=st.form, amt;
    if(cfg.items){ amt=this.totals(st.lines[f.type]).total; }
    else if(f.type==='journal'){ amt=st.jl.filter(function(j){ return j.side==='Dr'; }).reduce(function(s,j){ return s+(Number(j.amt)||0); },0); }
    else { amt=Number(form[p+'Amt'])||0; }
    if(draft){ this.selectTab(0); this.say('Draft saved on this phone'); return; }
    var no = f.type==='sales' ? 'Sales '+form.sNo : form[p+'No'];
    var id = 'n'+Date.now();
    var entry = {id:id, kind:f.type, no:no, party:form[p+'Party'], amt:amt, time:'Just now', status:'wait', fresh:true};
    this.selectTab(0, {acts:[entry].concat(st.acts)});
    this.say('Saved! It will reach Tally by itself');
    setTimeout(function(){ self.setState(function(q){ return {acts:q.acts.map(function(a){ return a.id===id?Object.assign({}, a, {status:'ok', time:'Just now'}):a; })}; }); }, 5000);
  }
  retry(id){
    var self=this;
    this.setState(function(q){ return {acts:q.acts.map(function(a){ return a.id===id?Object.assign({}, a, {status:'wait', note:'Trying again…'}):a; })}; });
    this.say('Trying again…');
    setTimeout(function(){ self.setState(function(q){ return {acts:q.acts.map(function(a){ return a.id===id?Object.assign({}, a, {status:'ok', note:''}):a; })}; }); self.say('Sent to Tally'); }, 1600);
  }
  openPick(title, key, opts){ this.setState(function(p){ return {overlay:'pick', pick:{title:title, key:key, opts:opts}, form:Object.assign({}, p.form, {pq:''})}; }); }
  choosePick(t, s){
    var pk=this.state.pick; if(!pk) return;
    if(pk.key==='__jl'){ this.setState(function(p){ return {overlay:null, jl:p.jl.concat([{side:'Dr', name:t, grp:s, amt:0}])}; }); return; }
    this.setF(pk.key, t); this.setState({overlay:null});
  }

  // ---------- Home pages: drag & drop ----------
  curWs(){ var st=this.state; return st.wsList.find(function(w){ return w.id===st.activeWs; }) || st.wsList[0]; }
  defaultPages(ws){ return [['newEntry'].concat(ws.feats).concat(['money'])]; }
  curPages(){ var ws=this.curWs(); var pg=this.state.pagesByWs[ws.id] || this.defaultPages(ws); return pg.map(function(p){ return p.slice(); }); }
  setPages(pages, extra){ var ws=this.curWs(); var o=Object.assign({}, this.state.pagesByWs); o[ws.id]=pages; this.setState(Object.assign({pagesByWs:o}, extra||{})); }
  hidList(){ var v=this.state.hiddenW[this.curWs().id]; return Array.isArray(v) ? v.filter(function(h){ return h && typeof h==='object'; }).map(function(h){ return Object.assign({}, h); }) : []; }
  cleanPages(pages, hid){
    hid = hid || this.hidList();
    var map={}, out=[];
    pages.forEach(function(p, i){ var keep = i===0 || p.length || hid.some(function(h){ return h.page===i; }); if(keep){ map[i]=out.length; out.push(p); } });
    if(!out.length) out=[[]];
    hid.forEach(function(h){ h.page = (map[h.page]!==undefined) ? map[h.page] : 0; });
    this._hidFix = hid;
    return out;
  }
  saveHid(hid, extra){ var ws=this.curWs(), hw=Object.assign({}, this.state.hiddenW); hw[ws.id]=hid; saveJ('tc-liquid-hidden-v2', hw); this.setState(Object.assign({hiddenW:hw}, extra||{})); }
  pagerEl(){ var r=this._root || document; return r.querySelector ? r.querySelector('.pager') : null; }
  scrollToPage(i){ var pg=this.pagerEl(); if(pg){ try { pg.scrollTo({left:i*pg.clientWidth, behavior:'smooth'}); } catch(e){ pg.scrollLeft=i*pg.clientWidth; } } this.setState({page:i}); saveJ('tc-liquid-page-v2', i); }
  enterEdit(){ if(this.state.editing) return; this.setState({editing:true, snap:JSON.stringify(this.curPages())}); }
  doneEdit(){ var pages=this.cleanPages(this.curPages()); var ws=this.curWs(); var o=Object.assign({}, this.state.pagesByWs); o[ws.id]=pages; savePages(o); var pi=Math.min(this.state.page, pages.length-1); this.setState({pagesByWs:o, editing:false, snap:null, page:pi}); this.say('Home layout saved'); }
  cancelEdit(){ var snap=this.state.snap; var pages = snap ? JSON.parse(snap) : this.curPages(); this.setPages(pages, {editing:false, snap:null}); var self=this; setTimeout(function(){ self.scrollToPage(0); }, 30); }
  wDown(e, id){ this.pDown(e, 'home', id); }
  startAnyDrag(list, id, x, y){ if(list==='home') this.beginDrag(id, x, y); else this.lBegin(list, id, x, y); }
  pDown(e, list, id){
    if(e.button>0) return;
    var self=this, x=e.clientX, y=e.clientY, card=e.currentTarget;
    this._root = card && card.closest ? card.closest('.root') : this._root;
    this._lpFired=false;
    var a=this.state.armed;
    if(a && a.list===list && a.id===id){ if(e.preventDefault) e.preventDefault(); this.startAnyDrag(list, id, x, y); return; }
    if(a) this.setState({armed:null});
    clearTimeout(this._lp);
    var fired=false;
    var cleanup=function(){ window.removeEventListener('pointermove', mv); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', up); };
    var mv=function(ev){
      if(!fired){ if(Math.abs(ev.clientX-x)+Math.abs(ev.clientY-y)>10){ clearTimeout(self._lp); cleanup(); } return; }
      if(Math.abs(ev.clientX-x)+Math.abs(ev.clientY-y)>12){ cleanup(); self.setState({cmenu:null}); self.startAnyDrag(list, id, ev.clientX, ev.clientY); }
    };
    var up=function(){ clearTimeout(self._lp); cleanup(); };
    window.addEventListener('pointermove', mv); window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up);
    this._lp=setTimeout(function(){ fired=true; self._lpFired=true; self.openCardMenu(list, id, card); try { if(navigator.vibrate) navigator.vibrate(12); } catch(err){} }, 480);
  }
  updPref(list, fn){ var all=Object.assign({}, this.state.listPrefs); var o=all[list]||{}; var pr={order:(o.order||[]).slice(), pinned:(o.pinned||[]).slice(), hidden:(o.hidden||[]).slice()}; fn(pr); all[list]=pr; saveJ('tc-liquid-lists', all); this.setState({listPrefs:all}); }
  cmPin(){ var c=this.state.cmenu; if(!c) return; var list=c.list||'home';
    if(list==='home'){ this.togglePin(c.id); return; }
    var on=false; this.updPref(list, function(pr){ var k=pr.pinned.indexOf(c.id); if(k>=0) pr.pinned.splice(k,1); else { pr.pinned.push(c.id); on=true; } });
    this.setState({cmenu:null}); this.say(on?'Pinned to the top':'Unpinned'); }
  cmHide(){ var c=this.state.cmenu; if(!c) return; var list=c.list||'home';
    if(list==='home'){ this.hideWidget(c.id); return; }
    this.updPref(list, function(pr){ if(pr.hidden.indexOf(c.id)<0) pr.hidden.push(c.id); var k=pr.pinned.indexOf(c.id); if(k>=0) pr.pinned.splice(k,1); });
    this.setState({cmenu:null}); this.say('Card hidden'); }
  hideWidget(id){
    var self=this, wsId=this.curWs().id, blocked=false, done=false;
    this.setState(function(p){
      var ws=p.wsList.find(function(w){ return w.id===p.activeWs; }) || p.wsList[0];
      var pages=(p.pagesByWs[ws.id] || self.defaultPages(ws)).map(function(x){ return x.slice(); });
      var total=pages.reduce(function(n,x){ return n+x.length; },0);
      if(total<=1){ blocked=true; return {cmenu:null}; }
      var pi=-1, idx=-1; pages.forEach(function(x, i){ var k=x.indexOf(id); if(k>=0){ pi=i; idx=k; } });
      if(pi<0) return {cmenu:null};
      var snap=pages[pi].slice();
      pages[pi].splice(idx, 1);
      var hid=(Array.isArray(p.hiddenW[ws.id]) ? p.hiddenW[ws.id] : []).filter(function(h){ return h && h.id!==id; }).map(function(h){ return Object.assign({}, h); });
      hid.push({id:id, page:pi, index:idx, snap:snap});
      pages=self.cleanPages(pages, hid); hid=self._hidFix;
      var pb=Object.assign({}, p.pagesByWs); pb[ws.id]=pages;
      var hw=Object.assign({}, p.hiddenW); hw[ws.id]=hid;
      var pinned=p.pinned.filter(function(x){ return x!==id; });
      savePages(pb); saveJ('tc-liquid-hidden-v2', hw); saveJ('tc-liquid-pinned', pinned); done=true;
      return {pagesByWs:pb, hiddenW:hw, pinned:pinned, cmenu:null};
    });
    this.say('Card hidden');
  }
  restoreHidden(ids){
    var self=this;
    this.setState(function(p){
      var ws=p.wsList.find(function(w){ return w.id===p.activeWs; }) || p.wsList[0];
      var pages=(p.pagesByWs[ws.id] || self.defaultPages(ws)).map(function(x){ return x.slice(); });
      var hid=(Array.isArray(p.hiddenW[ws.id]) ? p.hiddenW[ws.id] : []).map(function(h){ return Object.assign({}, h); });
      var present=[].concat.apply([], pages);
      hid.filter(function(h){ return ids.indexOf(h.id)>=0; }).sort(function(a,b){ return a.page-b.page || a.index-b.index; }).forEach(function(h){
        if(present.indexOf(h.id)>=0) return;
        while(pages.length<=h.page) pages.push([]);
        var pg=pages[h.page], at=-1, snap=Array.isArray(h.snap)?h.snap:[], me=snap.indexOf(h.id);
        if(me>=0){
          for(var k=me+1; k<snap.length && at<0; k++){ var n=pg.indexOf(snap[k]); if(n>=0) at=n; }
          if(at<0){ for(var q=me-1; q>=0 && at<0; q--){ var b=pg.indexOf(snap[q]); if(b>=0) at=b+1; } }
        }
        if(at<0) at=Math.max(0, Math.min(h.index, pg.length));
        pg.splice(at, 0, h.id); present.push(h.id);
      });
      hid=hid.filter(function(h){ return ids.indexOf(h.id)<0; });
      pages=self.cleanPages(pages, hid); hid=self._hidFix;
      var pb=Object.assign({}, p.pagesByWs); pb[ws.id]=pages;
      var hw=Object.assign({}, p.hiddenW); hw[ws.id]=hid;
      savePages(pb); saveJ('tc-liquid-hidden-v2', hw);
      var left=hid.filter(function(h){ return h.page===p.hidPage; }).length;
      return {pagesByWs:pb, hiddenW:hw, flash:ids.slice(), overlay: left ? p.overlay : null};
    });
    clearTimeout(this._fl); this._fl=setTimeout(function(){ self.setState({flash:[]}); }, 1400);
    this.say(ids.length>1 ? 'Cards unhidden' : 'Card unhidden');
  }
  lBegin(list, id, cx, cy){
    if(!this._root) return;
    var self=this, pt=this.localPt(cx, cy); this._lastKey=null;
    this.stopDrag();
    this.setState({ldrag:{list:list, id:id, x:pt.x, y:pt.y}});
    this._mv=function(ev){ self.lMove(ev); }; this._up=function(){ self.lEnd(); };
    window.addEventListener('pointermove', this._mv, {passive:false}); window.addEventListener('pointerup', this._up); window.addEventListener('pointercancel', this._up);
  }
  lMove(ev){
    var d=this.state.ldrag; if(!d) return;
    if(ev.cancelable) ev.preventDefault();
    var pt=this.localPt(ev.clientX, ev.clientY);
    this.setState({ldrag:Object.assign({}, d, {x:pt.x, y:pt.y})});
    var scr=this._root.querySelector('.scr'); if(scr){ var r=scr.getBoundingClientRect(); if(ev.clientY < r.top+56) scr.scrollTop -= 12; else if(ev.clientY > r.bottom-56) scr.scrollTop += 12; }
    var el=document.elementFromPoint(ev.clientX, ev.clientY); if(!el || !el.closest) return;
    var t=el.closest('[data-lk]'); if(!t || t.getAttribute('data-list')!==d.list) return;
    var tk=t.getAttribute('data-lk'); if(tk===d.id) return;
    var b=t.getBoundingClientRect();
    var after = d.list==='reports' ? (ev.clientX > b.left+b.width/2) : (ev.clientY > b.top+b.height/2);
    var key=tk+(after?'>':'<'); if(key===this._lastKey) return; this._lastKey=key;
    var seq=(this._seq[d.list]||[]).slice(); var i=seq.indexOf(d.id); if(i>=0) seq.splice(i,1);
    var j=seq.indexOf(tk); if(j<0) return; seq.splice(j+(after?1:0), 0, d.id);
    this.updPref(d.list, function(pr){ pr.order = seq.concat(pr.order.filter(function(k){ return seq.indexOf(k)<0; })); });
  }
  armDwell(ev, q){
    var self=this; clearTimeout(this._dw); clearTimeout(this._dw0);
    if(ev.pointerType==='touch' || ev.buttons || this.state.tdrag) return;
    var ti=this.state.tabOrder[q]; if(ti===this.state.tab) return;
    this._dw0=setTimeout(function(){ if(self.state.hovPos===q && self.state.hovOn) self.setState({dwell:true}); }, 60);
    this._dw=setTimeout(function(){ if(self.state.hovOn && self.state.hovPos===q && !self.state.tdrag){ self.setState({dwell:false}); if(self.state.tab!==ti) self.selectTab(ti); } }, 650);
  }
  lEnd(){ this.stopDrag(); this._lastKey=null; this.setState({ldrag:null, armed:null}); }
  openCardMenu(list, id, card){
    if(!this._root || !card) return;
    var r=this._root.getBoundingClientRect(), sc=(r.width/390)||1, b=card.getBoundingClientRect();
    var left=(b.left-r.left)/sc, top=(b.top-r.top)/sc, w=b.width/sc, h=b.height/sc, mh=262, mw=214;
    var y = (top+h+10+mh < 844-104) ? top+h+10 : Math.max(96, top-10-mh);
    if(y+mh > 844-104) y = Math.max(40, 844-104-mh);
    var x = Math.max(16, Math.min(390-16-mw, left + w/2 - mw/2));
    this.setState({cmenu:{list:list, id:id, x:Math.round(x), y:Math.round(y)}});
  }
  persistPages(pages, extra){ var ws=this.curWs(); var o=Object.assign({}, this.state.pagesByWs); o[ws.id]=pages; savePages(o); this.setState(Object.assign({pagesByWs:o}, extra||{})); }
  togglePin(id){
    var pinned=this.state.pinned.slice(), k=pinned.indexOf(id), pages=this.curPages();
    if(k>=0){ pinned.splice(k,1); saveJ('tc-liquid-pinned', pinned); this.setState({pinned:pinned, cmenu:null}); this.say('Unpinned'); return; }
    pinned.push(id); this.pluck(pages, id);
    var n=pages[0].filter(function(x){ return pinned.indexOf(x)>=0; }).length; pages[0].splice(n, 0, id);
    pages=this.cleanPages(pages); saveJ('tc-liquid-pinned', pinned); this.saveHid(this._hidFix);
    this.persistPages(pages, {pinned:pinned, cmenu:null, page:0}); var self=this; setTimeout(function(){ self.scrollToPage(0); saveJ('tc-liquid-page-v2', 0); }, 30);
    this.say('Pinned to the first page');
  }
  tDown(e, i){
    if(e.button>0) return;
    var self=this, x0=e.clientX, y0=e.clientY, bar=e.currentTarget && e.currentTarget.closest ? e.currentTarget.closest('.tabbar') : null;
    this._root = e.currentTarget && e.currentTarget.closest ? e.currentTarget.closest('.root') : this._root;
    this._tabLp=false; clearTimeout(this._tlp);
    var barX=function(cx){ var r=self._root.getBoundingClientRect(), sc=(r.width/390)||1; return (cx-r.left)/sc - 14; };
    var mv=function(ev){
      if(!self.state.tdrag){ if(Math.abs(ev.clientX-x0)+Math.abs(ev.clientY-y0)>10) clearTimeout(self._tlp); return; }
      if(ev.cancelable) ev.preventDefault();
      var bx=barX(ev.clientX), left=Math.max(0, Math.min(362-70, bx-35)), pos=Math.max(0, Math.min(4, Math.round((left-6)/70)));
      var order=self.state.tabOrder.slice(), cur=order.indexOf(i), patch={tdrag:{i:i, x:left}};
      if(pos!==cur){ order.splice(cur,1); order.splice(pos,0,i); patch.tabOrder=order; patch.pillL=6+order.indexOf(self.state.tab)*70; patch.pillW=70; patch.pillS='none'; patch.pillT='left .55s cubic-bezier(.28,1.5,.45,1), width .3s, transform .3s'; }
      self.setState(patch);
    };
    var up=function(){ clearTimeout(self._tlp); window.removeEventListener('pointermove', mv); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', up);
      if(self.state.tdrag){ saveJ('tc-liquid-tabs', self.state.tabOrder); self.setState({tdrag:null}); } };
    window.addEventListener('pointermove', mv, {passive:false}); window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up);
    this._tlp=setTimeout(function(){ self._tabLp=true; var left=Math.max(0, Math.min(362-70, barX(x0)-35)); self.setState({tdrag:{i:i, x:left}}); try { if(navigator.vibrate) navigator.vibrate(10); } catch(err){} }, 450);
  }
  localPt(cx, cy){ var r=this._root.getBoundingClientRect(); var sc=(r.width/390)||1; return {x:(cx-r.left)/sc, y:(cy-r.top)/sc}; }
  beginDrag(id, cx, cy){
    if(!this._root) return;
    var self=this, pt=this.localPt(cx, cy);
    this._lastKey=null; this._edge=null; this._flipped=null; this._d0={x:pt.x, y:pt.y}; this._snap=JSON.stringify(this.curPages());
    this.setState({drag:{id:id, x:pt.x, y:pt.y}, edge:null});
    this.stopDrag();
    this._mv=function(ev){ self.dragMove(ev); }; this._up=function(ev){ if(ev && ev.type==='pointercancel') self.dragCancel(); else self.dragEnd(); };
    window.addEventListener('pointermove', this._mv, {passive:false}); window.addEventListener('pointerup', this._up); window.addEventListener('pointercancel', this._up);
  }
  stopDrag(){ if(this._mv){ window.removeEventListener('pointermove', this._mv); window.removeEventListener('pointerup', this._up); window.removeEventListener('pointercancel', this._up); this._mv=null; this._up=null; } }
  dragMove(ev){
    if(!this.state.drag) return;
    if(ev.cancelable) ev.preventDefault();
    var id=this.state.drag.id, pt=this.localPt(ev.clientX, ev.clientY);
    var travelled = Math.abs(pt.x-this._d0.x) > 44;
    var edge = !travelled ? null : (pt.x<22 && pt.x<this._d0.x ? 'l' : (pt.x>368 && pt.x>this._d0.x ? 'r' : null));
    if(edge!==this._edge){ this._edge=edge; clearTimeout(this._et); if(!edge) this._flipped=null; if(edge && this._flipped!==edge) this.armEdge(edge); }
    this.setState({drag:{id:id, x:pt.x, y:pt.y}, edge:edge});
    if(edge) return;
    var el=document.elementFromPoint(ev.clientX, ev.clientY); if(!el || !el.closest) return;
    var wEl=el.closest('[data-wid]');
    if(wEl){ var tid=wEl.getAttribute('data-wid'); if(tid===id) return; var b=wEl.getBoundingClientRect(); var wide=wEl.classList.contains('wide');
      var after = wide ? (ev.clientY > b.top+b.height/2) : (ev.clientX > b.left+b.width/2); var key=tid+(after?'>':'<'); if(key===this._lastKey) return; this._lastKey=key; this.moveTo(id, tid, after); return; }
    var end=el.closest('[data-endpage]');
    if(end){ var pi=Number(end.getAttribute('data-endpage')); var k2='end'+pi; if(k2===this._lastKey) return; this._lastKey=k2; this.moveToPage(id, pi); }
  }
  pluck(pages, id){ pages.forEach(function(p){ var k=p.indexOf(id); if(k>=0) p.splice(k,1); }); }
  moveTo(id, tid, after){ var pages=this.curPages(); this.pluck(pages, id); for(var i=0;i<pages.length;i++){ var k=pages[i].indexOf(tid); if(k>=0){ pages[i].splice(k+(after?1:0), 0, id); break; } } this.setPages(pages); }
  moveToPage(id, pi){ var pages=this.curPages(); if(!pages[pi]) return; if(pages[pi][pages[pi].length-1]===id) return; this.pluck(pages, id); pages[pi].push(id); this.setPages(pages); }
  armEdge(edge){ var self=this; this._et=setTimeout(function(){ if(self._edge!==edge || !self.state.drag) return; self._flipped=edge; self.flip(edge); }, 700); }
  flip(edge){
    var id=this.state.drag.id, cur=this.state.page, pages=this.curPages();
    if(edge==='l' && cur===0) return;
    var target = edge==='l' ? cur-1 : cur+1;
    if(target>=pages.length){ var src=pages[cur]||[]; if(src.length<=1 && src.indexOf(id)>=0) return; pages.push([]); }
    this.pluck(pages, id); pages[target].push(id); this._lastKey=null;
    this.setPages(pages, {page:target});
    var self=this; setTimeout(function(){ self.scrollToPage(target); }, 20);
  }
  dragCancel(){
    this.stopDrag(); clearTimeout(this._et); this._edge=null; this._lastKey=null;
    var pages = this._snap ? JSON.parse(this._snap) : this.curPages();
    this.setPages(pages, {drag:null, edge:null, armed:null});
  }
  dragEnd(){
    this.stopDrag(); clearTimeout(this._et); this._edge=null; this._lastKey=null;
    var pages=this.cleanPages(this.curPages()); this.saveHid(this._hidFix); var pi=Math.min(this.state.page, pages.length-1);
    this.persistPages(pages, {drag:null, edge:null, page:pi, armed:null}); saveJ('tc-liquid-page-v2', pi);
    var self=this; setTimeout(function(){ self.scrollToPage(pi); }, 20);
  }

  renderVals(){
    var self=this, st=this.state, S=st.screen, form=st.form;
    var go=function(s,x){ return function(){ self.go(s,x); }; };
    var say=function(m){ return function(){ self.say(m); }; };
    var closeOv=function(){ self.setState({overlay:null}); };
    var reg={}, hl={};
    var lg=function(list, lk, fn){ return function(ev){ if(self._lpFired){ self._lpFired=false; return; } var a=self.state.armed; if(a && a.list===list && a.id===lk) return; fn(ev); }; };
    var L=function(list, rows, keyOf, labelOf, base){
      var pr=st.listPrefs[list]||{}, ord=pr.order||[], pin=pr.pinned||[], hid=pr.hidden||[];
      rows.forEach(function(x, n){ x.lk=String(keyOf(x)); x._n=n; var op=x.open || x.mopen || function(){}; reg[list+'|'+x.lk]={label:labelOf(x), d:x.d||x.md||IC.receipt, c:x.c||x.mc||C.navy, open:op}; if(x.open) x.open=lg(list, x.lk, x.open); });
      var vis=rows.filter(function(x){ return hid.indexOf(x.lk)<0; });
      vis.sort(function(a,b){ var pa=pin.indexOf(a.lk)>=0?0:1, pb=pin.indexOf(b.lk)>=0?0:1; if(pa!==pb) return pa-pb; var ra=ord.indexOf(a.lk), rb=ord.indexOf(b.lk); ra=ra<0?1e6+a._n:ra; rb=rb<0?1e6+b._n:rb; return ra-rb; });
      self._seq[list]=vis.map(function(x){ return x.lk; });
      var nh=rows.length-vis.length;
      hl[list]={any:nh>0, txt: nh+' hidden · Unhide', show:function(){ var keys=rows.map(function(x){ return x.lk; }); self.updPref(list, function(q){ q.hidden=q.hidden.filter(function(k){ return keys.indexOf(k)<0; }); }); }};
      var ar=st.armed, ld=st.ldrag, cmn=st.cmenu;
      return vis.map(function(x){ var armed=!!(ar && ar.list===list && ar.id===x.lk), ghost=!!(ld && ld.list===list && ld.id===x.lk), lift=!!(cmn && cmn.list===list && cmn.id===x.lk);
        return Object.assign(x, {pinned:pin.indexOf(x.lk)>=0, rcls:base+(armed?' armedrow':'')+(ghost?' ghostrow':'')+(lift?' liftrow':''), down:function(e){ self.pDown(e, list, x.lk); }}); });
    };

    // forms
    var fc={}; Object.keys(form).forEach(function(k){ fc[k]=function(e){ self.setF(k, e && e.target ? e.target.value : e); }; });

    var is={}; ['login','forgot','home','notifs','createWs','manageWs','newEntry','flow','vHub','vList','entryDetail','outHub','outList','billDetail','items','party','partyDetail','reports','report','activity','actDetail','team','settings','companies','billing','refer','help'].forEach(function(k){ is[k]=S===k; });
    var ov={}; ['hiddenPanel','menu','search','company','pick','newParty','picker','addItem','invite','newUser','member','pdf'].forEach(function(k){ ov[k]=st.overlay===k; });
    var showTabs = st.loggedIn && NO_TAB.indexOf(S)<0;
    var dirCls = st.dir==='bk'?' bk':'';
    var scrCls = 'scr'+dirCls+(showTabs?' wt':'');
    var flowCls = 'scr flowscr'+dirCls;
    var prev = st.history.length ? st.history[st.history.length-1] : 'home';
    var backLabel = TITLES[prev] || 'Home';

    var tabs = TABS.map(function(t,i){ var dragging = st.tdrag && st.tdrag.i===i; var pos = st.tabOrder.indexOf(i);
      return {t:t.t, d:IC[t.ic], cls:'tab tap'+(st.tab===i?' on':'')+(dragging?' lift':''), cur: st.tab===i?'page':'false',
        left: dragging ? st.tdrag.x : 6+pos*70, tr: dragging ? 'transform .3s cubic-bezier(.3,1.5,.5,1)' : 'left .55s cubic-bezier(.28,1.5,.45,1), transform .38s cubic-bezier(.3,1.45,.5,1), color .3s',
        down:function(ev){ self.tDown(ev, i); },
        go:function(){ if(self._tabLp){ self._tabLp=false; return; } self.selectTab(i); }}; });

    var company = COMPANIES.find(function(c){ return c.id===st.company; }) || COMPANIES[1];
    var companies = COMPANIES.map(function(c){ var sel=c.id===st.company; return {name:c.name, sub:c.sub, sel:sel, cls:'glass row tap'+(sel?' ':''), radio: sel?'tk':'tk" style="', pick:function(){ self.setState({company:c.id, overlay:null}); self.say('Now showing '+c.name.split(' - ')[0]); }}; });
    companies.forEach(function(c){ c.radio = c.sel ? 'tk' : 'tk tk-off'; c.cls = 'glass row tap' + (c.sel ? ' selrow' : ''); });

    var unread = st.notifs.filter(function(n){ return n.unread; }).length;

    var nav = {
      forgot:function(){ self.setState({forgotSent:false}); self.go('forgot'); },
      help:go('help'), notifs:go('notifs'), newEntry:go('newEntry'), manageWs:go('manageWs'),
      createWs:function(){ self.setState(function(p){ return {wsEdit:null, wsSel:[], wsSums:[], wsTab:'f', form:Object.assign({}, p.form, {wsName:''})}; }); self.go('createWs'); },
      companies:go('companies'), billing:go('billing'), profile:go('settings', {setTab:'profile'}),
      logout:function(){ self.setState({screen:'login', history:[], loggedIn:false, overlay:null, tab:0, pillL:6+self.posOf(0)*70, pillW:70, pillT:'none', dir:'bk'}); self.say('You are logged out'); },
      call:say('Calling support…'), chat:say('Opening WhatsApp…'), mail:say('Opening email…')
    };
    var menu = { acct:[
      {t:'Companies', ic:'building', c:C.navy, go:go('companies')},
      {t:'Sales Team', ic:'team', c:C.team, go:go('team')},
      {t:'Reports', ic:'chart', c:C.reports, go:go('reports')},
      {t:'Settings', ic:'gear', c:C.settings, go:go('settings')},
      {t:'Alerts', ic:'bell', c:C.acc, go:go('notifs'), count:unread},
      {t:'Workspaces', ic:'grid', c:C.navy, go:go('manageWs')},
      {t:'Refer a friend', ic:'gift', c:C.sales, go:go('refer')}
    ].map(function(m){ return Object.assign({}, m, {d:IC[m.ic], hasCount:!!m.count}); }) };

    // home
    var ws = st.wsList.find(function(w){ return w.id===st.activeWs; }) || st.wsList[0];
    var hid = st.customize ? st.hiddenDraft : st.hidden;
    var tiles = ws.feats.filter(function(k){ return st.customize || st.hidden.indexOf(k)<0; }).map(function(k){
      var t=T[k], off=hid.indexOf(k)>=0;
      return {t:t.t, s:t.s, d:IC[t.ic], c:t.c, edit:st.customize, badge: off?'+':'−', badgeCls:'tbadge '+(off?'badge-add':'badge-rm'),
        cls:'glass tile tap'+(st.customize?' wig':'')+(off?' off':''),
        go: st.customize ? function(){ self.setState(function(p){ var h=p.hiddenDraft.slice(); var i=h.indexOf(k); if(i>=0) h.splice(i,1); else h.push(k); return {hiddenDraft:h}; }); }
                         : function(){ if(t.flow) self.startFlow(t.flow); else self.go(t.to); }};
    });
    var guard=function(fn){ return function(ev){ if(self.state.editing || self._lpFired){ self._lpFired=false; return; } fn(ev); }; };
    var quick = [ {t:'Sale', ic:'bag', f:'sales'}, {t:'Purchase', ic:'cart', f:'purchase'}, {t:'Money In', ic:'in', f:'receipt'}, {t:'Money Out', ic:'out', f:'payment'} ].map(function(q){ return {t:q.t, d:IC[q.ic], go:guard(function(){ self.startFlow(q.f); })}; });
    var SUMBG = { toGet:'color-mix(in srgb,var(--pos) 9%,transparent)', toGive:'color-mix(in srgb,var(--warn) 8%,transparent)', mIn:'color-mix(in srgb,var(--pos) 6%,transparent)', mOut:'color-mix(in srgb,var(--warn) 6%,transparent)', sales:'color-mix(in srgb,var(--acc) 8%,transparent)', purch:'color-mix(in srgb,var(--navy2) 7%,transparent)', cash:'rgba(27,45,91,.06)', bank:'rgba(27,45,91,.06)' };
    var wsPages = st.pagesByWs[ws.id] || this.defaultPages(ws);
    var dragId = st.drag ? st.drag.id : null;
    var W = function(id){
      if(id==='newEntry') return {id:id, wide:true, isEntry:true, label:'New Entry', d:IC.plus, c:C.acc, go:guard(function(){ self.go('newEntry'); })};
      if(id==='money') return {id:id, wide:true, isMoney:true, label:'Money summary', d:IC.rupeeC, c:C.outstanding};
      var t=T[id]; if(!t) return null;
      return {id:id, isTile:true, t:t.t, s:t.s, d:IC[t.ic], c:t.c, label:t.t, go:guard(function(){ if(t.flow) self.startFlow(t.flow); else self.go(t.to); })};
    };
    var hidW = this.hidList();
    var pages = wsPages.map(function(ids, i){ return {i:String(i), title: i===0 ? 'What would you like to do?' : 'Page '+(i+1), hasHidden: hidW.some(function(h){ return h.page===i; }), hidTxt:'Hidden cards · Unhide', showHidden:function(){ self.setState({overlay:'hiddenPanel', hidPage:i}); },
      widgets: ids.map(W).filter(Boolean).map(function(w){ var armed=!!(st.armed && st.armed.list==='home' && st.armed.id===w.id); reg['home|'+w.id]={label:w.label, d:w.d, c:w.c, open:function(){ if(w.id==='newEntry') self.go('newEntry'); else if(w.id==='money') self.go('outHub'); else { var t=T[w.id]; if(t.flow) self.startFlow(t.flow); else self.go(t.to); } }}; return Object.assign(w, {isEntry:!!w.isEntry, isMoney:!!w.isMoney, isTile:!!w.isTile, armed:armed, pinned:st.pinned.indexOf(w.id)>=0,
        cls:'wg'+(w.wide?' wide':'')+(dragId===w.id?' ghosted':'')+(armed?' armed':'')+(st.cmenu&&st.cmenu.list==='home'&&st.cmenu.id===w.id?' lifted':'')+(st.flash.indexOf(w.id)>=0?' flash':''), down:function(ev){ self.wDown(ev, w.id); }}); })}; });
    var dots = pages.length<2 ? [] : pages.map(function(p, i){ return {cls:'pdhit tap'+(i===st.page?' on':''), label:'Go to page '+(i+1), go:function(){ self.scrollToPage(i); }}; });
    var dInfo = dragId ? (W(dragId) || {}) : {};
    var drag = { on:!!st.drag, x: st.drag?st.drag.x:0, y: st.drag?st.drag.y:0, label:dInfo.label||'', d:dInfo.d||'', c:dInfo.c||'var(--navy)', edgeL:'edge l'+(st.edge==='l'?' on':''), edgeR:'edge r'+(st.edge==='r'?' on':'') };
    var sums = ws.sums.map(function(k){ var m=SUMS[k]; return {t:m.t, s:m.s, d:IC[m.ic], c:m.c, cls:m.cls, bg:SUMBG[k], v:inr(m.v), go:guard(function(){ self.run(m.go); })}; });

    // search
    var SEARCH = [
      {t:'Items', s:'Stock from Tally', ic:'box', c:C.items, a:'items'},
      {t:'Party', s:'Customers and suppliers', ic:'person', c:C.party, a:'party'},
      {t:'All Vouchers', s:'Every entry in one list', ic:'receipt', c:C.vouchers, a:['vList',{vFilter:'all'}]},
      {t:'New Sale', s:'Make a sales bill', ic:'bag', c:C.sales, f:'sales'},
      {t:'New Purchase', s:'Write down what you bought', ic:'cart', c:C.purchase, f:'purchase'},
      {t:'Money In', s:'Record a receipt', ic:'in', c:C.receipt, f:'receipt'},
      {t:'Money Out', s:'Record a payment', ic:'out', c:C.payment, f:'payment'},
      {t:'To get (Receivable)', s:'Money others owe you', ic:'in', c:C.receipt, a:['outList',{outKind:'recv',outFilter:'all'}]},
      {t:'To give (Payable)', s:'Money you owe others', ic:'out', c:C.payment, a:['outList',{outKind:'pay',outFilter:'all'}]},
      {t:'Activity', s:'Entries going to Tally', ic:'activity', c:C.activity, a:'activity'},
      {t:'Reports', s:'Top customers, day book, stock', ic:'chart', c:C.reports, a:'reports'},
      {t:'Sales Team', s:'Your team and invites', ic:'team', c:C.team, a:'team'},
      {t:'Settings', s:'Profile, alerts, look', ic:'gear', c:C.settings, a:'settings'},
      {t:'Help', s:'Questions and support', ic:'help', c:C.sales, a:'help'}
    ];
    var q = (form.q||'').toLowerCase().trim();
    var results = SEARCH.filter(function(r){ return !q || (r.t+' '+r.s).toLowerCase().indexOf(q)>=0; }).map(function(r){ return {t:r.t, s:r.s, d:IC[r.ic], c:r.c, go:function(){ self.setState(function(p){ return {form:Object.assign({}, p.form, {q:''})}; }); if(r.f) self.startFlow(r.f); else self.run(r.a); }}; });

    // notifications
    var notifs = L('notifs', st.notifs.filter(function(n){ return st.nFilter==='all' || n.unread; }).map(function(n){ return {id:n.id, t:n.t, b:n.b, time:n.time, d:IC[n.ic], c:n.c, unread:n.unread, open:function(){ self.setState(function(p){ return {notifs:p.notifs.map(function(x){ return x.id===n.id?Object.assign({}, x, {unread:false}):x; })}; }); self.run(n.go); }}; }), function(x){ return x.id; }, function(x){ return x.t; }, 'row tap');

    // create workspace
    var FEATS = Object.keys(T), SUMK = Object.keys(SUMS);
    var isF = st.wsTab==='f';
    var cw = {
      fCls: isF?'on':'', mCls: isF?'':'on', setF:function(){ self.setState({wsTab:'f'}); }, setM:function(){ self.setState({wsTab:'m'}); },
      fCount: st.wsSel.length, mCount: st.wsSums.length,
      chosen: (isF?st.wsSel:st.wsSums).map(function(k){ var m=isF?T[k]:SUMS[k]; return {t:m.t, d:IC[m.ic], c:m.c, toggle:function(){ self.setState(function(p){ var key=isF?'wsSel':'wsSums'; var o={}; o[key]=p[key].filter(function(x){ return x!==k; }); return o; }); }}; }),
      avail: (isF?FEATS:SUMK).filter(function(k){ return (isF?st.wsSel:st.wsSums).indexOf(k)<0; }).map(function(k){ var m=isF?T[k]:SUMS[k]; return {t:m.t, d:IC[m.ic], c:m.c, toggle:function(){ self.setState(function(p){ var key=isF?'wsSel':'wsSums'; var o={}; o[key]=p[key].concat([k]); return o; }); }}; }),
      reset:function(){ self.setState(function(p){ return {wsSel:[], wsSums:[], form:Object.assign({}, p.form, {wsName:''})}; }); },
      cannot: !(form.wsName||'').trim() || !st.wsSel.length,
      save:function(){ var name=(self.state.form.wsName||'').trim(); var id=self.state.wsEdit || ('w'+Date.now()); var w={id:id, name:name, feats:self.state.wsSel.slice(), sums:self.state.wsSums.length?self.state.wsSums.slice():['toGet','toGive']};
        self.setState(function(p){ var list = p.wsEdit ? p.wsList.map(function(x){ return x.id===id?w:x; }) : p.wsList.concat([w]); var h=p.history.slice(); if(h[h.length-1]==='manageWs') h.pop(); return {wsList:list, screen:'manageWs', history:h, dir:'bk', wsEdit:null}; }); self.say('Workspace saved'); }
    };
    cw.empty = cw.chosen.length===0;
    var wsm = st.wsList.map(function(w){ var active=w.id===st.activeWs; return {name:w.name, active:active, notActive:!active, custom:!w.builtin,
      meta: w.feats.length+' shortcuts · '+w.sums.length+' money cards'+(w.builtin?' · built-in':''),
      feats: w.feats.map(function(k){ return T[k].t; }).join(', '), sums: w.sums.map(function(k){ return SUMS[k].t; }).join(', '),
      use:function(){ self.setState({activeWs:w.id, hidden:[], page:0}); self.say('Now using '+w.name); self.selectTab(0); },
      edit:function(){ self.setState(function(p){ return {wsEdit:w.id, wsSel:w.feats.slice(), wsSums:w.sums.slice(), wsTab:'f', form:Object.assign({}, p.form, {wsName:w.name})}; }); self.go('createWs'); },
      del:function(){ self.setState(function(p){ return {wsList:p.wsList.filter(function(x){ return x.id!==w.id; }), activeWs: p.activeWs===w.id?'def':p.activeWs}; }); self.say(w.name+' deleted'); }}; });

    // new entry
    var start = { journal:function(){ self.startFlow('journal'); } };
    var entryTiles = [ {t:'Sale', s:'You sold goods', ic:'bag', c:C.sales, f:'sales'}, {t:'Purchase', s:'You bought goods', ic:'cart', c:C.purchase, f:'purchase'}, {t:'Money In', s:'Money came to you', ic:'in', c:C.receipt, f:'receipt'}, {t:'Money Out', s:'Money went out', ic:'out', c:C.payment, f:'payment'} ].map(function(e){ return {t:e.t, s:e.s, d:IC[e.ic], c:e.c, go:function(){ self.startFlow(e.f); }}; });

    // flow
    var f=st.flow, cfg=FT[f.type], P=cfg.p, last=cfg.steps.length-1;
    var lines = st.lines[f.type] || [];
    var tot = this.totals(lines);
    var val = {no:form[P+'No'], date:form[P+'Date'], party:form[P+'Party'], note:form[P+'Note'], due:form[P+'Due'], amt:form[P+'Amt'], ref:form[P+'Ref'], bank:form[P+'Bank'], utr:form[P+'Utr'], acc:form[P+'Acc'], payNote:form[P+'PayNote']};
    var hh = {no:fc[P+'No'], date:fc[P+'Date'], note:fc[P+'Note'], due:fc[P+'Due'], amt:fc[P+'Amt'], ref:fc[P+'Ref'], bank:fc[P+'Bank'], utr:fc[P+'Utr'], payNote:fc[P+'PayNote']};
    var setStep=function(n){ return function(){ self.setState({flow:{type:f.type, step:n}}); }; };
    var mode = st.modes[f.type] || 'cash';
    var payAmt = Number(val.amt)||0, bal = tot.total - payAmt;
    var modeName = (MODES.find(function(m){ return m.id===mode; })||MODES[0]).t;
    var drSum = st.jl.filter(function(j){ return j.side==='Dr'; }).reduce(function(s,j){ return s+(Number(j.amt)||0); },0);
    var crSum = st.jl.filter(function(j){ return j.side==='Cr'; }).reduce(function(s,j){ return s+(Number(j.amt)||0); },0);
    var poolFor = function(list){ return self.partyPool().filter(function(p){ return p.type===list; }); };
    var sections = [];
    if(cfg.items){
      var items = lines.map(function(l){ return {k:l.name+' × '+l.qty+' '+l.unit, v:inr(l.rate*l.qty), cls:'kv'}; });
      sections = [
        {title:'Details', step:0, rows:[{k:cfg.noLabel, v:f.type==='sales'?'Sales '+val.no:val.no},{k:'Date', v:fdate(val.date)},{k:f.type==='sales'?'Customer':'Supplier', v:val.party}].concat(f.type==='purchase'?[{k:"Seller's bill no.", v:form.pSupInv}]:[]).concat([{k:'Pay by', v:fdate(val.due)},{k:'Note', v:val.note||'—'}])},
        {title:'Items ('+lines.length+')', step:1, rows: items.concat([{k:'Before GST', v:inr(tot.sub)},{k:'GST', v:inr(tot.gst)},{k:'Bill total', v:inr(tot.total), cls:'kv strong'}])},
        {title:'Payment', step:2, rows:[{k:'Paid by', v:modeName},{k:cfg.amtLabel, v:inr(payAmt)},{k:cfg.balLabel, v:inr(Math.max(bal,0)), cls:'kv strong'}]}
      ];
    } else if(f.type==='journal'){
      sections = [
        {title:'Details', step:0, rows:[{k:cfg.noLabel, v:val.no},{k:'Date', v:fdate(val.date)},{k:'Main account', v:val.party},{k:'Note', v:val.note||'—'}]},
        {title:'Accounts ('+st.jl.length+')', step:1, rows: st.jl.map(function(j){ return {k:(j.side==='Dr'?'Goes to · ':'Comes from · ')+j.name, v:inr(j.amt), cls:'kv'}; })}
      ];
    } else {
      sections = [
        {title:'Details', step:0, rows:[{k:cfg.noLabel, v:val.no},{k:'Date', v:fdate(val.date)},{k:cfg.partyLabel, v:val.party},{k:'Against bill', v:val.ref||'—'},{k:cfg.amtLabel, v:inr(payAmt), cls:'kv strong'},{k:'Note', v:val.note||'—'}]},
        {title:'How paid', step:1, rows:[{k:'Paid by', v:modeName}].concat(mode!=='cash'?[{k:'Bank name', v:val.bank||'—'},{k:'Reference no.', v:val.utr||'—'}]:[]).concat([{k:cfg.accLabel, v:val.acc}])}
      ];
    }
    sections = sections.map(function(s){ return Object.assign({}, s, {edit:setStep(s.step), rows:s.rows.map(function(r){ return Object.assign({cls:'kv'}, r); })}); });
    var heroAmt = cfg.items ? tot.total : (f.type==='journal' ? drSum : payAmt);
    var fl = {
      title:cfg.title, sub:cfg.sub, d:IC[cfg.ic], c:cfg.c, noLabel:cfg.noLabel, partyLabel:cfg.partyLabel, amtLabel:cfg.amtLabel, balLabel:cfg.balLabel, accLabel:cfg.accLabel,
      steps: cfg.steps.map(function(t,i){ return {t:t, n:i+1, done:i<f.step, todo:i>=f.step, cls:'st'+(i<f.step?' done':(i===f.step?' cur':''))}; }),
      isDetails:f.step===0, isItems:!!cfg.items && f.step===1, isPay:!!cfg.items && f.step===2, isMode:!cfg.items && f.type!=='journal' && f.step===1, isLedgers:f.type==='journal' && f.step===1, isSummary:f.step===last,
      notLast:f.step<last, notJournal:f.type!=='journal', showSupInv:f.type==='purchase', showAmt:!cfg.items && f.type!=='journal', showRef:!cfg.items && f.type!=='journal', showDue:!!cfg.items,
      v:val, h:hh, partyInit:initials(val.party),
      openParty:function(){ if(f.type==='journal') self.openPick('Choose account', 'jParty', LEDGERS); else self.openPick('Choose '+(cfg.list==='c'?'customer':'supplier'), P+'Party', poolFor(cfg.list).map(function(p){ return {t:p.name, s:(p.type==='c'?'Customer':'Supplier')+' · '+p.city}; })); },
      newParty:function(){ self.setState(function(p){ return {overlay:'newParty', npKey:P+'Party', npType:cfg.list, form:Object.assign({}, p.form, {npName:'', npPhone:'', npCity:''})}; }); },
      openAcc:function(){ self.openPick(cfg.accLabel, P+'Acc', ACCOUNTS); },
      accIcon: /Cash/.test(val.acc||'') ? IC.cash : IC.bank,
      lineCount:lines.length, noLines:!lines.length,
      lines: lines.map(function(l,i){ var upd=function(fn){ self.setState(function(p){ var L=Object.assign({}, p.lines); L[f.type]=p.lines[f.type].map(function(x,j){ return j===i?fn(x):x; }).filter(function(x){ return x.qty>0; }); return {lines:L}; }); };
        return {name:l.name, rateTxt:inr(l.rate)+' × '+l.qty+' '+l.unit+' · GST '+l.gst+'%', amtTxt:inr(l.rate*l.qty), qtyTxt:l.qty+' '+l.unit,
          inc:function(){ upd(function(x){ return Object.assign({}, x, {qty:x.qty+1}); }); },
          dec:function(){ upd(function(x){ return Object.assign({}, x, {qty:Math.max(1,x.qty-1)}); }); },
          del:function(){ upd(function(x){ return Object.assign({}, x, {qty:0}); }); self.say('Item removed'); }}; }),
      subTxt:inr(tot.sub), gstTxt:inr(tot.gst), totalTxt:inr(tot.total), amtTxt:inr(payAmt),
      balTxt:inr(Math.max(bal,0)), balCls: bal>0 ? 'tot b' : 'tot c',
      modes: MODES.map(function(m){ return {t:m.t, d:IC[m.ic], cls:'glass mode tap'+(m.id===mode?' on':''), pick:function(){ self.setState(function(p){ var o=Object.assign({}, p.modes); o[f.type]=m.id; var patch={modes:o}; if(f.type==='receipt'||f.type==='payment'){ var fm=Object.assign({}, p.form); fm[P+'Acc'] = m.id==='cash'?'Cash in hand':(f.type==='receipt'?'HDFC Bank – Current':'ICICI Bank – Current'); patch.form=fm; } return patch; }); }}; }),
      bankShow: mode!=='cash',
      openPicker:function(){ self.setState(function(p){ return {overlay:'picker', form:Object.assign({}, p.form, {pickQ:''})}; }); },
      drTxt:inr(drSum), crTxt:inr(crSum), balanced: drSum===crSum && drSum>0, unbalanced: !(drSum===crSum && drSum>0), diffTxt:inr(Math.abs(drSum-crSum)),
      jl: st.jl.map(function(j,i){ var upd=function(fn){ self.setState(function(p){ return {jl:p.jl.map(function(x,k){ return k===i?fn(x):x; }).filter(function(x){ return !x._del; })}; }); };
        return {name:j.name, grp:j.grp, amt:String(j.amt), sideTxt:j.side==='Dr'?'Goes to':'From', sideCls:'jside tap '+(j.side==='Dr'?'jdr':'jcr'),
          flip:function(){ upd(function(x){ return Object.assign({}, x, {side:x.side==='Dr'?'Cr':'Dr'}); }); },
          onAmt:function(e){ var v=String(e.target.value).replace(/[^0-9]/g,''); upd(function(x){ return Object.assign({}, x, {amt:v===''?0:Number(v)}); }); },
          del:function(){ upd(function(x){ return Object.assign({}, x, {_del:true}); }); }}; }),
      addJl:function(){ self.openPick('Add account', '__jl', LEDGERS); },
      sections:sections, heroNo: f.type==='sales'?'Sales '+val.no:val.no, heroAmt:inr(heroAmt), heroDate:'Date: '+fdate(val.date)+(cfg.items?' · Pay by: '+fdate(val.due):''),
      canDraft: !!cfg.draft && f.step===last,
      nextOff: (!!cfg.items && f.step===1 && !lines.length) || (f.type==='journal' && f.step===1 && !(drSum===crSum && drSum>0)) || (f.step===0 && !val.party),
      prevLabel: f.step===0?'Cancel':'Back',
      prev:function(){ if(self.state.flow.step>0) self.setState(function(p){ return {flow:{type:p.flow.type, step:p.flow.step-1}}; }); else self.back(); },
      next:function(){ self.setState(function(p){ return {flow:{type:p.flow.type, step:Math.min(p.flow.step+1, last)}}; }); },
      save:function(){ self.saveFlow(false); }, draft:function(){ self.saveFlow(true); }
    };

    // pick sheet
    var pk = {title:'', rows:[]};
    if(st.pick){ var pq=(form.pq||'').toLowerCase(); var cur=form[st.pick.key]; pk = {title:st.pick.title, rows: st.pick.opts.filter(function(o){ return !pq || o.t.toLowerCase().indexOf(pq)>=0; }).map(function(o){ return {t:o.t, s:o.s, init:initials(o.t), sel:o.t===cur, choose:function(){ self.choosePick(o.t, o.s); }}; })}; }
    var npOff = !(form.npName||'').trim();
    var saveParty = function(){ var nm=self.state.form.npName.trim(); if(!nm) return; var np={name:nm, type:self.state.npType||'c', city:self.state.form.npCity||'—', bal:0}; self.setState(function(p){ var fm=Object.assign({}, p.form); if(p.npKey) fm[p.npKey]=nm; return {extraParties:p.extraParties.concat([np]), form:fm, overlay:null}; }); self.say(nm+' added'); };
    var npHint = st.npType==='s' ? 'A supplier you buy from' : 'A customer you sell to';

    // item picker
    var cl = st.lines[f.type] || [];
    var pqq = (form.pickQ||'').toLowerCase();
    var pkr = {
      rows: ITEMS.filter(function(it){ return !pqq || it.name.toLowerCase().indexOf(pqq)>=0; }).map(function(it){
        var idx = cl.findIndex(function(l){ return l.name===it.name; }); var sel=idx>=0; var qty = sel?cl[idx].qty:0;
        var upd=function(fn){ self.setState(function(p){ var L=Object.assign({}, p.lines); L[f.type]=fn(p.lines[f.type]||[]); return {lines:L}; }); };
        return {name:it.name, init:initials(it.name), sel:sel, avBg: sel?'linear-gradient(160deg,var(--acc2),var(--acc3))':'linear-gradient(160deg,var(--navy2),var(--navy))', stock: it.stock>0 ? it.stock+' '+it.unit+' in stock' : 'Out of stock', rate:inr(it.rate)+' / '+it.unit, qty:qty+' '+it.unit,
          cls:'glass'+(sel?' selrow':''), radio: sel?'tk':'tk tk-off',
          toggle:function(){ upd(function(L){ var i=L.findIndex(function(l){ return l.name===it.name; }); if(i>=0) return L.filter(function(_,j){ return j!==i; }); return L.concat([{name:it.name, rate:it.rate, qty:1, unit:it.unit, gst:18}]); }); },
          inc:function(){ upd(function(L){ return L.map(function(l){ return l.name===it.name?Object.assign({}, l, {qty:l.qty+1}):l; }); }); },
          dec:function(){ upd(function(L){ return L.map(function(l){ return l.name===it.name?Object.assign({}, l, {qty:Math.max(1,l.qty-1)}):l; }); }); }}; }),
      countTxt: cl.length+' items picked', totalTxt: inr(this.totals(cl).total),
      addNew:function(){ self.setState({overlay:'addItem'}); }
    };
    // add new item
    var nq=Number(form.niQty)||0, nr=Number(form.niRate)||0, nd=Number(form.niDisc)||0, nsub=nq*nr*(1-nd/100), ngst=nsub*st.ni.gst/100;
    var chipsOf=function(list, key){ return list.map(function(v){ return {t:(key==='gst'?v+'%':v), cls:st.ni[key]===v?'on':'', pick:function(){ self.setState(function(p){ var n=Object.assign({}, p.ni); n[key]=v; return {ni:n}; }); }}; }); };
    var ni = { cats:chipsOf(['General','Wires & Cables','Lighting','Switches','Switchgear','Fans'],'cat'), units:chipsOf(['PCS','NOS','COIL','BOX','MTR'],'unit'), gsts:chipsOf([0,5,12,18,28],'gst'),
      calcSub:'Before GST '+inr2(nsub)+' + GST '+inr2(ngst), calcTot:inr2(nsub+ngst), off: !(form.niName||'').trim() || !nq || !nr,
      back:function(){ self.setState({overlay:'picker'}); },
      add:function(){ var nm=self.state.form.niName.trim(); self.setState(function(p){ var L=Object.assign({}, p.lines); L[f.type]=(p.lines[f.type]||[]).concat([{name:nm, rate:Math.round(nr*(1-nd/100)*100)/100, qty:nq, unit:p.ni.unit.toLowerCase(), gst:p.ni.gst}]); return {lines:L, overlay:null, form:Object.assign({}, p.form, {niName:'', niRate:'', niQty:'1', niDisc:'0', niHsn:''})}; }); self.say(nm+' added to bill'); } };

    // vouchers
    var vsum = [ {t:'Sales', v:348690, bg:'color-mix(in srgb,var(--acc) 9%,transparent)', f:'sales', cls:'amt'}, {t:'Purchase', v:126850, bg:'color-mix(in srgb,var(--navy2) 8%,transparent)', f:'purchase', cls:'amt'}, {t:'Money in', v:215000, bg:'color-mix(in srgb,var(--pos) 10%,transparent)', f:'receipt', cls:'amt in'}, {t:'Money out', v:98450, bg:'color-mix(in srgb,var(--warn) 9%,transparent)', f:'payment', cls:'amt out'} ];
    var vh = {
      sums: vsum.map(function(m){ return {t:m.t, v:inr(m.v), bg:m.bg, cls:m.cls, go:go('vList',{vFilter:m.f, vPeriod:'month'})}; }),
      tiles: [ {k:'all', t:'All', ic:'receipt', c:C.vouchers}, {k:'sales', t:'Sales', ic:'bag', c:C.sales}, {k:'purchase', t:'Purchase', ic:'cart', c:C.purchase}, {k:'receipt', t:'Money In', ic:'in', c:C.receipt}, {k:'payment', t:'Money Out', ic:'out', c:C.payment}, {k:'journal', t:'Adjustment', ic:'book', c:C.journal}, {k:'contra', t:'Bank ↔ Cash', ic:'swap', c:C.contra} ].map(function(t){ var n = VOUCH.filter(function(v){ return t.k==='all'||v.kind===t.k; }).length; return {t:t.t, s:n+' this month', d:IC[t.ic], c:t.c, go:go('vList',{vFilter:t.k, vPeriod:'month'})}; })
    };
    var VF = [ {k:'all', t:'All'}, {k:'sales', t:'Sales'}, {k:'purchase', t:'Purchase'}, {k:'receipt', t:'Money In'}, {k:'payment', t:'Money Out'}, {k:'journal', t:'Adjustment'}, {k:'contra', t:'Bank ↔ Cash'} ];
    var vrows = VOUCH.filter(function(v){ return (st.vFilter==='all'||v.kind===st.vFilter) && (st.vPeriod==='month' || (st.vPeriod==='week'?v.day>=20:v.day===26)); });
    var vk = st.vFilter==='all' ? {ic:'receipt', c:C.vouchers} : KIND[st.vFilter];
    var vl = {
      title: st.vFilter==='all' ? 'All Vouchers' : (VF.find(function(x){ return x.k===st.vFilter; })||{}).t, d:IC[vk.ic], c:vk.c,
      count: vrows.length, total: inr(vrows.reduce(function(s,v){ return s+v.amt; },0)), empty: !vrows.length,
      chips: VF.map(function(x){ return {t:x.t, cls:'glass chip tap'+(st.vFilter===x.k?' on':''), pick:function(){ self.setState({vFilter:x.k}); }}; }),
      periods: [ {k:'month', t:'This month'}, {k:'week', t:'Last 7 days'}, {k:'today', t:'Today'} ].map(function(x){ return {t:x.t, cls:st.vPeriod===x.k?'on':'', pick:function(){ self.setState({vPeriod:x.k}); }}; }),
      rows: L('vouchers', vrows.map(function(v){ var k=KIND[v.kind]; return {no:v.no, party:v.party, meta:v.no+' · '+v.day+' Sep', d:IC[k.ic], c:k.c, amt:(k.sign>0&&v.kind==='receipt'?'+':k.sign<0&&v.kind==='payment'?'−':'')+inr(v.amt), cls:'amt'+(v.kind==='receipt'?' in':v.kind==='payment'?' out':''), open:go('entryDetail',{entry:v})}; }), function(x){ return x.no; }, function(x){ return x.party+' · '+x.no; }, 'row tap')
    };
    // entry detail
    var e = st.entry || VOUCH[0], ek = KIND[e.kind];
    var ed = { kind:ek.long, no:e.no, party:e.party, d:IC[ek.ic], c:ek.c, amt:inr(e.amt), cls:'amt big'+(e.kind==='receipt'?' in':e.kind==='payment'?' out':''),
      rows:[{k:'Type', v:ek.long},{k:'Number', v:e.no},{k:'Date', v:e.day+' Sep 2026'},{k:'Party / account', v:e.party},{k:'Amount', v:inr(e.amt)},{k:'Company', v:company.name.split(' - ')[0]}],
      share:say('Share sheet opened'), pdf:function(){ self.setState({overlay:'pdf', zoom:100, pdf:{party:e.party, no:e.no, date:e.day+' Sep 2026', due:'—', total:e.amt, kind:ek.t, city:(PARTIES.find(function(p){ return p.name===e.party; })||{}).city||''}}); } };

    // outstanding
    var mkBill = function(b, kind){ var late=b.st==='late', soon=b.st==='soon'; return {party:b.party, no:b.no, city:b.city, init:initials(b.party), txt:b.txt, amt:(kind==='recv'?'+':'−')+inr(b.amt), cls:'amt '+(kind==='recv'?'in':'out'), stCls:'badge b-dot '+(late?'b-bad':soon?'b-warn':'b-info'), d:IC[kind==='recv'?'in':'out'], c:kind==='recv'?C.receipt:C.payment, open:go('billDetail',{bill:Object.assign({kind:kind}, b)})}; };
    var oh = {
      cards:[ {t:'To get', s:'Others owe you (Receivable)', d:IC.in, c:C.receipt, v:inr(348690), cls:'amt big in', parties:'6 parties', late:inr(113870)+' late', go:go('outList',{outKind:'recv', outFilter:'all'})},
              {t:'To give', s:'You owe others (Payable)', d:IC.out, c:C.payment, v:inr(126850), cls:'amt big out', parties:'5 parties', late:inr(17700)+' late', go:go('outList',{outKind:'pay', outFilter:'all'})} ],
      soon:[ mkBill(RECV[4],'recv'), mkBill(PAYB[0],'pay'), mkBill(PAYB[2],'pay'), mkBill(RECV[5],'recv') ]
    };
    var isR = st.outKind==='recv', BL = isR?RECV:PAYB;
    var OF = [ {k:'all', t:'All'}, {k:'late', t:'Late'}, {k:'soon', t:'Due soon'}, {k:'ok', t:'Later'} ];
    var onTime = isR?234820:109150, late30 = isR?113870:17700, totO = isR?348690:126850;
    var ol = { title: isR?'To get':'To give', sub: isR?'Money others owe you (Receivable)':'Money you owe others (Payable)', s: isR?'Others owe you':'You owe others',
      d:IC[isR?'in':'out'], c:isR?C.receipt:C.payment, cls:'amt big '+(isR?'in':'out'), total:inr(totO), parties:BL.length+' parties', late:inr(late30)+' late',
      bulkTxt: isR?'Send reminders to 2 late customers':'Pay 2 late bills', bulkIc: isR?IC.chat:IC.out,
      bulk: isR ? say('WhatsApp reminders sent to 2 customers') : function(){ self.startFlow('payment', {yParty:'Anchor Electricals', yAmt:'11800', yRef:'Against PI-0002'}); },
      autoT: isR?'Auto reminders':'Payment alerts', autoS: isR?(st.autoRemind?'WhatsApp reminders are on':'Reminders are off'):(st.autoRemind?'Alert me 3 days before due':'Alerts are off'),
      autoCls:'sw'+(st.autoRemind?' on':''), toggleAuto:function(){ self.setState({autoRemind:!self.state.autoRemind}); },
      ageing:[ {t:'On time (not due yet)', v:inr(onTime), w:Math.round(onTime/totO*100), c:'var(--pos)'}, {t:'1–30 days late', v:inr(late30), w:Math.max(2,Math.round(late30/totO*100)), c:'var(--warn)'}, {t:'31–60 days late', v:inr(0), w:0, c:'var(--neg)'}, {t:'More than 60 days late', v:inr(0), w:0, c:'var(--acc3)'} ],
      chips: OF.map(function(x){ return {t:x.t, cls:'glass chip tap'+(st.outFilter===x.k?' on':''), pick:function(){ self.setState({outFilter:x.k}); }}; }),
      rows: L('bills', BL.filter(function(b){ return st.outFilter==='all' || b.st===st.outFilter; }).map(function(b){ return mkBill(b, st.outKind); }), function(x){ return x.no; }, function(x){ return x.party+' · '+x.no; }, 'row tap')
    };
    // bill detail
    var b = st.bill || Object.assign({kind:'recv'}, RECV[0]), bR = b.kind==='recv', bst=b.st;
    var bd = { party:b.party, no:b.no, init:initials(b.party), city:b.city, kind: bR?'Sales bill':'Purchase bill', role: bR?'Customer':'Supplier',
      balLabel: bR?'Still to get':'Still to pay', amt:inr(b.amt), cls:'amt big '+(bR?'in':'out'), txt:b.txt, stCls:'badge b-dot '+(bst==='late'?'b-bad':bst==='soon'?'b-warn':'b-info'),
      file: b.no.replace(' ','_')+'.pdf', isRecv:bR,
      rows:[{k:'Bill number', v:b.no},{k:'Bill type', v:bR?'Sales bill':'Purchase bill'},{k:'Bill date', v:b.bill},{k:'Pay by', v:b.due},{k:'Credit time', v:b.credit}],
      pdf:function(){ self.setState({overlay:'pdf', zoom:100, pdf:{party:b.party, no:b.no, date:b.bill, due:b.due, total:b.amt, kind:bR?'Sales bill':'Purchase bill', city:b.city, recv:bR}}); },
      share:say('Share sheet opened'), download:say('Saved to Downloads'), remind:say('Reminder sent on WhatsApp to '+b.party),
      recTxt: bR?'Record Money In':'Record Money Out', recIc: bR?IC.in:IC.out,
      record:function(){ if(bR) self.startFlow('receipt', {rParty:b.party, rAmt:String(b.amt), rRef:'Against '+b.no}); else self.startFlow('payment', {yParty:b.party, yAmt:String(b.amt), yRef:'Against '+b.no}); } };
    // pdf
    var pd0 = st.pdf || {party:'Shree Balaji Traders', no:'Sales 9', date:'21 Sep 2026', due:'06 Oct 2026', total:112100, kind:'Sales bill', city:'Mumbai', recv:true};
    var isS9 = pd0.no==='Sales 9';
    var taxable = isS9 ? 95000 : Math.round(pd0.total/1.18); var cg = isS9 ? 8550 : Math.round((pd0.total-taxable)/2);
    var pdf = { file:pd0.no.replace(' ','_')+'.pdf', kind:pd0.kind, party:pd0.party, no:pd0.no, date:pd0.date, due:pd0.due, city:pd0.city+(isS9?' · GSTIN: 27AAKFS2291M1Z8':''),
      heading: pd0.recv===false || /PI|Purchase/.test(pd0.kind) ? 'PURCHASE BILL' : 'TAX INVOICE', toLabel: pd0.recv===false || /PI|Purchase/.test(pd0.kind) ? 'BILL FROM' : 'BILLED TO',
      lines: isS9 ? SALES9.map(function(l,i){ return {n:i+1, name:l.name, hsn:l.hsn, qty:l.qty, rate:l.rate, amt:inr(l.amt)}; }) : [{n:1, name:'Goods as per Tally entry', hsn:'—', qty:'—', rate:'—', amt:inr(taxable)}],
      sub:inr(taxable), cgst:inr(cg), total:inr(pd0.total), scale:st.zoom/100, zoomTxt:st.zoom+'%',
      zoomIn:function(){ self.setState({zoom:Math.min(160, self.state.zoom+20)}); }, zoomOut:function(){ self.setState({zoom:Math.max(60, self.state.zoom-20)}); },
      share:say('Share sheet opened'), download:say('Saved to Downloads') };

    // items
    var iq=(form.itemQ||'').toLowerCase();
    var irows = ITEMS.filter(function(x){ return (st.itemsFilter==='all'||x.st===st.itemsFilter) && (!iq || x.name.toLowerCase().indexOf(iq)>=0); });
    var it = { value:inr(ITEMS.reduce(function(s,x){ return s+x.stock*x.rate; },0)), count:ITEMS.length, low:ITEMS.filter(function(x){ return x.st==='low'; }).length, out:ITEMS.filter(function(x){ return x.st==='out'; }).length,
      segs:[ {k:'all', t:'All (8)'}, {k:'low', t:'Low (2)'}, {k:'out', t:'Finished (2)'} ].map(function(s){ return {t:s.t, cls:st.itemsFilter===s.k?'on':'', pick:function(){ self.setState({itemsFilter:s.k}); }}; }),
      rows: L('items', irows.map(function(x){ return {md:IC.box, mc:C.items, mopen:go('report',{report:'stock'}), name:x.name, stock: x.stock>0 ? x.stock+' '+x.unit : 'Finished', stCls:'badge '+(x.st==='ok'?'b-ok':x.st==='low'?'b-warn':'b-bad'), rate:inr(x.rate)+' / '+x.unit, value:inr(x.stock*x.rate)}; }), function(x){ return x.name; }, function(x){ return x.name; }, 'row'),
      empty: !irows.length, scan:say('Point the camera at a barcode'), share:say('Stock list shared') };

    // party
    var pq2=(form.partyQ||'').toLowerCase(); var pool=this.partyPool();
    var prow = pool.filter(function(p){ return (st.partyFilter==='all'||p.type===st.partyFilter) && (!pq2 || p.name.toLowerCase().indexOf(pq2)>=0); }).slice();
    if(st.partySort==='amt') prow.sort(function(a,b){ return b.bal-a.bal; }); else prow.sort(function(a,b){ return a.name.localeCompare(b.name); });
    var pv = { total:pool.length, cust:pool.filter(function(p){ return p.type==='c'; }).length, supp:pool.filter(function(p){ return p.type==='s'; }).length,
      segs:[ {k:'all', t:'All'}, {k:'c', t:'Customers'}, {k:'s', t:'Suppliers'} ].map(function(s){ return {t:s.t, cls:st.partyFilter===s.k?'on':'', pick:function(){ self.setState({partyFilter:s.k}); }}; }),
      sortLabel: st.partySort==='amt' ? 'Sorted by balance · tap ⇅ for A–Z' : 'Sorted A–Z · tap ⇅ for balance',
      toggleSort:function(){ self.setState({partySort:self.state.partySort==='amt'?'az':'amt'}); },
      addParty:function(){ self.setState(function(p){ return {overlay:'newParty', npKey:null, npType:'c', form:Object.assign({}, p.form, {npName:'', npPhone:'', npCity:''})}; }); },
      rows: L('party', prow.map(function(p){ var c=p.type==='c'; return {md:IC.person, mc:C.party, name:p.name, init:initials(p.name), city:p.city, role:c?'Customer':'Supplier', bal:inr(p.bal), cls:'amt '+(p.bal===0?'':(c?'in':'out')), owe: p.bal===0?'Settled':(c?'They owe you':'You owe'), open:go('partyDetail',{party:p.name, partyTab:'summary'})}; }), function(x){ return x.name; }, function(x){ return x.name; }, 'row tap'),
      empty: !prow.length };
    var P0 = pool.find(function(p){ return p.name===st.party; }) || PARTIES[0], pc = P0.type==='c';
    var pvouch = VOUCH.filter(function(v){ return v.party===P0.name; });
    var pd = { name:P0.name, init:initials(P0.name), city:P0.city, role:pc?'Customer':'Supplier', bal:inr(P0.bal)+(P0.bal?(pc?' Dr':' Cr'):''), cls:'amt big '+(pc?'in':'out'),
      owe: P0.bal===0?'All settled':(pc?'They owe you':'You owe them'), bg: pc?'color-mix(in srgb,var(--pos) 10%,transparent)':'color-mix(in srgb,var(--warn) 9%,transparent)',
      tabs:[ {k:'summary', t:'Summary'}, {k:'items', t:'Items'}, {k:'vouchers', t:'Entries'} ].map(function(s){ return {t:s.t, cls:st.partyTab===s.k?'on':'', pick:function(){ self.setState({partyTab:s.k}); }}; }),
      isSummary:st.partyTab==='summary', isItems:st.partyTab==='items', isVouchers:st.partyTab==='vouchers',
      rows: P0.name==='Shree Balaji Traders' ? [{k:'Group', v:'Customers (Sundry Debtors)'},{k:'City', v:'Mumbai'},{k:'GSTIN', v:'27AAKFS2291M1Z8'},{k:'Address', v:'Shop No. 12, Market Road, Kurla, Mumbai – 400070'},{k:'Contact person', v:'Rakesh Agarwal'},{k:'Phone', v:'+91 98298 48278'},{k:'Email', v:'accounts@shreebalaji.in'},{k:'Credit time', v:'30 days'},{k:'Opening balance (1 Apr 2026)', v:'₹12,540 Dr'}]
        : [{k:'Group', v:pc?'Customers (Sundry Debtors)':'Suppliers (Sundry Creditors)'},{k:'City', v:P0.city},{k:'Entries this month', v:String(pvouch.length)}],
      items: P0.name==='Shree Balaji Traders' ? SALES9.map(function(l){ return {name:l.name, sub:l.qty+' · '+l.rate, amt:inr(l.amt)}; }) : [],
      vouchers: pvouch.map(function(v){ var k=KIND[v.kind]; return {kind:k.t, no:v.no, date:v.day+' Sep 2026', d:IC[k.ic], c:k.c, amt:inr(v.amt), cls:'amt', open:go('entryDetail',{entry:v})}; }),
      remind:say('Reminder sent on WhatsApp to '+P0.name), share:say('Party details shared'),
      newTxt: pc?'New Sale':'New Purchase',
      newEntry:function(){ if(pc) self.startFlow('sales', {sParty:P0.name}); else self.startFlow('purchase', {pParty:P0.name}); } };
    pd.noItems = !pd.items.length; pd.noVouchers = !pd.vouchers.length;

    // reports
    var RC = [ {k:'all', t:'All'}, {k:'sales', t:'Sales'}, {k:'party', t:'Party'}, {k:'stock', t:'Stock'}, {k:'accounts', t:'Accounts'} ];
    var rv = { top:'Shree Balaji Traders', exp:inr(186450), inC:'2 customers', inI:'2 items', day:'21 entries', sreg:inr(348690), preg:inr(126850), stock:it.value };
    var rp = { chips: RC.map(function(x){ return {t:x.t, cls:'glass chip tap'+(st.repCat===x.k?' on':''), pick:function(){ self.setState({repCat:x.k}); }}; }),
      cards: L('reports', REPORTS.filter(function(r){ return st.repCat==='all'||r.cat===st.repCat; }).map(function(r){ return {id:r.id, t:r.t, s:r.s, v:rv[r.id], d:IC[r.ic], c:r.c, open:go('report',{report:r.id})}; }), function(x){ return x.id; }, function(x){ return x.t; }, 'glass sumc tap') };
    var R0 = REPORTS.find(function(r){ return r.id===st.report; }) || REPORTS[0];
    var AV = ['var(--navy2)','var(--c-sales)','var(--c-reports)','var(--c-items)','var(--acc)'];
    var rrows=[], rtot='', rtl='Total';
    if(R0.id==='top'){ rrows = RECV.slice().sort(function(a,b){ return b.amt-a.amt; }).slice(0,5).map(function(x,i){ return {n:i+1, t:x.party, s:x.city+' · '+x.no, v:inr(x.amt), cls:'amt in'}; }); rtot=inr(RECV.slice().sort(function(a,b){ return b.amt-a.amt; }).slice(0,5).reduce(function(s,x){ return s+x.amt; },0)); rtl='Top 5 owe you'; }
    else if(R0.id==='exp'){ rrows = [ {t:'Salaries A/c', s:'Indirect expense', v:120000}, {t:'Rent A/c', s:'Indirect expense', v:35000}, {t:'Depreciation A/c', s:'Indirect expense', v:24500}, {t:'Freight Charges', s:'Direct expense', v:6950} ].map(function(x,i){ return {n:i+1, t:x.t, s:x.s, v:inr(x.v), cls:'amt out'}; }); rtot=inr(186450); rtl='All expenses · Sep'; }
    else if(R0.id==='inC'){ rrows = PARTIES.filter(function(p){ return p.type==='c' && p.bal===0; }).map(function(p,i){ return {n:initials(p.name), t:p.name, s:p.city+' · no sale in 60 days', v:'—', cls:'amt'}; }); rtot='2'; rtl='Quiet customers'; }
    else if(R0.id==='inI'){ rrows = ITEMS.filter(function(x){ return x.st==='out'; }).map(function(x){ return {n:initials(x.name), t:x.name, s:'Finished · not sold this month', v:inr(0), cls:'amt'}; }); rtot='2'; rtl='Items not moving'; }
    else if(R0.id==='day'){ rrows = VOUCH.slice().sort(function(a,b){ return b.day-a.day; }).map(function(v){ var k=KIND[v.kind]; return {n:v.day, t:v.party, s:k.t+' · '+v.no, v:inr(v.amt), cls:'amt'}; }); rtot=inr(918490); rtl='21 entries · value'; }
    else if(R0.id==='sreg' || R0.id==='preg'){ var kk=R0.id==='sreg'?'sales':'purchase'; var L2=VOUCH.filter(function(v){ return v.kind===kk; }); rrows = L2.map(function(v){ return {n:v.day, t:v.party, s:v.no+' · '+v.day+' Sep', v:inr(v.amt), cls:'amt'}; }); rtot=inr(L2.reduce(function(s,v){ return s+v.amt; },0)); rtl=L2.length+' bills'; }
    else { rrows = ITEMS.map(function(x){ return {n:initials(x.name), t:x.name, s:x.stock+' '+x.unit+' × '+inr(x.rate), v:inr(x.stock*x.rate), cls:'amt'}; }); rtot=it.value; rtl='Stock value'; }
    var rd = { t:R0.t, s:R0.s+' · September 2026', d:IC[R0.ic], c:R0.c, tot:rtot, totLabel:rtl, share:say('Report shared'),
      rows: rrows.map(function(r,i){ return Object.assign({bg:AV[i%AV.length]}, r, {n:String(r.n)}); }) };

    // activity
    var AF = [ {k:'all', t:'All'}, {k:'sales', t:'Sales'}, {k:'purchase', t:'Purchase'}, {k:'receipt', t:'Money In'}, {k:'payment', t:'Money Out'}, {k:'journal', t:'Adjustment'} ];
    var stMeta = { ok:{t:'Sent', cls:'badge b-dot b-ok', col:'var(--pos)'}, wait:{t:'Waiting', cls:'badge b-dot b-warn', col:'var(--warn)'}, fail:{t:'Not sent', cls:'badge b-dot b-bad', col:'var(--neg)'} };
    var arows = st.acts.filter(function(a){ return st.actFilter==='all' || a.kind===st.actFilter; });
    var av = { ok:st.acts.filter(function(a){ return a.status==='ok'; }).length, wait:st.acts.filter(function(a){ return a.status==='wait'; }).length, fail:st.acts.filter(function(a){ return a.status==='fail'; }).length,
      chips: AF.map(function(x){ return {t:x.t, cls:'glass chip tap'+(st.actFilter===x.k?' on':''), pick:function(){ self.setState({actFilter:x.k}); }}; }),
      rows: L('acts', arows.map(function(a){ var k=KIND[a.kind], m=stMeta[a.status]; return {id:a.id, title:k.t+' · '+a.no, party:a.party, amt:inr(a.amt), time:a.time, d:IC[k.ic], c:k.c, stTxt:m.t, stCls:m.cls, note: a.note || (a.status==='wait'?'Waiting for Tally to open':''), canRetry:a.status==='fail', retry:function(){ self.retry(a.id); }, open:go('actDetail',{act:a.id})}; }), function(x){ return x.id; }, function(x){ return x.title; }, 'row'),
      empty: !arows.length,
      syncAll:function(){ var f1=self.state.acts.find(function(a){ return a.status==='fail'; }); if(f1) self.retry(f1.id); else self.say('Everything is up to date'); } };
    var A0 = st.acts.find(function(a){ return a.id===st.act; }) || st.acts[0], ak=KIND[A0.kind], am=stMeta[A0.status];
    var ad = { kind:ak.long, no:'Entry no: '+A0.no, amt:inr(A0.amt), party:A0.party, d:IC[ak.ic], stTxt:am.t.toUpperCase(), stColor:am.col,
      bannerCls: A0.status==='ok'?'okb':'warn', bannerIc: A0.status==='ok'?IC.check:(A0.status==='fail'?IC.xCircle:IC.sync),
      banner: A0.status==='ok' ? 'Reached Tally' : (A0.status==='fail' ? 'Not sent — '+(A0.note||'Tally was closed') : 'Waiting for Tally · will send by itself when Tally is open'),
      canRetry: A0.status==='fail', retry:function(){ self.retry(A0.id); },
      rows: A0.no==='Sales 11' ? [{k:'Entry number', v:'Sales 11'},{k:'Date', v:'26 Sep 2026'},{k:'Pay by', v:'11 Oct 2026'},{k:'Paid by', v:'Cash · ₹5,000 received'},{k:'Reference no.', v:'MOBILE-1790574691025'},{k:'Party GSTIN', v:'27AAQFO5582D1Z1'},{k:'Place of supply', v:'Maharashtra (27)'},{k:'Status', v:'Part paid · ₹5,000 received'}]
        : [{k:'Entry number', v:A0.no},{k:'Party / account', v:A0.party},{k:'Amount', v:inr(A0.amt)},{k:'Saved', v:A0.time},{k:'Status', v:am.t}],
      hasItems: A0.no==='Sales 11',
      items: [ {name:'1. Havells FR Wire 1.5 sq mm (90 m)', sub:'Qty: 2 coil · Rate: ₹1,850 · GST 18% · HSN 8544', amt:inr(3700)}, {name:'2. Anchor Roma Switch 6A', sub:'Qty: 100 pcs · Rate: ₹34 · GST 18% · HSN 8536', amt:inr(3400)}, {name:'3. Polycab LED Panel 18W', sub:'Qty: 10 pcs · Rate: ₹520 · GST 18% · HSN 9405', amt:inr(5200)} ] };

    // team
    var tq=(form.teamQ||'').toLowerCase();
    var TS = { active:{t:'Active', cls:'badge b-dot b-ok'}, pending:{t:'Invite sent', cls:'badge b-dot b-warn'}, off:{t:'Turned off', cls:'badge b-dot b-info'} };
    var trows = st.team.filter(function(m){ return (st.teamFilter==='all'||m.st===st.teamFilter) && (!tq || (m.name+' '+m.email).toLowerCase().indexOf(tq)>=0); });
    var tm = {
      stats:[ {t:'Total', v:st.team.length, ic:'team', c:C.team}, {t:'Active', v:st.team.filter(function(m){ return m.st==='active'; }).length, ic:'check', c:C.receipt}, {t:'Pending', v:st.team.filter(function(m){ return m.st==='pending'; }).length, ic:'clock', c:C.payment}, {t:'Off', v:st.team.filter(function(m){ return m.st==='off'; }).length, ic:'lock', c:C.settings} ].map(function(s){ return Object.assign({}, s, {d:IC[s.ic]}); }),
      segs:[ {k:'all', t:'All'}, {k:'active', t:'Active'}, {k:'pending', t:'Pending'}, {k:'off', t:'Off'} ].map(function(s){ return {t:s.t, cls:st.teamFilter===s.k?'on':'', pick:function(){ self.setState({teamFilter:s.k}); }}; }),
      countTxt: trows.length+' people', empty: !trows.length,
      rows: L('team', trows.map(function(m){ var s=TS[m.st]; return {md:IC.person, mc:C.team, name:m.name, email:m.email, role:m.role, init:initials(m.name), stTxt:s.t, stCls:s.cls, open:function(){ self.setState({overlay:'member', member:m.id}); }}; }), function(x){ return x.email; }, function(x){ return x.name; }, 'row tap'),
      invite:function(){ self.setState(function(p){ return {overlay:'invite', form:Object.assign({}, p.form, {iEmail:''})}; }); },
      create:function(){ self.setState(function(p){ return {overlay:'newUser', form:Object.assign({}, p.form, {nuName:'', nuPhone:''})}; }); },
      inviteOff: !/.+@.+\..+/.test(form.iEmail||''), userOff: !(form.nuName||'').trim(),
      sendInvite:function(){ var em=self.state.form.iEmail.trim(); self.setState(function(p){ return {overlay:null, team:p.team.concat([{id:'t'+Date.now(), name:em.split('@')[0], email:em, role:'Sales Rep', st:'pending'}])}; }); self.say('Invite sent to '+em); },
      saveUser:function(){ var nm=self.state.form.nuName.trim(); self.setState(function(p){ return {overlay:null, team:p.team.concat([{id:'t'+Date.now(), name:nm, email:p.form.nuPhone||'No email yet', role:'Sales Rep', st:'active'}])}; }); self.say(nm+' added to your team'); }
    };
    var M0 = st.team.find(function(m){ return m.id===st.member; }) || st.team[0], ms = TS[M0.st];
    var setM=function(v, msg){ return function(){ self.setState(function(p){ return {overlay:null, team:p.team.map(function(x){ return x.id===M0.id?Object.assign({}, x, {st:v}):x; })}; }); self.say(msg); }; };
    var mb = { name:M0.name, email:M0.email, init:initials(M0.name), stTxt:ms.t, stCls:ms.cls,
      actions: M0.st==='active' ? [ {t:'Turn off access', ic:'lock', color:'var(--neg)', go:setM('off', M0.name+' turned off')} ]
             : M0.st==='off' ? [ {t:'Turn on access', ic:'check', color:'var(--pos)', go:setM('active', M0.name+' turned on')} ]
             : [ {t:'Send invite again', ic:'send', color:'var(--navy)', go:function(){ self.setState({overlay:null}); self.say('Invite sent again'); }}, {t:'Cancel invite', ic:'close', color:'var(--neg)', go:function(){ self.setState(function(p){ return {overlay:null, team:p.team.filter(function(x){ return x.id!==M0.id; })}; }); self.say('Invite cancelled'); }} ] };
    mb.actions = mb.actions.map(function(a){ return Object.assign({}, a, {d:IC[a.ic]}); });

    // settings
    var PREFS = [ {k:'pay', t:'Money received', s:'When a customer pays you', ic:'in', c:C.receipt}, {k:'sync', t:'Sent to Tally', s:'When entries reach Tally', ic:'sync', c:C.activity}, {k:'due', t:'Bills due soon', s:'3 days before a bill is due', ic:'calendar', c:C.payment}, {k:'team', t:'Team updates', s:'Invites and new members', ic:'team', c:C.team}, {k:'wa', t:'WhatsApp reminders', s:'Send reminders to customers', ic:'chat', c:C.sales} ];
    var sg = { tabs:[ {k:'profile', t:'Profile'}, {k:'alerts', t:'Alerts'}, {k:'plan', t:'Plan'}, {k:'look', t:'Look'} ].map(function(s){ return {t:s.t, cls:st.setTab===s.k?'on':'', pick:function(){ self.setState({setTab:s.k}); }}; }),
      isProfile:st.setTab==='profile', isAlerts:st.setTab==='alerts', isPlan:st.setTab==='plan', isLook:st.setTab==='look',
      profile:[ {k:'Username', v:'workk72002', ic:'person'}, {k:'Email', v:'workk72002@gmail.com', ic:'mail'}, {k:'Mobile', v:'+91 98200 45127', ic:'phone'}, {k:'Company', v:company.name.split(' - ')[0], ic:'building'}, {k:'Role', v:'Admin', ic:'shield'}, {k:'Plan', v:'Enterprise', ic:'star'} ].map(function(r){ return Object.assign({}, r, {d:IC[r.ic]}); }),
      prefs: PREFS.map(function(p){ var on=!!st.prefs[p.k]; return {t:p.t, s:p.s, d:IC[p.ic], c:p.c, on:on, cls:'sw'+(on?' on':''), toggle:function(){ self.setState(function(q){ var o=Object.assign({}, q.prefs); o[p.k]=!o[p.k]; return {prefs:o}; }); }}; }),
      glass:st.glass, glassTxt:st.glass+'%', onGlass:function(e){ self.setState({glass:Number(e.target.value)}); },
      presets:[20,40,60,80,100].map(function(v){ return {t:v+'%', cls:'glass tap'+(st.glass===v?' on':''), pick:function(){ self.setState({glass:v}); }}; }),
      reset:function(){ self.setState({glass:60, preset:'aurora', accent:'look', mode:'look', wallK:'theme', pendWall:null}); saveJ('tc-liquid-preset', 'aurora'); saveJ('tc-liquid-accent', 'look'); saveJ('tc-liquid-mode', 'look'); saveJ('tc-liquid-wall', 'theme'); self.say('Look set back to default'); },
      accents: (function(){ var sig=LOOKSIG[st.preset]||LOOKSIG.aurora; return [{k:'look', t:sig[0], swc:'palsw', sws:'background: linear-gradient(150deg, '+sig[1]+' 0%, '+sig[2]+' 100%)'}].concat((LOOKACC[st.preset]||[]).map(function(k){ var a=ACCENTS.find(function(x){ return x.k===k; }); return {k:a.k, t:a.t, swc:'palsw', sws:'background: linear-gradient(150deg, '+a.a+' 0%, '+a.b+' 100%)'}; })); })().map(function(a){ var on=st.accent===a.k; return Object.assign(a, {on:on, cls:'glass palb tap'+(on?' on':''), pick:function(){ self.setState({accent:a.k, mode:'look'}); saveJ('tc-liquid-accent', a.k); saveJ('tc-liquid-mode', 'look'); }}); }),
      lookMode: st.mode==='look', customMode: st.mode==='custom',
      icColourful: st.iconMode==='colour'?'on':'', icMatch: st.iconMode==='match'?'on':'',
      setIcColour:function(){ self.setState({iconMode:'colour'}); saveJ('tc-liquid-icons', 'colour'); }, setIcMatch:function(){ self.setState({iconMode:'match'}); saveJ('tc-liquid-icons', 'match'); },
      looks: LOOKS.map(function(l){ var on=st.mode==='look' && st.preset===l.k; return {t:l.t, s:l.s, on:on, thumb:'lthumb ps-'+l.k+(st.accent!=='look' && okAccent(l.k, st.accent)?' ac-'+st.accent:''), cls:'glass lookbtn tap'+(on?' on':''), pick:function(){ var a=okAccent(l.k, self.state.accent)?self.state.accent:'look'; self.setState({preset:l.k, accent:a, mode:'look'}); saveJ('tc-liquid-preset', l.k); saveJ('tc-liquid-accent', a); saveJ('tc-liquid-mode', 'look'); }}; }),
      themes: THEMES.map(function(t){ var on=st.theme===t.k; return {t:t.t, a:t.a, n:t.n, on:on, cls:'glass theme tap'+(on?' on':''), pick:function(){ self.setState({theme:t.k}); saveJ('tc-liquid-look', {theme:t.k, wall:self.state.wall}); }}; }),
      walls: WALLS.map(function(w){ var on=st.wall===w.k; return {t:w.t, on:on, thumb:'wthumb wp-'+w.k, cls:'glass wbtn tap'+(on?' on':''), pick:function(){ self.setState({wall:w.k}); saveJ('tc-liquid-look', {theme:self.state.theme, wall:w.k}); }}; }) };

    // billing
    var PL = [ {k:'starter', t:'Starter', s:'1 company · 1 user', y:1499, m:149, ic:'box', c:C.party, feats:['1 Tally company','1 user','Vouchers and reports']},
               {k:'pro', t:'Professional', s:'Up to 3 companies · 5 users', y:3999, m:399, ic:'star', c:C.reports, feats:['Up to 3 Tally companies','Up to 5 users','Sales Team and invites','Payment reminders']},
               {k:'ent', t:'Enterprise', s:'For bigger teams', ic:'building', c:C.acc, feats:['Many companies','Many users','Everything in Professional'], current:true} ];
    var bl = { yCls:st.yearly?'on':'', mCls:st.yearly?'':'on', setY:function(){ self.setState({yearly:true}); }, setM:function(){ self.setState({yearly:false}); },
      plans: PL.map(function(p){ return {t:p.t, s:p.s, d:IC[p.ic], c:p.c, feats:p.feats, current:!!p.current, notCurrent:!p.current,
        price: p.current ? 'Custom' : inr(st.yearly?p.y:p.m), per: p.current ? '· talk to us' : (st.yearly?'/ year':'/ month'), pick:say('We will call you to switch to '+p.t)}; }) };

    var rf = { copy:say('Code copied'), share:say('Share sheet opened') };
    var faqs = FAQS.map(function(x,i){ var open=st.faq===i; return {q:x.q, a:x.a, open:open, color: open?'var(--acc)':'var(--ink)', chev: open?IC.chevU:IC.chevD, toggle:function(){ self.setState({faq: self.state.faq===i ? -1 : i}); }}; });

    var cmL = st.cmenu ? (st.cmenu.list||'home') : null, cmR = st.cmenu ? reg[cmL+'|'+st.cmenu.id] : null;
    var cmPinned = !!st.cmenu && (cmL==='home' ? st.pinned.indexOf(st.cmenu.id)>=0 : ((st.listPrefs[cmL]||{}).pinned||[]).indexOf(st.cmenu.id)>=0);
    var cm = { on:!!cmR, x: st.cmenu?st.cmenu.x:0, y: st.cmenu?st.cmenu.y:0, label: cmR?cmR.label:'', d: cmR?cmR.d:'', c: cmR?cmR.c:'',
      close:function(){ self._lpFired=false; self.setState({cmenu:null}); },
      items: !cmR ? [] : [
        {t: cmPinned?'Unpin':'Pin', d:IC.pin, go:function(){ self._lpFired=false; self.cmPin(); }},
        {t:'Open', d:IC.open, go:function(){ self._lpFired=false; self.setState({cmenu:null}); cmR.open(); }},
        {t:'Drag', d:IC.move, go:function(){ self._lpFired=false; var c=self.state.cmenu; self.setState({armed:{list:c.list||'home', id:c.id}, cmenu:null}); }},
        {t:'Hide', d:IC.eyeOff, go:function(){ self._lpFired=false; self.cmHide(); }}
      ] };
    var ldr = st.ldrag, lR = ldr ? reg[ldr.list+'|'+ldr.id] : null;
    var lgh = { on:!!(ldr && lR), x: ldr?ldr.x:0, y: ldr?ldr.y:0, label: lR?lR.label:'', d: lR?lR.d:'', c: lR?lR.c:'' };
    var barPos=function(ev){ var el=ev.currentTarget; if(!el || !el.getBoundingClientRect) return -1; var r=el.getBoundingClientRect(); var sc=(r.width/362)||1; var bx=(ev.clientX-r.left)/sc; return Math.max(0, Math.min(4, Math.floor((bx-6)/70))); };
    var hb = { cls:'hbub'+(st.hovOn?' on':'')+(st.dwell?' dwell':''), x: 6+st.hovPos*70+10,
      move:function(ev){ if(ev.pointerType==='touch' && !self.state.hovOn) return; var q=barPos(ev); if(q<0) return;
        if(q!==self.state.hovPos || !self.state.hovOn){ self.setState({hovPos:q, hovOn:true, dwell:false}); self.armDwell(ev, q); } },
      leave:function(){ clearTimeout(self._dw); if(self.state.hovOn) self.setState({hovOn:false, dwell:false}); },
      down:function(ev){ var q=barPos(ev); if(q<0) return; clearTimeout(self._hb); clearTimeout(self._dw); self._hbStart=q; self._hbTouch = ev.pointerType!=='mouse'; self.setState({hovPos:q, hovOn:true, dwell:false}); },
      up:function(ev){ clearTimeout(self._dw); var q=barPos(ev);
        if(self._hbTouch && q>=0 && q!==self._hbStart && !self.state.tdrag){ var ti=self.state.tabOrder[q]; if(ti!==self.state.tab){ self._tabLp=true; self.selectTab(ti); } }
        self._hbTouch=false;
        if(ev.pointerType!=='mouse'){ clearTimeout(self._hb); self._hb=setTimeout(function(){ self.setState({hovOn:false, dwell:false}); }, 320); } } };
    tabs.forEach(function(t, i){ var pos=st.tabOrder.indexOf(i); if(st.hovOn && pos===st.hovPos) t.cls += ' hov'; });
    var hpList = this.hidList().filter(function(h){ return h.page===st.hidPage; });
    var hp = { title: st.hidPage===0 ? 'Hidden on Page 1' : 'Hidden on Page '+(st.hidPage+1),
      rows: hpList.map(function(h){ var w=W(h.id) || {label:h.id, d:IC.grid, c:C.navy}; return {label:w.label, d:w.d, c:w.c, restore:function(){ self.restoreHidden([h.id]); }}; }),
      all:function(){ self.restoreHidden(hpList.map(function(h){ return h.id; })); }, many: hpList.length>1 };
    var cpHex = st.cpExact || hsv2hex(st.cpH, st.cpS, st.cpV);
    var cp = { h:st.cpH, hex:cpHex, sx:st.cpS, vy:100-st.cpV, hexIn: st.cpHexTyping!==null ? st.cpHexTyping : cpHex.slice(1),
      padBg:'linear-gradient(to top, #000 0%, rgba(0,0,0,0) 100%), linear-gradient(to right, #fff 0%, hsl('+st.cpH+', 100%, 50%) 100%)',
      padDown:function(e){ var el=e.currentTarget; if(!el) return; var set=function(ev){ var r=el.getBoundingClientRect(); self.setState({cpS:Math.round(clampN((ev.clientX-r.left)/r.width,0,1)*100), cpV:Math.round((1-clampN((ev.clientY-r.top)/r.height,0,1))*100), cpHexTyping:null, cpExact:null}); };
        set(e); var mv=function(ev){ if(ev.cancelable) ev.preventDefault(); set(ev); }; var up=function(){ window.removeEventListener('pointermove', mv); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', up); };
        window.addEventListener('pointermove', mv, {passive:false}); window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up); },
      onHue:function(e){ self.setState({cpH:Number(e.target.value)||0, cpHexTyping:null, cpExact:null}); },
      onHex:function(e){ var v=String(e.target.value).replace(/[^0-9a-fA-F]/g,'').slice(0,6); if(v.length===6){ var q=hex2hsv('#'+v); self.setState({cpH:q[0], cpS:q[1], cpV:q[2], cpHexTyping:null, cpExact:('#'+v).toUpperCase()}); } else self.setState({cpHexTyping:v}); },
      onNative:function(e){ var q=hex2hsv(e.target.value); self.setState({cpH:q[0], cpS:q[1], cpV:q[2], cpHexTyping:null, cpExact:String(e.target.value).toUpperCase()}); },
      quick: ['#8C1D3F','#C0392B','#D35400','#B7791F','#6B8E23','#2E7D32','#0E7159','#0F766E','#0B6A8F','#1D4ED8','#4338CA','#6D3FC4','#A0306A','#6B4A3A','#3E4C63','#5F6B7A'].map(function(h){ return {hex:h, cls:'qsw tap'+(h===cpHex?' on':''), pick:function(){ var q=hex2hsv(h); self.setState({cpH:q[0], cpS:q[1], cpV:q[2], cpHexTyping:null, cpExact:h}); }}; }),
      combos: COMBOS.map(function(c, i){ var v=makeTheme(cpHex, i); var on = st.mode==='custom' && st.custom.base===cpHex && st.custom.combo===i;
        return {t:c.t, s:c.s, on:on, cls:'glass lookbtn tap'+(on?' on':''),
          wallSt:'background: '+v['--wall'], cardSt:'background: rgba('+v['--gt']+', .55)', dotSt:'background: linear-gradient(160deg, '+v['--acc2']+', '+v['--acc3']+')', txtSt:'color: '+v['--ink'], btnSt:'background: '+v['--navy'],
          pick:function(){ var cu={base:cpHex, combo:i}; self.setState({mode:'custom', custom:cu}); saveJ('tc-liquid-custom', cu); saveJ('tc-liquid-mode', 'custom'); self.say(c.t+' look applied'); }}; }) };
    var themeWallSt = st.mode==='custom' ? 'background: '+makeTheme(st.custom.base, st.custom.combo)['--wall'] : '';
    var themeWallCls = st.mode==='custom' ? '' : ' ps-'+st.preset;
    var photoSt = function(u){ return 'background: linear-gradient(rgba(255,255,255,.3), rgba(255,255,255,.2)), url("'+u+'") center / cover no-repeat'; };
    var WITEMS = [{k:'theme', t:'Match theme'}].concat(WALLS).concat(st.photo ? [{k:'photo', t:'My photo'}] : []);
    var pend = st.pendWall;
    var wp = {
      items: WITEMS.map(function(w){ var on=st.wallK===w.k && !pend, sel=pend===w.k;
        return {t:w.t, on:on, cls:'glass wbtn tap'+((sel||on)?' on':''), thumbCls: w.k==='theme' ? 'wthumb'+themeWallCls : (w.k==='photo' ? 'wthumb' : 'wthumb wp-'+w.k), thumbSt: w.k==='theme' ? themeWallSt : (w.k==='photo' ? photoSt(st.photo.url) : ''),
          pick:function(){ if(w.k===self.state.wallK){ self.setState({pendWall:null}); return; } self.setState({pendWall:w.k, pendPhoto: w.k==='photo' ? self.state.photo : null}); }}; }),
      hasPend: !!pend,
      pendName: pend==='photo' ? 'Your photo' : pend==='theme' ? 'Match theme' : ((WALLS.find(function(x){ return x.k===pend; })||{}).t || ''),
      prevCls: 'wprev' + (pend && pend!=='photo' && pend!=='theme' ? ' wp-'+pend : (pend==='theme' ? themeWallCls : '')),
      prevSt: pend==='photo' && st.pendPhoto ? photoSt(st.pendPhoto.url) : (pend==='theme' ? themeWallSt : ''),
      cancel:function(){ self.setState({pendWall:null, pendPhoto:null}); },
      apply:function(){ var k=self.state.pendWall; if(!k) return; var patch={wallK:k, pendWall:null, pendPhoto:null};
        if(k==='photo' && self.state.pendPhoto){ patch.photo=self.state.pendPhoto; saveJ('tc-liquid-photo', self.state.pendPhoto); }
        self.setState(patch); saveJ('tc-liquid-wall', k); self.say('Wallpaper applied'); },
      onFile:function(e){ var f=e.target && e.target.files && e.target.files[0]; if(!f) return; if(!/^image\//.test(f.type||'')){ self.say('Please pick a photo'); return; }
        var rd=new FileReader(); rd.onload=function(){ var img=new Image(); img.onload=function(){ try {
          var max=1100, sc=Math.min(1, max/Math.max(img.width, img.height)), cv=document.createElement('canvas'); cv.width=Math.round(img.width*sc); cv.height=Math.round(img.height*sc);
          cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height); var url=cv.toDataURL('image/jpeg', .8);
          var t=document.createElement('canvas'); t.width=t.height=16; var tx=t.getContext('2d'); tx.drawImage(img, 0, 0, 16, 16); var d=tx.getImageData(0,0,16,16).data, sum=0; for(var i=0;i<d.length;i+=4) sum+=lumOf([d[i],d[i+1],d[i+2]]);
          self.setState({pendWall:'photo', pendPhoto:{url:url, lum:sum/(d.length/4)}}); } catch(err){ self.say('Could not read that photo'); } }; img.src=rd.result; }; rd.readAsDataURL(f); try { e.target.value=''; } catch(err){} }
    };
    var gl = Math.round(st.glass/10)*10;
    return {
      ic:IC, is:is, ov:ov, rootCls:'root g'+gl+' ps-'+st.preset+(st.accent!=='look'?' ac-'+st.accent:'')+' icmatch'+(st.wallK==='photo' && st.photo ? ' photo'+(st.photo.lum<.35?' photo-dark':'') : '')+(st.cmenu?' menuOnAll':''), cm:cm, lgh:lgh, hb:hb, hl:hl, hp:hp, cp:cp, wp:wp, scrCls:scrCls, flowCls:flowCls, backLabel:backLabel, showTabs:showTabs, tabs:tabs,
      pillL:st.pillL, pillW:st.pillW, pillT:st.pillT, pillS:st.pillS,
      homeCls:'homeScr'+dirCls+(st.drag?' dragging':'')+(st.cmenu?' menuOn':''), pages:pages, dots:dots, drag:drag, editing:st.editing, notEditing:!st.editing,
      startEdit:function(){ self._root = null; self.enterEdit(); }, cancelEdit:function(){ self.cancelEdit(); }, doneEdit:function(){ self.doneEdit(); },
      onPagerScroll:function(e){ var el=e.currentTarget; if(!el || !el.clientWidth) return; if(el.closest) self._root = el.closest('.root'); var i=Math.round(el.scrollLeft/el.clientWidth); if(i!==self.state.page){ self.setState({page:i}); saveJ('tc-liquid-page-v2', i); } }, toast:st.toast, hasToast:!!st.toast,
      back:function(){ self.back(); }, closeOv:closeOv, nav:nav, menu:menu, fv:form, fc:fc,
      passType: st.showPass?'text':'password', passIcon: st.showPass?IC.eyeOff:IC.eye, togglePass:function(){ self.setState({showPass:!self.state.showPass}); },
      doLogin:function(){ self.setState({loggedIn:true, tab:0, pillL:6+self.posOf(0)*70, pillW:70, pillT:'none', screen:'home', history:[], dir:'fwd'}); self.say('Welcome back, workk72002'); },
      forgotSent:st.forgotSent, notSent:!st.forgotSent, sendReset:function(){ self.setState({forgotSent:true}); },
      companyName:company.name.split(' - ')[0], companies:companies, refreshTally:say('Company list refreshed from Tally'),
      openMenu:function(){ self.setState({overlay:'menu'}); }, openSearch:function(){ self.setState({overlay:'search'}); }, openCompany:function(){ self.setState({overlay:'company'}); },
      refreshNow:say('Up to date · synced just now'),
      hasUnread:unread>0, unreadTxt: unread ? unread+' unread' : 'All read', markAll:function(){ self.setState(function(p){ return {notifs:p.notifs.map(function(n){ return Object.assign({}, n, {unread:false}); })}; }); self.say('All marked as read'); },
      nseg:{ all:st.nFilter==='all'?'on':'', unread:st.nFilter==='unread'?'on':'', setAll:function(){ self.setState({nFilter:'all'}); }, setUnread:function(){ self.setState({nFilter:'unread'}); } },
      notifs:notifs, noNotifs:!notifs.length,
      quick:quick, customize:st.customize,
      startCustomize:function(){ self.setState({customize:true, hiddenDraft:self.state.hidden.slice()}); },
      cancelCustomize:function(){ self.setState({customize:false}); },
      saveCustomize:function(){ self.setState({customize:false, hidden:self.state.hiddenDraft.slice()}); self.say('Shortcuts saved'); },
      wsName:ws.name, tiles:tiles, sums:sums,
      results:results, noResults:!results.length,
      cw:cw, wsm:wsm, start:start, entryTiles:entryTiles, fl:fl, pk:pk, npOff:npOff, saveParty:saveParty, npHint:npHint, pkr:pkr, ni:ni,
      vh:vh, vl:vl, ed:ed, oh:oh, ol:ol, bd:bd, pdf:pdf, it:it, pv:pv, pd:pd, rp:rp, rd:rd, av:av, ad:ad, tm:tm, mb:mb, sg:sg, bl:bl, rf:rf, faqs:faqs
    };
  }
}
