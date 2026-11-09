; BP_SkiDirector: rounds and teams, in Unreal MCP's Blueprint graph DSL (BlueprintTools.write_graph_dsl).
; A child of Other5's Game Coordinator (AOther5GameCoordinator), placed once in the level. Kept as text so the logic
; can be reviewed; the asset itself is binary.
;
; Only the server decides; it replicates Phase, PhaseEndsAt, the scores, the difficulty and a message, which the
; HUD (BP_SkiHUD) shows. Every player's team, hits and finish place live on their BP_SkiPlayerState.
;
; A round:  Lobby (LobbySeconds, everyone on the flat snow behind the gates; T switches team; an admin can change
;           the difficulty with [ and ]) -> Countdown (CountdownSeconds, everyone frozen behind their team's gate)
;           -> Race (until everyone has crossed the finish, or RaceSeconds) -> Results (ResultsSeconds) -> Lobby
;           with a new random slope.
; Scoring:  each paintball hit on the other team during the race: HitPoints for the shooter's team. Crossing the
;           finish: FinishPoints[place - 1] for your team (10, 8, 6, 5, 4, 3, 2, 1, then nothing). Most points wins.
; Phases:   0 Lobby, 1 Countdown, 2 Race, 3 Results.

(event Coordinator|EventOnCoordinatorStarted
  (if (Coordinator|RunsGame)
    (CallFunction|SetupRounds)))

; A player joined: put them on the team with fewer players (server).
(event Coordinator|EventOnPlayerJoined (Player)
  (if (Coordinator|RunsGame)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object Player)
      (:then
        (Class|BPSkiPlayerState|SetTeam :self ski :Team (select (> (CallFunction|CountTeam :Team 0) (CallFunction|CountTeam :Team 1)) 1 0))
        (Class|BPSkiPlayerState|SetJoinedTeam :self ski :bJoinedTeam true))
      (:CastFailed))))

; A player got a character (joined, or came back after a fall): put it where the round wants it (server).
(event Coordinator|EventOnPlayerPawnChanged (Player NewPawn OldPawn)
  (if (Coordinator|RunsGame)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object Player)
      (:then
        (CallFunction|PlaceOne :Player ski :bAtGate (or (== (Variables|Round|State|GetPhase) 1) (== (Variables|Round|State|GetPhase) 2)) :Index 7))
      (:CastFailed))))

; The time everyone agrees on (the server's clock, replicated by the game state).
(fn Now ()
  (return (GameState|GetServerWorldTimeSeconds :self (Game|GetGameState))))

; The slope this director runs: the Slope set on it in the level, or else the first BP_SkiSlope found.
(fn FindSlope ()
  (Utilities|IsValid (Variables|Round|Settings|GetSlope)
    (:"Is Valid"
      (return true))
    (:"Is Not Valid"
      (Variables|Round|Settings|SetSlope (Actor|GetActorOfClass :ActorClass "/SKIvSKI/Blueprints/BP_SkiSlope.BP_SkiSlope_C"))
      (Utilities|IsValid (Variables|Round|Settings|GetSlope)
        (:"Is Valid"
          (return true))
        (:"Is Not Valid"
          (return false))))))

(fn SetupRounds ()
  (CallFunction|FindSlope)
  ; The server can be started with -SkiDifficulty=Easy, Medium or Hard; otherwise the slope's Start Difficulty.
  (bind (value found) (Utilities|ParseParamValue (Utilities|GetCommandLine) "SkiDifficulty="))
  (Variables|Round|State|SetDifficulty (Class|BPSkiSlope|GetStartDifficulty :self (Variables|Round|Settings|GetSlope)))
  (if found
    (Variables|Round|State|SetDifficulty (select (Utilities|String|Equal,CaseInsensitive(String) value "Easy") 0 (select (Utilities|String|Equal,CaseInsensitive(String) value "Hard") 2 1))))
  (CallFunction|StartLobby)
  (Utilities|Time|SetTimerbyFunctionName :Object self :FunctionName "ServerStep" :Time 0.25 :bLooping true))

; Four times a second on the server: move the round on.
(fn ServerStep ()
  (bind now (CallFunction|Now))
  (bind phase (Variables|Round|State|GetPhase))
  (if (== phase 0)
    (CallFunction|RescueLost :bAtGate false)
    (if (< (Utilities|Array|Length (Coordinator|GetTrackedPlayers)) (Variables|Round|Settings|GetMinPlayers))
      (Variables|Round|State|SetPhaseEndsAt (+ now (Variables|Round|Settings|GetLobbySeconds)))
      (elif (>= now (Variables|Round|State|GetPhaseEndsAt))
        (CallFunction|StartCountdown))))
  (if (and (== phase 1) (>= now (Variables|Round|State|GetPhaseEndsAt)))
    (CallFunction|StartRace))
  (if (== phase 2)
    (CallFunction|CheckRacers)
    (if (or (>= now (Variables|Round|State|GetPhaseEndsAt)) (Variables|Round|Work|GetAllFinished))
      (CallFunction|EndRace)))
  (if (== phase 3)
    (CallFunction|RescueLost :bAtGate false)
    (if (>= now (Variables|Round|State|GetPhaseEndsAt))
      (CallFunction|StartLobby))))

(fn StartLobby ()
  (Variables|Round|State|SetPhase 0)
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (Variables|Round|Settings|GetLobbySeconds)))
  (Variables|Round|State|SetRedScore 0)
  (Variables|Round|State|SetBlueScore 0)
  (Variables|Round|State|SetMessage "Lobby: T switches team")
  ; A new random slope; the lobby itself is always flat, so nobody falls while it rebuilds.
  (Class|BPSkiSlope|Rebuild :self (Variables|Round|Settings|GetSlope) :NewSeed (Math|Random|RandomIntegerinRange 1 999999) :NewDifficulty (Variables|Round|State|GetDifficulty))
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (Class|BPSkiPlayerState|SetHits :self ski :Hits 0)
        (Class|BPSkiPlayerState|SetPoints :self ski :Points 0)
        (Class|BPSkiPlayerState|SetFinishPlace :self ski :FinishPlace 0)
        (Class|BPSkiPlayerState|SetFinishTime :self ski :FinishTime 0.0))
      (:CastFailed)))
  (CallFunction|PlaceAll :bAtGate false :bFreeze false))

