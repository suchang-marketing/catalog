# 취급품목 카탈로그 생성 (A1)
#
# 입력: 원물마스터_미러.csv  (build_원물마스터.ps1이 만든 것 — 이것만 입력으로 쓴다)
# 출력: 카탈로그_원물단위.csv (원물 1행, 발송용 통 카탈로그의 원본)
#       카탈로그_상품단위.csv (317행, 내부 작업본)
#
# [스펙 근거] 관제탑 §6 — 전 원물 1장 통 카탈로그, 2단 구조(원물 → 하위 상품). 종수는 미러 기준(하드코딩 금지)
#   컬럼 요구는 원물명·분류·가공형태·규격/포장단위였으나
#   ⚠️ 규격·포장은 원본에 데이터가 없어 이번 판에서 제외함(빈 칸으로 내면 신뢰를 잃음).
#      B2 작업으로 채워지면 이 스크립트만 다시 돌리면 반영됨.
#   제외 확정 항목(관제탑): 단가 · 산지 · 사진
#   ★ HS코드는 제외였다가 08-04 수록으로 바뀜(사용자 요청). 아래 [HS] 절 참조.
#
# [정렬] 분류(농산물→해조류→약재) 안에서 **원물명 가나다 순**(08-04 사용자 요청).
#   이전에는 Material ID 순이었는데, ID는 등록 순서라 사람이 이름으로 찾을 때 순서가 없어 보였음.
#   이 CSV의 행 순서가 곧 웹·docx·PDF의 표시 순서라, 여기만 바꾸면 산출물 전부가 따라감.
#
# ⚠️ 변수명 주의: PowerShell은 변수명 대소문자를 구분하지 않는다. param의 [string]$Out과
#    같은 이름을 배열에 쓰면 타입 제약 때문에 조용히 문자열로 바뀐다(실제로 겪음).

param(
  [string]$Src      = "$PSScriptRoot\원물마스터_미러.csv",
  [string]$SrcHS    = "$PSScriptRoot\_source\drive\HS.csv",                       # 구글시트 「HS코드_자동화」 탭 HS CODE_KEYWORD (sync_마스터.ps1이 받음)
  [string]$SrcHSChk = "$PSScriptRoot\HS참조\골든_HS_20260730_공식교차검증.csv",
  [string]$OutMat   = "$PSScriptRoot\카탈로그_원물단위.csv",
  [string]$OutProd  = "$PSScriptRoot\카탈로그_상품단위.csv"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Src)) { throw "미러가 없음: $Src — build_원물마스터.ps1을 먼저 실행할 것." }

$m = Import-Csv -LiteralPath $Src -Encoding UTF8

