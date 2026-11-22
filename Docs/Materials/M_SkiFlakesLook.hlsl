// Opacity of M_SkiFlakes: a soft round flake on its square, faded out near the camera (Near cm, so none fills the
// screen) and toward the edge of the flakes' cube (Box), so flakes wrapping round to the far side fade in, never pop.
// Inputs: UV, P (pixel world position), Cam (camera position), Box, Near.
float2 D = (UV - 0.5) * 2.0;
float Round = saturate(1.0 - dot(D, D));
float3 V = abs(P - Cam);
float Edge = max(max(V.x, V.y), V.z);
float Far = saturate((Box * 0.5 - Edge) / (Box * 0.2));
float Close = saturate((length(P - Cam) - Near) / Near);
return Round * Round * Far * Close;
