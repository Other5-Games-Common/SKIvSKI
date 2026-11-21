<#
.SYNOPSIS
  Rebuilds ABP_Skier's Anim Graph over Unreal MCP (the editor must be open). The DSL writes event graphs only, so
  the anim nodes are made and wired here. Rerunnable: it clears the Anim Graph (except the Output Pose) first.

  Legs:       on skis: both feet side by side on their skis, pointing along them, knees bent forward. The mannequin's
              poses all stand staggered with the feet turned out (even MM_Idle: the right foot 30 cm back and 47
              degrees out), so the legs are placed, not played: MM_Idle in component space, the pelvis lowered 5 cm
              (PelvisDown) and up to 28 cm more as you crouch (PelvisCrouch, Alpha = SkiCrouch, from the speed in the
              event graph, Docs/Graphs/ABP_Skier.lisp), then Two Bone IK puts each foot on its ski's binding (FootLeftLocation /
              FootRightLocation, worked out from the skis in ABP_Skier.lisp; mesh +Y is forward, mesh +X the skier's left) with the knee aimed forward, and two
              Transform (Modify) Bone nodes turn the feet to point along the skis (their idle rotation turned about
              Z until the toes point down mesh +Y: worked out from MM_Idle's foot and ball bones).
  Upper body: how the gun in hand is held, from Other5Characters' poses: a pistol (MM_Pistol_Idle_ADS through
              AO_MM_Pistol_Idle_ADS), a rifle or a shotgun (both MF_Rifle_Idle_ADS, the steady
              pose the rifle's aim offset AO_MM_Rifle_Idle_Hipfire is authored on; never MM_Rifle_Idle_Hipfire or
              MM_Shotgun_Idle_Hipfire: those are 0.8 s loops that swing the hands round and round, the "wrist twist"), each aim offset by X = AimYaw, Y = AimPitch so
              the chest and arms follow the camera while the skis point elsewhere. Two Blend Poses by Bool pick one
              (bArmsPistol, else bArmsShotgun, else the rifle; set from the gun's ArmsKind in ABP_Skier.lisp), then the
              FullBodyAdditivePreAim montage slot plays the guns' fire recoil (Other5Combat's fire montages) and the
              UpperBody slot their reloads (Other5Combat's reload montages are on UpperBody).
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
	@('bArmsShotgun', 'bool', 'Ski', 'None', $false),
	@('LeanDegrees', 'float', 'Ski', 'None', $true),
	# The feet on the skis' bindings (ABP_Skier.lisp works them out every frame; defaults in SetupAnimation.py).
	@('FootLeftLocation', 'Vector', 'Ski', 'None', $false),
	@('FootRightLocation', 'Vector', 'Ski', 'None', $false),
	@('FootLeftRotation', 'Rotator', 'Ski', 'None', $false),
	@('FootRightRotation', 'Rotator', 'Ski', 'None', $false),
	@('FootLeftBase', 'Rotator', 'Ski', 'None', $true),
	@('FootRightBase', 'Rotator', 'Ski', 'None', $true),
	@('AnkleHeight', 'float', 'Ski', 'None', $true),
	@('AnkleBack', 'float', 'Ski', 'None', $true),
	@('SoleHeight', 'float', 'Ski', 'None', $true)
)
Compile $A | Out-Null

# Clear the graph, keeping the Output Pose.
$nodes = (Mcp-Call $script:BP 'find_nodes' @{ graph = $g; title = '' } | ConvertFrom-Json).returnValue
foreach ($n in $nodes) { if ($n.refPath -notmatch 'AnimGraphNode_Root') { $null = Mcp-Call $script:BP 'delete_node' @{ node = $n } } }
$root = (Mcp-Call $script:BP 'find_nodes' @{ graph = $g; title = '' } | ConvertFrom-Json).returnValue | Select-Object -First 1