# --- [HS] 상품별 HS코드 6단위 ---------------------------------------------
# 원천은 Drive 시트 `HS코드_자동화`(관제탑 §3의 단일 진실 원천) 탭 HS CODE_KEYWORD — 새 원물마스터의 상품(PID)과 1:1이다.
# 여기서는 그 미러(_source\drive\HS.csv)를 읽기만 한다. 한 상품이 가공형태별로 코드가 갈리면 HS코드를 비우고
# 비고에 「가공형태별 코드 상이」를 적어 둔다 — 이런 상품은 코드를 싣지 않고 화면에 「HS 확인 중」으로 표기한다.
#
# ★ 대외 발행물에 실존하지 않는 세번을 실으면 바이어가 조회하는 순간 신뢰를 잃는다.
#   그래서 공식 교차검증(미국 HTS·관세청 2개 소스) 결과에서 **코드무효 플래그가 붙은 품목은
#   코드를 싣지 않고 빈 칸으로 둔다.** 빈 칸이 틀린 코드보다 낫다.
#   무효 플래그는 07-30 공식 교차검증 결과(HS참조\골든_…csv, 옛 PID 기준)이며 새 시트에 남은 PID에만 걸린다 — 관제탑 7-E에서 정정 대기 중.
#   정정되어 미러가 갱신되면 이 스크립트만 다시 돌리면 자동으로 실린다(여기 손댈 것 없음).
# --- HS 정정 사전 (08-04) ---------------------------------------------------
# 원천(Drive 시트)에 무효 코드가 남아 있는 동안만 쓰는 임시 사전이다.
# $원물표시명 사전과 같은 성격 — **시트가 정정되면 해당 줄을 지운다**(값이 같아지므로 결과 불변).
# 여기 있는 건은 전부 HS 개정으로 상위 코드가 하위로 갈린 것이며(10-12 원물마스터 재편으로 PID가 합쳐져 4건만 남음),
# 미국 HTS(hts.usitc.gov)와 관세청 HS부호 양쪽에서 정정 코드의 실존을 확인했다(08-04).
#
#   1003.00 → 1003.90   보리. 1003.10은 **파종용 종자**라 식용은 기타(1003.90)임.
#   1004.00 → 1004.90   귀리. 위와 같은 이유.
#                       ⚠️ 마스터 사용부위가 "씨앗(종자)"인 것은 식물학적 부위 표기이지
#                          파종용이라는 뜻이 아니다. 여기서 1003.10/1004.10을 쓰면 오분류.
#   2009.80 → 2009.89   HS2017에서 2009.81(크랜베리)/2009.89(기타)로 갈림. 둘 다 크랜베리 아님.
#                       ⚠️ 양파농축액은 원래 "3자 갈림 → 관세사 필수" 건이다. 추출물로 보면
#                          제1302호·제2106호가 될 수 있어 6단위 자체가 미확정임(관세사 확정 필요).
#   0805.19 → 품목마다 다름. HS2017에서 0805.19가 없어지고 감귤류가 다시 갈렸다.
#       · 진귤 껍질    → 0814.00  회사 관례와 일치(진피·청귤껍질·천혜향껍질 전부 0814.00)
#       · 진귤 과육분말 → 0813.40  회사 관례와 일치(감귤칩·감귤알맹이·딸기분말이 0813.40)
#       · 풋진귤(신선) → 0805.21  진귤은 재래 만다린. 관세청 품명도 "감귤"
$HS정정 = @{
  'P-M010-01' = '1004.90'   # 귀리
  'P-M034-01' = '1003.90'   # 보리
  'P-M038-01' = '0813.40'   # 산물귤 (건조 분말, 과육)
  'P-M038-02' = '0814.00'   # 산물귤껍질
}

$hsByProd = @{}   # Product ID -> HS코드(유효한 것만)
$무효Prod = @{}   # Product ID -> 공식소스에 없는 코드라 싣지 않은 것
$HS갈림Prod = @{} # Product ID -> 가공형태별로 코드가 달라 시트에서 일부러 비운 것(비고 「가공형태별 코드 상이」)
$hs무효 = 0; $hs총 = 0; $hs정정수 = 0
if (Test-Path -LiteralPath $SrcHS) {
  if (Test-Path -LiteralPath $SrcHSChk) {
    Import-Csv -LiteralPath $SrcHSChk -Encoding UTF8 |
      Where-Object { $_.'공식플래그' -match '코드무효' } |
      ForEach-Object { $무효Prod[$_.'Product ID'] = $true }
  } else {
    Write-Host "  주의: 공식 교차검증 파일이 없어 무효코드를 거르지 못함 — $SrcHSChk" -ForegroundColor Yellow
  }
  foreach ($r in (Import-Csv -LiteralPath $SrcHS -Encoding UTF8)) {
    $code = ([string]$r.'HS코드(확정)').Trim()
    if (-not $code) {
      if (([string]$r.'변경/비고') -match '가공형태별 코드 상이') { $HS갈림Prod[$r.'Product ID'] = $true }
      continue
    }
    $hs총++
    # 정정 사전이 무효 플래그보다 우선한다 — 정정된 코드는 이미 공식소스로 실존을 확인했다.
    if ($HS정정.ContainsKey($r.'Product ID')) {
      $hsByProd[$r.'Product ID'] = $HS정정[$r.'Product ID']; $hs정정수++; continue
    }
    if ($무효Prod[$r.'Product ID']) { $hs무효++; continue }
    $hsByProd[$r.'Product ID'] = $code
  }
  # 정정 사전에 적었는데 그 Product ID가 미러에 없으면 조용히 무시된다 — 오타를 잡는다.
  $정정미적용 = @($HS정정.Keys | Where-Object { -not $hsByProd.ContainsKey($_) })
  if ($정정미적용) { throw "HS 정정 사전의 Product ID가 미러에 없음: $($정정미적용 -join ', ') — 오타이거나 상품이 없어진 것임" }
} else {
  Write-Host "  주의: HS 미러가 없어 HS 칸이 비게 됨 — $SrcHS" -ForegroundColor Yellow
}
# 한 원물에 상품이 여럿이면 HS도 여럿일 수 있다(예: 비트 원물 0712.90 / 비트즙 2009.xx).
# 원물 단위 칸에는 중복을 없애고 코드순으로 나열한다.
function Get-원물HS { param($group) (@($group | ForEach-Object { $hsByProd[$_.'Product ID'] } |
    Where-Object { $_ } | Select-Object -Unique | Sort-Object) -join ', ') }

