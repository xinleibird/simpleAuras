---------------------------------------------------------------
-- Sound.lua
-- Play .ogg sounds when aura icons appear or disappear.
-- Trigger rules:
--   invert=0 -> play when aura becomes present (aura gain).
--   invert=1 -> play when aura becomes absent  (aura loss / Invert edge).
--   Types whose Invert option is hidden in the editor (Cooldown,
--   Enchant, Distance) -> play only when the icon appears, ignoring
--   aura.invert (a stale invert=1 left in saved data must not gate
--   the trigger the user cannot see):
--     Cooldown: showCD="No CD" fires on CD end, showCD="CD" fires on
--     CD start, showCD="Always" never fires (icon state never flips).
--     Enchant:  fires when the alert appears (missing/low enchant).
--     Distance: fires when the distance condition starts passing.
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
-- aura.invert selects which edge fires, except for types without an
-- Invert option in the editor (Cooldown/Enchant/Distance), which
-- always fire on the gain edge (icon appears) only.
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

  -- Types that hide the Invert checkbox in the editor: their saved
  -- aura.invert may hold a stale value the user cannot see or clear,
  -- so it must not gate the trigger. These always fire on icon
  -- appearance (gain edge) and never on icon disappearance.
  local noInvert = aura.type == "Cooldown"
                or aura.type == "Enchant"
                or aura.type == "Distance"
  local isInvert = aura.invert == 1
  if not prev and st.active then
    -- gain edge: the icon just appeared
    if noInvert or not isInvert then
      Sound.Play(aura.sound)
    end
  elseif prev and not st.active then
    -- loss edge: the icon just disappeared
    if not noInvert and isInvert then
      Sound.Play(aura.sound)
    end
  end
end