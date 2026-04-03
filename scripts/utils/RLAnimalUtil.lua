-- RLAnimalUtil.lua
-- Purpose: Centralized animal identity comparison, lookup, key formatting,
--          ID generation, state hashing, and stream identity helpers.
--          Replaces 62 inline identity patterns across 22+ files.
-- Author: Ritter

RLAnimalUtil = {}

local Log = RmLogging.getLogger("RLRM")


--- Compare two animals by identity triple (farmId + uniqueId + birthday.country).
--- Nil-safe: returns false with warning if either argument has nil identity fields.
---@param a table Animal or animal-like table with farmId, uniqueId, birthday.country
---@param b table Animal or animal-like table with farmId, uniqueId, birthday.country
---@return boolean true if all three identity fields match
function RLAnimalUtil.compare(a, b)
    Log:trace("RLAnimalUtil.compare: a=%s, b=%s", tostring(a), tostring(b))

    if a == nil or b == nil then
        Log:warning("RLAnimalUtil.compare: nil argument (a=%s, b=%s)", tostring(a), tostring(b))
        return false
    end

    if a.farmId == nil or a.uniqueId == nil or a.birthday == nil then
        Log:warning("RLAnimalUtil.compare: nil identity field on a (farmId=%s, uniqueId=%s, birthday=%s)",
            tostring(a.farmId), tostring(a.uniqueId), tostring(a.birthday))
        return false
    end

    if b.farmId == nil or b.uniqueId == nil or b.birthday == nil then
        Log:warning("RLAnimalUtil.compare: nil identity field on b (farmId=%s, uniqueId=%s, birthday=%s)",
            tostring(b.farmId), tostring(b.uniqueId), tostring(b.birthday))
        return false
    end

    local match = a.farmId == b.farmId
        and a.uniqueId == b.uniqueId
        and a.birthday.country == b.birthday.country

    if not match then
        Log:trace("RLAnimalUtil.compare: no match (a=%s/%s/%s vs b=%s/%s/%s)",
            tostring(a.farmId), tostring(a.uniqueId), tostring(a.birthday.country),
            tostring(b.farmId), tostring(b.uniqueId), tostring(b.birthday.country))
    end

    return match
end


--- Find an animal by identity in a list.
--- Uses pairs() for behavioral equivalence with existing inline loops.
---@param animals table Array of animal objects
---@param farmId string Farm ID to match
---@param uniqueId string Unique ID to match
---@param country number Birthday country index to match
---@return table|nil animal The matching animal, or nil if not found
function RLAnimalUtil.find(animals, farmId, uniqueId, country)
    Log:trace("RLAnimalUtil.find: farmId=%s, uniqueId=%s, country=%s", tostring(farmId), tostring(uniqueId), tostring(country))

    for _, animal in pairs(animals) do
        if animal.farmId == farmId and animal.uniqueId == uniqueId and animal.birthday.country == country then
            Log:debug("RLAnimalUtil.find: found animal uniqueId=%s", tostring(uniqueId))
            return animal
        end
    end

    Log:trace("RLAnimalUtil.find: not found farmId=%s, uniqueId=%s, country=%s", tostring(farmId), tostring(uniqueId), tostring(country))
    return nil
end


--- Find and remove an animal from a list by identity. Mutates the list in-place.
--- Returns immediately after first match (same as existing removeSaleAnimal pattern).
---@param animals table Array of animal objects (mutated in-place)
---@param farmId string Farm ID to match
---@param uniqueId string Unique ID to match
---@param country number Birthday country index to match
---@return table|nil animal The removed animal, or nil if not found
function RLAnimalUtil.findAndRemove(animals, farmId, uniqueId, country)
    Log:trace("RLAnimalUtil.findAndRemove: farmId=%s, uniqueId=%s, country=%s", tostring(farmId), tostring(uniqueId), tostring(country))

    for i, animal in pairs(animals) do
        if animal.farmId == farmId and animal.uniqueId == uniqueId and animal.birthday.country == country then
            table.remove(animals, i)
            Log:debug("RLAnimalUtil.findAndRemove: removed animal uniqueId=%s at index %d", tostring(uniqueId), i)
            return animal
        end
    end

    Log:trace("RLAnimalUtil.findAndRemove: not found farmId=%s, uniqueId=%s, country=%s", tostring(farmId), tostring(uniqueId), tostring(country))
    return nil
end


--- Build a 3-part key string from identity fields.
--- Used by cluster removeCluster, sell events, getClusterId.
---@param farmId string|number Farm ID
---@param uniqueId string|number Unique ID
---@param country string|number Birthday country index
---@return string key "farmId uniqueId country"
function RLAnimalUtil.toKey(farmId, uniqueId, country)
    return farmId .. " " .. uniqueId .. " " .. country
end


--- Build a 2-part key string from identity fields.
--- Used by horse brush/riding flows via idToIndex mapping.
---@param farmId string|number Farm ID
---@param uniqueId string|number Unique ID
---@return string key "farmId uniqueId"
function RLAnimalUtil.toShortKey(farmId, uniqueId)
    return farmId .. " " .. uniqueId
end


--- Build a 3-part key from an identifiers table, handling both flat form
--- (from readStreamIdentifiers: has .country) and nested form (from live Animal: has .birthday.country).
--- Returns nil with warning if country cannot be resolved.
---@param ids table Identifiers table with farmId, uniqueId, and either country or birthday.country
---@return string|nil key "farmId uniqueId country", or nil if country is unresolvable
function RLAnimalUtil.toKeyFromIdentifiers(ids)
    local country = ids.country or (ids.birthday and ids.birthday.country)

    if country == nil then
        Log:warning("RLAnimalUtil.toKeyFromIdentifiers: cannot resolve country (farmId=%s, uniqueId=%s)",
            tostring(ids.farmId), tostring(ids.uniqueId))
        return nil
    end

    return RLAnimalUtil.toKey(ids.farmId, ids.uniqueId, country)
