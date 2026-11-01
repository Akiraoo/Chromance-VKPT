# Chromance-VKPT

**English** · [繁體中文](README.zh-TW.md) · [简体中文](README.zh-CN.md)

![Chromance-VKPT: a cherry grove at sunset](figures/hero.jpg)

A path-traced shader pack for the [Radiance](https://github.com/Minecraft-Radiance) mod, written from scratch with a
warm, stylised look in the spirit of popular rasterised shader packs, but lit entirely by real path tracing.

## The name

**Chromance** = **Chroma** + **Radiance**. *Chroma* is colour: coloured light from every torch and lantern, a palette
that shifts with the time of day, warm sunlight against blue shade. *Radiance* is both the mod this pack is made for
and the physical quantity path tracing computes: the light travelling along every ray. **VKPT** stands for
**Vulkan Path Tracing**, the technique behind it.

> Status: **polishing**. All four development stages (core, water and rain, clouds, exposure and photo) are
> done; work now goes into fixes and fine-tuning the look.

## Screenshots

| Village in the rain | Under water |
| --- | --- |
| ![Rain: ripples and reflections on the water](figures/rain.jpg) | ![Under water: light shafts and blue-green haze](figures/underwater.jpg) |

![Night sky: moon, clouds and a coloured nebula](figures/night.jpg)

## Features

- **Path-traced lighting**: sun and moon light with soft shadows, sky light and multi-bounce indirect light.
- **Coloured block lights**: torches, lanterns, glowstone, lava and every other emissive surface light the world
  in their own colour. Lights are sampled directly instead of being found by chance, so they stay **stable while
  you move** (no flickering).
- **Limited light reach**: block light fades out over a configurable range, so a torch lights a small area and the
  rest of the cave stays dark, like a lighter in the dark.
- **Faint glows stay decorative**: glow lichen, emissive ores from resource packs and other faint glows still glow
  on screen but no longer light up a cave by default (*Weak Glow Lighting* turns that back on). Lava and other
  bright emitters are toned down so they no longer blow out the picture.
- **Caves**: underground, the sun is not traced at all; under a partial opening (a shaft, a cave mouth) it is traced
  in proportion to how much sky you can see. Cave haze is darker and thinner, and underground water no longer
  glows.
- **Time-of-day palette**: white noon, golden sunrise and sunset, a pale blue sky in the blue hour just after
  sunset and before sunrise, and dim, almost neutral moonlight at night (no all-blue world).
- **Sun and moon shape**: round discs or vanilla-style squares; the round moon shows its phase.
- **labPBR 1.3**: smoothness, F0 and hardcoded metals, emission, subsurface (foliage back-lighting), normal maps
  and ambient occlusion.
- **Sun shafts**: beams of sun and moon light through leaves, buildings and cloud gaps (Tyndall effect), plus
  screen-space shafts so the beams also show over open ground.
- **Glass**: clear, tinted when stained; with a dark room or night behind it, glass turns into a mirror like a real
  window. Glass and metal reflections stay sharp under the denoiser; *Metal Reflection Sharpness* makes metal blocks
  reflect more clearly than their resource pack's roughness says.
- **Water**: clear water you can see through from above, with reflection and refraction, gentle moving waves
  (drawn after denoising so they never freeze or smear) and a thin, scattered web of caustics on the floor.
  Under water, colours fade with depth in the real order (red first, then yellow and green, blue last), light
  shafts fade with depth, and the haze follows how much daylight reaches you. Looking up shows Snell's window: a
  round window to the world above with the surface mirroring the water around it (or a clean mirror, or fully
  clear, as you like). Special biome water (warm oceans, swamps...) keeps its colour.
- **Rain**: wet, glossy ground with a water film, puddles and ripples that spread as several thin rings of
  different sizes, overlapping at random, on puddles and open water; clear, refracting rain streaks. The sun is
  hidden behind the rain clouds, so there are no sun shadows in rain. Only places that actually get rain and are open to the sky get wet (deserts and
  snowy biomes stay dry); the ground dries slowly after the rain.
- **Clouds**: volumetric clouds (puffy cumulus in fair weather that close into a grey overcast deck as rain sets
  in) with moving cloud shadows, or vanilla block clouds, also casting shadows.
- **Night sky**: stars hidden behind clouds and an optional faint, coloured nebula band.
- **Eye adaptation**: stepping into daylight dazzles and settles quickly; darkness takes seconds to adjust to, and
  caves stay dark.
- **Item and entity lights**: dropped light blocks (glowstone, torches, lanterns...) light their surroundings.
- **Glowing mob eyes**: endermen, spiders, phantoms and other mobs with glowing eyes show them using Radiance's
  own eye emission maps, without a resource pack and without lighting up the mob's body.
- **Night vision**: the night vision effect brightens the world (including under water) with a soft lift instead
  of washing it out.
- **Spectator mode**: inside solid ground the walls around you are drawn plainly with an even light, so flying
  through terrain stays smooth and shows no holes to the sky.
- **Bloom and depth of field**: soft glow around bright light; optional depth of field with autofocus (on the
  crosshair) or a fixed focus distance.
- **Colour grading**: warm/cool split tone, filmic punch, contrast, saturation, vignette, film grain and a
  deband filter against 8-bit banding.
- Works with Radiance's denoisers (DLSS Ray Reconstruction or NRD) and upscalers; DLSS Ray Reconstruction is
  recommended.
- **Light that stays where it belongs**: lights only shine from their front face, and full blocks that a resource
  pack marks as subsurface no longer let light through, so no light leaks through floors and ceilings. Glow
  berries and other blocks that really give off light in Minecraft light their surroundings even with weak glow
  lighting off.
- **Linear texture colours**: textures keep their contrast and colour instead of looking pale and dusty.
- **Far coordinates**: waves, ripples, puddles, rain, caustics and clouds stay smooth even a million blocks from the origin
  instead of breaking into a mosaic from float precision loss.

## Requirements

- Minecraft **1.21.4** with **Radiance 0.1.6-alpha** (Fabric).
- A GPU with hardware ray tracing (NVIDIA RTX or equivalent). Developed on an RTX 3080.
- Radiance's chunk emission collection must stay enabled (it is on by default); Chromance needs it for block
  lights. If it is off, Radiance falls back to its built-in pack.

## Installation

1. Download the pack (or clone this repository) into `<minecraft instance>/shaderpacks/`.
   A folder works as well as a zip.
2. In game, open Radiance's settings, go to the shader pack page and select **Chromance VKPT**.
3. **After updating the pack, press "Reset all" on the shader pack settings page.** Radiance stores every
   setting value the first time a pack is loaded, so new defaults only apply after a reset.
4. **Recommended Radiance tone mapping settings** (Radiance settings, tone mapping page): turn on
   *Manual Exposure*, set *Manual Exposure EV* to **0**, and set *Curve Lift Limit* to **0**. Chromance's
   brightness levels are designed as final values; Radiance's automatic exposure and shadow lift otherwise
   brighten nights and rain back up to near daylight.
5. Keep Minecraft's own *Brightness* (gamma) at its default; use the pack's *Brightness* setting instead.

## Settings overview

| Group | What it controls |
| --- | --- |
| Lighting | Overall brightness, indirect bounces, sun / moon / sky strength, ambient sky light, sun shafts, shadow softness, minimum light |
| Block Lights | Strength, range, light rays and candidates per surface, sample limit, item and entity lights, weak glow lighting |
| Sky & Time of Day | Sun and moon shape and size, golden hour, blue hour, night brightness and colour, night nebula |
| Fog & Water | Haze, border fog start, underwater surface (Snell's window), water murkiness, biome water colour, waves, underwater light shafts, clouds, cloud coverage, quality and shadows |
| Rain | Wet ground, puddles, ripples, rain streak amount and opacity |
| Materials | labPBR texture filtering, normal map strength, glass reflection, metal reflection sharpness, linear texture colours |
| Camera | Eye adaptation, its strength, dark limit and speed; depth of field (autofocus, focus distance, strength) |
| Color Grading | Bloom (strength, threshold), contrast, saturation, vibrance, warm/cool split, punch, vignette, film grain |

Performance tips: *Indirect Bounces*, *Block Light Rays*, *Cloud Quality* and *Sun Shafts* have the largest cost.

## Roadmap

1. ~~Core: path tracing, labPBR, coloured lights, anti-flicker, time-of-day palette, sun / moon shape, night~~
2. ~~Water and rain: waves, caustics, underwater look, biome water colour, wet ground and ripples, clear rain~~
3. ~~Clouds: volumetric and block clouds with shadows~~
4. ~~Exposure and photo mode: eye adaptation, dropped item lights, depth of field, bloom~~

## Known limitations

- Faint emissive textures from resource packs (glowing ores, for example) are still in Radiance's light list even
  when *Weak Glow Lighting* is off, so many of them in view (an x-ray view of a cave system) cost some frame rate.
- With DLSS Ray Reconstruction off (NRD), small lights and caves are noisier; DLSS Ray Reconstruction is
  recommended.

- Very far from the origin (around a million blocks and beyond), the positions of blocks and lights themselves are
  limited by Minecraft's and Radiance's float precision, which a shader pack cannot fix. The pack's own patterns
  (waves, clouds, ...) repeat every 16384 blocks and jump slightly where that line is crossed.

## Credits

- [Radiance / MCVR](https://github.com/Minecraft-Radiance) for the renderer and the shader pack interface.
- The **Vanilla PT** shader pack that ships with Radiance, which served as the reference for the interface layer
  (geometry and material decoding, alpha testing, the raster passes for particles, text and stars). The files in
  `interface/` and `post/` are derived from it.
- The volumetric cloud noise volumes in `textures/` (`cloud_shape_noise.raw`, `cloud_detail_noise.raw`) come from
  Vanilla PT as well (GPL-3.0).
- Complementary Shaders and SEUS were visual references for the overall mood only; no code from them is used.

## License

Chromance-VKPT is licensed under the **GNU General Public License v3.0** (see `LICENSE`), like Radiance and its
built-in packs whose interface it uses.

Exceptions:
- `interface/random.glsl` is Copyright NVIDIA Corporation, licensed under the Apache License 2.0 (header kept in
  the file).
- `common/shared.hpp` and `common/mapping.hpp` are Radiance's (MCVR) interface headers, GPL-3.0.

