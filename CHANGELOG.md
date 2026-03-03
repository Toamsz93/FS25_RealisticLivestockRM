# Changelog

## v1.0.2.0-dev:
- Added genetics display in animal names (average score, or full breakdown per trait)
- Added sort by genetics option for animal lists
- Added selection count on bulk action buttons

## v1.0.1.1:
- Fixed compatibility with Hof Bergmann's subtype filter for animal pens

## v1.0.1.0:
- Add Hof Bergmann map support - exotic animals (ducks, geese, cats, rabbits) now support full breeding and reproduction
- Add basic support for butchers using Extended Production Point (EPP) mod
- Add missing translation keys across all languages
- Improve offspring subtype selection for maps with non-standard animal configurations
- Update Italian translation (contributed by FirenzeIT)
- Fix "Manage Animals" (R) key interfering with other mods' keybindings in different menu tabs
- Fix bulk move allowing more animals than target pen capacity
- Fix error when moving animals to Extended Production Points (EPP butchers)

## v1.0.0.0:
- Add "Manage Animals" (R) button to in-game animal menu for easier management
- Add "Select" (A) to check/uncheck selection boxes in buy and sell
- Disable insemination button when female is ineligible (pregnant, too young, recovering)
- Show "Removing..." state on monitor button when removal is pending
- Fix keybinding collisions in AnimalScreen - each action now has a unique key (D=Diseases, C=Castrate, M=Monitor, I=Insemination, X=Mark)
- Fix Mother/Father/Children info buttons intercepting Mark/Castrate keypresses - now mouse-only
- Fix insemination button showing on male animals
- Fix monitor visual not disappearing when removing monitor from animal
- Fix batch "Remove All Monitors" button not reflecting pending removal state
- Fix milk/wool/goat milk info not showing on dedicated server clients
- Protect GUI setup with pcall for dedicated server safety

## v0.6.1.0:
- Fix AI dialog insemination not syncing in multiplayer (AnimalAIDialog)
- Fix AI dialog insemination blocked for cows that never gave birth (missing isParent guard)
- Fix server crash when client inseminates cow with straw (AnimalInseminationEvent)
- Fix stream corruption in AI auto-insemination event (AIAnimalInseminationEvent)
- Fix pregnancy event silently failing to match animals on client (AnimalPregnancyEvent)
- Fix dewars bought mid-game not syncing to connected clients in multiplayer (SemenBuyEvent)
- Fix client-side error when buying semen in multiplayer (SemenBuyEvent)
- Fix disease treatment toggle not syncing to server in multiplayer (DiseaseDialog)
- Fix settings dependency check using undefined variable (RL_BroadcastSettingsEvent)
- Fixed error spam when dismounting horse outside pen in multiplayer
- Fix black screen when multiplayer client tries to ride a horse
- Fix multiplayer client unable to clean horses

## v0.6.0.0
- Add user guides and factsheets
- Add optional daily summary mode for message log to reduce noise on large farms (new setting: Message Log Summaries)
- Added "Reset AI Animals" button to settings to regenerate the AI straw catalog with new randomly generated animals
- Fix potential milk production loss that could occur when birth errors were silently caught
- Fix potential game freeze when selling animals with an active filter
- Fix potential mod errors blocking crop growth and other periodic game updates
- Fix texture warning for LED panel mask map
- Add Danish translation update and Chinese translation (community contributions)

## v0.5.0.0
- Randomize father selection during breeding - eligible males are now chosen randomly instead of always the first one
- Improve genetic inheritance with natural variation - offspring can now exceed or fall below parent trait values
- Fix wrong text shown for straw in monitor menu
- Detect conflicting mods (e.g., MoreVisualAnimals) and show a unified conflict dialog at startup
- Add Italian translation (community contribution by @FirenzeIT)

## v0.4.2.0
- Fix multiplayer sync issues when subTypeIndex differs between server/client (PR by killemth)
- Add fallback for days per month calculation during early load (PR by killemth)
- Refactor subType resolution into helper function with logging

## v0.4.1.0
- Fix crash caused by invalid animal root node in some cases.
- Fix death message count for auto-sold newborns
- Fix wrong text for when females can reproduce

## v0.4.0.0
- Remove Font Library dependency by inlining the required functionality directly in the mod.
- Refactor file loading and source folder.
- Update mod icon.

## v0.3.0.0
- Add Highland Bulls based on Renfordt's PR in 389 Arrow-kb's original mod.

## v0.2.0.0
- Migrate savegames from Arrow-kb's Realistic Livestock to RitterMod version. To avoid conflits with original mod and other forks of it, this mod uses a different mod ID. Therefore, when you load a savegame that used the original Realistic Livestock mod, you will be prompted to migrate the data to this mod.
