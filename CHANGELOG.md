# Changelog

## v1.2.0.1
- Fixed deprecated fillUnit warning in game log for semen dewar

## v1.2.0.0
- Rewrote semen dewar as a vehicle/pallet - fixes game freeze when looking at dewar, multiplayer pickup failures, and invisible dewars after mid-game purchase
- Dewar state (straws, bull genetics) now persists through save/load and object storage cycles
- Fixed crash in third-party mods that inspect stored pallets (e.g. Time Saving Stock Check) when a semen dewar is placed in object storage
- Fixed multiplayer desync: mark, castrate, monitor toggle, rename, and disease treatment changes from a client now sync to all other connected players
- Fixed all pre-existing animals getting the same identity (e.g. "UK 1 1") when installing RL on an existing save for the first time - also self-heals saves already affected
- Added Czech translation update (community contribution by Kynuska)
- Added Hungarian translation (community contribution by Toamsz93)
- Added missing translation keys across all 16 languages
- Fixed fillType errors in log when third-party selling station mods reference the ANIMAL category

### New RL Menu (preview - work in progress):
- Added new RL Menu (assign key in Settings -> Controls): a standalone tabbed menu. The legacy animal screen (R key) still works unchanged
- Messages tab: chronological message feed with single and bulk delete
- Info tab: husbandry selector, animal list with detail pane (pedigree, genetics, diseases, inputs/outputs), and action buttons (Mark, Monitor, Rename, Diseases, Inseminate, Castrate)
- Move tab: move animals between husbandries or to butchers with single-move and bulk-move using checkbox multi-select
- Status icons on animal list cards showing pregnancy, recovering, infertile/castrated, lactating, producing wool, and laying eggs at a glance

## v1.1.4.0
- Fixed horse breed visuals on Hof Bergmann: adult horses no longer display as foals, breed colors now match correctly, foal-to-adult model transition now works
- Fixed horse riding and equipment on Hof Bergmann v1.4: saddles, carriages, and tools from the Horse Addon Pack now attach correctly
- Disabled four horse breeds not natively supported by Hof Bergmann (Pinto, Chestnut, Bay, Dun) from the dealer - existing savegame horses of those breeds are unaffected
- Fixed dealer generating sale animals for breeds marked as not purchasable on the current map
- Fixed wool not spawning on Hof Bergmann v1.4: bridge now remaps WOOL to SHEEPWOOL_SHEARED to match HB's husbandry buildings
- Fixed chicken eggs not spawning on Hof Bergmann v1.4: bridge now remaps EGG to EGG_HB to match HB's husbandry buildings
- Fixed Hof Bergmann egg incubator failing to add hatched chicks to husbandry when RLRM is active
- Fixed crash when animal output curve returns nil, which could silently stop all production in a building
- Fixed bridge output overrides replacing valid production curves with empty ones when only the fillType needed remapping
- Fixed Hof Bergmann user guide with horse breed availability, riding notes, and wild duck clarification
- Added diagnostic logging for fillType mismatches in pallet and milk output

## v1.1.3.0
- Fixed bridge animals (rabbits, quail, etc.) getting duplicate IDs in multiplayer, causing animals to disappear on clients
- Fixed bridge animal ID counter, now tracks per-type counters with savegame persistence
- Fixed bulk buy silently failing when map husbandries reject animal breeds (e.g. Hereford in Hof Bergmann filtered pens)
- Existing saves with duplicate bridge animal IDs are automatically repaired on load
- Added pre-validation for bulk buy: shows which animals can't be purchased and why before confirming
- Added diagnostic logging for animal loading, breeding, and pack compatibility troubleshooting
- Added warnings when animals are lost due to removed packs or breed mismatches

## v1.1.2.0
- Added animal pack system: third-party mods can add breeds, override animal properties, or provide custom balance via rlrm_pack.xml
- Added Hof Bergmann 1.4 support with alpacas, quail, corrected chicken visuals, and version detection
- Added cross-color alpaca breeding (any male color can breed with any female color)
- Added user documentation for Hof Bergmann map support (exotic animals, known limitations, FAQ)
- Added: Exiting the RL animal screen returns to ingame menu animals tab when opened from there
- Added: RL animal screen opens on the Info tab by default when entered from ingame menu animals tab
- Fixed: Animal list scroll position jumping every 5 seconds in the ESC menu animals tab
- Fixed: Click sound playing every 5 seconds while viewing animal list
- Fixed: Crash when husbandry doesn't register a pallet or milk fillType that its animals produce
- Fixed: Animal model accumulation when maps redefine existing animal types
- Fixed: Base game reloads no longer clobber RLRM's superset animal configs
- Fixed: Random death money compensation (33% sell price) now correctly reaches farm balance
- Fixed: Bridge animal descriptions showing "Missing" in animal info dialog
- Fixed: Pig ear tag errors on Hof Bergmann maps
- Fixed: Sale animals of non-reproductive subtypes (e.g. bulls, dogs) could incorrectly become pregnant
- Fixed: Bridge animals' offspring could receive wrong breed when using non-standard subtype layout
- Fixed: Map-defined subtypes for existing animal types not loading alongside base game configs
- Improved Italian translation (community contribution)
- Improved German translation (community contribution)
- Internal refactoring: split Animal.lua into focused modules (reproduction, health, persistence, serialization)

## v1.1.1.0:
- Added version-aware map support: detects installed map version and loads the matching configuration
- Added warning dialog when an untested map version is detected (with link to report issues)
- Added breed and visual override support for map-based animal subtypes
- Fixed division-by-zero risk in horse riding fitness calculation at boundary threshold values
- Fixed horse riding value not being clamped (could accept values outside 0-100 range)
- Fixed male animals could theoretically become pregnant (missing gender guard in reproduction check)
- Fixed AI herdsman castrate notifications showing "marked for castrating" instead of "castrated" when in execute mode
- Fixed AI herdsman state tracking error after auto-buying animals
- Fixed BUM ID branding on cows showing all zeros and overlapping text

## v1.1.0.3:
- Fixed selected animal jumping to a different animal in the in-game animal menu

## v1.1.0.2:
- Fixed crash on Messages tab caused by unrecognized message IDs from older dev versions
- Invalid messages are now discarded on savegame load and handled gracefully in the UI

## v1.1.0.1:
- Fixed crash when moving animals between pens (nil subtraction on visual animal count)

## v1.1.0.0:
- Added Move tab for transferring animals between husbandries with destination picker and bulk move
- Added custom icons for all Animal Screen tabs
- Hidden castration tab in herdsman screen for chickens (not applicable)
- Fixed visual glitch in herdsman screen when enabling castration
- Internal refactoring for code quality and testability

## v1.0.2.0:
- Added genetics display in animal names (average score, or full breakdown per trait)
- Added sort by genetics option for animal lists
- Added selection count on bulk action buttons
- Fixed move messages in husbandry message log (were silently failing due to incorrect message keys)
- Fixed move messages showing wrong direction (to/from was swapped)
- Fixed typo in move message ("1 animals" → "1 animal")

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
