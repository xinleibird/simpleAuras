-- Perf: cache globals
local floor, format = math.floor, string.format
local getn = table.getn
local unpack = unpack

-- Parent frame
local sAParent = CreateFrame("Frame", "sAParentFrame", UIParent)
sAParent:SetFrameStrata("BACKGROUND")
sAParent:SetAllPoints(UIParent)

function sA:ShouldAuraBeActive(aura, inCombat, inRaid, inParty)
  -- This check is now more robust and will correctly filter out new, empty auras.
  if not aura or not aura.name or aura.name == "" then return false end

  local enabled = (aura.enabled == nil or aura.enabled == 1)
  if not enabled then return false end

  local combatCheck = aura.inCombat == 1
  local outCombatCheck = aura.outCombat == 1
  local raidCheck = aura.inRaid == 1
  local partyCheck = aura.inParty == 1
  
  -- Rule: If no conditions are set at all, the aura should never be active.
  local anyConditionSet = combatCheck or outCombatCheck or raidCheck or partyCheck
  if not anyConditionSet then
      return false
  end

  -- Part 1: Evaluate Combat State requirement
  local combatStateOK = false
  local combatStateRequired = combatCheck or outCombatCheck
  if not combatStateRequired then
      -- If no combat condition is specified, it's considered met.
      combatStateOK = true
  else
      -- If a combat condition IS specified, check if it's met.
      if (combatCheck and inCombat) or (outCombatCheck and not inCombat) then
          combatStateOK = true
      end
  end

  -- Part 2: Evaluate Group State requirement
  local groupStateOK = false
  local groupStateRequired = raidCheck or partyCheck
  if not groupStateRequired then
      -- If no group condition is specified, it's considered met.
      groupStateOK = true
  else
      -- If a group condition IS specified, check if it's met.
      if (raidCheck and inRaid) or (partyCheck and inParty) then
          groupStateOK = true
      end
  end

  -- Final Decision: Both categories of conditions must be met.
  return combatStateOK and groupStateOK
end

-------------------------------------------------
-- Cooldown info by spell name
-------------------------------------------------
function sA:GetCooldownInfo(spellName)
  local i = 1
  while true do
    local name = GetSpellName(i, "spell")
    if not name then break end

    if name == spellName then
      local start, duration, enabled = GetSpellCooldown(i, "spell")
      local texture = GetSpellTexture(i, "spell")

      local remaining
      if enabled == 1 and duration and duration > 1.5 then
        remaining = (start + duration) - GetTime()
        if remaining <= 0 then remaining = nil end
      end

      return texture, remaining, 0
    end
    i = i + 1
  end
end

-------------------------------------------------
-- SuperWoW-aware aura search
-- spellID > 0  : match by spell ID first (more accurate)
-- spellID == 0 : fall back to name matching (legacy behaviour)
-------------------------------------------------
local function find_aura(name, spellID, unit, auratype, myCast)
  if auratype == "Distance" then return false end
  if auratype == "Enchant" then return false end
  local useSpellID = spellID and spellID > 0
  local found, foundstacks, foundsid, foundrem, foundtex
  local function search(is_debuff)
    local i = (unit == "Player") and 0 or 1
    while true do
      local tex, stacks, sid, rem
      if unit == "Player" then
        local buffType = is_debuff and "HARMFUL" or "HELPFUL"
        local bid = GetPlayerBuff(i, buffType)
        tex, stacks, sid, rem = GetPlayerBuffTexture(bid), GetPlayerBuffApplications(bid), GetPlayerBuffID(bid), GetPlayerBuffTimeLeft(bid)
      else
        if is_debuff then
          tex, stacks, caster, sid, rem = UnitDebuff(unit, i)
        else
          tex, stacks, sid, rem = UnitBuff(unit, i)
        end

      end

      if not tex then break end
      local matched = false
      if sid then
        if useSpellID then
          matched = (sid == spellID)
        else
          local infoName = SpellInfo(sid)
          if infoName and name and name ~= "" and name == infoName then
            matched = true
          end
        end
      end
      if matched then
		found, foundstacks, foundsid, foundrem, foundtex = 1, stacks, sid, rem, tex
		local _, unitGUID = UnitExists(unit)
		if unitGUID then unitGUID = gsub(unitGUID, "^0x", "") end
		if sA.auraTimers[unitGUID] and sA.auraTimers[unitGUID][sid] and sA.auraTimers[unitGUID][sid].castby and sA.auraTimers[unitGUID][sid].castby == sA.playerGUID
		or (unit == "Player") then
			return true, stacks, sid, rem, tex
		end
      end
      i = i + 1
    end
	if found == 1 and myCast == 0 then
		return true, foundstacks, foundsid, foundrem, foundtex
	end
    return false
  end

  local was_found, s, sid, rem, tex
  if auratype == "Buff" then
	was_found, s, sid, rem, tex = search(false)
  else
	was_found, s, sid, rem, tex = search(true)
	if not was_found then
		was_found, s, sid, rem, tex = search(false)
	end
  end
  
  return was_found, s, sid, rem, tex
