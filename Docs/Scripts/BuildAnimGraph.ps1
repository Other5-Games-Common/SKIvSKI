<#
.SYNOPSIS
  Rebuilds ABP_Skier's Anim Graph over Unreal MCP (the editor must be open). The DSL writes event graphs only, so
  the anim nodes are made and wired here. Rerunnable: it clears the Anim Graph (except the Output Pose) first.

  Legs:       MM_Rifle_Idle_Hipfire (standing) -> Two Way Blend <- MM_Rifle_Crouch_Idle (knees bent); Alpha = SkiCrouch
              (set from the speed in the event graph, Docs/Graphs/ABP_Skier.lisp).
  Upper body: how the gun in hand is held, from Other5Characters' poses: a pistol (MM_Pistol_Idle_ADS through
              AO_MM_Pistol_Idle_ADS), a rifle (MM_Rifle_Idle_Hipfire through AO_MM_Rifle_Idle_Hipfire) or a shotgun
              (MM_Shotgun_Idle_Hipfire through the rifle's aim offset), each aim offset by X = AimYaw, Y = AimPitch so
              the chest and arms follow the camera while the skis point elsewhere. Two Blend Poses by Bool pick one
              (bArmsPistol, else bArmsShotgun, else the rifle; set from the gun's ArmsKind in ABP_Skier.lisp), then the
              FullBodyAdditivePreAim montage slot plays the guns' fire recoil (Other5Combat's fire montages).
  Output:     Layered blend per bone: legs as the base, upper body from spine_01 up, mesh-space rotation
              (set by SetupAnimation.py).
#>
. (Join-Path $PSScriptRoot 'UnrealMcp.ps1')
$A = '/SKIvSKI/Animation/ABP_Skier'
$g = @{ refPath = "$A.ABP_Skier:AnimGraph" }

AddVars $A @(
	@('SkiCrouch', 'float', 'Ski', 'None', $false),
	@('AimYaw', 'float', 'Ski', 'None', $false),
	@('AimPitch', 'float', 'Ski', 'None', $false),
	@('bArmsPistol', 'bool', 'Ski', 'None', $false),
	@('bArmsShotgun', 'bool', 'Ski', 'None', $false)
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
$layer = NewNode $g 'Animation|Blends|Layeredblendperbone' -300 150
$fire = NewNode $g "Animation|Montage|Slot'DefaultSlot'" -550 450
$pickPistol = NewNode $g 'Animation|Blends|BlendPosesbybool' -800 450
$pickShotgun = NewNode $g 'Animation|Blends|BlendPosesbybool' -1050 650
$isPistol = NewNode $g 'Variables|Ski|GetArmsPistol' -1050 900
$isShotgun = NewNode $g 'Variables|Ski|GetArmsShotgun' -1300 1050
$yaw = NewNode $g 'Variables|Ski|GetAimYaw' -1800 1100
$pitch = NewNode $g 'Variables|Ski|GetAimPitch' -1800 1200
# One pose -> aim offset chain per kind of gun.
$chains = @{}
$row = 300
foreach ($kind in @(
		@('Pistol', 'MM_Pistol_Idle_ADS', 'AO_MM_Pistol_Idle_ADS'),
		@('Rifle', 'MM_Rifle_Idle_Hipfire', 'AO_MM_Rifle_Idle_Hipfire'),
		@('Shotgun', 'MM_Shotgun_Idle_Hipfire', 'AO_MM_Rifle_Idle_Hipfire'))) {
	$pose = NewNode $g "Animation|Sequences|Play'$($kind[1])'" -1800 $row
	$aim = NewNode $g "Animation|BlendSpaces|AimOffsetPlayer'$($kind[2])'" -1500 $row
	$null = Link $pose 'Pose' $aim 'BasePose'
	$null = Link $yaw 'AimYaw' $aim 'X'
	$null = Link $pitch 'AimPitch' $aim 'Y'
	$chains[$kind[0]] = $aim
	$row += 250
}

$null = Link $stand 'Pose' $legs 'A'
$null = Link $crouch 'Pose' $legs 'B'
$null = Link $crouchAmount 'SkiCrouch' $legs 'Alpha'
# Blend Poses by Bool: BlendPose_0 when true, BlendPose_1 when false.
$null = Link $chains['Shotgun'] 'Pose' $pickShotgun 'BlendPose_0'
$null = Link $chains['Rifle'] 'Pose' $pickShotgun 'BlendPose_1'
$null = Link $isShotgun 'bArmsShotgun' $pickShotgun 'bActiveValue'
$null = Link $chains['Pistol'] 'Pose' $pickPistol 'BlendPose_0'
$null = Link $pickShotgun 'Pose' $pickPistol 'BlendPose_1'
$null = Link $isPistol 'bArmsPistol' $pickPistol 'bActiveValue'
$null = Link $pickPistol 'Pose' $fire 'Source'
$null = Link $legs 'Pose' $layer 'BasePose'
$null = Link $fire 'Pose' $layer 'BlendPoses_0'
$null = Link $layer 'Pose' $root 'Result'
"anim graph wired; now run SetupAnimation.py for the layer filter and the slot name"
