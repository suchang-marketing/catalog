# 원물마스터 미러 생성 — 새 「원물마스터_최종」 연결판 (2026-10-12)
#
# 무엇: 구글시트 「원물마스터_최종」의 품목 탭(상품 1줄 = 1행)을 읽어, 카탈로그 스크립트가
#       쓰는 미러(상품 단위 13열)로 바꿔 쓴다. 이 미러 뒤의 build_카탈로그·웹·워드는 그대로 돈다.
#
# [원본 = 단일 진실 원천]
#   구글시트 「원물마스터_최종」 탭 「품목」(1행 머리글, 열: PID·MID·게시상태·카테고리·사용부위·
#   생산방식·…·품목명·원물명·…·공급형태). sync_마스터.ps1이 CSV로 받아 _source\drive\품목.csv에 둔다.
#   (옛 「원료master_최종_현행」은 더 이상 쓰지 않음)
#
# [옛 구조로 바꾸는 규칙 — 새 마스터에는 없는 칸을 카탈로그가 요구하기 때문]
#   · 게시상태가 「게시」이고 PID가 P-M으로 시작하는 상품만 싣는다(도입검토·비공개·수입 원료는 제외).
#   · 가공형태(소분류) = 공급형태 원문(예: 원물, 분말).
#   · 가공형태(대분류) = 공급형태를 가공 단계로 묶은 값: 원물→원물 / 분말·파쇄·분쇄·세절·슬라이스·칩→건조 /
#     착즙액·농축액·추출물(액상)·오일→액상/추출. 새 공급형태 값이 생기면 일부러 멈춘다(조용히 빠지지 않게).
#   · 인증/등급 = 생산방식을 쉼표로 쪼갠 값(업사이클링 제외). 값이 둘 이상이면 같은 상품을 값마다 한 행씩 둔다
#     (옛 마스터가 인증품·일반품을 두 줄로 등록하던 구조와 같다 — 카탈로그는 Material ID 기준이라 PID 중복은 무해).
#   · 비고 = 생산방식에 「업사이클링」이 있으면 「업사이클」.
#   · 규격·포장단위·품종/시기는 새 마스터에 없거나 임시값이라 빈 칸.
#
# [함정] 한글 CSV는 utf8BOM으로 저장해야 Excel에서 안 깨진다. 변수명 $Out과 같은 이름으로 배열을 만들지 말 것
#        (PowerShell은 대소문자를 구분하지 않아 문자열로 바뀐다).

param(
  [string]$Src = "$PSScriptRoot\_source\drive\품목.csv",
  [string]$Out = "$PSScriptRoot\원물마스터_미러.csv"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Src)) {
  throw "품목 CSV를 찾을 수 없음: $Src`n   sync_마스터.ps1로 받거나, 구글시트 「원물마스터_최종」의 「품목」 탭을 CSV로 내려받아 이 경로에 두고 다시 실행할 것."
}

$all = @(Import-Csv -LiteralPath $Src -Encoding UTF8)
if ($all.Count -eq 0) { throw "데이터가 0행임. 품목 탭 형식이 바뀌었는지 확인할 것." }
foreach ($필수 in 'PID','MID','게시상태','카테고리','사용부위','생산방식','품목명','원물명','공급형태') {
  if (-not ($all[0].PSObject.Properties.Name -contains $필수)) { throw "품목 탭에 '$필수' 열이 없음 — 시트 구조가 바뀌었는지 확인할 것." }
}

# 도입검토·비공개·수입 원료는 카탈로그에 싣지 않는다(대외 문서이므로 게시된 것만).
# 10-19: 홈페이지와 같게 도입검토 상태의 수입 원료(P-I…)도 싣는다(분류 「수입 원료」).
$rows = @($all | Where-Object { $_.'PID' -match '^P-[MI]\d' -and "$($_.'게시상태')".Trim() -in @('게시','도입검토') })
$제외 = $all.Count - $rows.Count

$가공단계 = @{
  '원물' = '원물'
  '건조' = '건조'; '동결건조' = '건조'
  '분말' = '건조'; '파쇄' = '건조'; '분쇄' = '건조'; '세절' = '건조'; '슬라이스·칩' = '건조'
  '착즙액' = '액상/추출'; '농축액' = '액상/추출'; '추출물(액상)' = '액상/추출'; '오일' = '액상/추출'
}
$가공순 = @{ '원물' = 1; '건조' = 2; '액상/추출' = 3 }
$등급값 = @('일반','친환경','유기농','무농약','자연산','양식')

