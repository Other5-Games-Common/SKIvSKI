; BP_SkiFort: a log fort on the slope that a team captures by raising its flag, in Unreal MCP's Blueprint graph DSL
; (BlueprintTools.write_graph_dsl). Kept as text so the logic can be reviewed; the asset itself is binary.
;
; The slope plans where forts go (BP_SkiSlope PlanForts, from its Seed, so every machine keeps its pines and bumps
; clear of them) and the server spawns them (SpawnForts); they replicate to everyone.
;
; In the fort's own space: X runs downhill, Z up from the snow. Its walls (LayLogs, every machine) are SM_SkiLog
; stacked in RowHeights: a front wall across the downhill side and a wall down each side, open uphill, so you ski in
; from above and stop against the front wall. Shots can only get in by luck: through the slit between the top two
; rows, the gap in the middle of the front wall, or the corner gaps.
;
; Capturing (ServerStep, the server, during the race): while skiers of only one team (who aren't out) stand in its
; Zone, the flag rises (Progress, CaptureSeconds from bottom to top); the other team alone pulls it back down first;
; both teams there hold it still. At the top the fort is that team's for the rest of the race (CapturedBy): +1 point
; for the team and the director's HitCoins to every one of its skiers in the fort.
;
; Getting out: ski back up the open side (jumping while stopped pushes you along your skis, BP_SkiCharacter
; EventOnJumped), or press F (Exit fort): the server moves you just uphill of the fort (TakeExitSpot), at most every
; ExitCooldown seconds (BP_SkiCharacter ServerExitFort).

(event EventBeginPlay
  (CallFunction|LayLogs)
  (Variables|Fort|State|SetFlagShown -2))

(event EventTick (DeltaSeconds)
  (if (Networking|HasAuthority)
    (CallFunction|ServerStep :DeltaSeconds DeltaSeconds))
  (CallFunction|ShowFlag))

; The walls, every machine (they're the same everywhere: only the fort's place replicates).
(fn LayLogs ()
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetLogs))
  (bind halfW (* (Variables|Fort|Layout|GetWidth) 0.5))
  (bind halfD (* (Variables|Fort|Layout|GetDepth) 0.5))
  (bind gap (Variables|Fort|Layout|GetFrontGap))
  (for z (Variables|Fort|Layout|GetRowHeights)
    ; The front wall, downhill: two logs end to end, FrontGap between them.
    (CallFunction|AddLog :At (Math|Vector|MakeVector halfD (- 0.0 (* (+ halfW (* gap 0.5)) 0.5)) z) :Yaw 90.0 :Length (- halfW (* gap 0.5)))
    (CallFunction|AddLog :At (Math|Vector|MakeVector halfD (* (+ halfW (* gap 0.5)) 0.5) z) :Yaw 90.0 :Length (- halfW (* gap 0.5)))
    ; The side walls, from the front wall up to the open side, CornerGap out from the front wall's ends.
    (CallFunction|AddLog :At (Math|Vector|MakeVector 0.0 (- 0.0 (+ halfW (Variables|Fort|Layout|GetCornerGap))) z) :Yaw 0.0 :Length (Variables|Fort|Layout|GetDepth))
    (CallFunction|AddLog :At (Math|Vector|MakeVector 0.0 (+ halfW (Variables|Fort|Layout|GetCornerGap)) z) :Yaw 0.0 :Length (Variables|Fort|Layout|GetDepth))))

; One log (SM_SkiLog is 300 cm long along X) in the fort's space.
(fn AddLog (At Yaw Length)
  (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetLogs) :InstanceTransform (Math|Transform|MakeTransform At (Math|Rotator|MakeRotator :Yaw Yaw) (Math|Vector|MakeVector (/ Length 300.0) 1.0 1.0))))

; The server, every frame: raise or lower the flag by who's in the fort (see the top of this file).
(fn ServerStep (DeltaSeconds)
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (Utilities|IsValid director
    (:"Is Valid"
      (if (and (== (Class|BPSkiDirector|GetPhase :self director) 2) (< (Variables|Fort|State|GetCapturedBy) 0))
        (Variables|Fort|Work|SetRedInside 0)
        (Variables|Fort|Work|SetBlueInside 0)
        (for inside (Collision|GetOverlappingActors :self (Variables|Default|GetZone) :ClassFilter "/SKIvSKI/Blueprints/BP_SkiCharacter.BP_SkiCharacter_C")
          (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object inside)
            (:then
              (bind skierTeam (Other5|Teams|GetTeam :Player skier))
              (if (not (Class|BPSkiCharacter|IsOut :self skier))
                (if (== skierTeam 0)
                  (Variables|Fort|Work|SetRedInside (+ (Variables|Fort|Work|GetRedInside) 1)))
                (if (== skierTeam 1)
                  (Variables|Fort|Work|SetBlueInside (+ (Variables|Fort|Work|GetBlueInside) 1)))))
            (:CastFailed)))
        (bind red (> (Variables|Fort|Work|GetRedInside) 0))
        (bind blue (> (Variables|Fort|Work|GetBlueInside) 0))
        ; Only one team in it: that team's flag goes up, or the other team's comes down first.
        (if (or (and red (not blue)) (and blue (not red)))
          (bind team (select red 0 1))
          (bind step (/ DeltaSeconds (Math|Float|Max(Float) (Variables|Fort|Layout|GetCaptureSeconds) 0.5)))
          (if (or (== (Variables|Fort|State|GetProgressTeam) team) (<= (Variables|Fort|State|GetProgress) 0.0))
            (Variables|Fort|State|SetProgressTeam team)
            (Variables|Fort|State|SetProgress (Math|Float|Min(Float) (+ (Variables|Fort|State|GetProgress) step) 1.0))
            (else
              (Variables|Fort|State|SetProgress (Math|Float|Max(Float) (- (Variables|Fort|State|GetProgress) step) 0.0))))
          (if (>= (Variables|Fort|State|GetProgress) 1.0)
            (CallFunction|Capture :Team team :Director director)))))
    (:"Is Not Valid")))

