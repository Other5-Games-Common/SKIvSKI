<#
.SYNOPSIS
  Builds (or rebuilds) every SKIvSKI asset from the scripts and graph sources in Docs/, over Unreal MCP.
.DESCRIPTION
  The editor must be open with Other5 loaded (Unreal MCP on http://localhost:8000/mcp, or the URL in
  $env:UNREAL_MCP_URL when another project's editor holds port 8000; see UnrealMcp.ps1) and the "Cmd" console box
  visible in its status bar (editor Python is run through it). Rerunnable: existing assets and variables are kept,
  graphs are cleared and written again from Docs/Graphs/*.lisp, and the RPC events keep their inputs and Replicates.

  On a fresh project (no SKIvSKI assets yet) it also adds the RPC events' inputs and sets Replicates through the
  Blueprint editor's Details panel (the DSL can't), so leave the editor alone while it runs.

  Order matters: Blueprints that call others are written after those exist and compile. Last, LayoutGraphs.py lays
  every graph out (the DSL leaves all nodes in one row) and boxes each event and function with its .lisp comment.
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
$ISM = 'obj:/Script/Engine.InstancedStaticMeshComponent'

Step 'input, materials, Blueprint shells and components'
Py (Join-Path $Scripts 'SetupInput.py')
Py (Join-Path $Scripts 'SetupMaterials.py')
Py (Join-Path $Scripts 'SetupAudio.py')
Py (Join-Path $Scripts 'SetupFonts.py')
Py (Join-Path $Scripts 'SetupBlueprints.py') | Select-String -NotMatch 'char comp'

Step 'variables'
AddVars $G @(
	@('GunName', 'text', 'Gun', 'None', $true), @('Mesh', '/Script/Engine.StaticMesh', 'Gun', 'None', $true), @('MuzzleOffset', 'Vector', 'Gun', 'None', $true),
	@('MuzzleSpeed', 'float', 'Paintball', 'None', $true), @('BallGravityScale', 'float', 'Paintball', 'None', $true), @('BallSize', 'float', 'Paintball', 'None', $true),
	@('ShotsPerSecond', 'float', 'Firing', 'None', $true), @('PelletsPerShot', 'int', 'Firing', 'None', $true), @('SpreadDegrees', 'float', 'Firing', 'None', $true),
	@('FireSounds', '/Script/Engine.SoundBase:Array', 'Firing', 'None', $true), @('FireMontage', '/Script/Engine.AnimMontage', 'Firing', 'None', $true),
	@('GripOffset', 'Vector', 'Gun', 'None', $true), @('ArmsKind', 'int', 'Gun', 'None', $true))
# Teams are Other5's shared teams (team on Other5's player state), so the player state keeps only SKIvSKI's own state.
AddVars $P @(@('bOut', 'bool', 'Score', 'Replicated', $false), @('SnowFriction', 'float', 'Gear', 'Replicated', $true), @('BounceChance', 'float', 'Gear', 'Replicated', $true),
	@('Hits', 'int', 'Score', 'Replicated', $false),
	@('Points', 'int', 'Score', 'Replicated', $false), @('FinishPlace', 'int', 'Score', 'Replicated', $false), @('FinishTime', 'float', 'Score', 'Replicated', $false))
AddVars $C @(
	@('Gravity', 'float', 'Ski|Tuning', 'None', $true), @('SnowFriction', 'float', 'Ski|Tuning', 'None', $true), @('TopSpeed', 'float', 'Ski|Tuning', 'None', $true),
	@('FullInputAccel', 'float', 'Ski|Tuning', 'None', $true), @('TurnRate', 'float', 'Ski|Tuning', 'None', $true), @('CarveGrip', 'float', 'Ski|Tuning', 'None', $true),
	@('SkidBraking', 'float', 'Ski|Tuning', 'None', $true), @('SkidFriction', 'float', 'Ski|Tuning', 'None', $true), @('SkateInput', 'float', 'Ski|Tuning', 'None', $true),
	@('AcrossHoldSeconds', 'float', 'Ski|Tuning', 'None', $true), @('MaxLean', 'float', 'Ski|Tuning', 'None', $true), @('EdgeGrip', 'float', 'Ski|Tuning', 'None', $true), @('SkateSpeed', 'float', 'Ski|Tuning', 'None', $true),
	@('bHoldDownhill', 'bool', 'Ski|Input', 'None', $false), @('bHoldSlow', 'bool', 'Ski|Input', 'None', $false), @('bHoldLeft', 'bool', 'Ski|Input', 'None', $false), @('bHoldRight', 'bool', 'Ski|Input', 'None', $false),
	@('SkiYaw', 'float', 'Ski|State', 'None', $false), @('FallLineYaw', 'float', 'Ski|State', 'None', $false), @('SlopeDegrees', 'float', 'Ski|State', 'None', $false),
	@('bOnSlope', 'bool', 'Ski|State', 'None', $false), @('AcrossHoldLeft', 'float', 'Ski|State', 'None', $false), @('bSkiFrozen', 'bool', 'Ski|State', 'Replicated', $false),
	@('LastSentYaw', 'float', 'Ski|State', 'None', $false), @('Lean', 'float', 'Ski|State', 'None', $false), @('LastYaw', 'float', 'Ski|State', 'None', $false),
	@('SpeedKmh', 'float', 'Ski|State', 'None', $false), @('FloorNormal', 'Vector', 'Ski|State', 'None', $false),
	@('PlaceId', 'int', 'Ski|State', 'RepNotify', $false), @('PlacedYaw', 'float', 'Ski|State', 'Replicated', $false), @('bSkiStarted', 'bool', 'Ski|State', 'None', $false),
	@('Guns', '/SKIvSKI/Guns/BP_PaintGunData.BP_PaintGunData_C:Array', 'Paint', 'None', $true), @('GunIndex', 'int', 'Paint', 'RepNotify', $false),
	@('NextFireTime', 'float', 'Paint', 'None', $false), @('ShotSeed', 'int', 'Paint', 'None', $false), @('ShotDir', 'Vector', 'Paint', 'None', $false), @('bPrevSwitchGun', 'bool', 'Paint', 'None', $false), @('ShotStream', '/Script/CoreUObject.RandomStream', 'Paint', 'None', $false),
	@('TeamShown', 'int', 'Team', 'None', $false), @('TeamColor', 'LinearColor', 'Team', 'None', $false),
	@('bPrevSwitchTeam', 'bool', 'Team', 'None', $false), @('bPrevHarder', 'bool', 'Team', 'None', $false), @('bPrevEasier', 'bool', 'Team', 'None', $false))
AddVars $S @(
	@('Length', 'float', 'Slope|Layout', 'None', $true), @('TopWidth', 'float', 'Slope|Layout', 'None', $true), @('FinishWidth', 'float', 'Slope|Layout', 'None', $true),
	@('LobbyLength', 'float', 'Slope|Layout', 'None', $true), @('CellSize', 'float', 'Slope|Layout', 'None', $true), @('BankHeight', 'float', 'Slope|Layout', 'None', $true),
	@('BankWidth', 'float', 'Slope|Layout', 'None', $true), @('RidgeHeight', 'float', 'Slope|Layout', 'None', $true), @('GateSpread', 'float', 'Slope|Layout', 'None', $true),
	@('ClearPathWidth', 'float', 'Slope|Layout', 'None', $true), @('TreeGap', 'float', 'Slope|Layout', 'None', $true), @('RunoutLength', 'float', 'Slope|Layout', 'None', $true), @('RunoutRise', 'float', 'Slope|Layout', 'None', $true),
	@('SlopeDegreesByLevel', 'float:Array', 'Slope|Difficulty', 'None', $true), @('BumpHeightByLevel', 'float:Array', 'Slope|Difficulty', 'None', $true),
	@('TreeCountByLevel', 'int:Array', 'Slope|Difficulty', 'None', $true), @('bBuildOnBeginPlay', 'bool', 'Slope|Difficulty', 'None', $true), @('StartDifficulty', 'int', 'Slope|Difficulty', 'None', $true),
	@('Seed', 'int', 'Slope|Build', 'Replicated', $false), @('Difficulty', 'int', 'Slope|Build', 'Replicated', $false), @('BuildId', 'int', 'Slope|Build', 'RepNotify', $false),
	@('Vertices', 'Vector:Array', 'Slope|Work', 'None', $false), @('Triangles', 'int:Array', 'Slope|Work', 'None', $false), @('UVs', 'Vector2D:Array', 'Slope|Work', 'None', $false),
	@('Stream', '/Script/CoreUObject.RandomStream', 'Slope|Work', 'None', $false), @('SlopeTan', 'float', 'Slope|Work', 'None', $false), @('BumpHeight', 'float', 'Slope|Work', 'None', $false),
	@('Phase1', 'float', 'Slope|Work', 'None', $false), @('Phase2', 'float', 'Slope|Work', 'None', $false), @('Phase3', 'float', 'Slope|Work', 'None', $false), @('FinishX', 'float', 'Slope|Work', 'None', $false),
	@('TreeT', 'float', 'Slope|Work', 'None', $false), @('TreeSide', 'float', 'Slope|Work', 'None', $false), @('TreeSize', 'float', 'Slope|Work', 'None', $false), @('TreeSpin', 'float', 'Slope|Work', 'None', $false),
	@('TreeSpots', 'Vector:Array', 'Slope|Work', 'None', $false), @('bTreeClear', 'bool', 'Slope|Work', 'None', $false),
@('Xs', 'float:Array', 'Slope|Work', 'None', $false), @('Ys', 'float:Array', 'Slope|Work', 'None', $false), @('Steps', 'float:Array', 'Slope|Work', 'None', $false), @('StepAt', 'float', 'Slope|Work', 'None', $false), @('StepSize', 'float', 'Slope|Work', 'None', $false),
@('OuterWidth', 'float', 'Slope|Layout', 'None', $true),
@('LookTree', 'string', 'Slope|Look', 'None', $true), @('LookTreeTall', 'string', 'Slope|Look', 'None', $true), @('LookFarTrees', 'string', 'Slope|Look', 'None', $true), @('LookClump', 'string', 'Slope|Look', 'None', $true),
@('LookRock', 'string', 'Slope|Look', 'None', $true), @('LookMountain', 'string', 'Slope|Look', 'None', $true), @('LookMountainMaterial', 'string', 'Slope|Look', 'None', $true), @('LookSnow', 'string', 'Slope|Look', 'None', $true), @('LookSnowfall', 'string', 'Slope|Look', 'None', $true),
@('ForestCount', 'int', 'Slope|Look', 'None', $true), @('FarTreeCount', 'int', 'Slope|Look', 'None', $true), @('ClumpCount', 'int', 'Slope|Look', 'None', $true), @('RockCount', 'int', 'Slope|Look', 'None', $true), @('MountainCount', 'int', 'Slope|Look', 'None', $true), @('MountainDistance', 'float', 'Slope|Look', 'None', $true),
@('bFancy', 'bool', 'Slope|Look', 'None', $false), @('bSnowing', 'bool', 'Slope|Look', 'None', $false))
AddVars $D @(
	@('Slope', '/SKIvSKI/Blueprints/BP_SkiSlope.BP_SkiSlope_C', 'Round|Settings', 'None', $true), @('LobbySeconds', 'float', 'Round|Settings', 'None', $true),
	@('CountdownSeconds', 'float', 'Round|Settings', 'None', $true), @('RaceSeconds', 'float', 'Round|Settings', 'None', $true), @('ResultsSeconds', 'float', 'Round|Settings', 'None', $true),
	@('HitPoints', 'int', 'Round|Settings', 'None', $true), @('FinishPoints', 'int:Array', 'Round|Settings', 'None', $true), @('MinPlayers', 'int', 'Round|Settings', 'None', $true),
	@('bPracticeHits', 'bool', 'Round|Settings', 'None', $true), @('CoinsPerPoint', 'int', 'Round|Settings', 'None', $true),
	@('Phase', 'int', 'Round|State', 'Replicated', $false), @('PhaseEndsAt', 'float', 'Round|State', 'Replicated', $false), @('Difficulty', 'int', 'Round|State', 'Replicated', $false),
	@('RoundNumber', 'int', 'Round|State', 'Replicated', $false), @('Message', 'string', 'Round|State', 'Replicated', $false),
	@('RaceStartedAt', 'float', 'Round|Work', 'None', $false), @('NextPlace', 'int', 'Round|Work', 'None', $false), @('bAllFinished', 'bool', 'Round|Work', 'None', $false),
	@('RedPlaced', 'int', 'Round|Work', 'None', $false), @('BluePlaced', 'int', 'Round|Work', 'None', $false), @('LobbyPlaced', 'int', 'Round|Work', 'None', $false), @('HitResult', 'int', 'Round|Work', 'None', $false))
AddVars $B @(@('Shooter', '/Script/Engine.Pawn', 'Paintball', 'None', $false), @('bScores', 'bool', 'Paintball', 'None', $false), @('BallColor', 'LinearColor', 'Paintball', 'None', $false))
AddVars $H @(@('PopupTexts', 'string:Array', 'Popups', 'None', $false), @('PopupPlaces', 'Vector:Array', 'Popups', 'None', $false), @('PopupColors', 'LinearColor:Array', 'Popups', 'None', $false),
	@('PopupStarts', 'float:Array', 'Popups', 'None', $false), @('PopupSizes', 'float:Array', 'Popups', 'None', $false), @('PopupTargets', '/Script/Engine.Actor:Array', 'Popups', 'None', $false), @('PopupSeconds', 'float', 'Popups', 'None', $true),
	@('ScreenW', 'float', 'Layout', 'None', $false), @('ScreenH', 'float', 'Layout', 'None', $false), @('U', 'float', 'Layout', 'None', $false), @('Row', 'int', 'Layout', 'None', $false),
	@('LastPhase', 'int', 'Sound', 'None', $false), @('LastSecond', 'int', 'Sound', 'None', $false), @('GoUntil', 'float', 'Sound', 'None', $false),
	@('LastScore0', 'int', 'Sound', 'None', $false), @('LastScore1', 'int', 'Sound', 'None', $false), @('Flash0Until', 'float', 'Sound', 'None', $false), @('Flash1Until', 'float', 'Sound', 'None', $false))
foreach ($asset in $G, $P, $C, $S, $D, $B, $H) { Compile $asset | Out-Null }

Step 'functions (with typed inputs/outputs)'
AddFunctions $S @(
	@('HeightAt', @(@('X', 'float'), @('Y', 'float'), @('Height', 'float', 'out'))), @('BuildSnow', @()), @('PlantTrees', @()), @('PlantTree', @(@('X', 'float'), @('Y', 'float'), @('Size', 'float'), @('Spin', 'float'))), @('PlaceGates', @()), @('Generate', @()),
	@('PlaceArch', @(@('PostLeft', $SM), @('PostRight', $SM), @('Banner', $SM), @('X', 'float'), @('Y', 'float'), @('Width', 'float'))),
	@('Rebuild', @(@('NewSeed', 'int'), @('NewDifficulty', 'int'))), @('GetStartSpot', @(@('Team', 'int'), @('Index', 'int'), @('Spot', 'Transform', 'out'))),
	@('GetLobbySpot', @(@('Index', 'int'), @('Spot', 'Transform', 'out'))), @('IsPastFinish', @(@('WorldLocation', 'Vector'), @('Result', 'bool', 'out'))),
	@('IsOutOfBounds', @(@('WorldLocation', 'Vector'), @('Result', 'bool', 'out'))),
	@('OuterHeightAt', @(@('X', 'float'), @('Y', 'float'), @('Height', 'float', 'out'))), @('OuterSteps', @()), @('Draw', @(@('Min', 'float'), @('Max', 'float'), @('Value', 'float', 'out'))),
	@('PlantArt', @(@('Hism', $ISM), @('X', 'float'), @('Y', 'float'), @('Scale', 'float'), @('Spin', 'float'), @('Sink', 'float'))),
	@('LoadLook', @(@('Path', 'string'), @('Asset', 'obj:/Script/CoreUObject.Object', 'out'))), @('LookMeshOn', @(@('Hism', $ISM), @('Path', 'string'), @('Found', 'bool', 'out'))),
	@('LookMaterialOn', @(@('Target', 'obj:/Script/Engine.PrimitiveComponent'), @('Path', 'string'), @('Found', 'bool', 'out'))), @('StartSnowfall', @()), @('ApplyLook', @()), @('DressScene', @())) | Out-Null
AddFunctions $C @(
	@('SkiBeginPlay', @()), @('SetupSkiMovement', @()), @('UpdateGlide', @()), @('UpdateSlope', @()), @('SteerSkis', @(, @('DeltaSeconds', 'float'))), @('PushDownSlope', @()), @('LeanIntoTurn', @(, @('DeltaSeconds', 'float'))),
	@('DebugReport', @()), @('PlaceAt', @(, @('Spot', 'Transform'))),
	@('PaintedBy', @(@('Shooter', $PAWN), @('Where', 'Vector'), @('Direction', 'Vector'), @('Normal', 'Vector'), @('Color', 'LinearColor'), @('Size', 'float'))),
	@('IsOut', @(, @('Out', 'bool', 'out'))), @('AddCoins', @(, @('Amount', 'int'))), @('GetCoins', @(, @('Coins', 'int', 'out'))),
	@('GetSnowFriction', @(, @('Friction', 'float', 'out'))), @('ShowPopup', @(@('Text', 'string'), @('Where', 'Vector'), @('Color', 'LinearColor'), @('Size', 'float'), @('Target', 'obj:/Script/Engine.Actor'))), @('DebugPopup', @()), @('DebugHitMe', @()),
	@('GetCurrentGun', @(, @('Gun', 'obj:/SKIvSKI/Guns/BP_PaintGunData.BP_PaintGunData_C', 'out'))), @('GetSkiPlayerState', @(, @('Player', $PS, 'out'))),
	@('ShowGun', @()), @('UpdateTeamLook', @()), @('ReadButtons', @()), @('TryFire', @()),
	@('SpawnBalls', @(@('Muzzle', 'Vector'), @('Direction', 'Vector'), @('Seed', 'int'), @('bScores', 'bool'))),
	@('DebugAim', @(, @('Pitch', 'float'))), @('DebugFire', @()), @('DebugScore', @()), @('DebugSteerToMiddle', @()), @('DebugPhase', @(, @('Phase', 'int')))) | Out-Null
AddFunctions $D @(
	@('Now', @(, @('Time', 'float', 'out'))), @('FindSlope', @(, @('Found', 'bool', 'out'))), @('SetupRounds', @()), @('ServerStep', @()), @('StartLobby', @()),
	@('StartCountdown', @()), @('StartRace', @()), @('EndRace', @()), @('PlaceAll', @(@('bAtGate', 'bool'), @('bFreeze', 'bool'))),
	@('PlaceOne', @(@('Player', $PS), @('bAtGate', 'bool'), @('Index', 'int'))), @('FreezeAll', @(, @('bFreeze', 'bool'))), @('CheckRacers', @()),
	@('RescueLost', @(, @('bAtGate', 'bool'))), @('PlayerFinished', @(, @('Player', $PS))), @('AddPoints', @(@('Player', $PS), @('Points', 'int'))),
	@('ResolvePaintHit', @(@('Shooter', $PAWN), @('Victim', $PAWN), @('Result', 'int', 'out'))), @('ResetRound', @()),
	@('ChangeDifficulty', @(@('Player', $PS), @('Step', 'int')))) | Out-Null
AddFunctions $H @(
	@('DrawRound', @(, @('Director', 'obj:/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C'))), @('DrawSkier', @(, @('Skier', 'obj:/SKIvSKI/Blueprints/BP_SkiCharacter.BP_SkiCharacter_C'))),
	@('AddPopup', @(@('Text', 'string'), @('Where', 'Vector'), @('Color', 'LinearColor'), @('Size', 'float'), @('Target', 'obj:/Script/Engine.Actor'))), @('DrawPopups', @()),
	@('AddPopupLook', @(@('Color', 'LinearColor'), @('Size', 'float'))), @('PopupSpot', @(@('Index', 'int'), @('Spot', 'Vector', 'out'))),
	@('DrawOutlined', @(@('Text', 'string'), @('CenterX', 'float'), @('Y', 'float'), @('Color', 'LinearColor'), @('Size', 'float'))),
	@('DrawTeamPanel', @(@('Team', 'int'), @('X', 'float'), @('FlashUntil', 'float'))), @('DrawCountdown', @(, @('Left', 'float'))), @('DrawGo', @()),
	@('DrawResults', @(, @('Director', 'obj:/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C'))), @('DrawResultRow', @(@('Player', 'obj:/Script/Engine.PlayerState'), @('Top', 'float'))),
	@('PlayRoundSounds', @(, @('Director', 'obj:/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C'))),
	@('DrawPanel', @(@('X', 'float'), @('Y', 'float'), @('W', 'float'), @('H', 'float'), @('Accent', 'LinearColor'))),
	@('DrawCentered', @(@('Text', 'string'), @('CenterX', 'float'), @('Y', 'float'), @('Color', 'LinearColor'), @('Size', 'float'), @('bTitle', 'bool'))),
	@('DrawLeft', @(@('Text', 'string'), @('X', 'float'), @('Y', 'float'), @('Color', 'LinearColor'), @('Size', 'float'), @('bTitle', 'bool'))),
	@('Ink', @(, @('Color', 'LinearColor', 'out'))), @('Muted', @(, @('Color', 'LinearColor', 'out'))), @('Neon', @(, @('Color', 'LinearColor', 'out'))),
	@('Gold', @(, @('Color', 'LinearColor', 'out'))), @('Bad', @(, @('Color', 'LinearColor', 'out')))) | Out-Null
AddFunctions $B @(
	@('Launch', @(@('Velocity', 'Vector'), @('Color', 'LinearColor'), @('InShooter', $PAWN), @('bInScores', 'bool'), @('Size', 'float'), @('GravityScale', 'float'))),
	@('Splash', @(@('HitActor', 'obj:/Script/Engine.Actor'), @('HitComponent', 'obj:/Script/Engine.PrimitiveComponent'), @('Where', 'Vector'), @('Normal', 'Vector'))),
	@('ColorSplat', @(, @('Splat', 'obj:/Script/Engine.DecalComponent')))) | Out-Null
foreach ($asset in $C, $S, $D, $B, $H) { Compile $asset | Out-Null }
Py (Join-Path $Scripts 'SetupPureFunctions.py')

Step 'RPC events (inputs and Replicates through the Blueprint editor UI)'
$rpcs = @('ServerSetSkiYaw', 'ServerFire', 'MulticastFire', 'ServerNextGun', 'ServerChangeDifficulty', 'MulticastPaintResult')
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
			'MulticastPaintResult' { AddParam $w 'bHit' 'Boolean'; AddParam $w 'Where' 'Vector'; AddParam $w 'Bounce' 'Vector'; AddParam $w 'Tint' 'Vector'; AddParam $w 'Size' 'Float'; SetRpc $w 'Multicast' $true }
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

Step 'layout: readable graphs with comment boxes'
Py (Join-Path $Scripts 'LayoutGraphs.py') 600
SaveSki
