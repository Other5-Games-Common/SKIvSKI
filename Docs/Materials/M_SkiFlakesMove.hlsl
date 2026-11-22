// World Position Offset of M_SkiFlakes (BP_SkiFlakes*): each instance of the flakes' instanced mesh (a small square) is
// one snowflake fixed in the world, not on the screen: it falls and drifts through the world, and you ski through it.
// The flakes fill a Box cm cube round the camera, and a flake that leaves the cube (behind you, or below) comes back in
// on the far side (its position is wrapped round the camera), so there are always flakes ahead however fast you go.
// The square is turned to face the camera and sized Size cm.
// Inputs: R (Per Instance Random: this flake's own number, 0-1), Cam (camera position), Right, Up (the
// camera's right and up, in the world), UV (the square's corner, 0-1), P (the vertex's own world position), T (time),
// Box, Size, Speed (falling, cm/s), Sway (cm of side to side drift), WindX, WindY (cm/s), MinAngle.
// This flake's place in the world at T = 0, from its own number (the instances' own positions don't reach the shader
// on every platform).
float3 S = (frac(sin(R * float3(127.1, 311.7, 74.7) + float3(1.3, 2.9, 0.7)) * 43758.5453) - 0.5) * Box;
float H1 = frac(sin(R * 269.5 + 4.1) * 43758.5453);
float H2 = frac(sin(R * 183.3 + 2.2) * 43758.5453);
float Fall = Speed * (0.8 + 0.4 * H1);
float3 W = S + float3(WindX * T, WindY * T, -Fall * T);
W.xy += Sway * float2(sin(T * (0.7 + 0.6 * H2) + H1 * 6.2832), cos(T * (0.5 + 0.5 * H1) + H2 * 6.2832));
// The copy of this flake that's in the cube round the camera.
float3 F = Cam + (frac((W - Cam) / Box + 0.5) - 0.5) * Box;
// Never smaller on screen than MinAngle (radians across: about two pixels), or far flakes vanish between pixels.
float Across = max(Size * (0.75 + 0.5 * H2), length(F - Cam) * MinAngle);
float2 C = (UV - 0.5) * Across;
return F + Right * C.x + Up * C.y - P;
