--[[
    RLMapBridge.lua
    Map bridge system for RealisticLivestockRM.

    Detects supported maps and loads additional animal data (male subtypes, fill types)
    to enable full RLRM reproduction for exotic animal types defined by those maps.

    The bridge files are bundled inside RLRM at xml/bridge/<modName>/.
    No user configuration needed - detection is automatic via g_modIsLoaded.
]]

RLMapBridge = {}

local Log = RmLogging.getLogger("RLRM")
local modDirectory = g_currentModDirectory
local modName = g_currentModName

--- Registry of supported maps with bridge data.
--- Each entry: { modName = "FS25_...", basePath = "mod_support/...", name = "Human-readable name" }
--- At runtime, version resolution adds: resolvedConfigPath, resolvedConfigId, versionStatus
RLMapBridge.SUPPORTED_MAPS = {
    {
        modName = "FS25_HofBergmann",
        basePath = "mod_support/FS25_HofBergmann/",
        name = "Hof Bergmann"
    }
}

--- Tracks which bridges were activated (for logging/diagnostics)
RLMapBridge.activeBridges = {}

--- Queued warning text to display via InfoDialog in onStartMission (nil = no warning)
RLMapBridge.pendingVersionWarning = nil

--- Breeding group data: subTypeName -> groupName
RLMapBridge.breedingGroupBySubType = {}

--- Breeding group max fertility ages: groupName -> maxFertilityAge (months)
RLMapBridge.maxFertilityAgeByGroup = {}


--- Parse a version string into a numeric tuple.
--- @param versionStr string|nil Version string (e.g. "1.3.0.1")
--- @return table|nil versionTuple Array of numbers (e.g. {1, 3, 0, 1}), or nil if input is nil
function RLMapBridge.parseVersion(versionStr)
    if versionStr == nil then
        return nil
    end

    local parts = string.split(versionStr, ".")
    local tuple = {}
    for _, part in ipairs(parts) do
        local num = tonumber(part)
        if num == nil then
            Log:warning("MapBridge: Non-numeric version component '%s' in '%s'", part, versionStr)
            return nil
        end
        table.insert(tuple, num)
    end

    return tuple
end


