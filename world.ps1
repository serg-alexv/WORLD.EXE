param(
  [ValidateSet('doctor','test','queue','run','tick','github')][string]$Command='doctor',
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
)
$ErrorActionPreference='Stop'
$repo=$PSScriptRoot
$ops=Join-Path $env:USERPROFILE 'WORLD.EXE-ops'
$py=Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\python.exe'
if(!(Test-Path $py)){ $py=(Get-Command python -ErrorAction Stop).Source }
Push-Location $repo
try {
  if($Command -eq 'test') {
    & $py -m unittest discover -s DevTeam/tests -v
    if($LASTEXITCODE -ne 0){throw 'DevTeam gates failed'}
    & $py -m unittest discover -s scripts/tests -v
    if($LASTEXITCODE -ne 0){throw 'Repository gates failed'}
    & npm.cmd --prefix Gamebox test
    if($LASTEXITCODE -ne 0){throw 'Gamebox gates failed'}
  } elseif($Command -eq 'github') {
    & gh run list --repo serg-alexv/WORLD.EXE --limit 8 --json databaseId,headSha,workflowName,status,conclusion
    if($LASTEXITCODE -ne 0){throw 'GitHub visibility unavailable'}
  } else {
    & $py DevTeam/src/teamctl.py --repo $repo --ops $ops $Command @Arguments
    if($LASTEXITCODE -ne 0){throw 'DevTeam command blocked; inspect its explicit result'}
  }
} finally {Pop-Location}
