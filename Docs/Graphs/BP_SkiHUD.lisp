; BP_SkiHUD: the round, the scores, your own state, and "Hit!" / "Bounce!" pop-ups, in Unreal MCP's Blueprint DSL.
; A child of Other5's game HUD (BP_Other5GameHUD: game menu, chat), not Other5Combat's, so no ammo, grenade, health
; or credits widgets. Everything here is Draw Text. Kept as text so the logic can be reviewed.

(event EventReceiveDrawHUD (SizeX SizeY)
  (CallFunction|DrawPopups)
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (Utilities|IsValid director
   (:"Is Valid"
    (CallFunction|DrawRound :Director director))
   (:"Is Not Valid")))

(fn DrawRound (Director)
  (bind phase (Class|BPSkiDirector|GetPhase :self Director))
  (bind left (Math|Integer|Max(Integer) (Math|Float|Ceil (- (Class|BPSkiDirector|GetPhaseEndsAt :self Director) (Class|BPSkiDirector|Now :self Director))) 0))
  (bind secs (Utilities|String|ToString(Integer) left))
  (bind white (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 1.0))
  ; What the round is doing.
  (bind lobbyLine (Utilities|String|Append "LOBBY   next race in " (Utilities|String|Append secs " s     T: switch team")))
  (bind readyLine (Utilities|String|Append "GET READY   " secs))
  (bind raceLine (Utilities|String|Append "RACE   " (Utilities|String|Append secs " s left")))
  (bind resultsLine (Utilities|String|Append (Class|BPSkiDirector|GetMessage :self Director) (Utilities|String|Append "     next lobby in " (Utilities|String|Append secs " s"))))
  (bind phaseLine (select (== phase 0) lobbyLine (select (== phase 1) readyLine (select (== phase 2) raceLine resultsLine))))
  (HUD|DrawText :Text phaseLine :TextColor white :ScreenX 40.0 :ScreenY 70.0 :Scale 1.6)
  ; The team scores (Other5's shared teams), each in its team's colour.
  (HUD|DrawText :Text (Utilities|String|Append (Utilities|String|ToUpper (Utilities|String|ToString(Text) (Other5|Teams|GetTeamName :Team 0))) (Utilities|String|Append "  " (Utilities|String|ToString(Integer) (Other5|Teams|GetTeamScore :Team 0)))) :TextColor (Other5|Teams|GetTeamColor :Team 0) :ScreenX 40.0 :ScreenY 100.0 :Scale 1.6)
  (HUD|DrawText :Text (Utilities|String|Append (Utilities|String|ToUpper (Utilities|String|ToString(Text) (Other5|Teams|GetTeamName :Team 1))) (Utilities|String|Append "  " (Utilities|String|ToString(Integer) (Other5|Teams|GetTeamScore :Team 1)))) :TextColor (Other5|Teams|GetTeamColor :Team 1) :ScreenX 180.0 :ScreenY 100.0 :Scale 1.6)
  ; The slope's difficulty (an admin changes it with [ and ] in the lobby).
  (bind level (Class|BPSkiDirector|GetDifficulty :self Director))
  (HUD|DrawText :Text (Utilities|String|Append "Slope: " (Utilities|String|Append (select (== level 0) "Easy" (select (== level 2) "Hard" "Medium")) "    [ ] admin: easier / harder")) :TextColor white :ScreenX 40.0 :ScreenY 130.0 :Scale 1.1)
  ; Your own skier.
  (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (HUD|GetOwningPawn))
    (:then
      (CallFunction|DrawSkier :Skier skier))
    (:CastFailed)))

