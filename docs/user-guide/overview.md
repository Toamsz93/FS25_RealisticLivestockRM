# Realistic Livestock RM - Overview

Realistic Livestock RM transforms the animal system in Farming Simulator 25. Instead of anonymous clusters, every animal is a unique individual with its own genetics, health history, and lifecycle.

> **Note:** This documentation was generated with AI assistance and may contain inaccuracies. If you spot an error, please [open an issue](https://github.com/rittermod/FS25_RealisticLivestockRM/issues).

---

## What Changes

### Every Animal Is Unique

Each animal you buy or breed is tracked individually. They have a name tag, a birthday, and five genetic traits that make them different from every other animal in your herd. Two Holstein cows bought on the same day will produce different amounts of milk, eat different amounts of food, and sell for different prices.

### Genetics

Every animal is born with five genetic traits rated from Extremely Low to Extremely High:

- **Health** - Disease resistance and longevity
- **Fertility** - Breeding success rate
- **Productivity** - Milk, egg, and wool output (cows, sheep, goats, chickens only)
- **Quality** - Sell price and meat value
- **Metabolism** - Food consumption and weight gain

Offspring inherit traits from their parents, so selective breeding pays off over time. Most animals you encounter will be average, but occasionally you'll find an exceptional one - or a dud.

See the [Genetics Guide](guide-genetics.md) for the full rating scale and breeding tips.

### Realistic Breeding

Reproduction requires a male and female of the same species in the same pen. Each species has different breeding ages, gestation periods, and litter sizes:

| Animal | Gestation | Typical Offspring |
|--------|-----------|-------------------|
| Cattle | 10 months | 1 calf (twins rare) |
| Pigs | 4 months | 11-13 piglets |
| Sheep / Goats | 5 months | 1-2 lambs |
| Horses | 11 months | 1 foal |
| Chickens | 2 months | 1-12 chicks |

Males and females have different fertility windows - boars retire from breeding at just 4 years while sows can breed until 8 years. Cows lactate for 10 months after giving birth, during which they produce milk but need more food and water.

**Artificial Insemination** is available through the livestock menu if you don't want to keep a male.

See the [Breeding Guide](guide-breeding.md) for full details per species.

### Animal Management

Individual animals can be monitored, marked, and castrated:

- **Monitoring** - Place monitors on animals to track their stats over time. View active monitors in the livestock menu.
- **Marking** - Mark animals for visual identification in your herd
- **Castration** - Castrate males for a small sell price bonus. Castrated animals grow faster but cannot breed.

### Diseases

Five diseases can affect your animals:

| Disease | Affects | Treatable? | Key Impact |
|---------|---------|------------|------------|
| Mastitis | Cows, Sheep, Goats | Yes | Stops milk and wool production |
| CVM | Cattle (genetic) | No | Carrier cows produce extra milk, but calves may die |
| Foot & Mouth | Cows, Sheep, Pigs | Yes (slow) | Major milk and price reduction |
| PED | Pigs | Yes | Devastating to newborn piglets |
| Avian Influenza | Chickens | No | Stops all egg production |

Diseases can spread between animals in the same pen. Some diseases grant immunity after recovery.

See the [Disease Guide](guide-diseases.md) for prevention and treatment strategies.

### Death

Animals can die from three causes:

- **Old age** - Each species has a natural lifespan (chickens ~5-8 years, horses ~25-30 years)
- **Low health** - Unhealthy animals face increasing death risk
- **Accidents** - Random events affected by weather conditions

Death mechanics can be fully disabled or adjusted in the mod settings.

### Configurable Settings

Almost everything can be tuned to your preference:

- Toggle death and diseases on/off
- Scale food consumption up or down
- Adjust accident and disease probability
- Control dealer stock size
- Customise ear tag colours
- Display genetics values in animal names (short or detailed format)
- Export animal data to CSV
- Choose between individual event messages or daily summaries

See the [Settings Reference](reference-settings.md) for all options.

### Livestock Menu

Press **R** in the animal menu to open the animal screen. It has seven tabs:

- **Buy** - Purchase animals from the dealer with full genetics preview
- **Sell** - Sell animals back to the dealer
- **Move** - Transfer animals between your husbandries
- **Animal Information** - View detailed stats, genetics, health, and production for each animal
- **Insemination** - Browse and buy stored semen for artificial breeding without keeping males
- **Message Log** - Track births, deaths, diseases, and other events
- **Herdsman** - Automate herd management: auto-buy, auto-sell, castration rules, naming conventions, and auto-insemination. Save and load automation profiles.

### Controls

| Key | Action | Where |
|-----|--------|-------|
| **R** | Open Manage Animals | Animal menu |
| **A** | Select / deselect | Buy and sell dialogs |
| **Shift + T** | Toggle 3D name tags | In-game |
| **X** | Mark animal | Animal detail view |
| **M** | Toggle monitor | Animal detail view |
| **I** | Insemination | Animal detail view (females only) |
| **C** | Castrate | Animal detail view (males only) |
| **D** | Disease treatment | Animal detail view |

*All keybindings can be remapped in the game's input settings.*

### Map & Mod Support

The mod includes built-in support for third-party maps that add exotic animal types. When you load a supported map, the mod automatically detects the installed map version and loads the matching configuration for full breeding and reproduction.

- **[Hof Bergmann](map-hof-bergmann.md)** - Ducks, geese, cats, rabbits, alpacas, and quail fully supported with breeding, genetics, and reproduction. See the [dedicated page](map-hof-bergmann.md) for supported versions and known limitations (pasture bulls, dogs).

If a map updates to a version that hasn't been tested yet, you'll see a warning dialog when the game starts. The dialog includes a link to report any problems.

- **Extended Production Point (EPP)** - Basic support for moving animals to EPP butchers

*Looking for more breeds or animal types? See the [FAQ](faq.md#can-you-add-more-breeds-or-animal-types) for what's possible.*

---

## Species Factsheets

Each species has a detailed factsheet with breed comparisons, production ranges, and pricing:

- [Cattle Factsheet](factsheet-cattle.md) - 7 breeds from dairy Holsteins to beef Angus
- [Pigs Factsheet](factsheet-pigs.md) - 3 breeds with massive litter sizes
- [Sheep & Goats Factsheet](factsheet-sheep.md) - 4 sheep breeds + goats
- [Horses Factsheet](factsheet-horses.md) - 8 colour variants
- [Chickens Factsheet](factsheet-chickens.md) - Hens and roosters

## Guides

- [Genetics Guide](guide-genetics.md) - Trait ratings, breeding strategy, the CVM dilemma
- [Disease Guide](guide-diseases.md) - Prevention, treatment, and immunity
- [Breeding Guide](guide-breeding.md) - Fertility windows, offspring tables, lactation
- [Hof Bergmann Map Support](map-hof-bergmann.md) - Exotic animals, supported versions, known limitations
- [Settings Reference](reference-settings.md) - Every configurable option explained
- [FAQ](faq.md) - Common questions about genetics inheritance, breeding, and more
