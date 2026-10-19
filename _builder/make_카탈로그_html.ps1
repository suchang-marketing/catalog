# 취급품목 카탈로그 — 웹(HTML) 생성
#
# 입력: 카탈로그_원물단위.csv + 카탈로그_상품단위.csv
# 출력: 취급품목_카탈로그.html  (단일 파일, 외부 의존 없음 → 그대로 배포 가능)
#
# 원칙: 품목·수치를 손으로 옮겨 적지 않는다. CSV에서 직접 읽어 채운다.
#       원본이 갱신되면 이 스크립트만 다시 돌리면 웹 카탈로그가 최신이 된다.
#
# 이미지: 사진썸네일\{Material ID}.jpg 가 있으면 base64로 임베드(단일 파일 유지).
#         썸네일 생성은 fetch_사진썸네일.ps1 (홈페이지 → 180px JPEG).
#         사진 없는 원물은 기존 "준비 중" 문구 유지.

param(
  [string]$SrcMat   = "$PSScriptRoot\카탈로그_원물단위.csv",
  [string]$SrcProd  = "$PSScriptRoot\카탈로그_상품단위.csv",
  [string]$PhotoDir = "$PSScriptRoot\사진썸네일",
  [string]$LogoFile = "$PSScriptRoot\로고\수창로고_웹.png",
  [string]$Out      = "$PSScriptRoot\취급품목_카탈로그.html",
  # PDF 내려받기 단추가 가리킬 곳. 웹 발행 폴더·이 폴더 모두 PDF가 같은 자리에 있으므로 상대경로면 됨.
  [string]$PdfUrl   = '취급품목_카탈로그.pdf'
)

$ErrorActionPreference = 'Stop'
foreach ($p in @($SrcMat, $SrcProd)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "입력 없음: $p — build_카탈로그.ps1을 먼저 실행할 것." }
}

$mat  = Import-Csv -LiteralPath $SrcMat  -Encoding UTF8
$prod = Import-Csv -LiteralPath $SrcProd -Encoding UTF8
# 기대 종수 = 미러의 고유 Material ID 수(하드코딩 금지 — 자초 M237 추가 사례)
$기대종수 = @((Import-Csv "$PSScriptRoot\원물마스터_미러.csv" -Encoding UTF8).'Material ID' | Where-Object { $_ } | Sort-Object -Unique).Count
if ($mat.Count -ne $기대종수) { throw "원물 행수($($mat.Count))가 미러 고유 ID 수($기대종수)와 다름 — build_카탈로그.ps1 재실행 필요" }

# 원물별 상품 목록(가공형태 소분류까지) — 펼쳤을 때 보여줄 상세
$prodBy = $prod | Group-Object 'Material ID' -AsHashTable -AsString

# 회사 로고 — 아티팩트는 외부 이미지를 못 불러오므로 base64로 심는다(사진과 같은 방식).
# 원본은 Drive '로고.png', 전처리는 prep_로고.ps1(여백 제거 + 흰 배경 투명화).
$logoUri = ''
if (Test-Path -LiteralPath $LogoFile) {
  $logoUri = 'data:image/png;base64,' + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($LogoFile))
}

$photoCount = 0
$items = foreach ($m in $mat) {
  $ps = @($prodBy[$m.'Material ID'])
  $imgUri = ''
  $pf = Join-Path $PhotoDir "$($m.'Material ID').jpg"
  if (Test-Path -LiteralPath $pf) {
    $imgUri = 'data:image/jpeg;base64,' + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pf))
    $photoCount++
  }
  # 등급은 상품 단위로 붙는다. 같은 품목이 인증품·일반품 두 등급으로 등록된 경우가 있어
  # 원물 단위로 합치면 원물 전체가 인증품처럼 보임 → 상품마다 등급을 그대로 붙이고,
  # 원물 라벨에는 실제로 있는 등급을 전부 나열한다(예: 일반 · 친환경).
  # 인증(유기농·친환경)과 생산방식(자연산·양식)은 다른 것이라 분리한다 —
  # 한 칸에 섞으면 자연산 원물이 인증받은 것으로 읽힘.
  $certVals = @('유기농','친환경','무농약')
  $methodVals = @('자연산','양식')
  # 업사이클(ESG)은 마스터 '비고' 표시가 붙은 **품목**에만 해당함(원물 전체가 아님).
  $goods = @($ps | ForEach-Object {
              $v = $_.'인증/등급'
              [pscustomobject]@{
                n = $_.'상품(원료)명'; f = $_.'가공형태(소분류)'
                p = $_.'사용부위'
                g = $(if ($v -in $certVals) { $v } else { '일반' })
                u = ($_.'업사이클' -eq 'Y')
                h = $_.'HS코드'      # 품목별 HS 6단위(빈 칸 = 공식소스 대조에서 걸러진 것 → 화면에 "확인 중")
              }
            })
  # ★ 일반 등급이 디폴트임(사용자 확인 07-31) — 보통 일반을 취급하고, 일부 원물에 인증품이 더 있음.
  #   그래서 인증이 있는 원물은 언제나 "일반 + 인증명"으로 표시함(인증명만 적으면 과대표기).
  $certNames = @($goods.g | Where-Object { $_ -ne '일반' } | Select-Object -Unique | Sort-Object)
  $gradeList = @(if ($certNames.Count) { @('일반') + $certNames } else { @('일반') })
  $methods   = @($ps.'인증/등급' | Where-Object { $_ -in $methodVals } | Select-Object -Unique | Sort-Object)
  [pscustomobject]@{
    id      = $m.'Material ID'
    cat     = $m.'분류'
    name    = $m.'원물명'
    # HS 6단위 — 원물에 상품이 여럿이면 코드도 여럿일 수 있음(예: 감자 0712.90 · 1105.10).
    # hsChk는 공식소스에 없는 코드라 싣지 않은 품목명. 이게 있는데 hs만 보이면
    # 남은 코드가 원물 전체의 세번인 것처럼 읽히므로 화면에 함께 표기함.
    hs      = @(($m.'HS코드' -split ',\s*') | Where-Object { $_ })
    hsChk   = @(($m.'HS확인중' -split ',\s*') | Where-Object { $_ })
    proc    = @(($m.'가공형태' -split ',\s*') | Where-Object { $_ })
    parts   = @(($m.'사용부위' -split ',\s*') | Where-Object { $_ })
    cert    = @($certNames)     # 필터용(인증명만)
    grades  = @($gradeList)     # 표시용(일반 포함, 있는 등급 전부)
    mixed   = ($gradeList.Count -gt 1)
    method  = @($methods)       # 생산방식(인증 아님)
    upc     = [bool](@($goods | Where-Object { $_.u }).Count)   # 업사이클 품목이 하나라도 있는가
    upcN    = @($goods | Where-Object { $_.u } | ForEach-Object { $_.n })  # 어느 품목인지
    varyPart= (@($goods.p | Where-Object { $_ } | Select-Object -Unique).Count -gt 1)
    img     = $imgUri
    goods   = $goods
  }
}

