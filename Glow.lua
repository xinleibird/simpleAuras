---------------------------------------------------------------
-- Glow.lua
-- Glow overlay for aura frames: static border backdrop (IconAlert)
-- plus animated ants line (IconAlertAnts).
-- Animation runs on the overlay's own OnUpdate at 0.04 s/frame
-- (25 fps, full cycle ~0.88 s) - same speed as DoiteAuras,
-- independent of the simpleAuras refresh rate.
-- Adapted from DoiteAuras' DoiteGlow.lua; pfUI dependencies removed.
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local Glow = {}
sA.Glow = Glow

-- 5x5 grid of texCoord slices for IconAlertAnts.tga
local texCoords = {
  { 0.0078, 0.1796, 0.0039, 0.1757 }, { 0.1953, 0.3671, 0.0039, 0.1757 }, { 0.3828, 0.5546, 0.0039, 0.1757 }, { 0.5703, 0.7421, 0.0039, 0.1757 }, { 0.7578, 0.9296, 0.0039, 0.1757 },
  { 0.0078, 0.1796, 0.1914, 0.3632 }, { 0.1953, 0.3671, 0.1914, 0.3632 }, { 0.3828, 0.5546, 0.1914, 0.3632 }, { 0.5703, 0.7421, 0.1914, 0.3632 }, { 0.7578, 0.9296, 0.1914, 0.3632 },
  { 0.0078, 0.1796, 0.3789, 0.5507 }, { 0.1953, 0.3671, 0.3789, 0.5507 }, { 0.3828, 0.5546, 0.3789, 0.5507 }, { 0.5703, 0.7421, 0.3789, 0.5507 }, { 0.7578, 0.9296, 0.3789, 0.5507 },
  { 0.0078, 0.1796, 0.5664, 0.7382 }, { 0.1953, 0.3671, 0.5664, 0.7382 }, { 0.3828, 0.5546, 0.5664, 0.7382 }, { 0.5703, 0.7421, 0.5664, 0.7382 }, { 0.7578, 0.9296, 0.5664, 0.7382 },
  { 0.0078, 0.1796, 0.7539, 0.9257 }, { 0.1953, 0.3671, 0.7539, 0.9257 }, { 0.3828, 0.5546, 0.7539, 0.9257 }, { 0.5703, 0.7421, 0.7539, 0.9257 }, { 0.7578, 0.9296, 0.7539, 0.9257 }
}

local pool = {}
local numOverlays = 0
-- cycle frames 1..22 then back to 1 (Doite convention)
local NUM_FRAMES = 22
-- seconds per animation frame (Doite value; 22-frame cycle ~0.88 s)
local updateInterval = 0.04

local function NextIndex(i)
  if i >= NUM_FRAMES then return 1 end
  return i + 1
end

local function GetOverlay()
  local overlay = table.remove(pool)
  if not overlay then
    numOverlays = numOverlays + 1
    overlay = CreateFrame("Frame", "sAGlowOverlay" .. numOverlays)

    -- Static glowing border backdrop (under the animated ants)
    overlay.bg = overlay:CreateTexture(nil, "ARTWORK")
    overlay.bg:SetTexture("Interface\\AddOns\\simpleAuras\\Textures\\IconAlert")
    overlay.bg:SetTexCoord(0.0546, 0.4609, 0.3007, 0.5039)
    overlay.bg:SetAllPoints(overlay)

    overlay.glow = overlay:CreateTexture(nil, "OVERLAY")
    overlay.glow:SetTexture("Interface\\AddOns\\simpleAuras\\Textures\\IconAlertAnts")
    overlay.glow:SetAllPoints(overlay)
    overlay.glow:SetBlendMode("ADD")
  end
  return overlay
end

-- Attach the glow overlay to the aura frame and start the ants
-- animation. Called from UpdateAuras when aura.glow == 1 and the
-- aura frame is being shown. Idempotent: returns immediately when
-- the overlay is already attached. The animation itself runs on
-- the overlay's own OnUpdate (0.04 s per frame).
function Glow.Start(frame)
  if not frame or frame.glow then return end
  local overlay = GetOverlay()
  overlay:SetParent(frame)
  overlay:SetFrameStrata(frame:GetFrameStrata())
  overlay:SetAllPoints(frame)
  overlay.index = 1
  overlay.lastUpdated = 0
  frame.glow = overlay
  overlay:Show()

  overlay:SetScript("OnUpdate", function()
    overlay.lastUpdated = overlay.lastUpdated + arg1
    if overlay.lastUpdated > updateInterval then
      overlay.index = NextIndex(overlay.index)
      local tc = texCoords[overlay.index]
      overlay.glow:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      overlay.lastUpdated = 0
    end
  end)
end

-- Detach the overlay, stop the animation and return it to the
-- pool. Safe to call when no overlay is attached.
function Glow.Stop(frame)
  if not frame or not frame.glow then return end
  local overlay = frame.glow
  overlay:SetScript("OnUpdate", nil)
  frame.glow = nil
  overlay:Hide()
  overlay:SetParent(UIParent)
  table.insert(pool, overlay)
end