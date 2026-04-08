--[[
    DewarMigration.lua

    One-time migration of old PhysicsObject dewars (items.xml) to Vehicle dewars.
    Called from RealisticLivestock:loadMap() on server after map load.

    Idempotency: Checks if g_dewarManager already has dewars (from vehicles.xml).
    If yes, migration is skipped - the save was already converted.

    Reads items.xml from DISK (not in-memory) to get original data before
    RmItemSystemMigration patches classNames. Searches for both old and new
    mod name prefixes.

    RmItemSystemMigration continues to patch classNames as before - the patched
    Dewar class no longer exists so those item entries become harmless orphans.
]]

local Log = RmLogging.getLogger("RLRM")
local modDirectory = g_currentModDirectory

DewarMigration = {}

local OLD_CLASS = "FS25_RealisticLivestock.Dewar"
local NEW_CLASS = "FS25_RealisticLivestockRM.Dewar"


function DewarMigration.run()

    if g_server == nil then return end

    local savegameDir = g_currentMission.missionInfo.savegameDirectory
    if savegameDir == nil then
        Log:debug("DewarMigration: no savegame directory - new game, nothing to migrate")
        return
    end

    -- Idempotency: check vehicles.xml for existing rlDewar entries (timing-independent)
    -- Cannot use g_dewarManager:hasAnyDewars() because loadMap fires before vehicles.xml is loaded
    if DewarMigration.hasVehicleDewarsInSavegame(savegameDir) then
        Log:debug("DewarMigration: skipped - vehicles.xml already contains rlDewar entries")
        return
    end

    local itemsPath = savegameDir .. "/items.xml"
    if not fileExists(itemsPath) then
        Log:debug("DewarMigration: no items.xml found")
        return
    end

    -- Read items.xml from disk to find old Dewar entries
    local xmlFile = XMLFile.loadIfExists("dewar_migration", itemsPath)
    if xmlFile == nil then
        Log:warning("DewarMigration: could not load items.xml")
        return
    end

    local dewarEntries = {}

    xmlFile:iterate("items.item", function(_, key)
        local className = xmlFile:getString(key .. "#className")
        if className == OLD_CLASS or className == NEW_CLASS then
            local entry = DewarMigration.readDewarEntry(xmlFile, key)
            if entry ~= nil then
                table.insert(dewarEntries, entry)
            end
        end
    end)

    xmlFile:delete()

    if #dewarEntries == 0 then
        Log:debug("DewarMigration: no old Dewar entries found in items.xml")
        return
    end

    Log:info("DewarMigration: found %d old Dewar entries to migrate", #dewarEntries)

    -- Queue async Vehicle creation for each entry
    DewarMigration.pendingEntries = dewarEntries
    DewarMigration.currentIndex = 1
    DewarMigration.migratedCount = 0
    DewarMigration.failedCount = 0
    DewarMigration.processNext()

end


function DewarMigration.hasVehicleDewarsInSavegame(savegameDir)

    local vehiclesPath = savegameDir .. "/vehicles.xml"
    if not fileExists(vehiclesPath) then
        return false
    end

    local xmlFile = XMLFile.loadIfExists("dewar_migration_check", vehiclesPath)
    if xmlFile == nil then
        return false
    end

    local found = false
    xmlFile:iterate("vehicles.vehicle", function(_, key)
        local typeName = xmlFile:getString(key .. "#typeName")
        if typeName ~= nil and string.find(typeName, "rlDewar", 1, true) ~= nil then
            found = true
            return false -- stop iteration
        end
    end)

    xmlFile:delete()
    return found

end


function DewarMigration.readDewarEntry(xmlFile, key)

    local uniqueId = xmlFile:getString(key .. "#uniqueId")
    local position = xmlFile:getVector(key .. "#position")
    local rotation = xmlFile:getVector(key .. "#rotation")
    local farmId = xmlFile:getInt(key .. "#farmId")
    local straws = xmlFile:getInt(key .. "#straws")

    if uniqueId == nil or position == nil or straws == nil or straws <= 0 then
        Log:warning("DewarMigration: skipping invalid entry - uniqueId=%s straws=%s",
            tostring(uniqueId), tostring(straws))
        return nil
    end

    local entry = {
        uniqueId = uniqueId,
        position = position,
        rotation = rotation or {0, 0, 0},
        farmId = farmId or 1,
        straws = straws
    }

    -- Read animal data
    local animalKey = key .. ".animal"
    if xmlFile:hasProperty(animalKey) then
        local animal = {}
        animal.country = xmlFile:getInt(animalKey .. "#country")
        animal.farmId = xmlFile:getString(animalKey .. "#farmId")
        animal.uniqueId = xmlFile:getString(animalKey .. "#uniqueId")
        animal.name = xmlFile:getString(animalKey .. "#name")
        animal.typeIndex = xmlFile:getInt(animalKey .. "#typeIndex")
        animal.subTypeIndex = xmlFile:getInt(animalKey .. "#subTypeIndex")
        animal.success = xmlFile:getFloat(animalKey .. "#success")

        animal.genetics = {
            ["metabolism"] = xmlFile:getFloat(animalKey .. ".genetics#metabolism"),
            ["fertility"] = xmlFile:getFloat(animalKey .. ".genetics#fertility"),
            ["health"] = xmlFile:getFloat(animalKey .. ".genetics#health"),
            ["quality"] = xmlFile:getFloat(animalKey .. ".genetics#quality"),
            ["productivity"] = xmlFile:getFloat(animalKey .. ".genetics#productivity")
        }

        -- Validate subtype consistency
        local animalSystem = g_currentMission.animalSystem
        local st = animalSystem:getSubTypeByIndex(animal.subTypeIndex)
        if st == nil then
            Log:warning("DewarMigration: subTypeIndex=%d has no matching subtype for dewar %s - semen data may be from removed pack",
                animal.subTypeIndex, uniqueId)
        elseif st.typeIndex ~= animal.typeIndex then
            Log:warning("DewarMigration: type mismatch for dewar %s! saved typeIndex=%d but subTypeIndex=%d resolves to typeIndex=%d",
                uniqueId, animal.typeIndex, animal.subTypeIndex, st.typeIndex)
        end

        entry.animal = animal
    end

    return entry

end


function DewarMigration.processNext()

    if DewarMigration.currentIndex > #DewarMigration.pendingEntries then
        Log:info("DewarMigration: complete - migrated=%d failed=%d total=%d",
            DewarMigration.migratedCount, DewarMigration.failedCount, #DewarMigration.pendingEntries)
        DewarMigration.pendingEntries = nil
        return
    end

    local entry = DewarMigration.pendingEntries[DewarMigration.currentIndex]

    local storeItem = g_storeManager:getItemByXMLFilename(modDirectory .. "objects/dewar/dewar.xml")
    if storeItem == nil then
        Log:error("DewarMigration: could not find dewar store item - aborting migration")
        return
    end

    local data = VehicleLoadingData.new()
    data:setStoreItem(storeItem)
    data:setPropertyState(VehiclePropertyState.OWNED)
    data:setOwnerFarmId(entry.farmId)
    data:setPosition(entry.position[1], entry.position[2], entry.position[3])
    data:setRotation(entry.rotation[1], entry.rotation[2], entry.rotation[3])

    -- Store entry for callback
    DewarMigration.currentEntry = entry

    data:load(DewarMigration.onDewarLoaded, DewarMigration)

end


function DewarMigration.onDewarLoaded(_, vehicles, loadingState)

    local entry = DewarMigration.currentEntry

    if loadingState ~= VehicleLoadingState.OK then
        Log:warning("DewarMigration: failed to create vehicle for dewar %s, loadingState=%s",
            tostring(entry.uniqueId), tostring(loadingState))
        DewarMigration.failedCount = DewarMigration.failedCount + 1
    else
        local vehicle = vehicles[1]
        if vehicle == nil then
            Log:warning("DewarMigration: vehicle list empty for dewar %s", tostring(entry.uniqueId))
            DewarMigration.failedCount = DewarMigration.failedCount + 1
            DewarMigration.currentIndex = DewarMigration.currentIndex + 1
            DewarMigration.processNext()
            return
        end

        vehicle:setUniqueId(entry.uniqueId)
        if entry.animal ~= nil then
            -- Use raw table path (not live Animal) via setAnimal
            vehicle:setAnimal(entry.animal)
        end
        vehicle:setStraws(entry.straws)

        Log:info("DewarMigration: migrated dewar uniqueId=%s farmId=%d straws=%d",
            entry.uniqueId, entry.farmId, entry.straws)
        DewarMigration.migratedCount = DewarMigration.migratedCount + 1
    end

    -- Process next entry
    DewarMigration.currentIndex = DewarMigration.currentIndex + 1
    DewarMigration.processNext()

end
