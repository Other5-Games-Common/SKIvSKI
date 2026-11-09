<#
.SYNOPSIS
  Builds (or rebuilds) every SKIvSKI asset from the scripts and graph sources in Docs/, over Unreal MCP.
.DESCRIPTION
  The editor must be open with Other5 loaded (Unreal MCP on http://localhost:8000/mcp) and the "Cmd" console box
  visible in its status bar (editor Python is run through it). Rerunnable: existing assets and variables are kept,
  graphs are cleared and written again from Docs/Graphs/*.lisp, and the RPC events keep their inputs and Replicates.

  On a fresh project (no SKIvSKI assets yet) it also adds the RPC events' inputs and sets Replicates through the
  Blueprint editor's Details panel (the DSL can't), so leave the editor alone while it runs.

  Order matters: Blueprints that call others are written after those exist and compile.
#>
param([switch]$SkipRpcUi)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'UnrealMcp.ps1')
$Scripts = $PSScriptRoot
$Graphs = Join-Path $PSScriptRoot '..\Graphs'
function Step($text) { "`n== $text" }

$C = '/SKIvSKI/Blueprints/BP_SkiCharacter'
$S = '/SKIvSKI/Blueprints/BP_SkiSlope'
$D = '/SKIvSKI/Blueprints/BP_SkiDirector'
$P = '/SKIvSKI/Blueprints/BP_SkiPlayerState'
$B = '/SKIvSKI/Blueprints/BP_Paintball'
$H = '/SKIvSKI/Blueprints/BP_SkiHUD'
$G = '/SKIvSKI/Guns/BP_PaintGunData'
$A = '/SKIvSKI/Animation/ABP_Skier'
$PS = 'obj:/SKIvSKI/Blueprints/BP_SkiPlayerState.BP_SkiPlayerState_C'
$PAWN = 'obj:/Script/Engine.Pawn'
$SM = 'obj:/Script/Engine.StaticMeshComponent'

Step 'input, materials, Blueprint shells and components'
Py (Join-Path $Scripts 'SetupInput.py')
Py (Join-Path $Scripts 'SetupMaterials.py')
Py (Join-Path $Scripts 'SetupBlueprints.py') | Select-String -NotMatch 'char comp'

Step 'variables'
AddVars $G @(
	@('GunName', 'text', 'Gun', 'None', $true), @('Mesh', '/Script/Engine.StaticMesh', 'Gun', 'None', $true), @('MuzzleOffset', 'Vector', 'Gun', 'None', $true),
	@('MuzzleSpeed', 'float', 'Paintball', 'None', $true), @('BallGravityScale', 'float', 'Paintball', 'None', $true), @('BallSize', 'float', 'Paintball', 'None', $true),
	@('ShotsPerSecond', 'float', 'Firing', 'None', $true), @('PelletsPerShot', 'int', 'Firing', 'None', $true), @('SpreadDegrees', 'float', 'Firing', 'None', $true))
AddVars $P @(@('Team', 'int', 'Team', 'Replicated', $false), @('bJoinedTeam', 'bool', 'Team', 'Replicated', $false), @('Hits', 'int', 'Score', 'Replicated', $false),
	@('Points', 'int', 'Score', 'Replicated', $false), @('FinishPlace', 'int', 'Score', 'Replicated', $false), @('FinishTime', 'float', 'Score', 'Replicated', $false))
AddVars $C @(
	@('Gravity', 'float', 'Ski|Tuning', 'None', $true), @('SnowFriction', 'float', 'Ski|Tuning', 'None', $true), @('TopSpeed', 'float', 'Ski|Tuning', 'None', $true),
	@('FullInputAccel', 'float', 'Ski|Tuning', 'None', $true), @('TurnRate', 'float', 'Ski|Tuning', 'None', $true), @('CarveGrip', 'float', 'Ski|Tuning', 'None', $true),
	@('SkidBraking', 'float', 'Ski|Tuning', 'None', $true), @('SkidFriction', 'float', 'Ski|Tuning', 'None', $true), @('SkateInput', 'float', 'Ski|Tuning', 'None', $true),
	@('AcrossHoldSeconds', 'float', 'Ski|Tuning', 'None', $true), @('MaxLean', 'float', 'Ski|Tuning', 'None', $true),
	@('bHoldDownhill', 'bool', 'Ski|Input', 'None', $false), @('bHoldSlow', 'bool', 'Ski|Input', 'None', $false), @('bHoldLeft', 'bool', 'Ski|Input', 'None', $false), @('bHoldRight', 'bool', 'Ski|Input', 'None', $false),
	@('SkiYaw', 'float', 'Ski|State', 'None', $false), @('FallLineYaw', 'float', 'Ski|State', 'None', $false), @('SlopeDegrees', 'float', 'Ski|State', 'None', $false),
	@('bOnSlope', 'bool', 'Ski|State', 'None', $false), @('AcrossHoldLeft', 'float', 'Ski|State', 'None', $false), @('bSkiFrozen', 'bool', 'Ski|State', 'Replicated', $false),
	@('LastSentYaw', 'float', 'Ski|State', 'None', $false), @('Lean', 'float', 'Ski|State', 'None', $false), @('LastYaw', 'float', 'Ski|State', 'None', $false),
	@('SpeedKmh', 'float', 'Ski|State', 'None', $false), @('FloorNormal', 'Vector', 'Ski|State', 'None', $false),
	@('PlaceId', 'int', 'Ski|State', 'RepNotify', $false), @('PlacedYaw', 'float', 'Ski|State', 'Replicated', $false),
	@('Guns', '/SKIvSKI/Guns/BP_PaintGunData.BP_PaintGunData_C:Array', 'Paint', 'None', $true), @('GunIndex', 'int', 'Paint', 'RepNotify', $false),
	@('NextFireTime', 'float', 'Paint', 'None', $false), @('bPrevSwitchGun', 'bool', 'Paint', 'None', $false), @('ShotStream', '/Script/CoreUObject.RandomStream', 'Paint', 'None', $false),
	@('TeamShown', 'int', 'Team', 'None', $false), @('TeamColor', 'LinearColor', 'Team', 'None', $false),
	@('bPrevSwitchTeam', 'bool', 'Team', 'None', $false), @('bPrevHarder', 'bool', 'Team', 'None', $false), @('bPrevEasier', 'bool', 'Team', 'None', $false))
AddVars $S @(
	@('Length', 'float', 'Slope|Layout', 'None', $true), @('TopWidth', 'float', 'Slope|Layout', 'None', $true), @('FinishWidth', 'float', 'Slope|Layout', 'None', $true),
	@('LobbyLength', 'float', 'Slope|Layout', 'None', $true), @('CellSize', 'float', 'Slope|Layout', 'None', $true), @('BankHeight', 'float', 'Slope|Layout', 'None', $true),
	@('BankWidth', 'float', 'Slope|Layout', 'None', $true), @('RidgeHeight', 'float', 'Slope|Layout', 'None', $true), @('GateSpread', 'float', 'Slope|Layout', 'None', $true),
	@('ClearPathWidth', 'float', 'Slope|Layout', 'None', $true),
	@('SlopeDegreesByLevel', 'float:Array', 'Slope|Difficulty', 'None', $true), @('BumpHeightByLevel', 'float:Array', 'Slope|Difficulty', 'None', $true),
	@('TreeCountByLevel', 'int:Array', 'Slope|Difficulty', 'None', $true), @('bBuildOnBeginPlay', 'bool', 'Slope|Difficulty', 'None', $true), @('StartDifficulty', 'int', 'Slope|Difficulty', 'None', $true),
	@('Seed', 'int', 'Slope|Build', 'Replicated', $false), @('Difficulty', 'int', 'Slope|Build', 'Replicated', $false), @('BuildId', 'int', 'Slope|Build', 'RepNotify', $false),
	@('Vertices', 'Vector:Array', 'Slope|Work', 'None', $false), @('Triangles', 'int:Array', 'Slope|Work', 'None', $false), @('UVs', 'Vector2D:Array', 'Slope|Work', 'None', $false),
	@('Stream', '/Script/CoreUObject.RandomStream', 'Slope|Work', 'None', $false), @('SlopeTan', 'float', 'Slope|Work', 'None', $false), @('BumpHeight', 'float', 'Slope|Work', 'None', $false),
	@('Phase1', 'float', 'Slope|Work', 'None', $false), @('Phase2', 'float', 'Slope|Work', 'None', $false), @('Phase3', 'float', 'Slope|Work', 'None', $false), @('FinishX', 'float', 'Slope|Work', 'None', $false))
AddVars $D @(
	@('Slope', '/SKIvSKI/Blueprints/BP_SkiSlope.BP_SkiSlope_C', 'Round|Settings', 'None', $true), @('LobbySeconds', 'float', 'Round|Settings', 'None', $true),
	@('CountdownSeconds', 'float', 'Round|Settings', 'None', $true), @('RaceSeconds', 'float', 'Round|Settings', 'None', $true), @('ResultsSeconds', 'float', 'Round|Settings', 'None', $true),
	@('HitPoints', 'int', 'Round|Settings', 'None', $true), @('FinishPoints', 'int:Array', 'Round|Settings', 'None', $true), @('MinPlayers', 'int', 'Round|Settings', 'None', $true),
	@('bPracticeHits', 'bool', 'Round|Settings', 'None', $true),
	@('Phase', 'int', 'Round|State', 'Replicated', $false), @('PhaseEndsAt', 'float', 'Round|State', 'Replicated', $false), @('Difficulty', 'int', 'Round|State', 'Replicated', $false),
	@('RedScore', 'int', 'Round|State', 'Replicated', $false), @('BlueScore', 'int', 'Round|State', 'Replicated', $false), @('RoundNumber', 'int', 'Round|State', 'Replicated', $false),
	@('Message', 'string', 'Round|State', 'Replicated', $false),
	@('RaceStartedAt', 'float', 'Round|Work', 'None', $false), @('NextPlace', 'int', 'Round|Work', 'None', $false), @('bAllFinished', 'bool', 'Round|Work', 'None', $false),
	@('RedPlaced', 'int', 'Round|Work', 'None', $false), @('BluePlaced', 'int', 'Round|Work', 'None', $false), @('LobbyPlaced', 'int', 'Round|Work', 'None', $false), @('Counted', 'int', 'Round|Work', 'None', $false))
AddVars $B @(@('Shooter', '/Script/Engine.Pawn', 'Paintball', 'None', $false), @('bScores', 'bool', 'Paintball', 'None', $false), @('BallColor', 'LinearColor', 'Paintball', 'None', $false))
foreach ($asset in $G, $P, $C, $S, $D, $B) { Compile $asset | Out-Null }

Step 'functions (with typed inputs/outputs)'
AddFunctions $S @(
	@('HeightAt', @(@('X', 'float'), @('Y', 'float'), @('Height', 'float', 'out'))), @('BuildSnow', @()), @('PlantTrees', @()), @('PlaceGates', @()), @('Generate', @()),
	@('PlaceArch', @(@('PostLeft', $SM), @('PostRight', $SM), @('Banner', $SM), @('X', 'float'), @('Y', 'float'), @('Width', 'float'))),
	@('Rebuild', @(@('NewSeed', 'int'), @('NewDifficulty', 'int'))), @('GetStartSpot', @(@('Team', 'int'), @('Index', 'int'), @('Spot', 'Transform', 'out'))),
	@('GetLobbySpot', @(@('Index', 'int'), @('Spot', 'Transform', 'out'))), @('IsPastFinish', @(@('WorldLocation', 'Vector'), @('Result', 'bool', 'out'))),
	@('IsOutOfBounds', @(@('WorldLocation', 'Vector'), @('Result', 'bool', 'out')))) | Out-Null
AddFunctions $C @(
	@('SetupSkiMovement', @()), @('UpdateSlope', @()), @('SteerSkis', @(, @('DeltaSeconds', 'float'))), @('PushDownSlope', @()), @('LeanIntoTurn', @(, @('DeltaSeconds', 'float'))),
	@('DebugReport', @()), @('PlaceAt', @(, @('Spot', 'Transform'))), @('PaintedBy', @(, @('Shooter', $PAWN))),
	@('GetCurrentGun', @(, @('Gun', 'obj:/SKIvSKI/Guns/BP_PaintGunData.BP_PaintGunData_C', 'out'))), @('GetSkiPlayerState', @(, @('Player', $PS, 'out'))),
	@('ShowGun', @()), @('UpdateTeamLook', @()), @('ReadButtons', @()), @('TryFire', @()),
	@('SpawnBalls', @(@('Muzzle', 'Vector'), @('Direction', 'Vector'), @('Seed', 'int'), @('bScores', 'bool'))),
	@('DebugAim', @(, @('Pitch', 'float'))), @('DebugFire', @()), @('DebugScore', @()), @('DebugSteerToMiddle', @())) | Out-Null
AddFunctions $D @(
	@('Now', @(, @('Time', 'float', 'out'))), @('FindSlope', @(, @('Found', 'bool', 'out'))), @('SetupRounds', @()), @('ServerStep', @()), @('StartLobby', @()),
	@('StartCountdown', @()), @('StartRace', @()), @('EndRace', @()), @('PlaceAll', @(@('bAtGate', 'bool'), @('bFreeze', 'bool'))),
	@('PlaceOne', @(@('Player', $PS), @('bAtGate', 'bool'), @('Index', 'int'))), @('FreezeAll', @(, @('bFreeze', 'bool'))), @('CheckRacers', @()),
	@('RescueLost', @(, @('bAtGate', 'bool'))), @('PlayerFinished', @(, @('Player', $PS))), @('AddPoints', @(@('Player', $PS), @('Points', 'int'))),
	@('ScorePaintHit', @(@('Shooter', $PAWN), @('Victim', $PAWN))), @('SwitchTeam', @(, @('Player', $PS))), @('ChangeDifficulty', @(@('Player', $PS), @('Step', 'int'))),
	@('CountTeam', @(@('Team', 'int'), @('Count', 'int', 'out')))) | Out-Null
AddFunctions $B @(
	@('Launch', @(@('Velocity', 'Vector'), @('Color', 'LinearColor'), @('InShooter', $PAWN), @('bInScores', 'bool'), @('Size', 'float'), @('GravityScale', 'float'))),
	@('Splash', @(@('HitActor', 'obj:/Script/Engine.Actor'), @('HitComponent', 'obj:/Script/Engine.PrimitiveComponent'), @('Where', 'Vector'), @('Normal', 'Vector'))),
	@('ColorSplat', @(, @('Splat', 'obj:/Script/Engine.DecalComponent')))) | Out-Null
foreach ($asset in $C, $S, $D, $B) { Compile $asset | Out-Null }

Step 'RPC events (inputs and Replicates through the Blueprint editor UI)'
$rpcs = @('ServerSetSkiYaw', 'ServerFire', 'MulticastFire', 'ServerNextGun', 'ServerSwitchTeam', 'ServerChangeDifficulty')
# An RPC event is there if the event graph has an entry node of that name.
$missing = $rpcs | Where-Object { -not (Mcp-Call $script:BP 'find_nodes' @{ graph = (GraphRef $C); title = $_; entry_points_only = $true } | ConvertFrom-Json).returnValue }
if ($missing -and -not $SkipRpcUi) {
	$shell = ($missing | ForEach-Object { "(event Custom|$_ (Development|PrintString `"`" :bPrintToScreen false :bPrintToLog false))" }) -join "`n"
	Mcp-Call $script:BP 'write_graph_dsl' @{ graph = (GraphRef $C); code = $shell } | Out-Null
	Compile $C | Out-Null
	$w = OpenBpWindow $C
	foreach ($ev in $missing) {
		SelectEvent $w $ev
		switch ($ev) {
			'ServerSetSkiYaw' { AddParam $w 'NewYaw' 'Float'; SetRpc $w 'Run on Server' $false }
			'ServerFire' { AddParam $w 'Muzzle' 'Vector'; AddParam $w 'Direction' 'Vector'; AddParam $w 'Seed' 'Integer'; SetRpc $w 'Run on Server' $true }
			'MulticastFire' { AddParam $w 'Muzzle' 'Vector'; AddParam $w 'Direction' 'Vector'; AddParam $w 'Seed' 'Integer'; SetRpc $w 'Multicast' $false }
			'ServerChangeDifficulty' { AddParam $w 'Step' 'Integer'; SetRpc $w 'Run on Server' $true }
			default { SetRpc $w 'Run on Server' $true }
		}
	}
	Compile $C | Out-Null
} else { "RPC events present" }

Step 'graphs'
function WriteAll($asset, $file, [string[]]$keep = @()) {
	DeleteNodes $asset 'EventGraph' $keep | Out-Null
	WriteDslFn $asset (Join-Path $Graphs $file) | Where-Object { $_ -notmatch '"returnValue":null' }
}
WriteAll $S 'BP_SkiSlope.lisp'
Compile $S | Out-Null
WriteAll $D 'BP_SkiDirector.lisp'
Compile $D | Out-Null
DeleteNodes $C 'EventGraph' $rpcs | Out-Null
WriteDslFn $C (Join-Path $Graphs 'BP_SkiCharacter.Movement.lisp') | Where-Object { $_ -notmatch '"returnValue":null' }
Compile $C | Out-Null
WriteDslFn $C (Join-Path $Graphs 'BP_SkiCharacter.Paint.lisp') | Where-Object { $_ -notmatch '"returnValue":null' }
Compile $C | Out-Null
WriteDslFn $C (Join-Path $Graphs 'BP_SkiCharacter.Events.lisp') | Where-Object { $_ -notmatch '"returnValue":null' }
Compile $C | Out-Null
if ((Mcp-Call $script:BP 'find_nodes' @{ graph = (GraphRef $B); title = 'On Projectile Stop' }) -notmatch 'ComponentBoundEvent') {
	Mcp-Call $script:BP 'add_component_bound_event' @{ component = @{ refPath = '/SKIvSKI/Blueprints/BP_Paintball.BP_Paintball_C:Flight_GEN_VARIABLE' }; event_name = 'OnProjectileStop'; graph = (GraphRef $B) } | Out-Null
}
WriteAll $B 'BP_Paintball.lisp'
WriteAll $H 'BP_SkiHUD.lisp'

Step 'animation'
Py (Join-Path $Scripts 'SetupAnimation.py')
& (Join-Path $Scripts 'BuildAnimGraph.ps1')
Py (Join-Path $Scripts 'SetupAnimation.py')
WriteAll $A 'ABP_Skier.lisp'

Step 'compile (warnings as errors)'
foreach ($asset in $G, $P, $S, $D, $B, $C, $H, $A) {
	$n = $asset.Split('/')[-1]
	"$n " + (Mcp-Call $script:BP 'compile_blueprint' @{ blueprint = @{ refPath = "$asset.$n" }; warnings_as_errors = $true })
}

Step 'defaults, guns, level, creation label'
Py (Join-Path $Scripts 'SetupDefaults.py')
Py (Join-Path $Scripts 'SetupGuns.py')
Py (Join-Path $Scripts 'SetupSkiMap.py')
Py (Join-Path $Scripts 'SetupCreationLabel.py')
SaveSki
