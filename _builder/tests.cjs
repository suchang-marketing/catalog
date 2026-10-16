const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
test('알 수 없는 공급형태는 결과 파일을 쓰기 전에 차단함',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'catalog-validation-'));
  try {
    const src=path.join(dir,'items.csv'),out=path.join(dir,'mirror.csv');
    fs.writeFileSync(src,'PID,MID,게시상태,카테고리,사용부위,생산방식,품목명,원물명,공급형태\nP-M001-01,M001,게시,농산물,열매,일반,테스트,테스트,허용되지않는값\n');
    const result=spawnSync('pwsh',['-NoProfile','-File',path.join(__dirname,'build_원물마스터.ps1'),'-Src',src,'-Out',out],{encoding:'utf8'});
    assert.notEqual(result.status,0); assert.match(result.stderr,/새 공급형태/); assert(!fs.existsSync(out));
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});
test('영문 번역 누락 시 기존 영문 파일을 그대로 유지함',()=>{
  const root=path.resolve(__dirname,'..'),dir=fs.mkdtempSync(path.join(os.tmpdir(),'catalog-english-'));
  try {
    fs.mkdirSync(path.join(dir,'en'));
    const previous=fs.readFileSync(path.join(root,'en/index.html'));
    fs.writeFileSync(path.join(dir,'en/index.html'),previous);
    const csv=path.join(dir,'items.csv');
    fs.writeFileSync(csv,'PID,품목명,원물명,영문명,학명,사용부위\n');
    const fragment=path.join(dir,'fragment.html');
    let html=fs.readFileSync(path.join(__dirname,'취급품목_카탈로그.html'),'utf8');
    html=html.replace(/^(const ITEMS = )(.+);\r?$/m,(_,prefix,json)=>{
      const items=JSON.parse(json); items[0].name='번역누락검사용가상원물'; return prefix+JSON.stringify(items)+';';
    });
    fs.writeFileSync(fragment,html);
    const result=spawnSync(process.execPath,[path.join(__dirname,'prepare.cjs')],{encoding:'utf8',env:{...process.env,CATALOG_OUTPUT_DIR:dir,CATALOG_ITEM_CSV:csv,CATALOG_FRAGMENT_PATH:fragment,CATALOG_LOG_DIR:path.join(dir,'logs'),GITHUB_STEP_SUMMARY:''}});
    assert.equal(result.status,0,result.stderr);
    assert.equal(JSON.parse(fs.readFileSync(path.join(dir,'refresh-status.json'))).english,'held');
    assert.deepEqual(fs.readFileSync(path.join(dir,'en/index.html')),previous);
    assert(fs.readFileSync(path.join(dir,'index.html'),'utf8').includes('const ITEMS = '));
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});