function Get-가공대분류 {
  param([string]$공급형태, [string]$pid2)
  $토큰 = @($공급형태 -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if (-not $토큰) { throw "공급형태가 비어 있음: $pid2" }
  $단계 = foreach ($t in $토큰) {
    if (-not $가공단계.ContainsKey($t)) { throw "새 공급형태 값 '$t'($pid2) — 가공 대분류 규칙(`$가공단계)에 추가할 것" }
    $가공단계[$t]
  }
  ($단계 | Select-Object -Unique | Sort-Object @{E={ $가공순[$_] }}) -join ', '
}

$mirror = foreach ($r in $rows) {
  $pid2 = $r.'PID'.Trim()
  $값들 = @($r.'생산방식' -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $업사이클 = ($값들 -contains '업사이클링')
  $등급들 = @($값들 | Where-Object { $_ -ne '업사이클링' })
  foreach ($g in $등급들) { if ($g -notin $등급값) { throw "새 생산방식 값 '$g'($pid2) — 인증인지 생산방식인지 규칙에 추가할 것" } }
  if (-not $등급들) { $등급들 = @('일반') }
  foreach ($등급 in $등급들) {
    [pscustomobject][ordered]@{
      'Material ID'      = $r.'MID'.Trim()
      '분류'             = $r.'카테고리'.Trim()
      '원물명'           = $r.'원물명'.Trim()
      'Product ID'       = $pid2
      '상품(원료)명'     = $r.'품목명'.Trim()
      '사용부위'         = $r.'사용부위'.Trim()
      '가공형태(대분류)' = (Get-가공대분류 $r.'공급형태' $pid2)
      '가공형태(소분류)' = $r.'공급형태'.Trim()
      '인증/등급'        = $등급
      '품종/시기'        = ''
      '규격'             = ''
      '포장단위'         = ''
      '비고'             = $(if ($업사이클) { '업사이클' } else { '' })
    }
  }
}

# --- 정합성 검사: 통과 못 하면 저장하지 않는다 ---
$err = @()
$mids = $mirror.'Material ID' | Where-Object { $_ } | Sort-Object -Unique
# 종수는 고정하지 않는다(원물이 늘고 주는 것이 정상). 갑작스러운 급감(사고 신호)만 막는다.
# 10-28: 해조류 61종 등 63개 품목을 일부러 비공개로 돌려 176종이 됨 → 기준을 200에서 150으로 낮춤.
if ($mids.Count -lt 150) { $err += "원물이 $($mids.Count)종뿐임 — 받은 파일이 잘렸는지 확인할 것(10-28 기준 정상은 176종 안팎). 일부러 줄였다면 이 기준을 낮출 것" }
$분류값 = @('농산물','해조류','약재','수입 원료')
$이상분류 = $mirror | Where-Object { $_.'분류' -notin $분류값 }
if ($이상분류.Count -gt 0) { $err += "분류 이상 $($이상분류.Count)건: " + (($이상분류 | Select-Object -First 5).'Material ID' -join ', ') }
$빈원물명 = $mirror | Where-Object { -not $_.'원물명' }
if ($빈원물명.Count -gt 0) { $err += "원물명 공백 $($빈원물명.Count)건" }
$빈상품명 = $mirror | Where-Object { -not $_.'상품(원료)명' }
if ($빈상품명.Count -gt 0) { $err += "품목명 공백 $($빈상품명.Count)건" }
# 같은 PID가 같은 등급으로 두 번 나오면 시트의 PID가 중복된 것
$중복 = $mirror | Group-Object { $_.'Product ID' + '|' + $_.'인증/등급' } | Where-Object { $_.Count -gt 1 }
if ($중복.Count -gt 0) { $err += "Product ID 중복 $($중복.Count)건: " + (($중복 | Select-Object -First 5).Name -join ', ') }
$분류충돌 = $mirror | Group-Object 'Material ID' | Where-Object { ($_.Group.'분류' | Sort-Object -Unique).Count -gt 1 }
if ($분류충돌.Count -gt 0) { $err += "같은 원물에 분류가 두 개: " + (($분류충돌 | Select-Object -First 5).Name -join ', ') }
# 상품 수 보존: 미러의 고유 PID 수 = 게시된 품목 행 수
$고유PID = @($mirror.'Product ID' | Sort-Object -Unique).Count
if ($고유PID -ne $rows.Count) { $err += "상품 수 불일치: 미러 고유 PID $고유PID vs 품목 탭 게시 행 $($rows.Count)" }

if ($err.Count -gt 0) {
  Write-Host "`n[정합성 검사 실패 — 저장하지 않음]" -ForegroundColor Red
  $err | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  throw "검사 실패로 중단함."
}

$mirror | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding utf8BOM

Write-Host "[통과] 미러 생성 완료" -ForegroundColor Green
Write-Host "  경로   : $Out"
Write-Host "  품목   : $($rows.Count)개 게시 (게시 아님·수입 등 제외 $($제외)개)"
Write-Host "  미러행 : $($mirror.Count) (인증·일반을 따로 싣는 상품은 등급마다 한 행)"
Write-Host "  원물수 : $($mids.Count)"
Write-Host "  근거   : 정합성 6항목(원물수·분류·원물명/품목명 공백·PID 중복·분류충돌·상품수 보존) 전부 통과"
Write-Host "`n[분류 분포]"
$mirror | Group-Object '분류' | Sort-Object Count -Descending |
  ForEach-Object { "  {0,-6} 행 {1,3} / 원물 {2,3}종" -f $_.Name, $_.Count, (($_.Group.'Material ID' | Sort-Object -Unique).Count) }
Write-Host "`n  ※ 규격·포장단위는 새 마스터에 없어 빈 칸임."
