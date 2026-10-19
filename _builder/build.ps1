param([string]$SourceDirectory)
$ErrorActionPreference = 'Stop'
[System.Threading.Thread]::CurrentThread.CurrentCulture = 'ko-KR'
$root = Split-Path $PSScriptRoot -Parent
$site = Join-Path $root '_site'
$logs = Join-Path $root '_logs'
$source = Join-Path $PSScriptRoot '_source/drive'
New-Item -ItemType Directory -Force -Path $site,$logs,$source,(Join-Path $site 'en') | Out-Null
Start-Transcript -LiteralPath (Join-Path $logs 'build.log') | Out-Null
try {
  foreach ($file in 'index.html','og.png','취급품목_카탈로그.pdf','en/index.html','en/og.png') {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $site $file) -Force
  }
  $sheets = @(
    @{ Name='품목.csv'; Id='1Tqu5GIITbBdmt40LD7OMf3W7fFYJhfKJolebv6IEOns'; Gid='9001' },
    @{ Name='HS.csv'; Id='1LP0TsSwlB5ck8p1RbqpjqVddDm71rwaXt2wCfWoB3S0'; Gid='0' },
    @{ Name='사진연동.csv'; Id='1Tqu5GIITbBdmt40LD7OMf3W7fFYJhfKJolebv6IEOns'; Gid='9002' }
  )
  foreach ($s in $sheets) {
    $target = Join-Path $source $s.Name
    if ($SourceDirectory) { Copy-Item -LiteralPath (Join-Path $SourceDirectory $s.Name) -Destination $target -Force }
    else {
      $url = "https://docs.google.com/spreadsheets/d/$($s.Id)/export?format=csv&gid=$($s.Gid)"
      Invoke-WebRequest -Uri $url -OutFile $target -TimeoutSec 120 -MaximumRetryCount 2 -RetryIntervalSec 5 | Out-Null
    }
    if ((Get-Item $target).Length -lt 500) { throw "$($s.Name): 시트 내용을 받지 못함. 시트 공유 설정을 확인할 것." }
  }
  $itemCsv = Join-Path $source '품목.csv'
  $hs = @(Import-Csv -LiteralPath (Join-Path $source 'HS.csv') -Encoding utf8)
  foreach ($column in 'Product ID','HS코드(확정)') {
    if (-not $hs.Count -or $column -notin $hs[0].PSObject.Properties.Name) { throw "HS 시트에 '$column' 열이 없음" }
  }
  $item = @(Import-Csv -LiteralPath $itemCsv -Encoding utf8)
  $posted = @($item | Where-Object { $_.'게시상태' -in @('게시','도입검토') -and $_.'PID' -match '^P-[MI]\d' })
  if (@($posted | Group-Object PID | Where-Object Count -gt 1).Count) { throw '게시 품목의 PID가 중복됨' }
  Write-Host '[1/4] 시트 검사 및 카달로그 생성'
  # 사진 = 홈페이지와 같은 「사진 연동」 탭의 1번 사진(원물당 1장). 받지 못하면 중단하고 이전 화면을 유지함.
  Write-Host '[1/4] 홈페이지 1번 사진 받기'
  $photoDir = Join-Path $source '사진'
  if (Test-Path $photoDir) { Remove-Item -LiteralPath $photoDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $photoDir | Out-Null
  $photoRows = @(Import-Csv -LiteralPath (Join-Path $source '사진연동.csv') -Encoding utf8 | Where-Object { $_.'게시상태'.Trim() -eq '게시' -and $_.'파일URL' -and $_.'MID' -in $posted.'MID' })
  if ($photoRows.Count -lt 50) { throw "사진 연동 탭에서 게시 사진이 $($photoRows.Count)장뿐임 — 탭 구조나 공유 설정을 확인할 것." }
  $pick = $photoRows | Group-Object 'MID' | ForEach-Object {
    $_.Group | Sort-Object @{E={ [int]($_.'순서' -replace '\D','0') }}, @{E={ $_.'PID' }} | Select-Object -First 1
  }
  $failed = @()
  foreach ($r in $pick) {
    $url = $r.'파일URL' -replace 'sz=w\d+','sz=w180'
    $dst = Join-Path $photoDir "$($r.'MID').jpg"
    $done = $false
    foreach ($try in 1..3) {
      try { Invoke-WebRequest -Uri $url -OutFile $dst -TimeoutSec 60 | Out-Null; if ((Get-Item $dst).Length -gt 1000) { $done = $true; break } } catch { Start-Sleep -Seconds 3 }
    }
    if (-not $done) { $failed += "$($r.'MID') $($r.'원물명')" }
  }
  if ($failed.Count) { throw "홈페이지 사진을 받지 못함 $($failed.Count)건: $($failed -join ', ')" }
  Write-Host "  사진 $($pick.Count)종(원물당 순서가 가장 앞선 게시 사진)"
  & (Join-Path $PSScriptRoot 'build_원물마스터.ps1')
  & (Join-Path $PSScriptRoot 'build_카탈로그.ps1')
  & (Join-Path $PSScriptRoot 'make_카탈로그_html.ps1') -LogoFile (Join-Path $PSScriptRoot '로고/수창로고_웹.png') -PhotoDir $photoDir
  $env:CATALOG_OUTPUT_DIR = $site
  $env:CATALOG_ITEM_CSV = $itemCsv
  Write-Host '[2/4] 한글·영문 웹페이지 생성'
  & node (Join-Path $PSScriptRoot 'prepare.cjs')
  if ($LASTEXITCODE -ne 0) { throw '웹페이지 생성 실패' }
  Write-Host '[3/4] PDF 및 미리보기 이미지 생성'
  & node (Join-Path $PSScriptRoot 'render.cjs')
  if ($LASTEXITCODE -ne 0) { throw 'PDF 또는 미리보기 이미지 생성 실패' }
  Write-Host '[4/4] 발행 파일 검사'
  & node (Join-Path $PSScriptRoot 'verify.cjs')
  if ($LASTEXITCODE -ne 0) { throw '발행 파일 검사 실패' }
} catch {
  Write-Host "::error::갱신 중단 — 이전 공개 화면 유지. $($_.Exception.Message)"
  if ($env:GITHUB_STEP_SUMMARY) { '❌ 갱신 실패. 이전 공개 화면 유지됨. 실패한 단계의 로그를 확인한 뒤 다시 실행할 것.' | Add-Content $env:GITHUB_STEP_SUMMARY }
  throw
} finally { Stop-Transcript | Out-Null }
