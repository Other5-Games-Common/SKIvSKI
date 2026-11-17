; BP_SkiCharacter: ski movement, in Unreal MCP's Blueprint graph DSL (BlueprintTools.write_graph_dsl).
; Kept as text so the logic can be reviewed; the asset itself is binary. Rebuild with Docs/Scripts/WriteGraphs.ps1.
;
; How skiing works here (all Blueprint, and multiplayer-safe because only Add Movement Input drives the motion):
; - The skis point along SkiYaw. W turns them toward the fall line (straight downhill), S turns them away from it,
;   across the slope and on round until they point uphill (you then slide backwards). A / D steer directly.
; - Gravity pulls along the skis: Gravity * sin(slope) * cos(angle between skis and fall line), less snow friction.
;   That pull becomes Add Movement Input along the skis (or backwards when they point uphill). The Character
;   Movement component then does the rest, and it already predicts and replicates it for multiplayer:
;     * acceleration = Max Acceleration * input, and the top speed = Max Walk Speed * input, so a steeper slope or
;       skis nearer the fall line go faster;
;     * Ground Friction turns the velocity toward the skis (carving);
;     * when the pull is weaker than the speed you have (skis across the slope), Braking Deceleration slows you
;       (skidding). No pull at all (skis across, or flat snow) brakes you to a stop.

; Tune the movement component from the Ski|Tuning values. This runs on every machine, so the client's prediction and
; the server agree.
(fn SetupSkiMovement ()
  (bind cmc (Variables|Character|GetCharacterMovement))
  (Class|CharacterMovementComponent|SetMaxWalkSpeed :self cmc :MaxWalkSpeed (Variables|Ski|Tuning|GetTopSpeed))
  (Class|CharacterMovementComponent|SetMaxAcceleration :self cmc :MaxAcceleration (Variables|Ski|Tuning|GetFullInputAccel))
  ; Any input, however small, may build up to TopSpeed (otherwise the top speed would be TopSpeed x input).
  (Class|CharacterMovementComponent|SetMinAnalogWalkSpeed :self cmc :MinAnalogWalkSpeed (Variables|Ski|Tuning|GetTopSpeed))
  (Class|CharacterMovementComponent|SetGroundFriction :self cmc :GroundFriction (Variables|Ski|Tuning|GetCarveGrip))
  (Class|CharacterMovementComponent|SetBrakingDecelerationWalking :self cmc :BrakingDecelerationWalking (Variables|Ski|Tuning|GetSkidBraking))
  (Class|CharacterMovementComponent|SetUseSeparateBrakingFriction :self cmc :bUseSeparateBrakingFriction true)
  (Class|CharacterMovementComponent|SetBrakingFriction :self cmc :BrakingFriction (Variables|Ski|Tuning|GetSkidFriction))
  (Pawn|Components|CharacterMovement|SetWalkableFloorAngle :self cmc :InWalkableFloorAngle 55.0)
  ; The skis decide which way the body faces, not the camera (the camera stays free for aiming).
  (Variables|Pawn|SetUseControllerRotationYaw false)
  (bind yaw (.yaw (Transformation|GetActorRotation)))
  (Variables|Ski|State|SetSkiYaw yaw)
  (Variables|Ski|State|SetLastYaw yaw)
  (Variables|Ski|State|SetLastSentYaw yaw))

