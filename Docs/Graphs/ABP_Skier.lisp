; ABP_Skier: the skier's Animation Blueprint, event graph in Unreal MCP's Blueprint graph DSL.
; The Anim Graph is built by Docs/Scripts/BuildAnimGraph.ps1 (legs: standing <-> crouch by SkiCrouch; upper body:
; the gun's kind of pose (pistol, rifle or shotgun) through its aim offset by AimYaw / AimPitch; layered from spine_01 up). No walking or running
; legs: on skis the feet stay put and the snow moves. Leaning into turns is done by the character (it rolls the mesh).

(event EventBlueprintUpdateAnimation (DeltaTimeX)
  (bind pawn (Animation|TryGetPawnOwner))
  (Utilities|IsValid pawn
    (:"Is Valid"
      ; Knees: 35% bent standing still, fully bent from about 94 km/h; eased so they don't snap.
      (bind speed (Math|Vector|VectorLength (Transformation|GetVelocity :self pawn)))
      (bind target (Math|Float|Clamp(Float) (+ 0.35 (/ speed 4000.0)) 0.0 1.0))
      (Variables|Ski|SetSkiCrouch (Math|Interpolation|FInterpTo (Variables|Ski|GetSkiCrouch) target DeltaTimeX 4.0))
      ; Upper body: where the player aims (the camera), relative to where the skis point. Base Aim Rotation
      ; replicates, so other players see you aim too.
      (bind aim (Math|Rotator|Delta(Rotator) (Pawn|GetBaseAimRotation :self pawn) (Transformation|GetActorRotation :self pawn)))
      (Variables|Ski|SetAimYaw (Math|Float|Clamp(Float) (.yaw aim) -90.0 90.0))
      (Variables|Ski|SetAimPitch (Math|Float|Clamp(Float) (.pitch aim) -90.0 90.0))
      ; How the gun in hand is held (its ArmsKind: 0 pistol, 1 rifle, 2 shotgun): the Anim Graph's upper body plays
      ; that kind's pose and aim offset.
      (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object pawn)
        (:then
          (bind gun (Class|BPSkiCharacter|GetCurrentGun :self skier))
          (Utilities|IsValid gun
            (:"Is Valid"
              (Variables|Ski|SetArmsPistol (== (Class|BPPaintGunData|GetArmsKind :self gun) 0))
              (Variables|Ski|SetArmsShotgun (== (Class|BPPaintGunData|GetArmsKind :self gun) 2)))
            (:"Is Not Valid")))
        (:CastFailed)))
    (:"Is Not Valid")))
