// Falling streaks on a cylinder round the camera (BP_SkiSnow*), as the opacity of M_SkiStreaks (the same shader as
// CubeEscape's rain, Docs/Materials/M_CubeRain.hlsl there). Everything comes from the
// world position against the cylinder's centre, so the engine cylinder's UVs don't matter and each layer (any radius)
// gets streaks the same size: columns Spacing cm apart round the cylinder, one streak per Rows cm of height in each,
// Width cm wide and Length (0-1 of a row) long, falling Speed cm/s, a random Density of the columns in use, each column
// swaying Sway cm side to side (0 for rain; snowflakes drift). Short, wide, slow, swaying streaks make snow.
// Inputs: P (absolute world position), C (object position), T (time), Spacing, Width, Rows, Length, Speed, Density, Sway.
float2 D = P.xy - C.xy;
float R = max(length(D), 1.0);
float X0 = (atan2(D.y, D.x) + 3.14159265) * R / Spacing;
float Id = floor(X0);
float H1 = frac(sin(Id * 12.9898) * 43758.5453);
float H2 = frac(sin(Id * 78.233) * 12543.1234);
float X = X0 + Sway / Spacing * sin(T * (0.6 + 0.6 * H1) + H2 * 6.2832 + P.z * 0.004);
// Thin line in the middle of each column, widened to a pixel when far away (no shimmer), and faded by as much.
float W = Width / Spacing;
float Aa = max(W, fwidth(X));
float Line = saturate(1.0 - abs(frac(X) - 0.5) / Aa) * (W / Aa);
// Falling dashes: each column at its own speed and phase.
float Y = (P.z - C.z) / Rows + T * Speed / Rows * (0.75 + 0.5 * H1) + H2 * 17.0;
float Seg = frac(Y);
float Dash = Seg < Length ? Seg / Length : 0.0;
float Keep = step(H1, Density);
// Fade out towards the cylinder's top and bottom (it's 30 m tall, centred on the camera).
float Z = abs(P.z - C.z) / 1500.0;
float Ends = saturate((1.0 - Z) * 3.0);
return Line * Dash * Keep * Ends;
