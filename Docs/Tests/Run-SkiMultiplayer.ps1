<#
.SYNOPSIS
  SKIvSKI multiplayer check from the editor binaries: a dedicated server on L_SkiVSki and two clients that join it,
  aim at each other and fire paintballs through a lobby and a race (Docs/Tests/SkiDuelA.txt, SkiDuelB.txt).
.DESCRIPTION
  Logs go to -OutDir (default: %TEMP%\SkiMultiplayer). The clients log "SKI| phase P red R blue B myTeam T
  myHits H balls N" lines; the summary at the end prints them. The first client to join is Red, the second Blue.
  Needs the editor build of Other5 (no packaged builds). Close nothing else: these are extra processes.
.EXAMPLE
  .\Run-SkiMultiplayer.ps1
#>
param(
	[string]$Engine = '',
	[string]$OutDir = (Join-Path $env:TEMP 'SkiMultiplayer'),
	[int]$Port = 7787,
	[int]$TimeoutSeconds = 240
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\Other5.uproject')).Path
if (-not $Engine) {
	# The launcher engine the project uses (EngineAssociation "5.8"), from the registry.
	$assoc = (Get-Content $project -Raw | ConvertFrom-Json).EngineAssociation
	$Engine = (Get-ItemProperty "HKLM:\SOFTWARE\EpicGames\Unreal Engine\$assoc" -ErrorAction Stop).InstalledDirectory
}
$editor = Join-Path $Engine 'Engine\Binaries\Win64\UnrealEditor.exe'
New-Item -ItemType Directory -Force $OutDir | Out-Null
Remove-Item (Join-Path $OutDir '*.log') -ErrorAction SilentlyContinue

$common = @("`"$project`"", '-NoEOS', '-log', '-unattended', '-nosplash')
$server = Start-Process $editor -PassThru -ArgumentList ($common + @('/SKIvSKI/Maps/L_SkiVSki', '-server', "-port=$Port",
	'-Other5AllowNoTicket', '-SkiPracticeHits', "-abslog=`"$OutDir\Server.log`""))
Start-Sleep 20
$clients = @()
foreach ($name in 'A', 'B') {
	$script = Join-Path $PSScriptRoot "SkiDuel$name.txt"
	$clients += Start-Process $editor -PassThru -ArgumentList ($common + @("127.0.0.1:$Port", '-game', '-windowed',
		'-ResX=960', '-ResY=540', "-Other5TestScript=`"$script`"", "-abslog=`"$OutDir\Client$name.log`""))
	Start-Sleep 6
}
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and ($clients | Where-Object { -not $_.HasExited })) { Start-Sleep 2 }
$clients | Where-Object { -not $_.HasExited } | ForEach-Object { Stop-Process $_ -Force }
if (-not $server.HasExited) { Stop-Process $server -Force }

foreach ($name in 'A', 'B') {
	"== Client $name"
	Select-String -Path "$OutDir\Client$name.log" -Pattern 'SKI\||OTHER5TEST\| (FAIL|DONE)|Accessed None|Blueprint Runtime Error' |
		ForEach-Object { $_.Line -replace '^\[[^\]]*\]\[[^\]]*\]\w+: (Display: |Error: |Warning: )?(\[[^\]]*\] )?', '' }
}
"== Server"
Select-String -Path "$OutDir\Server.log" -Pattern 'SKI\||Accessed None|Blueprint Runtime Error|Join succeeded|O5Join' |
	Select-Object -First 40 | ForEach-Object { $_.Line -replace '^\[[^\]]*\]\[[^\]]*\]', '' }
