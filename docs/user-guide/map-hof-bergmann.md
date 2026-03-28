# Hof Bergmann Map Support

Realistic Livestock RM includes built-in support for the [Hof Bergmann](https://www.lsfarming-mods.com/filebase/filebase/27-maps/) map. When you load a savegame on Hof Bergmann, the mod automatically detects the installed map version and loads the matching configuration. No manual setup required.

> **Note:** This documentation was generated with AI assistance and may contain inaccuracies. If you spot an error, please [open an issue](https://github.com/rittermod/FS25_RealisticLivestockRM/issues).

---

## How It Works

The mod checks for Hof Bergmann at game start and reads the map's version number. If the version matches a tested configuration, everything loads seamlessly. If the map has been updated to a version the mod hasn't been tested with yet, you'll see a warning dialog with a link to report any problems.

You don't need to do anything — the detection and configuration loading is fully automatic.

## Supported Versions

| Map Version | Config | Status |
|-------------|--------|--------|
| 1.3.0.1 | v1.3 | Tested |
| 1.4.0.0 Beta1 | v1.4 | Tested |
| 1.4.0.0 Beta2 | v1.4 | Tested |

If your version isn't listed and you see a warning dialog, please [open an issue](https://github.com/rittermod/FS25_RealisticLivestockRM/issues) so support can be added.

---

## Exotic Animals

Hof Bergmann adds several animal types beyond the base game. The mod gives most of these animals full RLRM treatment: individual tracking, genetics, breeding, lifecycle, aging, and diseases.

### What the Bridge Adds

For each exotic animal type, the mod adds **male subtypes** so that natural breeding is possible. Without the bridge, these types only have females that spontaniously reproduce.

| Animal Type | Subtypes Added | Breeding |
|-------------|---------------|----------|
| **Ducks** | Drake (male) | Ducks and drakes breed naturally |
| **Geese** | Gander (male) | Geese and ganders breed naturally |
| **Cats** | Tomcat (male) | Cats and tomcats breed naturally |
| **Rabbits** | *(male already exists)* | Breeding age corrected |
| **Alpacas** *(v1.4+)* | 4 male colour variants | Cross-colour breeding supported |
| **Quail** *(v1.4+)* | Male quail | Quail breed naturally |

All exotic animals can be bought, sold, bred, monitored, and managed through the livestock menu just like base game animals.

### Corrections Applied

The map's default animal data is derived from 3D model dimensions, which sometimes produces unrealistic values. The bridge corrects these:

| Animal | What's Corrected | Why |
|--------|-----------------|-----|
| **Geese** | Weight reduced from ~90 kg to 5-8 kg | Map derived weight from navigation mesh size, not real goose weight |
| **Rabbits** | Weight refined to 2.5-5.5 kg | Same navigation mesh issue |
| **Rabbits** | Male breeding age set to 6 months | Map default was 18 months; real rabbits mature at 3-4 months |
| **Cats** | Litter size increased to 3-6 kittens | Map default was 1-3; real cats have 3-5 per litter |
| **Geese** | Clutch size set to 3-6 eggs | Map default was 1-3 |
| **Rabbits** | Litter size increased to 4-8 kits | Map default was 1-3; real rabbits have 4-8 per litter |

---

## Known Limitations

### Pasture Bulls Are Not Cattle

Hof Bergmann adds a **BULL** animal type for decorative pasture bulls. These are **not the same** as the bull breeds in the cattle system (Holstein Bull, Angus Bull, etc.).

In the base game and in RLRM, cattle bulls are subtypes of the **COW** animal type. A Holstein Bull and a Holstein Cow are both "COW" internally — they share the same husbandry, the same breeding system, and the same lifecycle. This is what allows bulls and cows to breed with each other.

Hof Bergmann's pasture bull is a completely separate animal type called **BULL**. The game engine treats each animal type as isolated — animals of different types cannot interact, breed, or share husbandries. The pasture bull has its own husbandry building, its own slot system, and its own internal logic.

**Why it can't be "just fixed":** Merging HB's BULL type into the COW type would require rewriting the map's husbandry building assignments, pasture system, and animal slot management. This isn't a mod-side fix — it would need changes to the map itself. Alternatively, implementing cross-type breeding (letting a BULL-type animal breed with a COW-type animal) would be a fundamental new system in the game engine that doesn't exist.

**"Can't you just use the pasture bull models on cow-type bulls?"** This is a natural question. The base game doesn't include separate bull 3D models at all — RLRM's breeding bulls (Holstein Bull, Angus Bull, etc.) reuse the female cow models, so visually they look the same as cows. HB's pasture bulls have their own distinct bull visuals, which is exactly what you'd want on your breeding bulls.

Unfortunately, each animal type loads its own set of 3D models from the map's configuration — the COW type has one model pool, the BULL type has a completely separate one. To use HB's bull models on COW-type animals, you'd have to rebuild the map's entire animal model loading infrastructure from a script mod and apply it on top. This is extremely brittle: any map update can shift model indices, causing wrong or missing visuals.

The pasture bull still gets individual tracking, a name, and genetics — it just doesn't participate in the cattle breeding and reproduction system.

### Dogs Are Companion Animals

Hof Bergmann includes 8 dog breeds (4 Labrador variants, 4 Border Collie variants). In base FS25, dogs are companion animals with special behaviour.

RLRM tracks dogs as individuals with names and genetics, but does not add breeding or reproduction. Dogs remain companion animals that behave the same as in vanilla FS25.

---

## Related Pages

- [Breeding Guide](guide-breeding.md) - How breeding works for all supported animals
- [Genetics Guide](guide-genetics.md) - How traits are inherited
- [FAQ: Can you add more breeds?](faq.md#can-you-add-more-breeds-or-animal-types) - Why new breeds aren't created from scratch
- [FAQ: Why don't HB bulls breed like cattle?](faq.md#why-dont-hof-bergmann-pasture-bulls-breed-like-cattle) - More detail on the BULL vs COW limitation
