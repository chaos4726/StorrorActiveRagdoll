# STORROR Active Ragdoll

Active ragdolls, injuries, gore and an x-ray skeleton for **STORROR Parkour Pro**, as a UE4SS Lua mod. When he bails, his body reacts like a person's: he braces on the way down, grabs whatever hurts, curls up and kicks, and each part of him dislocates, breaks or comes off by how hard it hits. He stays down until you press A (or Space).

**Download:** grab `StorrorActiveRagdoll_v1.0.zip` from [Releases](../../releases). It includes UE4SS, ready to drop in.

## What's in it

- **Active ragdoll:** STORROR's own bails, with soft joint limits, a gentle pull toward a natural posture, spin on every impact, a falling animation under the physics and his head protected on the way down. While he's down he holds his worst injury (face first, then chest, then limbs), kicks and curls up. Dead, he goes completely limp.
- **Injuries:** every part of him is hurt by its own impact: dislocated, broken or cut off. Injuries can stay after he gets up (hurt limbs hang, slow him and lower his jumps), stack with new hits, and heal over time. TARKOV DAMAGE splits his HP over head, chest, arms and legs.
- **Gore:** severed limbs and head, open breaks with the bone sticking out, bleeding, blood drops, splats and stains, blood soaking into his clothes, and explosions on the hardest hits. Each one can be switched off.
- **X-ray skeleton:** a real anatomical skeleton seen through his body on a break, while he's down, or all the time. Broken bones show red, dislocated ones orange. REMOVE PLAYER leaves only the bones.
- **Physics:** NEWTONS LAW (momentum kept, no air drag up to 400 mph), a GRAVITY slider from 0% to 300% (with the moon, Mars and Jupiter on it), a FALL HEIGHT for knock-downs, running into walls, and rolls that save him.
- **HUD:** an HP bar, a body figure colored by his injuries, STORROR's bail counter counting his injuries, and a speedometer.
- **Online:** peer-to-peer lobbies through Steam in STORROR's ONLINE tab (public, passworded or friends only). You see the other players' moves, ragdolls and gore.

## The RAGDOLL tab

The pause menu gets a **RAGDOLL** tab, between CONTROLS and SETTINGS, with 32 settings in 9 groups: RAGDOLL, GRAVITY, FALLS, INJURIES, GORE, X-RAY, HEALTH, HUD and HELP. The game keeps running behind it, so you see each change as you make it. With **SETTING INFO** on, a box beside the menu explains the setting you're on. Every setting is also listed in [`StorrorActiveRagdoll/README.txt`](StorrorActiveRagdoll/README.txt).

## Controls

- **Get up:** A on a controller, or Space. He never stands up on his own.
- **Roll as you land** (B or Left Ctrl) to stay on your feet, with ROLLS NEGATE RAGDOLLS on.

## With STORROR First Person

Works with or without [StorrorFirstPerson](https://github.com/chaos4726/StorrorFirstPerson). With both installed, the pause menu has both tabs (RAGDOLL, then FIRST PERSON). First person's **THIRD PERSON IN BAILS** setting picks whether you watch a ragdoll from his eyes or from behind him.

## Install

1. In Steam, right-click STORROR Parkour Pro > Manage > Browse local files.
2. Copy the `STORRORParkourPRO` folder from the release zip into that folder (merge / replace files).
3. Start the game. Pause and open the RAGDOLL tab to change anything.

Already using UE4SS for other mods (StorrorFirstPerson included)? Copy only `StorrorActiveRagdoll` into your `ue4ss\Mods` folder and add `StorrorActiveRagdoll : 1` to `Mods\mods.txt`.

**Uninstall:** delete `STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\StorrorActiveRagdoll` (and `dwmapi.dll` plus the `ue4ss` folder next to it to remove the loader too).

**Antivirus:** some antivirus programs flag `dwmapi.dll` (the UE4SS loader) or the mod's `bin\arnet.dll` (its online play). Allow them if yours does. The source of both is public: UE4SS's on its own GitHub, arnet's in [`arnet/`](arnet).

## This repository

- [`StorrorActiveRagdoll/`](StorrorActiveRagdoll) is the mod folder as it goes in `ue4ss\Mods`. `Scripts\main.lua` loads `ragdoll.lua` (the ragdoll, injuries and the body's mind), `gore.lua` (cut-off parts, wounds and blood), `xray.lua` and `xray_bones.lua` (the skeleton), `armenu.lua` (the RAGDOLL tab), `arhud.lua` (the HUD), `armp.lua` and `armpmenu.lua` (online play and its screen) and `alib.lua`.
- [`arnet/`](arnet) is the source of `bin\arnet.dll`, the online play's networking (Steam lobbies and peer-to-peer messages; no servers).

The release zip also contains [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT licence), the build that runs with STORROR's Unreal Engine 5.7. A game update may need a newer UE4SS.

## Credits

- **STORROR Parkour PRO** is by **Hole in the Sleeve Game Studios** ([Steam](https://store.steampowered.com/app/3125250/STORROR_Parkour_PRO/)). You need to own it to play this mod.
- The ragdoll's soft joint limits, posture pull, impact spin, layered falling animation, head protection and dislocations follow **Lincoln Margison**'s videos "Improving ragdolls forever" and "Ragdolls improved by YOUR suggestions".
- The x-ray skeleton is made from **BodyParts3D**, © The Database Center for Life Science, licensed under [CC Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/) ([BodyParts3D](https://dbarchive.biosciencedbc.jp/en/bodyparts3d/)). The changes made to it are listed in [`StorrorActiveRagdoll/CREDITS.txt`](StorrorActiveRagdoll/CREDITS.txt).
- **UE4SS** loads the mod into the game ([RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)).

This is a free fan project, not affiliated with or endorsed by Hole in the Sleeve Game Studios or STORROR.
