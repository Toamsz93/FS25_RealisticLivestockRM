--[[
    RLMenu.lua
    Root controller for the RL Tabbed Menu (standalone TabbedMenu subclass).

    Phase 1: ships the Messages tab as the first real tab. Opened via the
    unbound RL_MENU input action (user assigns a key in Settings -> Controls).
    ESC closes via the standard FS25 back-button pattern; the menu does NOT
    implement toggle-to-close (Fresh's quick-view pattern is unsuitable for a
    destination menu).

    Phase 2+ adds the remaining tabs (Herdsman, Info, Move, Buy, Sell, AI) with
    dedicated frame files under frames/ and service files under services/.
]]

RLMenu = RLMenu or {}
local RLMenu_mt = Class(RLMenu, TabbedMenu)

-- Store mod directory at source time (g_currentModDirectory is only valid during source())
local modDirectory = g_currentModDirectory

-- Input action name for opening the menu. Declared in modDesc.xml, unbound by default.
RLMenu.ACTION_NAME = "RL_MENU"

--- Construct a new RLMenu instance. Called once from setupGui() during mod load.
--- @param target table|nil
--- @param custom_mt table|nil
--- @return table self
function RLMenu.new(target, custom_mt)
    local self = TabbedMenu.new(target, custom_mt or RLMenu_mt)
    self.isOpen = false
    Log:trace("RLMenu.new: instance created")
    return self
end

--- One-time mod-load setup: profiles, frames, and the menu XML.
--- Order matters:
---   1. Profiles must load before any GUI XML that references them
---   2. Frame XMLs must load before the menu XML so FrameReference refs resolve
---   3. Menu XML loads last, linking everything together
--- Called from main.lua at end-of-file after all source() calls complete.
function RLMenu.setupGui()
    Log:debug("RLMenu.setupGui: begin")

    -- 1. Load RL menu profiles (separate file from gui/guiProfiles.xml)
    g_gui:loadProfiles(Utils.getFilename("gui/rlmenu/rlMenuProfiles.xml", modDirectory))

    -- 2. Register frames (Phase 1: Messages tab; Phase 2a: Info tab)
    RLMenuMessagesFrame.setupGui()
    RLMenuInfoFrame.setupGui()

    -- 3. Create the menu instance and load its XML
    g_rlMenu = RLMenu.new()
    g_gui:loadGui(
        Utils.getFilename("gui/rlmenu/rlMenu.xml", modDirectory),
        "RLMenu",
        g_rlMenu,
        false  -- false = full GUI (not a frame)
    )

    Log:debug("RLMenu.setupGui complete")
end

--- Called by TabbedMenu after all GUI XML has been parsed and bound.
--- Registers tabs with the Paging element.
function RLMenu:onGuiSetupFinished()
    Log:debug("RLMenu:onGuiSetupFinished: binding menu pages")
    RLMenu:superClass().onGuiSetupFinished(self)
    self:setupMenuPages()
end

--- Register each tab with the TabbedMenu Paging system and run its
--- per-instance initialize() on the clone. At this point
--- `self.messagesFrame` / `self.infoFrame` are the live clones produced
--- by Gui:resolveFrameReference. initialize() is optional on frames and
--- no-op when not overridden.
function RLMenu:setupMenuPages()
    local basePredicate = function() return g_currentMission ~= nil end

    -- Phase 1 Messages tab
    self:registerPage(self.messagesFrame, 1, basePredicate)
    self:addPageTab(self.messagesFrame, nil, nil, "rlExtra.notify_animal")
    if self.messagesFrame ~= nil and self.messagesFrame.initialize ~= nil then
        self.messagesFrame:initialize()
    end

    -- Phase 2a Info tab
    self:registerPage(self.infoFrame, 2, basePredicate)
    self:addPageTab(self.infoFrame, nil, nil, "rlExtra.info_animal")
    if self.infoFrame ~= nil and self.infoFrame.initialize ~= nil then
        self.infoFrame:initialize()
    end

    Log:debug("RLMenu:setupMenuPages: 2 pages registered (messages, info)")
end

--- Configure the bottom button bar.
--- Phase 0: ESC-only Back button; no toggle-to-close action. The footer shows
--- "ESC - Back" while the menu is open, matching every other FS25 tabbed menu.
function RLMenu:setupMenuButtonInfo()
    Log:debug("RLMenu:setupMenuButtonInfo: wiring back button")
    RLMenu:superClass().setupMenuButtonInfo(self)

    self.clickBackCallback = self:makeSelfCallback(self.onButtonBack)

    self.backButtonInfo = {
        inputAction = InputAction.MENU_BACK,
        text = g_i18n:getText("button_back"),
        callback = self.clickBackCallback,
    }

    self.defaultMenuButtonInfo = { self.backButtonInfo }
    self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK] = self.backButtonInfo
    self.defaultButtonActionCallbacks = {
        [InputAction.MENU_BACK] = self.clickBackCallback,
    }
