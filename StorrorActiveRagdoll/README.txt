STORROR ACTIVE RAGDOLL  v1.0
===========================

Active ragdolls, injuries, gore and an x-ray skeleton for STORROR Parkour Pro. When he bails, his body reacts like a
person's: he braces on the way down, grabs whatever hurts, curls up and kicks, and each part of him dislocates, breaks
or comes off by how hard it hits. He stays down until you press A on a controller, or Space.

Every setting is on the RAGDOLL tab of the pause menu, between CONTROLS and SETTINGS. With SETTING INFO on, a box
beside the menu explains the setting you're on. Your choices are kept in settings.txt in this folder; delete it to go
back to the defaults.


CONTROLS
--------
Get up: A, or Space. He never stands up on his own.
Roll as you land (B or Left Ctrl) to stay on your feet, with ROLLS NEGATE RAGDOLLS on.


THE SETTINGS
============

RAGDOLL
-------
LIVE RAGDOLL
    While he's down he moves on his own: holds his injuries, kicks, curls up and tries to get up. Off: he lies
    limp like STORROR's own ragdoll.
NEWTONS LAW
    Real momentum: his spin carries into the ragdoll and never slows in the air, and falls have no air drag,
    speeding up to 400 mph. Off: normal spin, and drag holds falls near 120 mph.
ROLLS NEGATE RAGDOLLS
    A roll saves him: falls and trips during a roll don't ragdoll him, and if one starts he's put straight back
    on his feet.
WALL SLIDE
    STORROR's slide down walls. Off: he ragdolls the moment a wall slide starts.
RUN INTO WALLS
    Running into a wall or an object knocks him down. Off: it doesn't.

GRAVITY
-------
GRAVITY
    How strong gravity is, for everything: him on his feet and ragdolled, cut-off limbs, blood and loose objects.
    100% is normal and 0% is none at all; 17% is the moon, 38% Mars, 253% Jupiter. Under 100%: higher jumps,
    slower falls. Over it: lower jumps, harder landings.
MOON GRAVITY
    Puts GRAVITY at 17%, the moon's: higher, floatier jumps and slow falls on his feet, and a ragdoll, cut-off
    limbs, blood and loose objects that fall slowly. Turn it off to go back to 100%.

FALLS
-----
FALL HEIGHT
    How far he can fall before the landing knocks him down, 5 to 500 ft. OFF: falls never knock him down. Heights
    are at normal gravity: with GRAVITY lower it takes a longer fall, with it higher a shorter one.

INJURIES
--------
KEEP INJURIES
    Injuries stay after he gets up: broken or dislocated limbs keep hanging until they heal. Off: he's healed
    every time he gets up.
EASY INJURIES
    Injuries at much lower speeds: a fracture from 5 mph, a break from 15 mph, a limb cut off from 30 mph.
SCALING DAMAGE
    Injuries stack: each new landing on a hurt part makes it worse by that hit - a dislocated part breaks, a
    broken part comes off, even under 50 mph. With TARKOV DAMAGE a limb at 0 HP comes off on its next hit.
NON-RAGDOLL DAMAGE
    He's hurt while not ragdolled: landing on his feet from about 8 ft or more hurts his legs by the landing's
    speed - fractures, breaks, a leg giving way. A roll takes none.
TARKOV DAMAGE
    His HP is split over head, chest, arms and legs, each with its own HP like Tarkov. Head or chest at zero
    kills him; limbs heal one at a time.
LIMB SLOWNESS
    Hurt legs and arms slow him down on his feet. Off: injuries don't slow him.
BLEED FOREVER
    Cuts and open breaks keep bleeding for as long as he has them. Off: a stump bleeds for 2 minutes, a broken
    bone's wound for 30 seconds.

GORE
----
SEVERED LIMBS
    Limbs and his head can be cut off by hard enough hits. Off: nothing is ever cut off - those hits break the
    limb instead, and he never explodes.
BONES STICKING OUT
    Some breaks are open: the broken bone pokes out through a bleeding wound. Off: every break is closed - no
    bone, no wound.
BLEEDING
    He bleeds from cuts, stumps and open breaks, losing HP as he does. Off: no blood at all and no HP lost to
    bleeding.
EXPLODE
    Any injury at all blows him apart.
NO EXPLOSIONS
    He is never blown apart, however fast the hit. Overrides EXPLODE. Hits still break and cut off limbs.
BLOOD STAIN LIMIT
    How many blood stains can be on the ground before the oldest disappear. Lower it if the game slows down.

X-RAY
-----
X-RAY ON BREAKS
    When one of his bones breaks, you see his real skeleton through his body until he gets up: broken bones red,
    dislocated orange.
X-RAY BODY
    See his skeleton through his body the whole time he's ragdolled: broken bones red, dislocated orange, cut-off
    bones gone.
X-RAY ALWAYS ON
    His skeleton shows through his body all the time - running, climbing and ragdolled.
REMOVE PLAYER
    Hides his body whenever his skeleton shows, so you see only the bones. With X-RAY ALWAYS ON he's a walking
    skeleton.

HEALTH
------
HP BAR
    Shows his HP, lost as he bleeds and gets hurt; at zero he's dead. Off: no bar and no bleeding out.
MAX HP
    How much HP he has, 10 to 1000. A drop of blood costs 0.1 HP, a fracture 3, a break 5, a limb cut off 10.
REGENERATION
    HP healed every second, from 0.25 up to 100 (OFF at 0). Fractures and breaks mend as he heals; cut-off limbs
    never grow back.

HUD
---
DAMAGE HUD
    Shows the body figure, each part colored by its injuries.
INJURY COUNTER
    STORROR's bail counter, counting his injuries as this mod has them.
SPEEDOMETER
    Shows his speed in mph and km/h under the HP panel.

HELP
----
SETTING INFO
    Shows this box explaining the setting you are on. Off: no box.


ONLINE
------
Pause and open the ONLINE tab: host a public, passworded or friends-only lobby, join a public one, or invite Steam
friends. Players see each other's moves, ragdolls and gore. It's peer to peer through Steam (bin\arnet.dll), with
no servers.


WITH STORROR FIRST PERSON
-------------------------
Works with or without StorrorFirstPerson. With both, the pause menu has both tabs (RAGDOLL, then FIRST PERSON). First
person's THIRD PERSON IN BAILS setting picks whether you watch a ragdoll from his eyes or from behind him.


CREDITS
-------
STORROR Parkour PRO is by Hole in the Sleeve Game Studios.
The ragdoll follows Lincoln Margison's videos "Improving ragdolls forever" and "Ragdolls improved by YOUR suggestions".
The x-ray skeleton is made from BodyParts3D, (c) The Database Center for Life Science, CC Attribution 4.0 - see
CREDITS.txt.
