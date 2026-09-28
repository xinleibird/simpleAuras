---------------------------------------------------------------
-- Sound.lua
-- Play .ogg sounds when aura icons appear or disappear.
-- Trigger rules:
--   invert=0 -> play when aura becomes present (aura gain).
--   invert=1 -> play when aura becomes absent  (aura loss / Invert edge).
--   Cooldown (no invert option in the editor) -> play only when the
--   icon appears, i.e. the CD state flip that shows it (showCD="No CD"
--   fires on CD end, showCD="CD" fires on CD start, showCD="Always"
--   never fires because the icon never changes state).
-- Edge-detected via per-aura state table; first observation per
-- aura is suppressed so login / ReloadUI does not play anything.
-- WoW 1.12 | Lua 5.0
---------------------------------------------------------------

local Sound = {}
sA.Sound = Sound

local _State = {}  -- [auraID] = { active = bool }
local PLAY_PREFIX = "Interface\\AddOns\\simpleAuras\\Sounds\\"

-- Resolve and play a sound file by basename. Silent no-op if
-- the name is empty or PlaySoundFile is unavailable; pcall wraps
-- the call so a missing/corrupt file cannot break the addon.
function Sound.Play(fileName)
  if not fileName or fileName == "" then return end
  if not PlaySoundFile then return end
  pcall(PlaySoundFile, PLAY_PREFIX .. fileName)
end

-- Edge-trigger sound on aura state transitions. `isActive` is the
-- current aura "presence" boolean:
--   Buff/Debuff: icon ~= nil
--   Cooldown:    icon is visible (show == 1)
--   Enchant:     alert
--   Distance:    passes
-- `aura.soundEnabled == 1` and `aura.sound ~= ""` are required.
-- aura.invert selects which edge fires; Cooldown fires on the gain
-- edge only because its invert option is hidden in the editor.
function Sound.HandleStateChange(auraID, isActive, aura)
  if not auraID or not aura then return end
  if not aura.soundEnabled or aura.soundEnabled ~= 1 then return end
  if not aura.sound or aura.sound == "" then return end

  local st = _State[auraID]
  if not st then
    _State[auraID] = { active = isActive and true or false }
    return
  end
  local prev = st.active
  st.active = isActive and true or false
  if prev == nil then return end
  if prev == st.active then return end

  local isCooldown = aura.type == "Cooldown"
  local isInvert = aura.invert == 1
  if not prev and st.active then
    -- gain edge: the icon just appeared
    if isCooldown or not isInvert then
      Sound.Play(aura.sound)
    end
  elseif prev and not st.active then
    -- loss edge: the icon just disappeared
    if not isCooldown and isInvert then
      Sound.Play(aura.sound)
    end
  end
end