; The server: Team took the fort. One point for the team; the hit coins for each of its skiers in it.
(fn Capture (Team Director)
  (Variables|Fort|State|SetCapturedBy Team)
  (Other5|Teams|AddTeamScore :Team Team :Points 1)
  (bind coins (Class|BPSkiDirector|GetHitCoins :self Director))
  (for inside (Collision|GetOverlappingActors :self (Variables|Default|GetZone) :ClassFilter "/SKIvSKI/Blueprints/BP_SkiCharacter.BP_SkiCharacter_C")
    (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object inside)
      (:then
        (if (and (== (Other5|Teams|GetTeam :Player skier) Team) (not (Class|BPSkiCharacter|IsOut :self skier)))
          (Class|BPSkiCharacter|AddCoins :self skier :Amount coins)))
      (:CastFailed))))

; Every machine (CapturedBy is RepNotify): "FORT TAKEN!" pops up over the flag in the team's colour.
(fn OnRep_CapturedBy ()
  (bind team (Variables|Fort|State|GetCapturedBy))
  (bind pc (Game|GetPlayerController :PlayerIndex 0))
  (if (>= team 0)
    ; (A dedicated server has no screen: no player controller of its own, or one without a HUD.)
    (Utilities|IsValid pc
      (:"Is Valid"
        (bind skiHud (Utilities|Casting|CastToBP_SkiHUD :Object (HUD|GetHUD :self pc))
          (:then
            (Class|BPSkiHUD|AddPopup :self skiHud :Text "FORT TAKEN!" :Where (Transformation|GetWorldLocation :self (Variables|Default|GetFlag)) :Color (Other5|Teams|GetTeamColor :Team team) :Size 1.3 :Target self))
          (:CastFailed)))
      (:"Is Not Valid"))))

; Every machine, every frame: the flag at Progress up the pole, in the colour of the team raising (or holding) it;
; the fort on the minimap in the same colour, pulsing while a flag is going up.
(fn ShowFlag ()
  (bind progress (Variables|Fort|State|GetProgress))
  (bind held (>= (Variables|Fort|State|GetCapturedBy) 0))
  (Transformation|SetRelativeLocation :self (Variables|Default|GetFlag) :NewLocation (Math|Vector|MakeVector (Variables|Fort|Layout|GetPoleX) 58.0 (Math|Float|Lerp (Variables|Fort|Layout|GetFlagLow) (Variables|Fort|Layout|GetFlagHigh) progress)))
  (bind team (select held (Variables|Fort|State|GetCapturedBy) (select (> progress 0.0) (Variables|Fort|State|GetProgressTeam) -1)))
  (bind rising (and (> progress 0.0) (not held)))
  (bind look (+ (* (+ team 1) 2) (select rising 1 0)))
  (if (!= look (Variables|Fort|State|GetFlagShown))
    (Variables|Fort|State|SetFlagShown look)
    (bind color (select (>= team 0) (Other5|Teams|GetTeamColor :Team team) (Utilities|Struct|MakeLinearColor 0.85 0.85 0.85 1.0)))
    (Rendering|Material|SetVectorParameterValueonMaterials :self (Variables|Default|GetFlag) :ParameterName "Color" :ParameterValue (Math|Conversions|ToVector(LinearColor) color))
    (Compass|SetMarker :self (Variables|Default|GetMapMarker) :NewMarker (Utilities|Struct|MakeOther5CompassMarker :Shape "Tick" :Color color :bPulse rising :Size 12.0))))

; The server: where someone who presses Exit fort goes: just uphill of the open side (ExitDistance out), spread
; across it so several at once don't land on each other, skis across the slope pointing away from the middle.
(fn TakeExitSpot ()
  (bind index (Variables|Fort|Work|GetExits))
  (Variables|Fort|Work|SetExits (+ index 1))
  (bind y (* (- (Math|Conversions|ToFloat(Integer) (Math|Integer|%(Integer) index 5)) 2.0) 150.0))
  (bind spot (Math|Vector|MakeVector (- 0.0 (+ (* (Variables|Fort|Layout|GetDepth) 0.5) (Variables|Fort|Layout|GetExitDistance))) y 120.0))
  (return (Math|Transform|ComposeTransforms (Math|Transform|MakeTransform spot (Math|Rotator|MakeRotator :Yaw (select (>= y 0.0) 90.0 -90.0)) (Math|Vector|MakeVector 1.0 1.0 1.0)) (Transformation|GetActorTransform))))