$json = $items | ConvertTo-Json -Depth 6 -Compress
$meta = [pscustomobject]@{
  total   = $mat.Count
  goods   = @($prod.'Product ID' | Sort-Object -Unique).Count   # 상품 수 = 시트 상품(PID) 기준(가공형태별 줄 수 아님)
  rows    = $prod.Count                                          # 가공형태별 상품 줄 수(내부 검사용)
  byCat   = [ordered]@{}
  updated = (Get-Date -Format 'yyyy-MM-dd')
}
foreach ($c in @('농산물','해조류','약재')) { $meta.byCat[$c] = ($mat | Where-Object { $_.'분류' -eq $c }).Count }
$meta | Add-Member -NotePropertyName photos -NotePropertyValue $photoCount
$metaJson = $meta | ConvertTo-Json -Depth 4 -Compress

$tpl = @'
<title>제주수창 취급품목 — 원물 __TOTAL__종</title>
<style>
:root{
  --ground:#F4F6F2; --panel:#FFFFFF; --ink:#18211D; --ink-soft:#5E6B64; --ink-faint:#8B978F;
  --line:#DFE4DD; --line-soft:#EDF0EA; --accent:#2F5D4A; --accent-soft:#E4EDE7;
  --agri:#7E6326; --agri-bg:#F5EEDC; --sea:#28596B; --sea-bg:#E2EEF2; --herb:#6B3A4C; --herb-bg:#F3E6EA;
  --upc:#0F6E63; --upc-bg:#DCF0EC; --upc-line:#9ED4CB;
  --focus:#3D7A61;
  --r:10px; --sp:clamp(1rem,3vw,1.6rem);
}
@media (prefers-color-scheme:dark){
  :root{
    --ground:#101413; --panel:#171D1B; --ink:#E8EDE9; --ink-soft:#9DAAA3; --ink-faint:#6E7C75;
    --line:#26302C; --line-soft:#1E2724; --accent:#7FBCA0; --accent-soft:#1C2A24;
    --agri:#D3B472; --agri-bg:#2A2418; --sea:#8CC2D4; --sea-bg:#16262C; --herb:#D49BB0; --herb-bg:#2A1B21;
    --upc:#6FD3C2; --upc-bg:#123029; --upc-line:#1F4C42;
    --focus:#8FCFB0;
  }
}
:root[data-theme="dark"]{
  --ground:#101413; --panel:#171D1B; --ink:#E8EDE9; --ink-soft:#9DAAA3; --ink-faint:#6E7C75;
  --line:#26302C; --line-soft:#1E2724; --accent:#7FBCA0; --accent-soft:#1C2A24;
  --agri:#D3B472; --agri-bg:#2A2418; --sea:#8CC2D4; --sea-bg:#16262C; --herb:#D49BB0; --herb-bg:#2A1B21;
  --upc:#6FD3C2; --upc-bg:#123029; --upc-line:#1F4C42;
  --focus:#8FCFB0;
}
:root[data-theme="light"]{
  --ground:#F4F6F2; --panel:#FFFFFF; --ink:#18211D; --ink-soft:#5E6B64; --ink-faint:#8B978F;
  --line:#DFE4DD; --line-soft:#EDF0EA; --accent:#2F5D4A; --accent-soft:#E4EDE7;
  --agri:#7E6326; --agri-bg:#F5EEDC; --sea:#28596B; --sea-bg:#E2EEF2; --herb:#6B3A4C; --herb-bg:#F3E6EA;
  --upc:#0F6E63; --upc-bg:#DCF0EC; --upc-line:#9ED4CB;
  --focus:#3D7A61;
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--ground); color:var(--ink);
  font-family:"Pretendard","Pretendard Variable","Apple SD Gothic Neo","Malgun Gothic",
              system-ui,-apple-system,"Segoe UI",sans-serif;
  font-size:15px; line-height:1.6; -webkit-font-smoothing:antialiased;
}
.mono{font-family:ui-monospace,"SFMono-Regular","Cascadia Mono","Consolas",monospace;
      font-variant-numeric:tabular-nums; letter-spacing:.02em}
