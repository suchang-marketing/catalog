const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const site = process.env.CATALOG_OUTPUT_DIR || path.resolve(__dirname, '../_site');
const ko = fs.readFileSync(path.join(site, 'index.html'), 'utf8');
const data = (text, name) => JSON.parse(text.match(new RegExp('^const '+name+'\\s*= (.+);\\r?$', 'm'))[1]);
const items = data(ko, 'ITEMS'), meta = data(ko, 'META');
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const logo = 'data:image/png;base64,' + fs.readFileSync(path.join(__dirname, '로고/수창로고_웹.png')).toString('base64');
const font = '"Noto Sans CJK KR", "Malgun Gothic", sans-serif';
const notes = [
  `취급 품목란은 원물의 가공형태별 상품임(전체 ${meta.goods}개).`,
  '생산방식은 일반이 기본이며, 일부 원물에 친환경·유기농 인증품이 추가됨. 품목별 등급은 요청 시 안내함.',
  '자연산·양식은 채취·양식 구분이며 인증이 아님.',
  '(업사이클)로 표시한 품목은 버려지던 부위·부산물을 원료로 쓰는 것임.',
  'HS코드는 6단위 참고용이며 최종 세번은 수입국 세관이 정함. 세번 확인 중인 품목은 해당 코드가 확정되지 않은 것임.',
  '규격·포장단위는 요청 시 별도 안내함. 단가는 수량·납기에 따라 협의함.'
];
const sections = ['농산물','해조류','약재'].map(cat => {
  const rows = items.filter(i => i.cat === cat);
  return `<section><h2>${cat} <small>${rows.length}종</small></h2><table>
  <colgroup><col style="width:8%"><col style="width:18%"><col style="width:13%"><col style="width:16%"><col style="width:29%"><col style="width:16%"></colgroup>
  <thead><tr>${['코드','원물명','HS코드','가공형태','취급 품목','생산방식'].map(x => `<th>${x}</th>`).join('')}</tr></thead>
  <tbody>${rows.map(i => {
    const goods = [...new Set(i.goods.map(g => g.n + (g.u ? ' (업사이클)' : '') + (i.hsChk.includes(g.n) ? ' (세번 확인 중)' : '')))];
    return `<tr>${[i.id,i.name,i.hs.join(', '),i.proc.join(', '),goods.join(', '),[...i.grades,...i.method].join(', ')].map(v => `<td>${esc(v)}</td>`).join('')}</tr>`;
  }).join('')}</tbody></table></section>`;
}).join('');
const html = `<!doctype html><html lang="ko"><head><meta charset="utf-8"><style>
@page { size:A4; margin:16mm 13mm 18mm; }
* { box-sizing:border-box } body { margin:0; color:#18211d; font-family:${font}; font-size:9pt; }
.cover { height:245mm; break-after:page; padding-top:43mm; text-align:center; }
.cover img { width:48mm; height:28mm; object-fit:contain; margin-bottom:17mm }
.cover .eyebrow { font-size:12pt; color:#2f5d4a; letter-spacing:2px; }
h1 { font-size:30pt; margin:9mm 0 5mm; } .counts { color:#2f5d4a; font-size:11pt; line-height:1.8; }
.contact { margin-top:25mm; color:#5e6b64; line-height:2; }
section { break-before:page; } h2 { color:#2f5d4a; font-size:18pt; margin:0 0 6mm; } small { font-size:10pt; font-weight:normal; margin-left:3mm; }
table { border-collapse:collapse; width:100%; table-layout:fixed; font-size:8pt; line-height:1.55; }
thead { display:table-header-group; } tr { break-inside:avoid; } th,td { padding:2.2mm 1.5mm; border:0.3mm solid #dfe4dd; vertical-align:top; overflow-wrap:anywhere; }
th { background:#2f5d4a; color:white; text-align:left; font-weight:600; } tbody tr:nth-child(even) { background:#f4f6f2; }
.notes { margin-top:7mm; font-size:8pt; line-height:1.8; color:#5e6b64; } .notes p { margin:1mm 0 }
</style></head><body><div class="cover"><img src="${logo}"><div class="eyebrow">JEJU SUCHANG</div><h1>취급품목 카탈로그</h1>
<div class="counts">원물 ${meta.total}종 · 상품 ${meta.goods}개<br>농산물 ${meta.byCat['농산물']}종 · 해조류 ${meta.byCat['해조류']}종 · 약재 ${meta.byCat['약재']}종</div>
<div class="contact">${esc(meta.updated)} 기준<br>TEL 064-713-6696<br>www.jejusuchang.com</div></div>${sections}
<div class="notes">${notes.map(n => `<p>· ${esc(n)}</p>`).join('')}</div></body></html>`;
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined });
  try {
    const page = await browser.newPage({ viewport:{width:1200,height:630}, deviceScaleFactor:1 });
    await page.setContent(html);
    await page.evaluate(() => document.fonts.ready);
    await page.pdf({ path:path.join(site,'취급품목_카탈로그.pdf'), format:'A4', printBackground:true,
      displayHeaderFooter:true, headerTemplate:'<span></span>', footerTemplate:'<div style="font-size:8px;width:100%;text-align:center;color:#718078">JEJU SUCHANG · <span class="pageNumber"></span> / <span class="totalPages"></span></div>' });
    const status = JSON.parse(fs.readFileSync(path.join(site,'refresh-status.json')));
    for (const en of [false,true]) {
      if (en && status.english === 'held') continue;
      await page.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>
      body{margin:0;width:1200px;height:630px;background:#f4f6f2;border-top:14px solid #2f5d4a;padding:65px 85px;box-sizing:border-box;font-family:${font};color:#18211d}
      img{width:255px;height:155px;object-fit:contain;object-position:left} .eyebrow{color:#2f5d4a;font-size:25px;margin-top:28px} h1{font-size:${en?65:76}px;line-height:1.1;margin:22px 0} p{font-size:26px;color:#5e6b64;margin:15px 0} footer{font-size:23px;color:#5e6b64;margin-top:25px}
      </style></head><body><img src="${logo}"><div class="eyebrow">${en?'JEJU SUCHANG CO., LTD.':'(주)수창 · JEJU SUCHANG'}</div>
      <h1>${en?'PRODUCT CATALOG':'취급품목 카탈로그'}</h1><p>${en?`${meta.total} Raw Materials · B2B Bulk Supply`:`청정 제주 원물 ${meta.total}종 · B2B 대량 공급`}</p>
      <p>${en?`Agricultural ${meta.byCat['농산물']} · Marine Algae ${meta.byCat['해조류']} · Medicinal Herbs ${meta.byCat['약재']}`:`농산물 ${meta.byCat['농산물']}종 · 해조류 ${meta.byCat['해조류']}종 · 약재 ${meta.byCat['약재']}종`}</p>
      <footer>www.jejusuchang.com · TEL ${en?'+82-64':'064'}-713-6696</footer></body></html>`);
      await page.evaluate(() => document.fonts.ready);
      await page.screenshot({ path:path.join(site,en?'en/og.png':'og.png') });
    }
    console.log(`PDF 및 공유 이미지 생성 완료: 원물 ${meta.total}종`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
