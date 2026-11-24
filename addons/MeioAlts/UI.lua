-- The character list: opens beside the Esc menu (where Logout is) and with /alts.
-- Two modes: "menu" follows GameMenuFrame (anchored, shown and hidden with it), "alone" is the
-- /alts window (movable, position in MeioAltsDB.pos, Esc closes it).
local _, A = ...

local ROW_H = 18
local PAD = 8 -- inside the inset
local TITLE_H = 24
local FRAME_PAD = 6 -- frame edge to inset
local MAIL_WARN_DAYS = 3
local RESTING_ICON = "|TInterface\\CharacterFrame\\UI-StateIcon:14:14:0:0:64:64:0:32:0:31|t"
local COLS = {
  { key = "name", label = "Character", w = 110, justify = "LEFT" },
  { key = "level", label = "Lvl", w = 26, justify = "RIGHT" },
  { key = "xp", label = "XP / rested", w = 120, justify = "CENTER" },
  { key = "money", label = "Gold", w = 96, justify = "RIGHT" },
  { key = "items", label = "Items", w = 80, justify = "RIGHT" },
  { key = "mail", label = "Mail", w = 96, justify = "RIGHT" },
  { key = "where", label = "Where", w = 128, justify = "LEFT", lead = 12 },
  { key = "seen", label = "Seen", w = 46, justify = "RIGHT" },
}
local GAP = 8
local PREFIX = "|cffb090ffMeioAlts:|r "

-- set in Create: COLS without Items when Meionomics isn't loaded
local cols, width
local frame, rows = nil, {}

local function Print(msg) print(PREFIX .. msg) end

local function Ago(t)
  local s = time() - t
  if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m" end
  if s < 86400 then return math.floor(s / 3600) .. "h" end
  return math.floor(s / 86400) .. "d"
end

local function Duration(s)
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return d .. "d " .. h .. "h" end
  if h > 0 then return h .. "h " .. m .. "m" end
  return m .. "m"
end

local function Gold(copper)
  return GetMoneyString(copper or 0, true)
end

-- Gold only: the columns stay narrow and alts' silver rarely matters at a glance
local function ShortGold(copper)
  if not copper or copper == 0 then return "" end
  if copper < 10000 then return GetMoneyString(copper, true) end
  return BreakUpLargeNumbers(math.floor(copper / 10000)) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
end

local function ClassColour(c)
  local col = c.class and RAID_CLASS_COLORS[c.class]
  return col and col:WrapTextInColorCode(c.name) or c.name
end

local function MailMoney(c)
  local m = A.Mail(c)
  return (m and m.money or 0) + (c.incoming and c.incoming.money or 0)
end

local function MailExpiring(c)
  local m = A.Mail(c)
  local e = m and m.count > 0 and m.expires
  return e and e - time() < MAIL_WARN_DAYS * 86400
end

local function MailText(c)
  local m = A.Mail(c)
  local money, items = MailMoney(c), (m and m.items or 0) + (c.incoming and c.incoming.items or 0)
  local text = money > 0 and ShortGold(money) or (items > 0 and items .. " items" or "")
  if MailExpiring(c) then text = "|cffff4040!|r " .. text end
  if c.newMail and A.IsMe(c) == false and text == "" then text = "|cff40c0ffnew|r" end
  return text
end

-- Meionomics (optional): what each character's items would sell for, from Syndicator's copy of
-- their bags, bank, gear, mail and auctions
local function Worth(c)
  local W = Meionomics and Meionomics.Worth
  if not W then return end
  local key = A.IsMe(c) and "me" or W.Find(c.name, c.realm)
  if not key then return end
  local ok, s = pcall(W.Summary, key)
  if ok and s and s.items > 0 then return s, key end
end