.wrap{max-width:1080px; margin:0 auto; padding:0 var(--sp)}

/* ── 머리말 ── */
.masthead{padding:clamp(2rem,6vw,3.4rem) 0 1.4rem}
.eyebrow{font-size:.72rem; letter-spacing:.18em; text-transform:uppercase; color:var(--accent); font-weight:700}
h1{margin:.5rem 0 .3rem; font-size:clamp(1.75rem,5vw,2.6rem); line-height:1.15; letter-spacing:-.02em; text-wrap:balance}
.tagline{margin:0; color:var(--ink-soft); font-size:1rem}
/* 로고 — 제목 왼쪽. 배경이 투명 PNG라 밝은 화면·어두운 화면 모두에서 그대로 쓸 수 있음 */
.titlerow{display:flex; align-items:center; gap:clamp(.8rem,2.5vw,1.4rem)}
.logo{height:clamp(46px,9vw,64px); width:auto; flex:none}
@media (max-width:420px){ .logo{height:40px} }
.counts{display:flex; flex-wrap:wrap; gap:.5rem .9rem; margin-top:1.1rem; align-items:baseline}
.counts .big{font-size:1.5rem; font-weight:700; letter-spacing:-.02em}
.counts .sep{color:var(--line); }
.counts .unit{color:var(--ink-soft); font-size:.9rem}

/* ── 조작부 ── */
.controls{position:sticky; top:0; z-index:20; background:color-mix(in srgb,var(--ground) 92%,transparent);
  backdrop-filter:blur(10px); border-bottom:1px solid var(--line); padding:.7rem 0}
.ctl-inner{display:flex; flex-direction:column; gap:.6rem}
.searchrow{display:flex; gap:.5rem; align-items:center}
.search{flex:1; display:flex; align-items:center; gap:.5rem; background:var(--panel);
  border:1px solid var(--line); border-radius:var(--r); padding:.5rem .7rem}
.search:focus-within{border-color:var(--focus); box-shadow:0 0 0 3px var(--accent-soft)}
.search input{flex:1; border:0; background:transparent; color:inherit; font:inherit; outline:none; min-width:0}
.search svg{flex:none; color:var(--ink-faint)}
.clearbtn{border:1px solid var(--line); background:var(--panel); color:var(--ink-soft);
  border-radius:var(--r); padding:.5rem .8rem; font:inherit; font-size:.85rem; cursor:pointer; white-space:nowrap}
.clearbtn:hover{border-color:var(--focus); color:var(--ink)}
/* 내려받기 — 조작부 오른쪽. 화면이 좁으면 아래 줄로 접힘 */
.dl{display:flex; gap:.35rem; flex:none}
.dlbtn{display:inline-flex; align-items:center; gap:.32rem; border:1px solid var(--line);
  background:var(--panel); color:var(--ink-soft); border-radius:var(--r); padding:.5rem .75rem;
  font:inherit; font-size:.85rem; cursor:pointer; white-space:nowrap; text-decoration:none}
.dlbtn:hover{border-color:var(--focus); color:var(--ink)}
.dlbtn:focus-visible{outline:2px solid var(--focus); outline-offset:2px}
.dlbtn svg{flex:none; color:var(--ink-faint)}
@media (max-width:640px){ .dlbtn span.t{display:none} .dlbtn{padding:.5rem .6rem} }
.filters{display:flex; flex-wrap:wrap; gap:.35rem}
.fgroup{display:flex; flex-wrap:wrap; gap:.3rem; align-items:center}
.flabel{font-size:.7rem; letter-spacing:.1em; color:var(--ink-faint); text-transform:uppercase;
  margin-right:.15rem; font-weight:700}
.chip{border:1px solid var(--line); background:var(--panel); color:var(--ink-soft);
  border-radius:999px; padding:.28rem .7rem; font-size:.82rem; cursor:pointer; font:inherit;
  line-height:1.4; transition:background .12s,border-color .12s,color .12s}
