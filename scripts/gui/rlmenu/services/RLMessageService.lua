--[[
    RLMessageService.lua
    Query + delete service for the RL Tabbed Menu Messages tab.

    getMessagesForFarm builds a unioned, newest-first, display-ready list
    of husbandry messages for a farm; it's read-only and safe on both
    server and client (clients receive messages via HusbandryMessageStateEvent).

    deleteMessages is the Phase 1.1 mutation path, using Pattern A
    (caller mutates local state first, then dispatches
    HusbandryMessageDeleteEvent for rebroadcast).
]]

RLMessageService = {}

local Log = RmLogging.getLogger("RLRM")

--- Parse a "d/m/yyyy" date string into integer (year, month, day) parts.
--- Malformed or nil input returns (0, 0, 0) and emits a single warning.
--- The (0,0,0) sentinel keeps malformed entries in the list but sorts them
--- to the bottom under the newest-first comparator.
--- @param dateStr string|nil Raw message.date string from PlaceableHusbandryAnimals
--- @return number year
--- @return number month
--- @return number day
function RLMessageService.parseDate(dateStr)
    if dateStr == nil then
        Log:warning("RLMessageService.parseDate: nil date string")
        return 0, 0, 0
    end

    local d, m, y = string.match(dateStr, "^(%d+)/(%d+)/(%d+)$")
    if d == nil or m == nil or y == nil then
        Log:warning("RLMessageService.parseDate: malformed date '%s'", tostring(dateStr))
        return 0, 0, 0
    end

    return tonumber(y), tonumber(m), tonumber(d)
end

--- Substitute %s and '%s' tokens in a localized message template with values
--- from message.args, resolving any rl_*-prefixed arg via g_i18n first.
---
--- This is a verbatim port of the legacy substitution logic. The space-split
--- approach is fragile for punctuation-heavy templates but every existing
--- rl_message_* translation in 17 language files was authored against this
--- exact behavior. Diverging now would silently break translated text.
--- Cleanup is deferred to Phase 8.
--- @param template string Localized template string (output of g_i18n:getText)
--- @param args table|nil Argument list from the raw message record
--- @return string Substituted text
local function substituteTokens(template, args)
    Log:trace("RLMessageService.substituteTokens: template='%s'", tostring(template))
    local tokens = string.split(template, " ")
    local argI = 1

    -- ipairs (not pairs) because the token table is a contiguous array and
    -- substitution order must match the positional %s argument sequence.
    for i, token in ipairs(tokens) do
        if token == "%s" then
            local arg = (args and args[argI]) or ""
            if string.contains(arg, "rl_") then
                tokens[i] = g_i18n:getText(arg)
            else
                tokens[i] = arg
            end
            argI = argI + 1
        elseif token == "'%s'" then
            local arg = (args and args[argI]) or ""
            if string.contains(arg, "rl_") then
                tokens[i] = "'" .. g_i18n:getText(arg) .. "'"
            else
                tokens[i] = "'" .. arg .. "'"
            end
            argI = argI + 1
        end
    end

    return table.concat(tokens, " ")
end

