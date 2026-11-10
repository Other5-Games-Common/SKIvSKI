; BP_SkiCharacter: paintball guns, teams and round placement, in Unreal MCP's Blueprint graph DSL.
; Kept as text so the logic can be reviewed; the asset itself is binary.
;
; Firing, multiplayer-friendly: the shooter's machine spawns its own balls straight away (no waiting for the
; server), and sends ServerFire with the muzzle, the direction and a random seed. The server spawns the same balls
; (these are the ones that score) and sends MulticastFire, so every other machine spawns them too. The seed makes a
; spread shot's pellets go the same way everywhere. Paintballs aren't replicated actors at all.
;
; RPC events (set in each event's Details: Replicates):
;   ServerFire (Run on Server, Reliable), MulticastFire (Multicast), ServerNextGun /
;   ServerChangeDifficulty (Run on Server, Reliable), ServerSetSkiYaw (Run on Server, unreliable; Movement file).

; The gun in hand: one of the Guns data assets (Q cycles through them).
(fn GetCurrentGun ()
  (bind guns (Variables|Paint|GetGuns))
  (return (Utilities|Array|Get(acopy) guns (Math|Integer|Clamp(Integer) (Variables|Paint|GetGunIndex) 0 (- (Utilities|Array|Length guns) 1)))))

; GunIndex replicates to everyone; each machine then shows that gun's mesh in the skier's hand.
(fn OnRep_GunIndex ()
  (CallFunction|ShowGun))

(fn ShowGun ()
  (Components|StaticMesh|SetStaticMesh :self (Variables|Default|GetGunMesh) :NewMesh (Class|BPPaintGunData|GetMesh :self (CallFunction|GetCurrentGun))))

(fn GetSkiPlayerState ()
  (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object (Variables|Pawn|GetPlayerState))
    (:then
      (return ski))
    (:CastFailed
      (return ski))))

; Helmet and skis in the team's colour (and the paintballs too), or grey once the skier is OUT. Team and out-ness live
; on the player state, which can reach a client after the character, so this checks every frame and only repaints
; when they changed (LookShown = team * 2 + 1 if out).
(fn UpdateTeamLook ()
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (bind team (Other5|Teams|GetTeam :Player ski))
      (bind out (Class|BPSkiPlayerState|GetOut :self ski))
      (bind look (+ (* team 2) (select out 1 0)))
      (if (!= look (Variables|Team|GetTeamShown))
        (Variables|Team|SetTeamShown look)
        (Variables|Team|SetTeamColor (Other5|Teams|GetTeamColor :Team team))
        (bind shown (select out (Utilities|Struct|MakeLinearColor 0.25 0.25 0.25 1.0) (Variables|Team|GetTeamColor)))
        (bind tint (Math|Conversions|ToVector(LinearColor) shown))
        (Rendering|Material|SetVectorParameterValueonMaterials :self (Variables|Default|GetHelmet) :ParameterName "Color" :ParameterValue tint)
        (Rendering|Material|SetVectorParameterValueonMaterials :self (Variables|Default|GetSkiLeft) :ParameterName "Color" :ParameterValue tint)
        (Rendering|Material|SetVectorParameterValueonMaterials :self (Variables|Default|GetSkiRight) :ParameterName "Color" :ParameterValue tint)))
    (:"Is Not Valid")))

; Is this skier out of the race (hit by paint)? Out skiers can't fire.
(fn IsOut ()
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (return (Class|BPSkiPlayerState|GetOut :self ski)))
    (:"Is Not Valid"
      (return false))))