(fn StartCountdown ()
  (Variables|Round|State|SetPhase 1)
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (Variables|Round|Settings|GetCountdownSeconds)))
  (Variables|Round|State|SetRoundNumber (+ (Variables|Round|State|GetRoundNumber) 1))
  (Variables|Round|State|SetMessage "Get ready!")
  (CallFunction|PlaceAll :bAtGate true :bFreeze true))

(fn StartRace ()
  (Variables|Round|State|SetPhase 2)
  (Variables|Round|Work|SetRaceStartedAt (CallFunction|Now))
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (Variables|Round|Settings|GetRaceSeconds)))
  (Variables|Round|Work|SetNextPlace 1)
  (Variables|Round|Work|SetAllFinished false)
  (Variables|Round|State|SetMessage "GO!")
  (CallFunction|FreezeAll :bFreeze false))

(fn EndRace ()
  (Variables|Round|State|SetPhase 3)
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (Variables|Round|Settings|GetResultsSeconds)))
  (bind red (Variables|Round|State|GetRedScore))
  (bind blue (Variables|Round|State|GetBlueScore))
  (bind score (Utilities|String|Append (Utilities|String|ToString(Integer) red) (Utilities|String|Append " - " (Utilities|String|ToString(Integer) blue))))
  (Variables|Round|State|SetMessage (Utilities|String|Append (select (> red blue) "RED WINS " (select (> blue red) "BLUE WINS " "A DRAW ")) score)))

; Everyone to the lobby (bAtGate false) or behind their team's start gate.
(fn PlaceAll (bAtGate bFreeze)
  (Variables|Round|Work|SetRedPlaced 0)
  (Variables|Round|Work|SetBluePlaced 0)
  (Variables|Round|Work|SetLobbyPlaced 0)
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (CallFunction|PlaceOne :Player ski :bAtGate bAtGate :Index -1))
      (:CastFailed)))
  (CallFunction|FreezeAll :bFreeze bFreeze))

; One player's character to the lobby or their gate. Index -1 takes the next free spot.
(fn PlaceOne (Player bAtGate Index)
  (if (CallFunction|FindSlope)
  (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (PlayerState|GetPawn :self Player))
    (:then
      (bind team (Class|BPSkiPlayerState|GetTeam :self Player))
      (if bAtGate
        (bind count (select (== team 0) (Variables|Round|Work|GetRedPlaced) (Variables|Round|Work|GetBluePlaced)))
        (Class|BPSkiCharacter|PlaceAt :self skier :Spot (Class|BPSkiSlope|GetStartSpot :self (Variables|Round|Settings|GetSlope) :Team team :Index (select (< Index 0) count Index)))
        (if (== team 0)
          (Variables|Round|Work|SetRedPlaced (+ count 1))
          (else
            (Variables|Round|Work|SetBluePlaced (+ count 1))))
        (else
          (bind spot (Variables|Round|Work|GetLobbyPlaced))
          (Class|BPSkiCharacter|PlaceAt :self skier :Spot (Class|BPSkiSlope|GetLobbySpot :self (Variables|Round|Settings|GetSlope) :Index (select (< Index 0) spot Index)))
          (Variables|Round|Work|SetLobbyPlaced (+ spot 1)))))
    (:CastFailed))))

(fn FreezeAll (bFreeze)
  (for player (Coordinator|GetTrackedPlayers)
    (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (PlayerState|GetPawn :self player))
      (:then
        (Class|BPSkiCharacter|SetSkiFrozen :self skier :bSkiFrozen bFreeze))
      (:CastFailed))))