--- Format a single message record into a display-ready row table.
--- Unknown ids fall back to a sentinel row plus a single warning.
---
--- Row schema (contract for the frame layer):
---   importanceSlice  : "realistic_livestock.importance_<1|2|3>"
---   typeText         : localized rl_messageTitle_<title>
---   animalText       : message.animal or "N/A"
---   messageText      : localized + token-substituted body
---   husbandryName    : placeable:getName() captured by caller (display-only)
---   date             : raw message.date string for display
---   sortKey          : { year, month, day, husbandryIndex, insertionIndex } desc
---   husbandryRef     : placeable reference (opaque delete token; Phase 1.1+; frame MUST treat as opaque)
---   uniqueId         : int (raw message.uniqueId; Phase 1.1+; used for delete routing)
--- @param message table Raw message record (id/animal/args/date/uniqueId)
--- @param husbandry table Source husbandry placeable (stored as opaque delete token)
--- @param husbandryIndex number Stable per-call index of the husbandry within getPlaceablesByFarm
--- @param insertionIndex number 1-based position of the message inside its source list
--- @return table row
function RLMessageService.formatMessage(message, husbandry, husbandryIndex, insertionIndex)
    local year, month, day = RLMessageService.parseDate(message.date)
    local sortKey = { year, month, day, husbandryIndex, insertionIndex }
    local husbandryName = (husbandry ~= nil and husbandry.getName and husbandry:getName()) or "Unknown"

    local baseMessage = RLMessage[message.id]
    if baseMessage == nil then
        Log:warning("RLMessageService.formatMessage: unknown message id '%s' (date=%s)",
            tostring(message.id), tostring(message.date))
        return {
            importanceSlice = "realistic_livestock.importance_3",
            typeText        = "?",
            animalText      = message.animal or "N/A",
            messageText     = string.format(g_i18n:getText("rl_menu_messages_unknown"), tostring(message.id)),
            husbandryName   = husbandryName,
            date            = message.date or "",
            sortKey         = sortKey,
            husbandryRef    = husbandry,
            uniqueId        = message.uniqueId,
        }
    end

    local template    = g_i18n:getText("rl_message_" .. baseMessage.text)
    local messageText = substituteTokens(template, message.args)

    return {
        importanceSlice = string.format("realistic_livestock.importance_%d", baseMessage.importance),
        typeText        = g_i18n:getText("rl_messageTitle_" .. baseMessage.title),
        animalText      = message.animal or "N/A",
        messageText     = messageText,
        husbandryName   = husbandryName,
        date            = message.date or "",
        sortKey         = sortKey,
        husbandryRef    = husbandry,
        uniqueId        = message.uniqueId,
    }
end

--- Sort comparator: returns true when row a should appear before row b
--- under the newest-first ordering. Compares the sortKey tuple component-wise
--- in descending order: year, month, day, husbandryIndex, insertionIndex.
---
--- The cross-husbandry tie-break (husbandryIndex) is heuristic and may
--- visually drift between host and client because getPlaceablesByFarm
--- iteration order is not guaranteed identical. Content is identical;
--- only same-day order across husbandries can differ.
---
--- Deliberately NOT logged: `table.sort` invokes this O(n log n) times per
--- refresh, so even a trace-level call would emit thousands of entries on
--- a large message list. The caller logs row count and timing instead.
--- @param a table Row a (must have sortKey)
--- @param b table Row b (must have sortKey)
--- @return boolean
function RLMessageService.compareRows(a, b)
    local ka = a.sortKey
    local kb = b.sortKey
    for i = 1, 5 do
        if ka[i] ~= kb[i] then
            return ka[i] > kb[i]
        end
    end
    return false
end