# ★ 묶을 때 생기는 오인을 막는 칸(08-04).
#   보리 원물은 상품이 둘(보리 1003.00·새싹보리 1211.90)인데 본품 코드가 무효라 빠지면
#   칸에 1211.90만 남아 **보리 자체가 약용식물 세번인 것처럼** 읽힌다.
#   그래서 코드를 못 실은 품목의 **이름을 따로 남긴다** — 화면·문서에서 "확인 중"으로 표기한다.
#   정정 사전으로 코드를 되찾은 품목은 여기서 빠진다(무효 플래그는 원천 기준으로 남아 있으므로).
function Get-HS확인중 { param($group) (@($group | Where-Object { ($무효Prod[$_.'Product ID'] -or $HS갈림Prod[$_.'Product ID']) -and -not $HS정정.ContainsKey($_.'Product ID') } |
    ForEach-Object { Get-표시상품명 $_.'Product ID' $_.'상품(원료)명' $_.'Material ID' $_.'원물명' } |
    Select-Object -Unique) -join ', ') }
$분류순 = @{ '농산물' = 1; '해조류' = 2; '약재' = 3 }   # 회사소개서 기준 순서
$가공순 = @{ '원물' = 1; '전처리/냉동' = 2; '건조' = 3; '액상/추출' = 4; '가공/기타' = 5 }  # 가공 단계 순

# --- 대외 표기 사전 (사용자 확정 07-31) ---
# 마스터 값은 그대로 두고 **발송물에 나갈 이름만** 여기서 바꾼다.
# 마스터를 고치지 않는 이유: 원천은 Drive 시트이고 미러는 원천과 대조돼야 하기 때문.
#   → 원천 시트가 정리되면 해당 줄을 지우면 된다(값이 같아지므로 결과는 안 바뀜).
$원물표시명 = @{
  'M215' = '하귤(나스미깡)'   # 원본 '하귤（나스）' — 전각 괄호 + 약칭. 정식 품종명으로 폄
}
# 상품명은 Product ID 기준으로 바꾼다(원물명이 옆 칸에 있으므로 품명을 반복하지 않는다).
$상품표시명 = @{
  # 메밀·쓴메밀의 「봄 수확/가을 수확」 표시는 옛 마스터가 봄·가을을 두 줄로 나눠 적던 때의 것이었다.
  # 새 원물마스터(10-12)는 메밀·쓴메밀을 연중 한 줄로 두므로 지웠다 — 남기면 한 줄짜리가 「봄 수확」으로 잘못 나온다.
  # 상품 이름을 따로 바꿔야 할 일이 생기면 여기에 'P-M000-00' = '표시 이름' 형태로 적는다.
}

# 업사이클 보완 목록 — 지금은 비어 있다(07-31).
# 잠깐 감귤박 등 4건을 여기 넣었었는데, 시트를 직접 받아 보니 감귤박은 시트 비고에 이미
# "업사이클"로 있었고 나머지 3건(청귤박·당근박·레몬박)은 없었다. 로컬 사본이 낡아서 안 보였을 뿐이다.
# **표시 여부는 시트에서 정한다** — 여기에 손으로 적으면 시트와 어긋나고, 시트를 고쳐도 안 지워진다.
# 시트에서 도저히 손댈 수 없는 예외가 생겼을 때만 쓰고, 왜 넣었는지 함께 적을 것.
$업사이클보완 = @()

