; BP_SkiDirector: rounds and teams, in Unreal MCP's Blueprint graph DSL (BlueprintTools.write_graph_dsl).
; A child of Other5's Game Coordinator (AOther5GameCoordinator), placed once in the level. Kept as text so the logic
; can be reviewed; the asset itself is binary.
;
; Only the server decides; it replicates Phase, PhaseEndsAt, the difficulty and a message, which the HUD (BP_SkiHUD)
; shows. Teams and team scores are Other5's shared teams (the Other5|Teams nodes; BP_SkiGameMode lists Red and Blue,
; new players join the smaller team). Every player's hits, outs, coins and finish place live on their BP_SkiPlayerState.
;
; A round:  Lobby (LobbySeconds, everyone on the flat snow behind the gates; T switches team; an admin can change
;           the difficulty with [ and ]) -> Countdown (CountdownSeconds, everyone frozen behind their team's gate)
;           -> Race (until everyone has crossed the finish, or RaceSeconds) -> Results (ResultsSeconds) -> Lobby
;           with a new random slope.
; Runs:     the slope's Runs (BP_SkiRunData assets) take turns, RoundsPerRun rounds each (0: stay on one run). RunIndex
;           is the one up now, and RunName replicates for the HUD. An admin picks another with , and . in the lobby or
;           the results; a server can start on one with -SkiRun=<number from 1, or name>. A run's RaceSeconds (when
;           above 0) replaces this director's, since a long run takes longer.
; Paint:    a paintball hit on the other team during the race puts the victim OUT for the rest of the race (grey helmet,
;           can't fire, no finish points) and gives HitPoints to the shooter's team, unless the ball bounces: each hit
;           bounces with the shooter's BounceChance (10% with standard paint).
; Bounds:   off the run's sides during the race, a BoundsSeconds countdown; still off when it ends, OUT as if hit and
;           moved to the bottom of the run (CheckBounds).
; Scoring:  HitPoints per out, FinishPoints[place - 1] for crossing the finish not out (10, 8, 6, 5, 4, 3, 2, 1).
;           Most points wins.
; Coins:    for the store between runs (each player's BP_SkiPlayerState Coins): HitCoins for each opponent you put
;           out, and SurviveCoins for getting through the race without being put out.
; Phases:   0 Lobby, 1 Countdown, 2 Race, 3 Results.

(event Coordinator|EventOnCoordinatorStarted
  (if (Coordinator|RunsGame)
    (CallFunction|SetupRounds)))

; A player got a character (joined, or came back after a fall): put it where the round wants it (server).
(event Coordinator|EventOnPlayerPawnChanged (Player NewPawn OldPawn)
  (if (Coordinator|RunsGame)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object Player)
      (:then
        (CallFunction|PlaceOne :Player ski :bAtGate (or (== (Variables|Round|State|GetPhase) 1) (== (Variables|Round|State|GetPhase) 2)) :Index 7))
      (:CastFailed))))

; The time everyone agrees on (the server's clock, replicated by the game state).
(fn Now ()
  (bind state (Game|GetGameState))
  (Utilities|IsValid state
    (:"Is Valid"
      (return (GameState|GetServerWorldTimeSeconds :self state)))
    (:"Is Not Valid"
      (return 0.0))))

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
  ; -SkiPracticeHits: paint hits score in the lobby too (to try scoring without racing).
  (Variables|Round|Settings|SetPracticeHits (Utilities|HasLaunchOption "SkiPracticeHits"))
  ; -SkiRun=2 (the second of the slope's Runs) or -SkiRun=Glacier (a run whose name starts with that).
  (bind (runValue runFound) (Utilities|ParseParamValue (Utilities|GetCommandLine) "SkiRun="))
  (if runFound
    (CallFunction|FindRun :Name runValue))
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
      (CallFunction|NextRunAfterRound)
      (CallFunction|StartLobby))))

