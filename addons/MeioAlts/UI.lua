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
  { key = "level", label = "Lvl", menu = "Level", w = 26, justify = "RIGHT" },
  { key = "xp", label = "XP / rested", menu = "XP and rested", w = 120, justify = "CENTER" },
  { key = "money", label = "Gold", w = 96, justify = "RIGHT" },
  { key = "items", label = "Items", w = 80, justify = "RIGHT" },
  { key = "mail", label = "Mail", w = 96, justify = "RIGHT" },
  { key = "where", label = "Where", w = 128, justify = "LEFT", lead = 12 },
  { key = "seen", label = "Seen", w = 46, justify = "RIGHT" },
}
local GAP = 8
local MIN_W = 220
local PREFIX = "|cffb090ffMeioAlts:|r "

-- set in Create: COLS without Items when Meionomics isn't loaded; x and width in Layout
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

-- here[c]: same realm and faction as the one playing, so its gold can be mailed over
local here = {}

local function Sorted()
  local list = {}
  here = {}
  for key, c in pairs(A.db.chars) do
    here[c] = A.SameGroup(key, c)
    if here[c] or A.db.elsewhere ~= false then list[#list + 1] = c end
  end
  table.sort(list, function(a, b)
    if A.IsMe(a) ~= A.IsMe(b) then return A.IsMe(a) end
    if here[a] ~= here[b] then return here[a] end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.name < b.name
  end)
  for _, o in ipairs(A.Others()) do list[#list + 1] = o end
  return list
end

local function GroupName(c)
  local mine = A.db.chars[A.myKey]
  if here[c] and mine then c = mine end
  return (c.realm or "?") .. ", " .. (c.faction or "faction unknown")
end

-- Gold and mailed gold per realm and faction; this one first
local function Groups()
  local sums, order = {}, {}
  for _, c in pairs(A.db.chars) do
    local name = GroupName(c)
    if not sums[name] then
      sums[name] = { name = name, here = here[c], money = 0 }
      order[#order + 1] = sums[name]
    end
    sums[name].money = sums[name].money + (c.money or 0) + MailMoney(c)
  end
  table.sort(order, function(a, b)
    if a.here ~= b.here then return a.here end
    return a.name < b.name
  end)
  return order
end

local function RestedHidden() return HideRested and HideRested.IsHidden() end

local function RestedLines(tt, c)
  local rested, cap, hours = A.RestedNow(c)
  tt:AddDoubleLine("Rested", ("%s (%d%% of a level)"):format(BreakUpLargeNumbers(math.floor(rested)),
    rested / c.xpMax * 100), nil, nil, nil, 0.4, 0.6, 1)
  if A.WellRestedBoost(c) > 0 then
    tt:AddDoubleLine(" ", ("Well Rested %d/%d: faster, cap %d%%"):format(c.wellRested,
      c.wellRestedMax, cap / c.xpMax * 100 + 0.5), nil, nil, nil, 0.7, 0.7, 0.7)
  end
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

-- beside the window, level with the row, rather than over its close button. No room on the
-- right (the list beside the game menu sits near the screen edge): below the window, else
-- above it; never to the left, where the game menu buttons are
local function PlaceTooltip(tt, row)
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

local function TotalTooltip(self)
  local groups = Groups()
  local tt = GameTooltip
  tt:SetOwner(self, "ANCHOR_NONE")
  tt:AddLine("Gold you can mail between characters")
  local all = 0
  for i, g in ipairs(groups) do
    if i == 2 then tt:AddLine("Other realm or faction: mail can't reach these", 0.7, 0.7, 0.7) end
    local shade = g.here and 1 or 0.7
    tt:AddDoubleLine(g.name, Gold(g.money), shade, shade, shade, 1, 1, 1)
    all = all + g.money
  end
  if #groups > 1 then
    tt:AddDoubleLine("All characters", Gold(all), 1, 0.82, 0, 1, 1, 1)
    local word = A.db.elsewhere == false and "show" or "hide"
    tt:AddLine("/alts elsewhere " .. (word == "show" and "on" or "off") .. " to " .. word
      .. " the others in the list", 0.5, 0.5, 0.5)
  end
  tt:AddLine("Counts gold in mail too", 0.5, 0.5, 0.5)
  tt:Show()
  PlaceTooltip(tt, self)
end

local function OtherTooltip(tt, o)
  tt:AddLine(o.name)
  tt:AddLine(o.realm, 0.6, 0.6, 0.6)
  tt:AddLine("Your character on another WoW account", 1, 1, 1)
  tt:AddLine(" ")
  local grey = 0.7
  tt:AddLine("Added by name. Addons can't read another account's saved data, so there "
    .. "is no gold, rested XP or mail to show.", grey, grey, grey, true)
  tt:AddLine("At the mailbox it's in the To picker, under Other account.", grey, grey, grey,
    true)
  tt:AddLine(" ")
  tt:AddLine("/alts remove " .. o.name .. " takes it off", 0.5, 0.5, 0.5)
end

local function Tooltip(row)
  local c = row.char
  local tt = GameTooltip
  tt:SetOwner(row, "ANCHOR_NONE")
  if c.other then
    OtherTooltip(tt, c)
    tt:Show()
    PlaceTooltip(tt, row)
    return
  end
  tt:AddLine(ClassColour(c))
  tt:AddLine(("Level %d %s %s"):format(c.level or 0, c.race or "", c.className or ""), 1, 1, 1)
  if c.guild then tt:AddLine("<" .. c.guild .. ">", 0.25, 1, 0.25) end
  tt:AddLine(c.realm, 0.6, 0.6, 0.6)
  if not here[c] then
    tt:AddLine("Other realm or faction: mail can't reach it from here", 1, 0.5, 0.25, true)
  end
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
  if c.legacyPoints and c.legacyPoints > 0 then
    tt:AddDoubleLine("Legacy points", c.legacyPoints .. " to spend", nil, nil, nil, 0.4, 1, 0.4)
  end
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
  PlaceTooltip(tt, row)
end

local function ShowWorth(row)
  if row.char.other then return end
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

local function Shown(key) return key == "name" or not A.db.hidden[key] end

local function PlaceCells(row)
  for _, col in ipairs(cols) do
    local cell = row.cells[col.key]
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", col.x, 0)
  end
  local name = cols[1]
  local x = name.x + name.w + GAP
  row.note:ClearAllPoints()
  row.note:SetPoint("LEFT", x, 0)
  row.note:SetWidth(width - (FRAME_PAD + PAD) * 2 - x)
end

-- Hidden columns take no room: the window narrows to what's left
local function Layout()
  local x = 0
  for _, col in ipairs(cols) do
    col.x = x + (col.lead or 0)
    frame.headers[col.key]:SetShown(Shown(col.key))
    if Shown(col.key) then
      frame.headers[col.key]:SetPoint("TOPLEFT", PAD + col.x, -PAD)
      x = col.x + col.w + GAP
    end
  end
  width = math.max(MIN_W, (FRAME_PAD + PAD) * 2 + x - GAP)
  for _, row in ipairs(rows) do PlaceCells(row) end
end

local function Row(i)
  if rows[i] then return rows[i] end
  local row = CreateFrame("Button", nil, frame.Inset)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", PAD, -PAD - ROW_H * (i + 1))
  row:SetPoint("RIGHT", -PAD, 0)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.cells = {}
  for _, col in ipairs(cols) do
    if col.key == "xp" then
      local bar = XPBar(row)
      bar:SetWidth(col.w)
      row.cells.xp = bar
    else
      local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fs:SetWidth(col.w)
      fs:SetJustifyH(col.justify)
      fs:SetWordWrap(false)
      row.cells[col.key] = fs
    end
  end
  row.note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.note:SetJustifyH("LEFT")
  row.note:SetWordWrap(false)
  row.note:SetText("other account: name only")
  row:SetScript("OnEnter", Tooltip)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", ShowWorth)
  rows[i] = row
  PlaceCells(row)
  return row
end

-- Returns what the character's items are worth, when Meionomics knows
local function FillRow(cells, c)
  cells.name:SetText(ClassColour(c))
  cells.level:SetText(c.level or "")
  SetXP(cells.xp, c)
  cells.money:SetText(ShortGold(c.money))
  local worth = Worth(c)
  if cells.items then cells.items:SetText(worth and ShortGold(worth.items) or "") end
  cells.mail:SetText(MailText(c))
  cells.where:SetText((c.resting and RESTING_ICON or "") .. (c.zone or ""))
  cells.seen:SetText(A.IsMe(c) and "|cff40ff40now|r" or (c.seen and Ago(c.seen) or ""))
  return worth
end

local function Refresh()
  if not (frame and frame:IsShown()) then return end
  frame.xpHeader:SetText(RestedHidden() and "XP" or "XP / rested")
  local list = Sorted()
  local total, mailTotal, itemTotal = 0, 0, 0
  for i, c in ipairs(list) do
    local row = Row(i)
    row.char = c
    for key, cell in pairs(row.cells) do cell:SetShown(not c.other and Shown(key)) end
    row.cells.name:Show()
    row.note:SetShown(c.other == true)
    row:Show()
    row:SetAlpha((c.other or here[c]) and 1 or 0.6)
    if c.other then
      row.cells.name:SetText("|cff808080" .. c.name .. "|r")
    else
      local worth = FillRow(row.cells, c)
      if here[c] then
        total, mailTotal = total + (c.money or 0), mailTotal + MailMoney(c)
        itemTotal = itemTotal + (worth and worth.items or 0)
      end
    end
  end
  local label = "Total "
  for _, c in pairs(A.db.chars) do
    if not here[c] then label = "Total here " break end
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  local items = itemTotal > 0 and "  + items " .. ShortGold(itemTotal) or ""
  local text = label .. Gold(total + mailTotal)
  if mailTotal > 0 then text = text .. "  |cff999999(" .. Gold(mailTotal) .. " in mail)|r" end
  frame.total:SetText(text .. items)
  -- a narrow window: whole gold only, and the hint gives way
  local room = width - (FRAME_PAD + PAD) * 2
  if frame.total:GetStringWidth() > room then
    frame.total:SetText(label .. ShortGold(total + mailTotal) .. items)
  end
  frame.hint:SetShown(frame.hint:GetStringWidth() + frame.total:GetStringWidth() + 12 <= room)
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
  A.db.hidden = A.db.hidden or {}

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

  local inset = frame.Inset
  frame.headers = {}
  for _, col in ipairs(cols) do
    local fs = inset:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    fs:SetWidth(col.w)
    fs:SetJustifyH(col.justify)
    fs:SetText(col.label)
    frame.headers[col.key] = fs
    if col.key == "xp" then frame.xpHeader = fs end
  end
  local heads = CreateFrame("Button", nil, inset)
  heads:SetPoint("TOPLEFT", PAD, -PAD + 2)
  heads:SetPoint("RIGHT", -PAD, 0)
  heads:SetHeight(ROW_H - 2)
  heads:RegisterForClicks("RightButtonUp")
  heads:SetScript("OnClick", function(self) A.ColumnMenu(self) end)
  heads:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Right-click: choose which columns show")
    GameTooltip:Show()
  end)
  heads:SetScript("OnLeave", GameTooltip_Hide)
  frame.heads = heads
  frame.total = inset:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  frame.total:SetPoint("TOPRIGHT", -PAD, -PAD - ROW_H)
  local totalHover = CreateFrame("Frame", nil, inset)
  totalHover:SetAllPoints(frame.total)
  totalHover:EnableMouse(true)
  totalHover:SetScript("OnEnter", TotalTooltip)
  totalHover:SetScript("OnLeave", GameTooltip_Hide)
  frame.totalHover = totalHover
  frame.hint = inset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  frame.hint:SetPoint("TOPLEFT", PAD, -PAD - ROW_H)
  frame.hint:SetText("Hover a character for details")
  Layout()
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

function A.SetElsewhere(on)
  A.db.elsewhere = on
  Print("characters on another realm or faction in the list "
    .. (on and "|cff80ff80shown|r" or "|cffff8080hidden|r") .. " (the total counts this "
    .. "realm and faction only)")
  A.Changed()
end

function A.SetColumn(key, on)
  A.db.hidden[key] = not on or nil
  Layout()
  Refresh()
end

function A.ColumnMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Columns")
    for _, col in ipairs(cols) do
      if col.key ~= "name" then
        root:CreateCheckbox(col.menu or col.label, function() return Shown(col.key) end,
          function() A.SetColumn(col.key, not Shown(col.key)) end)
      end
    end
  end)
end

-- "where", "Where", "lvl", "level", "xp", "rested", "gold"...
local function FindColumn(word)
  word = word and word:lower()
  for _, col in ipairs(cols) do
    local names = (col.key .. " " .. col.label .. " " .. (col.menu or "")):lower()
    if col.key ~= "name" and word and word ~= "" and (" " .. names .. " "):find(
      "[%s/]" .. word:gsub("%W", "%%%0") .. "[%s/]") then
      return col
    end
  end
end

local function ColumnNames()
  local list = {}
  for _, col in ipairs(cols) do
    if col.key ~= "name" then
      local name = (col.menu or col.label):lower()
      list[#list + 1] = Shown(col.key) and name or "|cff808080" .. name .. "|r"
    end
  end
  return table.concat(list, ", ")
end

local function ShowColumn(arg, on)
  local col = FindColumn(arg)
  if not col then
    return Print(("which column? %s (grey: hidden)"):format(ColumnNames()))
  end
  A.SetColumn(col.key, on)
  Print((col.menu or col.label) .. (on and " shown" or " hidden"))
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

-- At login, one chat line for alts whose rested XP is full (rest beyond it is lost) or fills
-- within a day. Each is named once per fill: again only after it has been played since.
local SOON_HOURS = 24
local SUMMARY_MAX = 5

local function Names(list)
  local out = {}
  for i = 1, math.min(#list, SUMMARY_MAX) do out[i] = list[i].text end
  if #list > SUMMARY_MAX then out[#out + 1] = (#list - SUMMARY_MAX) .. " more" end
  return table.concat(out, ", ")
end

function A.RestSummary()
  if A.db.restAlert == false or RestedHidden() then return end
  local full, soon = {}, {}
  for _, c in pairs(A.db.chars) do
    local rested, cap, hours
    if not A.IsMe(c) then rested, cap, hours = A.RestedNow(c) end
    if rested and rested >= cap then
      if c.toldFull ~= c.seen then
        c.toldFull = c.seen
        full[#full + 1] = { text = ClassColour(c), name = c.name }
      end
    elseif hours and hours <= SOON_HOURS and c.toldSoon ~= c.seen then
      c.toldSoon = c.seen
      soon[#soon + 1] = { text = ClassColour(c) .. " (" .. Duration(hours * 3600) .. ")",
        hours = hours }
    end
  end
  if #full + #soon == 0 then return end
  table.sort(full, function(a, b) return a.name < b.name end)
  table.sort(soon, function(a, b) return a.hours < b.hours end)
  local parts = {}
  if #full > 0 then parts[#parts + 1] = "fully rested: " .. Names(full) end
  if #soon > 0 then parts[#parts + 1] = "full within a day: " .. Names(soon) end
  Print(table.concat(parts, "; ") .. " |cff808080(/alts rest off)|r")
end

local loginEvents = CreateFrame("Frame")
loginEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
loginEvents:SetScript("OnEvent", function(self, _, isLogin)
  self:UnregisterAllEvents()
  if not isLogin then return end
  -- after the login chat flood, and once the realm (so A.myKey) is known
  C_Timer.After(8, function() if A.myKey then A.RestSummary() end end)
end)

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
    "  |cffffd100/alts add Name[-Realm]|r - one of yours on another WoW account: in the "
      .. "mailbox To picker and the list (name only)",
    "  |cffffd100/alts remove Name[-Realm]|r - take an other-account character off again",
    "  |cffffd100/alts hide||show Column|r - narrow the list (or right-click its headings): "
      .. ColumnNames(),
    "  |cffffd100/alts rest on||off|r - at login, a chat line names alts that are fully "
      .. "rested or will be within a day" .. Now(A.db.restAlert ~= false),
    "  |cffffd100/alts elsewhere on||off|r - characters on another realm or faction in the "
      .. "list (the total counts only this one's)" .. Now(A.db.elsewhere ~= false),
    "  |cffffd100/alts reset|r - put the window back",
    "  Settings: Esc > Options > AddOns > MeioAlts (|cffffd100/alts settings|r)",
  }) do
    print(line)
  end
end

local function AddOther(arg)
  if not arg or arg == "" then
    Print("which character? |cffffd100/alts add Name|r or |cffffd100Name-Realm|r (one of "
      .. "yours on another WoW account)")
    return
  end
  local key, err = A.AddOther(arg)
  if not key then return Print("|cffff8080" .. err .. "|r") end
  if A.UpdateMailPicker then A.UpdateMailPicker() end
  Print("added " .. key .. " (other account): at the mailbox it's in the To picker under "
    .. "Other account")
end

local function RemoveOther(arg)
  if not arg or arg == "" then
    Print("which character? |cffffd100/alts remove Name|r or |cffffd100Name-Realm|r")
    return
  end
  local key, tried = A.RemoveOther(arg)
  if not key then
    if not tried then
      return Print("|cffff8080realm not known yet, try again in a moment|r")
    end
    local hint = A.db.chars[tried] and " (on this account: |cffffd100/alts forget|r)" or ""
    return Print("|cffff8080no other-account character " .. tried .. "|r" .. hint)
  end
  if A.UpdateMailPicker then A.UpdateMailPicker() end
  Print("removed " .. key)
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
  elseif cmd == "add" then
    AddOther(arg)
  elseif cmd == "remove" then
    RemoveOther(arg)
  elseif cmd == "forget" and arg and arg ~= "" and A.db.others[A.Key(arg) or ""] then
    RemoveOther(arg)
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
  elseif cmd == "rest" then
    Switch(arg, A.db.restAlert ~= false, function(on)
      A.db.restAlert = on
      Print("rested line at login " .. (on and "on" or "off"))
    end)
  elseif cmd == "elsewhere" then
    Switch(arg, A.db.elsewhere ~= false, A.SetElsewhere)
  elseif cmd == "hide" or cmd == "show" then
    ShowColumn(arg, cmd == "show")
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