# ⚠️ 함정: $pid는 PowerShell 예약 변수(현재 프로세스 ID)라 param 이름으로 쓰면 실행이 막힌다.
function Get-표시원물명 { param($MatId, $name) if ($원물표시명.ContainsKey($MatId)) { $원물표시명[$MatId] } else { $name } }
# 상품명이 원물명과 같은 경우(다수)는 원물명 정정을 자동으로 따라가게 한다.
# 안 그러면 같은 정정을 두 사전에 두 번 적어야 하고, 한쪽만 고치면 이름이 어긋난다.
function Get-표시상품명 {
  param($ProdId, $name, $MatId, $원본원물명)
  if ($상품표시명.ContainsKey($ProdId)) { return $상품표시명[$ProdId] }
  if ($원본원물명 -and $name -eq $원본원물명) { return (Get-표시원물명 $MatId $name) }
  $name
}

# --- 원물 단위 (발송용): 한 원물의 하위 상품을 한 칸에 묶는다 ---
$원물 = $m | Group-Object 'Material ID' | ForEach-Object {
  $g    = $_.Group
  $첫행 = $g[0]

  # 가공형태: 원본 한 칸에 "건조, 전처리/냉동"처럼 여러 값이 들어 있으므로
  # 먼저 쉼표로 쪼갠 뒤 중복을 제거한다. 안 그러면 "건조, 건조, 전처리/냉동"이 나온다.
  # 순서도 고정한다. "건조, 전처리/냉동"과 "전처리/냉동, 건조"가 따로 잡히면
  # 발송 문서에서 같은 조합이 다르게 보인다. 가공 단계 순서로 정렬한다.
  $가공 = ($g.'가공형태(대분류)' | Where-Object { $_ } |
           ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } |
           Where-Object { $_ } | Select-Object -Unique |
           Sort-Object @{E={ $가공순[$_] ?? 99 }}) -join ', '

  # 하위 상품: 있는 대로 나열한다(원물명과 같아도 비우지 않는다).
  # ⚠️ 함정(07-31 실측): "이름이 원물명과 같은 상품 하나뿐이면 생략" 규칙을 쓰면
  #    1글자 원물(쑥·패·톳·칡)만 빈 칸이 됐다. PowerShell은 문자열에 [0]을 쓰면 배열
  #    첫 원소가 아니라 **첫 글자**를 돌려주기 때문이다("콜라비"[0]='콜' → 불일치라 생략 안 됨).
  #    07-21 "1글자 원물이 조용히 빠지던" 사고와 같은 유형. 발송물에서 빈 칸은
  #    "취급 안 함"으로 읽히므로 생략 규칙 자체를 없앤다.
  $상품들 = @($g | Where-Object { $_.'상품(원료)명' } |
              ForEach-Object { Get-표시상품명 $_.'Product ID' $_.'상품(원료)명' $_.'Material ID' $_.'원물명' } |
              Select-Object -Unique)
  $하위 = $상품들 -join ', '

  # 인증과 생산방식을 나눈다.
  #  · 인증 = 유기농·친환경 (정부 인증. 없는 것을 있다고 쓰면 위법)
  #  · 생산방식 = 자연산·양식 (인증이 아니라 채취·양식 구분)
  # 둘을 '인증' 한 칸에 섞으면 자연산 원물이 인증받은 것으로 읽힘.
  # 인증품만 올리면 원물 전체가 인증품으로 읽히므로, 등급은 있는 대로 나열한다("일반, 친환경").
  # 같은 품목이 인증품·일반품 두 줄로 등록된 원물이 있음(귤 진피, 청귤 껍질, 당근, 산물귤, 생강).
  $인증값 = @('유기농','친환경','무농약')
  $방식값 = @('자연산','양식')

  # ★ 회사 사실(사용자 확인 07-31): **일반 등급이 디폴트임** — 거의 모든 원물이 일반으로 공급됨.
  #   인증품은 그 위에 얹히는 것이므로, 인증이 있는 원물은 항상 "일반, 인증명"으로 적는다.
  #   마스터에 인증품 행만 등록된 원물(예: 석창포)도 일반 공급이 되므로 인증명만 적으면 과대표기임.
  #   "인증품만 취급"하는 원물이 생기면 아래 예외 목록에 등록할 것(현재 없음).
  $인증전용 = @()   # 예: 'M999'
  $인증명 = @($g.'인증/등급' | Where-Object { $_ -in $인증값 } | Select-Object -Unique | Sort-Object)
  $인증 = if (-not $인증명) { '' }
          elseif ($첫행.'Material ID' -in $인증전용) { $인증명 -join ', ' }
          else { (@('일반') + $인증명) -join ', ' }

  # 업사이클(ESG) — 원물 전체가 아니라 **해당 품목**이 업사이클이므로 품목명을 그대로 적는다
  # (인증 때와 같은 과대표기를 만들지 않기 위함).
  # 출처 둘: ①마스터 '비고'에 "업사이클"이라 적힌 품목 ②아래 보완 목록($업사이클보완).
  #   보완 목록은 착즙하고 남은 박처럼 성격이 분명한데 비고가 비어 있던 품목임(사용자 확인 07-31).
  #   → **원천 Drive 시트 비고에도 넣어야 함.** 시트에 채워지면 아래 줄을 지우면 됨(결과 불변).
  $업사이클품목 = @($g | Where-Object { $_.'비고'.Trim() -eq '업사이클' -or $_.'Product ID' -in $업사이클보완 } |
                    ForEach-Object { Get-표시상품명 $_.'Product ID' $_.'상품(원료)명' $_.'Material ID' $_.'원물명' } |
                    Select-Object -Unique)
  $업사이클 = $업사이클품목 -join ', '

  $방식상품 = @($g | Where-Object { $_.'인증/등급' -in $방식값 })
  $방식명   = @($방식상품.'인증/등급' | Select-Object -Unique | Sort-Object)
  $생산방식 = if (-not $방식명) { '' }
              elseif ($방식상품.Count -eq $g.Count) { $방식명 -join ', ' }
              else { ($방식명 -join ', ') + '(일부 품목)' }

  [pscustomobject][ordered]@{
    'Material ID' = $첫행.'Material ID'
    '분류'        = $첫행.'분류'
    '원물명'      = (Get-표시원물명 $첫행.'Material ID' $첫행.'원물명')
    '가공형태'    = $가공
    '취급 품목'   = $하위
    '사용부위'    = ($g.'사용부위' | Where-Object { $_ } | Select-Object -Unique) -join ', '
    'HS코드'      = (Get-원물HS $g)
    'HS확인중'    = (Get-HS확인중 $g)
    '인증'        = $인증
    '생산방식'    = $생산방식
    '업사이클'    = $업사이클
    '규격'        = ''        # B2 대기
    '포장단위'    = ''        # B2 대기
  }
} | Sort-Object @{E={$분류순[$_.'분류']}}, '원물명'

