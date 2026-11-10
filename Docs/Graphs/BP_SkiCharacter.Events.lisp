; BP_SkiCharacter: events. Functions are in BP_SkiCharacter.Movement.lisp (skiing) and BP_SkiCharacter.Paint.lisp
; (guns, teams, round placement).

; Set up once, from the first Tick. There's deliberately no BeginPlay here: overriding it would skip the parent's
; (Other5's character adds the Esc/F10 game menu keys, IMC_BaseGamePawn, checks the saved admin PIN and refreshes
; player names there), and the graph DSL can't add a call to the parent's BeginPlay.
(fn SkiBeginPlay ()
  (CallFunction|SetupSkiMovement)
  ; Helmet on the head, paintball gun in the right hand (sockets on the Other5 mannequin skeleton).
  (Transformation|AttachComponentToComponent :self (Variables|Default|GetHelmet) :Parent (Variables|Character|GetMesh) :SocketName "head" :LocationRule "SnapToTarget" :RotationRule "KeepRelative" :ScaleRule "KeepRelative")
  (Transformation|AttachComponentToComponent :self (Variables|Default|GetGunMesh) :Parent (Variables|Character|GetMesh) :SocketName "weapon_r" :LocationRule "SnapToTarget" :RotationRule "SnapToTarget" :ScaleRule "KeepRelative")
  ; Other5Combat's gun meshes point their barrels along +Y; turned -90 degrees they point where the hand points
  ; (Other5Combat holds them the same way, with its weapons' Attach Offset).
  (Transformation|SetRelativeRotation :self (Variables|Default|GetGunMesh) :NewRotation (Math|Rotator|MakeRotator :Yaw -90.0))
  (CallFunction|ShowGun)
  ; Other5Combat's inventory hands out a pistol and grenades; skiers carry paintball guns instead.
  (if (Networking|HasAuthority)
    (Inventory|ClearInventory :self (Variables|Default|GetInventory))))

; Our player got this character: add the SKIvSKI controls (Settings > Controls lists them, keys can be changed).
; Priority 10 puts them above Other5Combat's controls, so W/A/S/D steer the skis instead of walking.
(event EventReceiveControllerChanged (OldController NewController)
  (if (Pawn|IsLocallyControlled)
    (bind pc (Utilities|Casting|CastToPlayerController :Object NewController)
      (:then
        (Other5|Input|AddOther5MappingContext :Player pc :Context "/SKIvSKI/Input/IMC_SkiVSki.IMC_SkiVSki" :Priority 10))
      (:CastFailed))))

(event EventTick (DeltaSeconds)
  (if (not (Variables|Ski|State|GetSkiStarted))
    (Variables|Ski|State|SetSkiStarted true)
    (CallFunction|SkiBeginPlay))
  (CallFunction|UpdateSlope)
  (CallFunction|UpdateGlide)
  (CallFunction|UpdateTeamLook)
  (if (Pawn|IsLocallyControlled)
    (CallFunction|ReadButtons)
    (if (not (Variables|Ski|State|GetSkiFrozen))
      ; Held keys (this player's own machine only).
      (Variables|Ski|Input|SetHoldDownhill (Input|EnhancedActionValues|IA_SkiDownhill))
      (Variables|Ski|Input|SetHoldSlow (Input|EnhancedActionValues|IA_SkiSlow))
      (Variables|Ski|Input|SetHoldLeft (Input|EnhancedActionValues|IA_SkiLeft))
      (Variables|Ski|Input|SetHoldRight (Input|EnhancedActionValues|IA_SkiRight))
      (CallFunction|SteerSkis :DeltaSeconds DeltaSeconds)
      (CallFunction|PushDownSlope)))
  (CallFunction|LeanIntoTurn :DeltaSeconds DeltaSeconds))

; Run on Server (unreliable): the owning player's skis turned; turn this character on the server too, which
; replicates the rotation to everyone else.
(event Custom|ServerSetSkiYaw (NewYaw)
  (Variables|Ski|State|SetSkiYaw NewYaw)
  (Transformation|SetActorRotation :NewRotation (Math|Rotator|MakeRotator :Yaw NewYaw)))