(fn StartLobby ()
  (Variables|Round|State|SetPhase 0)
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (Variables|Round|Settings|GetLobbySeconds)))
  (Other5|Teams|SetTeamSwitchAllowed :bAllowed true)
  ; Pings and quick chat: everyone hears everyone in the lobby; from the countdown to the results, only your team.
  (Other5|Teams|SetTeamOnlyComms :bTeamOnly false)
  (Variables|Round|State|SetMessage "Lobby: T switches team")
  ; A new random slope on this round's run; the lobby itself is always flat, so nobody falls while it rebuilds.
  (CallFunction|UseRun)
  (Class|BPSkiSlope|Rebuild :self (Variables|Round|Settings|GetSlope) :NewSeed (Math|Random|RandomIntegerinRange 1 999999) :NewDifficulty (Variables|Round|State|GetDifficulty))
  (CallFunction|ResetRound)
  (CallFunction|PlaceAll :bAtGate false :bFreeze false))

(fn StartCountdown ()
  (Variables|Round|State|SetPhase 1)
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (Variables|Round|Settings|GetCountdownSeconds)))
  (Variables|Round|State|SetRoundNumber (+ (Variables|Round|State|GetRoundNumber) 1))
  (Variables|Round|State|SetMessage "Get ready!")
  ; Practice in the lobby doesn't carry into the race: everyone back in, scores back to 0.
  (CallFunction|ResetRound)
  (Other5|Teams|SetTeamSwitchAllowed :bAllowed false)
  (Other5|Teams|SetTeamOnlyComms :bTeamOnly true)
  (CallFunction|PlaceAll :bAtGate true :bFreeze true))

(fn StartRace ()
  (Variables|Round|State|SetPhase 2)
  (Variables|Round|Work|SetRaceStartedAt (CallFunction|Now))
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (CallFunction|RaceTime)))
  (Variables|Round|Work|SetNextPlace 1)
  (Variables|Round|Work|SetAllFinished false)
  (Variables|Round|State|SetMessage "GO!")
  (CallFunction|FreezeAll :bFreeze false))

(fn EndRace ()
  (Variables|Round|State|SetPhase 3)
  (Variables|Round|State|SetPhaseEndsAt (+ (CallFunction|Now) (Variables|Round|Settings|GetResultsSeconds)))
  (bind red (Other5|Teams|GetTeamScore :Team 0))
  (bind blue (Other5|Teams|GetTeamScore :Team 1))
  (bind score (Utilities|String|Append (Utilities|String|ToString(Integer) red) (Utilities|String|Append " - " (Utilities|String|ToString(Integer) blue))))
  (bind winner (Utilities|String|ToString(Text) (Other5|Teams|GetTeamName :Team (select (> red blue) 0 1))))
  (CallFunction|PaySurvivors)
  (CallFunction|ClearBounds)
  (Other5|Teams|SetTeamOnlyComms :bTeamOnly false)
  (Variables|Round|State|SetMessage (select (== red blue) (Utilities|String|Append "A DRAW " score) (Utilities|String|Append (Utilities|String|ToUpper winner) (Utilities|String|Append " WINS " score)))))

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
      (bind team (Other5|Teams|GetTeam :Player Player))
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

; During the race: who crossed the finish, who is lost (fell off, left the slope), is everyone finished or out?
(fn CheckRacers ()
  (Variables|Round|Work|SetAllFinished true)
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (PlayerState|GetPawn :self ski))
          (:then
            (bind where (Transformation|GetActorLocation :self skier))
            (bind racing (and (== (Class|BPSkiPlayerState|GetFinishPlace :self ski) 0) (not (Class|BPSkiPlayerState|GetOut :self ski))))
            (if racing
              (Variables|Round|Work|SetAllFinished false))
            ; Out players may still ski down, but crossing the finish counts only for those still in.
            (if (== (Class|BPSkiPlayerState|GetFinishPlace :self ski) 0)
              (if (Class|BPSkiSlope|IsPastFinish :self (Variables|Round|Settings|GetSlope) :WorldLocation where)
                (if racing
                  (CallFunction|PlayerFinished :Player ski))
                (else
                  (CallFunction|CheckBounds :Player ski :Skier skier :bRacing racing)))))
          (:CastFailed)))
      (:CastFailed))))

