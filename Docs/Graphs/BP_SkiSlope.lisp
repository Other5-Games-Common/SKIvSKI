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
;   90% of Length  the finish arch; the last 15% flattens out
;   past Length    the run-out (RunoutLength): long and nearly flat, gently rolling, curving up towards its end
;                  (RunoutRise) so everyone slows down and stays on the snow

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
  ; Never an uphill pointing down the run: the bumps' steepest rise along X (about BumpHeight x 0.0198) stays under
  ; 60% of the run's own downhill gradient here (which eases off in the run-out), so nobody gets stuck in a dip.
  (bind localTan (* (Variables|Slope|Work|GetSlopeTan) (- 1.0 (/ runout 0.15))))
  (bind bumpCap (Math|Float|Min(Float) 1.0 (/ (* 0.6 localTan) (Math|Float|Max(Float) (* (Variables|Slope|Work|GetBumpHeight) 0.0198) 0.001))))
  (bind bumps (* (* (* (Variables|Slope|Work|GetBumpHeight) (+ moguls rollers)) fade) bumpCap))
  ; The run-out, past the run: flat where the run ends, rolling gently (15 cm, about 50 m apart: under 1 degree, so they never stop anyone), then rising as the
  ; cube of the way along it to RunoutRise at its end, so it stays nearly flat for its first half and stops even a
  ; skier at top speed (108 km/h needs about 45 m of climb).
  (bind past (Math|Float|Clamp(Float) (/ (- X length) (Variables|Slope|Layout|GetRunoutLength)) 0.0 1.0))
  (bind rise (* (Variables|Slope|Layout|GetRunoutRise) (* past (* past past))))
  (bind rolls (* (* 15.0 (Math|Float|Min(Float) (* past 6.0) 1.0)) (Math|Trig|Sin(Radians) (+ (+ (* X 0.0012) (* Y 0.0009)) (Variables|Slope|Work|GetPhase1)))))
  (return (+ (+ (+ (- bank fall) ridge) bumps) (+ rise rolls))))

