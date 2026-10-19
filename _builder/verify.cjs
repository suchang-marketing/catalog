const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');
const site = process.env.CATALOG_OUTPUT_DIR || path.resolve(__dirname,'../_site');
(async () => {
  const allowed = ['.nojekyll','index.html','og.png','취급품목_카탈로그.pdf','en/index.html','en/og.png','refresh-status.json'].sort();
  const files = fs.readdirSync(site,{recursive:true}).filter(f=>fs.statSync(path.join(site,f)).isFile()).map(f=>f.replaceAll('\\','/')).sort();
  assert.deepEqual(files,allowed,'발행 폴더에는 공개 파일만 포함되어야 함');
  const pdf = fs.readFileSync(path.join(site,'취급품목_카탈로그.pdf'));
  assert(pdf.subarray(0,5).toString()==='%PDF-' && pdf.length>10000,'PDF 생성 실패');
  const status = JSON.parse(fs.readFileSync(path.join(site,'refresh-status.json')));
  const browser = await chromium.launch({executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined});
  try {
    for(const lang of ['','en/']) {
      const page = await browser.newPage();
      const errors=[]; page.on('pageerror',e=>errors.push(e.message));
      await page.goto(pathToFileURL(path.join(site,lang,'index.html')).href);
      const result = await page.evaluate(()=>({count:ITEMS.length,total:META.total,goods:META.goods,rows:META.rows,actual:ITEMS.reduce((s,i)=>s+i.goods.length,0),link:document.querySelector('#dl-pdf')?.getAttribute('href'),languages:document.querySelectorAll('.langsw a').length}));
      assert.equal(result.count,result.total); assert.equal(result.rows,result.actual); assert(result.goods<=result.rows);
      assert.equal(result.languages,2); assert(result.link,'PDF 다운로드 링크 없음');
      const file=path.resolve(site,lang,decodeURIComponent(result.link));
      assert(fs.existsSync(file),'PDF 링크가 파일을 가리키지 않음');
      if(!lang || status.english==='updated') assert.equal(result.total,status.materials);
      assert.deepEqual(errors,[],'웹페이지 실행 오류');
      await page.close();
    }
  } finally { await browser.close(); }
  console.log(`검사 통과: 원물 ${status.materials}종 / 상품 ${status.products}개 / 영문 ${status.english}`);
})().catch(error=>{console.error(error);process.exitCode=1;});
