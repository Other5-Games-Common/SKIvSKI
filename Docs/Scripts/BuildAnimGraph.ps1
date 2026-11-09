<#
.SYNOPSIS
  Rebuilds ABP_Skier's Anim Graph over Unreal MCP (the editor must be open). The DSL writes event graphs only, so
  the anim nodes are made and wired here. Rerunnable: it clears the Anim Graph (except the Output Pose) first.

  Legs:       MM_Rifle_Idle_Hipfire (standing) -> Two Way Blend <- MM_Rifle_Crouch_Idle (knees bent); Alpha = SkiCrouch
              (set from the speed in the event graph, Docs/Graphs/ABP_Skier.lisp).
  Upper body: MM_Rifle_Idle_Hipfire through the AO_MM_Rifle_Idle_Hipfire aim offset (X = AimYaw, Y = AimPitch),
              so the chest and arms follow the camera while the skis point elsewhere.
  Output:     Layered blend per bone: legs as the base, upper body from spine_01 up, mesh-space rotation
              (set by SetupAnimation.py).
#>
. (Join-Path $PSScriptRoot 'UnrealMcp.ps1')
$A = '/SKIvSKI/Animation/ABP_Skier'
$g = @{ refPath = "$A.ABP_Skier:AnimGraph" }

AddVars $A @(
	@('SkiCrouch', 'float', 'Ski', 'None', $false),
	@('AimYaw', 'float', 'Ski', 'None', $false),
	@('AimPitch', 'float', 'Ski', 'None', $false)
)
Compile $A | Out-Null

# Clear the graph, keeping the Output Pose.
$nodes = (Mcp-Call $script:BP 'find_nodes' @{ graph = $g; title = '' } | ConvertFrom-Json).returnValue
foreach ($n in $nodes) { if ($n.refPath -notmatch 'AnimGraphNode_Root') { $null = Mcp-Call $script:BP 'delete_node' @{ node = $n } } }
$root = (Mcp-Call $script:BP 'find_nodes' @{ graph = $g; title = '' } | ConvertFrom-Json).returnValue | Select-Object -First 1

$stand = NewNode $g "Animation|Sequences|Play'MM_Rifle_Idle_Hipfire'" -1300 -100
$crouch = NewNode $g "Animation|Sequences|Play'MM_Rifle_Crouch_Idle'" -1300 100
$crouchAmount = NewNode $g 'Variables|Ski|GetSkiCrouch' -1250 300
$legs = NewNode $g 'Animation|Blends|TwoWayBlend' -950 0
$arms = NewNode $g "Animation|Sequences|Play'MM_Rifle_Idle_Hipfire'" -1300 450
$aim = NewNode $g "Animation|BlendSpaces|AimOffset'AO_MM_Rifle_Idle_Hipfire'" -950 450
$yaw = NewNode $g 'Variables|Ski|GetAimYaw' -1250 650
$pitch = NewNode $g 'Variables|Ski|GetAimPitch' -1250 750
$layer = NewNode $g 'Animation|Blends|Layeredblendperbone' -550 150

$null = Link $stand 'Pose' $legs 'A'
$null = Link $crouch 'Pose' $legs 'B'
$null = Link $crouchAmount 'SkiCrouch' $legs 'Alpha'
$null = Link $arms 'Pose' $aim 'BasePose'
$null = Link $yaw 'AimYaw' $aim 'X'
$null = Link $pitch 'AimPitch' $aim 'Y'
$null = Link $legs 'Pose' $layer 'BasePose'
$null = Link $aim 'Pose' $layer 'BlendPoses_0'
$null = Link $layer 'Pose' $root 'Result'
"anim graph wired; now run SetupAnimation.py for the layer filter"
