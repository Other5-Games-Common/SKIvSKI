; BP_SkiHUD: the round, the scores, your own skier, and the "Hit!" / "Bounce!" pop-ups, in Unreal MCP's Blueprint DSL.
; A child of Other5's game HUD (BP_Other5GameHUD: game menu, chat), not Other5Combat's, so no ammo, grenade, health
; or credits widgets. Everything is drawn on the HUD's canvas (Draw Rect, Draw Text) in Other5's UI style
; (Docs/UIStyleGuide.html in Other5): dark see-through panels with a coloured top edge, Orbitron for titles and
; numbers, Exo 2 for the rest (SKIvSKI's big copies of Other5's fonts: /SKIvSKI/UI/Font_SkiTitle, Font_SkiText).
; Sizes are for a 1080-pixel-high screen, times U (the screen's height / 1080); a text Size of 1 is 9 points.
;
; On screen:  top     your team scores either side of the round panel (what's happening, time left, the slope);
;             middle  the GET READY countdown, GO!, and the results scoreboard;
;             bottom  your skier (speed, team, outs, place) in the middle (Other5's chat is bottom left), your gear
;                     (gun and ammo, skis, wax, coins) on the right, and the keys above your skier in the lobby;
;             the store between runs (B, and by itself with the results): see "the store" below.
; Sounds (this machine only): a beep each countdown second, a higher one at GO!, a chime when a team scores and a
; fanfare with the results. Hit and bounce sounds come with the pop-ups (BP_SkiCharacter MulticastPaintResult).

(event EventReceiveDrawHUD (SizeX SizeY)
  (Variables|Layout|SetScreenW SizeX)
  (Variables|Layout|SetScreenH SizeY)
  (Variables|Layout|SetU (/ SizeY 1080.0))
  (CallFunction|EnsureMinimap)
  (CallFunction|DrawPopups)
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (Utilities|IsValid director
   (:"Is Valid"
    (CallFunction|DrawRound :Director director))
   (:"Is Not Valid")))

; ---- the minimap -------------------------------------------------------------------------------------------------

; Other5's minimap (Other5Compass's Other5 Minimap Widget), top right, out to MapRange. It shows markers only, not every
; other player: your teammates (each skier's MapMarker shows to its own team, BP_SkiCharacter UpdateMapMarker) and the
; enemies your team tags with middle mouse (Other5's comms marks them for a few seconds). Made once, on the first frame.
(fn EnsureMinimap ()
  (Utilities|IsValid (Variables|Map|GetMinimap)
    (:"Is Valid")
    (:"Is Not Valid"
      (bind map (UserInterface|CreateWidget :Class "/Script/Other5Compass.Other5MinimapWidget" :OwningPlayer (HUD|GetOwningPlayerController)))
      (Variables|Map|SetMinimap map)
      (Class|Other5CompassWidget|SetShowOtherPlayers :self map :bShowOtherPlayers false)
      (Minimap|SetRange :self map :NewRange (Variables|Map|GetMapRange))
      (UserInterface|Viewport|AddtoViewport :self map))))

; ---- the round ---------------------------------------------------------------------------------------------------

(fn DrawRound (Director)
  (CallFunction|PlayRoundSounds :Director Director)
  (bind u (Variables|Layout|GetU))
  (bind cx (* (Variables|Layout|GetScreenW) 0.5))
  (bind phase (Class|BPSkiDirector|GetPhase :self Director))
  (bind left (Math|Float|Max(Float) (- (Class|BPSkiDirector|GetPhaseEndsAt :self Director) (Class|BPSkiDirector|Now :self Director)) 0.0))
  (bind secs (Utilities|String|ToString(Integer) (Math|Float|Ceil left)))
  ; The round panel, top middle: what's happening, the time, the slope.
  (bind title (select (== phase 0) "LOBBY" (select (== phase 1) "GET READY" (select (== phase 2) "RACE" "RESULTS"))))
  (bind timeLine (select (== phase 0) (Utilities|String|Append "next race in " (Utilities|String|Append secs " s")) (select (== phase 2) (Utilities|String|Append secs " s left") (select (== phase 3) (Utilities|String|Append "next lobby in " (Utilities|String|Append secs " s")) ""))))
  (bind level (Class|BPSkiDirector|GetDifficulty :self Director))
  (bind slopeLine (Utilities|String|Append "slope: " (select (== level 0) "easy" (select (== level 2) "hard" "medium"))))
  (CallFunction|DrawPanel :X (- cx (* 190.0 u)) :Y (* 20.0 u) :W (* 380.0 u) :H (* 112.0 u) :Accent (CallFunction|Neon))
  (CallFunction|DrawCentered :Text title :CenterX cx :Y (* 34.0 u) :Color (CallFunction|Ink) :Size 3.2 :bTitle true)
  (CallFunction|DrawCentered :Text timeLine :CenterX cx :Y (* 78.0 u) :Color (CallFunction|Ink) :Size 1.9 :bTitle false)
  (CallFunction|DrawCentered :Text slopeLine :CenterX cx :Y (* 104.0 u) :Color (CallFunction|Muted) :Size 1.5 :bTitle false)
  ; The two team scores either side of it (Other5's shared teams), flashing when they go up.
  (CallFunction|DrawTeamPanel :Team 0 :X (- cx (* 420.0 u)) :FlashUntil (Variables|Sound|GetFlash0Until))
  (CallFunction|DrawTeamPanel :Team 1 :X (+ cx (* 210.0 u)) :FlashUntil (Variables|Sound|GetFlash1Until))
  (if (== phase 1)
    (CallFunction|DrawCountdown :Left left))
  (CallFunction|DrawGo)
  (if (== phase 3)
    (CallFunction|DrawResults :Director Director))
  (if (and (or (== phase 0) (== phase 1)) (not (Variables|Store|GetStoreOpen)))
    (CallFunction|DrawCentered :Text "B  store      R  reload      T  switch team      [  ]  slope (admin)      Esc  menu" :CenterX cx :Y (- (Variables|Layout|GetScreenH) (* 200.0 u)) :Color (CallFunction|Muted) :Size 1.6 :bTitle false))
  ; The store opens by itself with the results, and closes when the countdown starts.
  (if (!= phase (Variables|Store|GetStorePhase))
    (Variables|Store|SetStorePhase phase)
    (if (== phase 3)
      (CallFunction|SetStoreOpen :bOpen true))
    (if (and (or (== phase 1) (== phase 2)) (Variables|Store|GetStoreOpen))
      (CallFunction|SetStoreOpen :bOpen false)))
  ; Your own skier, and the store.
  (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (HUD|GetOwningPawn))
    (:then
      (CallFunction|DrawSkier :Skier skier)
      (CallFunction|DrawFort :Skier skier)
      (if (Variables|Store|GetStoreOpen)
        (CallFunction|DrawStore :Skier skier)))
    (:CastFailed)))

; One team's score box: the team's name over its score, in the team's colour, with a team-coloured top edge.
(fn DrawTeamPanel (Team X FlashUntil)
  (bind u (Variables|Layout|GetU))
  (bind color (Other5|Teams|GetTeamColor :Team Team))
  ; Just after the score went up the box glows in the team's colour, fading over half a second.
  (bind flash (Math|Float|Clamp(Float) (* (- FlashUntil (Utilities|Time|GetTimeSeconds)) 2.0) 0.0 1.0))
  (bind (r g b a) (Utilities|Struct|BreakLinearColor color))
  (HUD|DrawRect :RectColor (Utilities|Struct|MakeLinearColor r g b (* flash 0.5)) :ScreenX (- X (* 6.0 u)) :ScreenY (* 14.0 u) :ScreenW (* 222.0 u) :ScreenH (* 124.0 u))
  (CallFunction|DrawPanel :X X :Y (* 20.0 u) :W (* 210.0 u) :H (* 112.0 u) :Accent color)
  (bind cx (+ X (* 105.0 u)))
  (CallFunction|DrawCentered :Text (Utilities|String|ToUpper (Utilities|String|ToString(Text) (Other5|Teams|GetTeamName :Team Team))) :CenterX cx :Y (* 32.0 u) :Color (CallFunction|Muted) :Size 1.6 :bTitle false)
  (CallFunction|DrawCentered :Text (Utilities|String|ToString(Integer) (Other5|Teams|GetTeamScore :Team Team)) :CenterX cx :Y (* 56.0 u) :Color color :Size 4.4 :bTitle true))

; GET READY: the seconds left, huge in the middle, each one popping in big and settling.
(fn DrawCountdown (Left)
  (bind u (Variables|Layout|GetU))
  (bind pop (+ 1.0 (* 0.5 (Math|Float|Power (Math|Float|Fraction Left) 3.0))))
  (CallFunction|DrawCentered :Text (Utilities|String|ToString(Integer) (Math|Float|Ceil Left)) :CenterX (* (Variables|Layout|GetScreenW) 0.5) :Y (- (* (Variables|Layout|GetScreenH) 0.42) (* 60.0 (* u pop))) :Color (CallFunction|Ink) :Size (* 12.0 pop) :bTitle true))

; GO! for a moment when the race starts (PlayRoundSounds sets GoUntil), fading out.
(fn DrawGo ()
  (bind left (- (Variables|Sound|GetGoUntil) (Utilities|Time|GetTimeSeconds)))
  (if (> left 0.0)
    (bind fade (Math|Float|Clamp(Float) (/ left 0.6) 0.0 1.0))
    (bind (r g b a) (Utilities|Struct|BreakLinearColor (CallFunction|Neon)))
    (CallFunction|DrawCentered :Text "GO!" :CenterX (* (Variables|Layout|GetScreenW) 0.5) :Y (* (Variables|Layout|GetScreenH) 0.36) :Color (Utilities|Struct|MakeLinearColor r g b fade) :Size (+ 12.0 (* 4.0 (- 1.0 fade))) :bTitle true)))

; The results: who won and the score, then every player (Red first, then Blue) with their points, outs and place.
(fn DrawResults (Director)
  (bind u (Variables|Layout|GetU))
  (bind cx (* (Variables|Layout|GetScreenW) 0.5))
  ; Higher up while the store is open (it's in the middle of the screen).
  (bind top (* (Variables|Layout|GetScreenH) (select (Variables|Store|GetStoreOpen) 0.135 0.24)))
  (bind players (Class|GameStateBase|GetPlayerArray :self (Game|GetGameState)))
  (bind rows (Utilities|Array|Length players))
  (CallFunction|DrawPanel :X (- cx (* 360.0 u)) :Y top :W (* 720.0 u) :H (* (+ 170.0 (* 40.0 rows)) u) :Accent (CallFunction|Neon))
  (CallFunction|DrawCentered :Text (Class|BPSkiDirector|GetMessage :self Director) :CenterX cx :Y (+ top (* 22.0 u)) :Color (CallFunction|Ink) :Size 3.6 :bTitle true)
  (bind headY (+ top (* 96.0 u)))
  (CallFunction|DrawLeft :Text "player" :X (- cx (* 320.0 u)) :Y headY :Color (CallFunction|Muted) :Size 1.5 :bTitle false)
  (CallFunction|DrawCentered :Text "points" :CenterX (+ cx (* 70.0 u)) :Y headY :Color (CallFunction|Muted) :Size 1.5 :bTitle false)
  (CallFunction|DrawCentered :Text "outs" :CenterX (+ cx (* 175.0 u)) :Y headY :Color (CallFunction|Muted) :Size 1.5 :bTitle false)
  (CallFunction|DrawCentered :Text "place" :CenterX (+ cx (* 275.0 u)) :Y headY :Color (CallFunction|Muted) :Size 1.5 :bTitle false)
  (Variables|Layout|SetRow 0)
  (for player players
    (if (== (Other5|Teams|GetTeam :Player player) 0)
      (CallFunction|DrawResultRow :Player player :Top (+ top (* 130.0 u)))))
  (for player players
    (if (!= (Other5|Teams|GetTeam :Player player) 0)
      (CallFunction|DrawResultRow :Player player :Top (+ top (* 130.0 u))))))

; One scoreboard line (the next Row down from Top).
(fn DrawResultRow (Player Top)
  (bind u (Variables|Layout|GetU))
  (bind cx (* (Variables|Layout|GetScreenW) 0.5))
  (bind y (+ Top (* (* 40.0 u) (Variables|Layout|GetRow))))
  (Variables|Layout|SetRow (+ (Variables|Layout|GetRow) 1))
  (bind color (Other5|Teams|GetTeamColor :Team (Other5|Teams|GetTeam :Player Player)))
  (CallFunction|DrawLeft :Text (PlayerState|GetPlayerName :self Player) :X (- cx (* 320.0 u)) :Y y :Color color :Size 2.0 :bTitle false)
  (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object Player)
    (:then
      (bind place (Class|BPSkiPlayerState|GetFinishPlace :self ski))
      (CallFunction|DrawCentered :Text (Utilities|String|ToString(Integer) (Class|BPSkiPlayerState|GetPoints :self ski)) :CenterX (+ cx (* 70.0 u)) :Y y :Color (CallFunction|Ink) :Size 2.0 :bTitle true)
      (CallFunction|DrawCentered :Text (Utilities|String|ToString(Integer) (Class|BPSkiPlayerState|GetHits :self ski)) :CenterX (+ cx (* 175.0 u)) :Y y :Color (CallFunction|Ink) :Size 2.0 :bTitle true)
      (CallFunction|DrawCentered :Text (select (> place 0) (Utilities|String|Append "#" (Utilities|String|ToString(Integer) place)) (select (Class|BPSkiPlayerState|GetOut :self ski) "OUT" "-")) :CenterX (+ cx (* 275.0 u)) :Y y :Color (select (Class|BPSkiPlayerState|GetOut :self ski) (CallFunction|Bad) (CallFunction|Ink)) :Size 2.0 :bTitle true))
    (:CastFailed)))

; ---- your skier ----------------------------------------------------------------------------------------------------

; Bottom middle: speed (big), team, OUT, outs scored and finish place. Bottom right: the gear (the gun and what's in
; its magazine, or RELOADING; the skis and wax) and coins. (Bottom left is Other5's chat.)
(fn DrawSkier (Skier)
  (bind ski (Class|BPSkiCharacter|GetSkiPlayerState :self Skier))
  (Utilities|IsValid ski
    (:"Is Valid"
      (bind u (Variables|Layout|GetU))
      (bind w (Variables|Layout|GetScreenW))
      (bind bottom (Variables|Layout|GetScreenH))
      (bind out (Class|BPSkiPlayerState|GetOut :self ski))
      (bind teamColor (select out (CallFunction|Muted) (Class|BPSkiCharacter|GetTeamColor :self Skier)))
      (bind place (Class|BPSkiPlayerState|GetFinishPlace :self ski))
      (bind sx (- (* w 0.5) (* 200.0 u)))
      (CallFunction|DrawPanel :X sx :Y (- bottom (* 160.0 u)) :W (* 400.0 u) :H (* 136.0 u) :Accent teamColor)
      (CallFunction|DrawLeft :Text (Utilities|String|ToString(Integer) (Math|Float|Round (Class|BPSkiCharacter|GetSpeedKmh :self Skier))) :X (+ sx (* 20.0 u)) :Y (- bottom (* 146.0 u)) :Color (CallFunction|Ink) :Size 6.0 :bTitle true)
      (CallFunction|DrawLeft :Text "km/h" :X (+ sx (* 212.0 u)) :Y (- bottom (* 110.0 u)) :Color (CallFunction|Muted) :Size 1.8 :bTitle false)
      (bind team (Utilities|String|ToUpper (Utilities|String|ToString(Text) (Other5|Teams|GetTeamName :Team (Other5|Teams|GetTeam :Player ski)))))
      (CallFunction|DrawLeft :Text team :X (+ sx (* 286.0 u)) :Y (- bottom (* 146.0 u)) :Color teamColor :Size 2.0 :bTitle true)
      (if out
        (CallFunction|DrawLeft :Text "OUT" :X (+ sx (* 286.0 u)) :Y (- bottom (* 112.0 u)) :Color (CallFunction|Bad) :Size 2.4 :bTitle true))
      (bind outs (Utilities|String|Append "outs " (Utilities|String|ToString(Integer) (Class|BPSkiPlayerState|GetHits :self ski))))
      (bind status (Utilities|String|Append outs (select (> place 0) (Utilities|String|Append "      finished #" (Utilities|String|ToString(Integer) place)) "")))
      (CallFunction|DrawLeft :Text status :X (+ sx (* 20.0 u)) :Y (- bottom (* 62.0 u)) :Color (CallFunction|Ink) :Size 1.8 :bTitle false)
      ; The gear, bottom right.
      (bind gx (- w (* 424.0 u)))
      (CallFunction|DrawPanel :X gx :Y (- bottom (* 160.0 u)) :W (* 400.0 u) :H (* 136.0 u) :Accent (CallFunction|Gold))
      (bind gunData (Class|BPSkiCharacter|GetCurrentGun :self Skier))
      (bind gun (Utilities|String|ToString(Text) (Class|BPPaintGunData|GetGunName :self gunData)))
      (CallFunction|DrawLeft :Text gun :X (+ gx (* 20.0 u)) :Y (- bottom (* 150.0 u)) :Color (CallFunction|Ink) :Size 2.4 :bTitle true)
      ; The magazine (what's left of it / its size) and the spare paint (+N), or RELOADING, or OUT OF PAINT when both
      ; are gone (till the next run), under the gun's name.
      (bind reloading (Class|BPSkiCharacter|GetReloading :self Skier))
      (bind mag (Class|BPSkiCharacter|MagSizeFor :self Skier :Gun gunData))
      (bind spare (Class|BPSkiCharacter|GetSpare :self Skier))
      (bind ammo (Utilities|String|Append (Utilities|String|ToString(Integer) (Class|BPSkiCharacter|GetAmmo :self Skier)) (Utilities|String|Append " / " (Utilities|String|Append (Utilities|String|ToString(Integer) mag) (Utilities|String|Append "   +" (Utilities|String|ToString(Integer) spare))))))
      (bind empty (<= (Class|BPSkiCharacter|GetAmmo :self Skier) 0))
      (bind dry (and empty (<= spare 0)))
      (bind ammoText (select reloading "RELOADING" (select dry "OUT OF PAINT" ammo)))
      (CallFunction|DrawLeft :Text ammoText :X (+ gx (* 20.0 u)) :Y (- bottom (* 114.0 u)) :Color (select (or reloading empty) (CallFunction|Bad) (CallFunction|Gold)) :Size 1.9 :bTitle true)
      (bind skisData (Class|BPSkiCharacter|CurrentSkis :self Skier))
      (bind wax (Utilities|Array|Get(acopy) (Class|BPSkiCharacter|GetWaxes :self Skier) (Class|BPSkiPlayerState|GetWaxIndex :self ski)))
      (bind skiLine (Utilities|String|Append (Utilities|String|ToString(Text) (Class|BPSkiData|GetSkiName :self skisData)) (Utilities|String|Append "  +  " (Utilities|String|ToString(Text) (Class|BPWaxData|GetWaxName :self wax)))))
      (CallFunction|DrawLeft :Text skiLine :X (+ gx (* 20.0 u)) :Y (- bottom (* 82.0 u)) :Color (CallFunction|Muted) :Size 1.5 :bTitle false)
      (bind coins (Class|BPSkiCharacter|GetCoins :self Skier))
      (CallFunction|DrawLeft :Text (Utilities|String|Append "coins  " (Utilities|String|ToString(Integer) coins)) :X (+ gx (* 20.0 u)) :Y (- bottom (* 54.0 u)) :Color (CallFunction|Gold) :Size 1.8 :bTitle true)
      (CallFunction|DrawLeft :Text "B  store" :X (+ gx (* 300.0 u)) :Y (- bottom (* 52.0 u)) :Color (CallFunction|Muted) :Size 1.4 :bTitle false))
    (:"Is Not Valid")))

; Above your skier, while you're in a fort (BP_SkiFort): whose flag is going up (or who holds it) with a bar, and the
; Exit fort key, or how long until you can use it again.
(fn DrawFort (Skier)
  (bind fort (Class|BPSkiCharacter|CurrentFort :self Skier))
  (Utilities|IsValid fort
    (:"Is Valid"
      (bind u (Variables|Layout|GetU))
      (bind w (Variables|Layout|GetScreenW))
      (bind bottom (Variables|Layout|GetScreenH))
      (bind captured (Class|BPSkiFort|GetCapturedBy :self fort))
      (bind progress (Class|BPSkiFort|GetProgress :self fort))
      (bind team (select (>= captured 0) captured (Class|BPSkiFort|GetProgressTeam :self fort)))
      (bind shown (and (>= team 0) (or (>= captured 0) (> progress 0.0))))
      (bind color (select shown (Other5|Teams|GetTeamColor :Team team) (CallFunction|Muted)))
      (bind teamName (Utilities|String|ToUpper (Utilities|String|ToString(Text) (Other5|Teams|GetTeamName :Team team))))
      (bind percent (Utilities|String|Append (Utilities|String|ToString(Integer) (Math|Float|Round (* progress 100.0))) "%"))
      (bind status (select (>= captured 0) (Utilities|String|Append "FORT HELD BY " teamName) (select shown (Utilities|String|Append (Utilities|String|Append "RAISING " teamName) (Utilities|String|Append " FLAG  " percent)) "FORT: STAY IN TO RAISE YOUR FLAG")))
      (bind fx (- (* w 0.5) (* 200.0 u)))
      (bind fy (- bottom (* 262.0 u)))
      (CallFunction|DrawPanel :X fx :Y fy :W (* 400.0 u) :H (* 90.0 u) :Accent color)
      (CallFunction|DrawLeft :Text status :X (+ fx (* 20.0 u)) :Y (+ fy (* 12.0 u)) :Color color :Size 1.7 :bTitle true)
      (HUD|DrawRect :RectColor (Utilities|Struct|MakeLinearColor 1.0 1.0 1.0 0.12) :ScreenX (+ fx (* 20.0 u)) :ScreenY (+ fy (* 42.0 u)) :ScreenW (* 360.0 u) :ScreenH (* 8.0 u))
      (HUD|DrawRect :RectColor color :ScreenX (+ fx (* 20.0 u)) :ScreenY (+ fy (* 42.0 u)) :ScreenW (* (* 360.0 u) progress) :ScreenH (* 8.0 u))
      (bind wait (- (Class|BPSkiCharacter|GetExitReadyAt :self Skier) (GameState|GetServerWorldTimeSeconds :self (Game|GetGameState))))
      (bind exitText (select (> wait 0.0) (Utilities|String|Append "exit fort in " (Utilities|String|Append (Utilities|String|ToString(Integer) (Math|Float|Ceil wait)) " s")) "F  exit fort"))
      (CallFunction|DrawLeft :Text exitText :X (+ fx (* 20.0 u)) :Y (+ fy (* 58.0 u)) :Color (CallFunction|Ink) :Size 1.5 :bTitle false))
    (:"Is Not Valid")))

; ---- sounds ----------------------------------------------------------------------------------------------------------

; This machine's round sounds, from what the director replicates: phase changes (GO!, the results fanfare), each
; countdown second, and a team's score going up.
(fn PlayRoundSounds (Director)
  (bind phase (Class|BPSkiDirector|GetPhase :self Director))
  (bind now (Utilities|Time|GetTimeSeconds))
  (if (!= phase (Variables|Sound|GetLastPhase))
    (if (and (== phase 2) (== (Variables|Sound|GetLastPhase) 1))
      (Variables|Sound|SetGoUntil (+ now 1.2))
      (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiGo.S_SkiGo"))
    (if (== phase 3)
      (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiFanfare.S_SkiFanfare"))
    (Variables|Sound|SetLastPhase phase))
  ; Countdown: a beep as each second starts.
  (bind second (Math|Float|Ceil (- (Class|BPSkiDirector|GetPhaseEndsAt :self Director) (Class|BPSkiDirector|Now :self Director))))
  (if (and (== phase 1) (!= second (Variables|Sound|GetLastSecond)))
    (if (> second 0)
      (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiBeep.S_SkiBeep")))
  (Variables|Sound|SetLastSecond second)
  ; Scores: a chime and a flash on the team's box when it goes up (not when the round resets them to 0).
  (bind red (Other5|Teams|GetTeamScore :Team 0))
  (bind blue (Other5|Teams|GetTeamScore :Team 1))
  (if (> red (Variables|Sound|GetLastScore0))
    (Variables|Sound|SetFlash0Until (+ now 0.5))
    (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiScore.S_SkiScore" :VolumeMultiplier 0.7))
  (if (> blue (Variables|Sound|GetLastScore1))
    (Variables|Sound|SetFlash1Until (+ now 0.5))
    (Audio|PlaySound2D :Sound "/SKIvSKI/Audio/S_SkiScore.S_SkiScore" :VolumeMultiplier 0.7))
  (Variables|Sound|SetLastScore0 red)
  (Variables|Sound|SetLastScore1 blue))

; ---- pop-ups ---------------------------------------------------------------------------------------------------------

; A word that pops up over Where and flies up, fading, over PopupSeconds ("Hit!" at Size 1, "Bounce!" smaller).
; Called on every machine. With a Target (the skier who was hit) it follows them: skiers move at 20 m/s, so a word
; left at the spot of the hit was behind everyone within a second.
(fn AddPopup (Text Where Color Size Target)
  (Utilities|Array|Add (Variables|Popups|GetPopupTexts) Text)
  (Utilities|Array|Add (Variables|Popups|GetPopupTargets) Target)
  (CallFunction|AddPopupLook :Color Color :Size Size)
  ; Kept relative to the Target when there is one, else as the spot in the world.
  (Utilities|IsValid Target
    (:"Is Valid"
      (Utilities|Array|Add (Variables|Popups|GetPopupPlaces) (- Where (Transformation|GetActorLocation :self Target))))
    (:"Is Not Valid"
      (Utilities|Array|Add (Variables|Popups|GetPopupPlaces) Where))))

(fn AddPopupLook (Color Size)
  (Utilities|Array|Add (Variables|Popups|GetPopupColors) Color)
  (Utilities|Array|Add (Variables|Popups|GetPopupSizes) Size)
  (Utilities|Array|Add (Variables|Popups|GetPopupStarts) (Utilities|Time|GetTimeSeconds)))

; Where pop-up Index is in the world now: on its Target if it still has one.
(fn PopupSpot (Index)
  (bind target (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupTargets) Index))
  (bind place (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupPlaces) Index))
  (Utilities|IsValid target
    (:"Is Valid"
      (return (+ (Transformation|GetActorLocation :self target) place)))
    (:"Is Not Valid"
      (return place))))

; Each pop-up starts nearly twice its size and settles in a fifth of its life, flies up the screen (fast, then
; slowing), and fades over its last 40%, drawn where its skier (or spot) is on screen, outlined so it reads against
; snow and sky alike.
(fn DrawPopups ()
  (bind now (Utilities|Time|GetTimeSeconds))
  (bind life (Variables|Popups|GetPopupSeconds))
  (bind u (Variables|Layout|GetU))
  ; Drop the ones that are over (from the last back, so removing doesn't shift the ones still to check).
  (bind count (Utilities|Array|Length (Variables|Popups|GetPopupStarts)))
  (for k (range count)
    (bind old (- (- count 1) k))
    (if (> (- now (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupStarts) old)) life)
      (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupTexts) old)
      (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupTargets) old)
      (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupPlaces) old)
      (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupColors) old)
      (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupSizes) old)
      (Utilities|Array|RemoveIndex (Variables|Popups|GetPopupStarts) old)))
  (for i (range (Utilities|Array|Length (Variables|Popups|GetPopupStarts)))
    (bind age (/ (- now (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupStarts) i)) life))
    (bind screen (HUD|Project :Location (CallFunction|PopupSpot :Index i) :bClampToZeroPlane false))
    ; Behind the camera Project gives Z <= 0: skip those.
    (if (> (.z screen) 0.0)
      (bind rise (- 1.0 (Math|Float|Power (- 1.0 age) 3.0)))
      (bind pop (+ 1.0 (* 0.9 (Math|Float|Max(Float) (- 1.0 (* age 5.0)) 0.0))))
      (bind fade (Math|Float|Clamp(Float) (/ (- 1.0 age) 0.4) 0.0 1.0))
      (bind (r g b a) (Utilities|Struct|BreakLinearColor (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupColors) i)))
      ; A little lighter than the team colour, so it stands out from the skier's own helmet and skis.
      (bind light (Utilities|Struct|MakeLinearColor (Math|Float|Lerp r 1.0 0.25) (Math|Float|Lerp g 1.0 0.25) (Math|Float|Lerp b 1.0 0.25) fade))
      (CallFunction|DrawOutlined :Text (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupTexts) i) :CenterX (.x screen) :Y (- (.y screen) (* (* rise 220.0) u)) :Color light :Size (* (* (Utilities|Array|Get(acopy) (Variables|Popups|GetPopupSizes) i) 8.0) pop)))))

; Big text centred on CenterX with a dark outline all round (drawn four times offset, then on top).
(fn DrawOutlined (Text CenterX Y Color Size)
  (bind u (Variables|Layout|GetU))
  (bind scale (* (* Size u) 0.125))
  (bind (w h) (HUD|GetTextSize :Text Text :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale))
  (bind x (- CenterX (* w 0.5)))
  (bind (r g b a) (Utilities|Struct|BreakLinearColor Color))
  (bind edge (Utilities|Struct|MakeLinearColor 0.0 0.0 0.0 (* a 0.85)))
  (bind o (Math|Float|Max(Float) (* (* Size 0.35) u) 1.5))
  (HUD|DrawText :Text Text :TextColor edge :ScreenX (- x o) :ScreenY (- Y o) :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale)
  (HUD|DrawText :Text Text :TextColor edge :ScreenX (+ x o) :ScreenY (- Y o) :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale)
  (HUD|DrawText :Text Text :TextColor edge :ScreenX (- x o) :ScreenY (+ Y o) :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale)
  (HUD|DrawText :Text Text :TextColor edge :ScreenX (+ x o) :ScreenY (+ Y o) :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale)
  (HUD|DrawText :Text Text :TextColor Color :ScreenX x :ScreenY Y :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale))

; ---- the store -------------------------------------------------------------------------------------------------------
; Between runs (the lobby and the results) B opens and closes the store; it also opens by itself when the results come
; up, and closes when the countdown starts. While it's open the mouse pointer shows: click an item to buy it, or to put
; back on one you already have. Four columns: guns, skis, wax and paint upgrades (the character's Guns, Skis, Waxes and
; Upgrades, in that order). Each item is a hit box (Add Hit Box) named by its column's letter and its number (G0, S2,
; W1, U0...); a click on one
; comes to Event Hit Box Clicked, which asks the server (the character's ServerBuy): the server checks the phase and
; the coins, and the player state brings the result back (coins, what's owned, what's on).

; B (BP_SkiCharacter ToggleMyStore): open the store, or close it; it only opens between runs.
(fn ToggleStore ()
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (Utilities|IsValid director
    (:"Is Valid"
      (bind phase (Class|BPSkiDirector|GetPhase :self director))
      (CallFunction|SetStoreOpen :bOpen (and (not (Variables|Store|GetStoreOpen)) (or (== phase 0) (== phase 3)))))
    (:"Is Not Valid")))

; Open: the mouse pointer shows and clicks reach the hit boxes (Enable Click Events), the game keeps its keys (Game and
; UI). Closed: back to the game alone (the mouse aims again).
(fn SetStoreOpen (bOpen)
  (Variables|Store|SetStoreOpen bOpen)
  (bind pc (HUD|GetOwningPlayerController))
  (Class|PlayerController|SetShowMouseCursor :self pc :bShowMouseCursor bOpen)
  (Class|PlayerController|SetEnableClickEvents :self pc :bEnableClickEvents bOpen)
  (if bOpen
    (Input|SetInputModeGameAndUI :PlayerController pc :bHideCursorDuringCapture false)
    (else
      (Input|SetInputModeGameOnly :PlayerController pc))))

; The store panel, in the middle of the screen: coins, the three columns, and what the item under the mouse is. With
; the results it sits under their list (DrawResults: 170 + 40 per player, from 13.5% down).
(fn DrawStore (Skier)
  (bind u (Variables|Layout|GetU))
  (bind cx (* (Variables|Layout|GetScreenW) 0.5))
  (bind screenH (Variables|Layout|GetScreenH))
  (bind director (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiDirector.BP_SkiDirector_C"))
  (bind results (== (Class|BPSkiDirector|GetPhase :self director) 3))
  (bind rows (Math|Conversions|ToFloat(Integer) (Utilities|Array|Length (Class|GameStateBase|GetPlayerArray :self (Game|GetGameState)))))
  (bind under (+ (* screenH 0.135) (* (+ 186.0 (* 40.0 rows)) u)))
  (bind top (select results (Math|Float|Max(Float) (* screenH 0.32) under) (* screenH 0.32)))
  (Variables|Store|SetStoreHint "")
  (CallFunction|DrawPanel :X (- cx (* 570.0 u)) :Y top :W (* 1140.0 u) :H (* 450.0 u) :Accent (CallFunction|Gold))
  (CallFunction|DrawLeft :Text "STORE" :X (- cx (* 545.0 u)) :Y (+ top (* 16.0 u)) :Color (CallFunction|Ink) :Size 3.0 :bTitle true)
  (bind coins (Class|BPSkiCharacter|GetCoins :self Skier))
  (CallFunction|DrawLeft :Text (Utilities|String|Append "coins  " (Utilities|String|ToString(Integer) coins)) :X (- cx (* 330.0 u)) :Y (+ top (* 22.0 u)) :Color (CallFunction|Gold) :Size 2.2 :bTitle true)
  (CallFunction|DrawLeft :Text "earn coins: 3 for each opponent you put out, 10 for getting through a race" :X (- cx (* 80.0 u)) :Y (+ top (* 28.0 u)) :Color (CallFunction|Muted) :Size 1.4 :bTitle false)
  (CallFunction|DrawStoreColumn :Skier Skier :Kind 0 :X (- cx (* 558.0 u)) :Y (+ top (* 76.0 u)))
  (CallFunction|DrawStoreColumn :Skier Skier :Kind 1 :X (- cx (* 279.0 u)) :Y (+ top (* 76.0 u)))
  (CallFunction|DrawStoreColumn :Skier Skier :Kind 2 :X cx :Y (+ top (* 76.0 u)))
  (CallFunction|DrawStoreColumn :Skier Skier :Kind 3 :X (+ cx (* 279.0 u)) :Y (+ top (* 76.0 u)))
  ; The item under the mouse, in a sentence; otherwise how to use the store.
  (bind hint (Variables|Store|GetStoreHint))
  (CallFunction|DrawCentered :Text (select (> (Utilities|String|Len hint) 0) hint "click an item to buy it, or to put it back on      B  closes") :CenterX cx :Y (+ top (* 408.0 u)) :Color (CallFunction|Ink) :Size 1.6 :bTitle false))

; One column: its heading and its items, each with a line of what it does.
(fn DrawStoreColumn (Skier Kind X Y)
  (bind u (Variables|Layout|GetU))
  (CallFunction|DrawLeft :Text (select (== Kind 0) "MARKERS" (select (== Kind 1) "SKIS" (select (== Kind 2) "WAX" "UPGRADES"))) :X X :Y Y :Color (CallFunction|Muted) :Size 1.6 :bTitle true)
  (Variables|Store|SetStoreRow 0)
  (if (== Kind 0)
    (for gun (Class|BPSkiCharacter|GetGuns :self Skier)
      (bind auto (select (Class|BPPaintGunData|GetFullAuto :self gun) "full-auto" "semi-auto"))
      ; The magazine with this player's hopper.
      (bind mag (Class|BPSkiCharacter|MagSizeFor :self Skier :Gun gun))
      (bind shots (Utilities|String|Append (Utilities|String|ToString(Integer) mag) " shots"))
      (bind pellets (select (> (Class|BPPaintGunData|GetPelletsPerShot :self gun) 1) (Utilities|String|Append (Utilities|String|ToString(Integer) (Class|BPPaintGunData|GetPelletsPerShot :self gun)) " balls  ") ""))
      (bind detail (Utilities|String|Append (Utilities|String|Append pellets auto) (Utilities|String|Append "  " (Utilities|String|Append shots (Utilities|String|Append "  reload " (Utilities|String|Append (Utilities|String|ToString(Float) (Class|BPPaintGunData|GetReloadSeconds :self gun)) " s"))))))
      (CallFunction|DrawStoreItem :Skier Skier :Kind 0 :Index (Variables|Store|GetStoreRow) :Name (Utilities|String|ToString(Text) (Class|BPPaintGunData|GetGunName :self gun)) :Detail detail :Price (Class|BPPaintGunData|GetPrice :self gun) :X X :Y (+ Y (* 34.0 u)))
      (Variables|Store|SetStoreRow (+ (Variables|Store|GetStoreRow) 1))))
  (if (== Kind 1)
    (for skis (Class|BPSkiCharacter|GetSkis :self Skier)
      (bind speed (Utilities|String|Append "speed " (Utilities|String|Append (Utilities|String|ToString(Integer) (Math|Float|Round (* (Class|BPSkiData|GetSpeedScale :self skis) 100.0))) "%")))
      (bind turn (Utilities|String|Append "  turn " (Utilities|String|Append (Utilities|String|ToString(Integer) (Math|Float|Round (* (Class|BPSkiData|GetTurnScale :self skis) 100.0))) "%")))
      (bind stop (Utilities|String|Append "  stop " (Utilities|String|Append (Utilities|String|ToString(Integer) (Math|Float|Round (* (Class|BPSkiData|GetBrakeScale :self skis) 100.0))) "%")))
      (CallFunction|DrawStoreItem :Skier Skier :Kind 1 :Index (Variables|Store|GetStoreRow) :Name (Utilities|String|ToString(Text) (Class|BPSkiData|GetSkiName :self skis)) :Detail (Utilities|String|Append speed (Utilities|String|Append turn stop)) :Price (Class|BPSkiData|GetPrice :self skis) :X X :Y (+ Y (* 34.0 u)))
      (Variables|Store|SetStoreRow (+ (Variables|Store|GetStoreRow) 1))))
  (if (== Kind 2)
    (for wax (Class|BPSkiCharacter|GetWaxes :self Skier)
      (bind detail (Utilities|String|Append "snow friction " (Utilities|String|ToString(Float) (Class|BPWaxData|GetSnowFriction :self wax))))
      (CallFunction|DrawStoreItem :Skier Skier :Kind 2 :Index (Variables|Store|GetStoreRow) :Name (Utilities|String|ToString(Text) (Class|BPWaxData|GetWaxName :self wax)) :Detail detail :Price (Class|BPWaxData|GetPrice :self wax) :X X :Y (+ Y (* 34.0 u)))
      (Variables|Store|SetStoreRow (+ (Variables|Store|GetStoreRow) 1))))
  (if (== Kind 3)
    (for up (Class|BPSkiCharacter|GetUpgrades :self Skier)
      ; "magazine +50%" for a bigger hopper, "+3 spare magazines" for more paint (either, or both).
      (bind scale (Class|BPUpgradeData|GetMagScale :self up))
      (bind extra (Class|BPUpgradeData|GetSpareMags :self up))
      (bind bigger (select (> scale 1.0) (Utilities|String|Append "magazine +" (Utilities|String|Append (Utilities|String|ToString(Integer) (Math|Float|Round (* (- scale 1.0) 100.0))) "%  ")) ""))
      (bind more (select (> extra 0) (Utilities|String|Append "+" (Utilities|String|Append (Utilities|String|ToString(Integer) extra) " spare magazines")) ""))
      (CallFunction|DrawStoreItem :Skier Skier :Kind 3 :Index (Variables|Store|GetStoreRow) :Name (Utilities|String|ToString(Text) (Class|BPUpgradeData|GetUpgradeName :self up)) :Detail (Utilities|String|Append bigger more) :Price (Class|BPUpgradeData|GetPrice :self up) :X X :Y (+ Y (* 34.0 u)))
      (Variables|Store|SetStoreRow (+ (Variables|Store|GetStoreRow) 1)))))

; One item (row Index of the column): a box with its name, its line of numbers and, on the right, ON (what you have
; on; an upgrade is on once it's yours), OWNED (yours: click to put it back on), or its price (gold if you can afford
; it). Brighter under the mouse.
(fn DrawStoreItem (Skier Kind Index Name Detail Price X Y)
  (bind u (Variables|Layout|GetU))
  (bind ski (Class|BPSkiCharacter|GetSkiPlayerState :self Skier))
  (bind y (+ Y (* (* 72.0 u) (Math|Conversions|ToFloat(Integer) Index))))
  (bind w (* 270.0 u))
  (bind h (* 64.0 u))
  (bind owned (or (== Price 0) (Utilities|Array|ContainsItem (Class|BPSkiPlayerState|GetOwned :self ski) (+ (* Kind 100) Index))))
  (bind on (select (== Kind 3) owned (== Index (select (== Kind 0) (Class|BPSkiPlayerState|GetGunIndex :self ski) (select (== Kind 1) (Class|BPSkiPlayerState|GetSkisIndex :self ski) (Class|BPSkiPlayerState|GetWaxIndex :self ski))))))
  (bind coins (Class|BPSkiPlayerState|GetCoins :self ski))
  (bind (mx my found) (Game|Player|GetMousePosition :self (HUD|GetOwningPlayerController)))
  (bind over (and (and (>= mx X) (<= mx (+ X w))) (and (>= my y) (<= my (+ y h)))))
  (HUD|DrawRect :RectColor (Utilities|Struct|MakeLinearColor 0.2 0.18 0.45 (select over 0.55 0.25)) :ScreenX X :ScreenY y :ScreenW w :ScreenH h)
  (if on
    (HUD|DrawRect :RectColor (CallFunction|Neon) :ScreenX X :ScreenY y :ScreenW (* 5.0 u) :ScreenH h))
  (CallFunction|DrawLeft :Text Name :X (+ X (* 16.0 u)) :Y (+ y (* 8.0 u)) :Color (CallFunction|Ink) :Size 2.0 :bTitle false)
  (CallFunction|DrawLeft :Text Detail :X (+ X (* 16.0 u)) :Y (+ y (* 38.0 u)) :Color (CallFunction|Muted) :Size 1.2 :bTitle false)
  (bind label (select on "ON" (select owned "OWNED" (Utilities|String|ToString(Integer) Price))))
  (bind labelColor (select on (CallFunction|Neon) (select owned (CallFunction|Ink) (select (>= coins Price) (CallFunction|Gold) (CallFunction|Muted)))))
  (bind (lw lh) (HUD|GetTextSize :Text label :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale (* (* 1.8 u) 0.125)))
  (CallFunction|DrawLeft :Text label :X (- (+ X w) (+ lw (* 14.0 u))) :Y (+ y (* 10.0 u)) :Color labelColor :Size 1.8 :bTitle true)
  ; Under the mouse: the item's sentence goes to the bottom of the store (DrawStore shows it).
  (if over
    (bind blurb (Class|BPSkiCharacter|GearBlurb :self Skier :Kind Kind :Index Index))
    (Variables|Store|SetStoreHint (Utilities|String|Append Name (Utilities|String|Append ":  " blurb))))
  (HUD|AddHitBox :Position (Math|Vector2D|MakeVector2D X y) :Size (Math|Vector2D|MakeVector2D w h) :InName (Utilities|String|StringToName (Utilities|String|Append (select (== Kind 0) "G" (select (== Kind 1) "S" (select (== Kind 2) "W" "U"))) (Utilities|String|ToString(Integer) Index))) :bConsumesInput true :Priority 0))

; A click on a store item: its hit box's name says which (G, S, W or U, then its number). The server decides
; (ServerBuy).
(event EventHitBoxClicked (BoxName)
  (bind name (Utilities|String|ToString(Name) BoxName))
  (bind letter (Utilities|String|GetSubstring :SourceString name :StartIndex 0 :Length 1))
  (bind kind (select (Utilities|String|Equal,CaseInsensitive(String) letter "G") 0 (select (Utilities|String|Equal,CaseInsensitive(String) letter "S") 1 (select (Utilities|String|Equal,CaseInsensitive(String) letter "W") 2 3))))
  (bind index (Utilities|String|StringToInteger (Utilities|String|GetSubstring :SourceString name :StartIndex 1 :Length 3)))
  (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (HUD|GetOwningPawn))
    (:then
      (Class|BPSkiCharacter|ServerBuy :self skier :Kind kind :Index index))
    (:CastFailed)))

; ---- drawing helpers -------------------------------------------------------------------------------------------------

; A panel: dark and see-through, with a 4-pixel top edge in Accent.
(fn DrawPanel (X Y W H Accent)
  (bind u (Variables|Layout|GetU))
  (HUD|DrawRect :RectColor (Utilities|Struct|MakeLinearColor 0.007 0.005 0.025 0.82) :ScreenX X :ScreenY Y :ScreenW W :ScreenH H)
  (HUD|DrawRect :RectColor Accent :ScreenX X :ScreenY Y :ScreenW W :ScreenH (* 4.0 u)))

; Text centred on CenterX, top at Y. Size is in 9-point steps for a 1080-pixel-high screen; bTitle picks Orbitron
; (Font_SkiTitle, 72 points, so scaled by 9 / 72), else Exo 2 (Font_SkiText, 32 points, scaled by 9 / 32).
(fn DrawCentered (Text CenterX Y Color Size bTitle)
  (bind scale (* (* Size (Variables|Layout|GetU)) (select bTitle 0.125 0.28125)))
  (if bTitle
    (bind (w h) (HUD|GetTextSize :Text Text :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale))
    (CallFunction|DrawLeft :Text Text :X (- CenterX (* w 0.5)) :Y Y :Color Color :Size Size :bTitle true)
    (else
      (bind (w2 h2) (HUD|GetTextSize :Text Text :Font "/SKIvSKI/UI/Font_SkiText.Font_SkiText" :Scale scale))
      (CallFunction|DrawLeft :Text Text :X (- CenterX (* w2 0.5)) :Y Y :Color Color :Size Size :bTitle false))))

; Text with its top-left at X, Y and a soft drop shadow (as see-through as the text).
(fn DrawLeft (Text X Y Color Size bTitle)
  (bind u (Variables|Layout|GetU))
  (bind scale (* (* Size u) (select bTitle 0.125 0.28125)))
  (bind (r g b a) (Utilities|Struct|BreakLinearColor Color))
  (bind shadow (Utilities|Struct|MakeLinearColor 0.0 0.0 0.0 (* a 0.6)))
  (bind off (Math|Float|Max(Float) (* 2.0 u) 1.0))
  (if bTitle
    (HUD|DrawText :Text Text :TextColor shadow :ScreenX (+ X off) :ScreenY (+ Y off) :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale)
    (HUD|DrawText :Text Text :TextColor Color :ScreenX X :ScreenY Y :Font "/SKIvSKI/UI/Font_SkiTitle.Font_SkiTitle" :Scale scale)
    (else
      (HUD|DrawText :Text Text :TextColor shadow :ScreenX (+ X off) :ScreenY (+ Y off) :Font "/SKIvSKI/UI/Font_SkiText.Font_SkiText" :Scale scale)
      (HUD|DrawText :Text Text :TextColor Color :ScreenX X :ScreenY Y :Font "/SKIvSKI/UI/Font_SkiText.Font_SkiText" :Scale scale))))

; Other5's UI colours (Docs/UIStyleGuide.html), as linear colours (the canvas works in linear colour).
(fn Ink ()
  (return (Utilities|Struct|MakeLinearColor 0.815 0.791 1.0 1.0)))

(fn Muted ()
  (return (Utilities|Struct|MakeLinearColor 0.323 0.291 0.578 1.0)))

(fn Neon ()
  (return (Utilities|Struct|MakeLinearColor 1.0 0.028 0.456 1.0)))

(fn Gold ()
  (return (Utilities|Struct|MakeLinearColor 1.0 0.539 0.046 1.0)))

(fn Bad ()
  (return (Utilities|Struct|MakeLinearColor 1.0 0.074 0.147 1.0)))
