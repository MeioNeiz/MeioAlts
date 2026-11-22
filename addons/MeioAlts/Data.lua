-- Records each character while it plays; the others are shown from what was saved at their
-- last logout. Addons can't run on the character select screen, hence the in-game list.
local _, A = ...

local SOUL_SHARD = 6265
local REST_PER_HOUR = 0.05 / 8 -- of a level bar, logged out in an inn or city; a quarter elsewhere
local REST_OUTSIDE = 0.25
A.REST_CAP = 1.5 -- of a level bar

local me
local events = CreateFrame("Frame")

local function MaxLevel()
  return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end

-- string.upper/lower only touch ASCII; names can start with or contain Latin-1 letters (É, ö),
-- two bytes in UTF-8 whose lower case is the upper case's second byte + 32
local function Lower(s)
  return (s:lower():gsub("\195([\128-\158])", function(b)
    if b ~= "\151" then return "\195" .. string.char(b:byte() + 32) end -- not ×
  end))
end

local function Capital(s)
  local first, rest = s:match("^([\1-\127\194-\244][\128-\191]*)(.*)$")
  if not first then return s end
  first = first:upper():gsub("^\195([\160-\190])", function(b)
    if b ~= "\183" then return "\195" .. string.char(b:byte() - 32) end -- not ÷
  end)
  return first .. Lower(rest)
end

-- The realm of the one playing, without spaces. Forever's GetRealmName and
-- GetNormalizedRealmName can answer "" at PLAYER_LOGIN: then the realm last seen for this
-- server id (Player-<id>-... GUID), remembered whenever the realm is known.
local function ServerID()
  local guid = UnitGUID("player")
  return guid and guid:match("^Player%-(%d+)%-")
end

local function RealmNow()
  local r = GetNormalizedRealmName and GetNormalizedRealmName()
  if r and r ~= "" then return r end
  r = GetRealmName and GetRealmName()
  if r and r ~= "" then return (r:gsub("%s", "")) end
end

function A.RealmKey()
  local r = RealmNow()
  local id = ServerID()
  local servers = A.db and A.db.servers
  if r then
    if servers and id then servers[id] = r end
    return r
  end
  return servers and id and servers[id]
end

-- "Name" or "Name-Realm" (any case, realm with or without spaces) to our key; nil while the
-- realm is unknown, so no character is ever keyed "Name-"
function A.Key(name, realm)
  if not name then return end
  local n, r = strsplit("-", name, 2)
  if not r or r == "" then r = realm end
  if not r or r == "" then r = A.RealmKey() end
  if not r or r == "" then return end
  return Capital(n) .. "-" .. r:gsub("%s", "")
end

-- Rested XP now: offline characters keep earning it, faster if they logged out resting
function A.RestedNow(c)
  if c.atMax or not c.xpMax or c.xpMax == 0 then return end
  local cap = A.REST_CAP * c.xpMax
  local rested, rate = c.rested or 0, 0
  if c == me then
    if c.resting then rate = REST_PER_HOUR * c.xpMax end
  else
    rate = REST_PER_HOUR * c.xpMax * (c.resting and 1 or REST_OUTSIDE)
    rested = rested + rate * (time() - (c.seen or time())) / 3600
  end
  rested = math.min(rested, cap)
  local hoursToFull = rate > 0 and (cap - rested) / rate or nil
  return rested, cap, hoursToFull
end

function A.IsMe(c) return c == me end

function A.PlayedNow(c)
  if not c.played then return end
  if c == me and c.playedAt then return c.played + time() - c.playedAt end
  return c.played
end

local function Bags(c)
  local get = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
  local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local free, total = 0, 0
  for bag = 0, NUM_BAG_SLOTS or 4 do
    local n, family = get(bag)
    if family == 0 then
      free, total = free + n, total + slots(bag)
    end
  end
  if total > 0 then c.bagFree, c.bagTotal = free, total end
end

local function Durability(c)
  local cur, max = 0, 0
  for slot = 1, 19 do
    local a, b = GetInventoryItemDurability(slot)
    if a and b then cur, max = cur + a, max + b end
  end
  c.durability = max > 0 and cur / max or nil
end

