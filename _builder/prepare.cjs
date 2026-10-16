const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const site = process.env.CATALOG_OUTPUT_DIR || path.join(root, '_site');
const logs = process.env.CATALOG_LOG_DIR || path.join(root, '_logs');
const readData = (text, name) => JSON.parse(text.match(new RegExp('^const '+name+'\\s*= (.+);\\r?$', 'm'))[1]);
let body = fs.readFileSync(path.join(__dirname, '취급품목_카탈로그.html'), 'utf8').replace(/^\uFEFF?\s*<title>.*?<\/title>\s*/s, '');
const meta = readData(body, 'META');
const title = `제주수창 취급품목 — 원물 ${meta.total}종`;
const desc = `청정 제주 원물 ${meta.total}종 · B2B 대량 공급. 농산물 ${meta.byCat['농산물']}종 · 해조류 ${meta.byCat['해조류']}종 · 약재 ${meta.byCat['약재']}종`;
const base = 'https://suchang-marketing.github.io/catalog';
fs.writeFileSync(path.join(site, 'index.html'), `<!doctype html>
<html lang="ko"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${title}</title><meta name="description" content="${desc}">
<meta name="robots" content="noindex,nofollow"><meta property="og:type" content="website">
<meta property="og:site_name" content="(주)수창 JEJU SUCHANG"><meta property="og:title" content="${title}">
<meta property="og:description" content="${desc}"><meta property="og:image" content="${base}/og.png">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta property="og:url" content="${base}/"><meta property="og:locale" content="ko_KR">
<meta name="twitter:card" content="summary_large_image"><link rel="icon" href="${base}/og.png">
<style>body{margin:0}</style></head><body>${body}\n</body></html>\n`);
execFileSync(process.execPath, [path.join(root, 'fix-ko.js')], { stdio: 'inherit' });
const previousEnglish = fs.readFileSync(path.join(site, 'en/index.html'));
let held = false;
try {
  execFileSync(process.execPath, [path.join(root, 'build-en.js')], { stdio: 'inherit' });
  held = /확인 필요/.test(fs.readFileSync(path.join(site, 'build-report.txt'), 'utf8'));
} catch (error) {
  held = true;
  fs.appendFileSync(path.join(site, 'build-report.txt'), `\n영문 생성 실패: ${error.message}\n`);
}
if (held) {
  fs.writeFileSync(path.join(site, 'en/index.html'), previousEnglish);
  console.log('::warning::영문판 갱신 보류. 이전 영문판 유지됨. build-report.txt를 확인할 것.');
}
fs.mkdirSync(logs, { recursive: true });
for (const name of ['build-report.txt', 'fix-ko-report.txt']) {
  fs.copyFileSync(path.join(site, name), path.join(logs, name));
  fs.unlinkSync(path.join(site, name));
}
fs.unlinkSync(path.join(site, 'index.ko-backup.html'));
fs.writeFileSync(path.join(site, '.nojekyll'), '');
fs.writeFileSync(path.join(site, 'refresh-status.json'), JSON.stringify({
  generatedAt: new Date().toISOString(), runId: process.env.GITHUB_RUN_ID || 'local',
  materials: meta.total, products: meta.goods, english: held ? 'held' : 'updated'
}, null, 2)+'\n');
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
  `## 웹카달로그 갱신\n\n원물 ${meta.total}종 / 상품 ${meta.goods}개\n\n`+
  (held ? '⚠️ 영문판은 이전 내용 유지됨. 아래 catalog-build-logs의 build-report.txt에서 빠진 번역을 확인할 것.\n' : '한글·영문 생성 완료.\n')+
  '\n발행 성공 여부는 실행 결과가 초록색인지 확인할 것.\n');
module.exports = { readData };