$idle = NewNode $g "Animation|Sequences|Play'MM_Idle'" -2600 -100
$toComponent = NewNode $g 'Animation|ConvertSpaces|LocalToComponent' -2350 -100
$pelvisDown = NewNode $g 'Animation|SkeletalControls|Transform(Modify)Bone' -2150 -100
$pelvisCrouch = NewNode $g 'Animation|SkeletalControls|Transform(Modify)Bone' -1900 -100
$crouchAmount = NewNode $g 'Variables|Ski|GetSkiCrouch' -2100 150
$ikLeft = NewNode $g 'Animation|SkeletalControls|TwoBoneIK' -1650 -100
$ikRight = NewNode $g 'Animation|SkeletalControls|TwoBoneIK' -1400 -100
$footLeft = NewNode $g 'Animation|SkeletalControls|Transform(Modify)Bone' -1150 -100
$footRight = NewNode $g 'Animation|SkeletalControls|Transform(Modify)Bone' -900 -100
$legs = NewNode $g 'Animation|ConvertSpaces|ComponentToLocal' -650 -100
$layer = NewNode $g 'Animation|Blends|Layeredblendperbone' -300 150
# After the layers: the spine leans forward as you crouch (the aim offset lifts the arms and gun by as much, in
# ABP_Skier.lisp, so the aim holds).
$curlIn = NewNode $g 'Animation|ConvertSpaces|LocalToComponent' -50 150
$curl1 = NewNode $g 'Animation|SkeletalControls|Transform(Modify)Bone' 200 150
$curl2 = NewNode $g 'Animation|SkeletalControls|Transform(Modify)Bone' 450 150
$curl3 = NewNode $g 'Animation|SkeletalControls|Transform(Modify)Bone' 700 150
$curlOut = NewNode $g 'Animation|ConvertSpaces|ComponentToLocal' 950 150
$curlAmount = NewNode $g 'Variables|Ski|GetSkiCrouch' 200 450
$fire = NewNode $g "Animation|Montage|Slot'DefaultSlot'" -650 450
$reload = NewNode $g "Animation|Montage|Slot'DefaultSlot'" -450 450
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
		@('Rifle', 'MF_Rifle_Idle_ADS', 'AO_MM_Rifle_Idle_Hipfire'),
		@('Shotgun', 'MF_Rifle_Idle_ADS', 'AO_MM_Rifle_Idle_Hipfire'))) {
	$pose = NewNode $g "Animation|Sequences|Play'$($kind[1])'" -1800 $row
	$aim = NewNode $g "Animation|BlendSpaces|AimOffsetPlayer'$($kind[2])'" -1500 $row
	$null = Link $pose 'Pose' $aim 'BasePose'
	$null = Link $yaw 'AimYaw' $aim 'X'
	$null = Link $pitch 'AimPitch' $aim 'Y'
	$chains[$kind[0]] = $aim
	$row += 250
}

