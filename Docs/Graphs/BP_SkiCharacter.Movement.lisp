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

; Gravity's pull along the skis becomes movement input (see the top of this file).
(fn PushDownSlope ()
  (bind yaw (Variables|Ski|State|GetSkiYaw))
  (bind skiForward (Math|Vector|MakeVector (Math|Trig|Cos(Degrees) yaw) (Math|Trig|Sin(Degrees) yaw) 0.0))
  (bind slope (Variables|Ski|State|GetSlopeDegrees))
  (bind gravity (Variables|Ski|Tuning|GetGravity))
  (bind off (- yaw (Variables|Ski|State|GetFallLineYaw)))
  ; cm/s^2 along the skis: positive pulls them forward, negative (pointing uphill) pulls them backwards.
  (bind along (select (Variables|Ski|State|GetOnSlope) (* (* gravity (Math|Trig|Sin(Degrees) slope)) (Math|Trig|Cos(Degrees) off)) 0.0))
  (bind grip (* (* (Variables|Ski|Tuning|GetSnowFriction) gravity) (Math|Trig|Cos(Degrees) slope)))
  (bind pull (- (Math|Float|Absolute(Float) along) grip))
  (bind input (Math|Float|Clamp(Float) (/ pull (Variables|Ski|Tuning|GetFullInputAccel)) 0.0 1.0))
  (if (and (Variables|Ski|Input|GetHoldDownhill) (< input (Variables|Ski|Tuning|GetSkateInput)))
    ; Nearly flat (the finish, the lobby): W skates forward slowly.
    (Pawn|Input|AddMovementInput :WorldDirection skiForward :ScaleValue (Variables|Ski|Tuning|GetSkateInput))
    (elif (> input 0.0)
      (Pawn|Input|AddMovementInput :WorldDirection (select (>= along 0.0) skiForward (Math|Vector|NegateVector skiForward)) :ScaleValue input))))

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