# --- 상품 단위 (내부 작업본) ---
# 웹 카탈로그·docx가 이 파일의 이름을 그대로 화면에 쓰므로 표시 사전을 여기에도 적용한다
# (원물 단위에만 적용하면 접힌 줄과 펼친 상세의 이름이 서로 달라진다).
$상품 = $m | ForEach-Object {
  [pscustomobject][ordered]@{
    'Material ID'      = $_.'Material ID'
    '분류'             = $_.'분류'
    '원물명'           = (Get-표시원물명 $_.'Material ID' $_.'원물명')
    'Product ID'       = $_.'Product ID'
    '상품(원료)명'     = (Get-표시상품명 $_.'Product ID' $_.'상품(원료)명' $_.'Material ID' $_.'원물명')
    '가공형태(대분류)' = $_.'가공형태(대분류)'
    '가공형태(소분류)' = $_.'가공형태(소분류)'
    '사용부위'         = $_.'사용부위'
    'HS코드'           = ([string]$hsByProd[$_.'Product ID'])
    '인증/등급'        = $_.'인증/등급'
    '업사이클'         = $(if ($_.'비고'.Trim() -eq '업사이클' -or $_.'Product ID' -in $업사이클보완) { 'Y' } else { '' })
    '규격'             = $_.'규격'
    '포장단위'         = $_.'포장단위'
  }
} | Sort-Object @{E={$분류순[$_.'분류']}}, '원물명', 'Product ID'

