RL_FarmManager = {}

local Log = RmLogging.getLogger("RLRM")

function RL_FarmManager:loadFromXMLFile(superFunc, path)

    -- Initialize migration manager and check for conflicts/migration needs (server only)
    -- NOTE: Early migration (items.xml, handTools.xml) is now handled by RmItemSystemMigration
    -- which hooks into ItemSystem.loadItems and runs BEFORE items are loaded.
    -- Here we only check for mod conflicts and set flags for showing dialogs.
    if g_currentMission:getIsServer() then
        Log:info("FarmManager: Checking migration state...")

        -- Create migration manager instance if not already created by RmItemSystemMigration
        if g_rmMigrationManager == nil then
            Log:info("FarmManager: Creating RmMigrationManager instance")
            g_rmMigrationManager = RmMigrationManager.new()
        end

        -- Check for mod conflict (both old and new mod installed)
        if g_rmMigrationManager:checkModConflict() then
            -- Conflict detected - will show dialog in onStartMission
            Log:warning("FarmManager: Conflict detected!")
            g_rmMigrationConflict = true
        elseif not g_rmPendingMigration and g_rmMigrationManager:shouldMigrate() then
            -- Migration needed but wasn't handled by RmItemSystemMigration (shouldn't happen normally)
            -- This is a fallback in case ItemSystem hook didn't run
            Log:info("FarmManager: Migration needed (fallback path)")
            g_rmPendingMigration = true
        else
            Log:info("FarmManager: No conflict detected, migration state = %s", tostring(g_rmPendingMigration))
        end

        Log:info("FarmManager: g_rmMigrationConflict = %s", tostring(g_rmMigrationConflict))
        Log:info("FarmManager: g_rmPendingMigration = %s", tostring(g_rmPendingMigration))
    else
        Log:info("FarmManager: Not running on server, skipping migration check")
    end

    local returnValue = superFunc(self, path)

    local animalSystem = g_currentMission.animalSystem
    animalSystem:initialiseCountries()

    if g_currentMission:getIsServer() then
        local hasData = animalSystem:loadFromXMLFile()
        animalSystem:validateFarms(hasData)
    end

    return returnValue

end

FarmManager.loadFromXMLFile = Utils.overwrittenFunction(FarmManager.loadFromXMLFile, RL_FarmManager.loadFromXMLFile)