--- Compare two version tuples component by component.
--- Treats missing components as 0 (e.g. {1,3} == {1,3,0,0}).
--- @param a table Version tuple (e.g. {1, 3, 0, 1})
--- @param b table Version tuple (e.g. {1, 4, 0, 0})
--- @return number result Negative if a < b, 0 if equal, positive if a > b
function RLMapBridge.compareVersions(a, b)
    local maxLen = math.max(#a, #b)
    for i = 1, maxLen do
        local ai = a[i] or 0
        local bi = b[i] or 0
        if ai ~= bi then
            return ai - bi
        end
    end
    return 0
end


--- Resolve which bridge config to use for a detected map version.
--- Three-step algorithm:
---   1. Exact match: mapVersion is in a config's supportedVersions list → "confirmed"
---   2. Closest lower: highest config whose max confirmed version ≤ mapVersion → "unknown"
---   3. Lowest overall: if nothing ≤ mapVersion, use the config with the lowest min version → "unknown"
--- Nil mapVersion is treated as oldest possible (goes to step 3).
--- @param mapVersion string|nil Detected map version string (e.g. "1.3.0.1")
--- @param configs table Array of config tables from loadBridgeXml, each with:
---   id (string), path (string), supportedVersions (array of version strings)
--- @return table|nil config The selected config table, or nil if configs is empty
--- @return string status "confirmed" or "unknown"
function RLMapBridge.resolveVersionConfig(mapVersion, configs)
    if configs == nil or #configs == 0 then
        return nil, "unknown"
    end

    local mapTuple = RLMapBridge.parseVersion(mapVersion)
    Log:trace("MapBridge: resolveVersionConfig: mapVersion=%s, %d config(s)", tostring(mapVersion), #configs)

    -- Pre-parse all config version tuples and track min/max per config
    local configData = {}
    for _, config in ipairs(configs) do
        local parsedVersions = {}
        local minVersion = nil
        local maxVersion = nil

        for _, verStr in ipairs(config.supportedVersions) do
            local tuple = RLMapBridge.parseVersion(verStr)
            if tuple ~= nil then
                table.insert(parsedVersions, { str = verStr, tuple = tuple })

                if minVersion == nil or RLMapBridge.compareVersions(tuple, minVersion) < 0 then
                    minVersion = tuple
                end
                if maxVersion == nil or RLMapBridge.compareVersions(tuple, maxVersion) > 0 then
                    maxVersion = tuple
                end
            end
        end

        table.insert(configData, {
            config = config,
            parsedVersions = parsedVersions,
            minVersion = minVersion,
            maxVersion = maxVersion
        })
    end

    -- Step 1: Exact match
    if mapTuple ~= nil then
        for _, cd in ipairs(configData) do
            for _, pv in ipairs(cd.parsedVersions) do
                if RLMapBridge.compareVersions(mapTuple, pv.tuple) == 0 then
                    Log:trace("MapBridge: resolveVersionConfig: exact match -> config '%s'", cd.config.id)
                    return cd.config, "confirmed"
                end
            end
        end
    end

    -- Step 2: Highest config whose max confirmed version ≤ mapVersion
    if mapTuple ~= nil then
        local bestConfig = nil
        local bestMaxVersion = nil

        for _, cd in ipairs(configData) do
            if cd.maxVersion ~= nil and RLMapBridge.compareVersions(cd.maxVersion, mapTuple) <= 0 then
                if bestMaxVersion == nil or RLMapBridge.compareVersions(cd.maxVersion, bestMaxVersion) > 0 then
                    bestConfig = cd
                    bestMaxVersion = cd.maxVersion
                end
            end
        end

        if bestConfig ~= nil then
            Log:trace("MapBridge: resolveVersionConfig: closest lower -> config '%s'", bestConfig.config.id)
            return bestConfig.config, "unknown"
        end
    end

    -- Step 3: Nothing ≤ mapVersion (or nil mapVersion) - use lowest min version config
    local lowestConfig = nil
    local lowestMinVersion = nil

    for _, cd in ipairs(configData) do
        if cd.minVersion ~= nil then
            if lowestMinVersion == nil or RLMapBridge.compareVersions(cd.minVersion, lowestMinVersion) < 0 then
                lowestConfig = cd
                lowestMinVersion = cd.minVersion
            end
        end
    end

    if lowestConfig ~= nil then
        Log:trace("MapBridge: resolveVersionConfig: lowest overall -> config '%s'", lowestConfig.config.id)
        return lowestConfig.config, "unknown"
    end

    -- Fallback: return first config if somehow none had parseable versions
    Log:warning("MapBridge: resolveVersionConfig: no parseable versions in any config, using first")
    return configs[1], "unknown"
end


--- Load and parse a bridge.xml configuration file for version-aware config resolution.
--- Returns an array of config tables, each containing an id, path, and list of supported versions.
--- Second return value indicates whether the file was found (distinguishes "no file" from "malformed").
--- @param bridgeXmlPath string Absolute path to bridge.xml
--- @return table|nil configs Array of { id=string, path=string, supportedVersions={string...} }, or nil
--- @return boolean fileFound True if bridge.xml exists (even if parsing failed)
function RLMapBridge.loadBridgeXml(bridgeXmlPath)
    local xmlFile = XMLFile.loadIfExists("RLMapBridge", bridgeXmlPath)
    if xmlFile == nil then
        Log:trace("MapBridge: No bridge.xml at '%s', using legacy mode", bridgeXmlPath)
        return nil, false
    end

    local configs = {}

    for _, configKey in xmlFile:iterator("bridge.configs.config") do
        local id = xmlFile:getString(configKey .. "#id")
        local path = xmlFile:getString(configKey .. "#path")

        if id == nil or path == nil then
            Log:warning("MapBridge: bridge.xml config entry missing 'id' or 'path' attribute, bridge.xml is malformed")
            xmlFile:delete()
            return nil, true
        end

        local supportedVersions = {}
        for _, versionKey in xmlFile:iterator(configKey .. ".supportedVersions.version") do
            local value = xmlFile:getString(versionKey .. "#value")
            if value ~= nil then
                table.insert(supportedVersions, value)
            end
        end

        if #supportedVersions == 0 then
            Log:warning("MapBridge: bridge.xml config '%s' has no supported versions, bridge.xml is malformed", id)
            xmlFile:delete()
            return nil, true
        end

        table.insert(configs, {
            id = id,
            path = path,
            supportedVersions = supportedVersions
        })

        Log:trace("MapBridge: bridge.xml config '%s' path='%s' versions=%s",
            id, path, table.concat(supportedVersions, ", "))
    end

    xmlFile:delete()

    if #configs == 0 then
        Log:warning("MapBridge: bridge.xml has no config entries, bridge.xml is malformed")
        return nil, true
    end

    Log:debug("MapBridge: Parsed bridge.xml: %d config(s)", #configs)
    return configs, true
end


--- Load bridge translations for a detected map.
--- Tries current language first, falls back to English, then German.
--- Uses the same XML format as modDesc l10n files: <l10n><texts><text name="..." text="..."/></texts></l10n>
---
--- Translations must be set in the GLOBAL I18N texts table (not the mod proxy)
--- because $l10n_ keys for animal visual data resolve using the map's mod name,
--- not RLRM's mod name, so the mod proxy table is never consulted.
---@param bridge table Bridge entry from SUPPORTED_MAPS
function RLMapBridge.loadBridgeTranslations(bridge)
    local translationsDir = modDirectory .. bridge.resolvedConfigPath .. "translations/translation"

    local xmlFile = nil
    for _, lang in ipairs({ g_languageShort, "en", "de" }) do
        local path = translationsDir .. "_" .. lang .. ".xml"
        if fileExists(path) then
            xmlFile = XMLFile.load("bridgeL10n", path)
            if xmlFile ~= nil then
                Log:info("MapBridge: Loading translations for '%s' (lang=%s)", bridge.name, lang)
                break
            end
        end
    end

    if xmlFile == nil then
        Log:warning("MapBridge: No translation files found for '%s'", bridge.name)
        return
    end

    -- Write to the GLOBAL I18N instance (_G.g_i18n), not the mod proxy (g_i18n).
    -- The mod proxy only stores texts under this mod's name, but $l10n_ keys
    -- for animal visual data resolve under the map mod's name, so they only
    -- find texts in the global table.
    local count = 0
    for _, key in xmlFile:iterator("l10n.texts.text") do
        local name = xmlFile:getString(key .. "#name")
        local text = xmlFile:getString(key .. "#text")

        if name ~= nil and text ~= nil then
            _G.g_i18n.texts[name] = text
            count = count + 1
        end
    end

    xmlFile:delete()
    Log:info("MapBridge: Loaded %d translation(s) for '%s'", count, bridge.name)
end


--- Load bridge metadata from metadata.xml.
--- Reads map-level settings (area code, etc.) and stores them on the bridge entry.
---@param bridge table Bridge entry from SUPPORTED_MAPS
function RLMapBridge.loadBridgeMetadata(bridge)
    local metadataPath = modDirectory .. bridge.resolvedConfigPath .. "metadata.xml"
    local xmlFile = XMLFile.load("bridgeMetadata", metadataPath)

    if xmlFile == nil then
        Log:debug("MapBridge: No metadata.xml found for '%s', skipping", bridge.name)
        return
    end

    bridge.metadata = {}

    local areaCode = xmlFile:getInt("metadata.map#areaCode")
    if areaCode ~= nil then
        bridge.metadata.areaCode = areaCode
        Log:info("MapBridge: '%s' area code set to %d", bridge.name, areaCode)
    end

    xmlFile:delete()
end


--- Return the map area code from an active bridge, or nil if none set.
---@return integer|nil areaCode Area code index, or nil
function RLMapBridge.getMapAreaCode()
    for _, bridge in ipairs(RLMapBridge.activeBridges) do
        if bridge.metadata ~= nil and bridge.metadata.areaCode ~= nil then
            return bridge.metadata.areaCode
        end
    end
    return nil
end


--- Load bridge fill types for detected maps.
--- Called from RealisticLivestock_FillTypeManager.loadFillTypes (appended to FillTypeManager.loadMapData).
--- Must run BEFORE AnimalSystem.loadMapData so fill types are available for subtype registration.
function RLMapBridge.loadBridgeFillTypes()
    Log:info("MapBridge: Scanning for supported maps...")

    if g_modIsLoaded == nil then
        Log:info("MapBridge: g_modIsLoaded not available, skipping bridge fill type loading")
        return
    end

    for _, bridge in ipairs(RLMapBridge.SUPPORTED_MAPS) do
        Log:info("MapBridge: Checking for '%s' (%s)...", bridge.name, bridge.modName)

        if g_modIsLoaded[bridge.modName] then
            Log:info("MapBridge: '%s' DETECTED - resolving version config", bridge.name)

            -- Version resolution: parse bridge.xml and resolve config path
            local configs, bridgeXmlFound = RLMapBridge.loadBridgeXml(modDirectory .. bridge.basePath .. "bridge.xml")

            if configs == nil and bridgeXmlFound then
                -- bridge.xml exists but is malformed - skip this bridge entirely
                -- (config files are in version subdirectories, basePath root has no files)
                Log:error("MapBridge: bridge.xml for '%s' is malformed, skipping bridge", bridge.name)
            elseif configs ~= nil then
                -- Get installed map version
                local mapMod = g_modManager:getModByName(bridge.modName)
                local mapVersion = mapMod and mapMod.version
                Log:debug("MapBridge: '%s' installed version: %s", bridge.name, tostring(mapVersion))

                local config, status = RLMapBridge.resolveVersionConfig(mapVersion, configs)

                if config ~= nil then
                    bridge.resolvedConfigPath = bridge.basePath .. config.path
                    bridge.resolvedConfigId = config.id
                    bridge.versionStatus = status

                    Log:info("MapBridge: %s v%s -> config '%s' (%s)",
                        bridge.name, tostring(mapVersion), config.id, status)

                    if status == "unknown" then
                        local rlrmMod = g_modManager:getModByName(modName)
                        local rlrmVersion = rlrmMod and rlrmMod.version or "?"
                        local warningText = string.format(
                            g_i18n:getText("rl_bridge_version_unknown"),
                            bridge.name,
                            tostring(mapVersion),
                            rlrmVersion,
                            config.id,
                            "https://github.com/rittermod/FS25_RealisticLivestockRM/issues"
                        )
                        Log:warning("MapBridge: %s", warningText)
                        RLMapBridge.pendingVersionWarning = warningText
                    end
                else
                    -- Should not happen with valid configs, but guard defensively
                    Log:error("MapBridge: Version resolution returned nil for '%s', skipping bridge", bridge.name)
                end
            else
                -- Legacy mode: no bridge.xml, use basePath directly
                bridge.resolvedConfigPath = bridge.basePath
                bridge.resolvedConfigId = nil
                bridge.versionStatus = "legacy"
                Log:info("MapBridge: '%s' using legacy mode (no bridge.xml)", bridge.name)
            end

            -- Only proceed with loading if version resolution succeeded
            if bridge.resolvedConfigPath ~= nil then
                -- Load bridge metadata and translations BEFORE fill types (fill type names reference l10n keys)
                RLMapBridge.loadBridgeMetadata(bridge)
                RLMapBridge.loadBridgeTranslations(bridge)

                local fillTypesPath = modDirectory .. bridge.resolvedConfigPath .. "fillTypes.xml"
                Log:debug("MapBridge: Fill types path: '%s'", fillTypesPath)

                local xml = loadXMLFile("bridgeFillTypes", fillTypesPath)

                if xml ~= nil then
                    g_fillTypeManager:loadFillTypes(xml, modDirectory, false, modName)
                    Log:info("MapBridge: Fill types loaded successfully for '%s'", bridge.name)

                    table.insert(RLMapBridge.activeBridges, bridge)
                else
                    Log:warning("MapBridge: Failed to load fill types XML at '%s'", fillTypesPath)
                end
            end
        else
            Log:info("MapBridge: '%s' not loaded, skipping", bridge.name)
        end
    end

    Log:info("MapBridge: Fill type scan complete. %d bridge(s) activated.", #RLMapBridge.activeBridges)
end


--- Load bridge animal subtypes for detected maps.
--- Called from RealisticLivestock_AnimalSystem.loadMapData after Phase 2 (map animals).
--- Only adds subtypes to EXISTING types (does not create new types).
---@param animalSystem table The AnimalSystem instance
function RLMapBridge.loadBridgeAnimals(animalSystem)
    if #RLMapBridge.activeBridges == 0 then
        Log:info("MapBridge: No active bridges, skipping animal loading")
        return
    end

    for _, bridge in ipairs(RLMapBridge.activeBridges) do
        Log:info("MapBridge: Loading bridge animals for '%s'...", bridge.name)

        -- Resolve the map mod's directory for image path resolution
        local mapModDir = g_modNameToDirectory[bridge.modName]
        if mapModDir == nil then
            Log:warning("MapBridge: Could not resolve mod directory for '%s', using RLRM directory", bridge.modName)
            mapModDir = modDirectory
        end

        local animalsPath = modDirectory .. bridge.resolvedConfigPath .. "animals.xml"
        Log:debug("MapBridge: Animals path: '%s', image base dir: '%s'", animalsPath, mapModDir)

        local xmlFile = XMLFile.load("bridgeAnimals", animalsPath)

        if xmlFile == nil then
            Log:warning("MapBridge: Failed to load animals XML at '%s'", animalsPath)
        else
            -- Apply config overrides BEFORE loading subtypes so C++ has correct model configs
            RLMapBridge.loadConfigOverrides(animalSystem, xmlFile, mapModDir, bridge.name)

            local subtypesAdded = 0
            local subtypesSkipped = 0

            for _, key in xmlFile:iterator("animals.animal") do
                local rawTypeName = xmlFile:getString(key .. "#type")

                if rawTypeName == nil then
                    Log:warning("MapBridge: Missing type attribute on animal entry, skipping")
                elseif animalSystem.nameToType[rawTypeName:upper()] == nil then
                    Log:warning("MapBridge: Type '%s' not found in AnimalSystem - was the map's animals.xml loaded? Skipping.", rawTypeName:upper())
                else
                    local typeName = rawTypeName:upper()
                    local animalType = animalSystem.nameToType[typeName]

                    Log:info("MapBridge: Processing bridge entry for type '%s' (typeIndex=%d, %d existing subTypes)",
                        typeName, animalType.typeIndex, #animalType.subTypes)

                    -- Count subtypes before loading
                    local beforeCount = #animalSystem.subTypes

                    local success = animalSystem:loadSubTypes(animalType, xmlFile, key, mapModDir)

                    local afterCount = #animalSystem.subTypes
                    local added = afterCount - beforeCount

                    if success and added > 0 then
                        subtypesAdded = subtypesAdded + added
                        Log:info("MapBridge: Added %d subtype(s) to '%s'", added, typeName)

                        -- Log details of each new subtype
                        for i = beforeCount + 1, afterCount do
                            local st = animalSystem.subTypes[i]
                            if st ~= nil then
                                Log:info("MapBridge:   -> SubType '%s' (index=%d, gender=%s, breed=%s, fillType=%s)",
                                    st.name, st.subTypeIndex, st.gender or "?", st.breed or "?",
                                    g_fillTypeManager:getFillTypeNameByIndex(st.fillTypeIndex) or "?")
                            end
                        end
                    elseif added == 0 then
                        subtypesSkipped = subtypesSkipped + 1
                        Log:info("MapBridge: No new subtypes added for '%s' (all may have been duplicates)", typeName)
                    else
                        Log:warning("MapBridge: loadSubTypes returned false for type '%s'", typeName)
                    end
                end
            end

            -- Apply property overrides on existing types and subtypes
            RLMapBridge.applyPropertyOverrides(animalSystem, xmlFile, bridge.name, mapModDir)

            -- Load breeding groups
            RLMapBridge.loadBreedingGroups(xmlFile, bridge.name)

            xmlFile:delete()
            Log:info("MapBridge: Bridge loading complete for '%s': %d subtypes added, %d type entries with no new subtypes",
                bridge.name, subtypesAdded, subtypesSkipped)
        end
    end
end


--- Load breeding groups from bridge XML.
--- Groups define which subtypes can exclusively breed with each other (same-group only).
---@param xmlFile table XMLFile handle
---@param bridgeName string Human-readable bridge name for logging
function RLMapBridge.loadBreedingGroups(xmlFile, bridgeName)
    local groupCount = 0

    for _, key in xmlFile:iterator("animals.breedingGroups.group") do
        local groupName = xmlFile:getString(key .. "#name")
        local maxFertilityAge = xmlFile:getInt(key .. "#maxFertilityAge")

        if groupName == nil then
            Log:warning("MapBridge: Breeding group missing 'name' attribute, skipping")
        else
            groupName = groupName:upper()

            if maxFertilityAge ~= nil then
                RLMapBridge.maxFertilityAgeByGroup[groupName] = maxFertilityAge
                Log:info("MapBridge: Breeding group '%s' maxFertilityAge=%d months", groupName, maxFertilityAge)
            end

            for _, stKey in xmlFile:iterator(key .. ".subType") do
                local stName = xmlFile:getString(stKey .. "#name")

                if stName ~= nil then
                    stName = stName:upper()
                    RLMapBridge.breedingGroupBySubType[stName] = groupName
                    Log:info("MapBridge: SubType '%s' -> breeding group '%s'", stName, groupName)
                end
            end

            groupCount = groupCount + 1
        end
    end

    if groupCount > 0 then
        Log:info("MapBridge: Loaded %d breeding group(s) for '%s'", groupCount, bridgeName)
    end
end


--- Apply config overrides from bridge XML.
--- Updates animalType.configFilename for types where the map's 3D model config
--- has additional models beyond the base game config. Without this, the C++ engine
--- only loads base game models and map-specific visual indices cause
--- "invalid animal subtype" errors.
---@param animalSystem table The AnimalSystem instance
---@param xmlFile table XMLFile handle
---@param mapModDir string Map mod directory for resolving relative config paths
---@param bridgeName string Human-readable bridge name for logging
function RLMapBridge.loadConfigOverrides(animalSystem, xmlFile, mapModDir, bridgeName)
    local overrideCount = 0

    for _, key in xmlFile:iterator("animals.configOverrides.override") do
        local rawTypeName = xmlFile:getString(key .. "#type")
        local rawConfigFilename = xmlFile:getString(key .. "#configFilename")

        if rawTypeName == nil or rawConfigFilename == nil then
            Log:warning("MapBridge: Config override missing 'type' or 'configFilename' attribute, skipping")
        else
            local typeName = rawTypeName:upper()
            local animalType = animalSystem.nameToType[typeName]

            if animalType == nil then
                Log:warning("MapBridge: Config override type '%s' not found in AnimalSystem, skipping", typeName)
            else
                local resolvedPath = Utils.getFilename(rawConfigFilename, mapModDir)
                local oldPath = animalType.configFilename

                animalType.configFilename = resolvedPath
                overrideCount = overrideCount + 1

                Log:info("MapBridge: Config override for '%s': '%s' -> '%s'", typeName, oldPath, resolvedPath)
            end
        end
    end

    if overrideCount > 0 then
        Log:info("MapBridge: Applied %d config override(s) for '%s'", overrideCount, bridgeName)
    end
end


--- Apply property overrides from bridge XML to existing types and subtypes.
--- Reads the same XML structure as loadAnimals/loadSubTypes, but instead of creating
--- new entries, patches properties on objects that already exist. This enables the
--- bridge to act as a "cascade layer" - any property defined in the bridge XML
--- overrides the value set by earlier layers (base game, RLRM, map).
---
--- Called AFTER loadSubTypes (which adds new subtypes), so both new and existing
--- subtypes are available for patching.
---@param animalSystem table The AnimalSystem instance
---@param xmlFile table XMLFile handle
---@param bridgeName string Human-readable bridge name for logging
---@param mapModDir string Map mod directory for resolving image paths in visual overrides
function RLMapBridge.applyPropertyOverrides(animalSystem, xmlFile, bridgeName, mapModDir)
    local typeOverrideCount = 0
    local subTypeOverrideCount = 0

    for _, key in xmlFile:iterator("animals.animal") do
        local rawTypeName = xmlFile:getString(key .. "#type")
        if rawTypeName == nil then
            -- Already warned in loadBridgeAnimals, skip silently
            continue
        end

        local typeName = rawTypeName:upper()
        local animalType = animalSystem.nameToType[typeName]
        if animalType == nil then
            continue
        end

        -- Type-level property overrides
        if RLMapBridge.applyTypeOverrides(animalType, animalSystem, xmlFile, key, typeName) then
            typeOverrideCount = typeOverrideCount + 1
        end

        -- SubType-level property overrides (for ALL subtypes, new and existing)
        for _, subTypeKey in xmlFile:iterator(key .. ".subType") do
            local rawName = xmlFile:getString(subTypeKey .. "#subType")
            if rawName == nil then
                continue
            end

            local name = rawName:upper()
            local subType = animalSystem.nameToSubType[name]
            if subType == nil then
                -- SubType not registered - might have failed to load, skip
                continue
            end

            if RLMapBridge.applySubTypeOverrides(subType, animalSystem, xmlFile, subTypeKey, name, mapModDir) then
                subTypeOverrideCount = subTypeOverrideCount + 1
            end
        end
    end

    if typeOverrideCount > 0 or subTypeOverrideCount > 0 then
        Log:info("MapBridge: Property overrides for '%s': %d type(s), %d subtype(s)",
            bridgeName, typeOverrideCount, subTypeOverrideCount)
    end
end


--- Apply type-level property overrides from bridge XML.
--- Only overrides properties that are explicitly defined in the XML (nil = keep current).
---@param animalType table The animalType object to patch
---@param animalSystem table The AnimalSystem instance (for loadAnimCurve)
---@param xmlFile table XMLFile handle
---@param key string XML key for this animal entry
---@param typeName string Type name for logging
---@return boolean patched Whether any properties were overridden
function RLMapBridge.applyTypeOverrides(animalType, animalSystem, xmlFile, key, typeName)
    local patches = {}

    -- Pregnancy (average and max children)
    local avgChildren = xmlFile:getInt(key .. ".pregnancy#average")
    if avgChildren ~= nil then
        local maxChildren = xmlFile:getInt(key .. ".pregnancy#max", math.max(avgChildren * 3, 3))
        animalType.pregnancy = RLMapBridge.buildPregnancyData(avgChildren, maxChildren)
        table.insert(patches, string.format("pregnancy(avg=%d, max=%d)", avgChildren, maxChildren))
    end

    -- Fertility curve
    local fertility = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".fertility")
    if fertility ~= nil then
        animalType.fertility = fertility
        table.insert(patches, "fertility")
    end

    -- Buy age
    local avgBuyAge = xmlFile:getInt(key .. "#averageBuyAge")
    if avgBuyAge ~= nil then
        animalType.averageBuyAge = avgBuyAge
        table.insert(patches, "averageBuyAge=" .. avgBuyAge)
    end

    local maxBuyAge = xmlFile:getInt(key .. "#maxBuyAge")
    if maxBuyAge ~= nil then
        animalType.maxBuyAge = maxBuyAge
        table.insert(patches, "maxBuyAge=" .. maxBuyAge)
    end

    -- Pasture sqm
    local sqmPerAnimal = xmlFile:getFloat(key .. ".pasture#sqmPerAnimal")
    if sqmPerAnimal ~= nil then
        animalType.sqmPerAnimal = sqmPerAnimal
        table.insert(patches, "sqmPerAnimal=" .. sqmPerAnimal)
    end

    if #patches > 0 then
        Log:info("MapBridge: Type '%s' overrides: %s", typeName, table.concat(patches, ", "))
        return true
    end

    return false
end


--- Apply subtype-level property overrides from bridge XML.
--- Only overrides properties that are explicitly defined in the XML (nil = keep current).
---@param subType table The subType object to patch
---@param animalSystem table The AnimalSystem instance (for loadAnimCurve)
---@param xmlFile table XMLFile handle
---@param key string XML key for this subType entry
---@param subTypeName string SubType name for logging
---@param mapModDir string Map mod directory for resolving image paths in visual overrides
---@return boolean patched Whether any properties were overridden
function RLMapBridge.applySubTypeOverrides(subType, animalSystem, xmlFile, key, subTypeName, mapModDir)
    local patches = {}

    -- Gender
    local gender = xmlFile:getString(key .. "#gender")
    if gender ~= nil then
        subType.gender = gender
        table.insert(patches, "gender=" .. gender)
    end

    -- Breed (re-registers subtype in animalType.breeds registry)
    local breed = xmlFile:getString(key .. "#breed")
    if breed ~= nil then
        breed = breed:upper()
        local oldBreed = subType.breed
        if breed ~= oldBreed then
            local animalType = animalSystem:getTypeByIndex(subType.typeIndex)
            if animalType ~= nil and animalType.breeds ~= nil then
                -- Remove from old breed group
                if oldBreed ~= nil and animalType.breeds[oldBreed] ~= nil then
                    for i, st in ipairs(animalType.breeds[oldBreed]) do
                        if st.name == subTypeName then
                            table.remove(animalType.breeds[oldBreed], i)
                            break
                        end
                    end
                    if #animalType.breeds[oldBreed] == 0 then
                        animalType.breeds[oldBreed] = nil
                    end
                end
                -- Add to new breed group
                if animalType.breeds[breed] == nil then
                    animalType.breeds[breed] = {}
                end
                table.insert(animalType.breeds[breed], subType)
            end
            subType.breed = breed
            table.insert(patches, string.format("breed(%s->%s)", oldBreed or "nil", breed))
        end
    end

    -- Weights
    local minWeight = xmlFile:getFloat(key .. "#minWeight")
    if minWeight ~= nil then
        subType.minWeight = minWeight
        table.insert(patches, "minWeight=" .. minWeight)
    end

    local targetWeight = xmlFile:getFloat(key .. "#targetWeight")
    if targetWeight ~= nil then
        subType.targetWeight = targetWeight
        table.insert(patches, "targetWeight=" .. targetWeight)
    end

    local maxWeight = xmlFile:getFloat(key .. "#maxWeight")
    if maxWeight ~= nil then
        subType.maxWeight = maxWeight
        table.insert(patches, "maxWeight=" .. maxWeight)
    end

    -- Reproduction
    local supported = xmlFile:getBool(key .. ".reproduction#supported")
    if supported ~= nil then
        subType.supportsReproduction = supported
        table.insert(patches, "supportsReproduction=" .. tostring(supported))
    end

    local minAgeMonth = xmlFile:getInt(key .. ".reproduction#minAgeMonth")
    if minAgeMonth ~= nil then
        subType.reproductionMinAgeMonth = minAgeMonth
        table.insert(patches, "reproductionMinAgeMonth=" .. minAgeMonth)
    end

    local durationMonth = xmlFile:getInt(key .. ".reproduction#durationMonth")
    if durationMonth ~= nil then
        subType.reproductionDurationMonth = durationMonth
        table.insert(patches, "reproductionDurationMonth=" .. durationMonth)
    end

    local minHealth = xmlFile:getFloat(key .. ".reproduction#minHealthFactor")
    if minHealth ~= nil then
        subType.reproductionMinHealth = math.clamp(minHealth, 0, 1)
        table.insert(patches, "reproductionMinHealth=" .. minHealth)
    end

    -- Health
    local healthInc = xmlFile:getInt(key .. ".health#increasePerHour")
    if healthInc ~= nil then
        subType.healthIncreaseHour = math.clamp(healthInc, 0, 100)
        table.insert(patches, "healthIncreaseHour=" .. healthInc)
    end

    local healthDec = xmlFile:getInt(key .. ".health#decreasePerHour")
    if healthDec ~= nil then
        subType.healthDecreaseHour = math.clamp(healthDec, 0, 100)
        table.insert(patches, "healthDecreaseHour=" .. healthDec)
    end

    -- Prices (AnimCurves)
    local buyPrice = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".buyPrice")
    if buyPrice ~= nil then
        subType.buyPrice = buyPrice
        table.insert(patches, "buyPrice")
    end

    local sellPrice = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".sellPrice")
    if sellPrice ~= nil then
        subType.sellPrice = sellPrice
        table.insert(patches, "sellPrice")
    end

    local transportPrice = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".transportPrice")
    if transportPrice ~= nil then
        subType.transportPrice = transportPrice
        table.insert(patches, "transportPrice")
    end

    -- Input (AnimCurves)
    local food = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".input.food")
    if food ~= nil then
        subType.input.food = food
        table.insert(patches, "input.food")
    end

    local straw = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".input.straw")
    if straw ~= nil then
        subType.input.straw = straw
        table.insert(patches, "input.straw")
    end

    local water = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".input.water")
    if water ~= nil then
        subType.input.water = water
        table.insert(patches, "input.water")
    end

    -- Output (AnimCurves)
    local manure = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".output.manure")
    if manure ~= nil then
        subType.output.manure = manure
        table.insert(patches, "output.manure")
    end

    local liquidManure = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".output.liquidManure")
    if liquidManure ~= nil then
        subType.output.liquidManure = liquidManure
        table.insert(patches, "output.liquidManure")
    end

    if xmlFile:hasProperty(key .. ".output.milk") then
        local milkFillTypeName = xmlFile:getString(key .. ".output.milk#fillType")
        local milkCurve = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".output.milk")
        if milkCurve ~= nil then
            subType.output.milk = {
                fillType = milkFillTypeName and g_fillTypeManager:getFillTypeIndexByName(milkFillTypeName) or (subType.output.milk and subType.output.milk.fillType),
                curve = milkCurve
            }
            table.insert(patches, "output.milk")
        end
    end

    if xmlFile:hasProperty(key .. ".output.pallets") then
        local palletsFillTypeName = xmlFile:getString(key .. ".output.pallets#fillType")
        local palletsCurve = AnimalSystem.loadAnimCurve(animalSystem, xmlFile, key .. ".output.pallets")
        if palletsCurve ~= nil then
            subType.output.pallets = {
                fillType = palletsFillTypeName and g_fillTypeManager:getFillTypeIndexByName(palletsFillTypeName) or (subType.output.pallets and subType.output.pallets.fillType),
                curve = palletsCurve
            }
            table.insert(patches, "output.pallets")
        end
    end

    -- Visuals (override visualAnimalIndex, image, description on existing visual stages)
    if xmlFile:hasProperty(key .. ".visuals") then
        local animalType = animalSystem:getTypeByIndex(subType.typeIndex)
        local visualOverrides = 0

        for _, visualKey in xmlFile:iterator(key .. ".visuals.visual") do
            local minAge = xmlFile:getInt(visualKey .. "#minAge")
            if minAge == nil then
                Log:warning("MapBridge: Visual override for '%s' missing minAge, skipping", subTypeName)
            else
                -- Find matching visual by minAge
                local matchedVisual = nil
                for _, visual in ipairs(subType.visuals) do
                    if visual.minAge == minAge then
                        matchedVisual = visual
                        break
                    end
                end

                if matchedVisual == nil then
                    Log:warning("MapBridge: Visual override for '%s' minAge=%d has no matching visual, skipping", subTypeName, minAge)
                else
                    local newIndex = xmlFile:getInt(visualKey .. "#visualAnimalIndex")
                    if newIndex ~= nil and animalType ~= nil then
                        local newAnimal = animalType.animals[newIndex]
                        if newAnimal ~= nil then
                            matchedVisual.visualAnimalIndex = newIndex
                            matchedVisual.visualAnimal = newAnimal
                        else
                            Log:warning("MapBridge: Visual override for '%s' minAge=%d: visualAnimalIndex %d not found in animalType.animals", subTypeName, minAge, newIndex)
                        end
                    end

                    local newImage = xmlFile:getString(visualKey .. "#image")
                    if newImage ~= nil then
                        matchedVisual.store.imageFilename = Utils.getFilename(newImage, mapModDir)
                    end

                    local newDesc = xmlFile:getString(visualKey .. "#description")
                    if newDesc ~= nil then
                        matchedVisual.store.description = g_i18n:convertText(newDesc)
                    end

                    local newCanBeBought = xmlFile:getBool(visualKey .. "#canBeBought")
                    if newCanBeBought ~= nil then
                        matchedVisual.store.canBeBought = newCanBeBought
                    end

                    visualOverrides = visualOverrides + 1
                end
            end
        end

        if visualOverrides > 0 then
            table.insert(patches, string.format("visuals(%d)", visualOverrides))
        end
    end

    if #patches > 0 then
        Log:info("MapBridge: SubType '%s' overrides: %s", subTypeName, table.concat(patches, ", "))
        return true
    end

    return false
