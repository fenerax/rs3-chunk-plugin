-- Stable location diff and successful-report heartbeat. Failed sends never consume work.
local location = require("location")
local M = {}
function M.new()
  local self = {}
  function self:reset() self.candidate=nil; self.since=nil; self.sent=nil; self.lastSent=nil; self.forced=nil end
  function self:observe(position, now)
    local signature=location.signature(position)
    if signature~=location.signature(self.candidate) then self.candidate=position; self.since=now end
  end
  -- Sync now: reports go without waiting for a move or the minute heartbeat, until main turns it off.
  function self:force(on) self.forced=on~=false or nil end
  function self:due(now, progress)
    if not self.candidate or not self.since or now-self.since<1 then return false end
    return progress or self.forced or self.sent~=location.signature(self.candidate) or not self.lastSent or now-self.lastSent>=60
  end
  function self:ack(position,now) self.sent=location.signature(position); self.lastSent=now end
  self:reset(); return self
end
return M