; Around the slope (past the lobby, the banks and the run-out's end) the snow carries on as hills rising away from it,
; OuterWidth wide, so the slope sits in a valley instead of floating in the air. In the slope's own area this is HeightAt.
(fn OuterHeightAt (X Y)
  (bind minX (- 0.0 (Variables|Slope|Layout|GetLobbyLength)))
  (bind maxX (+ (Variables|Slope|Layout|GetLength) (Variables|Slope|Layout|GetRunoutLength)))
  (bind halfY (+ (* (Variables|Slope|Layout|GetTopWidth) 0.5) (Variables|Slope|Layout|GetBankWidth)))
  (bind cx (Math|Float|Clamp(Float) X minX maxX))
  (bind cy (Math|Float|Clamp(Float) Y (- 0.0 halfY) halfY))
  ; How far outside the slope's area: 0 inside it.
  ; Beyond the rim (OuterWidth) the ground stays at the rim's height, so whatever stands out there (the mountains)
  ; sits behind the ridge instead of up in the air.
  (bind d (Math|Float|Min(Float) (Math|Vector|VectorLengthXY (Math|Vector|MakeVector (- X cx) (- Y cy) 0.0)) (Variables|Slope|Layout|GetOuterWidth)))
  ; Rising 22 cm a metre, with rounded hills (9 m high, a few hundred metres across) growing in over the first 60 m.
  (bind hills (* (* 900.0 (Math|Float|Min(Float) (/ d 6000.0) 1.0)) (* (Math|Trig|Sin(Radians) (+ (* X 0.00023) (Variables|Slope|Work|GetPhase2))) (Math|Trig|Sin(Radians) (+ (* Y 0.00031) (Variables|Slope|Work|GetPhase3))))))
  ; Towards OuterWidth the hills curve up into a ridge (180 m higher at the rim, more or less along it), so the valley
  ; closes in and nobody sees where the snow ends; the mountains stand beyond it.
  (bind far (/ d (Variables|Slope|Layout|GetOuterWidth)))
  (bind ridge (* (* 18000.0 (* far far)) (+ 1.0 (* 0.35 (Math|Trig|Sin(Radians) (+ (+ (* X 0.00011) (* Y 0.00007)) (Variables|Slope|Work|GetPhase1)))))))
  (bind edge (CallFunction|HeightAt :X cx :Y cy))
  (return (+ edge (+ (+ (* d 0.22) hills) ridge))))

; The distances out from the slope's edge where the surrounding snow has a row (or column) of vertices: one cell, then
; each 30% wider than the last, out to OuterWidth (about 16 of them), so the far hills cost few triangles.
(fn OuterSteps ()
  (Utilities|Array|Clear (Variables|Slope|Work|GetSteps))
  (Variables|Slope|Work|SetStepAt 0.0)
  (Variables|Slope|Work|SetStepSize (Variables|Slope|Layout|GetCellSize))
  (while (< (Variables|Slope|Work|GetStepAt) (Variables|Slope|Layout|GetOuterWidth))
    (Variables|Slope|Work|SetStepAt (+ (Variables|Slope|Work|GetStepAt) (Variables|Slope|Work|GetStepSize)))
    (Utilities|Array|Add (Variables|Slope|Work|GetSteps) (Variables|Slope|Work|GetStepAt))
    (Variables|Slope|Work|SetStepSize (* (Variables|Slope|Work|GetStepSize) 1.3))))

; The snow: one mesh, a grid of CellSize squares over the lobby, the run and the run-out (banks included), widening
; into the surrounding hills on every side (OuterSteps), heights from OuterHeightAt. One mesh, so there's no seam.
(fn BuildSnow ()
  (bind cell (Variables|Slope|Layout|GetCellSize))
  (bind lobby (Variables|Slope|Layout|GetLobbyLength))
  (bind maxX (+ (Variables|Slope|Layout|GetLength) (Variables|Slope|Layout|GetRunoutLength)))
  (bind halfY (+ (* (Variables|Slope|Layout|GetTopWidth) 0.5) (Variables|Slope|Layout|GetBankWidth)))
  (CallFunction|OuterSteps)
  (bind steps (Utilities|Array|Length (Variables|Slope|Work|GetSteps)))
  (Utilities|Array|Clear (Variables|Slope|Work|GetXs))
  (Utilities|Array|Clear (Variables|Slope|Work|GetYs))
  (for i (range steps)
    (Utilities|Array|Add (Variables|Slope|Work|GetXs) (- (- 0.0 lobby) (Utilities|Array|Get(acopy) (Variables|Slope|Work|GetSteps) (- (- steps 1) i))))
    (Utilities|Array|Add (Variables|Slope|Work|GetYs) (- (- 0.0 halfY) (Utilities|Array|Get(acopy) (Variables|Slope|Work|GetSteps) (- (- steps 1) i)))))
  (for row (range (+ (Math|Float|Round (/ (+ lobby maxX) cell)) 1))
    (Utilities|Array|Add (Variables|Slope|Work|GetXs) (- (* (Math|Conversions|ToFloat(Integer) row) cell) lobby)))
  (for col (range (+ (Math|Float|Round (/ (* halfY 2.0) cell)) 1))
    (Utilities|Array|Add (Variables|Slope|Work|GetYs) (- (* (Math|Conversions|ToFloat(Integer) col) cell) halfY)))
  (for i (range steps)
    (Utilities|Array|Add (Variables|Slope|Work|GetXs) (+ maxX (Utilities|Array|Get(acopy) (Variables|Slope|Work|GetSteps) i)))
    (Utilities|Array|Add (Variables|Slope|Work|GetYs) (+ halfY (Utilities|Array|Get(acopy) (Variables|Slope|Work|GetSteps) i))))
  (bind columns (Utilities|Array|Length (Variables|Slope|Work|GetYs)))
  (bind rows (Utilities|Array|Length (Variables|Slope|Work|GetXs)))
  (Utilities|Array|Clear (Variables|Slope|Work|GetVertices))
  (Utilities|Array|Clear (Variables|Slope|Work|GetTriangles))
  (Utilities|Array|Clear (Variables|Slope|Work|GetUVs))
  (for x (Variables|Slope|Work|GetXs)
    (for y (Variables|Slope|Work|GetYs)
      (bind h (CallFunction|OuterHeightAt :X x :Y y))
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
; team's racing line (a ClearPathWidth lane from its gate to the middle of the slope), and never so close to another
; pine that a skier could be wedged between them: there is always TreeGap of open snow between two crowns. Same
; Seed, same trees.
(fn PlantTrees ()
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetTreeCrowns))
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetTreeTrunks))
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetTreeArt))
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetTreeArtTall))
  (Utilities|Array|Clear (Variables|Slope|Work|GetTreeSpots))
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
      (CallFunction|PlantTree :X x :Y y :Size size :Spin spin))))

