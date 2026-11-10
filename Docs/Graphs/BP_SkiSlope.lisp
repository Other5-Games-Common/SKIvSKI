; BP_SkiSlope: the random ski slope, in Unreal MCP's Blueprint graph DSL (BlueprintTools.write_graph_dsl).
; Kept as text so the logic can be reviewed; the asset itself is binary.
;
; Every machine builds the same slope from two numbers, Seed and Difficulty, so only those (and BuildId, which says
; "build again") are replicated. The server calls Rebuild; BuildId's RepNotify then runs Generate everywhere.
;
; Layout, in the actor's space (place it at the origin, unrotated; X runs downhill):
;   X < 0          the lobby: flat snow behind the start, where players wait between rounds
;   X = 0          two start gates, Red on the left (-Y) and Blue on the right (+Y), a ridge between them
;   0 .. Length    the run: it narrows from TopWidth to FinishWidth, banks rise at its sides, the ridge fades out
;                  by 45% of the way down so the two runs meet, moguls and rollers, pines
;   90% of Length  the finish arch; the last 15% flattens out so everyone can stop

; How high the snow is at (X, Y), in cm. Everything else (mesh, trees, gates, spawn spots) asks this.
(fn HeightAt (X Y)
  (bind length (Variables|Slope|Layout|GetLength))
  (bind t (Math|Float|Clamp(Float) (/ X length) 0.0 1.0))
  ; Downhill at the slope's angle, easing out to flat over the last 15% (the finish run-out).
  (bind runout (Math|Float|Max(Float) (- t 0.85) 0.0))
  (bind fall (* (* (Variables|Slope|Work|GetSlopeTan) length) (- t (/ (* runout runout) 0.3))))
  ; Banks: outside the run (which narrows from TopWidth to FinishWidth) the snow rises.
  (bind halfWidth (Math|Float|Lerp (* (Variables|Slope|Layout|GetTopWidth) 0.5) (* (Variables|Slope|Layout|GetFinishWidth) 0.5) t))
  (bind outside (Math|Float|Clamp(Float) (/ (- (Math|Float|Absolute(Float) Y) halfWidth) (Variables|Slope|Layout|GetBankWidth)) 0.0 1.0))
  (bind bank (* (Variables|Slope|Layout|GetBankHeight) (* outside outside)))
  ; A ridge down the middle keeps the two teams apart at the top, fading out by 45% of the way down.
  (bind ridgeShape (Math|Float|Max(Float) (- 1.0 (/ (Math|Float|Absolute(Float) Y) (* (Variables|Slope|Layout|GetTopWidth) 0.16))) 0.0))
  (bind ridgeFade (* (Math|Float|Clamp(Float) (/ X 2500.0) 0.0 1.0) (Math|Float|Max(Float) (- 1.0 (/ t 0.45)) 0.0)))
  (bind ridge (* (* (Variables|Slope|Layout|GetRidgeHeight) ridgeShape) ridgeFade))
  ; Bumps: moguls (about 6 m apart) and long rollers (2.5 times as high, so a big bump stays skiable), from sines shifted by this round's random phases.
  ; None near the start or the finish.
  (bind moguls (* (Math|Trig|Sin(Radians) (+ (* X 0.0105) (Variables|Slope|Work|GetPhase1))) (Math|Trig|Sin(Radians) (+ (* Y 0.0126) (Variables|Slope|Work|GetPhase2)))))
  (bind rollers (* 2.5 (Math|Trig|Sin(Radians) (+ (+ (* X 0.0037) (* Y 0.0021)) (Variables|Slope|Work|GetPhase3)))))
  (bind fade (* (Math|Float|Clamp(Float) (* t 10.0) 0.0 1.0) (Math|Float|Clamp(Float) (* (- 1.0 t) 6.0) 0.0 1.0)))
  (bind bumps (* (* (Variables|Slope|Work|GetBumpHeight) (+ moguls rollers)) fade))
  (return (+ (+ (- bank fall) ridge) bumps)))