end


--- Build pregnancy data (function + average) from average and max children counts.
--- Replicates the pregnancy probability distribution used by the animal system.
---@param averageChildren number Average number of offspring per pregnancy
---@param maxChildren number Maximum number of offspring per pregnancy
---@return table pregnancy { get = function, average = number }
function RLMapBridge.buildPregnancyData(averageChildren, maxChildren)
    local thresholds = {}
    local totalChance = 0

    for i = 0, averageChildren - 1 do
        totalChance = totalChance + (i / averageChildren) / maxChildren
        table.insert(thresholds, totalChance)
    end

    totalChance = totalChance + 0.5
    table.insert(thresholds, totalChance)

    for _ = averageChildren + 1, maxChildren - 1 do
        totalChance = totalChance + (1 - totalChance) * 0.8
        table.insert(thresholds, totalChance)
    end

    table.insert(thresholds, 1)

    return {
        get = function(value)
            for i = 0, #thresholds - 1 do
                if thresholds[i + 1] > value then return i end
            end
            return 0
        end,
        average = averageChildren
    }
end


--- Check if two subtypes are breeding-compatible according to bridge rules.
--- Returns nil if neither subtype is in a bridge breeding group (base rules apply).
--- Returns true if both are in the same group.
--- Returns false if one or both are in groups but different groups.
---@param maleSubTypeName string
---@param femaleSubTypeName string
---@return boolean|nil compatible
function RLMapBridge.isBreedingCompatible(maleSubTypeName, femaleSubTypeName)
    local maleGroup = RLMapBridge.breedingGroupBySubType[maleSubTypeName]
    local femaleGroup = RLMapBridge.breedingGroupBySubType[femaleSubTypeName]

    -- Neither in a bridge group - bridge has no opinion
    if maleGroup == nil and femaleGroup == nil then
        return nil
    end

    -- Both in same group = compatible; otherwise incompatible
    local compatible = maleGroup == femaleGroup
    Log:debug("MapBridge: isBreedingCompatible('%s' [%s], '%s' [%s]) = %s",
        maleSubTypeName, maleGroup or "none", femaleSubTypeName, femaleGroup or "none", tostring(compatible))
    return compatible
