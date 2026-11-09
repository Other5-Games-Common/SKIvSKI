; BP_Paintball: one paintball, in Unreal MCP's Blueprint graph DSL (BlueprintTools.write_graph_dsl).
; Kept as text so the logic can be reviewed; the asset itself is binary.
;
; A real, slow, visible ball: the Projectile Movement component (Flight) flies the Ball sphere with gravity until it
; hits something, then it leaves a splat of its colour (a decal) and goes away.
;
; Multiplayer: balls are not replicated. Each machine spawns its own copy of every shot (BP_SkiCharacter's
; SpawnBalls), from the same muzzle, direction and random seed, so they fly the same way everywhere. Only the
; server's copy (bScores) counts a hit; the shooter sees their own copy at once, without waiting for the server.

; Fire it: Velocity in cm/s (the gun's speed plus the skier's own), the team colour, who shot it, whether this copy
; scores, its size in cm and how strongly gravity pulls it (1 = normal).
(fn Launch (Velocity Color InShooter bInScores Size GravityScale)
  (Variables|Paintball|SetShooter InShooter)
  (Variables|Paintball|SetScores bInScores)
  (Variables|Paintball|SetBallColor Color)
  ; Don't hit the skier who fired it.
  (Collision|IgnoreActorwhenMoving :self (Variables|Default|GetBall) :Actor InShooter :bShouldIgnore true)
  (Components|Sphere|SetSphereRadius :self (Variables|Default|GetBall) :InSphereRadius (* Size 0.5))
  (Transformation|SetRelativeScale3D :self (Variables|Default|GetBallMesh) :NewScale3D (Math|Vector|MakeVector (/ Size 100.0) (/ Size 100.0) (/ Size 100.0)))
  ; Colour it (this makes a dynamic material instance for the mesh on the first call), and let it glow a little.
  (Rendering|Material|SetVectorParameterValueonMaterials :self (Variables|Default|GetBallMesh) :ParameterName "Color" :ParameterValue (Math|Conversions|ToVector(LinearColor) Color))
  (Rendering|Material|SetScalarParameterValueonMaterials :self (Variables|Default|GetBallMesh) :ParameterName "Glow" :ParameterValue 0.6)
  (Rendering|Material|SetScalarParameterValueonMaterials :self (Variables|Default|GetBallMesh) :ParameterName "Roughness" :ParameterValue 0.15)
  ; Point the ball along its velocity, then give Flight the speed straight ahead.
  (Transformation|SetActorRotation :NewRotation (Math|Conversions|RotationFromXVector Velocity))
  (Class|ProjectileMovementComponent|SetProjectileGravityScale :self (Variables|Default|GetFlight) :ProjectileGravityScale GravityScale)
  (Game|Components|ProjectileMovement|SetVelocityinLocalSpace :self (Variables|Default|GetFlight) :NewVelocity (Math|Vector|MakeVector (Math|Vector|VectorLength Velocity) 0.0 0.0))
  (Components|Activation|Activate :self (Variables|Default|GetFlight) :bReset true)
  ; A ball that never lands (shot into the sky) goes after 6 s.
  (Actor|SetLifeSpan :InLifespan 6.0))

; It hit something: a splat where it landed, the hit counted (server's copy only), and the ball is gone.
(event OnProjectileStop(Flight) (ImpactResult)
  (bind (blocking overlap time dist loc impact normal impactNormal physMat hitActor hitComponent) (Collision|BreakHitResult ImpactResult))
  (CallFunction|Splash :HitActor hitActor :HitComponent hitComponent :Where impact :Normal impactNormal)
  (Actor|DestroyActor))

; Leave a splat where it landed and, on the server's copy, count a hit on a skier.
(fn Splash (HitActor HitComponent Where Normal)
  ; A decal points its X axis into the surface it paints; a random roll turns the splat shape.
  (bind into (Math|Conversions|RotationFromXVector (Math|Vector|NegateVector Normal)))
  (bind facing (Math|Rotator|MakeRotator :Roll (Math|Random|RandomFloatinRange 0.0 360.0) :Pitch (.pitch into) :Yaw (.yaw into)))
  (bind size (* (Components|Sphere|GetScaledSphereRadius :self (Variables|Default|GetBall)) 7.0))
  (bind extent (Math|Vector|MakeVector 20.0 size size))
  (bind victim (Utilities|Casting|CastToPawn :Object HitActor)
    (:then
      ; On a skier: stick the splat to them, so it rides along.
      (CallFunction|ColorSplat :Splat (Rendering|Decal|SpawnDecalAttached :DecalMaterial "/SKIvSKI/Materials/M_PaintSplat.M_PaintSplat" :DecalSize extent :AttachToComponent HitComponent :Location Where :Rotation facing :LocationType "KeepWorldPosition" :LifeSpan 20.0))
      (if (and (Variables|Paintball|GetScores) (Networking|HasAuthority))
        (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object victim)
          (:then
            (Class|BPSkiCharacter|PaintedBy :self skier :Shooter (Variables|Paintball|GetShooter)))
          (:CastFailed))))
    (:CastFailed
      (CallFunction|ColorSplat :Splat (Rendering|Decal|SpawnDecalatLocation :DecalMaterial "/SKIvSKI/Materials/M_PaintSplat.M_PaintSplat" :DecalSize extent :Location Where :Rotation facing :LifeSpan 40.0)))))

; A fresh splat takes this ball's colour (the material reads it with its Decal Color node).
(fn ColorSplat (Splat)
  (Rendering|Components|Decal|SetDecalColor :self Splat :Color (Variables|Paintball|GetBallColor)))