--- Build the unioned, display-ready, newest-first list of messages for a farm.
--- Walks every husbandry placeable on the farm, unions their getRLMessages()
--- via formatMessage, and sorts the result. Read-only and side-effect-free
--- on both server and client.
--- @param farmId number|nil Farm id (typically g_currentMission:getFarmId())
--- @return table rows[] Array of formatted row tables; empty if farmId is nil/0
function RLMessageService.getMessagesForFarm(farmId)
    Log:debug("RLMessageService.getMessagesForFarm: farmId=%s", tostring(farmId))

    if farmId == nil or farmId == 0 then
        Log:trace("RLMessageService.getMessagesForFarm: no farm, returning empty")
        return {}
    end

    if g_currentMission == nil or g_currentMission.husbandrySystem == nil then
        Log:warning("RLMessageService.getMessagesForFarm: husbandrySystem unavailable")
        return {}
    end

    local placeables = g_currentMission.husbandrySystem:getPlaceablesByFarm(farmId)
    if placeables == nil then
        Log:trace("RLMessageService.getMessagesForFarm: no placeables for farm %d", farmId)
        return {}
    end

    local rows = {}
    local husbandryIndex = 0

    for _, placeable in pairs(placeables) do
        husbandryIndex = husbandryIndex + 1
        if placeable.getRLMessages ~= nil then
            local messages = placeable:getRLMessages() or {}
            for i = 1, #messages do
                table.insert(rows, RLMessageService.formatMessage(
                    messages[i], placeable, husbandryIndex, i))
            end
        end
    end

    table.sort(rows, RLMessageService.compareRows)

    Log:debug("RLMessageService.getMessagesForFarm: %d rows from %d husbandries",
        #rows, husbandryIndex)
    return rows
end

-- =============================================================================
-- Phase 1.1: mutation path (delete)
-- =============================================================================

--- Dispatch hook for unit tests. Production code sends through HusbandryMessageDeleteEvent.
--- Tests can swap this field (RLMessageService._sendDeleteEvent = stub) to assert
--- deleteMessages calls it with the expected payload WITHOUT requiring a real network.
--- @type function
RLMessageService._sendDeleteEvent = function(husbandry, uniqueIds)
    HusbandryMessageDeleteEvent.sendEvent(husbandry, uniqueIds)
end

--- Delete one or more messages from a husbandry.
---
--- Pattern A (caller-mutates-first + rebroadcast-from-run):
---   1. This service mutates local state immediately via placeable:deleteRLMessage
---      (SP, host, and client originator all take this path).
---   2. Then it dispatches the event, which broadcasts to remote clients or
---      uploads to the server depending on g_server state.
---   3. On remote receivers, the event's run() applies the mutation via
---      its own deleteRLMessage loop.
---
--- Idempotent: unknown uniqueIds are silently skipped by deleteRLMessage.
--- @param husbandry table Target husbandry placeable (must have spec_husbandryAnimals)
--- @param uniqueIds table Array of uniqueIds to delete (non-empty)
function RLMessageService.deleteMessages(husbandry, uniqueIds)
    if husbandry == nil or husbandry.spec_husbandryAnimals == nil then
        Log:warning("RLMessageService.deleteMessages: invalid husbandry, aborting")
        return
    end
    if uniqueIds == nil or #uniqueIds == 0 then
        Log:warning("RLMessageService.deleteMessages: empty uniqueIds, aborting")
        return
    end

    Log:debug("RLMessageService.deleteMessages: husbandry='%s' count=%d",
        tostring(husbandry:getName()), #uniqueIds)

    -- 1. Mutate local state first (caller-mutates-first per Pattern A).
    for i = 1, #uniqueIds do
        husbandry:deleteRLMessage(uniqueIds[i])
    end

    -- 2. Dispatch the event via the swappable hook (production path calls
    --    HusbandryMessageDeleteEvent.sendEvent, tests can stub).
    RLMessageService._sendDeleteEvent(husbandry, uniqueIds)
end

--- Group an array of display rows by their source husbandry so a bulk delete
--- can fire one event per husbandry (minimizes event count).
---
--- Returns an ordered array (not a map) so the dispatch order is deterministic.
--- The first row seen for a given husbandry defines that husbandry's position
--- in the result. Rows without `husbandryRef` or `uniqueId` are skipped.
--- @param rows table Array of display rows with `husbandryRef` + `uniqueId`
--- @return table groups Array of `{ husbandry = <placeable>, uniqueIds = {...} }`
function RLMessageService.groupRowsByHusbandry(rows)
    local groups = {}
    local indexByHusbandry = {}

    if rows == nil then return groups end

    for i = 1, #rows do
        local row = rows[i]
        if row.husbandryRef ~= nil and row.uniqueId ~= nil then
            local groupIdx = indexByHusbandry[row.husbandryRef]
            if groupIdx == nil then
                table.insert(groups, { husbandry = row.husbandryRef, uniqueIds = {} })
                groupIdx = #groups
                indexByHusbandry[row.husbandryRef] = groupIdx
            end
            table.insert(groups[groupIdx].uniqueIds, row.uniqueId)
        end
    end

    Log:trace("RLMessageService.groupRowsByHusbandry: %d row(s) -> %d group(s)", #rows, #groups)
    return groups
end