-- Forever has the retail API (no GetSkillLineInfo); GetProfessions leaves nil gaps
local function Professions(c)
  if not (GetProfessions and GetProfessionInfo) then return end
  local list, slots = {}, { GetProfessions() }
  for i = 1, select("#", GetProfessions()) do
    if slots[i] then
      local name, _, rank, maxRank = GetProfessionInfo(slots[i])
      if name then list[#list + 1] = { name = name, rank = rank, max = maxRank } end
    end
  end
  c.professions = list
end

-- UnitXPMax is 0 while the player isn't loaded (early login, logout), and level, money
-- and bags read wrong then too, so such a read keeps the last good values
local function Snapshot()
  local c = me
  c.seen = time()
  local xpMax = UnitXPMax("player")
  if not xpMax or xpMax == 0 then return end
  c.level = UnitLevel("player")
  c.atMax = c.level >= MaxLevel()
  c.xp, c.xpMax = UnitXP("player"), xpMax
  -- the real value even while HideRested hides it, or the projection would start from 0
  local rested = HideRested and HideRested.RealGetXPExhaustion or GetXPExhaustion
  c.rested = rested() or 0
  c.resting = IsResting() or nil
  c.money = GetMoney()
  c.zone, c.subzone = GetRealZoneText(), GetSubZoneText()
  c.hearth = GetBindLocation and GetBindLocation() or c.hearth
  c.guild = GetGuildInfo("player")
  c.newMail = HasNewMail and HasNewMail() or nil
  c.shards = c.class == "WARLOCK" and (C_Item and C_Item.GetItemCount or GetItemCount)(SOUL_SHARD) or nil
  Bags(c)
  Durability(c)
  A.Changed()
end

local pending
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    Snapshot()
  end)
end

-- Only while the mailbox is open: outside it the inbox reads as empty
local mailOpen
local function ScanInbox()
  local shown, total = GetInboxNumItems()
  local m = { money = 0, cod = 0, items = 0, count = total or shown, at = time() }
  for i = 1, shown do
    local _, _, _, _, money, cod, daysLeft, numItems = GetInboxHeaderInfo(i)
    m.money = m.money + (money or 0)
    m.cod = m.cod + (cod or 0)
    m.items = m.items + (numItems or 0)
    if daysLeft then
      local expires = time() + math.floor(daysLeft * 86400)
      if not m.expires or expires < m.expires then m.expires = expires end
    end
  end
  me.mail, me.incoming, me.newMail = m, nil, nil
  A.Changed()
end

-- Mail sent to our own characters, so theirs is known before they log in
local sending
hooksecurefunc("SendMail", function(recipient)
  local items = 0
  for i = 1, ATTACHMENTS_MAX_SEND or 12 do
    if GetSendMailItem(i) then items = items + 1 end
  end
  local cod = GetSendMailCOD and GetSendMailCOD() or 0
  sending = { key = A.Key(recipient), money = cod > 0 and 0 or GetSendMailMoney(), items = items }
end)

local function Sent()
  local s = sending
  sending = nil
  local alt = s and A.db.chars[s.key]
  if not alt or alt == me then return end
  local inc = alt.incoming or { money = 0, items = 0 }
  inc.money, inc.items = inc.money + s.money, inc.items + s.items
  alt.incoming = inc
  A.Changed()
end

-- /played for the tooltip, asked once at login unless MeioStats does it (it mutes chat the same
-- way). RequestTimePlayed prints to chat, so the chat frames stop listening until the reply.
local muted = {}
local function Unmute()
  for _, f in ipairs(muted) do f:RegisterEvent("TIME_PLAYED_MSG") end
  wipe(muted)
end