; One pine at (X, Y), if it leaves TreeGap of open snow to every pine already planted (a crown is 1.2 m x Size
; across its middle, TreeSpots keeps X, Y and Size of each). The cone and trunk are what skiers hit; with the winter
; look (bFancy) they're hidden and a snowy pine from Other5WinterBiome stands in the same spot, the bigger ones taller.
(fn PlantTree (X Y Size Spin)
  (bind here (Math|Vector|MakeVector X Y Size))
  (Variables|Slope|Work|SetTreeClear true)
  (for spot (Variables|Slope|Work|GetTreeSpots)
    (if (< (Math|Vector|VectorLengthXY (- spot here)) (+ (* 120.0 (+ Size (.z spot))) (Variables|Slope|Layout|GetTreeGap)))
      (Variables|Slope|Work|SetTreeClear false)))
  (if (Variables|Slope|Work|GetTreeClear)
    (Utilities|Array|Add (Variables|Slope|Work|GetTreeSpots) here)
    (bind x X)
    (bind y Y)
    (bind size Size)
    (bind spin Spin)
    (bind ground (CallFunction|OuterHeightAt :X x :Y y))
    (bind turn (Math|Rotator|MakeRotator :Yaw spin))
    (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetTreeTrunks) :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector x y (+ ground (* 60.0 size))) turn (Math|Vector|MakeVector (* 0.35 size) (* 0.35 size) (* 1.6 size))))
    (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetTreeCrowns) :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector x y (+ ground (* 360.0 size))) turn (Math|Vector|MakeVector (* 2.4 size) (* 2.4 size) (* 5.0 size))))
    (if (Variables|Slope|Look|GetFancy)
      (if (> size 1.15)
        (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetTreeArtTall) :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector x y (- ground 20.0)) turn (Math|Vector|MakeVector (* 0.45 size) (* 0.45 size) (* 0.45 size))))
        (else
          (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetTreeArt) :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector x y (- ground 20.0)) turn (Math|Vector|MakeVector (* 0.57 size) (* 0.57 size) (* 0.57 size)))))))))

; A random number from this round's stream (one draw per call, so bind it before using it twice).
(fn Draw (Min Max)
  (return (Math|Random|RandomFloatinRangefromStream :Stream (Variables|Slope|Work|GetStream) :Min Min :Max Max)))

; One piece of scenery (no collision) on the snow at (X, Y), sunk Sink into it.
(fn PlantArt (Hism X Y Scale Spin Sink)
  (bind ground (CallFunction|OuterHeightAt :X X :Y Y))
  (Components|InstancedStaticMesh|AddInstance :self Hism :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector X Y (- ground Sink)) (Math|Rotator|MakeRotator :Yaw Spin) (Math|Vector|MakeVector Scale Scale Scale))))

; Loads an asset by its path, if this project has it (Other5WinterBiome is optional: without it nothing loads).
(fn LoadLook (Path)
  (bind asset (Utilities|LoadAssetBlocking :Asset (Utilities|ToSoftObjectReference :SoftObjectPath (Utilities|MakeSoftObjectPath :PathString Path))))
  (return asset))

; Gives Hism the static mesh at Path; Found says whether there was one.
(fn LookMeshOn (Hism Path)
  (bind asset (CallFunction|LoadLook :Path Path))
  (bind mesh (Utilities|Casting|CastToStaticMesh :Object asset)
    (:then
      (Components|StaticMesh|SetStaticMesh :self Hism :NewMesh mesh)
      (return true))
    (:CastFailed
      (return false))))

