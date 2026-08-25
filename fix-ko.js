// 한글판(index.html) 손보기 — 두 가지만 한다.
//  ① 부위 "전초(잎,줄기,뿌리)"가 쉼표에서 잘려 세 조각으로 저장된 것을 한 덩어리로 되돌림
//  ② 오른쪽 위에 KO / EN 언어 전환 단추 추가
// 고치기 전 원본은 index.ko-backup.html 로 남긴다.
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, 'index.html');
const BAK = path.join(__dirname, 'index.ko-backup.html');

if (!fs.existsSync(BAK)) fs.copyFileSync(SRC, BAK);   // 백업은 한 번만 (재실행해도 원본이 안 덮인다)

const raw = fs.readFileSync(SRC, 'utf8');
const bom = raw.startsWith('﻿');
let text = bom ? raw.slice(1) : raw;
const lines = text.split('\n');

// ── ① 부위 되돌리기 ──
function fixParts(arr) {
  const out = []; let buf = null;
  for (const p of arr) {
    const piece = buf === null ? p : buf + ',' + p;
    const open = (piece.match(/\(/g) || []).length;
    const close = (piece.match(/\)/g) || []).length;
    if (open > close) buf = piece; else { out.push(piece); buf = null; }
  }
  if (buf !== null) out.push(buf);
  return out;
}
const i = lines.findIndex(l => l.startsWith('const ITEMS = '));
if (i < 0) throw new Error('ITEMS 줄을 못 찾음');
const items = JSON.parse(lines[i].replace(/^const ITEMS = /, '').replace(/;\s*$/, ''));
let fixed = 0;
for (const it of items) {
  const before = it.parts.length;
  it.parts = fixParts(it.parts);
  if (it.parts.length !== before) fixed++;
}
lines[i] = 'const ITEMS = ' + JSON.stringify(items) + ';';
text = lines.join('\n');

// ── ② 언어 전환 단추 ──
const CSS_ADD = `
/* ── 언어 전환 ── */
.langsw{display:inline-flex; border:1px solid var(--line); border-radius:var(--r); overflow:hidden; flex:none}
.langsw a{padding:.5rem .7rem; font-size:.85rem; text-decoration:none; color:var(--ink-soft); background:var(--panel)}
.langsw a[aria-current="true"]{background:var(--accent); color:#fff}
.langsw a:not([aria-current="true"]):hover{color:var(--ink)}
</style>`;
let added = 0;
if (!text.includes('class="langsw"')) {
  text = text.replace(/<\/style>(?![\s\S]*<\/style>)/, CSS_ADD);
  text = text.replace('<div class="dl">',
    `<div class="langsw"><a href="./" aria-current="true" hreflang="ko">KO</a><a href="en/" hreflang="en">EN</a></div>
      <div class="dl">`);
  added = 1;
}

fs.writeFileSync(SRC, (bom ? '﻿' : '') + text, 'utf8');
const msg = [
  `백업: ${fs.existsSync(BAK) ? 'index.ko-backup.html 있음' : '없음'}`,
  `부위 되돌린 품목: ${fixed}개`,
  `언어 전환 단추: ${added ? '추가함' : '이미 있어서 건너뜀'}`,
].join('\n');
fs.writeFileSync(path.join(__dirname, 'fix-ko-report.txt'), msg, 'utf8');
console.log(msg);
