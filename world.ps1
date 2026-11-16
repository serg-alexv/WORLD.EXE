param(
  [ValidateSet('doctor','test','queue','run','tick','github')][string]$Command='doctor',
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
)
$ErrorActionPreference='Stop'
$repo=$PSScriptRoot
$ops=Join-Path $env:USERPROFILE 'WORLD.EXE-ops'
$py=Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\python.exe'
if(!(Test-Path $py)){ $py=(Get-Command python -ErrorAction Stop).Source }
function Invoke-CheckedNative {
  param([string]$Executable,[string[]]$NativeArguments)
  $previous=$ErrorActionPreference
  try {
    # Python unittest writes successful progress to stderr; exit status is authoritative.
    $ErrorActionPreference='Continue'
    & $Executable @NativeArguments
    $result=$LASTEXITCODE
  } finally { $ErrorActionPreference=$previous }
  if($result -ne 0){throw "Native command failed (exit $result): $Executable"}
}
Push-Location $repo
try {
  if($Command -eq 'test') {
    Invoke-CheckedNative $py @('-m','unittest','discover','-s','DevTeam/tests','-v')
    Invoke-CheckedNative $py @('-m','unittest','discover','-s','scripts/tests','-v')
    Invoke-CheckedNative 'npm.cmd' @('--prefix','Gamebox','test')
  } elseif($Command -eq 'github') {
    Invoke-CheckedNative 'gh' @('run','list','--repo','serg-alexv/WORLD.EXE','--limit','8','--json','databaseId,headSha,workflowName,status,conclusion')
  } else {
    $argsForTeam=@('DevTeam/src/teamctl.py','--repo',$repo,'--ops',$ops,$Command)+$Arguments
    Invoke-CheckedNative $py $argsForTeam
  }
} finally {Pop-Location}