; Gives Target the material at Path (its first slot); Found says whether there was one.
(fn LookMaterialOn (Target Path)
  (bind asset (CallFunction|LoadLook :Path Path))
  (bind material (Utilities|Casting|CastToMaterialInterface :Object asset)
    (:then
      (Rendering|Material|SetMaterial :self Target :ElementIndex 0 :Material material)
      (return true))
    (:CastFailed
      (return false))))

; Falling snow around this player's camera (once; not on a dedicated server, which has no camera).
(fn StartSnowfall ()
  (if (not (Variables|Slope|Look|GetSnowing))
    (bind asset (CallFunction|LoadLook :Path (Variables|Slope|Look|GetLookSnowfall)))
    (bind fx (Utilities|Casting|CastToParticleSystem :Object asset)
      (:then
        (bind cam (Game|GetPlayerCameraManager :PlayerIndex 0))
        (Utilities|IsValid cam
          (:"Is Valid"
            (Variables|Slope|Look|SetSnowing true)
            (Effects|SpawnEmitterAttached :EmitterTemplate fx :AttachToComponent (Actor|GetComponentbyClass :self cam :ComponentClass "/Script/Engine.SceneComponent") :Location (Math|Vector|MakeVector 0.0 0.0 300.0) :bAutoDestroy false))
          (:"Is Not Valid")))
      (:CastFailed))))

; The winter look, when this project has Other5WinterBiome (the private art plugin: snowy pines, snow, rocks,
; mountains, falling snow). Without it bFancy stays false and the slope keeps its own look: cones on trunks, plain snow.
; Either way the gameplay is the same: the same snow, and the same cones and trunks to hit (hidden with the winter look).
(fn ApplyLook ()
  (bind found (CallFunction|LookMeshOn :Hism (Variables|Default|GetTreeArt) :Path (Variables|Slope|Look|GetLookTree)))
  (Variables|Slope|Look|SetFancy found)
  (if (Variables|Slope|Look|GetFancy)
    (CallFunction|LookMeshOn :Hism (Variables|Default|GetTreeArtTall) :Path (Variables|Slope|Look|GetLookTreeTall))
    (CallFunction|LookMeshOn :Hism (Variables|Default|GetFarTrees) :Path (Variables|Slope|Look|GetLookFarTrees))
    (CallFunction|LookMeshOn :Hism (Variables|Default|GetClumps) :Path (Variables|Slope|Look|GetLookClump))
    (CallFunction|LookMeshOn :Hism (Variables|Default|GetRocks) :Path (Variables|Slope|Look|GetLookRock))
    (CallFunction|LookMeshOn :Hism (Variables|Default|GetMountains) :Path (Variables|Slope|Look|GetLookMountain))
    (CallFunction|LookMaterialOn :Target (Variables|Default|GetMountains) :Path (Variables|Slope|Look|GetLookMountainMaterial))
    (CallFunction|LookMaterialOn :Target (Variables|Default|GetSnow) :Path (Variables|Slope|Look|GetLookSnow))
    (Rendering|SetVisibility :self (Variables|Default|GetTreeCrowns) :bNewVisibility false)
    (Rendering|SetVisibility :self (Variables|Default|GetTreeTrunks) :bNewVisibility false)
    (CallFunction|StartSnowfall)))

