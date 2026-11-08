-- ============================================================
--  EMBER CONTROL - APP TEMPLATE
--  Copy this file to /ember/apps/<something>.lua on your pocket
--  computer and restart Ember Control. It appears as a new tile.
--
--  This example is a working "Notes" app (saved on the pocket
--  computer). The comments show how to talk to a real system.
-- ============================================================
-- `ember` is the toolkit (ctx). Handy parts:
--   ember.request(protocol, hostname, msg, timeout) -> reply or nil, error
--        the system must rednet.host(protocol, hostname) and reply with
--        rednet.send(sender, { rid = msg.rid, ... }, protocol)
--   ember.header(title, colour [, onBack])   ember.tabs(y, {{id,label},..}, active, onPick)
--   ember.button(x, y, label, fg, bg, onTap [, width]) -> next x
--   ember.list(state, y1, y2, items, renderRow(item, y), onTap(item))   (scrolls by itself)
--   ember.at(x, y, text, fg, bg)   ember.fill(x, y, w, h, bg)   ember.bar(x, y, w, fraction, colour)
--   ember.prompt(question [, hidden]) -> text or nil     ember.promptNumber(q) -> whole number or nil
--   ember.confirm(question) -> true/false                ember.toast(message, ok)
--   ember.appConfig(id) -> table saved between runs (call ember.saveConfig() after changing it)
--   ember.fmt(n) -> "1,234"    ember.clip(text, n)    ember.W / ember.H (screen size)

local app = {
  id = "notes",                 -- unique, lowercase
  name = "Notes",               -- shown on the tile
  icon = "N",                   -- one character on the tile
  color = colors.purple,        -- tile colour
  interval = 5,                 -- seconds between refresh() calls while open
  -- protocol = "myproto",      -- add this if the app talks to a system: Settings then lets
                                -- you type that computer's ID if auto-find fails
}

-- refresh(self, ember, background): fetch fresh data. background = true when
-- called from the home screen (use a short timeout there).
function app.refresh(self, e, background)
  -- A real system would do something like:
  --   local r, err = e.request("myproto", "myserver", { type = "status" }, background and 1.5 or 3)
  --   if r then self.data, self.err = r, nil else self.err = err end
  self.notes = e.appConfig("notes").list or {}
end

-- summary(self, ember) -> text [, colour] shown under the tile name on the home screen
function app.summary(self, e)
  local n = #(self.notes or {})
  return n .. " note" .. (n == 1 and "" or "s")
end

-- draw(self, ember): draw the whole screen. Buttons/taps are re-registered every draw.
function app.draw(self, e)
  e.header("Notes", app.color)
  e.button(2, 3, "+ New note", colors.white, colors.green, function()
    local text = e.prompt("Note text")
    if text then
      local cfg = e.appConfig("notes")
      cfg.list = cfg.list or {}
      table.insert(cfg.list, 1, text)
      e.saveConfig()
      self:refresh(e)
      e.toast("Saved", true)
    end
  end)
  e.list(self.state, 5, e.H - 1, self.notes or {}, function(note, y)
    e.at(2, y, e.clip(note, e.W - 2), colors.white, colors.black)
  end, function(note, index)
    if e.confirm("Delete this note?") then
      local cfg = e.appConfig("notes")
      table.remove(cfg.list, index)
      e.saveConfig()
      self:refresh(e)
    end
  end)
  if #(self.notes or {}) == 0 then e.at(2, 6, "No notes yet", colors.lightGray, colors.black) end
end

return app
