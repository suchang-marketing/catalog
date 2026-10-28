// 한글 카탈로그(index.html) → 영문 카탈로그(en/index.html) 변환기
// 원본은 절대 건드리지 않는다. 읽기만 하고 en/ 아래에 새로 쓴다.
// 한글판이 갱신되면 이 스크립트를 다시 돌리면 영문판이 따라온다.
//   실행:  node build-en.js
const fs = require('fs');
const path = require('path');

const outputRoot = process.env.CATALOG_OUTPUT_DIR || __dirname;
const SRC = path.join(outputRoot, 'index.html');
const OUT_DIR = path.join(outputRoot, 'en');
const OUT = path.join(OUT_DIR, 'index.html');

// ── 대조표 읽기 ─────────────────────────────────────────────
// 값 안에 쉼표가 있는 칸은 큰따옴표로 감싸져 있다(예: "전초(잎,줄기,뿌리)")
function parseCsv(file) {
  const text = fs.readFileSync(path.join(__dirname, file), 'utf8').replace(/^﻿/, '');
  return text.trim().split(/\r?\n/).slice(1).map(line => {
    const cells = []; let cur = '', q = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (c === '"') { if (q && line[i + 1] === '"') { cur += '"'; i++; } else q = !q; }
      else if (c === ',' && !q) { cells.push(cur); cur = ''; }
      else cur += c;
    }
    cells.push(cur);
    return cells;
  });
}

const NAMES = new Map();   // 원물 한글명 → {en, latin}
for (const [id, cat, ko, en, latin] of parseCsv('en-names.csv')) NAMES.set(ko, { en, latin, id });

const GOODS = new Map();   // 가공품 한글명 → 영문
for (const [ko, en] of parseCsv('en-goods.csv')) GOODS.set(ko, en);

const TERM = {};           // 구분별 용어 사전
for (const [group, ko, en] of parseCsv('en-terms.csv')) {
  (TERM[group] ||= new Map()).set(ko, en);
}

const missing = new Set();