; Out of bounds in the race (server). Off the side of the run (more than BoundsBanks bank widths past its edge) starts
; a BoundsSeconds countdown: BoundsDeadline on the player state, which their HUD shows as a warning. Back on the run in
; time clears it; otherwise they're out, as if hit (no finish points, no SurviveCoins, nobody scores), and moved to the
; bottom of the run, stopped. Fallen through the snow: out at once. Someone already out who leaves the run goes
; straight to the bottom. (It used to put lost racers back at their start gate, which a racer could use to go back
; for a fort everyone had passed, or to escape being cornered.)
(fn CheckBounds (Player Skier bRacing)
  (bind slope (Variables|Round|Settings|GetSlope))
  (bind where (Transformation|GetActorLocation :self Skier))
  (bind deadline (Class|BPSkiPlayerState|GetBoundsDeadline :self Player))
  (bind off (Class|BPSkiSlope|IsOffRun :self slope :WorldLocation where :Banks (Variables|Round|Settings|GetBoundsBanks)))
  (if (Class|BPSkiSlope|IsBelowSnow :self slope :WorldLocation where)
    (CallFunction|SendOutOfBounds :Player Player)
    (elif off
      (if (not bRacing)
        (CallFunction|SendOutOfBounds :Player Player)
        (elif (<= deadline 0.0)
          (Class|BPSkiPlayerState|SetBoundsDeadline :self Player :BoundsDeadline (+ (CallFunction|Now) (Variables|Round|Settings|GetBoundsSeconds)))
          (elif (>= (CallFunction|Now) deadline)
            (CallFunction|SendOutOfBounds :Player Player))))
      (elif (> deadline 0.0)
        (Class|BPSkiPlayerState|SetBoundsDeadline :self Player :BoundsDeadline 0.0)))))

; Out for leaving the run: out as if hit, and to the bottom of the run (BP_SkiSlope GetBottomSpot), stopped.
(fn SendOutOfBounds (Player)
  (Class|BPSkiPlayerState|SetBoundsDeadline :self Player :BoundsDeadline 0.0)
  (Class|BPSkiPlayerState|SetOut :self Player :bOut true)
  (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object (PlayerState|GetPawn :self Player))
    (:then
      (bind spot (Variables|Round|Work|GetBottomPlaced))
      (Class|BPSkiCharacter|PlaceAt :self skier :Spot (Class|BPSkiSlope|GetBottomSpot :self (Variables|Round|Settings|GetSlope) :Index spot))
      (Variables|Round|Work|SetBottomPlaced (+ spot 1)))
    (:CastFailed)))

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

; Points for a player and their team.
(fn AddPoints (Player Points)
  (Class|BPSkiPlayerState|SetPoints :self Player :Points (+ (Class|BPSkiPlayerState|GetPoints :self Player) Points))
  (Other5|Teams|AddTeamScore :Team (Other5|Teams|GetTeam :Player Player) :Points Points))

; The race is over: nobody's out-of-bounds countdown carries on.
(fn ClearBounds ()
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (Class|BPSkiPlayerState|SetBoundsDeadline :self ski :BoundsDeadline 0.0))
      (:CastFailed))))

; The race is over: SurviveCoins for everyone who wasn't put out.
(fn PaySurvivors ()
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (if (not (Class|BPSkiPlayerState|GetOut :self ski))
          (Class|BPSkiPlayerState|SetCoins :self ski :Coins (+ (Class|BPSkiPlayerState|GetCoins :self ski) (Variables|Round|Settings|GetSurviveCoins)))))
      (:CastFailed))))