; The forest around the slope: ForestCount more pines on the hills either side, just past where skiers are out of
; bounds (cones without the winter look). With the winter look also: distant pines further out, snow clumps on the
; banks, rocks on the hills, and MountainCount rings of mountains MountainDistance away, past the rim.
(fn DressScene ()
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetFarTrees))
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetClumps))
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetRocks))
  (Components|InstancedStaticMesh|ClearInstances :self (Variables|Default|GetMountains))
  (bind minX (- 0.0 (Variables|Slope|Layout|GetLobbyLength)))
  (bind maxX (+ (Variables|Slope|Layout|GetLength) (Variables|Slope|Layout|GetRunoutLength)))
  (bind halfY (+ (* (Variables|Slope|Layout|GetTopWidth) 0.5) (Variables|Slope|Layout|GetBankWidth)))
  (for n (range (Variables|Slope|Look|GetForestCount))
    (bind x (CallFunction|Draw :Min (- minX 4000.0) :Max (+ maxX 4000.0)))
    (bind side (CallFunction|Draw :Min -1.0 :Max 1.0))
    (bind size (CallFunction|Draw :Min 0.8 :Max 1.6))
    (bind spin (CallFunction|Draw :Min 0.0 :Max 360.0))
    (CallFunction|PlantTree :X x :Y (* (Math|Float|Sign(Float) side) (+ (+ halfY 1300.0) (* (Math|Float|Absolute(Float) side) 5000.0))) :Size size :Spin spin))
  (if (Variables|Slope|Look|GetFancy)
    (for n (range (Variables|Slope|Look|GetFarTreeCount))
      (bind x (CallFunction|Draw :Min (- minX 20000.0) :Max (+ maxX 20000.0)))
      (bind side (CallFunction|Draw :Min -1.0 :Max 1.0))
      (bind size (CallFunction|Draw :Min 0.9 :Max 1.7))
      (bind spin (CallFunction|Draw :Min 0.0 :Max 360.0))
      (CallFunction|PlantArt :Hism (Variables|Default|GetFarTrees) :X x :Y (* (Math|Float|Sign(Float) side) (+ (+ halfY 6000.0) (* (Math|Float|Absolute(Float) side) 30000.0))) :Scale size :Spin spin :Sink 30.0))
    (for n (range (Variables|Slope|Look|GetClumpCount))
      (bind x (CallFunction|Draw :Min minX :Max maxX))
      (bind side (CallFunction|Draw :Min -1.0 :Max 1.0))
      (bind size (CallFunction|Draw :Min 0.6 :Max 2.2))
      (bind spin (CallFunction|Draw :Min 0.0 :Max 360.0))
      (CallFunction|PlantArt :Hism (Variables|Default|GetClumps) :X x :Y (* (Math|Float|Sign(Float) side) (+ (- halfY (Variables|Slope|Layout|GetBankWidth)) (* (Math|Float|Absolute(Float) side) 5000.0))) :Scale size :Spin spin :Sink 6.0))
    (for n (range (Variables|Slope|Look|GetRockCount))
      (bind x (CallFunction|Draw :Min (- minX 3000.0) :Max (+ maxX 3000.0)))
      (bind side (CallFunction|Draw :Min -1.0 :Max 1.0))
      (bind size (CallFunction|Draw :Min 0.8 :Max 3.0))
      (bind spin (CallFunction|Draw :Min 0.0 :Max 360.0))
      (CallFunction|PlantArt :Hism (Variables|Default|GetRocks) :X x :Y (* (Math|Float|Sign(Float) side) (+ (+ halfY 900.0) (* (Math|Float|Absolute(Float) side) 9000.0))) :Scale size :Spin spin :Sink (* 35.0 size)))
    ; The mountain mesh is a whole ring of peaks (348 m across, seen from inside), so each ring is one instance centred
    ; on the slope, scaled out to MountainDistance and standing at the rim's height (its foot is below the ridge).
    ; MountainCount rings, each a third wider and higher than the last and turned at random, for ranges behind ranges.
    (bind middle (* (+ minX maxX) 0.5))
    (bind rim (CallFunction|OuterHeightAt :X middle :Y (+ halfY (Variables|Slope|Layout|GetOuterWidth))))
    (for n (range (Variables|Slope|Look|GetMountainCount))
      (bind spin (CallFunction|Draw :Min 0.0 :Max 360.0))
      (bind grow (+ 1.0 (* 0.33 (Math|Conversions|ToFloat(Integer) n))))
      (bind across (/ (* (Variables|Slope|Look|GetMountainDistance) grow) 17400.0))
      (bind high (* 5.0 grow))
      (Components|InstancedStaticMesh|AddInstance :self (Variables|Default|GetMountains) :InstanceTransform (Math|Transform|MakeTransform (Math|Vector|MakeVector middle 0.0 rim) (Math|Rotator|MakeRotator :Yaw spin) (Math|Vector|MakeVector across across high))))))

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
  (CallFunction|ApplyLook)
  (CallFunction|BuildSnow)
  (CallFunction|PlantTrees)
  (CallFunction|PlaceGates)
  ; Scenery last: it draws from the stream after the run's own pines, so those are the same with or without the winter look.
  (CallFunction|DressScene))

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