// ── 마스터 시트 보충 ─────────────────────────────────────────
// 손으로 만든 대조표(en-names.csv·en-goods.csv)에 없는 새 이름은 원물마스터_최종의 「영문명」·「학명」 열로 채운다.
// 대조표가 항상 우선. 시트를 못 받으면 보충 없이 진행(없는 이름은 아래 「확인 필요」로 남음).
// 10-28: 수입 원료(P-I)도 보충한다 — 시트에서 이름을 바꿔도 「영문명」 칸만 채우면 되게(코드를 못 만지는 담당자용).
const SHEET_ID = '1Tqu5GIITbBdmt40LD7OMf3W7fFYJhfKJolebv6IEOns', SHEET_GID = '9001';
function parseCsvText(text) {
  const rows = []; let row = [], cur = '', q = false;
  text = text.replace(/^﻿/, '');
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cur); cur = ''; }
    else if (c === '\n') { row.push(cur.replace(/\r$/, '')); rows.push(row); row = []; cur = ''; }
    else cur += c;
  }
  if (cur || row.length) { row.push(cur.replace(/\r$/, '')); rows.push(row); }
  return rows;
}
const M_ORG = new Map(), M_PROD = new Map();   // 원물명 / 품목명 → {en, latin, part, org}
try {
  const csv = process.env.CATALOG_ITEM_CSV
    ? fs.readFileSync(process.env.CATALOG_ITEM_CSV, 'utf8')
    : require('child_process').execFileSync('curl', ['-fsSL', '--max-time', '60',
      `https://docs.google.com/spreadsheets/d/${SHEET_ID}/export?format=csv&gid=${SHEET_GID}`], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const [hd, ...body] = parseCsvText(csv);
  const ix = n => hd.indexOf(n);
  if (['PID', '품목명', '원물명', '영문명', '학명', '사용부위'].some(n => ix(n) < 0)) throw new Error('시트 열 이름이 바뀜');
  for (const r of body) {
    if (!/^P-[MI]\d/.test(r[ix('PID')] || '')) continue;
    const v = { en: (r[ix('영문명')] || '').trim(), latin: (r[ix('학명')] || '').trim(), part: (r[ix('사용부위')] || '').trim(), org: (r[ix('원물명')] || '').trim() };
    if (!v.en) continue;
    if (!M_ORG.has(v.org)) M_ORG.set(v.org, v);
    const pn = (r[ix('품목명')] || '').trim(); if (pn && !M_PROD.has(pn)) M_PROD.set(pn, v);
  }
} catch (e) { console.log('※ 마스터 시트 보충 못 함: ' + e.message); }
const autoFilled = new Set();   // 시트 값으로 자동 채운 이름(사람이 한 번 훑어볼 목록)
// 용어(가공형태·부위 등)는 시트에 영문 칸이 없어 담당자가 고칠 수 없다 → 영문판을 보류하지 않고 한글 그대로 두고 경고만 남긴다.
const termKept = new Set();
function look(map, ko, where) {
  if (ko == null || ko === '') return ko;
  const hit = map.get(ko);
  if (hit === undefined) { termKept.add(`${where}: ${ko}`); return ko; }
  return hit;
}
const T = (group, ko) => look(TERM[group], ko, group);
// 품목명은 가공품 사전 → 원물 사전 순으로 찾는다
function goodName(ko) {
  if (GOODS.has(ko)) return GOODS.get(ko);
  if (NAMES.has(ko)) return NAMES.get(ko).en;
  const m = M_PROD.get(ko);
  if (m) {
    // 품목명이 원물명 + 부위 꼬리(예: 마르멜로껍질)면 영문명 뒤에 부위를 붙인다
    const part = (m.org && ko !== m.org && ko.startsWith(m.org) && TERM['부위'].get(m.part)) || '';
    const en = part ? `${m.en}, ${part}` : m.en;
    autoFilled.add(`품목명 ${ko} → ${en}`);
    return en;
  }
  missing.add(`품목명: ${ko}`);
  return ko;
}
// 「건조, 원물, 분말」처럼 쉼표로 묶인 가공형태는 하나씩 옮긴다
function procForm(ko) {
  const whole = TERM['가공형태'].get(ko);
  if (whole !== undefined) return whole;
  return ko.split(',').map(t => T('가공형태', t.trim())).join(', ');
}

// ── 부위(parts) 쉼표 분리 버그 고치기 ────────────────────────
// 원본 데이터에서 "전초(잎,줄기,뿌리)" 가 쉼표에서 잘려 세 조각으로 저장돼 있다.
// 괄호가 닫히지 않은 조각은 닫힐 때까지 뒤 조각과 다시 붙인다.
function fixParts(arr) {
  const out = [];
  let buf = null;
  for (const p of arr) {
    const piece = buf === null ? p : buf + ',' + p;
    const open = (piece.match(/\(/g) || []).length;
    const close = (piece.match(/\)/g) || []).length;
    if (open > close) buf = piece;
    else { out.push(piece); buf = null; }
  }
  if (buf !== null) out.push(buf);
  return out;
}

// ── 원본 읽기 ───────────────────────────────────────────────
const raw = fs.readFileSync(SRC, 'utf8');
const bom = raw.startsWith('﻿');
const lines = (bom ? raw.slice(1) : raw).split('\n');

const iItems = lines.findIndex(l => l.startsWith('const ITEMS = '));
const iMeta = lines.findIndex(l => l.startsWith('const META  = '));
const iCats = lines.findIndex(l => l.startsWith('const CATS  = '));
const iProcs = lines.findIndex(l => l.startsWith('const PROCS = '));
if (iItems < 0 || iMeta < 0 || iCats < 0 || iProcs < 0) throw new Error('원본에서 데이터 줄을 못 찾음');

const ITEMS = JSON.parse(lines[iItems].replace(/^const ITEMS = /, '').replace(/;\s*$/, ''));
const META = JSON.parse(lines[iMeta].replace(/^const META  = /, '').replace(/;\s*$/, ''));

// ── 데이터 영문화 ───────────────────────────────────────────
const CATKEY = { '농산물': 'agri', '해조류': 'sea', '약재': 'herb', '수입 원료': 'imp' };

const enItems = ITEMS.map(it => {
  let nm = NAMES.get(it.name);
  if (!nm && M_ORG.has(it.name)) { const m = M_ORG.get(it.name); nm = { en: m.en, latin: m.latin }; autoFilled.add(`원물명 ${it.name} → ${m.en} (${m.latin})`); }
  if (!nm) missing.add(`원물명: ${it.name}`);
  return {
    id: it.id,
    cat: T('카테고리', it.cat),
    catK: CATKEY[it.cat],
    name: nm ? nm.en : it.name,
    sci: nm ? nm.latin : '',
    ko: it.name,                                  // 한글명도 남긴다 — 바이어가 한글 자료와 대조할 때 쓴다
    hs: it.hs,
    hsChk: it.hsChk.map(goodName),
    proc: it.proc.map(p => T('가공', p)),
    parts: fixParts(it.parts).map(p => T('부위', p)),
    cert: it.cert.map(c => T('인증', c)),
    grades: it.grades.map(g => T('등급', g)),
    mixed: it.mixed,
    method: it.method.map(m => T('방식', m)),
    upc: it.upc,
    upcN: it.upcN.map(goodName),
    varyPart: it.varyPart,
    img: it.img,
    goods: (it.goods || []).map(g => ({
      n: goodName(g.n),
      f: g.f ? procForm(g.f) : g.f,
      p: g.p ? T('부위', g.p) : g.p,
      g: T('등급', g.g),
      u: g.u,
      h: g.h,
    })),
  };
});


// ── 정렬: 카테고리(농산물→해조류→약재) 안에서 영문명 A~Z ──
// 한글판은 카테고리 안에서 가나다순이라, 영문판은 같은 자리에서 알파벳순이어야 바이어가 찾기 쉽다.
const CAT_ORDER = { agri: 0, sea: 1, herb: 2, imp: 3 };
enItems.sort((a, b) => {
  const d = (CAT_ORDER[a.catK] ?? 99) - (CAT_ORDER[b.catK] ?? 99);
  if (d !== 0) return d;
  const n = a.name.localeCompare(b.name, 'en', { sensitivity: 'base' });
  if (n !== 0) return n;
  return a.id.localeCompare(b.id);      // 영문명이 같으면 ID로 순서를 고정
});

const enMeta = {
  total: META.total,
  goods: META.goods,
  rows: META.rows,
  byCat: { agri: META.byCat['농산물'], sea: META.byCat['해조류'], herb: META.byCat['약재'], imp: META.byCat['수입 원료'] },
  updated: META.updated,
  photos: META.photos,
};

// ── 뼈대(디자인·화면문구) 영문화 ────────────────────────────
// 원본에서 데이터 네 줄을 뺀 나머지를 문자열 치환한다.
let head = lines.slice(0, iItems).join('\n');
let tail = lines.slice(iProcs + 1).join('\n');

// 한글이 박힌 CSS 클래스·id 이름 (화면에는 안 보이지만 영문 데이터와 짝이 맞아야 한다)
for (const [ko, key] of Object.entries(CATKEY)) {
  const re = new RegExp('-' + ko, 'g');
  head = head.replace(re, '-' + key);
  tail = tail.replace(re, '-' + key);
}
// 한글판의 「수입 원료」는 id·색 클래스에 짧게 「-수입」으로 쓰임
head = head.replace(/-수입(?!국)/g, '-imp');
tail = tail.replace(/-수입(?!국)/g, '-imp');

const REPL_HEAD = [
  ['<html lang="ko">', '<html lang="en">'],
  [`<title>제주수창 취급품목 — 원물 ${META.total}종</title>`,
    `<title>Jeju Suchang Raw Materials — ${META.total} Items</title>`],
  [`content="청정 제주 원물 ${META.total}종 · B2B 대량 공급. 농산물 ${META.byCat['농산물']}종 · 해조류 ${META.byCat['해조류']}종 · 약재 ${META.byCat['약재']}종 · 수입 원료 ${META.byCat['수입 원료']}종"`,
    `content="${META.total} raw materials from pristine Jeju · B2B bulk supply. ${META.byCat['농산물']} agricultural · ${META.byCat['해조류']} marine algae · ${META.byCat['약재']} medicinal herbs · ${META.byCat['수입 원료']} imported ingredients."`],
  [`content="제주수창 취급품목 — 원물 ${META.total}종"`, `content="Jeju Suchang Raw Materials — ${META.total} Items"`],
  ['content="(주)수창 JEJU SUCHANG"', 'content="JEJU SUCHANG CO., LTD."'],
  ['content="https://suchang-marketing.github.io/catalog/"', 'content="https://suchang-marketing.github.io/catalog/en/"'],
  ['content="ko_KR"', 'content="en_US"'],
  // 학명을 이탤릭으로 보여줄 자리와 언어 전환 단추
  ['<style>body{margin:0}</style>', `<style>body{margin:0}</style>`],
  ['alt="(주)수창 로고"', 'alt="Jeju Suchang logo"'],
  ['<h1>취급품목</h1>', '<h1>Raw Materials</h1>'],
  ['<p class="tagline">청정 제주, 그 자체를 원료로</p>',
    '<p class="tagline">Pristine Jeju, in its raw form</p>'],
  ['<span class="unit">종</span>', '<span class="unit">items</span>'],
  ['<span class="dot d-agri"></span> 농산물 ', '<span class="dot d-agri"></span> Agricultural '],
  ['<span class="dot d-sea"></span> 해조류 ', '<span class="dot d-sea"></span> Marine Algae '],
  ['<span class="dot d-herb"></span> 약재 ', '<span class="dot d-herb"></span> Medicinal Herbs '],
  ['<span class="dot d-imp"></span> 수입 원료 ', '<span class="dot d-imp"></span> Imported Ingredients '],
  ['placeholder="원물명 또는 품목으로 찾기 (예: 감태, 진피, 분말)"',
    'placeholder="Search by material, product, HS code or scientific name (e.g. Ecklonia, peel, powder)"'],
  ['>초기화<', '>Reset<'],
  ['title="지금 화면에 보이는 목록을 엑셀로 내려받음"', 'title="Download the items currently listed as a spreadsheet"'],
  ['<span class="t">엑셀</span>', '<span class="t">Excel</span>'],
  ['title="카탈로그 전체를 PDF로 내려받음"', 'title="Full catalog PDF (Korean edition)"'],
  ['<span class="t">PDF</span>', '<span class="t">PDF (KR)</span>'],
  ['<span class="flabel">분류</span>', '<span class="flabel">Category</span>'],
  ['<span class="flabel">가공</span>', '<span class="flabel">Processing</span>'],
  ['<span class="flabel">생산방식</span>', '<span class="flabel">Production Method</span>'],
  // 꼬리말
  ['<span>· 취급 품목은 해당 원물의 가공형태별 상품임. 전체 <b id="n-goods">—</b>개.</span>',
    '<span>· Products are listed per raw material by processing type — <b id="n-goods">—</b> in total.</span>'],
  ['<span>· 원물 사진 <b id="n-photos">—</b>종 수록함. 나머지는 준비 중임.</span>',
    '<span>· Photos included for <b id="n-photos">—</b> materials; the remainder are in preparation.</span>'],
  ['<span>· <b>생산방식은 일반이 기본이고, 일부 원물에 친환경·유기농(인증품)이 더 있음.</b> "일반 · 친환경"처럼 적힌 원물은 두 가지를 함께 취급함 — 항목을 열면 어느 품목이 인증품인지 보임.</span>',
    '<span>· <b>Conventional is the default; some materials are also available as Eco-friendly or Organic certified products.</b> A material marked "Conventional · Eco-friendly Certified" is supplied in both — open the item to see which products are certified.</span>'],
  ['<span>· <b>자연산·양식은 채취·양식 구분이며 인증이 아님.</b></span>',
    '<span>· <b>Wild-harvested and Farmed describe how the material is sourced; they are not certifications.</b></span>'],
  ['<span>· <b>업사이클(ESG)</b>은 버려지던 부위·부산물을 원료로 쓰는 품목임. 위 ESG 단추로 모아 볼 수 있음.</span>',
    '<span>· <b>Upcycled (ESG)</b> products are made from parts and by-products that were previously discarded. Use the ESG button above to list them.</span>'],
  ['<span>· <b>HS코드는 6단위 참고용임.</b> 미국 HTS·관세청 두 공식자료와 대조한 값이며, 최종 세번은 수입국 세관이 정함. "확인 중"인 품목은 대조가 끝나지 않아 적지 않음.</span>',
    '<span>· <b>HS codes are 6-digit references.</b> They were cross-checked against the US HTS and the Korea Customs Service tariff schedule; the final classification is determined by the customs authority of the importing country. Items marked "Pending" are still being verified.</span>'],
  ['<span>· <b>엑셀</b> 단추는 지금 화면에 보이는 목록만 내려받음(검색·조건을 걸면 그만큼만 받아짐).</span>',
    '<span>· <b>Excel</b> downloads only the items currently listed — search and filters apply. Scientific names are included in the file.</span>'],
  ['<span>· 규격·포장단위는 요청 시 별도 안내함.</span>',
    '<span>· <b>Scientific names are given for identification.</b> Where the species has not yet been confirmed, the genus is shown with "sp.". Specifications and packaging units are provided on request.</span>'],
  ['<span>· 단가는 수량·납기에 따라 협의함.</span>',
    '<span>· Pricing is quoted per order, based on quantity and delivery schedule.</span>'],
  ['<span class="co">(주)수창 JEJU SUCHANG</span>', '<span class="co">JEJU SUCHANG CO., LTD.</span>'],
  ['<span>TEL 064-713-6696</span>', '<span>TEL +82-64-713-6696</span>'],
];

const REPL_TAIL = [
  // 분류 이름이 영문으로 바뀌었으므로 화면 요소 id는 짧은 열쇠(agri/sea/herb)로 찾는다
  ["CATS.forEach(c => document.getElementById('c-'+ck(c)).textContent = META.byCat[c]);",
    "CATS.forEach(c => document.getElementById('c-'+CATKEY[c]).textContent = META.byCat[CATKEY[c]]);"],
  ["META.updated + ' 기준'", "'As of ' + META.updated"],
  ["chipRow($('#f-upc'), ['업사이클(ESG)'], 'upc');", "chipRow($('#f-upc'), ['Upcycled (ESG)'], 'upc');"],
  // 검색 대상에 학명과 한글명을 넣는다 — 바이어는 학명으로, 국내 담당자는 한글로 찾는다
  ["const hay = (it.name+' '+it.id+' '", "const hay = (it.name+' '+it.sci+' '+it.ko+' '+it.id+' '"],
  ["+(it.upc?' 업사이클 esg':'')", "+(it.upc?' upcycled esg':'')"],
  ['`<b>${hits.length}종</b> 찾음 <span style="color:var(--ink-faint)">/ 전체 ${META.total}종</span>`',
    '`<b>${hits.length}</b> found <span style="color:var(--ink-faint)">/ ${META.total} total</span>`'],
  ['`전체 <b>${META.total}종</b> · 상품 ${META.goods}개 · 항목을 누르면 상세가 열림`',
    '`<b>${META.total} materials</b> · ${META.goods} products · tap an item for details`'],
  ['<b>해당하는 원물이 없음</b>조건을 줄이거나 초기화해 보십시오.',
    '<b>No matching materials</b>Try fewer filters, or reset.'],
  ['<span class="dot d-${ck(cat)}"></span><span class="catname">${cat}</span>',
    '<span class="dot d-${CATKEY[cat]}"></span><span class="catname">${cat}</span>'],
  ['<span class="catcount">${rows.length}종</span>', '<span class="catcount">${rows.length}</span>'],
  ['`<span class="more"> 외 ${it.hs.length-1}</span>`', '`<span class="more"> +${it.hs.length-1}</span>`'],
  ['`<span class="hs pend">확인 중</span>`', '`<span class="hs pend">Pending</span>`'],
  ['<button class="row cat-${cat}"', '<button class="row cat-${CATKEY[cat]}"'],
  // 원물명 아래에 학명을 이탤릭으로 붙인다
  ['<span class="nm">${esc(it.name)}</span>',
    '<span class="nm">${esc(it.name)}</span>${it.sci?`<span class="sci">${esc(it.sci)}</span>`:\'\'}'],
  ['`<span class="tag upc">업사이클</span>`', '`<span class="tag upc">Upcycled</span>`'],
  ["it.grades.map(g=>g==='일반'", "it.grades.map(g=>g==='Conventional'"],
  ['`<span class="tag plain">일반</span>`', '`<span class="tag plain">Conventional</span>`'],
  ['alt="${esc(it.name)} 사진"', 'alt="${esc(it.name)}"'],
  ['<span class="dk">취급 품목</span>', '<span class="dk">Products</span>'],
  ["const cert = g.g!=='일반';", "const cert = g.g!=='Conventional';"],
  ["` <s>일반</s>`", "` <s>Conventional</s>`"],
  ["` <em>업사이클</em>`", "` <em>Upcycled</em>`"],
  ['` <q class="pend">HS 확인 중</q>`', '` <q class="pend">HS pending</q>`'],
  ['<span class="dk">사용 부위</span>', '<span class="dk">Plant Part</span>'],
  ["' <span style=\"color:var(--ink-faint);font-size:.8rem\">— 품목마다 다름(위 표시 참조)</span>'",
    "' <span style=\"color:var(--ink-faint);font-size:.8rem\">— varies by product (marked above)</span>'"],
  ['<span class="dk">HS코드</span>', '<span class="dk">HS Code</span>'],
  ['` <span style="color:var(--ink-faint);font-size:.8rem">— ${esc(it.hsChk.join(\', \'))}은(는) 세번 확인 중임</span>`',
    '` <span style="color:var(--ink-faint);font-size:.8rem">— HS code pending for ${esc(it.hsChk.join(\', \'))}</span>`'],
  ['<span class="dk">가공 형태</span>', '<span class="dk">Processing</span>'],
  ['<span class="dk">생산방식</span>', '<span class="dk">Production Method</span>'],
  ['`<span class="dk">업사이클</span>', '`<span class="dk">Upcycled</span>'],
  ['<span style="color:var(--ink-faint);font-size:.8rem">— 버려지던 부위·부산물을 원료로 쓰는 품목임</span>',
    '<span style="color:var(--ink-faint);font-size:.8rem">— made from parts and by-products that were previously discarded</span>'],
  ['<span class="dk">품목 코드</span>', '<span class="dk">Item Code</span>'],
  ['`<div class="photoslot">원물 사진은 준비 중임. 필요하시면 문의 시 함께 보내드림.</div>`',
    '`<div class="photoslot">Photo in preparation — available on request.</div>`'],
  // 엑셀 내려받기
  ["const head = ['코드','분류','원물명','HS코드','HS 확인 중','가공형태','취급 품목','사용부위','생산방식','업사이클'];",
    "const head = ['Code','Category','Material','Scientific Name','Korean Name','HS Code','HS Pending','Processing','Products','Plant Part','Production Method','Upcycled'];"],
  ["csvCell(it.id), csvCell(it.cat), csvCell(it.name),",
    "csvCell(it.id), csvCell(it.cat), csvCell(it.name), csvCell(it.sci), csvCell(it.ko),"],
  ["a.download = `제주수창_취급품목_${hits.length}종_${META.updated}.csv`;",
    "a.download = `JejuSuchang_RawMaterials_${hits.length}items_${META.updated}.csv`;"],
];

function applyAll(text, pairs, label) {
  for (const [from, to] of pairs) {
    if (!text.includes(from)) { missing.add(`${label} 치환 실패: ${from.slice(0, 60)}`); continue; }
    text = text.split(from).join(to);
  }
  return text;
}
head = applyAll(head, REPL_HEAD, 'HTML');
tail = applyAll(tail, REPL_TAIL, 'JS');

// 상세에 학명 줄을 새로 넣는다 (품목 코드 바로 위)
const SCI_ANCHOR = '<span class="dk">Item Code</span>';
tail = tail.replace(SCI_ANCHOR,
  '${it.sci?`<span class="dk">Scientific Name</span><span class="dv"><i>${esc(it.sci)}</i></span>`:\'\'}\n          ' +
  '<span class="dk">Korean Name</span><span class="dv">${esc(it.ko)}</span>\n          ' + SCI_ANCHOR);

// 학명 표시용 css를 CSS 끝에 덧붙인다 (영문판에만 필요)
const CSS_SCI = `
/* ── 영문판 추가분 ── */
.sci{display:block; font-style:italic; color:var(--ink-faint); font-size:.78rem; margin-top:.08rem; line-height:1.3}
</style>`;
head = head.replace(/<\/style>(?![\s\S]*<\/style>)/, CSS_SCI);

// 언어 전환 단추 스타일은 한글판에 이미 있으면 다시 넣지 않는다
const CSS_LANG = `
.langsw{display:inline-flex; border:1px solid var(--line); border-radius:var(--r); overflow:hidden; flex:none}
.langsw a{padding:.5rem .7rem; font-size:.85rem; text-decoration:none; color:var(--ink-soft); background:var(--panel)}
.langsw a[aria-current="true"]{background:var(--accent); color:#fff}
.langsw a:not([aria-current="true"]):hover{color:var(--ink)}
</style>`;
if (!head.includes('.langsw{')) head = head.replace(/<\/style>(?![\s\S]*<\/style>)/, CSS_LANG);

// KO / EN 전환 단추 — 한글판에 이미 있으면 영문판용으로 바꿔 끼우고, 없으면 새로 넣는다
// (그냥 넣기만 하면 단추가 두 벌 생긴다 — 실제로 겪은 사고)
const KO_SW = '<div class="langsw"><a href="./" aria-current="true" hreflang="ko">KO</a><a href="en/" hreflang="en">EN</a></div>';
const EN_SW = '<div class="langsw"><a href="../" hreflang="ko">KO</a><a href="./" aria-current="true" hreflang="en">EN</a></div>';
if (head.includes(KO_SW)) head = head.split(KO_SW).join(EN_SW);
else head = head.replace('<div class="dl">', EN_SW + '\n      <div class="dl">');

// PDF 링크는 한글판 폴더의 파일을 가리키게 한다(영문 PDF는 아직 없음)
head = head.replace('href="%EC%B7%A8%EA%B8%89%ED%92%88%EB%AA%A9_%EC%B9%B4%ED%83%88%EB%A1%9C%EA%B7%B8.pdf"',
  'href="../%EC%B7%A8%EA%B8%89%ED%92%88%EB%AA%A9_%EC%B9%B4%ED%83%88%EB%A1%9C%EA%B7%B8.pdf"');

// og:image = 영문 전용 썸네일(en/og.png). 카톡·SNS 미리보기가 한글로 뜨지 않게 한다.
// 그림은 make-og-en.py 로 만든다 (한글판 og.png의 로고·배경을 그대로 쓰고 글자만 영어)
head = head.replace(/https:\/\/suchang-marketing\.github\.io\/catalog\/og\.png/g,
  'https://suchang-marketing.github.io/catalog/en/og.png');

// ── 조립 ────────────────────────────────────────────────────
const out = [
  head,
  'const ITEMS = ' + JSON.stringify(enItems) + ';',
  'const META  = ' + JSON.stringify(enMeta) + ';',
  "const CATS  = ['Agricultural','Marine Algae','Medicinal Herbs','Imported Ingredients'];",
  "const CATKEY = {'Agricultural':'agri','Marine Algae':'sea','Medicinal Herbs':'herb','Imported Ingredients':'imp'};",
  'const PROCS = ' + JSON.stringify(['Raw', 'Prepared / Frozen', 'Dried', 'Liquid / Extract', 'Processed / Other']) + ';',
  tail,
].join('\n');

fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(OUT, '﻿' + out, 'utf8');

// ── 결과 보고 ───────────────────────────────────────────────
const report = [];
report.push(`영문판 생성: en/index.html  (${(Buffer.byteLength(out, 'utf8') / 1024 / 1024).toFixed(2)} MB)`);
report.push(`품목 ${enItems.length}종 / 상품 ${enItems.reduce((s, i) => s + i.goods.length, 0)}개`);
const noSci = enItems.filter(i => !i.sci).length;
report.push(`학명 없는 품목: ${noSci}`);
if (autoFilled.size) { report.push('', `ℹ 시트 영문명으로 자동 채움 ${autoFilled.size}건(한 번 훑어볼 것):`); [...autoFilled].forEach(m => report.push('  - ' + m)); }
if (termKept.size) {
  report.push('', `ℹ 용어표(en-terms.csv)에 없어 영문판에 한글 그대로 둔 값 ${termKept.size}건(영문판은 정상 갱신):`);
  [...termKept].forEach(m => report.push('  - ' + m));
  console.log(`::warning::영문 용어표에 없는 값 ${termKept.size}건은 영문판에 한글 그대로 표시함: ${[...termKept].join(', ')}`);
}
if (missing.size) {
  report.push('', `⚠ 확인 필요 ${missing.size}건 — 시트 「품목」 탭에서 해당 품목의 「영문명」·「학명」 칸을 채운 뒤 다시 실행:`);
  [...missing].forEach(m => report.push('  - ' + m));
} else {
  report.push(termKept.size ? '원물명·품목명 빠짐 없음' : '빠짐 없음 — 모든 한글값이 영문으로 바뀜');
}
fs.writeFileSync(path.join(outputRoot, 'build-report.txt'), report.join('\n'), 'utf8');
console.log(report.join('\n'));
