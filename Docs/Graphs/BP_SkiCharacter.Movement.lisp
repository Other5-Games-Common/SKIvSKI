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

; Look down for the snow under the skis: its slope, and which way is straight downhill (the fall line).
(fn UpdateSlope ()
  (bind start (Transformation|GetActorLocation))
  (bind end (- start (Math|Vector|MakeVector 0.0 0.0 250.0)))
  (bind (hit didHit) (Collision|LineTraceByChannel :Start start :End end :TraceChannel "TraceTypeQuery1" :bIgnoreSelf true))
  (bind (blocking overlap time dist loc impact normal impactNormal) (Collision|BreakHitResult hit))
  (if didHit
    (Variables|Ski|State|SetFloorNormal impactNormal)
    ; The normal leans toward downhill: its flat (X, Y) part points down the fall line, and its length is sin(slope).
    (bind flatLength (Math|Vector|VectorLengthXY impactNormal))
    (Variables|Ski|State|SetSlopeDegrees (Math|Trig|Asin(Degrees) flatLength))
    (Variables|Ski|State|SetOnSlope (> flatLength 0.02))
    (if (> flatLength 0.02)
      (Variables|Ski|State|SetFallLineYaw (Math|Trig|Atan2(Degrees) (.y impactNormal) (.x impactNormal))))
    (else
      (Variables|Ski|State|SetOnSlope false)
      (Variables|Ski|State|SetFloorNormal (Math|Vector|MakeVector 0.0 0.0 1.0)))))

; Turn the skis from the keys. Runs only on the player's own machine; the server hears the result (ServerSetSkiYaw).
(fn SteerSkis (DeltaSeconds)
  (bind step (* (Variables|Ski|Tuning|GetTurnRate) DeltaSeconds))
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
  (bind alongPull (- (Math|Float|Absolute(Float) along) (* (CallFunction|GetSnowFriction) pressing)))
  (if (> alongPull 0.0)
    (Pawn|Input|AddMovementInput :WorldDirection (select (>= along 0.0) skiForward (Math|Vector|NegateVector skiForward)) :ScaleValue (Math|Float|Clamp(Float) (/ alongPull full) 0.0 1.0)))
  ; Across the skis: the edges hold until the slope beats them.
  (bind acrossPull (- (Math|Float|Absolute(Float) (* downhill (Math|Trig|Sin(Degrees) off))) (* (Variables|Ski|Tuning|GetEdgeGrip) pressing)))
  (if (> acrossPull 0.0)
    (Pawn|Input|AddMovementInput :WorldDirection (Math|Vector|Normalize (- fallDir (* skiForward (Math|Vector|DotProduct fallDir skiForward)))) :ScaleValue (Math|Float|Clamp(Float) (/ acrossPull full) 0.0 1.0)))
  ; Nearly flat (the finish, the lobby): W skates forward, up to SkateSpeed.
  (if (and (and (Variables|Ski|Input|GetHoldDownhill) (< alongPull (* (Variables|Ski|Tuning|GetSkateInput) full)))
           (< (Math|Vector|VectorLengthXY (Transformation|GetVelocity)) (Variables|Ski|Tuning|GetSkateSpeed)))
    (Pawn|Input|AddMovementInput :WorldDirection skiForward :ScaleValue (Variables|Ski|Tuning|GetSkateInput))))

; How hard the snow slows the skier when gravity isn't pulling them on (Character Movement's braking). Gliding along
; the skis only the snow friction slows you; the more the skis are sideways to where you're going, the harder they
; skid you to a stop. Runs on every machine, so the server's copy of the movement brakes the same way.
(fn UpdateGlide ()
  (bind cmc (Variables|Character|GetCharacterMovement))
  (bind vel (Transformation|GetVelocity))
  (bind speed (Math|Vector|VectorLengthXY vel))
  (bind yaw (Variables|Ski|State|GetSkiYaw))
  ; sin of the angle between the skis and the motion: 0 gliding straight, 1 fully sideways. (A select works out both
  ; sides, so the division never sees a speed of 0.)
  (bind sideways (select (> speed 10.0) (Math|Float|Absolute(Float) (/ (- (* (.x vel) (Math|Trig|Sin(Degrees) yaw)) (* (.y vel) (Math|Trig|Cos(Degrees) yaw))) (Math|Float|Max(Float) speed 1.0))) 0.0))
  (bind pressing (* (Variables|Ski|Tuning|GetGravity) (Math|Trig|Cos(Degrees) (Variables|Ski|State|GetSlopeDegrees))))
  (Class|CharacterMovementComponent|SetBrakingDecelerationWalking :self cmc :BrakingDecelerationWalking (+ (* (CallFunction|GetSnowFriction) pressing) (* sideways (Variables|Ski|Tuning|GetSkidBraking))))
  (Class|CharacterMovementComponent|SetBrakingFriction :self cmc :BrakingFriction (* sideways (Variables|Ski|Tuning|GetSkidFriction))))

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
  (bind localNormal (Math|Transform|InverseTransformDirection (Transformation|GetActorTransform) (Variables|Ski|State|GetFloorNormal)))
  (bind skiRot (Math|Rotator|MakeRotfromZX localNormal (Math|Vector|MakeVector 1.0 0.0 0.0)))
  (Transformation|SetRelativeRotation :self (Variables|Default|GetSkiLeft) :NewRotation skiRot)
  (Transformation|SetRelativeRotation :self (Variables|Default|GetSkiRight) :NewRotation skiRot))

; For tests and tuning: log the ski state (the Other5 test runner calls it with "call pawn DebugReport").
(fn DebugReport ()
  (bind a (Utilities|String|Append "SKI| km/h " (Utilities|String|ToString(Float) (Variables|Ski|State|GetSpeedKmh))))
  (bind b (Utilities|String|Append a (Utilities|String|Append " skiYaw " (Utilities|String|ToString(Float) (Variables|Ski|State|GetSkiYaw)))))
  (bind c (Utilities|String|Append b (Utilities|String|Append " fallLine " (Utilities|String|ToString(Float) (Variables|Ski|State|GetFallLineYaw)))))
  (bind d (Utilities|String|Append c (Utilities|String|Append " slope " (Utilities|String|ToString(Float) (Variables|Ski|State|GetSlopeDegrees)))))
  (bind e (Utilities|String|Append d (Utilities|String|Append " at " (Utilities|String|ToString(Vector) (Transformation|GetActorLocation)))))
  (Development|PrintString :InString e :Duration 5.0))

; The friction between this skier's skis and the snow: the player's own (BP_SkiPlayerState SnowFriction, which the
; shop's ski wax will lower between runs), or the character's SnowFriction before the player state arrives.
(fn GetSnowFriction ()
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (return (Class|BPSkiPlayerState|GetSnowFriction :self ski)))
    (:"Is Not Valid"
      (return (Variables|Ski|Tuning|GetSnowFriction)))))
