; ABP_Skier: the skier's Animation Blueprint, event graph in Unreal MCP's Blueprint graph DSL.
; The Anim Graph is built by Docs/Scripts/BuildAnimGraph.ps1 (legs: standing <-> crouch by SkiCrouch; upper body:
; the gun's kind of pose (pistol, rifle or shotgun) through its aim offset by AimYaw / AimPitch; layered from spine_01 up). No walking or running
; legs: on skis the feet stay put and the snow moves. Leaning into turns is done by the character (it rolls the mesh).

(event EventBlueprintUpdateAnimation (DeltaTimeX)
  (bind pawn (Animation|TryGetPawnOwner))
  (Utilities|IsValid pawn
    (:"Is Valid"
      ; Crouch (knees and spine lean): 30% standing still, full from about 70 km/h; eased so it doesn't snap.
      (bind speed (Math|Vector|VectorLength (Transformation|GetVelocity :self pawn)))
      (bind target (Math|Float|Clamp(Float) (+ 0.3 (/ speed 2800.0)) 0.0 1.0))
      (Variables|Ski|SetSkiCrouch (Math|Interpolation|FInterpTo (Variables|Ski|GetSkiCrouch) target DeltaTimeX 4.0))
      ; Upper body: where the player aims (the camera), relative to where the skis point. Base Aim Rotation
      ; replicates, so other players see you aim too.
      (bind aim (Math|Rotator|Delta(Rotator) (Pawn|GetBaseAimRotation :self pawn) (Transformation|GetActorRotation :self pawn)))
      (Variables|Ski|SetAimYaw (Math|Float|Clamp(Float) (.yaw aim) -90.0 90.0))
      ; The crouch leans the spine forward by up to LeanDegrees (the Anim Graph's spine lean, after the aim offset):
      ; aim that much higher, so the arms and gun come back up to where the player aims. Only when aiming ahead: the lean is
      ; toward the skis' tips, so aimed 90 degrees to the side it only tilts the gun about its barrel (cos AimYaw).
      (Variables|Ski|SetAimPitch (Math|Float|Clamp(Float) (+ (.pitch aim) (* (* (Variables|Ski|GetLeanDegrees) (Variables|Ski|GetSkiCrouch)) (Math|Trig|Cos(Degrees) (Variables|Ski|GetAimYaw)))) -90.0 90.0))
      ; How the gun in hand is held (its ArmsKind: 0 pistol, 1 rifle, 2 shotgun): the Anim Graph's upper body plays
      ; that kind's pose and aim offset.
      (bind skier (Utilities|Casting|CastToBP_SkiCharacter :Object pawn)
        (:then
          (CallFunction|PlaceFeet :Skier skier)
          (bind gun (Class|BPSkiCharacter|GetCurrentGun :self skier))
          (Utilities|IsValid gun
            (:"Is Valid"
              (Variables|Ski|SetArmsPistol (== (Class|BPPaintGunData|GetArmsKind :self gun) 0))
              (Variables|Ski|SetArmsShotgun (== (Class|BPPaintGunData|GetArmsKind :self gun) 2)))
            (:"Is Not Valid")))
        (:CastFailed)))
    (:"Is Not Valid")))

; Feet on the skis' bindings, every frame (from the event graph): see the comment inside.
(fn PlaceFeet (Skier)
  ; Feet on the skis' bindings (the Anim Graph's Two Bone IK and foot turns use these, in component space).
  ; Each ankle goes AnkleBack behind the boot's middle and AnkleHeight above the sole, which rests SoleHeight above
  ; the ski's running surface (SM_Ski's origin, under the boot), all in the ski's own frame: so the feet follow the
  ; ski as it tilts to the snow, and stay on it as the body leans into a turn (the mesh rolls, the skis don't).
  ; The feet turn with the ski: their flat-ski rotation (FootLeftBase / FootRightBase, in the mesh's space,
  ; whose +Y is the skis' forward: hence the -90 yaw), then the ski's own rotation.
  (bind body (Animation|GetOwningComponent))
  (bind meshFrame (Transformation|GetWorldTransform :self body))
  (bind ankle (Math|Vector|MakeVector (- 0.0 (Variables|Ski|GetAnkleBack)) 0.0 (+ (Variables|Ski|GetSoleHeight) (Variables|Ski|GetAnkleHeight))))
  (bind meshFlat (Math|Rotator|MakeRotator :Yaw -90.0))
  ; (The skis aren't there on the very first update, while the character is still being made.)
  (bind skiLeft (Class|BPSkiCharacter|GetSkiLeft :self Skier))
  (bind skiRight (Class|BPSkiCharacter|GetSkiRight :self Skier))
  (Utilities|IsValid skiLeft
    (:"Is Valid"
      (Variables|Ski|SetFootLeftLocation (Math|Transform|InverseTransformLocation meshFrame (Math|Transform|TransformLocation (Transformation|GetWorldTransform :self skiLeft) ankle)))
      (Variables|Ski|SetFootLeftRotation (Math|Transform|InverseTransformRotation meshFrame (Math|Rotator|CombineRotators (Math|Rotator|CombineRotators (Variables|Ski|GetFootLeftBase) meshFlat) (Transformation|GetWorldRotation :self skiLeft))))
      (Variables|Ski|SetFootRightLocation (Math|Transform|InverseTransformLocation meshFrame (Math|Transform|TransformLocation (Transformation|GetWorldTransform :self skiRight) ankle)))
      (Variables|Ski|SetFootRightRotation (Math|Transform|InverseTransformRotation meshFrame (Math|Rotator|CombineRotators (Math|Rotator|CombineRotators (Variables|Ski|GetFootRightBase) meshFlat) (Transformation|GetWorldRotation :self skiRight)))))
    (:"Is Not Valid")))