# --- 정합성 검사: 통과 못 하면 저장하지 않는다 ---
$err = @()
# 기대 종수 = 입력(미러)의 고유 Material ID 수 — 마스터가 늘어도 숫자 하드코딩 없이 따라감
$기대종수 = @($m.'Material ID' | Where-Object { $_ } | Sort-Object -Unique).Count
if ($원물.Count -ne $기대종수) { $err += "원물 행수($($원물.Count))가 미러 고유 ID 수($기대종수)와 다름" }
if ($상품.Count -ne $m.Count) { $err += "상품 행수 불일치: $($상품.Count) vs 입력 $($m.Count)" }
$빈가공 = $원물 | Where-Object { -not $_.'가공형태' }
if ($빈가공.Count -gt 0) { $err += "가공형태 공백 $($빈가공.Count)건: " + (($빈가공 | Select-Object -First 5).'원물명' -join ', ') }
# 취급 품목 공백 방어 — 발송물에서 빈 칸은 "취급 안 함"으로 읽힌다(1글자 원물 함정 재발 차단)
$빈품목 = $원물 | Where-Object { -not $_.'취급 품목' }
if ($빈품목.Count -gt 0) { $err += "취급 품목 공백 $($빈품목.Count)건: " + (($빈품목 | Select-Object -First 5).'원물명' -join ', ') }
# 전각문자(일본식 괄호 등) 방어 — 발송물에 남으면 글꼴이 어긋나 보인다. 새로 생기면 표시 사전에 등록할 것
$전각 = @($원물 | Where-Object { $_.'원물명' -match '[＀-￯]' -or $_.'취급 품목' -match '[＀-￯]' }).Count +
        @($상품 | Where-Object { $_.'상품(원료)명' -match '[＀-￯]' -or $_.'원물명' -match '[＀-￯]' }).Count
if ($전각 -gt 0) { $err += "전각문자 잔존 $($전각)건 — 표시 사전(`$원물표시명/`$상품표시명)에 등록할 것" }
# 업사이클 표시가 조용히 빠지지 않게 — 마스터의 표시 수와 산출물의 표시 수가 같아야 한다
$마스터업사이클 = @($m | Where-Object { $_.'비고'.Trim() -eq '업사이클' -or $_.'Product ID' -in $업사이클보완 }).Count
$산출업사이클   = @($상품 | Where-Object { $_.'업사이클' -eq 'Y' }).Count
if ($마스터업사이클 -ne $산출업사이클) { $err += "업사이클 표시 수 불일치: 마스터 $마스터업사이클 vs 산출 $산출업사이클" }
$미분류 = $원물 | Where-Object { $_.'분류' -notin @('농산물','해조류','약재','수입 원료') }
if ($미분류.Count -gt 0) { $err += "분류 이상 $($미분류.Count)건" }
$중복원물 = $원물 | Group-Object 'Material ID' | Where-Object { $_.Count -gt 1 }
if ($중복원물.Count -gt 0) { $err += "Material ID 중복 $($중복원물.Count)건" }
# 인증 과대표기 방어 ①인증이 있으면 기본 등급 '일반'이 함께 적혀 있어야 한다(일반이 디폴트)
#                    ②인증 칸에 인증이 아닌 값(자연산·양식)이 섞이면 안 된다
foreach ($row in $원물) {
  if ($row.'인증') {
    if ($row.'인증' -notmatch '일반' -and $row.'Material ID' -notin @()) {
      $err += "인증 과대표기: $($row.'원물명')($($row.'Material ID')) — 일반이 기본 등급인데 인증 칸에 '일반'이 없음(인증품만 취급하는 원물이면 `$인증전용에 등록할 것)"
    }
    if ($row.'인증' -match '자연산|양식') { $err += "인증 칸 오염: $($row.'원물명') — 자연산·양식은 인증이 아니라 생산방식임" }
  }
  # 생산방식이 일부 품목만인 경우는 사람이 확인해야 함(현재 0건 — 생기면 표기 방침 결정 필요)
  if ($row.'생산방식' -match '일부 품목') { $err += "생산방식 부분 표기 발생: $($row.'원물명') — 표기 방침 확인 필요(사람 판단)" }
}
# 마스터에 새 등급값이 생기면 분류 규칙을 갱신해야 함 — 조용히 빠지는 것을 막는다
$미분류등급 = @($m.'인증/등급' | Where-Object { $_ -and $_ -ne '일반' } | Sort-Object -Unique |
               Where-Object { $_ -notin @('유기농','친환경','무농약','자연산','양식') })