local function RequestPlayed()
  if MeioStats or not RequestTimePlayed or #muted > 0 then return end
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local f = _G["ChatFrame" .. i]
    if f and f:IsEventRegistered("TIME_PLAYED_MSG") then
      f:UnregisterEvent("TIME_PLAYED_MSG")
      muted[#muted + 1] = f
    end
  end
  C_Timer.After(10, Unmute)
  RequestTimePlayed()
end

local handlers = {
  PLAYER_LOGOUT = Snapshot,
  SKILL_LINES_CHANGED = function() Professions(me) end,
  TIME_PLAYED_MSG = function(total)
    me.played, me.playedAt = total, time()
    if #muted > 0 then C_Timer.After(0, Unmute) end
  end,
  MAIL_SHOW = function() mailOpen = true end,
  MAIL_CLOSED = function() mailOpen = false end,
  MAIL_INBOX_UPDATE = function() if mailOpen then ScanInbox() end end,
  MAIL_SEND_SUCCESS = Sent,
  MAIL_FAILED = function() sending = nil end,
}
for _, e in ipairs({
  "PLAYER_MONEY", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
  "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "HEARTHSTONE_BOUND",
  "PLAYER_GUILD_UPDATE", "UPDATE_PENDING_MAIL",
}) do
  handlers[e] = Soon
end

-- Before the realm fix, a login that read the realm as "" saved the character as "Name-"
-- beside its "Name-<realm>" entry: fold each into its twin (newer fields by seen, the larger
-- played), or re-key it to this realm when it has none
local function Merge(into, from)
  local newer, older = into, from
  if (from.seen or 0) > (into.seen or 0) then newer, older = from, into end
  local played = math.max(into.played or 0, from.played or 0)
  local realm = into.realm ~= "" and into.realm or from.realm
  local merged = {}
  for k, v in pairs(older) do merged[k] = v end
  for k, v in pairs(newer) do merged[k] = v end
  wipe(into)
  for k, v in pairs(merged) do into[k] = v end
  if played > 0 then into.played = played end
  into.realm = realm
end

local function MigrateBlankRealm(realm, realmName)
  local chars, blank = A.db.chars, {}
  for key in pairs(chars) do
    if key:match("%-$") then blank[#blank + 1] = key end
  end
  for _, key in ipairs(blank) do
    local name, c = key:sub(1, -2), chars[key]
    chars[key] = nil
    local twin
    for k, other in pairs(chars) do
      if k:match("^(.-)%-") == name then
        if twin then twin = false break end
        twin = other
      end
    end
    if twin then
      Merge(twin, c)
    else
      -- none, or one per realm: this realm, where it was most likely played
      if c.realm == "" then c.realm = realmName end
      local into = name .. "-" .. realm
      if chars[into] then Merge(chars[into], c) else chars[into] = c end
    end
  end
end

-- the realm from a saved character with this name, when exactly one has one
local function RealmFromTwin(name)
  local found
  for key in pairs(A.db.chars) do
    local n, r = key:match("^(.-)%-(.+)$")
    if n == name then
      if found then return end
      found = r
    end
  end
  return found
end

local function Start(realm)
  local name = UnitName("player")
  local realmName = GetRealmName()
  if not realmName or realmName == "" then
    realmName = nil
    for key, c in pairs(A.db.chars) do
      if key:match("%-(.+)$") == realm and c.realm and c.realm ~= "" then
        realmName = c.realm
        break
      end
    end
  end
  MigrateBlankRealm(realm, realmName or realm)
  A.myKey = A.Key(name, realm)
  me = A.db.chars[A.myKey] or {}
  A.db.chars[A.myKey] = me
  me.name = name
  me.realm = realmName or (me.realm ~= "" and me.realm) or realm
  me.race = UnitRace("player")
  me.className, me.class = UnitClass("player")
  me.faction = UnitFactionGroup("player")
  for e in pairs(handlers) do events:RegisterEvent(e) end
  Snapshot()
  Professions(me)
  C_Timer.After(5, RequestPlayed)
  A.Changed()
end

-- realm still unknown at login: wait for it (a second at a time, a minute at most)
local function StartWhenRealmKnown(tries)
  local realm = A.RealmKey() or (tries == 0 and RealmFromTwin(UnitName("player")))
  if realm then return Start(realm) end
  if tries < 60 then C_Timer.After(1, function() StartWhenRealmKnown(tries + 1) end) end
end

events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    MeioAltsDB = MeioAltsDB or {}
    MeioAltsDB.chars = MeioAltsDB.chars or {}
    MeioAltsDB.servers = MeioAltsDB.servers or {}
    A.db = MeioAltsDB
    StartWhenRealmKnown(0)
    return
  end
  handlers[event](...)
end)
