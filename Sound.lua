---------------------------------------------------------------
-- Sound.lua
-- Play .ogg sounds when aura icons appear or disappear.
-- Trigger rule (driven by aura.invert):
--   invert=0 -> play when aura becomes present (aura gain).
--   invert=1 -> play when aura becomes absent  (aura loss / Invert edge).
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
--   Buff/Debuff/Cooldown: icon ~= nil
--   Enchant:              alert
--   Distance:             passes
-- `aura.soundEnabled == 1` and `aura.sound ~= ""` are required.
-- Aura.invert selects which edge fires (gain vs loss).
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

  local isInvert = aura.invert == 1
  if not prev and st.active and not isInvert then
    Sound.Play(aura.sound)
  elseif prev and not st.active and isInvert then
    Sound.Play(aura.sound)
  end
end