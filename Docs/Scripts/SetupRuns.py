# SKIvSKI: the ski runs (BP_SkiRunData data assets, DA_Run*) and their skies (Other5 Sky Presets, DA_Sky*), in
# /SKIvSKI/Runs, and the slope's Runs list (BP_SkiSlope, in the order they take turns). Docs/SkiRuns.md says what each
# value does. Rerunnable: the assets are made if missing and every value set again.
# Run in the editor after the graphs are written: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupRuns"
FOLDER = "/SKIvSKI/Runs"
SKIES = FOLDER + "/Skies"
# Falling snow from Other5WinterBiome, the optional private art plugin: named by path, never referenced, so SKIvSKI
# stays public (a project without the plugin just has no snowfall).
SNOW = "/Other5WinterBiome/Particles/Snow_FX/snow_falling.snow_falling"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary


def color(r, g, b):
    return unreal.LinearColor(r, g, b, 1.0)


# name: (shown name, settings (FOther5SkySettings, by Python name), clouds, weather: (copies, speed) or None, cloud
# material parameters). The clouds are the engine's simple volumetric clouds (m_SimpleVolumetricCloud_Inst): its
# Cloud_GlobalCoverage (-0.2 as it comes: scattered) and Cloud_GlobalDensity (0.008) are set per sky.
SKY = {
    "DA_SkyClearDay": ("Clear day", {
        "sun_elevation": 48.0, "sun_yaw": 35.0, "sun_intensity": 10.0, "sun_color": color(1.0, 0.98, 0.95), "sun_temperature": 6000.0,
        "sky_light_intensity": 1.0, "sky_light_color": color(1, 1, 1),
        "rayleigh_scale": 0.0331, "mie_scale": 0.004, "sky_tint": color(1, 1, 1),
        "fog_density": 0.008, "fog_height_falloff": 0.2, "fog_color": color(0, 0, 0), "fog_start_distance": 0.0, "fog_max_opacity": 1.0,
        "cloud_bottom": 5.0, "cloud_height": 10.0,
        "exposure_bias": 0.0, "white_temp": 6500.0, "saturation": 1.05, "bloom": 0.675}, False, None, {}),
    "DA_SkyGoldenHour": ("Golden hour", {
        "sun_elevation": 9.0, "sun_yaw": 245.0, "sun_intensity": 6.0, "sun_color": color(1.0, 0.9, 0.8), "sun_temperature": 4300.0, "sun_shadow_amount": 0.85,
        "sky_light_intensity": 0.9, "sky_light_color": color(1.0, 0.95, 0.92),
        "rayleigh_scale": 0.0331, "mie_scale": 0.008, "sky_tint": color(1, 1, 1),
        "fog_density": 0.015, "fog_height_falloff": 0.25, "fog_color": color(0.02, 0.012, 0.006), "fog_start_distance": 0.0, "fog_max_opacity": 1.0,
        "cloud_bottom": 4.0, "cloud_height": 6.0,
        "exposure_bias": 0.0, "white_temp": 6500.0, "saturation": 1.0, "bloom": 0.8}, True, None, {"Cloud_GlobalCoverage": -0.25}),
    "DA_SkyOvercast": ("Overcast, light snow", {
        "sun_elevation": 35.0, "sun_yaw": 120.0, "sun_intensity": 2.5, "sun_color": color(0.9, 0.93, 1.0), "sun_temperature": 7000.0, "sun_shadow_amount": 0.35,
        "sky_light_intensity": 1.6, "sky_light_color": color(0.95, 0.97, 1.0),
        "rayleigh_scale": 0.006, "mie_scale": 0.02, "sky_tint": color(0.8, 0.82, 0.86),
        "fog_density": 0.06, "fog_height_falloff": 0.12, "fog_color": color(0.05, 0.055, 0.06), "fog_start_distance": 0.0, "fog_max_opacity": 1.0,
        "cloud_bottom": 2.0, "cloud_height": 6.0,
        "exposure_bias": 0.5, "white_temp": 6300.0, "saturation": 0.8, "bloom": 0.4}, True, (1, 1.0),
        {"Cloud_GlobalCoverage": 0.35, "Cloud_GlobalDensity": 0.02}),
    "DA_SkySnowstorm": ("Snowstorm", {
        "sun_elevation": 30.0, "sun_yaw": 160.0, "sun_intensity": 1.2, "sun_color": color(0.88, 0.92, 1.0), "sun_temperature": 7500.0, "sun_shadow_amount": 0.15,
        "sky_light_intensity": 1.8, "sky_light_color": color(0.92, 0.95, 1.0),
        "rayleigh_scale": 0.008, "mie_scale": 0.03, "sky_tint": color(0.75, 0.78, 0.82),
        "fog_density": 0.2, "fog_height_falloff": 0.05, "fog_color": color(0.12, 0.13, 0.14), "fog_start_distance": 0.0, "fog_max_opacity": 0.97,
        "cloud_bottom": 1.0, "cloud_height": 5.0,
        "exposure_bias": 0.7, "white_temp": 6200.0, "saturation": 0.6, "bloom": 0.3}, True, (4, 1.8),
        {"Cloud_GlobalCoverage": 0.6, "Cloud_GlobalDensity": 0.03}),
}

# Flakes drifting round the camera (BuildSnowfall.py), per sky: the clear day stays clear, golden hour gets a gentle
# fall, overcast light snow, the storm a heavy one.
SNOWFALL = {"DA_SkyGoldenHour": "BP_SkiFlakesLight", "DA_SkyOvercast": "BP_SkiFlakesLight", "DA_SkySnowstorm": "BP_SkiFlakesHeavy"}