end


--- Get max fertility age for a subtype from its bridge breeding group.
--- Returns nil if subtype is not in any bridge breeding group (base rules apply).
---@param subTypeName string
---@return number|nil maxFertilityAge in months
function RLMapBridge.getMaxFertilityAge(subTypeName)
    local group = RLMapBridge.breedingGroupBySubType[subTypeName]

    if group == nil then
        return nil
    end

    return RLMapBridge.maxFertilityAgeByGroup[group]
end


--- Check if a specific map bridge is active.
---@param mapModName string Mod name (e.g. "FS25_HofBergmann")
---@return boolean
function RLMapBridge.isMapActive(mapModName)
    for _, bridge in ipairs(RLMapBridge.activeBridges) do
        if bridge.modName == mapModName then return true end
    end
    return false
end


--- Called from PlaceableHusbandryAnimals.onLoad to apply husbandry compat fixes.
--- Expands subtype filter whitelists to include breed siblings (e.g. adds BULL_SWISS_BROWN
--- when COW_SWISS_BROWN is whitelisted).
---@param placeable table PlaceableHusbandryAnimals instance
function RLMapBridge.onHusbandryLoad(placeable)
    if #RLMapBridge.activeBridges == 0 then return end

    local spec = placeable.spec_husbandryAnimals
    if spec == nil or spec.allowedSubTypeIndices == nil then return end

    -- Map husbandries may whitelist specific subtypes (e.g. COW_SWISS_BROWN)
    -- but not know about RL's male variants (e.g. BULL_SWISS_BROWN).
    -- Expand the whitelist to include breed siblings.
    local animalSystem = g_currentMission.animalSystem
    local toAdd = {}

    for allowedIdx, _ in pairs(spec.allowedSubTypeIndices) do
        local subType = animalSystem:getSubTypeByIndex(allowedIdx)
        if subType ~= nil then
            local animalType = animalSystem:getTypeByIndex(subType.typeIndex)
            if animalType ~= nil and animalType.breeds ~= nil and animalType.breeds[subType.breed] ~= nil then
                for _, sibling in ipairs(animalType.breeds[subType.breed]) do
                    if not spec.allowedSubTypeIndices[sibling.subTypeIndex] then
                        toAdd[sibling.subTypeIndex] = sibling.name
                    end
                end
            end
        end
    end

    for idx, name in pairs(toAdd) do
        spec.allowedSubTypeIndices[idx] = true
        Log:info("MapBridge: Husbandry compat - added '%s' (idx=%d) as breed sibling for '%s'",
            name, idx, placeable:getName())
    end
end