; A scoring paintball from Shooter hit Victim (server). Returns 0 when it doesn't count (not racing, same team,
; either already out), 1 for a hit (Victim is out), 2 for a bounce (the shooter's BounceChance came up).
; The casts that decide it are in JudgePaintHit: a cast ends the flow in a graph, so the Return here would only be
; reached when nobody is racing, and a function that ends without its Return node gives 0 (the hit counted, but
; nobody saw "Hit!", the splat or heard the hit sound).
(fn ResolvePaintHit (Shooter Victim)
  (Variables|Round|Work|SetHitResult 0)
  (if (or (== (Variables|Round|State|GetPhase) 2) (and (Variables|Round|Settings|GetPracticeHits) (== (Variables|Round|State|GetPhase) 0)))
    (CallFunction|JudgePaintHit :Shooter Shooter :Victim Victim))
  (return (Variables|Round|Work|GetHitResult)))

; ResolvePaintHit's decision, left in HitResult: a hit (Victim out, a point for the shooter's team) or a bounce.
(fn JudgePaintHit (Shooter Victim)
  (bind from (Utilities|Casting|CastToBP_SkiPlayerState :Object (Class|Pawn|GetPlayerState :self Shooter))
    (:then
      (bind to (Utilities|Casting|CastToBP_SkiPlayerState :Object (Class|Pawn|GetPlayerState :self Victim))
        (:then
          (if (and (not (Other5|Teams|SameTeam :A from :B to)) (and (not (Class|BPSkiPlayerState|GetOut :self from)) (not (Class|BPSkiPlayerState|GetOut :self to))))
            (if (< (Math|Random|RandomFloat) (Class|BPSkiPlayerState|GetBounceChance :self from))
              (Variables|Round|Work|SetHitResult 2)
              (else
                (Variables|Round|Work|SetHitResult 1)
                (Class|BPSkiPlayerState|SetOut :self to :bOut true)
                (Class|BPSkiPlayerState|SetHits :self from :Hits (+ (Class|BPSkiPlayerState|GetHits :self from) 1))
                (Class|BPSkiPlayerState|SetCoins :self from :Coins (+ (Class|BPSkiPlayerState|GetCoins :self from) (Variables|Round|Settings|GetHitCoins)))
                (CallFunction|AddPoints :Player from :Points (Variables|Round|Settings|GetHitPoints))))))
        (:CastFailed)))
    (:CastFailed)))

; [ or ] from an admin, in the lobby or the results (server). Without an AdminPIN on the server everyone is an admin.
;
; Step 1 or -1 is the difficulty ([ and ]); 10 or -10 the next or previous run (. and ,), which starts at once.
(fn ChangeDifficulty (Player Step)
  (if (and (Class|Other5BasePlayerState|GetHasValidAdminPIN :self Player) (or (== (Variables|Round|State|GetPhase) 0) (== (Variables|Round|State|GetPhase) 3)))
    (if (>= (Math|Integer|Absolute(Integer) Step) 10)
      (CallFunction|StepRun :Step (select (> Step 0) 1 -1))
      (else
        (Variables|Round|State|SetDifficulty (Math|Integer|Clamp(Integer) (+ (Variables|Round|State|GetDifficulty) Step) 0 2))))
    (CallFunction|StartLobby)))

; ---- runs -------------------------------------------------------------------------------------------------------

; How many runs the slope has (its Runs list).
(fn RunCount ()
  (if (CallFunction|FindSlope)
    (return (Utilities|Array|Length (Class|BPSkiSlope|GetRuns :self (Variables|Round|Settings|GetSlope)))))
  (return 0))