; The snow: a grid of CellSize squares over the lobby and the run (banks included), heights from HeightAt.
(fn BuildSnow ()
  (bind cell (Variables|Slope|Layout|GetCellSize))
  (bind lobby (Variables|Slope|Layout|GetLobbyLength))
  (bind halfY (+ (* (Variables|Slope|Layout|GetTopWidth) 0.5) (Variables|Slope|Layout|GetBankWidth)))
  (bind columns (+ (Math|Float|Round (/ (* halfY 2.0) cell)) 1))
  (bind rows (+ (Math|Float|Round (/ (+ lobby (Variables|Slope|Layout|GetLength)) cell)) 1))
  (Utilities|Array|Clear (Variables|Slope|Work|GetVertices))
  (Utilities|Array|Clear (Variables|Slope|Work|GetTriangles))
  (Utilities|Array|Clear (Variables|Slope|Work|GetUVs))
  (for row (range rows)
    (bind x (- (* (Math|Conversions|ToFloat(Integer) row) cell) lobby))
    (for col (range columns)
      (bind y (- (* (Math|Conversions|ToFloat(Integer) col) cell) halfY))
      (bind h (CallFunction|HeightAt :X x :Y y))
      (Utilities|Array|Add (Variables|Slope|Work|GetVertices) (Math|Vector|MakeVector x y h))
      (Utilities|Array|Add (Variables|Slope|Work|GetUVs) (Math|Vector2D|MakeVector2D (/ x 400.0) (/ y 400.0)))))
  ; Two triangles per square, wound so they face up.
  (for row (range (- rows 1))
    (for col (range (- columns 1))
      (bind i (+ (* row columns) col))
      (Utilities|Array|Add (Variables|Slope|Work|GetTriangles) i)
      (Utilities|Array|Add (Variables|Slope|Work|GetTriangles) (+ i 1))
      (Utilities|Array|Add (Variables|Slope|Work|GetTriangles) (+ i columns))
      (Utilities|Array|Add (Variables|Slope|Work|GetTriangles) (+ i 1))
      (Utilities|Array|Add (Variables|Slope|Work|GetTriangles) (+ (+ i columns) 1))
      (Utilities|Array|Add (Variables|Slope|Work|GetTriangles) (+ i columns))))
  (bind (normals tangents) (Components|ProceduralMesh|CalculateTangentsforMesh :Vertices (Variables|Slope|Work|GetVertices) :Triangles (Variables|Slope|Work|GetTriangles) :UVs (Variables|Slope|Work|GetUVs)))
  (Components|ProceduralMesh|ClearAllMeshSections :self (Variables|Default|GetSnow))
  (Components|ProceduralMesh|CreateMeshSection :self (Variables|Default|GetSnow) :SectionIndex 0 :Vertices (Variables|Slope|Work|GetVertices) :Triangles (Variables|Slope|Work|GetTriangles) :Normals normals :UV0 (Variables|Slope|Work|GetUVs) :Tangents tangents :bCreateCollision true))

; Pines: TreeCountByLevel tries for this difficulty, at random spots on the run and its banks, except on each
; team's racing line (a ClearPathWidth lane from its gate to the middle of the slope). Same Seed, same trees.
(fn PlantTrees ()
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetTreeCrowns))
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetTreeTrunks))
  (bind length (Variables|Slope|Layout|GetLength))
  (bind count (Utilities|Array|Get(acopy) (Variables|Slope|Difficulty|GetTreeCountByLevel) (Variables|Slope|Build|GetDifficulty)))
  (for n (range count)
    ; Each random number is drawn once into a variable: a random node is pure, so using its result twice would draw
    ; again (that put trees at the height of a different spot, floating in the air or buried).
    (Variables|Slope|Work|SetTreeT (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min 0.06 :Max 0.84))
    (Variables|Slope|Work|SetTreeSide (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min -1.0 :Max 1.0))
    (Variables|Slope|Work|SetTreeSize (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min 0.7 :Max 1.4))
    (Variables|Slope|Work|SetTreeSpin (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min 0.0 :Max 360.0))
    (bind t (Variables|Slope|Work|GetTreeT))
    (bind side (Variables|Slope|Work|GetTreeSide))
    (bind size (Variables|Slope|Work|GetTreeSize))
    (bind spin (Variables|Slope|Work|GetTreeSpin))
    (bind x (* t length))
    (bind halfWidth (Math|Float|Lerp (* (Variables|Slope|Layout|GetTopWidth) 0.5) (* (Variables|Slope|Layout|GetFinishWidth) 0.5) t))
    (bind y (* side (+ halfWidth 600.0)))
    ; Each team's line runs from its gate (GateSpread out from the middle) to the middle by 55% of the way down.
    (bind lineY (* (Variables|Slope|Layout|GetGateSpread) (Math|Float|Max(Float) (- 1.0 (/ t 0.55)) 0.0)))
    (if (> (Math|Float|Absolute(Float) (- (Math|Float|Absolute(Float) y) lineY)) (* (Variables|Slope|Layout|GetClearPathWidth) 0.5))
      (bind ground (CallFunction|HeightAt :X x :Y y))
      (bind turn (Math|Rotator|MakeRotator :Yaw spin))
      (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetTreeTrunks) :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector x y (+ ground (* 60.0 size))) turn (Math|Vector|MakeVector (* 0.35 size) (* 0.35 size) (* 1.6 size))))
      (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetTreeCrowns) :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector x y (+ ground (* 360.0 size))) turn (Math|Vector|MakeVector (* 2.4 size) (* 2.4 size) (* 5.0 size)))))))