.chip:hover{border-color:var(--focus)}
.chip[aria-pressed="true"]{background:var(--accent); border-color:var(--accent); color:#fff; font-weight:600}
:root[data-theme="dark"] .chip[aria-pressed="true"],
@media (prefers-color-scheme:dark){.chip[aria-pressed="true"]{color:#0F1613}}
.chip:focus-visible,.clearbtn:focus-visible,.row:focus-visible{outline:2px solid var(--focus); outline-offset:2px}

/* ── 결과 ── */
.status{padding:1rem 0 .4rem; color:var(--ink-soft); font-size:.88rem}
.status b{color:var(--ink); font-weight:700}
.catblock{margin-bottom:1.6rem}
.cathead{position:sticky; top:calc(var(--stick,116px)); z-index:10;
  display:flex; align-items:baseline; gap:.6rem; padding:.5rem 0;
  background:color-mix(in srgb,var(--ground) 94%,transparent); backdrop-filter:blur(6px)}
.catname{font-size:1.05rem; font-weight:700; letter-spacing:-.01em}
.catcount{font-size:.8rem; color:var(--ink-faint)}
.catrule{flex:1; height:1px; background:var(--line)}
.list{display:flex; flex-direction:column; gap:2px}

.row{display:grid; grid-template-columns:5.4rem 1fr auto; gap:.5rem .8rem; align-items:center;
  width:100%; text-align:left; background:var(--panel); border:1px solid var(--line-soft);
  border-radius:var(--r); padding:.62rem .8rem; font:inherit; color:inherit; cursor:pointer;
  transition:border-color .12s, background .12s}
.row:hover{border-color:var(--line)}
.row[aria-expanded="true"]{border-color:var(--accent)}
.code{font-size:.76rem; color:var(--ink-faint); display:flex; flex-direction:column; gap:.1rem}
/* HS 6단위 — 코드 칸 아랫줄. 숫자라 자릿수가 흔들리지 않게 mono */
.hs{font-size:.72rem; color:var(--ink-soft); letter-spacing:.01em}
.hs .more{color:var(--ink-faint)}
.hs.pend{color:var(--ink-faint)}
.namecell{display:flex; flex-wrap:wrap; align-items:baseline; gap:.4rem .55rem; min-width:0}
.nm{font-weight:600; letter-spacing:-.01em}
.goodspeek{color:var(--ink-faint); font-size:.82rem; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; max-width:100%}
.tags{display:flex; gap:.3rem; flex-wrap:wrap; justify-content:flex-end}
.tag{font-size:.72rem; padding:.14rem .5rem; border-radius:999px; white-space:nowrap; border:1px solid transparent}
.tag.proc{background:var(--line-soft); color:var(--ink-soft)}
.tag.cert{background:var(--accent-soft); color:var(--accent); font-weight:600}
/* 기본 등급 — 인증 라벨과 나란히 놓여도 구분되게 회색으로 */
.tag.plain{background:transparent; color:var(--ink-faint); border-color:var(--line)}
/* 생산방식(자연산·양식) — 인증이 아니므로 인증 라벨과 다른 색으로 */
.tag.method{background:var(--line-soft); color:var(--ink-soft); font-weight:600}
/* 업사이클(ESG) — 인증·생산방식과 또 다른 축이므로 색을 따로 씀 */
.tag.upc{background:var(--upc-bg); color:var(--upc); font-weight:600; border-color:var(--upc-line)}
.good.upcd{background:var(--upc-bg)}
.good em{font-style:normal; color:var(--upc); font-size:.72rem; font-weight:700; margin-left:.25rem}
.good.certed{background:var(--accent-soft)}
.good b{font-weight:700; color:var(--accent); font-size:.72rem; margin-left:.2rem}
.good s{text-decoration:none; color:var(--ink-faint); font-size:.72rem; margin-left:.2rem}
.good u{text-decoration:none; color:var(--ink-soft); font-size:.72rem; margin-left:.25rem}
.cat-농산물 .code,.cat-농산물 .nm::before{color:var(--agri)}
.dot{width:.42rem; height:.42rem; border-radius:50%; flex:none; display:inline-block}
.d-농산물{background:var(--agri)} .d-해조류{background:var(--sea)} .d-약재{background:var(--herb)}

.detail{background:var(--panel); border:1px solid var(--accent); border-top:0;
  border-radius:0 0 var(--r) var(--r); margin-top:-2px; padding:.8rem .9rem 1rem; font-size:.88rem}
.dgrid{display:grid; grid-template-columns:5.2rem 1fr; gap:.45rem .8rem}
.dk{color:var(--ink-faint); font-size:.8rem}
.dv{color:var(--ink)}
.goodlist{display:flex; flex-wrap:wrap; gap:.3rem}
.good{background:var(--line-soft); border-radius:6px; padding:.18rem .5rem; font-size:.8rem}
.good i{font-style:normal; color:var(--ink-faint); font-size:.74rem}
/* 품목별 HS 6단위 — 따옴표가 붙지 않게 quotes를 지움 */
.good q{quotes:none; color:var(--ink-soft); font-size:.72rem; margin-left:.28rem}
.good q.pend{color:var(--ink-faint)}
.photoslot{margin-top:.7rem; border:1px dashed var(--line); border-radius:8px; padding:.6rem .7rem;
  color:var(--ink-faint); font-size:.78rem}
.dphoto{width:120px; height:auto; border-radius:8px; border:1px solid var(--line);
  float:right; margin:0 0 .6rem .9rem}
@media (max-width:640px){ .dphoto{width:96px} }

.empty{padding:3rem 1rem; text-align:center; color:var(--ink-soft)}
.empty b{display:block; color:var(--ink); font-size:1.05rem; margin-bottom:.3rem}

footer{border-top:1px solid var(--line); margin-top:2rem; padding:1.6rem 0 3rem; color:var(--ink-soft); font-size:.85rem}
.notes{display:flex; flex-direction:column; gap:.3rem; margin-bottom:1.2rem}
.contact{display:flex; flex-wrap:wrap; gap:.4rem 1.2rem; align-items:baseline}
.contact .co{font-weight:700; color:var(--ink)}
footer a{color:var(--accent)}
@media (max-width:640px){
  .row{grid-template-columns:3.9rem 1fr; }
  .tags{grid-column:1/-1; justify-content:flex-start}
  .goodspeek{display:none}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>

<div class="wrap">
  <header class="masthead">
    <div class="eyebrow">Jeju Suchang · B2B Raw Material</div>
    <div class="titlerow">
      __LOGO__
      <div>
        <h1>취급품목</h1>
        <p class="tagline">청정 제주, 그 자체를 원료로</p>
      </div>
    </div>
    <div class="counts">
      <span class="big mono" id="c-total">—</span><span class="unit">종</span>
      <span class="sep">/</span>
      <span class="unit"><span class="dot d-농산물"></span> 농산물 <b class="mono" id="c-농산물">—</b></span>
      <span class="unit"><span class="dot d-해조류"></span> 해조류 <b class="mono" id="c-해조류">—</b></span>
      <span class="unit"><span class="dot d-약재"></span> 약재 <b class="mono" id="c-약재">—</b></span>
    </div>
  </header>
</div>

<div class="controls" id="controls">
  <div class="wrap ctl-inner">
    <div class="searchrow">
      <label class="search">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
        <input id="q" type="search" placeholder="원물명 또는 품목으로 찾기 (예: 감태, 진피, 분말)" autocomplete="off">
      </label>
      <button class="clearbtn" id="reset" type="button">초기화</button>
      <div class="dl">
        <button class="dlbtn" id="dl-xls" type="button" title="지금 화면에 보이는 목록을 엑셀로 내려받음">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><path d="M12 3v12m0 0 4-4m-4 4-4-4"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/></svg>
          <span class="t">엑셀</span>
        </button>
        <a class="dlbtn" id="dl-pdf" href="__PDF__" download title="카탈로그 전체를 PDF로 내려받음">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/></svg>
          <span class="t">PDF</span>
        </a>
      </div>
    </div>
    <div class="filters">
      <div class="fgroup"><span class="flabel">분류</span><span id="f-cat"></span></div>
      <div class="fgroup"><span class="flabel">가공</span><span id="f-proc"></span></div>
      <div class="fgroup"><span class="flabel">생산방식</span><span id="f-cert"></span><span id="f-method"></span></div>
      <div class="fgroup"><span class="flabel">ESG</span><span id="f-upc"></span></div>
    </div>
  </div>
</div>

<div class="wrap">
  <p class="status" id="status"></p>
  <div id="results"></div>
  <footer>
    <div class="notes">
      <span>· 취급 품목은 해당 원물의 가공형태별 상품임. 전체 <b id="n-goods">—</b>개.</span>
      <span>· 원물 사진 <b id="n-photos">—</b>종 수록함. 나머지는 준비 중임.</span>
      <span>· <b>생산방식은 일반이 기본이고, 일부 원물에 친환경·유기농(인증품)이 더 있음.</b> "일반 · 친환경"처럼 적힌 원물은 두 가지를 함께 취급함 — 항목을 열면 어느 품목이 인증품인지 보임.</span>
      <span>· <b>자연산·양식은 채취·양식 구분이며 인증이 아님.</b></span>
      <span>· <b>업사이클(ESG)</b>은 버려지던 부위·부산물을 원료로 쓰는 품목임. 위 ESG 단추로 모아 볼 수 있음.</span>
      <span>· <b>HS코드는 6단위 참고용임.</b> 미국 HTS·관세청 두 공식자료와 대조한 값이며, 최종 세번은 수입국 세관이 정함. "확인 중"인 품목은 대조가 끝나지 않아 적지 않음.</span>
      <span>· <b>엑셀</b> 단추는 지금 화면에 보이는 목록만 내려받음(검색·조건을 걸면 그만큼만 받아짐).</span>
      <span>· 규격·포장단위는 요청 시 별도 안내함.</span>
      <span>· 단가는 수량·납기에 따라 협의함.</span>
    </div>
    <div class="contact">
      <span class="co">(주)수창 JEJU SUCHANG</span>
      <span>TEL 064-713-6696</span>
      <span><a href="https://www.jejusuchang.com">www.jejusuchang.com</a></span>
      <span id="updated"></span>
    </div>
  </footer>
</div>

<script>
const ITEMS = /*__DATA__*/;
const META  = /*__META__*/;
const CATS  = ['농산물','해조류','약재'];
const PROCS = ['원물','전처리/냉동','건조','액상/추출','가공/기타'];

const state = { q:'', cat:new Set(), proc:new Set(), cert:new Set(), method:new Set(), upc:new Set(), open:null };

const certList   = [...new Set(ITEMS.flatMap(i=>i.cert))].sort();
const methodList = [...new Set(ITEMS.flatMap(i=>i.method))].sort();
const $ = s => document.querySelector(s);

document.getElementById('c-total').textContent = META.total;
CATS.forEach(c => document.getElementById('c-'+c).textContent = META.byCat[c]);
document.getElementById('n-goods').textContent = META.goods;
document.getElementById('n-photos').textContent = META.photos;
document.getElementById('updated').textContent = META.updated + ' 기준';

function chipRow(host, values, key){
  host.innerHTML = '';
  values.forEach(v=>{
    const b = document.createElement('button');
    b.type='button'; b.className='chip'; b.textContent=v; b.setAttribute('aria-pressed','false');
    b.onclick = ()=>{
      const s = state[key];
      s.has(v) ? s.delete(v) : s.add(v);
      b.setAttribute('aria-pressed', s.has(v));
      render();
    };
    host.appendChild(b);
  });
}
chipRow($('#f-cat'),  CATS,  'cat');
chipRow($('#f-proc'), PROCS.filter(p => ITEMS.some(i=>i.proc.includes(p))), 'proc');   // 마스터에 없는 가공 단계는 칩을 만들지 않는다(눌러도 0건이라 혼란)
chipRow($('#f-cert'), certList, 'cert');
chipRow($('#f-method'), methodList, 'method');
chipRow($('#f-upc'), ['업사이클(ESG)'], 'upc');

$('#q').addEventListener('input', e=>{ state.q = e.target.value.trim().toLowerCase(); render(); });
$('#reset').addEventListener('click', ()=>{
  state.q=''; state.cat.clear(); state.proc.clear(); state.cert.clear(); state.method.clear(); state.upc.clear(); state.open=null;
  $('#q').value='';
  document.querySelectorAll('.chip').forEach(c=>c.setAttribute('aria-pressed','false'));
  render(); $('#q').focus();
});

function match(it){
  if(state.cat.size  && !state.cat.has(it.cat)) return false;
  if(state.cert.size && !it.cert.some(c=>state.cert.has(c))) return false;
  if(state.method.size && !it.method.some(v=>state.method.has(v))) return false;
  if(state.upc.size && !it.upc) return false;
  if(state.proc.size && !it.proc.some(p=>state.proc.has(p))) return false;
  if(state.q){
    // HS도 검색 대상 — 바이어가 세번으로 찾는 경우가 있음. 점을 뺀 형태(071290)로도 걸리게 함
    const hs = it.hs.join(' ');
    const hay = (it.name+' '+it.id+' '+it.goods.map(g=>g.n+' '+g.f).join(' ')+' '+it.parts.join(' ')
                 +' '+hs+' '+hs.replace(/\./g,'')+(it.upc?' 업사이클 esg':'')).toLowerCase();
    if(!hay.includes(state.q.replace(/\s+/g,' '))) return false;
  }
  return true;
}

function esc(s){ return String(s).replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function render(){
  const hits = ITEMS.filter(match);
  const on = state.cat.size+state.proc.size+state.cert.size+state.method.size+state.upc.size || state.q;
  $('#status').innerHTML = on
    ? `<b>${hits.length}종</b> 찾음 <span style="color:var(--ink-faint)">/ 전체 ${META.total}종</span>`
    : `전체 <b>${META.total}종</b> · 상품 ${META.goods}개 · 항목을 누르면 상세가 열림`;

  const box = $('#results');
  if(!hits.length){
    box.innerHTML = `<div class="empty"><b>해당하는 원물이 없음</b>조건을 줄이거나 초기화해 보십시오.</div>`;
    return;
  }
  let html = '';
  CATS.forEach(cat=>{
    const rows = hits.filter(i=>i.cat===cat);
    if(!rows.length) return;
    html += `<section class="catblock"><div class="cathead">
      <span class="dot d-${cat}"></span><span class="catname">${cat}</span>
      <span class="catcount">${rows.length}종</span><span class="catrule"></span></div><div class="list">`;
    rows.forEach(it=>{
      const opened = state.open === it.id;
      // 미리보기는 이름 중복 제거 — 같은 품목의 인증품·일반품이 두 줄이라 그대로 쓰면 오류처럼 보임
      const peekNames = [...new Set(it.goods.map(g=>g.n))];
      const peek = peekNames.length>1 ? peekNames.join(', ') : '';
      // HS는 원물당 여러 개일 수 있음(품목마다 다름) — 줄에는 첫 코드만, 나머지는 "외 n"으로 접고
      // 정확한 대응은 펼친 상세에서 품목별로 보여줌. 코드를 못 실은 품목만 있으면 "확인 중".
      const hsCell = it.hs.length
        ? `<span class="hs mono">${it.hs[0]}${it.hs.length>1?`<span class="more"> 외 ${it.hs.length-1}</span>`:''}</span>`
        : (it.hsChk.length ? `<span class="hs pend">확인 중</span>` : '');
      html += `<button class="row cat-${cat}" type="button" aria-expanded="${opened}" data-id="${it.id}">
        <span class="code"><span class="mono">${it.id}</span>${hsCell}</span>
        <span class="namecell"><span class="nm">${esc(it.name)}</span>
          ${peek ? `<span class="goodspeek">${esc(peek)}</span>` : ''}</span>
        <span class="tags">
          ${it.proc.map(p=>`<span class="tag proc">${esc(p)}</span>`).join('')}
          ${it.method.map(v=>`<span class="tag method">${esc(v)}</span>`).join('')}
          ${it.upc ? `<span class="tag upc">업사이클</span>` : ''}
          ${it.cert.length ? it.grades.map(g=>g==='일반'
              ? `<span class="tag plain">일반</span>`
              : `<span class="tag cert">${esc(g)}</span>`).join('') : ''}
        </span></button>`;
      if(opened){
        // 원물 안에서 값이 갈리는 것만 품목마다 붙임(전 품목이 같으면 아래 줄로 충분)
        const showGrade = it.mixed, showPart = it.varyPart;
        html += `<div class="detail">${it.img?`<img class="dphoto" src="${it.img}" alt="${esc(it.name)} 사진">`:''}<div class="dgrid">
          <span class="dk">취급 품목</span><span class="dv"><span class="goodlist">${
            it.goods.map(g=>{
              const cert = g.g!=='일반';
              const part  = showPart && g.p ? ` <u>${esc(g.p)}</u>` : '';
              const badge = !showGrade ? '' : (cert ? ` <b>${esc(g.g)}</b>` : ` <s>일반</s>`);
              const up = g.u ? ` <em>업사이클</em>` : '';
              // 품목별 HS — 원물 칸에 코드를 몰아 적으면 어느 품목 것인지 알 수 없어 여기에 붙임
              const hs = g.h ? ` <q class="mono">${esc(g.h)}</q>` : ` <q class="pend">HS 확인 중</q>`;
              return `<span class="good${showGrade&&cert?' certed':''}${g.u?' upcd':''}">${esc(g.n)}${g.f?` <i>${esc(g.f)}</i>`:''}${part}${hs}${badge}${up}</span>`;
            }).join('')
          }</span></span>
          <span class="dk">사용 부위</span><span class="dv">${esc(it.parts.join(', ')||'—')}${showPart?' <span style="color:var(--ink-faint);font-size:.8rem">— 품목마다 다름(위 표시 참조)</span>':''}</span>
          <span class="dk">HS코드</span><span class="dv"><span class="mono">${it.hs.join(' · ')||'—'}</span>${
            it.hsChk.length?` <span style="color:var(--ink-faint);font-size:.8rem">— ${esc(it.hsChk.join(', '))}은(는) 세번 확인 중임</span>`:''
          }</span>
          <span class="dk">가공 형태</span><span class="dv">${esc(it.proc.join(', '))}</span>
          <span class="dk">생산방식</span><span class="dv">${esc([...it.grades, ...it.method].join(' · '))}</span>
          ${it.upc?`<span class="dk">업사이클</span><span class="dv">${esc(it.upcN.join(', '))} <span style="color:var(--ink-faint);font-size:.8rem">— 버려지던 부위·부산물을 원료로 쓰는 품목임</span></span>`:''}
          <span class="dk">품목 코드</span><span class="dv mono">${it.id}</span>
        </div>${it.img?'':`<div class="photoslot">원물 사진은 준비 중임. 필요하시면 문의 시 함께 보내드림.</div>`}</div>`;
      }
    });
    html += `</div></section>`;
  });
  box.innerHTML = html;

  box.querySelectorAll('.row').forEach(r=>{
    r.onclick = ()=>{ const id=r.dataset.id; state.open = (state.open===id)?null:id; render();
      requestAnimationFrame(()=>{ const el=document.querySelector(`.row[data-id="${id}"]`); if(el&&state.open===id) el.focus({preventScroll:true}); }); };
  });
}

// ── 엑셀 내려받기 ──
// 화면에 보이는 목록(필터·검색이 걸린 그대로)을 CSV로 만들어 준다.
// 엑셀 한글이 깨지지 않게 맨 앞에 BOM을 붙인다(회사 공통 규칙).
// HS는 ="0712.90" 형태로 넣는다 — 그냥 넣으면 엑셀이 숫자로 읽어 712.9로 바꿔 버린다(실제로 겪은 사고).
function csvCell(v){ return '"' + String(v ?? '').replace(/"/g,'""') + '"'; }
function csvCode(v){ return v ? '"=""' + String(v).replace(/"/g,'""') + '"""' : '""'; }
function downloadCsv(){
  const hits = ITEMS.filter(match);
  const head = ['코드','분류','원물명','HS코드','HS 확인 중','가공형태','취급 품목','사용부위','생산방식','업사이클'];
  const lines = [head.map(csvCell).join(',')];
  CATS.forEach(cat=>{
    hits.filter(i=>i.cat===cat).forEach(it=>{
      lines.push([
        csvCell(it.id), csvCell(it.cat), csvCell(it.name),
        csvCode(it.hs.join(', ')), csvCell(it.hsChk.join(', ')),
        csvCell(it.proc.join(', ')),
        csvCell([...new Set(it.goods.map(g=>g.n))].join(', ')),
        csvCell(it.parts.join(', ')),
        csvCell([...it.grades, ...it.method].join(', ')),
        csvCell(it.upcN.join(', '))
      ].join(','));
    });
  });
  // ﻿ = BOM. 눈에 보이지 않는 문자를 그대로 적으면 편집 중 조용히 사라지므로 이스케이프로 씀
  const blob = new Blob(['\ufeff' + lines.join('\r\n')], {type:'text/csv;charset=utf-8;'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `제주수창_취급품목_${hits.length}종_${META.updated}.csv`;
  document.body.appendChild(a); a.click();
  document.body.removeChild(a); setTimeout(()=>URL.revokeObjectURL(a.href), 1000);
}
$('#dl-xls').addEventListener('click', downloadCsv);

// 분류 머리말이 조작부 아래에 붙도록 높이 반영
function stick(){ document.documentElement.style.setProperty('--stick', document.getElementById('controls').offsetHeight+'px'); }
window.addEventListener('resize', stick); stick();

render();
</script>
'@

$logoTag = if ($logoUri) { "<img class=""logo"" src=""$logoUri"" alt=""(주)수창 로고"">" } else { '' }
$html = $tpl.Replace('/*__DATA__*/', $json).Replace('/*__META__*/', $metaJson).Replace('__TOTAL__', [string]$items.Count).Replace('__LOGO__', $logoTag).Replace('__PDF__', [uri]::EscapeDataString($PdfUrl))
Set-Content -LiteralPath $Out -Value $html -Encoding utf8BOM

# --- 정합성 검사 ---
$err = @()
if ($html -match '/\*__DATA__\*/' -or $html -match '/\*__META__\*/') { $err += "데이터 치환이 안 됨" }
if ($html -match '__LOGO__') { $err += "로고 자리표시자가 남음" }
if ($html -match '__PDF__')  { $err += "PDF 자리표시자가 남음" }
# HS가 조용히 빠지지 않게 — 입력 CSV에 코드가 있는 원물 수와 화면에 실린 수가 같아야 함
$입력HS = @($mat | Where-Object { $_.'HS코드' }).Count
$화면HS = @($items | Where-Object { $_.hs.Count }).Count
if ($입력HS -ne $화면HS) { $err += "HS 표시 수 불일치: 입력 $입력HS vs 화면 $화면HS" }
if ($입력HS -eq 0) { $err += "HS가 하나도 없음 — build_카탈로그.ps1이 HS 미러를 못 읽었는지 확인할 것" }
if (-not $logoUri) { $err += "로고 파일 없음: $LogoFile — prep_로고.ps1을 먼저 실행할 것" }
if ($items.Count -ne $기대종수) { $err += "항목 수 이상: $($items.Count) (기대 $기대종수)" }
$빈이름 = $items | Where-Object { -not $_.name }
if ($빈이름.Count -gt 0) { $err += "원물명 공백 $($빈이름.Count)건" }
$상품합 = ($items | ForEach-Object { $_.goods.Count } | Measure-Object -Sum).Sum
if ($상품합 -ne $prod.Count) { $err += "상품 수 불일치: $상품합 vs $($prod.Count)" }
$썸네일수 = @(Get-ChildItem -LiteralPath $PhotoDir -Filter *.jpg -ErrorAction SilentlyContinue).Count
if ($photoCount -ne $썸네일수) { $err += "사진 임베드 수 불일치: 임베드 $photoCount vs 썸네일 파일 $썸네일수 (카탈로그에 없는 ID의 썸네일 존재?)" }
# 업사이클 표시가 조용히 빠지지 않게 — 입력 CSV의 표시 수와 화면에 실린 수가 같아야 한다
$입력업사이클 = @($prod | Where-Object { $_.'업사이클' -eq 'Y' }).Count
$화면업사이클 = ($items | ForEach-Object { @($_.goods | Where-Object { $_.u }).Count } | Measure-Object -Sum).Sum
if ($입력업사이클 -ne $화면업사이클) { $err += "업사이클 표시 수 불일치: 입력 $입력업사이클 vs 화면 $화면업사이클" }
if ($err.Count -gt 0) {
  Remove-Item -LiteralPath $Out -ErrorAction SilentlyContinue
  Write-Host "[검사 실패 — 파일 삭제함]" -ForegroundColor Red
  $err | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  throw "검사 실패로 중단함."
}

Write-Host "[통과] 웹 카탈로그 생성 완료" -ForegroundColor Green
Write-Host "  경로   : $Out ($([Math]::Round((Get-Item $Out).Length/1KB)) KB)"
Write-Host "  수록   : 원물 $($items.Count)종 / 상품 $($meta.goods)개(가공형태별 줄 $상품합) / 사진 $photoCount 종 / HS $화면HS 종"
Write-Host "  근거   : 검사 11항목(치환·로고·PDF링크·항목수·이름공백·상품수·사진수·업사이클수·HS수) 통과"
Write-Host "  단추   : 엑셀(화면에 보이는 목록을 CSV로) · PDF($PdfUrl)"