end

-------------------------------------------------
-- Target condition evaluation (DoiteAuras-style)
--   Friendly/Hostile/Self: relation gate; when any is checked a target
--     must exist and match at least one selected relation.
--   Alive/Dead: status gate; UI keeps them exclusive, both set is a no-op.
-------------------------------------------------
function sA:TargetConditionPasses(aura)
  local wantHelp = aura.targetHelp == 1
  local wantHarm = aura.targetHarm == 1
  local wantSelf = aura.targetSelf == 1
  local wantAlive = aura.targetAlive == 1
  local wantDead = aura.targetDead == 1

  if not (wantHelp or wantHarm or wantSelf or wantAlive or wantDead) then
    return true
  end

  if not UnitExists("target") then return false end

  -- Relation gate
  if wantHelp or wantHarm or wantSelf then
    local isSelf = UnitIsUnit("player", "target") and true or false
    local isFriend = UnitIsFriend("player", "target") and true or false
    local canAttack = UnitCanAttack("player", "target") and true or false
    local ok = false
    if wantSelf and isSelf then ok = true end
    if not ok and wantHelp and isFriend and (not isSelf) then ok = true end
    if not ok and wantHarm and canAttack and (not isFriend) then ok = true end
    if not ok then return false end
  end

  -- Status gate
  if wantAlive and wantDead then
    return true
  elseif wantAlive or wantDead then
    local isDead = (UnitIsDead and UnitIsDead("target") == 1) and true or false
    if wantAlive then return not isDead end
    return isDead
  end

  return true
end