; An arch: two posts and a banner between them, Width apart, standing on the snow at (X, Y).
(fn PlaceArch (PostLeft PostRight Banner X Y Width)
  (bind half (* Width 0.5))
  (Transformation|SetRelativeLocation :self PostLeft :NewLocation (Math|Vector|MakeVector X (- Y half) (+ (CallFunction|HeightAt :X X :Y (- Y half)) 200.0)))
  (Transformation|SetRelativeScale3D :self PostLeft :NewScale3D (Math|Vector|MakeVector 0.3 0.3 4.0))
  (Transformation|SetRelativeLocation :self PostRight :NewLocation (Math|Vector|MakeVector X (+ Y half) (+ (CallFunction|HeightAt :X X :Y (+ Y half)) 200.0)))
  (Transformation|SetRelativeScale3D :self PostRight :NewScale3D (Math|Vector|MakeVector 0.3 0.3 4.0))
  (Transformation|SetRelativeLocation :self Banner :NewLocation (Math|Vector|MakeVector X Y (+ (CallFunction|HeightAt :X X :Y Y) 380.0)))
  (Transformation|SetRelativeScale3D :self Banner :NewScale3D (Math|Vector|MakeVector 0.15 (/ Width 100.0) 0.8)))

(fn PlaceGates ()
  (bind spread (Variables|Slope|Layout|GetGateSpread))
  (CallFunction|PlaceArch :PostLeft (Variables|Default|GetGateRedPostLeft) :PostRight (Variables|Default|GetGateRedPostRight) :Banner (Variables|Default|GetGateRedBanner) :X 0.0 :Y (- spread) :Width 700.0)
  (CallFunction|PlaceArch :PostLeft (Variables|Default|GetGateBluePostLeft) :PostRight (Variables|Default|GetGateBluePostRight) :Banner (Variables|Default|GetGateBlueBanner) :X 0.0 :Y spread :Width 700.0)
  (Variables|Slope|Work|SetFinishX (* (Variables|Slope|Layout|GetLength) 0.9))
  (CallFunction|PlaceArch :PostLeft (Variables|Default|GetFinishPostLeft) :PostRight (Variables|Default|GetFinishPostRight) :Banner (Variables|Default|GetFinishBanner) :X (Variables|Slope|Work|GetFinishX) :Y 0.0 :Width (* (Variables|Slope|Layout|GetFinishWidth) 0.9)))

; Build everything from Seed and Difficulty (0 Easy, 1 Medium, 2 Hard). Runs on every machine.
(fn Generate ()
  (bind level (Math|Integer|Clamp(Integer) (Variables|Slope|Build|GetDifficulty) 0 2))
  (Variables|Slope|Work|SetStream (Math|Random|MakeRandomStream (Variables|Slope|Build|GetSeed)))
  (Variables|Slope|Work|SetSlopeTan (Math|Trig|Tan(Degrees) (Utilities|Array|Get(acopy) (Variables|Slope|Difficulty|GetSlopeDegreesByLevel) level)))
  (Variables|Slope|Work|SetBumpHeight (Utilities|Array|Get(acopy) (Variables|Slope|Difficulty|GetBumpHeightByLevel) level))
  (Variables|Slope|Work|SetPhase1 (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min 0.0 :Max 6.283))
  (Variables|Slope|Work|SetPhase2 (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min 0.0 :Max 6.283))
  (Variables|Slope|Work|SetPhase3 (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min 0.0 :Max 6.283))
  (CallFunction|BuildSnow)
  (CallFunction|PlantTrees)
  (CallFunction|PlaceGates))

