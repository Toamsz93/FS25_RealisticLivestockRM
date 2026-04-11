--[[
    RLAnimalQuery.lua
    Read-only query service for the RL Tabbed Menu Info tab:
      * list husbandries on a farm
      * list animals inside a husbandry, sorted + filtered
      * format one display row per animal
      * group sorted items into SmoothList sections
]]

RLAnimalQuery = {}

local Log = RmLogging.getLogger("RLRM")

-- =============================================================================
-- Husbandry list
-- =============================================================================

--- Return placeable husbandries owned by the given farm. Empty if farmId is nil or 0.
--- @param farmId number|nil
--- @return table husbandries
function RLAnimalQuery.listHusbandriesForFarm(farmId)
    if farmId == nil or farmId == 0 then return {} end

    if g_currentMission == nil or g_currentMission.husbandrySystem == nil then
        Log:warning("RLAnimalQuery.listHusbandriesForFarm: husbandrySystem unavailable")
        return {}
    end

    local placeables = g_currentMission.husbandrySystem:getPlaceablesByFarm(farmId)
    if placeables == nil then return {} end

    local result = {}
    for _, placeable in pairs(placeables) do
        table.insert(result, placeable)
    end

    Log:debug("RLAnimalQuery.listHusbandriesForFarm: farmId=%s -> %d husbandries",
        tostring(farmId), #result)
    return result
end

-- =============================================================================
-- Husbandry label
-- =============================================================================

--- Return the husbandry's display name, falling back to "Husbandry N" when empty.
--- @param husbandry table
--- @param fallbackIndex number
--- @return string
function RLAnimalQuery.formatHusbandryLabel(husbandry, fallbackIndex)
    if husbandry == nil then return "" end
    local name
    if husbandry.getName ~= nil then name = husbandry:getName() end
    if name == nil or name == "" then
        name = string.format("Husbandry %d", fallbackIndex or 0)
    end
    return name
end

-- =============================================================================
-- Animal list + sort + filter
-- =============================================================================

--- Wrap a cluster in an AnimalItemStock. Exposed as a field so unit tests can
--- swap in a lightweight stub without the full animalSystem lookups.
--- @param cluster table
--- @return table|nil
function RLAnimalQuery._wrapCluster(cluster)
    if AnimalItemStock == nil or AnimalItemStock.new == nil then return nil end
    return AnimalItemStock.new(cluster)
end

--- Return the sorted, filtered list of AnimalItemStock items for a husbandry.
--- Sorted via RL_AnimalScreenBase.sortAnimals (disease-first, then subType,
--- optional genetics, then age). Filtered via AnimalFilterDialog.applyFilters.
--- @param husbandry table
--- @param filters table|nil
--- @return table items
function RLAnimalQuery.listAnimalsForHusbandry(husbandry, filters)
    if husbandry == nil or husbandry.spec_husbandryAnimals == nil then return {} end

    local clusterSystem = husbandry.spec_husbandryAnimals
    if clusterSystem.getClusters == nil then
        Log:warning("RLAnimalQuery.listAnimalsForHusbandry: clusterSystem has no getClusters")
        return {}
    end

    local clusters = clusterSystem:getClusters()
    if clusters == nil then return {} end

    local items = {}
    for _, cluster in pairs(clusters) do
        local wrapped = RLAnimalQuery._wrapCluster(cluster)
        if wrapped ~= nil then
            table.insert(items, wrapped)
        end
    end

    -- Fail-fast if the shared comparator is missing. Unreachable in practice;
    -- main.lua load order puts AnimalScreenBase in SECTION 12 before rlmenu in 13b.
    if RL_AnimalScreenBase == nil or RL_AnimalScreenBase.sortAnimals == nil then
        Log:error("RLAnimalQuery.listAnimalsForHusbandry: RL_AnimalScreenBase.sortAnimals unavailable; returning empty")
        return {}
    end
    table.sort(items, RL_AnimalScreenBase.sortAnimals)

    if filters ~= nil and next(filters) ~= nil
        and AnimalFilterDialog ~= nil and AnimalFilterDialog.applyFilters ~= nil then
        items = AnimalFilterDialog.applyFilters(items, filters, false)
    end

    Log:debug("RLAnimalQuery.listAnimalsForHusbandry: husbandry='%s' items=%d filters=%s",
        (husbandry.getName ~= nil and husbandry:getName()) or "?",
        #items,
        (filters ~= nil and next(filters) ~= nil) and "yes" or "no")

    return items
end

-- =============================================================================
-- Row formatting
-- =============================================================================

RLAnimalQuery.TINT_NORMAL  = "normal"
RLAnimalQuery.TINT_DISEASE = "disease"
RLAnimalQuery.TINT_MARKED  = "marked"

--- Format an AnimalItemStock into a display-ready row for the frame layer.
---
--- Row schema:
---   uniqueId, farmId, country : selection identity (three-field animal id)
---   subTypeIndex              : section boundary key
---   icon                      : store image filename
---   baseName                  : raw cluster:getName(), empty = no custom name
---   identifier                : raw cluster:getIdentifiers()
---   displayName               : baseName with genetics tag applied
---   displayIdentifier         : identifier with genetics tag applied
---   price                     : sell price (setValue on the currency cell)
---   hasDisease, isMarked, recentlyBoughtByAI : state flags
---   descriptorVisible, descriptorText         : herdsman/mark badge
---   tint                      : "normal" | "disease" | "marked"
---
--- Malformed cluster returns a sentinel row with "?" placeholders + a warning.
--- @param item table|nil
--- @return table row
function RLAnimalQuery.formatAnimalRow(item)
    local row = {
        uniqueId           = 0,
        farmId             = 0,
        country            = "",
        subTypeIndex       = 0,
        icon               = nil,
        baseName           = "",
        identifier         = "",
        displayName        = "?",
        displayIdentifier  = "?",
        price              = 0,
        hasDisease         = false,
        isMarked           = false,
        recentlyBoughtByAI = false,
        descriptorVisible  = false,
        descriptorText     = "",
        tint               = RLAnimalQuery.TINT_NORMAL,
    }

    if item == nil or item.cluster == nil then
        Log:warning("RLAnimalQuery.formatAnimalRow: item or cluster missing")
        return row
    end

    local cluster = item.cluster

    row.uniqueId = cluster.uniqueId or 0
    row.farmId   = cluster.farmId or 0
    if cluster.birthday ~= nil then
        row.country = cluster.birthday.country or ""
    end
    row.subTypeIndex = (cluster.getSubTypeIndex ~= nil and cluster:getSubTypeIndex())
        or cluster.subTypeIndex or 0

    if item.getFilename ~= nil then
        row.icon = item:getFilename()
    end

    if cluster.getName ~= nil then
        row.baseName = cluster:getName() or ""
    end
    if cluster.getIdentifiers ~= nil then
        row.identifier = cluster:getIdentifiers() or ""
    end

    if RL_AnimalScreenBase ~= nil and RL_AnimalScreenBase.formatDisplayName ~= nil then
        row.displayName       = RL_AnimalScreenBase.formatDisplayName(row.baseName, cluster)
        row.displayIdentifier = RL_AnimalScreenBase.formatDisplayName(row.identifier, cluster)
    else
        row.displayName       = row.baseName
        row.displayIdentifier = row.identifier
    end

    if cluster.getSellPrice ~= nil then
        row.price = cluster:getSellPrice() or 0
    end

    if cluster.getHasAnyDisease ~= nil then
        row.hasDisease = cluster:getHasAnyDisease() == true
    end
    if cluster.getMarked ~= nil then
        row.isMarked = cluster:getMarked() == true
    end
    if cluster.getRecentlyBoughtByAI ~= nil then
        row.recentlyBoughtByAI = cluster:getRecentlyBoughtByAI() == true
    end

    -- Descriptor: recently-bought beats mark text when both are set.
    if row.recentlyBoughtByAI then
        row.descriptorVisible = true
        if g_i18n ~= nil then
            row.descriptorText = g_i18n:getText("rl_ui_herdsmanRecentlyBought")
        end
    elseif row.isMarked then
        row.descriptorVisible = true
        if cluster.getHighestPriorityMark ~= nil and RLConstants ~= nil and RLConstants.MARKS ~= nil then
            local markIndex = cluster:getHighestPriorityMark()
            local markEntry = markIndex ~= nil and RLConstants.MARKS[markIndex] or nil
            if markEntry ~= nil and markEntry.text ~= nil and g_i18n ~= nil then
                row.descriptorText = g_i18n:getText("rl_mark_" .. markEntry.text)
            end
        end
    end

    -- Tint: disease beats marked beats normal.
    if row.hasDisease then
        row.tint = RLAnimalQuery.TINT_DISEASE
    elseif row.isMarked then
        row.tint = RLAnimalQuery.TINT_MARKED
    end

    return row
end

-- =============================================================================
-- Section grouping (SmoothList multi-section data source)
-- =============================================================================

--- Group a sorted item list into sections:
---   1. Diseased Animals (if any diseased items exist, regardless of subType)
---   2. One section per distinct subType, in first-seen order
---
--- Returns three parallel tables:
---   sectionOrder[]  : opaque section keys in display order
---   itemsBySection  : section key -> items array
---   titlesBySection : section key -> localized title string
---
--- Pure function on the items array; no mutation of the input.
--- @param items table
--- @return table sectionOrder, table itemsBySection, table titlesBySection
function RLAnimalQuery.buildSections(items)
    local sectionOrder    = {}
    local itemsBySection  = {}
    local titlesBySection = {}

    if items == nil or #items == 0 then
        return sectionOrder, itemsBySection, titlesBySection
    end

    local DISEASED_KEY = "__diseased__"

    for _, item in ipairs(items) do
        local cluster = item.cluster
        if cluster ~= nil then
            local isDiseased = cluster.getHasAnyDisease ~= nil and cluster:getHasAnyDisease() == true
            local key, title

            if isDiseased then
                key = DISEASED_KEY
                title = (g_i18n ~= nil) and g_i18n:getText("rl_ui_diseasedAnimals") or "Diseased Animals"
            else
                key = "subtype_" .. tostring(cluster.subTypeIndex or 0)
                -- Prefer wrapper's cached title; fall back to animalSystem lookup
                -- so test stubs with minimal item tables still produce something.
                title = item.title
                if (title == nil or title == "") and g_currentMission ~= nil
                    and g_currentMission.animalSystem ~= nil then
                    local subType = g_currentMission.animalSystem:getSubTypeByIndex(cluster.subTypeIndex)
                    if subType ~= nil and subType.fillTypeIndex ~= nil and g_fillTypeManager ~= nil then
                        title = g_fillTypeManager:getFillTypeTitleByIndex(subType.fillTypeIndex)
                    end
                end
                if title == nil or title == "" then title = "?" end
            end

            if itemsBySection[key] == nil then
                table.insert(sectionOrder, key)
                itemsBySection[key] = {}
                titlesBySection[key] = title
            end
            table.insert(itemsBySection[key], item)
        end
    end

    return sectionOrder, itemsBySection, titlesBySection
end

--- Find (section, index) for an item by stable animal identity.
--- @param sectionOrder table
--- @param itemsBySection table
--- @param farmId number|nil
--- @param uniqueId number|nil
--- @param country string|nil
--- @return number|nil section, number|nil indexInSection
function RLAnimalQuery.findSectionedItemByIdentity(sectionOrder, itemsBySection, farmId, uniqueId, country)
    if sectionOrder == nil or itemsBySection == nil
        or farmId == nil or uniqueId == nil then
        return nil, nil
    end

    for sectionIdx, key in ipairs(sectionOrder) do
        local list = itemsBySection[key]
        if list ~= nil then
            for i = 1, #list do
                local cluster = list[i] ~= nil and list[i].cluster or nil
                if cluster ~= nil
                    and cluster.farmId == farmId
                    and cluster.uniqueId == uniqueId then
                    local clusterCountry = cluster.birthday ~= nil and cluster.birthday.country or nil
                    if country == nil or clusterCountry == country then
                        return sectionIdx, i
                    end
                end
            end
        end
    end

    return nil, nil
end
