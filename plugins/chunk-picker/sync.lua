-- Decides when a report is due: after the position has held still for a second, on new
-- progress, or as a once-a-minute heartbeat. Only a report the picker accepted (ack) counts
-- as sent, so a failed send never uses up the change it carried.
local location = require("location")
local M = {}
function M.new()
  local self = {}
  function self:reset()
    self.candidate = nil  -- latest position seen
    self.since = nil      -- when the candidate was first seen
    self.sent = nil       -- signature of the last position the picker accepted
    self.lastSent = nil
    self.forced = nil
  end
  function self:observe(position, now)
    local signature = location.signature(position)
    if signature ~= location.signature(self.candidate) then
      self.candidate = position
      self.since = now
    end
  end
  -- Sync now: reports go without waiting for a move or the minute heartbeat, until main turns it off.
  function self:force(on) self.forced = on ~= false or nil end
  -- `progress` is true when the report carries anything besides the position.
  function self:due(now, progress)
    -- Wait a second after a move so walking across a border doesn't send every square.
    if not self.candidate or not self.since or now - self.since < 1 then return false end
    return progress or self.forced or self.sent ~= location.signature(self.candidate)
      or not self.lastSent or now - self.lastSent >= 60
  end
  function self:ack(position, now)
    self.sent = location.signature(position)
    self.lastSent = now
  end
  self:reset()
  return self
end
return M
