; BP_SkiCharacter: paintball guns, teams and round placement, in Unreal MCP's Blueprint graph DSL.
; Kept as text so the logic can be reviewed; the asset itself is binary.
;
; Firing, multiplayer-friendly: the shooter's machine spawns its own balls straight away (no waiting for the
; server), and sends ServerFire with the muzzle, the direction and a random seed. The server spawns the same balls
; (these are the ones that score) and sends MulticastFire, so every other machine spawns them too. The seed makes a
; spread shot's pellets go the same way everywhere. Paintballs aren't replicated actors at all.
;
; RPC events (set in each event's Details: Replicates):
;   ServerFire (Run on Server, Reliable), MulticastFire (Multicast), ServerBuy /
;   ServerChangeDifficulty (Run on Server, Reliable), ServerSetSkiYaw (Run on Server, unreliable; Movement file).
;
; Gear: everything the store sells is listed here, in the store's order (Guns, Skis, Waxes: data assets; the first of
; each is what everyone starts with, free). What a player has on is on their player state (GunIndex, SkisIndex,
; WaxIndex, and the SnowFriction their wax gives), with their Coins and what they've bought (Owned, as Kind x 100 +
; Index: 0 guns, 1 skis, 2 wax). It all lives on the player state, so it lasts while they're connected (a new
; character after a fall keeps it), and a player who joins starts with the basics.

; The gun in hand: the player's GunIndex in Guns (the first, until the player state reaches this machine).
(fn GetCurrentGun ()
  (bind guns (Variables|Paint|GetGuns))
  (bind last (- (Utilities|Array|Length guns) 1))
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (return (Utilities|Array|Get(acopy) guns (Math|Integer|Clamp(Integer) (Class|BPSkiPlayerState|GetGunIndex :self ski) 0 last))))
    (:"Is Not Valid"
      (return (Utilities|Array|Get(acopy) guns 0)))))

; The skis on: the player's SkisIndex in Skis (the first, until the player state reaches this machine).
(fn CurrentSkis ()
  (bind skis (Variables|Store|GetSkis))
  (bind last (- (Utilities|Array|Length skis) 1))
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (return (Utilities|Array|Get(acopy) skis (Math|Integer|Clamp(Integer) (Class|BPSkiPlayerState|GetSkisIndex :self ski) 0 last))))
    (:"Is Not Valid"
      (return (Utilities|Array|Get(acopy) skis 0)))))

; Every machine, every frame: when the player's gun or skis changed (bought, or the player state just arrived), show
; them: the gun in the hand with a full magazine, the skis at their length.
(fn UpdateGear ()
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (bind gunIndex (Class|BPSkiPlayerState|GetGunIndex :self ski))
      (if (!= gunIndex (Variables|Paint|GetGunShown))
        (Variables|Paint|SetGunShown gunIndex)
        (CallFunction|ShowGun)
        (bind gun (CallFunction|GetCurrentGun))
        (Variables|Paint|SetAmmo (Class|BPPaintGunData|GetMagSize :self gun))
        (Variables|Paint|SetReloading false))
      (bind skisIndex (Class|BPSkiPlayerState|GetSkisIndex :self ski))
      (if (!= skisIndex (Variables|Paint|GetSkisShown))
        (Variables|Paint|SetSkisShown skisIndex)
        (bind skis (CallFunction|CurrentSkis))
        (bind length (* 1.7 (Class|BPSkiData|GetLengthScale :self skis)))
        (Transformation|SetRelativeScale3D :self (Variables|Default|GetSkiLeft) :NewScale3D (Math|Vector|MakeVector length 0.09 0.025))
        (Transformation|SetRelativeScale3D :self (Variables|Default|GetSkiRight) :NewScale3D (Math|Vector|MakeVector length 0.09 0.025))))
    (:"Is Not Valid")))

; Unused since the store (the gun shown follows the player state, UpdateGear); kept because GunIndex replicates.
(fn OnRep_GunIndex ()
  (CallFunction|ShowGun))

; The gun in the right hand: its mesh, placed so the hand holds the grip (GripOffset, in the hand socket's space: the
; static meshes are centred on their middle, Other5Combat's skeletal ones on the grip). The upper body's pose and aim
; offset for this kind of gun come from the same data (ABP_Skier reads them).
(fn ShowGun ()
  (bind gun (CallFunction|GetCurrentGun))
  (Components|StaticMesh|SetStaticMesh :self (Variables|Default|GetGunMesh) :NewMesh (Class|BPPaintGunData|GetMesh :self gun))
  (Transformation|SetRelativeLocation :self (Variables|Default|GetGunMesh) :NewLocation (Class|BPPaintGunData|GetGripOffset :self gun)))

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

; Server: coins for this player (BP_SkiPlayerState Coins, spent in the store).
(fn AddCoins (Amount)
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (Class|BPSkiPlayerState|SetCoins :self ski :Coins (+ (Class|BPSkiPlayerState|GetCoins :self ski) Amount)))
    (:"Is Not Valid")))