local function Sorted()
  local list = {}
  for _, c in pairs(A.db.chars) do list[#list + 1] = c end
  table.sort(list, function(a, b)
    if A.IsMe(a) ~= A.IsMe(b) then return A.IsMe(a) end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.name < b.name
  end)
  return list
end

local function RestedHidden() return HideRested and HideRested.IsHidden() end

local function RestedLines(tt, c)
  local rested, cap, hours = A.RestedNow(c)
  tt:AddDoubleLine("Rested", ("%s (%d%% of a level)"):format(BreakUpLargeNumbers(math.floor(rested)),
    rested / c.xpMax * 100), nil, nil, nil, 0.4, 0.6, 1)
  if rested >= cap then
    tt:AddDoubleLine(" ", "full: resting earns no more", nil, nil, nil, 1, 0.82, 0)
  elseif hours then
    local where = c.resting and "logged out resting" or "logged out outside an inn (quarter speed)"
    if A.IsMe(c) then where = "resting here" end
    tt:AddDoubleLine(" ", "full in " .. Duration(hours * 3600) .. ", " .. where, nil, nil, nil, 0.7, 0.7, 0.7)
  elseif A.IsMe(c) then
    tt:AddDoubleLine(" ", "log out in an inn or city to rest at full speed", nil, nil, nil, 0.7, 0.7, 0.7)
  end
end

local function Tooltip(row)
  local c = row.char
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_NONE")
  tt:AddLine(ClassColour(c))
  tt:AddLine(("Level %d %s %s"):format(c.level or 0, c.race or "", c.className or ""), 1, 1, 1)
  if c.guild then tt:AddLine("<" .. c.guild .. ">", 0.25, 1, 0.25) end
  tt:AddLine(c.realm, 0.6, 0.6, 0.6)
  tt:AddLine(" ")
  if not c.atMax and c.xpMax and c.xpMax > 0 then
    tt:AddDoubleLine("XP", ("%s / %s (%d%%)"):format(BreakUpLargeNumbers(c.xp),
      BreakUpLargeNumbers(c.xpMax), c.xp / c.xpMax * 100), nil, nil, nil, 1, 1, 1)
    if not RestedHidden() then RestedLines(tt, c) end
  end
  tt:AddDoubleLine("Gold", Gold(c.money), nil, nil, nil, 1, 1, 1)
  local worth = Worth(c)
  if worth then
    tt:AddDoubleLine("Items", Gold(worth.items), nil, nil, nil, 1, 1, 1)
    local parts = {}
    for _, place in ipairs(Meionomics.Worth.PLACES) do
      local p = worth[place]
      if p and p.value >= 10000 then
        parts[#parts + 1] = Meionomics.Worth.NAMES[place]:lower() .. " " .. ShortGold(p.value)
      end
    end
    if #parts > 0 then
      tt:AddDoubleLine(" ", table.concat(parts, ", "), nil, nil, nil, 0.7, 0.7, 0.7)
    end
    tt:AddDoubleLine("Worth", Gold(worth.items + (c.money or 0) + MailMoney(c)), nil, nil, nil, 1, 0.82, 0)
    tt:AddDoubleLine(" ", "click: every item and its price", nil, nil, nil, 0.5, 0.5, 0.5)
  end
  local m = A.Mail(c)
  if m and m.count > 0 then
    local line = ("%d mail, %d items"):format(m.count, m.items)
    if m.money > 0 then line = line .. ", " .. Gold(m.money) end
    tt:AddDoubleLine("Mail", line, nil, nil, nil, 1, 1, 1)
    if m.cod > 0 then tt:AddDoubleLine(" ", "COD to pay " .. Gold(m.cod), nil, nil, nil, 1, 0.5, 0.5) end
    if m.expires then
      local r, g, b = 0.7, 0.7, 0.7
      if MailExpiring(c) then r, g, b = 1, 0.25, 0.25 end
      tt:AddDoubleLine(" ", "first expires in " .. Duration(math.max(0, m.expires - time())), nil, nil, nil, r, g, b)
    end
    tt:AddDoubleLine(" ", "checked " .. Ago(m.at) .. " ago", nil, nil, nil, 0.5, 0.5, 0.5)
  end
  local inc = c.incoming
  if inc then
    local parts = {}
    if inc.money > 0 then parts[#parts + 1] = Gold(inc.money) end
    if inc.items > 0 then parts[#parts + 1] = inc.items .. " items" end
    tt:AddDoubleLine("Sent by your alts", table.concat(parts, ", "), nil, nil, nil, 1, 1, 1)
  end
  if c.newMail and not (m and m.at and c.seen and m.at >= c.seen) then
    tt:AddDoubleLine(" ", "new mail waiting, not opened yet", nil, nil, nil, 0.25, 0.75, 1)
  end
  tt:AddLine(" ")
  local where = c.zone or "?"
  if c.subzone and c.subzone ~= "" and c.subzone ~= c.zone then where = c.subzone .. ", " .. where end
  tt:AddDoubleLine("Location", where, nil, nil, nil, 1, 1, 1)
  if c.hearth then tt:AddDoubleLine("Hearth", c.hearth, nil, nil, nil, 1, 1, 1) end
  if c.bagTotal then
    local r, g = 1, 1
    if c.bagFree <= 3 then r, g = 1, 0.25 end
    tt:AddDoubleLine("Bags", ("%d free of %d"):format(c.bagFree, c.bagTotal), nil, nil, nil, r, g, g)
  end
  if c.durability then
    local r, g = 1, 1
    if c.durability < 0.3 then r, g = 1, 0.25 end
    tt:AddDoubleLine("Durability", ("%d%%"):format(c.durability * 100), nil, nil, nil, r, g, g)
  end
  if c.shards then tt:AddDoubleLine("Soul Shards", c.shards, nil, nil, nil, 1, 1, 1) end
  if c.professions and #c.professions > 0 then
    tt:AddLine(" ")
    for _, p in ipairs(c.professions) do
      tt:AddDoubleLine(p.name, ("%d / %d"):format(p.rank or 0, p.max or 0), nil, nil, nil, 1, 1, 1)
    end
  end
  tt:AddLine(" ")
  local played = A.PlayedNow(c)
  if played then tt:AddDoubleLine("Played", Duration(played), nil, nil, nil, 1, 1, 1) end
  if A.IsMe(c) then
    tt:AddDoubleLine("Last seen", "now", nil, nil, nil, 1, 1, 1)
  elseif c.seen then
    local seen = date("%d %b %H:%M", c.seen) --[[@as string]]
    tt:AddDoubleLine("Last seen", seen, nil, nil, nil, 1, 1, 1)
  end
  tt:Show()
  -- beside the window, level with the row, rather than over its close button. No room on
  -- the right (the list beside the game menu sits near the screen edge): below the window,
  -- else above it; never to the left, where the game menu buttons are
  local edge = PAD + FRAME_PAD + 4
  local fs, ts = frame:GetEffectiveScale(), tt:GetEffectiveScale()
  local screenR = UIParent:GetRight() * UIParent:GetEffectiveScale()
  tt:ClearAllPoints()
  if frame:GetRight() * fs + (tt:GetWidth() + edge) * ts <= screenR then
    tt:SetPoint("TOPLEFT", row, "TOPRIGHT", edge, 0)
  elseif frame:GetBottom() * fs - (tt:GetHeight() + 2) * ts >= 0 then
    tt:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
  else
    tt:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
  end
end

local function ShowWorth(row)
  local _, key = Worth(row.char)
  local ui = Meionomics and Meionomics.WorthUI
  if key and ui then ui.Show(key ~= "me" and key or nil, "all", frame) end
end

local function XPBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(12)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.5)
  bar.rested = bar:CreateTexture(nil, "BORDER")
  bar.rested:SetPoint("TOPLEFT")
  bar.rested:SetPoint("BOTTOMLEFT")
  bar.rested:SetColorTexture(0.25, 0.45, 1, 0.45)
  bar.xp = bar:CreateTexture(nil, "ARTWORK")
  bar.xp:SetPoint("TOPLEFT")
  bar.xp:SetPoint("BOTTOMLEFT")
  bar.xp:SetColorTexture(0.6, 0.25, 0.85, 0.85)
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER")
  return bar
end

local function SetFill(tex, width, fraction)
  tex:SetShown(fraction > 0)
  tex:SetWidth(math.max(1, width * math.min(1, fraction)))
end

local function SetXP(bar, c)
  local w = bar:GetWidth()
  if c.atMax or not c.xpMax or c.xpMax == 0 then
    bar.xp:Hide()
    bar.rested:Hide()
    bar.text:SetText("|cff999999max|r")
    return
  end
  local done = c.xp / c.xpMax
  SetFill(bar.xp, w, done)
  if RestedHidden() then
    bar.rested:Hide()
    bar.text:SetFormattedText("%d%%", done * 100)
    return
  end
  local restedFrac = A.RestedNow(c) / c.xpMax
  SetFill(bar.rested, w, done + restedFrac)
  bar.text:SetFormattedText("%d%%  |cff8fb4ff+%d%%|r", done * 100, restedFrac * 100)
end

local function Row(i)
  if rows[i] then return rows[i] end
  local row = CreateFrame("Button", nil, frame.Inset)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", PAD, -PAD - ROW_H * (i + 1))
  row:SetPoint("RIGHT", -PAD, 0)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.cells = {}
  local x = 0
  for _, col in ipairs(cols) do
    x = x + (col.lead or 0)
    if col.key == "xp" then
      local bar = XPBar(row)
      bar:SetPoint("LEFT", x, 0)
      bar:SetWidth(col.w)
      row.cells.xp = bar
    else
      local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", x, 0)
      fs:SetWidth(col.w)
      fs:SetJustifyH(col.justify)
      fs:SetWordWrap(false)
      row.cells[col.key] = fs
    end
    x = x + col.w + GAP
  end
  row:SetScript("OnEnter", Tooltip)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", ShowWorth)
  rows[i] = row
  return row
end

local function Refresh()
  if not (frame and frame:IsShown()) then return end
  frame.xpHeader:SetText(RestedHidden() and "XP" or "XP / rested")
  local list = Sorted()
  local total, mailTotal, itemTotal = 0, 0, 0
  for i, c in ipairs(list) do
    local row = Row(i)
    row.char = c
    local cells = row.cells
    cells.name:SetText(ClassColour(c))
    cells.level:SetText(c.level or "")
    SetXP(cells.xp, c)
    cells.money:SetText(ShortGold(c.money))
    local worth = Worth(c)
    if cells.items then cells.items:SetText(worth and ShortGold(worth.items) or "") end
    cells.mail:SetText(MailText(c))
    cells.where:SetText((c.resting and RESTING_ICON or "") .. (c.zone or ""))
    cells.seen:SetText(A.IsMe(c) and "|cff40ff40now|r" or (c.seen and Ago(c.seen) or ""))
    row:Show()
    total, mailTotal = total + (c.money or 0), mailTotal + MailMoney(c)
    itemTotal = itemTotal + (worth and worth.items or 0)
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  local text = "Total " .. Gold(total + mailTotal)
  if mailTotal > 0 then text = text .. "  |cff999999(" .. Gold(mailTotal) .. " in mail)|r" end
  if itemTotal > 0 then text = text .. "  + items " .. ShortGold(itemTotal) end
  frame.total:SetText(text)
  frame:SetSize(width, TITLE_H + FRAME_PAD + PAD * 2 + ROW_H * (#list + 2) + 4)
end

local scheduled
function A.Changed()
  if scheduled or not (frame and frame:IsShown()) then return end
  scheduled = true
  C_Timer.After(0, function()
    scheduled = false
    Refresh()
  end)
end

local function SavePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  A.db.pos = { point, relPoint, x, y }
end

local function PlaceAlone()
  frame:ClearAllPoints()
  local p = A.db.pos --[[@as any]]
  if p then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    frame:SetPoint("CENTER", 0, 120)
  end
end

local function Create()
  cols = {}
  local worth = Meionomics and Meionomics.Worth
  for _, col in ipairs(COLS) do
    if col.key ~= "items" or worth then cols[#cols + 1] = col end
  end
  width = (FRAME_PAD + PAD) * 2 - GAP
  for _, col in ipairs(cols) do width = width + (col.lead or 0) + col.w + GAP end

  frame = CreateFrame("Frame", "MeioAltsFrame", UIParent, "ButtonFrameTemplate")
  ButtonFrameTemplate_HidePortrait(frame)
  if frame.SetTitle then frame:SetTitle("MeioAlts") end
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  -- our own saved position; the client's layout cache would fight the beside-menu anchor
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if self.mode == "alone" then self:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.mode == "alone" then SavePosition() end
  end)
  -- Esc closes the /alts window; beside the game menu, Blizzard's Esc handler hides the menu
  -- first (and the list with it) before it gets round to special frames
  tinsert(UISpecialFrames, frame:GetName())
  frame.Inset:ClearAllPoints()
  frame.Inset:SetPoint("TOPLEFT", FRAME_PAD, -TITLE_H)
  frame.Inset:SetPoint("BOTTOMRIGHT", -FRAME_PAD, FRAME_PAD)

  local inset, x = frame.Inset, PAD
  for _, col in ipairs(cols) do
    x = x + (col.lead or 0)
    local fs = inset:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, -PAD)
    fs:SetWidth(col.w)
    fs:SetJustifyH(col.justify)
    fs:SetText(col.label)
    if col.key == "xp" then frame.xpHeader = fs end
    x = x + col.w + GAP
  end
  frame.total = inset:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  frame.total:SetPoint("TOPRIGHT", -PAD, -PAD - ROW_H)
  local hint = inset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", PAD, -PAD - ROW_H)
  hint:SetText("Hover a character for details")
  frame:SetScript("OnShow", Refresh)
  -- the live character's rested XP and times tick on
  frame:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t > 5 then
      self.t = 0
      Refresh()
    end
  end)
  frame:Hide()
end

-- Right of the menu; left of it when that would run off screen (clamping would push the list
-- over the menu); below it as a last resort
local function ShowBesideMenu()
  if not A.db or A.db.menu == false then return end
  frame.mode = "menu"
  frame:Show()
  local menuScale, scale = GameMenuFrame:GetEffectiveScale(), frame:GetEffectiveScale()
  local screenW = UIParent:GetWidth() * UIParent:GetEffectiveScale()
  local need = (frame:GetWidth() + 12) * scale
  frame:ClearAllPoints()
  if (GameMenuFrame:GetRight() or 0) * menuScale + need <= screenW then
    frame:SetPoint("LEFT", GameMenuFrame, "RIGHT", 12, 0)
  elseif (GameMenuFrame:GetLeft() or 0) * menuScale >= need then
    frame:SetPoint("RIGHT", GameMenuFrame, "LEFT", -12, 0)
  else
    frame:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -8)
  end
end

local function ShowAlone()
  frame.mode = "alone"
  PlaceAlone()
  frame:Show()
end

function A.Toggle()
  if frame:IsShown() then frame:Hide() else ShowAlone() end
end

function A.ResetPosition()
  A.db.pos = nil
  if frame and frame:IsShown() and frame.mode == "alone" then PlaceAlone() end
end

function A.SetMenu(on)
  A.db.menu = on
  Print("list beside the game menu " .. (on and "|cff80ff80on|r" or "|cffff8080off|r"))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  Create()
  if GameMenuFrame then
    GameMenuFrame:HookScript("OnShow", ShowBesideMenu)
    GameMenuFrame:HookScript("OnHide", function()
      if frame.mode == "menu" then frame:Hide() end
    end)
  end
  local ok, err = pcall(A.RegisterSettings)
  if not ok then geterrorhandler()(err) end
end)

-- minimap addon compartment (.toc AddonCompartmentFunc)
function MeioAlts_OnAddonCompartmentClick() A.Toggle() end

local function Now(on) return " (now " .. (on and "on" or "off") .. ")" end

local function Help()
  Print("every character's gold, mail, rested XP and more, in one list")
  for _, line in ipairs({
    "  |cffffd100/alts|r - open or close the list",
    "  |cffffd100/alts menu on||off|r - show the list beside the game menu (Esc)"
      .. Now(A.db.menu ~= false),
    "  |cffffd100/alts mail on||off|r - mailbox: alt picker beside To, Alt-click a bag item to "
      .. "attach it" .. Now(A.db.mail ~= false),
    "  |cffffd100/alts mailsend on||off|r - Alt-click also sends at once (to your alts, items "
      .. "only)" .. Now(A.db.mailSend == true),
    "  |cffffd100/alts forget Name[-Realm]|r - remove a character from the list",
    "  |cffffd100/alts reset|r - put the window back",
    "  Settings: Esc > Options > AddOns > MeioAlts (|cffffd100/alts settings|r)",
  }) do
    print(line)
  end
end

-- "on", "off", or nothing to flip
local function Switch(arg, current, set)
  local word = arg and arg:lower()
  if word == "on" then set(true)
  elseif word == "off" then set(false)
  else set(not current) end
end

SLASH_MEIOALTS1 = "/alts"
SlashCmdList.MEIOALTS = function(msg)
  local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
  cmd = cmd:lower()
  arg = arg and strtrim(arg)
  if cmd == "" then
    A.Toggle()
  elseif cmd == "menu" then
    Switch(arg, A.db.menu ~= false, A.SetMenu)
  elseif cmd == "mail" then
    Switch(arg, A.db.mail ~= false, A.SetMail)
  elseif cmd == "mailsend" then
    Switch(arg, A.db.mailSend == true, A.SetMailSend)
  elseif cmd == "forget" and arg and arg ~= "" then
    local key = A.Key(arg)
    if not key then
      Print("|cffff8080realm not known yet, try again in a moment|r")
    elseif key == A.myKey then
      Print("|cffff8080can't forget the character you're playing|r")
    elseif A.db.chars[key] then
      A.db.chars[key] = nil
      Print("forgot " .. key)
      A.Changed()
    else
      Print("|cffff8080no character " .. key .. "|r")
    end
  elseif cmd == "forget" then
    Print("which character? |cffffd100/alts forget Name|r or |cffffd100Name-Realm|r")
  elseif cmd == "reset" then
    A.ResetPosition()
    Print("window back in the middle of the screen")
  elseif cmd == "settings" or cmd == "options" then
    if not A.OpenSettings() then Help() end
  elseif cmd == "help" or cmd == "?" then
    Help()
  else
    Print(('unknown command "%s"'):format(cmd))
    Help()
  end
end