# Legs: idle -> component space -> pelvis down (always) -> pelvis down more (Alpha = SkiCrouch) -> left / right foot IK
# -> left / right foot turned along the skis -> local space.
$null = Link $idle 'Pose' $toComponent 'LocalPose'
$null = Link $toComponent 'ComponentPose' $pelvisDown 'ComponentPose'
$null = Link $pelvisDown 'Pose' $pelvisCrouch 'ComponentPose'
$null = Link $crouchAmount 'SkiCrouch' $pelvisCrouch 'Alpha'
$null = Link $pelvisCrouch 'Pose' $ikLeft 'ComponentPose'
$null = Link $ikLeft 'Pose' $ikRight 'ComponentPose'
$null = Link $ikRight 'Pose' $footLeft 'ComponentPose'
$null = Link $footLeft 'Pose' $footRight 'ComponentPose'
$null = Link $footRight 'Pose' $legs 'ComponentPose'
# Their numbers (component space, cm and degrees; pins, so set here). The bones and the modes are SetupAnimation.py's.
$PELVIS_CROUCH = '0.0,-10.0,-34.0'
# Spine lean at full crouch: spine_01 to spine_03 each turn CURL degrees about the mesh's sideways axis (component
# space, rotator Roll: +Roll tips up toward mesh +Y, forward). Not about each bone's own axis: on the mannequin that's
# tilted ~23 degrees, so the lean also tipped the torso right, and the gun aimed low to the right and high to the left.
# ABP_Skier.lisp adds the lean (LeanDegrees x SkiCrouch x cos AimYaw) to the aim offset's pitch, so the arms and gun come
# back up by what the lean tips them where the player aims.
$CURL = 8.0
function SetPin($node, $name, $value) { $null = Mcp-Call $script:BP 'set_pin_value' @{ pin = (PinId $node $name 'in'); value = $value } }
SetPin $pelvisDown 'Translation' '0.0,0.0,-5.0'
# Crouching sits the hips back as well as down (mesh -Y is back), so the knees go forward over the boots.
SetPin $pelvisCrouch 'Translation' $PELVIS_CROUCH
SetPin $ikLeft 'JointTargetLocation' '15.0,60.0,50.0'
SetPin $ikRight 'JointTargetLocation' '-15.0,60.0,50.0'
# The feet go where the skis' bindings are (ABP_Skier.lisp: FootLeftLocation / FootRightLocation for the IK,
# FootLeftRotation / FootRightRotation for the foot turns; their defaults, used in the editor's preview, are the flat
# stance, and MM_Idle's foot rotations turned about Z so the toes point down mesh +Y).
$null = Link (NewNode $g 'Variables|Ski|GetFootLeftLocation' -1650 150) 'FootLeftLocation' $ikLeft 'EffectorLocation'
$null = Link (NewNode $g 'Variables|Ski|GetFootRightLocation' -1400 150) 'FootRightLocation' $ikRight 'EffectorLocation'
$null = Link (NewNode $g 'Variables|Ski|GetFootLeftRotation' -1150 150) 'FootLeftRotation' $footLeft 'Rotation'
$null = Link (NewNode $g 'Variables|Ski|GetFootRightRotation' -900 150) 'FootRightRotation' $footRight 'Rotation'
foreach ($c in $curl1, $curl2, $curl3) { SetPin $c 'Rotation' "0.0,0.0,$CURL" }
# Which node is which, for SetupAnimation.py (bones, spaces, modes, the layers and the slots' names). By their exact
# names: a guess by number found nodes an earlier rebuild had deleted (still in memory) and set those up instead.
$which = @{ PelvisDown = $pelvisDown.refPath; PelvisCrouch = $pelvisCrouch.refPath; IkLeft = $ikLeft.refPath; IkRight = $ikRight.refPath;
	FootLeft = $footLeft.refPath; FootRight = $footRight.refPath; FireSlot = $fire.refPath; ReloadSlot = $reload.refPath;
	LayerBlend = $layer.refPath; Curl1 = $curl1.refPath; Curl2 = $curl2.refPath; Curl3 = $curl3.refPath; LeanDegrees = 3 * $CURL }
$whichFile = Join-Path ([IO.Path]::GetTempPath()) 'SKIvSKI\AnimNodes.json'
New-Item -ItemType Directory -Force (Split-Path $whichFile) | Out-Null
$which | ConvertTo-Json | Set-Content -Encoding utf8 $whichFile
# Blend Poses by Bool: BlendPose_0 when true, BlendPose_1 when false.
$null = Link $chains['Shotgun'] 'Pose' $pickShotgun 'BlendPose_0'
$null = Link $chains['Rifle'] 'Pose' $pickShotgun 'BlendPose_1'
$null = Link $isShotgun 'bArmsShotgun' $pickShotgun 'bActiveValue'
$null = Link $chains['Pistol'] 'Pose' $pickPistol 'BlendPose_0'
$null = Link $pickShotgun 'Pose' $pickPistol 'BlendPose_1'
$null = Link $isPistol 'bArmsPistol' $pickPistol 'bActiveValue'
$null = Link $pickPistol 'Pose' $fire 'Source'
$null = Link $fire 'Pose' $reload 'Source'
$null = Link $legs 'Pose' $layer 'BasePose'
$null = Link $reload 'Pose' $layer 'BlendPoses_0'
$null = Link $layer 'Pose' $curlIn 'LocalPose'
$null = Link $curlIn 'ComponentPose' $curl1 'ComponentPose'
$null = Link $curl1 'Pose' $curl2 'ComponentPose'
$null = Link $curl2 'Pose' $curl3 'ComponentPose'
$null = Link $curl3 'Pose' $curlOut 'ComponentPose'
foreach ($c in $curl1, $curl2, $curl3) { $null = Link $curlAmount 'SkiCrouch' $c 'Alpha' }
$null = Link $curlOut 'Pose' $root 'Result'
"anim graph wired; now run SetupAnimation.py for the layer filter, the bones and the slot names"