; The run up now (RunIndex in the slope's Runs), or none when the slope has no runs.
(fn CurrentRun ()
  (bind count (CallFunction|RunCount))
  (if (> count 0)
    (return (Utilities|Array|Get(acopy) (Class|BPSkiSlope|GetRuns :self (Variables|Round|Settings|GetSlope)) (Math|Integer|%(Integer) (Math|Integer|Max(Integer) (Variables|Round|State|GetRunIndex) 0) count))))
  (return (Class|BPSkiSlope|GetRun :self (Variables|Round|Settings|GetSlope))))

; Tells the slope which run to build next (it replicates; Rebuild then builds it everywhere), and RunName for the HUD.
(fn UseRun ()
  (if (CallFunction|FindSlope)
    (bind run (CallFunction|CurrentRun))
    (Utilities|IsValid run
      (:"Is Valid"
        (Class|BPSkiSlope|SetRun :self (Variables|Round|Settings|GetSlope) :Run run)
        (Variables|Round|State|SetRunName (Utilities|String|ToString(Text) (Class|BPSkiRunData|GetRunName :self run))))
      (:"Is Not Valid"
        (Variables|Round|State|SetRunName "")))))

; Another run, Step along the slope's Runs (round the end), and a new lobby on it.
(fn StepRun (Step)
  (bind count (CallFunction|RunCount))
  (if (> count 0)
    (Variables|Round|State|SetRunIndex (Math|Integer|%(Integer) (+ (+ (Variables|Round|State|GetRunIndex) Step) count) count))
    (Variables|Round|Work|SetRoundsOnRun 0)))

; After each round's results: the next run once this one has had RoundsPerRun rounds (0: never).
(fn NextRunAfterRound ()
  (Variables|Round|Work|SetRoundsOnRun (+ (Variables|Round|Work|GetRoundsOnRun) 1))
  (if (and (> (Variables|Round|Settings|GetRoundsPerRun) 0) (>= (Variables|Round|Work|GetRoundsOnRun) (Variables|Round|Settings|GetRoundsPerRun)))
    (CallFunction|StepRun :Step 1)))

; -SkiRun=: a number (1 is the first run) or the start of a run's name.
(fn FindRun (Name)
  (bind count (CallFunction|RunCount))
  (bind number (Utilities|String|StringToInteger Name))
  (if (and (> number 0) (<= number count))
    (Variables|Round|State|SetRunIndex (- number 1))
    (else
      (for n (range count)
        (bind run (Utilities|Array|Get(acopy) (Class|BPSkiSlope|GetRuns :self (Variables|Round|Settings|GetSlope)) n))
        (if (Utilities|String|StartsWith (Utilities|String|ToString(Text) (Class|BPSkiRunData|GetRunName :self run)) Name)
          (Variables|Round|State|SetRunIndex n))))))

; How long the race may last: the run's own RaceSeconds when it has one (a long run takes longer), else RaceSeconds.
(fn RaceTime ()
  (bind run (CallFunction|CurrentRun))
  (Utilities|IsValid run
    (:"Is Valid"
      (if (> (Class|BPSkiRunData|GetRaceSeconds :self run) 0.0)
        (return (Class|BPSkiRunData|GetRaceSeconds :self run)))
      (return (Variables|Round|Settings|GetRaceSeconds)))
    (:"Is Not Valid"
      (return (Variables|Round|Settings|GetRaceSeconds)))))


; Everyone back in the race with nothing scored: team scores, each player's hits, points, finish and out.
(fn ResetRound ()
  (Other5|Teams|ResetTeamScores)
  (for player (Coordinator|GetTrackedPlayers)
    (bind ski (Utilities|Casting|CastToBP_SkiPlayerState :Object player)
      (:then
        (Class|BPSkiPlayerState|SetHits :self ski :Hits 0)
        (Class|BPSkiPlayerState|SetPoints :self ski :Points 0)
        (Class|BPSkiPlayerState|SetFinishPlace :self ski :FinishPlace 0)
        (Class|BPSkiPlayerState|SetFinishTime :self ski :FinishTime 0.0)
        (Class|BPSkiPlayerState|SetOut :self ski :bOut false)
        (Class|BPSkiPlayerState|SetBoundsDeadline :self ski :BoundsDeadline 0.0))
      (:CastFailed)))
  (Variables|Round|Work|SetBottomPlaced 0))