; Where the snow is under one point of the skis' footprint: Along the skis and Across them from the skier's middle (cm).
; A line down from a little above it; on a miss (in the air, off the edge) SnowFound goes false for this frame.
; On the Camera channel: the snow blocks it, but forts' logs don't (BP_SkiFort's Logs ignore it), so skis by a fort's
; wall lie on the snow, not on the logs.
(fn SnowPoint (Along Across)
  (bind yaw (.yaw (Transformation|GetActorRotation)))
  (bind forward (Math|Vector|MakeVector (Math|Trig|Cos(Degrees) yaw) (Math|Trig|Sin(Degrees) yaw) 0.0))
  (bind right (Math|Vector|MakeVector (- 0.0 (Math|Trig|Sin(Degrees) yaw)) (Math|Trig|Cos(Degrees) yaw) 0.0))
  (bind at (+ (Transformation|GetActorLocation) (+ (* forward Along) (* right Across))))
  (bind start (+ at (Math|Vector|MakeVector 0.0 0.0 60.0)))
  (bind end (- at (Math|Vector|MakeVector 0.0 0.0 260.0)))
  (bind (hit didHit) (Collision|LineTraceByChannel :Start start :End end :TraceChannel "TraceTypeQuery2" :bIgnoreSelf true))
  (bind (blocking overlap time dist loc impact normal impactNormal) (Collision|BreakHitResult hit))
  (if (not didHit)
    (Variables|Ski|State|SetSnowFound false))
  (return (select didHit impact (- at (Math|Vector|MakeVector 0.0 0.0 90.0)))))

; The snow under the skis, as a plane through four points: the corners of the skis' footprint (SnowProbeHalf ahead of
; and behind the boots, under each ski). One line straight down would follow the snow mesh's flat triangles: creeping
; across the crease between two of them, its slope snaps from one to the other and back, the skis flicker and the fall
; line jumps (a stopped skier was pushed onto the other triangle, which pushed them back). A point on the snow moves
; smoothly as you move, so a plane through four of them never snaps: over a crease it lies along it.
(fn SampleSnow ()
  (Variables|Ski|State|SetSnowFound true)
  (bind half (Variables|Ski|Tuning|GetSnowProbeHalf))
  (bind side (Variables|Ski|Tuning|GetSkiStance))
  (bind boots (Variables|Ski|Tuning|GetBindingForward))
  (bind frontLeft (CallFunction|SnowPoint :Along (+ boots half) :Across (- 0.0 side)))
  (bind frontRight (CallFunction|SnowPoint :Along (+ boots half) :Across side))
  (bind backLeft (CallFunction|SnowPoint :Along (- boots half) :Across (- 0.0 side)))
  (bind backRight (CallFunction|SnowPoint :Along (- boots half) :Across side))
  ; The plane's normal: the cross product of its two diagonals (front left to back right, back left to front right),
  ; which points up.
  (bind normal (Math|Vector|Normalize (Math|Vector|CrossProduct (- frontLeft backRight) (- frontRight backLeft))))
  (Variables|Ski|State|SetSnowNormal (select (< (.z normal) 0.0) (Math|Vector|NegateVector normal) normal))
  (Variables|Ski|State|SetSnowCentre (* (+ (+ frontLeft frontRight) (+ backLeft backRight)) 0.25)))

; How high the snow plane (SampleSnow) is at a point's X, Y.
(fn SnowHeightAt (Where)
  (bind n (Variables|Ski|State|GetSnowNormal))
  (bind c (Variables|Ski|State|GetSnowCentre))
  (return (- (.z c) (/ (+ (* (.x n) (- (.x Where) (.x c))) (* (.y n) (- (.y Where) (.y c)))) (Math|Float|Max(Float) (.z n) 0.2)))))

; Look down for the snow under the skis: its slope, and which way is straight downhill (the fall line).
(fn UpdateSlope ()
  (CallFunction|SampleSnow)
  (if (Variables|Ski|State|GetSnowFound)
    (bind snow (Variables|Ski|State|GetSnowNormal))
    (Variables|Ski|State|SetFloorNormal snow)
    ; The normal leans toward downhill: its flat (X, Y) part points down the fall line, and its length is sin(slope).
    (bind flatLength (Math|Vector|VectorLengthXY snow))
    (Variables|Ski|State|SetSlopeDegrees (Math|Trig|Asin(Degrees) flatLength))
    (Variables|Ski|State|SetOnSlope (> flatLength 0.02))
    (if (> flatLength 0.02)
      (Variables|Ski|State|SetFallLineYaw (Math|Trig|Atan2(Degrees) (.y snow) (.x snow))))
    (else
      (Variables|Ski|State|SetOnSlope false)
      (Variables|Ski|State|SetFloorNormal (Math|Vector|MakeVector 0.0 0.0 1.0)))))