end


--- Pad a raw sequential ID to 5+ digits by prefixing with "1"s.
--- IDs already at 5+ digits are returned as string unchanged.
--- Accepts string or number (Lua .. operator auto-coerces).
---@param rawId string|number Raw sequential animal ID
---@return string paddedId ID string of at least 5 characters
function RLAnimalUtil.padId(rawId)
    local id = tostring(rawId)
    local idLen = string.len(id)

    if idLen < 5 then
        if idLen == 1 then
            id = "1000" .. id
        elseif idLen == 2 then
            id = "100" .. id
        elseif idLen == 3 then
            id = "10" .. id
        elseif idLen == 4 then
            id = "1" .. id
        end
    end

    Log:trace("RLAnimalUtil.padId: rawId=%s -> %s", tostring(rawId), id)
    return id
end


--- Compute check digit from farm herd ID and animal ID.
--- Result range: 1-7, prepended to padded ID.
--- Uses ::number typecast (Giants Engine extension) for nil-safety.
--- Accepts string or number params (Lua .. operator auto-coerces).
---@param farmHerdId string|number Farm herd ID
---@param id string|number Padded animal ID
---@return number checkDigit Value 1-7
function RLAnimalUtil.computeCheckDigit(farmHerdId, id)
    local checkDigit = (tonumber(farmHerdId .. id)::number % 7) + 1
    Log:trace("RLAnimalUtil.computeCheckDigit: farmHerdId=%s, id=%s -> %d", tostring(farmHerdId), tostring(id), checkDigit)
    return checkDigit
end


--- Generate a complete unique ID from farm herd ID and raw sequential ID.
--- Combines padId + computeCheckDigit + prepend into one call.
--- Returns checkDigit .. paddedId as a string.
---@param farmHerdId string|number Farm herd ID
---@param rawId string|number Raw sequential animal ID
---@return string uniqueId Complete unique ID string (e.g. "410003")
function RLAnimalUtil.generateUniqueId(farmHerdId, rawId)
    local paddedId = RLAnimalUtil.padId(rawId)
    local checkDigit = RLAnimalUtil.computeCheckDigit(farmHerdId, paddedId)
    local uniqueId = checkDigit .. paddedId
    Log:debug("RLAnimalUtil.generateUniqueId: farmHerdId=%s, rawId=%s -> %s", tostring(farmHerdId), tostring(rawId), uniqueId)
    return uniqueId
end


--- Compute state hash for dirty-checking (network sync).
--- NOT an identity hash - encodes age + health + reproduction + subTypeIndex.
---@param animal table Animal object with age, health, reproduction, subTypeIndex fields
---@return number hash State hash value
function RLAnimalUtil.getHash(animal)
    local hash = (100 + animal.age) + (1000 * (100 + animal.health)) + (1000000 * (100 + animal.reproduction)) + (1000000000 * (100 + animal.subTypeIndex))
    Log:trace("RLAnimalUtil.getHash: age=%s, health=%s -> %s", tostring(animal.age), tostring(animal.health), tostring(hash))
    return hash
end


--- Deserialize animal identity from a network stream.
--- Read order: uniqueId (string), farmId (string), country (UInt8), animalTypeIndex (UInt8).
--- WARNING: This is the per-animal event protocol. The cluster system uses a DIFFERENT order.
---@param streamId number Network stream ID
---@param connection table Network connection (unused, kept for API consistency)
---@return table identifiers Table with uniqueId, farmId, country, animalTypeIndex fields
function RLAnimalUtil.readStreamIdentifiers(streamId, connection)
    local uniqueId = streamReadString(streamId)
    local farmId = streamReadString(streamId)
    local country = streamReadUInt8(streamId)
    local animalTypeIndex = streamReadUInt8(streamId)

    Log:trace("RLAnimalUtil.readStreamIdentifiers: farmId=%s, uniqueId=%s, country=%d, typeIdx=%d",
        farmId, uniqueId, country, animalTypeIndex)

    return {
        ["uniqueId"] = uniqueId,
        ["farmId"] = farmId,
        ["country"] = country,
        ["animalTypeIndex"] = animalTypeIndex
    }
end


--- Serialize animal identity to a network stream.
--- Write order: uniqueId (string), farmId (string), birthday.country (UInt8), animalTypeIndex (UInt8).
--- WARNING: This is the per-animal event protocol. The cluster system uses a DIFFERENT order.
---@param animal table Animal object with uniqueId, farmId, birthday.country, animalTypeIndex
---@param streamId number Network stream ID
---@param connection table Network connection (unused, kept for API consistency)
---@return boolean true
function RLAnimalUtil.writeStreamIdentifiers(animal, streamId, connection)
    streamWriteString(streamId, animal.uniqueId)
    streamWriteString(streamId, animal.farmId)
    streamWriteUInt8(streamId, animal.birthday.country)
    streamWriteUInt8(streamId, animal.animalTypeIndex)

    Log:trace("RLAnimalUtil.writeStreamIdentifiers: farmId=%s, uniqueId=%s, country=%d, typeIdx=%d",
        animal.farmId, animal.uniqueId, animal.birthday.country, animal.animalTypeIndex)

    return true
end