-------------------------------------------------
-- Distance condition evaluation (targetDistance-style)
-- Mirrors DoiteAuras' 7-value condition. Behaves conservatively:
--   - Behind/Front/BehindInRange/FrontInRange require UnitXP (SP3/Nampower);
--     when UnitXP is unavailable, do NOT show.
--   - InRange/OutOfRange use IsSpellInRange; nil result is treated as in-range
--     (matches Doite's lenient behaviour).
--   - Any / nil / unknown condition always passes.
-------------------------------------------------
function sA:DistanceConditionPasses(condition, name, spellID)
  if not condition or condition == "" or condition == "Any" then
    return true
  end

  local wantBehind, wantInRange
  if     condition == "InRange"      then wantInRange = true
  elseif condition == "OutOfRange"   then wantInRange = false
  elseif condition == "Behind"       then wantBehind  = true
  elseif condition == "Front"        then wantBehind  = false
  elseif condition == "BehindInRange"then wantBehind  = true;  wantInRange = true
  elseif condition == "FrontInRange" then wantBehind  = false; wantInRange = true
  else return true end

  local hasUnitXP = (type(UnitXP) == "function")

  -- Behind/Front requires UnitXP; if unavailable, do not show (per spec)
  if wantBehind ~= nil and not hasUnitXP then
    return false
  end

  -- Behind / Front check
  local behindOK = true
  if wantBehind ~= nil then
    if wantBehind then
      local ok, behind = pcall(UnitXP, "behind", "player", "target")
      behindOK = ok and (behind == true)
    else
      -- Front: not behind AND in sight
      local okB, behind   = pcall(UnitXP, "behind",  "player", "target")
      local okS, inSight  = pcall(UnitXP, "inSight", "player", "target")
      local notBehind = okB and (behind == false)
      local sightOK   = okS and (inSight ~= false)
      behindOK = notBehind and sightOK
    end
  end

  -- Range check (optional)
  local rangeOK = true
  if wantInRange ~= nil then
    local hasID   = (spellID and spellID > 0)
    local hasName = (name and name ~= "")
    if IsSpellInRange and (hasID or hasName) then
      local ok, res
      if hasID then
        ok, res = pcall(IsSpellInRange, spellID, "target")
      else
        ok, res = pcall(IsSpellInRange, name, "target")
      end
      if ok and (res == 1 or res == 0) then
        rangeOK = (wantInRange == (res == 1))
      else
        -- nil / error: treat as in-range (Doite lenient fallback)
        rangeOK = (wantInRange == true)
      end
    else
      -- No spell identifier and no IsSpellInRange → fall back to "in range"
      rangeOK = (wantInRange == true)
    end
  end

  return behindOK and rangeOK
end

-------------------------------------------------
-- Get Icon / Duration / Stacks (SuperWoW)
-------------------------------------------------
function sA:GetSuperAuraInfos(name, spellID, unit, auratype, myCast)
  if auratype == "Cooldown" then
    local texture, remaining_time = self:GetCooldownInfo(name)
    return _, texture, remaining_time, 1
  end

  local found, stacks, foundSpellID, remaining_time, texture = find_aura(name, spellID, unit, auratype, myCast)
  if not found then return end

  -- Fallback for missing remaining_time
  if (not remaining_time or remaining_time == 0) and foundSpellID and sA.auraTimers then
    local _, unitGUID = UnitExists(unit)
    if unitGUID then
      unitGUID = gsub(unitGUID, "^0x", "")
      local timers = sA.auraTimers[unitGUID]
      if timers and timers[foundSpellID] and timers[foundSpellID].duration then
        local expiry = timers[foundSpellID].duration
        remaining_time = (expiry > GetTime()) and (expiry - GetTime()) or 0
      end
    end
  end
  return foundSpellID, texture, remaining_time, stacks
end

-------------------------------------------------
-- Tooltip-based aura info (no SuperWoW)
-- spellID parameter accepted for API parity with GetSuperAuraInfos,
-- but ignored: vanilla 1.12 UnitBuff/UnitDebuff does not return spell IDs.
-------------------------------------------------
function sA:GetAuraInfos(auraname, spellID, unit, auratype)
  if auratype == "Cooldown" then
    local texture, remaining_time = self:GetCooldownInfo(auraname)
    return texture, remaining_time, 1
  end

  if not sAScanner then
    sAScanner = CreateFrame("GameTooltip", "sAScanner", sAParent, "GameTooltipTemplate")
    sAScanner:SetOwner(sAParent, "ANCHOR_NONE")
  end

  local function AuraInfo(unit, index, kind)
    sAScanner:ClearLines()

    local name, icon, duration, stacks
    if unit == "Player" then
      local buffindex = GetPlayerBuff(index - 1, (kind == "Buff") and "HELPFUL" or "HARMFUL")
      sAScanner:SetPlayerBuff(buffindex)
      icon, duration, stacks = GetPlayerBuffTexture(buffindex), GetPlayerBuffTimeLeft(buffindex), GetPlayerBuffApplications(buffindex)
    else
      if kind == "Buff" then
        sAScanner:SetUnitBuff(unit, index)
        icon = UnitBuff(unit, index)
      else
        sAScanner:SetUnitDebuff(unit, index)
        icon = UnitDebuff(unit, index)
      end
      duration = 0
    end
    name = sAScannerTextLeft1:GetText()
    return name, icon, duration, stacks
  end

  local i = 1
  while true do
    local name, icon, duration, stacks = AuraInfo(unit, i, auratype)
    if not name then break end
    if name == auraname then
      return icon, duration, stacks
    end
    i = i + 1
  end
end

-------------------------------------------------
-- Frame creation helpers
-------------------------------------------------
local FONT = "Fonts\\FRIZQT__.TTF"

local function CreateAuraFrame(id)
  local f = CreateFrame("Frame", "sAAura" .. id, UIParent)
  f:SetFrameStrata("BACKGROUND")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:SetUserPlaced(true) -- Tell WoW that this frame's position is managed by the user

  f.texture = f:CreateTexture(nil, "ARTWORK")
  f.texture:SetAllPoints(f)

  f.durationtext = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.durationtext:SetFont(FONT, 12, "OUTLINE")
  f.durationtext:SetPoint("CENTER", f, "CENTER", 0, 0)

  f.stackstext = f:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  f.stackstext:SetFont(FONT, 10, "OUTLINE")
  f.stackstext:SetPoint("TOPLEFT", f.durationtext, "CENTER", 1, -6)

  return f
end

local function CreateDualFrame(id)
  local f = CreateAuraFrame(id)
  f.texture:SetTexCoord(1, 0, 0, 1)
  f.stackstext:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  return f
end

local function CreateDraggerFrame(id, auraFrame)
  local dragger = CreateFrame("Frame", "sADragger" .. id, auraFrame)
  dragger:SetAllPoints(auraFrame)
  dragger:SetFrameStrata("HIGH")
  dragger:EnableMouse(true)
  dragger:RegisterForDrag("LeftButton")

  dragger:SetScript("OnDragStart", function(self)
    auraFrame:StartMoving()
  end)

  dragger:SetScript("OnDragStop", function(self)
    auraFrame:StopMovingOrSizing()
    
    -- We must calculate the offset from the screen's center because
    -- SetPoint uses a center-based coordinate system, while GetPoint
    -- returns coordinates from a corner anchor. This mismatch
    -- was causing auras to fly off-screen after being moved.
    local frameX, frameY = auraFrame:GetCenter()
    local screenWidth, screenHeight = GetScreenWidth(), GetScreenHeight()
    
    local offsetX = frameX - (screenWidth / 2)
    local offsetY = frameY - (screenHeight / 2)

    -- Round coordinates to prevent floating point issues in SavedVariables
    simpleAuras.auras[id].xpos = math.floor(offsetX + 0.5)
    simpleAuras.auras[id].ypos = math.floor(offsetY + 0.5)
	
	-- if gui.editor then
	  -- gui.editor:Hide()
	  -- gui.editor = nil
	  -- sA:EditAura(id)
	-- end
	
  end)
  
  -- Add a border to make it visible
  dragger:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  dragger:SetBackdropBorderColor(0, 1, 0, 0.5) -- Green, semi-transparent
  dragger:Hide()
  return dragger
end

local function CreateDualFrame(id)
  local f = CreateAuraFrame(id)
  f.texture:SetTexCoord(1, 0, 0, 1)
  f.stackstext:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  return f
end

-------------------------------------------------
-- Update aura display
-------------------------------------------------
function sA:UpdateAuras()

  if not sA.SettingsLoaded then return end

  -- hide test/editor when not editing
  if not (gui and gui.editor and gui.editor:IsVisible()) then
    if sA.TestAura     then sA.TestAura:Hide() end
    if sA.TestAuraDual then sA.TestAuraDual:Hide() end
    if gui and gui.editor then gui.editor:Hide(); gui.editor = nil end
  end

  -- Get the current player status once per cycle
  local hasTarget = UnitExists("target")
  local inCombat = UnitAffectingCombat("player")
  local inRaid = UnitInRaid("player")
  local inParty = GetNumPartyMembers() > 0 and not inRaid

  for id, aura in ipairs(simpleAuras.auras) do
    -- Add a guard clause to skip invalid/empty auras completely.
    -- This prevents errors when a new, unconfigured aura exists.
    if aura and aura.name then
      local show, icon, duration, stacks
      local currentDuration, currentStacks, currentDurationtext, spellID = 600, 20, "", nil

      local frame     = self.frames[id]     or CreateAuraFrame(id)
      local dualframe = self.dualframes[id] or (aura.dual == 1 and aura.type ~= "Cooldown" and aura.type ~= "Distance" and aura.type ~= "Enchant" and CreateDualFrame(id))
      local dragger   = self.draggers[id]   or CreateDraggerFrame(id, frame)
      self.frames[id] = frame
      self.draggers[id] = dragger
      if aura.dual == 1 and aura.type ~= "Cooldown" and aura.type ~= "Distance" and aura.type ~= "Enchant" then self.dualframes[id] = dualframe end
      
      local isEnabled = (aura.enabled == nil or aura.enabled == 1)
      local shouldShow

      if gui and gui:IsVisible() then
        -- SCENARIO 2 & 3: CONFIG or EDIT MODE
        -- Show all ENABLED auras, unless the editor is open for a DIFFERENT aura.
        shouldShow = isEnabled and not (gui.editor and gui.editor:IsVisible())
		
      else
	  
        -- SCENARIO 1: NORMAL GAMEPLAY MODE
        local conditionsMet = self:ShouldAuraBeActive(aura, inCombat, inRaid, inParty)
        show = 0 -- Default to not showing
        
        if conditionsMet then
          if aura.type == "Distance" then
            -- Distance type: independent path, requires a current target
            -- and a passing target condition (Friendly/Hostile/Self, Alive/Dead)
            if hasTarget and self:TargetConditionPasses(aura) then
              local passes = self:DistanceConditionPasses(
                aura.showDistance or aura.distanceCondition,
                aura.name, aura.spellID)
              show = passes and 1 or 0
            end
          elseif aura.type == "Enchant" then
            -- Enchant type: alert when weapon enchant is missing OR low on
            -- time OR low on charges (any checked trigger fires the icon).
            -- Icon = the weapon's own texture; duration/stacks text shown
            -- only when aura.duration / aura.stacks is enabled (existing gates).
            local slotID = (aura.enchantSlot == "OffHand") and 17 or 16
            local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", slotID)
            if tex then
              local hasEnchant, remMS, charges
              if sA.SuperWoW and GetEquippedItem then
                local info = GetEquippedItem("player", slotID)
                if info then
                  hasEnchant = info.tempEnchantId and info.tempEnchantId > 0
                  remMS = info.tempEnchantmentTimeLeftMs
                  charges = info.tempEnchantmentCharges
                  tex = tex or info.texture
                end
              end
              if hasEnchant == nil then
                local hMH, mhExpireMS, mhCharges, hOH, ohExpireMS, ohCharges = GetWeaponEnchantInfo()
                if slotID == 16 then
                  hasEnchant = hMH and hMH == 1
                  remMS = mhExpireMS
                  charges = mhCharges
                else
                  hasEnchant = hOH and hOH == 1
                  remMS = ohExpireMS
                  charges = ohCharges
                end
              end
              local present = hasEnchant and true or false
              icon = tex
              duration = (remMS or 0) / 1000
              stacks = charges or 0
              -- Guard against nil remaining/charges (some SuperWoW builds
              -- omit these fields); only alert when the value is actually
              -- known, so an unknown value does not fire the alert forever.
              local alert =
                   (aura.enchantAlertMissing    == 1 and not present)
                or (aura.enchantAlertLowTime    == 1 and present and remMS    ~= nil and remMS    <= (aura.enchantLowTime     or 0) * 1000)
                or (aura.enchantAlertLowCharges == 1 and present and charges   ~= nil and charges   <= (aura.enchantLowCharges or 0))
              show = alert and 1 or 0
            else
              -- No weapon in slot: nothing to alert about.
              show = 0
            end
          else
            -- Check for target existence if required by the aura
            local targetCheckPassed = (aura.unit ~= "Target" or hasTarget)

            if targetCheckPassed then
              -- Get aura data (icon indicates presence)
              if sA.SuperWoW then
                  spellID, icon, duration, stacks = self:GetSuperAuraInfos(aura.name, aura.spellID, aura.unit, aura.type, aura.myCast)
              else
                  icon, duration, stacks = self:GetAuraInfos(aura.name, aura.spellID, aura.unit, aura.type)
              end

              local auraIsPresent = icon and 1 or 0

              -- Apply inversion logic
              if aura.type == "Cooldown" then
                local onCooldown = duration and duration > 0
                show = (((aura.showCD == "No CD" or aura.showCD == "Always") and not onCooldown) or ((aura.showCD == "CD" or aura.showCD == "Always") and onCooldown)) and 1 or 0
              elseif aura.invert == 1 then
                show = 1 - auraIsPresent
              else
                show = auraIsPresent
              end
            end
          end
        end
        
        shouldShow = (show == 1)
		
      end
      
      -- This handles hiding the aura if the editor for it is open
      if gui.editor and gui.editor:IsVisible() then
          shouldShow = false
      end

      -- Defensive Stop for any glow attached to a frame we are about to hide.
      -- The block below re-shows + restarts the glow when shouldShow becomes
      -- true again.
      if not shouldShow and frame.glow and sA.Glow then
        sA.Glow.Stop(frame)
      end

      if shouldShow then
        -- Get fresh aura data only if we are going to show it
        if not (icon or aura.name) then -- Data might not have been fetched in /sa mode
		  spellID = nil
          if sA.SuperWoW then
            spellID, icon, duration, stacks = self:GetSuperAuraInfos(aura.name, aura.spellID, aura.unit, aura.type, aura.myCast)
          else
            icon, duration, stacks = self:GetAuraInfos(aura.name, aura.spellID, aura.unit, aura.type)
          end
        end

        if icon then
          currentDuration = duration
          currentStacks = stacks
          if aura.autodetect == 1 and aura.texture ~= icon then
              aura.texture, simpleAuras.auras[id].texture = icon, icon
          end
        end
        
        -------------------------------------------------
        -- Duration text
        -------------------------------------------------
        if aura.duration == 1 and currentDuration then
          if sA.SuperWoW and spellID and sA.learnNew[spellID] and sA.learnNew[spellID] == 1 then
			currentDurationtext = "learning"
          elseif currentDuration > 100 then
            currentDurationtext = floor(currentDuration / 60 + 0.5) .. "m"
		  elseif aura.lowduration == 1 and currentDuration <= (aura.lowdurationvalue or 5) then
            currentDurationtext = format("%.1f", floor(currentDuration * 10 + 0.5) / 10)
          else
            currentDurationtext = floor(currentDuration + 0.5)
          end
        end

        if currentDurationtext == "0.0" then
          currentDurationtext = 0
        end

        -------------------------------------------------
        -- Apply visuals
        -------------------------------------------------
        local scale = aura.scale or 1
		if currentDurationtext == "learning" then
			textscale = scale/2
		else
			textscale = scale
		end
        frame:SetPoint("CENTER", UIParent, "CENTER", aura.xpos or 0, aura.ypos or 0)
        frame:SetFrameLevel(128 - id)
        frame:SetWidth(48 * scale)
        frame:SetHeight(48 * scale)
        frame.texture:SetTexture(aura.type == "Enchant" and icon or aura.texture)
        frame.durationtext:SetText((aura.duration == 1 and (sA.SuperWoW or aura.unit == "Player" or aura.type == "Cooldown" or aura.type == "Enchant")) and currentDurationtext or "")
        frame.stackstext:SetText((aura.stacks == 1) and currentStacks or "")
        if aura.duration == 1 then frame.durationtext:SetFont(FONT, 20 * textscale, "OUTLINE") end
        if aura.stacks   == 1 then frame.stackstext:SetFont(FONT, 14 * scale, "OUTLINE") end

        local color = (aura.lowduration == 1 and currentDuration and currentDuration <= aura.lowdurationvalue)
          and (aura.lowdurationcolor or {1, 0, 0, 1})
          or  (aura.auracolor or {1, 1, 1, 1})

        local r, g, b, alpha = unpack(color)
        if aura.type == "Cooldown" and currentDuration then
          frame.texture:SetVertexColor(r * 0.5, g * 0.5, b * 0.5, alpha)
        else
          frame.texture:SetVertexColor(r, g, b, alpha)
        end

        local durationcolor = {1.0, 0.82, 0.0, alpha}
        local stackcolor    = {1, 1, 1, alpha}
        if aura.lowduration == 1
           and (sA.SuperWoW or aura.unit == "Player" or aura.type == "Cooldown" or aura.type == "Enchant")
           and currentDuration
           and currentDuration <= (aura.lowdurationvalue or 5)
           and currentDurationtext ~= "learning" then
          durationcolor = {1, 0, 0, alpha}
        end
        frame.durationtext:SetTextColor(unpack(durationcolor))
        frame.stackstext:SetTextColor(unpack(stackcolor))
        frame:Show()

        -------------------------------------------------
        -- Glow (ants) overlay
        -------------------------------------------------
        if aura.glow == 1 and sA.Glow then
          sA.Glow.Start(frame)
        elseif frame.glow then
          sA.Glow.Stop(frame)
        end

        -------------------------------------------------
        -- Dual frame
        -------------------------------------------------
        if aura.dual == 1 and aura.type ~= "Cooldown" and aura.type ~= "Distance" and aura.type ~= "Enchant" and dualframe then
          dualframe:SetPoint("CENTER", UIParent, "CENTER", -(aura.xpos or 0), aura.ypos or 0)
          dualframe:SetFrameLevel(128 - id)
          dualframe:SetWidth(48 * scale)
  		    dualframe:SetHeight(48 * scale)
          dualframe.texture:SetTexture(aura.texture)
          if aura.type == "Cooldown" and currentDuration then
            dualframe.texture:SetVertexColor(r * 0.5, g * 0.5, b * 0.5, alpha)
          else
            dualframe.texture:SetVertexColor(r, g, b, alpha)
          end
          dualframe.durationtext:SetText((aura.duration == 1 and (sA.SuperWoW or aura.unit == "Player" or aura.type == "Cooldown" or aura.type == "Enchant")) and currentDurationtext or "")
          dualframe.stackstext:SetText((aura.stacks == 1) and currentStacks or "")
          if aura.duration == 1 then dualframe.durationtext:SetFont(FONT, 20 * scale, "OUTLINE") end
          if aura.stacks   == 1 then dualframe.stackstext:SetFont(FONT, 14 * scale, "OUTLINE") end
          dualframe.durationtext:SetTextColor(unpack(durationcolor))
          dualframe:Show()
        elseif dualframe then
          dualframe:Hide()
        end
      else
        if frame     then frame:Hide()     end
        if dualframe then dualframe:Hide() end
      end
    else
      -- This is a new/empty aura, make sure its frame is hidden if it exists
      if self.frames[id] then
        if self.frames[id].glow and sA.Glow then sA.Glow.Stop(self.frames[id]) end
        self.frames[id]:Hide()
      end
      if self.dualframes[id] then self.dualframes[id]:Hide() end
    end
  end
end