; Turn the skis from the keys. Runs only on the player's own machine; the server hears the result (ServerSetSkiYaw).
; The skis' TurnScale (slalom skis turn faster, downhill skis slower) scales the turn rate.
(fn SteerSkis (DeltaSeconds)
  (bind skis (CallFunction|CurrentSkis))
  (bind step (* (* (Variables|Ski|Tuning|GetTurnRate) DeltaSeconds) (Class|BPSkiData|GetTurnScale :self skis)))
  (bind yaw (Variables|Ski|State|GetSkiYaw))
  ; A / D: steer left / right.
  (if (Variables|Ski|Input|GetHoldLeft)
    (Variables|Ski|State|SetSkiYaw (- (Variables|Ski|State|GetSkiYaw) step)))
  (if (Variables|Ski|Input|GetHoldRight)
    (Variables|Ski|State|SetSkiYaw (+ (Variables|Ski|State|GetSkiYaw) step)))
  (if (Variables|Ski|State|GetOnSlope)
    ; How far the skis point away from straight downhill, -180..180 (positive: turned to the right of it).
    (bind off (Math|Rotator|NormalizeAxis (- (Variables|Ski|State|GetSkiYaw) (Variables|Ski|State|GetFallLineYaw))))
    ; W: turn toward the fall line, the short way.
    (if (Variables|Ski|Input|GetHoldDownhill)
      (Variables|Ski|State|SetSkiYaw (- (Variables|Ski|State|GetSkiYaw) (Math|Float|Clamp(Float) off (- step) step))))
    ; S: turn away from the fall line on the side the skis are already on. Stop for a moment when they are across
    ; the slope (that's the quickest stop), then keep turning until they point straight uphill.
    (if (Variables|Ski|Input|GetHoldSlow)
      (bind side (select (>= off 0.0) 1.0 -1.0))
      (bind away (Math|Float|Absolute(Float) off))
      (if (< away 90.0)
        (Variables|Ski|State|SetAcrossHoldLeft (Variables|Ski|Tuning|GetAcrossHoldSeconds))
        (Variables|Ski|State|SetSkiYaw (+ (Variables|Ski|State|GetFallLineYaw) (* side (Math|Float|Min(Float) (+ away step) 90.0))))
        (elif (> (Variables|Ski|State|GetAcrossHoldLeft) 0.0)
          (Variables|Ski|State|SetAcrossHoldLeft (- (Variables|Ski|State|GetAcrossHoldLeft) DeltaSeconds))
          (else
            (Variables|Ski|State|SetSkiYaw (+ (Variables|Ski|State|GetFallLineYaw) (* side (Math|Float|Min(Float) (+ away step) 180.0)))))))))
  (Variables|Ski|State|SetSkiYaw (Math|Rotator|NormalizeAxis (Variables|Ski|State|GetSkiYaw)))
  (Transformation|SetActorRotation :NewRotation (Math|Rotator|MakeRotator :Yaw (Variables|Ski|State|GetSkiYaw)))
  ; Tell the server when the skis turned (more than half a degree), so everyone else sees it.
  (if (and (not (Networking|HasAuthority))
           (> (Math|Float|Absolute(Float) (Math|Rotator|NormalizeAxis (- (Variables|Ski|State|GetSkiYaw) (Variables|Ski|State|GetLastSentYaw)))) 0.5))
    (Variables|Ski|State|SetLastSentYaw (Variables|Ski|State|GetSkiYaw))
    (CallFunction|ServerSetSkiYaw :NewYaw (Variables|Ski|State|GetSkiYaw))))

; Gravity on the slope, as on real skis (see the top of this file). Runs on the player's own machine; Character
; Movement sends the resulting input to the server, which moves the skier the same way.
; - Along the skis: gravity's pull down the slope (g sin(slope)) times cos(skis to fall line), less the snow friction
;   (SnowFriction x g cos(slope), the shop's ski wax lowers it). Skis down the fall line: almost no friction.
; - Across the skis: the edges hold (up to EdgeGrip x g cos(slope)), so skis across the slope keep you standing still,
;   until the slope is steep enough that its sideways pull beats the edges: then you side-slip down.
; - The pull is the input's size (FullInputAccel = input 1); Min Analog Walk Speed is TopSpeed, so a small pull still
;   builds up speed (it used to cap the speed at TopSpeed x input, which made skiing slow).
(fn PushDownSlope ()
  (bind skis (CallFunction|CurrentSkis))
  (bind friction (CallFunction|GetSnowFriction))
  (bind yaw (Variables|Ski|State|GetSkiYaw))
  (bind skiForward (Math|Vector|MakeVector (Math|Trig|Cos(Degrees) yaw) (Math|Trig|Sin(Degrees) yaw) 0.0))
  (bind fallYaw (Variables|Ski|State|GetFallLineYaw))
  (bind fallDir (Math|Vector|MakeVector (Math|Trig|Cos(Degrees) fallYaw) (Math|Trig|Sin(Degrees) fallYaw) 0.0))
  (bind slope (Variables|Ski|State|GetSlopeDegrees))
  (bind gravity (Variables|Ski|Tuning|GetGravity))
  (bind full (Variables|Ski|Tuning|GetFullInputAccel))
  (bind off (- yaw fallYaw))
  ; cm/s^2: down the slope, and pressing the skis into the snow.
  (bind downhill (select (Variables|Ski|State|GetOnSlope) (* gravity (Math|Trig|Sin(Degrees) slope)) 0.0))
  (bind pressing (* gravity (Math|Trig|Cos(Degrees) slope)))
  ; Along the skis: positive pulls them forward, negative (pointing uphill) backwards.
  (bind along (* downhill (Math|Trig|Cos(Degrees) off)))
  (bind alongPull (- (Math|Float|Absolute(Float) along) (* friction pressing)))
  (if (> alongPull 0.0)
    (Pawn|Input|AddMovementInput :WorldDirection (select (>= along 0.0) skiForward (Math|Vector|NegateVector skiForward)) :ScaleValue (Math|Float|Clamp(Float) (/ alongPull full) 0.0 1.0)))
  ; Across the skis: the edges hold until the slope beats them (the skis' GripScale: slalom skis hold better).
  (bind acrossPull (- (Math|Float|Absolute(Float) (* downhill (Math|Trig|Sin(Degrees) off))) (* (* (Variables|Ski|Tuning|GetEdgeGrip) (Class|BPSkiData|GetGripScale :self skis)) pressing)))
  (if (> acrossPull 0.0)
    (Pawn|Input|AddMovementInput :WorldDirection (Math|Vector|Normalize (- fallDir (* skiForward (Math|Vector|DotProduct fallDir skiForward)))) :ScaleValue (Math|Float|Clamp(Float) (/ acrossPull full) 0.0 1.0)))
  ; Nearly flat (the finish, the lobby): W skates forward, up to SkateSpeed.
  (if (and (and (Variables|Ski|Input|GetHoldDownhill) (< alongPull (* (Variables|Ski|Tuning|GetSkateInput) full)))
           (< (Math|Vector|VectorLengthXY (Transformation|GetVelocity)) (Variables|Ski|Tuning|GetSkateSpeed)))
    (Pawn|Input|AddMovementInput :WorldDirection skiForward :ScaleValue (Variables|Ski|Tuning|GetSkateInput))))

; How hard the snow slows the skier when gravity isn't pulling them on (Character Movement's braking). Gliding along
; the skis only the snow friction slows you; the more the skis are sideways to where you're going, the harder they
; skid you to a stop. Runs on every machine, so the server's copy of the movement brakes the same way.
; The skis on (BP_SkiData) scale it all: top speed (SpeedScale), carving grip (GripScale), how hard a skid stops you
; (BrakeScale), and the snow friction (FrictionScale, with the player's wax, in GetSnowFriction).
(fn UpdateGlide ()
  (bind cmc (Variables|Character|GetCharacterMovement))
  (bind skis (CallFunction|CurrentSkis))
  (bind friction (CallFunction|GetSnowFriction))
  (bind top (* (Variables|Ski|Tuning|GetTopSpeed) (Class|BPSkiData|GetSpeedScale :self skis)))
  (bind brake (Class|BPSkiData|GetBrakeScale :self skis))
  (Class|CharacterMovementComponent|SetMaxWalkSpeed :self cmc :MaxWalkSpeed top)
  (Class|CharacterMovementComponent|SetMinAnalogWalkSpeed :self cmc :MinAnalogWalkSpeed top)
  (Class|CharacterMovementComponent|SetGroundFriction :self cmc :GroundFriction (* (Variables|Ski|Tuning|GetCarveGrip) (Class|BPSkiData|GetGripScale :self skis)))
  (bind vel (Transformation|GetVelocity))
  (bind speed (Math|Vector|VectorLengthXY vel))
  (bind yaw (Variables|Ski|State|GetSkiYaw))
  ; sin of the angle between the skis and the motion: 0 gliding straight, 1 fully sideways. (A select works out both
  ; sides, so the division never sees a speed of 0.)
  (bind sideways (select (> speed 10.0) (Math|Float|Absolute(Float) (/ (- (* (.x vel) (Math|Trig|Sin(Degrees) yaw)) (* (.y vel) (Math|Trig|Cos(Degrees) yaw))) (Math|Float|Max(Float) speed 1.0))) 0.0))
  (bind pressing (* (Variables|Ski|Tuning|GetGravity) (Math|Trig|Cos(Degrees) (Variables|Ski|State|GetSlopeDegrees))))
  (Class|CharacterMovementComponent|SetBrakingDecelerationWalking :self cmc :BrakingDecelerationWalking (+ (* friction pressing) (* (* sideways (Variables|Ski|Tuning|GetSkidBraking)) brake)))
  (Class|CharacterMovementComponent|SetBrakingFriction :self cmc :BrakingFriction (* (* sideways (Variables|Ski|Tuning|GetSkidFriction)) brake)))

; Where the movement is worked out (this player's machine and the server): keep the velocity to how far the skier
; really moved last frame. Pressed against something that won't let them through (a fort's front wall, with gravity
; and the skis pulling into it), Character Movement went on adding speed while the skier stood still: the HUD showed
; 100 km/h, the crouch went deep, and the skier would have shot off at that speed once free. Moving freely the two
; are the same, so this only acts when stuck.
(fn MatchVelocityToMove (DeltaSeconds)
  (bind here (Transformation|GetActorLocation))
  (bind moved (/ (Math|Vector|VectorLengthXY (- here (Variables|Ski|State|GetLastPlace))) (Math|Float|Max(Float) DeltaSeconds 0.001)))
  (Variables|Ski|State|SetLastPlace here)
  (bind cmc (Variables|Character|GetCharacterMovement))
  (bind vel (Class|MovementComponent|GetVelocity :self cmc))
  (bind speed (Math|Vector|VectorLengthXY vel))
  (if (and (or (Pawn|IsLocallyControlled) (Networking|HasAuthority)) (and (Pawn|Components|CharacterMovement|IsWalking :self cmc) (> speed (+ (* moved 1.5) 150.0))))
    (bind keep (/ moved (Math|Float|Max(Float) speed 1.0)))
    (Class|MovementComponent|SetVelocity :self cmc :Velocity (Math|Vector|MakeVector (* (.x vel) keep) (* (.y vel) keep) (.z vel)))))

; Looks only: lean the body into turns and lay the skis flat on the snow. Runs on every machine.
(fn LeanIntoTurn (DeltaSeconds)
  (bind yaw (.yaw (Transformation|GetActorRotation)))
  (bind yawRate (/ (Math|Rotator|NormalizeAxis (- yaw (Variables|Ski|State|GetLastYaw))) (Math|Float|Max(Float) DeltaSeconds 0.001)))
  (Variables|Ski|State|SetLastYaw yaw)
  (bind speed (Math|Vector|VectorLength (Transformation|GetVelocity)))
  (Variables|Ski|State|SetSpeedKmh (* speed 0.036))
  (bind maxLean (Variables|Ski|Tuning|GetMaxLean))
  (bind target (Math|Float|Clamp(Float) (* (* yawRate speed) 0.00025) (- maxLean) maxLean))
  (Variables|Ski|State|SetLean (Math|Interpolation|FInterpTo (Variables|Ski|State|GetLean) target DeltaSeconds 6.0))
  (Transformation|SetRelativeRotation :self (Variables|Character|GetMesh) :NewRotation (Math|Rotator|MakeRotator :Roll (Variables|Ski|State|GetLean) :Yaw -90.0))
  (CallFunction|PlaceSkis :DeltaSeconds DeltaSeconds))

; Looks only: lay each ski on the snow (SampleSnow's plane), under the boots. The skis tilt with the plane, eased
; (SkiSettleSpeed) so a bump doesn't jerk them, and each sits at the plane's height under its own middle, so neither
; floats nor sinks on a slope across the skis. ABP_Skier then puts the feet on the skis' bindings. Runs on every machine.
(fn PlaceSkis (DeltaSeconds)
  (Variables|Ski|State|SetSkiNormal (Math|Vector|Normalize (Math|Interpolation|VInterpTo (Variables|Ski|State|GetSkiNormal) (Variables|Ski|State|GetFloorNormal) DeltaSeconds (Variables|Ski|Tuning|GetSkiSettleSpeed))))
  (bind localNormal (Math|Transform|InverseTransformDirection (Transformation|GetActorTransform) (Variables|Ski|State|GetSkiNormal)))
  (bind skiRot (Math|Rotator|MakeRotfromZX localNormal (Math|Vector|MakeVector 1.0 0.0 0.0)))
  (bind boots (Variables|Ski|Tuning|GetBindingForward))
  (bind side (Variables|Ski|Tuning|GetSkiStance))
  ; Below the capsule's middle: on the snow when it's found (never more than 10 cm off where it stands), else where
  ; it would be on flat snow. SkiLift above the plane: the snow's look (the winter art) shows its surface a little above
  ; the collision the traces hit, and would poke through the skis.
  (bind here (- (.z (Transformation|GetActorLocation)) (Variables|Ski|Tuning|GetSkiLift)))
  (bind leftAt (Math|Transform|TransformLocation (Transformation|GetActorTransform) (Math|Vector|MakeVector boots (- 0.0 side) 0.0)))
  (bind rightAt (Math|Transform|TransformLocation (Transformation|GetActorTransform) (Math|Vector|MakeVector boots side 0.0)))
  (bind found (Variables|Ski|State|GetSnowFound))
  (bind leftZ (select found (Math|Float|Clamp(Float) (- (CallFunction|SnowHeightAt :Where leftAt) here) -100.5 -80.5) -90.5))
  (bind rightZ (select found (Math|Float|Clamp(Float) (- (CallFunction|SnowHeightAt :Where rightAt) here) -100.5 -80.5) -90.5))
  (Transformation|SetRelativeLocationAndRotation :self (Variables|Default|GetSkiLeft) :NewLocation (Math|Vector|MakeVector boots (- 0.0 side) leftZ) :NewRotation skiRot)
  (Transformation|SetRelativeLocationAndRotation :self (Variables|Default|GetSkiRight) :NewLocation (Math|Vector|MakeVector boots side rightZ) :NewRotation skiRot))

; For tests and tuning: log the ski state (the Other5 test runner calls it with "call pawn DebugReport").
(fn DebugReport ()
  (bind a (Utilities|String|Append "SKI| km/h " (Utilities|String|ToString(Float) (Variables|Ski|State|GetSpeedKmh))))
  (bind b (Utilities|String|Append a (Utilities|String|Append " skiYaw " (Utilities|String|ToString(Float) (Variables|Ski|State|GetSkiYaw)))))
  (bind c (Utilities|String|Append b (Utilities|String|Append " fallLine " (Utilities|String|ToString(Float) (Variables|Ski|State|GetFallLineYaw)))))
  (bind d (Utilities|String|Append c (Utilities|String|Append " slope " (Utilities|String|ToString(Float) (Variables|Ski|State|GetSlopeDegrees)))))
  (bind e (Utilities|String|Append d (Utilities|String|Append " at " (Utilities|String|ToString(Vector) (Transformation|GetActorLocation)))))
  (Development|PrintString :InString e :Duration 5.0))

; The friction between this skier's skis and the snow: their wax's (BP_SkiPlayerState SnowFriction, from the store),
; or the character's SnowFriction before the player state arrives, times the skis' FrictionScale (downhill skis glide).
(fn GetSnowFriction ()
  (bind skis (CallFunction|CurrentSkis))
  (bind scale (Class|BPSkiData|GetFrictionScale :self skis))
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (return (* (Class|BPSkiPlayerState|GetSnowFriction :self ski) scale)))
    (:"Is Not Valid"
      (return (* (Variables|Ski|Tuning|GetSnowFriction) scale)))))
