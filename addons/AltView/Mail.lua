-- Mailbox Send tab: a picker beside the To box fills in one of our alts, and Alt-click on a
-- bag item attaches it (Shift-click is taken: chat link, split stack). Optional quick send
-- (A.db.mailSend): that Alt-click also sends, only to our own alts and only item-only mail.
local _, A = ...

local PREFIX = "|cffb090ffAltView:|r "
-- seconds; a send with no MAIL_SEND_SUCCESS / MAIL_FAILED by then counts as over
local PENDING_TIMEOUT = 15
local READY_TIMEOUT = 2

local picker
local pendingAt -- GetTime() of the last SendMail, until the server answers
local quickTo -- the alt our quick send went to, put back in the To box after Blizzard clears it
local waitingSince -- quick send waiting for the attachment to show up (subject not filled yet)

local function On() return A.db and A.db.mail ~= false end
local function SendOn() return On() and A.db.mailSend == true end

local function Realm(key) return key:match("%-(.+)$") end

-- Same realm and faction as the one playing (unknown faction counts): mail can't go further
local function Mailable(key, c)
  local faction = A.db.chars[A.myKey].faction
  return not A.IsMe(c) and Realm(key) == Realm(A.myKey)
    and (not c.faction or not faction or c.faction == faction)
end

function A.MailAlts()
  local list = {}
  for key, c in pairs(A.db.chars) do
    if Mailable(key, c) then list[#list + 1] = c end
  end
  table.sort(list, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.name < b.name
  end)
  return list
end

-- The To box names one of the characters the picker offers
local function AltInToBox()
  local text = strtrim(SendMailNameEditBox:GetText() or "")
  if text == "" then return end
  local key = A.Key(text)
  local c = A.db.chars[key]
  return c and Mailable(key, c) and c or nil
end

local function ItemOnly()
  return MoneyInputFrame_GetCopper(SendMailMoney) == 0 and not SendMailCODButton:GetChecked()
end

local function Pending()
  if pendingAt and GetTime() - pendingAt > PENDING_TIMEOUT then pendingAt = nil end
  return pendingAt ~= nil
end

local function Error(msg)
  UIErrorsFrame:AddMessage(msg, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
end

local function AltLabel(c)
  local col = c.class and RAID_CLASS_COLORS[c.class]
  local name = col and col:WrapTextInColorCode(c.name) or c.name
  return name .. " |cff999999" .. (c.level or "?") .. "|r"
end

-- Blizzard fills the subject with the item's name when it updates the Send tab; sending needs
-- To and subject, so the Send button is enabled once the attachment counts
local function TrySend()
  SendMailFrame_Update()
  if not SendMailMailButton:IsEnabled() then return false end
  waitingSince = nil
  quickTo = SendMailNameEditBox:GetText()
  SendMailMailButton:Click()
  return true
end

local function QuickSend()
  if not (SendOn() and AltInToBox() and ItemOnly()) then return end
  if not TrySend() then waitingSince = GetTime() end
end

local function OnModifiedItemClick(_, loc)
  if not (On() and IsAltKeyDown() and SendMailFrame:IsVisible()) then return end
  if not (loc and loc.IsBagAndSlot and loc:IsBagAndSlot()) or CursorHasItem() then return end
  if Pending() then
    Error("Still sending the last mail")
    return
  end
  local bag, slot = loc:GetBagAndSlot()
  C_Container.PickupContainerItem(bag, slot)
  ClickSendMailItemButton()
  -- not attached (soulbound, all slots full; the client says why): back to the bag
  if CursorHasItem() then
    ClearCursor()
    return
  end
  QuickSend()
end

local function PickerMenu(owner, root)
  local alts = A.MailAlts()
  root:CreateTitle("Send to")
  for _, c in ipairs(alts) do
    root:CreateButton(AltLabel(c), function()
      SendMailNameEditBox:SetText(c.name)
      SendMailNameEditBox:ClearFocus()
      SendMailFrame_CanSend()
    end)
  end
end

local function PickerTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Your alts")
  if #A.MailAlts() == 0 then
    GameTooltip:AddLine("No other character on this realm and faction yet: log in once on "
      .. "each to add it.", 1, 1, 1, true)
  else
    GameTooltip:AddLine("Click: pick one of your characters to send to", 1, 1, 1, true)
  end
  local alt = SendOn() and "Alt-click a bag item: attach it, and send at once when To is one "
    .. "of your alts and no money or COD is set" or "Alt-click a bag item: attach it"
  GameTooltip:AddLine(alt, 1, 1, 1, true)
  GameTooltip:Show()
end

local function UpdatePicker()
  if not picker then return end
  picker:SetShown(On())
  picker:SetEnabled(#A.MailAlts() > 0)
end

local function CreatePicker()
  picker = CreateFrame("Button", "AltViewMailPicker", SendMailFrame)
  picker:SetSize(24, 24)
  picker:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 2, 0)
  picker:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  picker:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
  picker:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
  picker:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  picker:SetMotionScriptsWhileDisabled(true)
  picker:SetScript("OnClick", function(self)
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(self, PickerMenu)
    end
  end)
  picker:SetScript("OnEnter", PickerTooltip)
  picker:SetScript("OnLeave", GameTooltip_Hide)
  SendMailFrame:HookScript("OnShow", UpdatePicker)
  UpdatePicker()
end

local function Setup()
  if picker or not (A.myKey and SendMailFrame and SendMailNameEditBox) then return end
  CreatePicker()
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", OnModifiedItemClick)
  end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "MAIL_SHOW", "MAIL_SEND_INFO_UPDATE",
  "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_CLOSED" }) do
  events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" or event == "MAIL_SHOW" then
    Setup()
  elseif event == "MAIL_SEND_INFO_UPDATE" then
    if waitingSince then
      -- after Blizzard's own update of the Send tab
      C_Timer.After(0, function()
        if waitingSince and GetTime() - waitingSince <= READY_TIMEOUT then TrySend() end
      end)
    end
  elseif event == "MAIL_SEND_SUCCESS" then
    pendingAt = nil
    local to = quickTo
    quickTo = nil
    -- Blizzard empties the To box on success; keep the alt for the next Alt-click
    if to then
      C_Timer.After(0, function()
        if SendMailFrame:IsVisible() and SendMailNameEditBox:GetText() == "" then
          SendMailNameEditBox:SetText(to)
          SendMailFrame_CanSend()
        end
      end)
    end
  else
    pendingAt, quickTo, waitingSince = nil, nil, nil
  end
end)

hooksecurefunc("SendMail", function() pendingAt = GetTime() end)

local function State(on) return on and "|cff80ff80on|r" or "|cffff8080off|r" end

function A.SetMail(on)
  A.db.mail = on
  UpdatePicker()
  print(PREFIX .. "mailbox alt picker and Alt-click attach " .. State(on))
end

function A.SetMailSend(on)
  A.db.mailSend = on
  local note = on and not On() and " |cff999999(needs /alts mail on)|r" or ""
  print(PREFIX .. "Alt-click sends at once " .. State(on) .. note)
end

-- Settings checkbox changes, without the chat line
function A.MailSettingChanged() UpdatePicker() end
