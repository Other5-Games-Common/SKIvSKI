; BP_SkiHUD: the round, the scores and your own state as lines of text, in Unreal MCP's Blueprint graph DSL.
; A child of Other5Combat's HUD (which keeps the game menu, chat, health and the rest); this only adds Draw HUD.
; Kept as text so the logic can be reviewed; the asset itself is binary.

(event EventReceiveDrawHUD (SizeX SizeY)
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (Utilities|IsValid director
   (:"Is Valid"
    (bind phase (Class|BPSkiDirector|GetPhase :self director))
    (bind left (Math|Integer|Max(Integer) (Math|Float|Ceil (- (Class|BPSkiDirector|GetPhaseEndsAt :self director) (Class|BPSkiDirector|Now :self director))) 0))
    (bind secs (Utilities|String|ToString(Integer) left))
    (bind white (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 1.0))
    ; What the round is doing.
    (bind lobbyLine (Utilities|String|Append "LOBBY   next race in " (Utilities|String|Append secs " s     T: switch team")))
    (bind readyLine (Utilities|String|Append "GET READY   " secs))
    (bind raceLine (Utilities|String|Append "RACE   " (Utilities|String|Append secs " s left")))
    (bind resultsLine (Utilities|String|Append (Class|BPSkiDirector|GetMessage :self director) (Utilities|String|Append "     next lobby in " (Utilities|String|Append secs " s"))))
    (bind phaseLine (select (== phase 0) lobbyLine (select (== phase 1) readyLine (select (== phase 2) raceLine resultsLine))))
    (HUD|DrawText :Text phaseLine :TextColor white :ScreenX 40.0 :ScreenY 70.0 :Scale 1.6)
    ; The team scores, each in its colour.
    (HUD|DrawText :Text (Utilities|String|Append "RED  " (Utilities|String|ToString(Integer) (Class|BPSkiDirector|GetRedScore :self director))) :TextColor (Utilities|Struct|MakeLinearColor 1.0 0.25 0.15 1.0) :ScreenX 40.0 :ScreenY 100.0 :Scale 1.6)
    (HUD|DrawText :Text (Utilities|String|Append "BLUE  " (Utilities|String|ToString(Integer) (Class|BPSkiDirector|GetBlueScore :self director))) :TextColor (Utilities|Struct|MakeLinearColor 0.3 0.55 1.0 1.0) :ScreenX 160.0 :ScreenY 100.0 :Scale 1.6)
    ; The slope's difficulty (an admin changes it with [ and ] in the lobby).
    (bind level (Class|BPSkiDirector|GetDifficulty :self director))
    (HUD|DrawText :Text (Utilities|String|Append "Slope: " (Utilities|String|Append (select (== level 0) "Easy" (select (== level 2) "Hard" "Medium")) "    [ ] admin: easier / harder")) :TextColor white :ScreenX 40.0 :ScreenY 130.0 :Scale 1.1)
    ; Your own skier.
    (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (HUD|GetOwningPawn))
      (:then
        (bind ski (Class|BPSkiCharacter|GetSkiPlayerState :self skier))
        (Utilities|IsValid ski
         (:"Is Valid"
          (bind team (select (== (Class|BPSkiPlayerState|GetTeam :self ski) 0) "RED team" "BLUE team"))
          (bind gun (Utilities|String|ToString(Text) (Class|BPPaintGunData|GetGunName :self (Class|BPSkiCharacter|GetCurrentGun :self skier))))
          (bind speed (Utilities|String|ToString(Integer) (Math|Float|Round (Class|BPSkiCharacter|GetSpeedKmh :self skier))))
          (bind place (Class|BPSkiPlayerState|GetFinishPlace :self ski))
          (bind a (Utilities|String|Append team (Utilities|String|Append "     " (Utilities|String|Append gun " (Q: next gun)"))))
          (bind b (Utilities|String|Append a (Utilities|String|Append "     " (Utilities|String|Append speed " km/h"))))
          (bind c (Utilities|String|Append b (Utilities|String|Append "     hits " (Utilities|String|ToString(Integer) (Class|BPSkiPlayerState|GetHits :self ski)))))
          (bind d (Utilities|String|Append c (select (> place 0) (Utilities|String|Append "     finished #" (Utilities|String|ToString(Integer) place)) "")))
          (HUD|DrawText :Text d :TextColor (Class|BPSkiCharacter|GetTeamColor :self skier) :ScreenX 40.0 :ScreenY 155.0 :Scale 1.3))
         (:"Is Not Valid")))
      (:CastFailed)))
   (:"Is Not Valid")))