; Server: coins for this player (Other5's inventory currency, which a shop between runs will spend).
(fn AddCoins (Amount)
  (Inventory|Currency|AddCurrency :self (Variables|Default|GetInventory) :Amount Amount))

(fn GetCoins ()
  (return (Inventory|Currency|GetCurrency :self (Variables|Default|GetInventory))))

; Buttons that act once per press (this player's own machine): Q next gun, T switch team, ] harder, [ easier.
; Fire is held: TryFire keeps firing at the gun's rate.
(fn ReadButtons ()
  (bind gunKey (Input|EnhancedActionValues|IA_SkiSwitchGun))
  (if (and gunKey (not (Variables|Paint|GetPrevSwitchGun)))
    (CallFunction|ServerNextGun))
  (Variables|Paint|SetPrevSwitchGun gunKey)
  (bind teamKey (Input|EnhancedActionValues|IA_SkiSwitchTeam))
  (if (and teamKey (not (Variables|Team|GetPrevSwitchTeam)))
    ; Other5's shared teams: ask for the next team; the server allows it while switching is on (the lobby).
    (Other5|Teams|RequestTeam :Player self :Team -2))
  (Variables|Team|SetPrevSwitchTeam teamKey)
  (bind harderKey (Input|EnhancedActionValues|IA_SkiHarder))
  (if (and harderKey (not (Variables|Team|GetPrevHarder)))
    (CallFunction|ServerChangeDifficulty :Step 1))
  (Variables|Team|SetPrevHarder harderKey)
  (bind easierKey (Input|EnhancedActionValues|IA_SkiEasier))
  (if (and easierKey (not (Variables|Team|GetPrevEasier)))
    (CallFunction|ServerChangeDifficulty :Step -1))
  (Variables|Team|SetPrevEasier easierKey)
  (if (Input|EnhancedActionValues|IA_SkiFire)
    (CallFunction|TryFire)))

(fn TryFire ()
  (bind now (Utilities|Time|GetTimeSeconds))
  (if (and (>= now (Variables|Paint|GetNextFireTime)) (and (not (Variables|Ski|State|GetSkiFrozen)) (not (CallFunction|IsOut))))
    (bind gun (CallFunction|GetCurrentGun))
    (Variables|Paint|SetNextFireTime (+ now (/ 1.0 (Math|Float|Max(Float) (Class|BPPaintGunData|GetShotsPerSecond :self gun) 0.1))))
    ; Aim from the camera through the crosshair (up to 300 m); the balls leave the gun's muzzle toward that point.
    (bind camera (Game|GetPlayerCameraManager 0))
    (bind eye (Camera|GetCameraLocation :self camera))
    (bind far (+ eye (* (Math|Vector|GetForwardVector (Camera|GetCameraRotation :self camera)) 30000.0)))
    (bind (hit didHit) (Collision|LineTraceByChannel :Start eye :End far :TraceChannel "TraceTypeQuery1" :bIgnoreSelf true))
    (bind (blocking overlap time dist loc impact) (Collision|BreakHitResult hit))
    (bind target (select didHit impact far))
    (bind muzzle (Math|Transform|TransformLocation (Transformation|GetWorldTransform :self (Variables|Default|GetGunMesh)) (Class|BPPaintGunData|GetMuzzleOffset :self gun)))
    (bind direction (Math|Vector|Normalize (- target muzzle)))
    ; Drawn once into a variable (a random node is pure: each use would draw again, and the server and the other
    ; players would get a different spread from the shooter's).
    (Variables|Paint|SetShotSeed (Math|Random|RandomIntegerinRange 0 1000000))
    (bind seed (Variables|Paint|GetShotSeed))
    ; Our own balls now (they score only if we are the server), then the server's.
    (CallFunction|SpawnBalls :Muzzle muzzle :Direction direction :Seed seed :bScores (Networking|HasAuthority))
    (if (Networking|HasAuthority)
      (CallFunction|MulticastFire :Muzzle muzzle :Direction direction :Seed seed)
      (else
        (CallFunction|ServerFire :Muzzle muzzle :Direction direction :Seed seed)))))

; One shot of the gun in hand: PelletsPerShot balls in a SpreadDegrees cone, picked from Seed. Each ball also gets
; the skier's own velocity (throw a ball from a moving sled and it keeps the sled's speed).
(fn SpawnBalls (Muzzle Direction Seed bScores)
  (bind gun (CallFunction|GetCurrentGun))
  (Variables|Paint|SetShotStream (Math|Random|MakeRandomStream Seed))
  (for i (range (Class|BPPaintGunData|GetPelletsPerShot :self gun))
    (Variables|Paint|SetShotDir (Math|Random|RandomUnitVectorinConeinDegreesfromStream :Stream (Variables|Paint|GetShotStream) :ConeDir Direction :ConeHalfAngleInDegrees (Class|BPPaintGunData|GetSpreadDegrees :self gun)))
    (bind dir (Variables|Paint|GetShotDir))
    (bind ball (Game|SpawnActorfromClass :Class "/SKIvSKI/Blueprints/BP_Paintball.BP_Paintball_C" :SpawnTransform (Math|Transform|MakeTransform Muzzle (Math|Conversions|RotationFromXVector dir) (Math|Vector|MakeVector 1.0 1.0 1.0)) :CollisionHandlingOverride "AlwaysSpawn" :Owner self))
    (Class|BPPaintball|Launch :self ball :Velocity (+ (* dir (Class|BPPaintGunData|GetMuzzleSpeed :self gun)) (Transformation|GetVelocity)) :Color (Variables|Team|GetTeamColor) :InShooter self :bInScores bScores :Size (Class|BPPaintGunData|GetBallSize :self gun) :GravityScale (Class|BPPaintGunData|GetBallGravityScale :self gun))))

(event Custom|ServerFire (Muzzle Direction Seed)
  (CallFunction|SpawnBalls :Muzzle Muzzle :Direction Direction :Seed Seed :bScores true)
  (CallFunction|MulticastFire :Muzzle Muzzle :Direction Direction :Seed Seed))

(event Custom|MulticastFire (Muzzle Direction Seed)
  ; The shooter already has theirs, and the server made the scoring ones.
  (if (and (not (Pawn|IsLocallyControlled)) (not (Networking|HasAuthority)))
    (CallFunction|SpawnBalls :Muzzle Muzzle :Direction Direction :Seed Seed :bScores false)))

(event Custom|ServerNextGun
  (Variables|Paint|SetGunIndex (Math|Integer|%(Integer) (+ (Variables|Paint|GetGunIndex) 1) (Math|Integer|Max(Integer) (Utilities|Array|Length (Variables|Paint|GetGuns)) 1))))

(event Custom|ServerChangeDifficulty (Step)
  (Class|BPSkiDirector|ChangeDifficulty :self (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C") :Player (CallFunction|GetSkiPlayerState) :Step Step))

; A scoring paintball hit this skier (server): the director decides whether it counts.
; A scoring paintball (the server's copy) hit this skier at Where, flying along Direction, with the ball's Color and
; Size. The director decides (ResolvePaintHit): a hit puts this skier out, a bounce doesn't. Everyone then sees the
; result through MulticastPaintResult. (The other machines' copies of the ball vanish on a skier without a splat.)
(fn PaintedBy (Shooter Where Direction Normal Color Size)
  (bind result (Class|BPSkiDirector|ResolvePaintHit :self (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C") :Shooter Shooter :Victim self))
  (Development|PrintString :InString (Utilities|String|Append "SKI| paint result " (Utilities|String|Append (Utilities|String|ToString(Integer) result) (Utilities|String|Append " on " (Utilities|String|ToString(Object) self)))) :bPrintToScreen false)
  (if (> result 0)
    ; A bounce flies off the skier like light off a mirror, slower, and a little up.
    (bind off (+ (* (Math|Vector|MirrorVectorbyNormal Direction Normal) 1500.0) (Math|Vector|MakeVector 0.0 0.0 300.0)))
    (CallFunction|MulticastPaintResult :bHit (== result 1) :Where Where :Bounce off :Tint (Math|Conversions|ToVector(LinearColor) Color) :Size Size)))

; The director moves this skier (server): to the lobby, or behind the team's gate. PlaceId (RepNotify) tells the
; owning player's machine to point the skis and the camera the new way.
(fn PlaceAt (Spot)
  (bind yaw (.yaw (.rotation Spot)))
  (Components|Movement|StopMovementImmediately :self (Variables|Character|GetCharacterMovement))
  (Transformation|Teleport :DestLocation (.location Spot) :DestRotation (Math|Rotator|MakeRotator :Yaw yaw))
  (Variables|Ski|State|SetSkiYaw yaw)
  (Variables|Ski|State|SetPlacedYaw yaw)
  (Variables|Ski|State|SetPlaceId (+ (Variables|Ski|State|GetPlaceId) 1)))

(fn OnRep_PlaceId ()
  (if (Pawn|IsLocallyControlled)
    (bind yaw (Variables|Ski|State|GetPlacedYaw))
    (Variables|Ski|State|SetSkiYaw yaw)
    (Variables|Ski|State|SetLastSentYaw yaw)
    (Components|Movement|StopMovementImmediately :self (Variables|Character|GetCharacterMovement))
    (Pawn|SetControlRotation :self (Pawn|GetController) :NewRotation (Math|Rotator|MakeRotator :Pitch -12.0 :Yaw yaw))))

; For tests: look Pitch degrees up (+) or down (-) along the skis, and pull the trigger once
; (the Other5 test runner: "call pawn DebugAim -15", "call pawn DebugFire").
(fn DebugAim (Pitch)
  (Pawn|SetControlRotation :self (Pawn|GetController) :NewRotation (Math|Rotator|MakeRotator :Pitch Pitch :Yaw (Variables|Ski|State|GetSkiYaw))))

(fn DebugFire ()
  (Variables|Paint|SetNextFireTime 0.0)
  (CallFunction|TryFire)
  (bind balls (Actor|GetAllActorsOfClass :ActorClass "/SKIvSKI/Blueprints/BP_Paintball.BP_Paintball_C"))
  (Development|PrintString :InString (Utilities|String|Append "SKI| paintballs flying: " (Utilities|String|ToString(Integer) (Utilities|Array|Length balls))) :Duration 3.0))

; For tests: log the round and the scores as this machine sees them ("call pawn DebugScore").
(fn DebugScore ()
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (bind ski (CallFunction|GetSkiPlayerState))
  (bind a (Utilities|String|Append "SKI| phase " (Utilities|String|ToString(Integer) (Class|BPSkiDirector|GetPhase :self director))))
  (bind b (Utilities|String|Append a (Utilities|String|Append " red " (Utilities|String|ToString(Integer) (Other5|Teams|GetTeamScore :Team 0)))))
  (bind c (Utilities|String|Append b (Utilities|String|Append " blue " (Utilities|String|ToString(Integer) (Other5|Teams|GetTeamScore :Team 1)))))
  (bind d (Utilities|String|Append c (Utilities|String|Append " myTeam " (Utilities|String|ToString(Integer) (Other5|Teams|GetTeam :Player ski)))))
  (bind e0 (Utilities|String|Append d (Utilities|String|Append " myHits " (Utilities|String|ToString(Integer) (Class|BPSkiPlayerState|GetHits :self ski)))))
  (bind e1 (Utilities|String|Append e0 (Utilities|String|Append " out " (Utilities|String|ToString(Boolean) (CallFunction|IsOut)))))
  (bind e (Utilities|String|Append e1 (Utilities|String|Append " coins " (Utilities|String|ToString(Integer) (Inventory|Currency|GetCurrency :self (Variables|Default|GetInventory))))))
  (bind f (Utilities|String|Append e (Utilities|String|Append " balls " (Utilities|String|ToString(Integer) (Utilities|Array|Length (Actor|GetAllActorsOfClass :ActorClass "/SKIvSKI/Blueprints/BP_Paintball.BP_Paintball_C"))))))
  (Development|PrintString :InString f :Duration 3.0))

; For tests: during the race, point the skis 35 degrees off the fall line toward the middle of the slope, so both
; teams meet ("call pawn DebugSteerToMiddle").
(fn DebugSteerToMiddle ()
  (if (== (Class|BPSkiDirector|GetPhase :self (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C")) 2)
    (bind y (.y (Transformation|GetActorLocation)))
    (if (> (Math|Float|Absolute(Float) y) 600.0)
      (Variables|Ski|State|SetSkiYaw (+ (Variables|Ski|State|GetFallLineYaw) (select (< y 0.0) 35.0 -35.0)))
      (else
        (Variables|Ski|State|SetSkiYaw (Variables|Ski|State|GetFallLineYaw))))))

; Multicast (Reliable): every machine shows what a paintball did to this skier. A hit: a splat on the skier and
; "Hit!" over their head. A bounce: the ball flies off (a ball that can't score) and "Bounce!" over their head.
(event Custom|MulticastPaintResult (bHit Where Bounce Tint Size)
  ; The colour comes as a vector (R, G, B): simpler to add as an event input than a Linear Color.
  (bind Color (Math|Conversions|ToLinearColor(Vector) Tint))
  (bind head (+ (Transformation|GetActorLocation) (Math|Vector|MakeVector 0.0 0.0 120.0)))
  (CallFunction|ShowPopup :Text (select bHit "Hit!" "Bounce!") :Where head :Color (select bHit Color (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 1.0)))
  (if bHit
    (bind splat (Rendering|Decal|SpawnDecalAttached :DecalMaterial "/SKIvSKI/Materials/M_PaintSplat.M_PaintSplat" :DecalSize (Math|Vector|MakeVector 20.0 (* Size 4.0) (* Size 4.0)) :AttachToComponent (Variables|Character|GetMesh) :Location Where :Rotation (Math|Conversions|RotationFromXVector (- (Transformation|GetActorLocation) Where)) :LocationType "KeepWorldPosition" :LifeSpan 20.0))
    (Utilities|IsValid splat
      (:"Is Valid"
        (Rendering|Components|Decal|SetDecalColor :self splat :Color Color))
      (:"Is Not Valid"))
    (else
      (bind ball (Game|SpawnActorfromClass :Class "/SKIvSKI/Blueprints/BP_Paintball.BP_Paintball_C" :SpawnTransform (Math|Transform|MakeTransform (+ Where (* (Math|Vector|Normalize Bounce) 20.0)) (Math|Conversions|RotationFromXVector Bounce) (Math|Vector|MakeVector 1.0 1.0 1.0)) :CollisionHandlingOverride "AlwaysSpawn"))
      (Class|BPPaintball|Launch :self ball :Velocity Bounce :Color Color :InShooter self :bInScores false :Size Size :GravityScale 1.0))))

; Shows a rising, fading word over a spot on this machine's HUD (BP_SkiHUD AddPopup). Nothing on a dedicated server.
(fn ShowPopup (Text Where Color)
  (bind hud (Utilities|Casting|CastToBP_SkiHUD :Object (HUD|GetHUD :self (Game|GetPlayerController 0)))
    (:then
      (Class|BPSkiHUD|AddPopup :self hud :Text Text :Where Where :Color Color))
    (:CastFailed)))

; For tests: show both pop-ups over this skier on this machine ("call pawn DebugPopup").
(fn DebugPopup ()
  (CallFunction|ShowPopup :Text "Hit!" :Where (+ (Transformation|GetActorLocation) (Math|Vector|MakeVector 0.0 0.0 120.0)) :Color (Variables|Team|GetTeamColor))
  (CallFunction|ShowPopup :Text "Bounce!" :Where (+ (Transformation|GetActorLocation) (Math|Vector|MakeVector 0.0 80.0 60.0)) :Color (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 1.0)))