; During the race: who crossed the finish, who is lost (fell off, left the slope), has everyone finished?
(fn CheckRacers ()
  (Variables|Round|Work|SetAllFinished true)
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (PlayerState|GetPawn :self ski))
          (:then
            (if (== (Class|BPSkiPlayerState|GetFinishPlace :self ski) 0)
              (Variables|Round|Work|SetAllFinished false)
              (bind where (Transformation|GetActorLocation :self skier))
              (if (Class|BPSkiSlope|IsPastFinish :self (Variables|Round|Settings|GetSlope) :WorldLocation where)
                (CallFunction|PlayerFinished :Player ski)
                (elif (Class|BPSkiSlope|IsOutOfBounds :self (Variables|Round|Settings|GetSlope) :WorldLocation where)
                  (CallFunction|PlaceOne :Player ski :bAtGate true :Index 7)))))
          (:CastFailed)))
      (:CastFailed))))

; Outside the race: anyone lost goes back to the lobby.
(fn RescueLost (bAtGate)
  (for player (Coordinator|GetTrackedPlayers)
    (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (PlayerState|GetPawn :self player))
      (:then
        (if (Class|BPSkiSlope|IsOutOfBounds :self (Variables|Round|Settings|GetSlope) :WorldLocation (Transformation|GetActorLocation :self skier))
          (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
            (:then
              (CallFunction|PlaceOne :Player ski :bAtGate bAtGate :Index 11))
            (:CastFailed))))
      (:CastFailed))))

(fn PlayerFinished (Player)
  (bind place (Variables|Round|Work|GetNextPlace))
  (Variables|Round|Work|SetNextPlace (+ place 1))
  (Class|BPSkiPlayerState|SetFinishPlace :self Player :FinishPlace place)
  (Class|BPSkiPlayerState|SetFinishTime :self Player :FinishTime (- (CallFunction|Now) (Variables|Round|Work|GetRaceStartedAt)))
  (bind table (Variables|Round|Settings|GetFinishPoints))
  (bind points (select (<= place (Utilities|Array|Length table)) (Utilities|Array|Get(acopy) table (- place 1)) 0))
  (CallFunction|AddPoints :Player Player :Points points))

(fn AddPoints (Player Points)
  (Class|BPSkiPlayerState|SetPoints :self Player :Points (+ (Class|BPSkiPlayerState|GetPoints :self Player) Points))
  (if (== (Class|BPSkiPlayerState|GetTeam :self Player) 0)
    (Variables|Round|State|SetRedScore (+ (Variables|Round|State|GetRedScore) Points))
    (else
      (Variables|Round|State|SetBlueScore (+ (Variables|Round|State|GetBlueScore) Points)))))

; A paintball from Shooter hit Victim (server, from the ball that counts). Scores only in the race, only across teams.
(fn ScorePaintHit (Shooter Victim)
  (if (== (Variables|Round|State|GetPhase) 2)
    (bind from (Utilities|Casting|CastToBP_SkiPlayerState :Object (Class|Pawn|GetPlayerState :self Shooter))
      (:then
        (bind to (Utilities|Casting|CastToBP_SkiPlayerState :Object (Class|Pawn|GetPlayerState :self Victim))
          (:then
            (if (!= (Class|BPSkiPlayerState|GetTeam :self from) (Class|BPSkiPlayerState|GetTeam :self to))
              (Class|BPSkiPlayerState|SetHits :self from :Hits (+ (Class|BPSkiPlayerState|GetHits :self from) 1))
              (CallFunction|AddPoints :Player from :Points (Variables|Round|Settings|GetHitPoints))))
          (:CastFailed)))
      (:CastFailed))))

; T in the lobby (server).
(fn SwitchTeam (Player)
  (if (== (Variables|Round|State|GetPhase) 0)
    (Class|BPSkiPlayerState|SetTeam :self Player :Team (- 1 (Class|BPSkiPlayerState|GetTeam :self Player)))))

; [ or ] from an admin, in the lobby or the results (server). Without an AdminPIN on the server everyone is an admin.
(fn ChangeDifficulty (Player Step)
  (if (and (Class|Other5BasePlayerState|GetHasValidAdminPIN :self Player) (or (== (Variables|Round|State|GetPhase) 0) (== (Variables|Round|State|GetPhase) 3)))
    (Variables|Round|State|SetDifficulty (Math|Integer|Clamp(Integer) (+ (Variables|Round|State|GetDifficulty) Step) 0 2))
    (CallFunction|StartLobby)))

(fn CountTeam (Team)
  (Variables|Round|Work|SetCounted 0)
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (if (and (Class|BPSkiPlayerState|GetJoinedTeam :self ski) (== (Class|BPSkiPlayerState|GetTeam :self ski) Team))
          (Variables|Round|Work|SetCounted (+ (Variables|Round|Work|GetCounted) 1))))
      (:CastFailed)))
  (return (Variables|Round|Work|GetCounted)))
