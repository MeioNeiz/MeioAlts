-- Options panel: Esc > Options > AddOns > MeioAlts, or /alts settings. Writes into MeioAltsDB.
local _, A = ...

local category

function A.RegisterSettings()
  if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory("MeioAlts")
  if A.db.menu == nil then A.db.menu = true end
  local menu = Settings.RegisterAddOnSetting(category, "MEIOALTS_MENU", "menu", A.db,
    Settings.VarType.Boolean, "Beside game menu", true)
  Settings.CreateCheckbox(category, menu, "Pressing Esc shows the character list beside the "
    .. "game menu, where Log Out is. Off: only /alts opens it. /alts menu on||off does the "
    .. "same.")
  if A.db.elsewhere == nil then A.db.elsewhere = true end
  local elsewhere = Settings.RegisterAddOnSetting(category, "MEIOALTS_ELSEWHERE", "elsewhere",
    A.db, Settings.VarType.Boolean, "Other realms and factions", true)
  Settings.CreateCheckbox(category, elsewhere, "Characters on another realm or the other "
    .. "faction show (faded) in the list. Mail can't reach them, so the total only ever counts "
    .. "this realm and faction. /alts elsewhere on||off does the same.")
  if elsewhere.SetValueChangedCallback then
    elsewhere:SetValueChangedCallback(function() A.Changed() end)
  end
  if A.db.restAlert == nil then A.db.restAlert = true end
  local rest = Settings.RegisterAddOnSetting(category, "MEIOALTS_RESTALERT", "restAlert", A.db,
    Settings.VarType.Boolean, "Rested alts at login", true)
  Settings.CreateCheckbox(category, rest, "When you log in, one chat line names your alts "
    .. "whose rested XP is full (more rest is lost) or will be within a day. Each is named "
    .. "once, until you play it again. /alts rest on||off does the same.")
  if A.db.mail == nil then A.db.mail = true end
  if A.db.mailSend == nil then A.db.mailSend = false end
  local mail = Settings.RegisterAddOnSetting(category, "MEIOALTS_MAIL", "mail", A.db,
    Settings.VarType.Boolean, "Mail: alt picker + Alt-click attach", true)
  local mailInit = Settings.CreateCheckbox(category, mail, "At the mailbox's Send tab, a button "
    .. "beside To lists your characters on this realm to send to, and Alt-click on a bag item "
    .. "attaches it. /alts mail on||off does the same. Yours on another WoW account: "
    .. "/alts add Name lists them too, under Other account.")
  local send = Settings.RegisterAddOnSetting(category, "MEIOALTS_MAILSEND", "mailSend", A.db,
    Settings.VarType.Boolean, "Alt-click sends at once", false)
  local sendInit = Settings.CreateCheckbox(category, send, "Alt-click on a bag item also sends "
    .. "the mail straight away, but only when To is one of your characters on this account "
    .. "(not one added by name) and no money or COD is set. /alts mailsend on||off does the same.")
  if sendInit and sendInit.SetParentInitializer then
    sendInit:SetParentInitializer(mailInit, function() return A.db.mail ~= false end)
  end
  for _, setting in ipairs({ mail, send }) do
    if setting.SetValueChangedCallback then
      setting:SetValueChangedCallback(function() A.MailSettingChanged() end)
    end
  end
  if layout and CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer("Character list", "Open",
      function() if not MeioAltsFrame:IsShown() then A.Toggle() end end,
      "Opens the /alts window.", true))
    layout:AddInitializer(CreateSettingsButtonInitializer("Window position", "Reset",
      A.ResetPosition, "Puts the /alts window back in the middle of the screen (/alts reset).",
      true))
  end
  Settings.RegisterAddOnCategory(category)
end

function A.OpenSettings()
  if not category then return end
  Settings.OpenToCategory(category:GetID())
  return true
end
