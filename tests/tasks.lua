-- Pure task-list parsing and paging; no game or PrettyUI needed.
local tasks = require('tasks')
local json = require('json')
local function decode(text) return tasks.list(json.decode(text)) end

assert(tasks.list(nil) == nil and tasks.list({v = 2, ready = true}) == nil and tasks.list({v = 1}) == nil)
local list = decode('{"v":1,"ready":true,"stale":false,"chunkId":"13613","hereKnown":true,'
  .. '"here":[{"id":"a","label":"Mine <col=ff0000>copper\\n","category":"Skills","level":5}],'
  .. '"all":[{"id":"a","label":"Mine copper","category":"Skills","level":5},{"label":7},{"id":"b","label":"Visit Nardah","category":"Extra","level":0}],'
  .. '"hereCount":1,"allCount":3}')
assert(list.ready and not list.stale and list.hereKnown and list.chunkId == '13613')
assert(list.here[1].label == 'Mine col=ff0000copper', list.here[1].label)
assert(#list.all == 2, 'a row without a text label is dropped')
assert(tasks.row(list.all[1]) == 'Skills · Mine copper (5)' and tasks.row(list.all[2]) == 'Extra · Visit Nardah')

local head, rows = tasks.page(list, 'here', 1)
assert(head == 'Here: 1 task' and #rows == 1, head)
head, rows = tasks.page(list, 'all', 1)
assert(head == 'All active: 3 · first 2' and rows[2] == 'Extra · Visit Nardah', head)

-- Paging: 30 rows at 12 a page; out-of-range pages clamp.
local many = {v = 1, ready = true, hereKnown = false, here = {}, all = {}, hereCount = 0, allCount = 130}
for i = 1, 100 do many.all[i] = {label = 'Task ' .. i, category = 'Skills'} end
local parsed = tasks.list(many)
local h, r, page, pages = tasks.page(parsed, 'all', 99)
assert(page == 9 and pages == 9 and #r == 4 and r[1] == 'Skills · Task 97', h)
assert(h == 'All active: 130 · page 9/9 · first 100', h)
-- A taller window pages by its own row count.
h, r, page, pages = tasks.page(parsed, 'all', 2, nil, 20)
assert(#r == 20 and r[1] == 'Skills · Task 21' and pages == 5, h)
h, r = tasks.page(parsed, 'here', 1)
assert(h == 'Waiting for your location in the picker.' and #r == 0)
assert(parsed.allFrom == nil, 'an older picker sends no allFrom, so paging stays within the first 100')

-- A picker that pages: pages run over the whole list; a page outside the rows held asks for them.
local function chunk(from, total)
  local body = {v = 1, ready = true, hereKnown = false, here = {}, all = {}, hereCount = 0, allCount = total, allFrom = from}
  for i = from + 1, math.min(from + tasks.CHUNK, total) do body.all[#body.all + 1] = {label = 'Task ' .. i, category = 'Skills'} end
  return tasks.list(body)
end
local first, rest = chunk(0, 130), chunk(96, 130)
assert(first.allFrom == 0 and first.allHeld == 100 and rest.allFrom == 96 and rest.allHeld == 34)
local want
h, r, page, pages, want = tasks.page(first, 'all', 8)
assert(h == 'All active: 130 · page 8/11' and r[12] == 'Skills · Task 96' and want == nil, h)
h, r, page, pages, want = tasks.page(first, 'all', 9)
assert(h == 'All active: 130 · page 9/11 · loading…' and #r == 0 and want == 96, h)
h, r, page, pages, want = tasks.page(rest, 'all', 9)
assert(#r == 12 and r[1] == 'Skills · Task 97' and r[12] == 'Skills · Task 108' and want == nil, h)
h, r, page, pages, want = tasks.page(rest, 'all', 99)
assert(page == 11 and #r == 10 and r[10] == 'Skills · Task 130' and h == 'All active: 130 · page 11/11', h)
-- Back past the rows held asks for the rows that end at that page.
h, r, page, pages, want = tasks.page(rest, 'all', 8)
assert(#r == 0 and want == 0, h)
h, r, page, pages, want = tasks.page(chunk(150, 300), 'all', 12, nil, 12)
assert(want == 44, tostring(want))
-- The Here view is never paged by the picker.
assert(select(5, tasks.page(rest, 'here', 1)) == nil)
for _, bad in ipairs({-1, 1.5, '3'}) do assert(tasks.list({v = 1, ready = true, allFrom = bad}).allFrom == nil, tostring(bad)) end

-- Not ready, stale, empty and still loading.
assert(tasks.page(tasks.list({v = 1, ready = false}), 'all', 1) == 'No saved task list yet. Open your tasks in the picker once.')
local stale = tasks.list({v = 1, ready = true, stale = true, hereKnown = true, here = {}, all = {}, hereCount = 0, allCount = 0})
assert(tasks.page(stale, 'here', 1) == 'No active tasks in this chunk. · saved before your last change')
assert(tasks.page(stale, 'all', 1, 'picker asked to slow down') == 'No active tasks. · saved before your last change · picker asked to slow down')
assert(tasks.page(nil, 'here', 1) == 'Loading tasks…')
assert(tasks.page(nil, 'here', 1, 'Open plugin Settings') == 'Open plugin Settings')
print('tasks tests passed')