(fn GetCoins ()
  (bind ski (CallFunction|GetSkiPlayerState))
  (Utilities|IsValid ski
    (:"Is Valid"
      (return (Class|BPSkiPlayerState|GetCoins :self ski)))
    (:"Is Not Valid"
      (return 0))))

; ---- the store (the HUD draws it: BP_SkiHUD DrawStore) ----------------------------------------------------------

; What store item Index of Kind (0 guns, 1 skis, 2 wax) costs; -1 if there's no such item.
(fn GearPrice (Kind Index)
  (if (and (== Kind 0) (Utilities|Array|IsValidIndex (Variables|Paint|GetGuns) Index))
    (return (Class|BPPaintGunData|GetPrice :self (Utilities|Array|Get(acopy) (Variables|Paint|GetGuns) Index))))
  (if (and (== Kind 1) (Utilities|Array|IsValidIndex (Variables|Store|GetSkis) Index))
    (return (Class|BPSkiData|GetPrice :self (Utilities|Array|Get(acopy) (Variables|Store|GetSkis) Index))))
  (if (and (== Kind 2) (Utilities|Array|IsValidIndex (Variables|Store|GetWaxes) Index))
    (return (Class|BPWaxData|GetPrice :self (Utilities|Array|Get(acopy) (Variables|Store|GetWaxes) Index))))
  (return -1))

; Run on Server (Reliable): this player clicked store item Index of Kind.
(event Custom|ServerBuy (Kind Index)
  (CallFunction|BuyGear :Kind Kind :Index Index))