(fn DrawSkier (Skier)
  (bind ski (Class|BPSkiCharacter|GetSkiPlayerState :self Skier))
  (Utilities|IsValid ski
    (:"Is Valid"
      (bind white (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 1.0))
      (bind team (Utilities|String|ToUpper (Utilities|String|ToString(Text) (Other5|Teams|GetTeamName :Team (Other5|Teams|GetTeam :Player ski)))))
      (bind gun (Utilities|String|ToString(Text) (Class|BPPaintGunData|GetGunName :self (Class|BPSkiCharacter|GetCurrentGun :self Skier))))
      (bind speed (Utilities|String|ToString(Integer) (Math|Float|Round (Class|BPSkiCharacter|GetSpeedKmh :self Skier))))
      (bind place (Class|BPSkiPlayerState|GetFinishPlace :self ski))
      (bind out (Class|BPSkiPlayerState|GetOut :self ski))
      (bind a (Utilities|String|Append team (select out "  -  OUT" "")))
      (bind b (Utilities|String|Append a (Utilities|String|Append "     " (Utilities|String|Append speed " km/h"))))
      (bind c (Utilities|String|Append b (Utilities|String|Append "     outs " (Utilities|String|ToString(Integer) (Class|BPSkiPlayerState|GetHits :self ski)))))
      (bind d (Utilities|String|Append c (select (> place 0) (Utilities|String|Append "     finished #" (Utilities|String|ToString(Integer) place)) "")))
      (HUD|DrawText :Text d :TextColor (select out (Utilities|Struct|MakeLinearColor 0.6 0.6 0.6 1.0) (Class|BPSkiCharacter|GetTeamColor :self Skier)) :ScreenX 40.0 :ScreenY 155.0 :Scale 1.3)
      ; Your gear: the gun, the paint's bounce chance and the skis' friction (the shop will improve both), coins.
      (bind bounce (Utilities|String|ToString(Integer) (Math|Float|Round (* (Class|BPSkiPlayerState|GetBounceChance :self ski) 100.0))))
      (bind friction (Utilities|String|ToString(Float) (Class|BPSkiPlayerState|GetSnowFriction :self ski)))
      (bind coins (Utilities|String|ToString(Integer) (Class|BPSkiCharacter|GetCoins :self Skier)))
      (bind g1 (Utilities|String|Append gun (Utilities|String|Append " (Q)     paint bounce " (Utilities|String|Append bounce "%"))))
      (bind g2 (Utilities|String|Append g1 (Utilities|String|Append "     ski friction " friction)))
      (HUD|DrawText :Text (Utilities|String|Append g2 (Utilities|String|Append "     coins " coins)) :TextColor white :ScreenX 40.0 :ScreenY 185.0 :Scale 1.1))
    (:"Is Not Valid")))

; A word that rises from Where and fades over PopupSeconds ("Hit!", "Bounce!"). Called on every machine.
(fn AddPopup (Text Where Color)
  (Utilities|Array|Add (Variables|Popups|GetPopupTexts) Text)
  (Utilities|Array|Add (Variables|Popups|GetPopupPlaces) Where)
  (Utilities|Array|Add (Variables|Popups|GetPopupColors) Color)
  (Utilities|Array|Add (Variables|Popups|GetPopupStarts) (Utilities|Time|GetTimeSeconds)))

; Each pop-up rises 1.5 m and fades out over PopupSeconds, drawn where its spot in the world is on screen.
(fn DrawPopups ()
  (bind now (Utilities|Time|GetTimeSeconds))
  (bind life (Variables|Popups|GetPopupSeconds))
  ; Oldest first: drop the ones that are over.
  (while (and (> (Utilities|Array|Length (Variables|Popups|GetPopupStarts)) 0) (> (- now (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupStarts) 0)) life))
    (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupTexts) 0)
    (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupPlaces) 0)
    (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupColors) 0)
    (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupStarts) 0))
  (for i (range (Utilities|Array|Length (Variables|Popups|GetPopupStarts)))
    (bind age (/ (- now (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupStarts) i)) life))
    (bind where (+ (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupPlaces) i) (Math|Vector|MakeVector 0.0 0.0 (* age 150.0))))
    (bind screen (HUD|Project :Location where :bClampToZeroPlane false))
    ; Behind the camera Project gives Z <= 0: skip those.
    (if (> (.z screen) 0.0)
      (bind (r g b a) (Utilities|Struct|BreakLinearColor (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupColors) i)))
      (HUD|DrawText :Text (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupTexts) i) :TextColor (Utilities|Struct|MakeLinearColor r g b (- 1.0 age)) :ScreenX (- (.x screen) 40.0) :ScreenY (.y screen) :Scale 2.0))))