; Server only: a new slope. Setting BuildId (RepNotify) runs OnRep_BuildId here and on every client.
(fn Rebuild (NewSeed NewDifficulty)
  (Variables|Slope|Build|SetSeed NewSeed)
  (Variables|Slope|Build|SetDifficulty NewDifficulty)
  (Variables|Slope|Build|SetBuildId (+ (Variables|Slope|Build|GetBuildId) 1)))

(fn OnRep_BuildId ()
  (CallFunction|Generate))

; Where a team's skier number Index waits at its start gate (rows of four, just past the gate on the slope, so
; gravity starts them at GO), in the world.
(fn GetStartSpot (Team Index)
  (bind side (select (== Team 0) -1.0 1.0))
  (bind x (+ 150.0 (* (Math|Conversions|ToFloat(Integer) (/ Index 4)) 250.0)))
  (bind y (+ (* side (Variables|Slope|Layout|GetGateSpread)) (* (- (Math|Conversions|ToFloat(Integer) (Math|Integer|%(Integer) Index 4)) 1.5) 160.0)))
  (bind spot (Math|Vector|MakeVector x y (+ (CallFunction|HeightAt :X x :Y y) 110.0)))
  (return (Math|Transform|ComposeTransforms (Math|Transform|MakeTransform spot (Math|Rotator|MakeRotator :Yaw 0.0) (Math|Vector|MakeVector 1.0 1.0 1.0)) (Transformation|GetActorTransform))))

; Where player number Index waits in the lobby (rows of six), in the world.
(fn GetLobbySpot (Index)
  (bind x (+ (* (Variables|Slope|Layout|GetLobbyLength) -0.6) (* (Math|Conversions|ToFloat(Integer) (/ Index 6)) 220.0)))
  (bind y (* (- (Math|Conversions|ToFloat(Integer) (Math|Integer|%(Integer) Index 6)) 2.5) 220.0))
  (bind spot (Math|Vector|MakeVector x y (+ (CallFunction|HeightAt :X x :Y y) 110.0)))
  (return (Math|Transform|ComposeTransforms (Math|Transform|MakeTransform spot (Math|Rotator|MakeRotator :Yaw 0.0) (Math|Vector|MakeVector 1.0 1.0 1.0)) (Transformation|GetActorTransform))))

; Has a point (in the world) crossed the finish line, between the posts?
(fn IsPastFinish (WorldLocation)
  (bind local (Math|Transform|InverseTransformLocation (Transformation|GetActorTransform) WorldLocation))
  (return (and (> (.x local) (Variables|Slope|Work|GetFinishX)) (< (Math|Float|Absolute(Float) (.y local)) (* (Variables|Slope|Layout|GetFinishWidth) 0.6)))))

; Is a point (in the world) lost: fallen well below the snow, or far outside the slope?
(fn IsOutOfBounds (WorldLocation)
  (bind local (Math|Transform|InverseTransformLocation (Transformation|GetActorTransform) WorldLocation))
  (bind ground (CallFunction|HeightAt :X (.x local) :Y (.y local)))
  (return (or (< (.z local) (- ground 1500.0)) (> (Math|Float|Absolute(Float) (.y local)) (+ (* (Variables|Slope|Layout|GetTopWidth) 0.5) (* (Variables|Slope|Layout|GetBankWidth) 2.0))))))

(event EventBeginPlay
  ; On its own (no director asking), the server builds a slope straight away, so the level can be tried as it is.
  (if (and (Networking|HasAuthority) (and (Variables|Slope|Difficulty|GetBuildOnBeginPlay) (== (Variables|Slope|Build|GetBuildId) 0)))
    (CallFunction|Rebuild :NewSeed (Math|Random|RandomIntegerinRange 1 999999) :NewDifficulty (Variables|Slope|Difficulty|GetStartDifficulty))))
