// Falling streaks on a cylinder round the camera (BP_SkiSnow*), as the opacity of M_SkiStreaks (the same shader as
// CubeEscape's rain, Docs/Materials/M_CubeRain.hlsl there). Everything comes from the
// world position against the cylinder's centre, so the engine cylinder's UVs don't matter and each layer (any radius)
// gets streaks the same size: columns Spacing cm apart round the cylinder, one streak per Rows cm of height in each,
// Width cm wide and Length (0-1 of a row) long, falling Speed cm/s, a random Density of the columns in use, each column
// swaying Sway cm side to side (0 for rain; snowflakes drift), and each dash moved up to Jitter (0-0.4 of a column) to the
// side and given its own sway, so flakes don't fall in straight lines. Short, wide, slow, swaying streaks make snow.
// Inputs: P (absolute world position), C (object position), T (time), Spacing, Width, Rows, Length, Speed, Density, Sway,
// Jitter, Round (0: streaks with a fading tail, for rain; 1: soft round flakes, for snow).
float2 D = P.xy - C.xy;
float R = max(length(D), 1.0);
float X0 = (atan2(D.y, D.x) + 3.14159265) * R / Spacing;
float Id = floor(X0);
float H1 = frac(sin(Id * 12.9898) * 43758.5453);
float H2 = frac(sin(Id * 78.233) * 12543.1234);
// Falling dashes: each column at its own speed and phase.
float Y = (P.z - C.z) / Rows + T * Speed / Rows * (0.75 + 0.5 * H1) + H2 * 17.0;
// Each dash (flake) its own place across the column and its own sway.
float H3 = frac(sin(Id * 37.719 + floor(Y) * 91.173) * 24634.6345);
float X = X0 + (H3 - 0.5) * 2.0 * Jitter + Sway / Spacing * sin(T * (0.6 + 0.8 * H3) + H3 * 6.2832 + H2 * 3.1);
// Thin line in the middle of each column, widened to a pixel when far away (no shimmer), and faded by as much.
float W = Width / Spacing;
// (From the smooth X0: each flake's own offset jumps between flakes, and its fwidth would wash out the flakes.)
float Aa = max(W, fwidth(X0));
float Line = saturate(1.0 - abs(frac(X) - 0.5) / Aa) * (W / Aa);
float Seg = frac(Y);
float Dash = Seg < Length ? Seg / Length : 0.0;
// A soft round blob over the same dash, for snowflakes.
float Dx = abs(frac(X) - 0.5) / Aa;
float Dy = abs(Seg / Length - 0.5) * 2.0;
float Blob = saturate(1.0 - (Dx * Dx + Dy * Dy)) * (W / Aa);
float Shape = lerp(Line * Dash, Blob, Round);
float Keep = step(H3, Density);
// Fade out towards the cylinder's top and bottom (it's 30 m tall, centred on the camera).
float Z = abs(P.z - C.z) / 1500.0;
float Ends = saturate((1.0 - Z) * 3.0);
return Shape * Keep * Ends;