# name: values (BP_SkiRunData's variables; 0 keeps the slope's own). FortSpots: (how far down 0-1, across -1 left edge
# .. 1 right edge), the same every time the run is played. Lengths in cm; the first run is the original 400 m slope.
RUNS = [
    ("DA_RunPineBowl", {
        "RunName": unreal.Text("Pine Bowl"), "Blurb": "The original run: 400 m, three forts down the second half.",
        "Length": 40000.0, "TopWidth": 12000.0, "FinishWidth": 4000.0, "SlopeScale": 1.0, "BumpScale": 1.0, "ShapeSeed": 0,
        "CellSize": 0.0, "TreeScale": 1.0, "FortSpots": [(0.5, -0.55), (0.64, 0.5), (0.78, -0.4)],
        "FortCount": 0, "FortSeed": 0, "FortFrom": 0.0, "FortTo": 0.0, "RaceSeconds": 150.0, "Sky": "DA_SkyClearDay"}),
    ("DA_RunLongGlacier", {
        "RunName": unreal.Text("Long Glacier"), "Blurb": "Twice as long (800 m), gentler and smoother, five forts, at sunset.",
        "Length": 80000.0, "TopWidth": 12000.0, "FinishWidth": 5000.0, "SlopeScale": 0.9, "BumpScale": 0.8, "ShapeSeed": 4242,
        "CellSize": 0.0, "TreeScale": 1.0, "FortSpots": [(0.3, 0.55), (0.42, -0.6), (0.55, 0.1), (0.68, 0.6), (0.82, -0.45)],
        "FortCount": 0, "FortSeed": 0, "FortFrom": 0.0, "FortTo": 0.0, "RaceSeconds": 240.0, "Sky": "DA_SkyGoldenHour"}),
    ("DA_RunStormChute", {
        "RunName": unreal.Text("Storm Chute"), "Blurb": "600 m, narrow, steep and bumpy, four forts zigzagging, in a snowstorm.",
        "Length": 60000.0, "TopWidth": 9000.0, "FinishWidth": 3500.0, "SlopeScale": 1.1, "BumpScale": 1.3, "ShapeSeed": 99,
        "CellSize": 0.0, "TreeScale": 0.8, "FortSpots": [(0.35, -0.5), (0.5, 0.5), (0.65, -0.5), (0.8, 0.5)],
        "FortCount": 0, "FortSeed": 0, "FortFrom": 0.0, "FortTo": 0.0, "RaceSeconds": 200.0, "Sky": "DA_SkySnowstorm"}),
    ("DA_RunGrandDescent", {
        "RunName": unreal.Text("Grand Descent"), "Blurb": "Three times as long (1.2 km), wide, seven forts, under grey skies.",
        "Length": 120000.0, "TopWidth": 14000.0, "FinishWidth": 4500.0, "SlopeScale": 0.85, "BumpScale": 1.0, "ShapeSeed": 777,
        "CellSize": 300.0, "TreeScale": 0.9,
        "FortSpots": [(0.25, -0.5), (0.36, 0.55), (0.47, 0.0), (0.58, -0.6), (0.66, 0.6), (0.75, -0.2), (0.85, 0.45)],
        "FortCount": 0, "FortSeed": 0, "FortFrom": 0.0, "FortTo": 0.0, "RaceSeconds": 330.0, "Sky": "DA_SkyOvercast"}),
]


def make(folder, name, data_class):
    path = folder + "/" + name
    if eal.does_asset_exist(path):
        return unreal.load_asset(path)
    f = unreal.DataAssetFactory()
    f.set_editor_property("data_asset_class", data_class)
    log("created " + path)
    return at.create_asset(name, folder, data_class, f)


def main():
    skies = {}
    for name, (label, values, clouds, weather, cloud_params) in SKY.items():
        da = make(SKIES, name, unreal.Other5SkyPreset)
        da.set_editor_property("display_name", unreal.Text(label))
        settings = da.get_editor_property("settings")
        for k, v in values.items():
            settings.set_editor_property(k, v)
        da.set_editor_property("settings", settings)
        da.set_editor_property("clouds", clouds)
        da.set_editor_property("cloud_parameters", {unreal.Name(k): v for k, v in cloud_params.items()})
        # The Winter biome's particle snow only where there are no flakes of our own: its copies sit round the camera
        # and move with it (and a copy beside you looked like a bubble of snow, 2026-11-22).
        if weather and not SNOWFALL.get(name):
            da.set_editor_property("weather_effect_path", SNOW)
            da.set_editor_property("weather_copies", weather[0])
            da.set_editor_property("weather_speed", weather[1])
        else:
            da.set_editor_property("weather_effect_path", "")
        fall = SNOWFALL.get(name)
        da.set_editor_property("weather_actor", unreal.load_asset(SKIES + "/FX/" + fall).generated_class() if fall and eal.does_asset_exist(SKIES + "/FX/" + fall) else None)
        eal.save_loaded_asset(da, False)
        skies[name] = da
        log("sky " + name)
    run_class = unreal.load_asset(FOLDER + "/BP_SkiRunData").generated_class()
    runs = []
    for name, values in RUNS:
        da = make(FOLDER, name, run_class)
        for k, v in values.items():
            if k == "FortSpots":
                v = [unreal.Vector2D(x, y) for x, y in v]
            elif k == "Sky":
                v = skies[v]
            try:
                da.set_editor_property(k, v)
            except Exception as e:
                log("  cannot set %s.%s: %s" % (name, k, e))
        eal.save_loaded_asset(da, False)
        runs.append(da)
        log("run " + name)
    bp = unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiSlope")
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    cdo = unreal.get_default_object(bp.generated_class())
    cdo.set_editor_property("Runs", runs)
    eal.save_loaded_asset(bp, False)
    log("BP_SkiSlope: %d runs" % len(runs))


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