if ($미분류등급.Count -gt 0) { $err += "미분류 등급값 $($미분류등급.Count)종: $($미분류등급 -join ', ') — 인증인지 생산방식인지 규칙에 추가할 것" }
# HS 빈 칸은 두 가지 이유로 생긴다. 둘을 구분해야 한다.
#  ①무효코드·가공형태별 상이라 일부러 뺀 것(정상)  ②미러에 애초에 없는 것(데이터 누락 — 고쳐야 함)
# ②는 조용히 빈 칸으로 나가면 "HS가 없는 품목"으로 오인되므로 오류로 세운다.
$hs누락 = @($m | Where-Object { -not $hsByProd.ContainsKey($_.'Product ID') -and -not $무효Prod[$_.'Product ID'] -and -not $HS갈림Prod[$_.'Product ID'] -and $_.'Material ID' -notmatch '^I' })
if ($hs누락.Count -gt 0) {
  $err += "HS 미러에 없는 품목 $($hs누락.Count)건: " + (($hs누락 | Select-Object -First 5).'Product ID' -join ', ') +
          " — Drive 시트 `HS코드_자동화`에 채우고 미러를 다시 받을 것"
}
# 원물 단위로 묶은 뒤에도 원래 상품 수가 보존돼야 한다
$합 = ($m | Group-Object 'Material ID').Count
if ($합 -ne $원물.Count) { $err += "묶기 전후 원물 수 불일치: $합 vs $($원물.Count)" }

if ($err.Count -gt 0) {
  Write-Host "`n[정합성 검사 실패 — 저장하지 않음]" -ForegroundColor Red
  $err | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  throw "검사 실패로 중단함."
}

$원물 | Export-Csv -LiteralPath $OutMat  -NoTypeInformation -Encoding utf8BOM
$상품 | Export-Csv -LiteralPath $OutProd -NoTypeInformation -Encoding utf8BOM

Write-Host "[통과] 카탈로그 생성 완료" -ForegroundColor Green
Write-Host "  발송용(원물 단위) : $OutMat  — $($원물.Count)행"
Write-Host "  작업본(상품 단위) : $OutProd — $($상품.Count)행"
Write-Host "  근거 : 정합성 13항목(원물수·상품수·가공형태공백·취급품목공백·전각문자·업사이클수·분류이상·ID중복·묶기전후·인증과대표기·인증칸오염·미분류등급·HS누락) 전부 통과"
Write-Host "`n[분류별]  (분류 안 정렬: 원물명 가나다 순)"
$원물 | Group-Object '분류' | Sort-Object @{E={$분류순[$_.Name]}} |
  ForEach-Object { "  {0,-6} {1,3}종" -f $_.Name, $_.Count }

$hs있음 = @($원물 | Where-Object { $_.'HS코드' }).Count
Write-Host "`n[HS코드] 수록 $hs있음 / $($원물.Count)종  (상품 기준 $($hsByProd.Count) / $hs총 건)"
if ($hs정정수 -gt 0) {
  Write-Host "  · 정정 사전 적용 $($hs정정수)건 — 원천 시트가 정정되면 `$HS정정 사전을 지울 것" -ForegroundColor Cyan
}
if ($HS갈림Prod.Count -gt 0) {
  Write-Host "  · 가공형태별로 코드가 달라 비워 둔 상품 $($HS갈림Prod.Count)개 — 화면에는 「HS 확인 중」으로 표기" -ForegroundColor Cyan
}
if ($hs무효 -gt 0) {
  Write-Host "  ※ 공식소스(미국 HTS·관세청)에 없는 코드 $($hs무효)건은 싣지 않고 빈 칸으로 둠 — 관제탑 7-E 정정 대기" -ForegroundColor Yellow
  $빈칸원물 = @($원물 | Where-Object { -not $_.'HS코드' } | ForEach-Object { $_.'원물명' })
  if ($빈칸원물) { Write-Host "     빈 칸 원물: $($빈칸원물 -join ', ')" -ForegroundColor Yellow }
}
Write-Host "`n  ※ 규격·포장단위는 빈 칸임(원본에 데이터 없음). 채워지면 이 스크립트만 다시 돌리면 됨."