; Server: buy store item Index of Kind, or put back on one already owned (or free), only between runs (the lobby and
; the results). Buying costs its Price in coins, if the player has enough; it's theirs from then on.
(fn BuyGear (Kind Index)
  (bind ski (CallFunction|GetSkiPlayerState))
  (bind phase (Class|BPSkiDirector|GetPhase :self (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C")))
  (bind price (CallFunction|GearPrice :Kind Kind :Index Index))
  (bind code (+ (* Kind 100) Index))
  (bind coinsBefore (CallFunction|GetCoins))
  (Development|PrintString :InString (Utilities|String|Append "SKI| buy " (Utilities|String|Append (Utilities|String|ToString(Integer) code) (Utilities|String|Append " price " (Utilities|String|Append (Utilities|String|ToString(Integer) price) (Utilities|String|Append " coins " (Utilities|String|Append (Utilities|String|ToString(Integer) coinsBefore) (Utilities|String|Append " phase " (Utilities|String|ToString(Integer) phase)))))))) :bPrintToScreen false)
  (Utilities|IsValid ski
    (:"Is Valid"
      (if (and (or (== phase 0) (== phase 3)) (>= price 0))
        (if (or (== price 0) (Utilities|Array|ContainsItem (Class|BPSkiPlayerState|GetOwned :self ski) code))
          (CallFunction|Equip :Kind Kind :Index Index)
          (elif (>= (Class|BPSkiPlayerState|GetCoins :self ski) price)
            (Class|BPSkiPlayerState|SetCoins :self ski :Coins (- (Class|BPSkiPlayerState|GetCoins :self ski) price))
            (Utilities|Array|Add (Class|BPSkiPlayerState|GetOwned :self ski) code)
            (CallFunction|Equip :Kind Kind :Index Index)))))
    (:"Is Not Valid")))

; Server: put on store item Index of Kind (the player state replicates it; every machine's UpdateGear shows it).
(fn Equip (Kind Index)
  (bind ski (CallFunction|GetSkiPlayerState))
  (if (== Kind 0)
    (Class|BPSkiPlayerState|SetGunIndex :self ski :GunIndex Index))
  (if (== Kind 1)
    (Class|BPSkiPlayerState|SetSkisIndex :self ski :SkisIndex Index))
  (if (== Kind 2)
    (Class|BPSkiPlayerState|SetWaxIndex :self ski :WaxIndex Index)
    (Class|BPSkiPlayerState|SetSnowFriction :self ski :SnowFriction (Class|BPWaxData|GetSnowFriction :self (Utilities|Array|Get(acopy) (Variables|Store|GetWaxes) Index)))))

; Is this player's store open (their HUD's)? Then the mouse clicks the store, not the trigger.
(fn IsStoreOpen ()
  (bind hud (Utilities|Casting|CastToBP_SkiHUD :Object (HUD|GetHUD :self (Game|GetPlayerController 0)))
    (:then
      (return (Class|BPSkiHUD|GetStoreOpen :self hud)))
    (:CastFailed
      (return false))))

(fn ToggleMyStore ()
  (bind hud (Utilities|Casting|CastToBP_SkiHUD :Object (HUD|GetHUD :self (Game|GetPlayerController 0)))
    (:then
      (Class|BPSkiHUD|ToggleStore :self hud))
    (:CastFailed)))

; For tests: give this player Coins coins and buy item Index of Kind, as a click in the store would (server, or a
; standalone game: "call pawn DebugBuy 0 2 50" buys the Stream Marker).
(fn DebugBuy (Kind Index Coins)
  (if (Networking|HasAuthority)
    (bind ski (CallFunction|GetSkiPlayerState))
    (Class|BPSkiPlayerState|SetCoins :self ski :Coins Coins)
    (CallFunction|BuyGear :Kind Kind :Index Index)))

; ---- reloading --------------------------------------------------------------------------------------------------

; R, or firing with an empty magazine: reload (ReloadSeconds, with the gun's reload animation). Ammo is counted on the
; player's own machine.
(fn StartReload ()
  (bind gun (CallFunction|GetCurrentGun))
  (if (and (not (Variables|Paint|GetReloading)) (< (Variables|Paint|GetAmmo) (Class|BPPaintGunData|GetMagSize :self gun)))
    (Variables|Paint|SetReloading true)
    (Variables|Paint|SetReloadDoneAt (+ (Utilities|Time|GetTimeSeconds) (Class|BPPaintGunData|GetReloadSeconds :self gun)))
    (Animation|PlayAnimMontage :AnimMontage (Class|BPPaintGunData|GetReloadMontage :self gun))))

(fn UpdateReload ()
  (if (and (Variables|Paint|GetReloading) (>= (Utilities|Time|GetTimeSeconds) (Variables|Paint|GetReloadDoneAt)))
    (Variables|Paint|SetReloading false)
    (bind gun (CallFunction|GetCurrentGun))
    (Variables|Paint|SetAmmo (Class|BPPaintGunData|GetMagSize :self gun))))

; Buttons that act once per press (this player's own machine): R reload, B store, T switch team, ] harder, [ easier.
; Fire: a semi-automatic gun fires once per press, a full-automatic one (bFullAuto) keeps firing while it's held, both
; at most ShotsPerSecond.
(fn ReadButtons ()
  (bind reloadKey (Input|EnhancedActionValues|IA_SkiReload))
  (if (and reloadKey (not (Variables|Paint|GetPrevReload)))
    (CallFunction|StartReload))
  (Variables|Paint|SetPrevReload reloadKey)
  (bind storeKey (Input|EnhancedActionValues|IA_SkiStore))
  (if (and storeKey (not (Variables|Paint|GetPrevStore)))
    (CallFunction|ToggleMyStore))
  (Variables|Paint|SetPrevStore storeKey)
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
  (bind fireKey (Input|EnhancedActionValues|IA_SkiFire))
  (bind gun (CallFunction|GetCurrentGun))
  (if (and fireKey (or (Class|BPPaintGunData|GetFullAuto :self gun) (not (Variables|Paint|GetPrevFire))))
    (CallFunction|TryFire))
  (Variables|Paint|SetPrevFire fireKey))

; The camera, and so every shot, stays within MaxAimYaw (100 degrees) of where the skis point: as far as the body can
; twist to aim, so nobody shoots behind their own gun. Runs on the player's own machine after the skis turn; skis
; turning past the camera carry it round with them.
(fn ClampAim ()
  (bind rot (Pawn|GetControlRotation :self (Pawn|GetController)))
  (bind limit (Variables|Paint|GetMaxAimYaw))
  (bind off (Math|Rotator|NormalizeAxis (- (.yaw rot) (Variables|Ski|State|GetSkiYaw))))
  (if (> (Math|Float|Absolute(Float) off) limit)
    (Pawn|SetControlRotation :self (Pawn|GetController) :NewRotation (Math|Rotator|MakeRotator :Pitch (.pitch rot) :Yaw (+ (Variables|Ski|State|GetSkiYaw) (Math|Float|Clamp(Float) off (- limit) limit))))))

; One shot, if the gun's ready (its rate, a ball in the magazine, not reloading) and the skier can shoot (not frozen at
; the gate, not out, the store not open). An empty magazine reloads instead.
(fn TryFire ()
  (bind now (Utilities|Time|GetTimeSeconds))
  (bind out (CallFunction|IsOut))
  (bind shopping (CallFunction|IsStoreOpen))
  (bind ready (and (>= now (Variables|Paint|GetNextFireTime)) (and (not (Variables|Paint|GetReloading)) (> (Variables|Paint|GetAmmo) 0))))
  (if (and (not (Variables|Paint|GetReloading)) (<= (Variables|Paint|GetAmmo) 0))
    (CallFunction|StartReload))
  (if (and ready (and (and (not (Variables|Ski|State|GetSkiFrozen)) (not out)) (not shopping)))
    (bind gun (CallFunction|GetCurrentGun))
    (Variables|Paint|SetAmmo (- (Variables|Paint|GetAmmo) 1))
    ; The last ball out: reload straight away.
    (if (<= (Variables|Paint|GetAmmo) 0)
      (CallFunction|StartReload))
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
; This runs on every machine for every shot, so it's also where the shot is heard and seen: one of the gun's
; FireSounds at the muzzle, and its FireMontage (Other5Combat's recoil) on the skier's upper body.
(fn SpawnBalls (Muzzle Direction Seed bScores)
  (bind gun (CallFunction|GetCurrentGun))
  (bind sounds (Class|BPPaintGunData|GetFireSounds :self gun))
  (if (> (Utilities|Array|Length sounds) 0)
    (Audio|PlaySoundatLocation :Sound (Utilities|Array|Get(acopy) sounds (Math|Random|RandomIntegerinRange 0 (- (Utilities|Array|Length sounds) 1))) :Location Muzzle :AttenuationSettings "/Other5Combat/Audio/AttenuationPresets/ATT_Rifle.ATT_Rifle"))
  (Animation|PlayAnimMontage :AnimMontage (Class|BPPaintGunData|GetFireMontage :self gun))
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

; For tests: fire the last ball in the magazine, so it reloads ("call pawn DebugEmpty").
(fn DebugEmpty ()
  (Variables|Paint|SetAmmo 1)
  (Variables|Paint|SetNextFireTime 0.0)
  (CallFunction|TryFire))

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
  (bind coins (CallFunction|GetCoins))
  (bind e2 (Utilities|String|Append e1 (Utilities|String|Append " coins " (Utilities|String|ToString(Integer) coins))))
  (bind gun (CallFunction|GetCurrentGun))
  (bind skis (CallFunction|CurrentSkis))
  (bind e3 (Utilities|String|Append e2 (Utilities|String|Append " gun " (Utilities|String|ToString(Text) (Class|BPPaintGunData|GetGunName :self gun)))))
  (bind e4 (Utilities|String|Append e3 (Utilities|String|Append " ammo " (Utilities|String|Append (Utilities|String|ToString(Integer) (Variables|Paint|GetAmmo)) (select (Variables|Paint|GetReloading) " reloading" "")))))
  (bind e5 (Utilities|String|Append e4 (Utilities|String|Append " skis " (Utilities|String|ToString(Text) (Class|BPSkiData|GetSkiName :self skis)))))
  (bind e (Utilities|String|Append e5 (Utilities|String|Append " friction " (Utilities|String|ToString(Float) (CallFunction|GetSnowFriction)))))
  (bind f (Utilities|String|Append e (Utilities|String|Append " balls " (Utilities|String|ToString(Integer) (Utilities|Array|Length (Actor|GetAllActorsOfClass :ActorClass "/SKIvSKI/Blueprints/BP_Paintball.BP_Paintball_C"))))))
  (Development|PrintString :InString f :Duration 3.0))

; For tests: move the round on now, without waiting for its timers: 1 the countdown, 2 the race, 3 the results
; ("call pawn DebugPhase 3"). Only where the round is run (the server, or a standalone game).
(fn DebugPhase (Phase)
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (if (Networking|HasAuthority)
    (if (== Phase 1)
      (Class|BPSkiDirector|StartCountdown :self director))
    (if (== Phase 2)
      (Class|BPSkiDirector|StartRace :self director))
    (if (== Phase 3)
      (Class|BPSkiDirector|EndRace :self director))))

; For tests: during the race, point the skis 35 degrees off the fall line toward the middle of the slope, so both
; teams meet ("call pawn DebugSteerToMiddle").
(fn DebugSteerToMiddle ()
  (if (== (Class|BPSkiDirector|GetPhase :self (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C")) 2)
    (bind y (.y (Transformation|GetActorLocation)))
    (if (> (Math|Float|Absolute(Float) y) 600.0)
      (Variables|Ski|State|SetSkiYaw (+ (Variables|Ski|State|GetFallLineYaw) (select (< y 0.0) 35.0 -35.0)))
      (else
        (Variables|Ski|State|SetSkiYaw (Variables|Ski|State|GetFallLineYaw))))))

; Multicast (Reliable): every machine shows what a paintball did to this skier. A hit: a splat on the skier, a big
; "Hit!" over their head and the hit sound. A bounce: the ball flies off (a ball that can't score), a smaller
; "Bounce!" and the bounce sound. Both sounds are heard by everyone, wherever they are on the slope.
(event Custom|MulticastPaintResult (bHit Where Bounce Tint Size)
  ; The colour comes as a vector (R, G, B): simpler to add as an event input than a Linear Color.
  (bind Color (Math|Conversions|ToLinearColor(Vector) Tint))
  (bind head (+ (Transformation|GetActorLocation) (Math|Vector|MakeVector 0.0 0.0 120.0)))
  (CallFunction|ShowPopup :Text (select bHit "Hit!" "Bounce!") :Where head :Color (select bHit Color (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 1.0)) :Size (select bHit 1.0 0.6) :Target self)
  (if bHit
    (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiHit.S_SkiHit" :VolumeMultiplier 0.9 :bIsUISound false)
    (bind splat (Rendering|Decal|SpawnDecalAttached :DecalMaterial "/SKIvSKI/Materials/M_PaintSplat.M_PaintSplat" :DecalSize (Math|Vector|MakeVector 20.0 (* Size 4.0) (* Size 4.0)) :AttachToComponent (Variables|Character|GetMesh) :Location Where :Rotation (Math|Conversions|RotationFromXVector (- (Transformation|GetActorLocation) Where)) :LocationType "KeepWorldPosition" :LifeSpan 20.0))
    (Utilities|IsValid splat
      (:"Is Valid"
        (Rendering|Components|Decal|SetDecalColor :self splat :Color Color))
      (:"Is Not Valid"))
    (else
      (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiBounce.S_SkiBounce" :VolumeMultiplier 0.8 :bIsUISound false)
      (bind ball (Game|SpawnActorfromClass :Class "/SKIvSKI/Blueprints/BP_Paintball.BP_Paintball_C" :SpawnTransform (Math|Transform|MakeTransform (+ Where (* (Math|Vector|Normalize Bounce) 20.0)) (Math|Conversions|RotationFromXVector Bounce) (Math|Vector|MakeVector 1.0 1.0 1.0)) :CollisionHandlingOverride "AlwaysSpawn"))
      (Class|BPPaintball|Launch :self ball :Velocity Bounce :Color Color :InShooter self :bInScores false :Size Size :GravityScale 1.0))))

; Shows a word that pops up big and flies up off a spot, fading, on this machine's HUD (BP_SkiHUD AddPopup), following
; Target (a skier) if there is one. Size 1 is a "Hit!"; smaller for lesser news. Nothing on a dedicated server.
(fn ShowPopup (Text Where Color Size Target)
  (bind hud (Utilities|Casting|CastToBP_SkiHUD :Object (HUD|GetHUD :self (Game|GetPlayerController 0)))
    (:then
      (Class|BPSkiHUD|AddPopup :self hud :Text Text :Where Where :Color Color :Size Size :Target Target))
    (:CastFailed)))

; For tests: the server sends this skier a paint hit through MulticastPaintResult, as a real hit would, so every
; machine should show the splat, "Hit!" and its sound (server only: "call pawn DebugHitMe" on a listen server).
(fn DebugHitMe ()
  (if (Networking|HasAuthority)
    (CallFunction|MulticastPaintResult :bHit true :Where (+ (Transformation|GetActorLocation) (Math|Vector|MakeVector 30.0 0.0 40.0)) :Bounce (Math|Vector|MakeVector 0.0 0.0 0.0) :Tint (Math|Vector|MakeVector 1.0 0.1 0.1) :Size 14.0)))

; For tests: show both pop-ups over this skier on this machine, with their sounds ("call pawn DebugPopup").
(fn DebugPopup ()
  (CallFunction|ShowPopup :Text "Hit!" :Where (+ (Transformation|GetActorLocation) (Math|Vector|MakeVector 0.0 0.0 120.0)) :Color (Variables|Team|GetTeamColor) :Size 1.0 :Target self)
  (CallFunction|ShowPopup :Text "Bounce!" :Where (+ (Transformation|GetActorLocation) (Math|Vector|MakeVector 0.0 80.0 60.0)) :Color (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 1.0) :Size 0.6 :Target self)
  (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiHit.S_SkiHit"))