end

--- Back button callback (ESC or clicking the Back footer button).
function RLMenu:onButtonBack()
    Log:debug("RLMenu:onButtonBack: closing menu via back")
    self:exitMenu()
end

--- Called by the GUI manager when the menu becomes visible.
--- Tracks open state for the open() no-op guard.
function RLMenu:onOpen()
    RLMenu:superClass().onOpen(self)
    self.isOpen = true
    Log:info("RLMenu opened")
end

--- Called by the GUI manager when the menu is closing.
--- Clears open state.
function RLMenu:onClose()
    RLMenu:superClass().onClose(self)
    self.isOpen = false
    Log:info("RLMenu closed")
end

--- Show the menu. No-op if any GUI is already visible to avoid stacking.
--- Invoked by the RL_MENU input action callback.
function RLMenu.open()
    if g_gui:getIsGuiVisible() then
        Log:trace("RLMenu.open: skipped, a GUI is already visible")
        return
    end
    Log:debug("RLMenu.open: showing menu")
    g_gui:showGui("RLMenu")
end

-- =============================================================================
-- INPUT BINDING
-- =============================================================================

--- Input action callback registered via PlayerInputComponent hook.
--- Called by FS25's input system when the user presses the key bound to RL_MENU.
--- @param playerInputComponent table The player input component (unused)
--- @param controlling string Input context ("VEHICLE", "PLAYER", etc.)
function RLMenu.addPlayerActionEvents(playerInputComponent, controlling)
    local triggerUp = false      -- Don't trigger on key release
    local triggerDown = true     -- Trigger on key press
    local triggerAlways = false  -- Not continuous
    local startActive = true     -- Active from start
    local callbackState = nil
    local disableConflictingBindings = true

    local success, actionEventId = g_inputBinding:registerActionEvent(
        RLMenu.ACTION_NAME,
        RLMenu,
        RLMenu.open,
        triggerUp, triggerDown, triggerAlways, startActive,
        callbackState, disableConflictingBindings
    )

    if not success then
        -- registerActionEvent has been observed to return false even when
        -- registration succeeded for the VEHICLE context. A non-empty
        -- actionEventId on failure usually means a duplicate registration (benign).
        if controlling == "VEHICLE" or (actionEventId ~= nil and actionEventId ~= "") then
            Log:trace("RLMenu.addPlayerActionEvents: registration returned false (controlling=%s, eventId=%s)",
                tostring(controlling), tostring(actionEventId))
        else
            Log:debug("RLMenu.addPlayerActionEvents: RL_MENU action NOT registered (controlling=%s)",
                tostring(controlling))
        end
        return
    end

    -- Hide the action event text from the HUD (we don't want a screen-edge hint)
    g_inputBinding:setActionEventTextVisibility(actionEventId, false)
    Log:debug("RLMenu.addPlayerActionEvents: RL_MENU action registered, eventId=%s",
        tostring(actionEventId))
end

--- Install the PlayerInputComponent and loadMap hooks.
--- Called once from main.lua at end-of-file before the TESTING block.
---
--- Two hooks installed:
---   1. PlayerInputComponent.registerGlobalPlayerActionEvents - so `RL_MENU` is
---      registered whenever a player input context is created.
---   2. RealisticLivestock.loadMap - defers `RLMenu.setupGui()` until AFTER
---      RealisticLivestock.loadMap has registered the `rlExtra` texture
---      config. Without this hook ordering, setupGui parses rlMenu.xml's
---      `imageSliceId="rlExtra.buy_animal"` before the texture namespace
---      exists, emitting `Warning: No texture config with prefix 'rlExtra'
---      found` at mod load. The warning was harmless in practice but noisy.
---      Hooking into loadMap resolves the ordering cleanly.
---
--- Idempotency: main.lua sources this file exactly once, so install() runs exactly once;
--- re-entry is not a supported scenario and would double-append both hooks.
function RLMenu.install()
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        RLMenu.addPlayerActionEvents
    )

    RealisticLivestock.loadMap = Utils.appendedFunction(
        RealisticLivestock.loadMap,
        RLMenu.setupGui
    )

    Log:debug("RLMenu.install: PlayerInputComponent + loadMap hooks installed")
end
