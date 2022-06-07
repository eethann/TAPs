-- TAPs: delay matrix for norns
-- tap apt pats

local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/mg_128" or grid
g = grid.connect()
saved_states = {}
state = {}
active_state = 1


-- TODO allow 7 switchable configurations (may rework data structure into just 2 matrices)
-- TODO refactor this into a UI lib
local viewport = { width = 128, height = 64, frame = 0 }
local focus = { x = 1, y = 1, brightness = 15 }
local keys_status = {0,0,0}
local sliders = {}
local slider_mode = 0
local grid_mode = 0

function default_state() 
  local state = {
    in_gates = {},
    out_gates = {},
    route_gates = {},
    in_levels = {},
    out_levels = {},
    route_levels = {},
    in_pans = {},
    out_pans = {},
    in_level_mult = 1.0,
    route_level_mult = 1.0,
    delay_times = {},
  }
  for i=1,6 do
    state.in_gates[i] = 0
    state.in_levels[i] = 0.9
    state.out_gates[i] = 1
    state.out_levels[i] = 0.9
    state.out_pans[i] = -0.75 + 0.75 * (i % 3)
    state.in_pans[i] = 1 - 2 * (i % 2)
    state.delay_times[i] = 0.25*i
    for j=1,6 do
      state.route_levels[route_index(i,j)] = 0.75
      state.route_gates[route_index(i,j)] = 0
    end
  end
  state.in_gates[1] = 1;
  for i=0,5 do
    state.route_gates[route_index(((i+1)%6)+1,i+1)] = 1
  end
  return state
end

function load_state(i) 
  state = saved_states[i]
  active_state = i
  update()
end

function save_state(i)
  saved_states[i] = state
  active_state = i
  update()
end

function init()
  -- TODO make better defaults
  for i=1,6 do
    saved_states[i] = default_state()
  end
  load_state(1)
  -- TODO refactor this to be 0 indexed, 1 base is a pain
  screen_init()
  softcut_init()
  update()
end

function update()
  -- TODO add clean / dirty flags to eliminate unneeded re-renders
  softcut_update()
  redraw()
  grid_redraw()
end

function route_index(destination, source) 
  -- TODO update this to make it more sensible for 1 indexed tables
  -- (currently wasting the first 6 entries in the array)
  return destination * 6 + source
end

function loop_start_time(ch)
  return (ch - 1) * 36 + 1
end

function loop_end_time(ch) 
  return loop_start_time(ch) + util.clamp(state.delay_times[ch]*clock.get_beat_sec(),0,35)
end

function toggle(val)
  if val == 0 then
    return 1
  else
    return 0
  end
end

function screen_init()
  screen.level(15)
  screen.aa(0)
  screen.line_width(1)
end


function softcut_init()
  softcut.reset()
  audio.level_cut(1)
  audio.level_adc_cut(1)
  audio.level_tape_cut(1)

  for recordhead=1,6 do
    softcut.buffer(recordhead, 1)
    softcut.enable(recordhead, 1)
    softcut.loop_start(recordhead,loop_start_time(recordhead))
    softcut.loop_end(recordhead,loop_end_time(recordhead))
    softcut.position(recordhead, loop_start_time(recordhead))
    softcut.loop(recordhead, 1)
    softcut.pre_level(recordhead, 0)
    softcut.rec_level(recordhead, 1)
    softcut.play(recordhead, 1)
    softcut.rec(recordhead, 1)
    softcut.rate(recordhead, 1)
    softcut.level(recordhead, 0) 
    softcut.fade_time(recordhead, 0.02)
    softcut.level_slew_time(recordhead, 0.01)
    softcut.rate_slew_time(recordhead, 0.01)
    softcut.filter_dry(recordhead, 1)
    -- softcut.filter_fc(recordhead, 0)
    softcut.filter_lp(recordhead, 0)
    softcut.filter_bp(recordhead, 0)
    softcut.filter_rq(recordhead, 0)
  end
end

function softcut_update() 
  for recordhead=1,6 do
    -- TODO offer option for speed (tape) or buffer len (digital) time control
    softcut.loop_end(recordhead,loop_end_time(recordhead))
    -- TODO immplement proper log panning, not linear
    local in_1_pan_amt = 0.5 + 0.5 * state.in_pans[recordhead]
    local in_2_pan_amt = 0.5 - 0.5 * state.in_pans[recordhead]
    local in_base_level = state.in_gates[recordhead] * state.in_levels[recordhead] * state.in_level_mult
    print("in levels: " .. in_1_pan_amt .. " and " .. in_2_pan_amt .. ", " .. in_base_level)
    softcut.level_input_cut(1,recordhead,in_1_pan_amt * in_base_level)
    softcut.level_input_cut(2,recordhead,in_2_pan_amt * in_base_level)
    softcut.level(recordhead, state.out_gates[recordhead] * state.out_levels[recordhead])
    softcut.pan(recordhead, state.out_pans[recordhead]) 
    for source=1,6 do
      local idx = route_index(recordhead, source)
      local route_level = state.route_level_mult*state.route_gates[idx]*state.route_levels[idx]
      if (source == recordhead) then
        softcut.pre_level(recordhead,route_level)
      else
        print("UPDATE ROUTE " .. source .. "-" .. route_level .. "->" .. recordhead)
        softcut.level_cut_cut(source,recordhead,route_level)
      end
    end
  end
end

function is_connected()
  return g.device ~= nil
end

-- TODO handle connect and disconnect, assign key func on connect
g.key = function(x,y,z)
  if y == 1 and x == 8 then
    grid_mode = z
  elseif y == 8 and x == 1 then
    grid_mode = z * 2
  elseif (grid_mode == 0) then
    if z == 1 then
      if y < 7 then
        if (x == 1) then
          state.in_gates[y] = toggle(state.in_gates[y])
        elseif (x > 1) and (x < 8) then
          local idx = route_index(y,x-1)
          state.route_gates[idx] = toggle(state.route_gates[idx])
        end
      elseif y == 7 then
        state.out_gates[x-1] = toggle(state.out_gates[x-1])
      elseif y == 8 and x > 1 and x < 8 then
        -- TODO should we save the current state before loading by default?
        load_state(x-1)
      end
      focus = { x = x, y = y}
    end
  elseif grid_mode == 1 then
    if z == 1 then
      if x < 8 and y < 8 then
        focus = { x = x, y = y}
      elseif x == 8 and y < 8 then
        update_slider_val(1,-1*(y-4))
      elseif y == 8 and x < 8 then
        update_slider_val(2,(x-4))
      end
    end
  elseif grid_mode == 2 then
    if z == 1 then
      if y == 8 and x > 1 and x < 8 then
        save_state(x-1)
      end
    end  
  end
  update()
end

function grid_redraw()
  if is_connected() ~= true then return end
  g:all(0)
  for i=1,6 do
    g:led(1,i,state.in_gates[i] == 1 and 15 or 1)
    for j=1,6 do
      g:led(j+1,i,state.route_gates[route_index(i,j)] == 1 and 15 or 1)
    end
    g:led(i+1,7,state.out_gates[i] == 1 and 15 or 1)
    g:led(i+1,8,active_state == i and 15 or 1)
  end
  g:refresh()
end

-- Render

-- TODO DRY up these handling funcs with grid handling funcs
function key(n,z) 
  keys_status[n] = z
  if (n == 2) then 
    if keys_status[3] ~= 1 then       
      slider_mode = z
    end
  elseif (n == 3) then
    if (slider_mode > 0) then
      if (z == 1) then
        slider_mode = 2
      else
        slider_mode = slider_mode - 1
      end 
    elseif (z == 1) then
      if (focus.x > 1 and focus.x < 8 and focus.y < 7) then
        state.route_gates[route_index(focus.y, focus.x - 1)] = toggle(state.route_gates[route_index(focus.y, focus.x - 1)])
      elseif (focus.x == 1 and focus.y < 7) then
        state.in_gates[focus.y] = toggle(state.in_gates[focus.y])
      elseif (focus.y == 7 and focus.x > 1) then
        state.out_gates[focus.x-1] = toggle(state.out_gates[focus.x-1])
      end
    end 
  end
  -- may trigger unneeded updates
  update()
end

function update_slider_val(n,d)
  local step_size = 0.05
  print("updating slider " .. n .. " " .. d)
  if (focus.x > 1 and focus.x < 8 and focus.y < 7) then
    local idx = route_index(focus.y, focus.x - 1)
    if n == 1 then
      state.route_levels[idx] = util.clamp(state.route_levels[idx]+(d*step_size),0.0,1.0) 
    elseif n == 2 then
      state.delay_times[focus.y] = util.clamp(state.delay_times[focus.y]+(d*0.25),0.0,16.0) 
    end
  elseif (focus.x == 1 and focus.y < 7) then
    if n == 1 then
      state.in_levels[focus.y] = util.clamp(state.in_levels[focus.y]+(d*step_size),0.0,1.0) 
    elseif n == 2 then
      state.in_pans[focus.y] = util.clamp(state.in_pans[focus.y]+(d*step_size),-1.0,1.0) 
    end
  elseif (focus.y == 7 and focus.x > 1) then
    if n == 1 then
      state.out_levels[focus.x-1] = util.clamp(out_levels[focus.x-1]+(d*step_size),0.0,1.0) 
    elseif n == 2 then
      state.out_pans[focus.x-1] = util.clamp(state.out_pans[focus.x-1]+(d*step_size),-1.0,1.0) 
    end
  elseif (focus.y==7 and focus.x==1) then
    -- TODO implement dry/wet balance
    if n == 1 then
    elseif n == 2 then
    end
  end
  update()
end

-- TODO implement encode functionality via 8th col on grid
function enc(n,d)
  if (slider_mode == 2) then
    if n == 2 then
      state.route_level_mult = util.clamp(state.route_level_mult+(d*step_size),0.0,1.0) 
    elseif n == 3 then
      state.in_level_mult = util.clamp(state.in_level_mult+(d*step_size),0.0,1.0) 
    end
  elseif (slider_mode == 1) then
    update_slider_val(n-1, d)
  else
    if n == 2 then
      focus.x = util.clamp(focus.x + d,1,7)
    elseif n == 3 then
      focus.y = util.clamp(focus.y + d,1,7)
    end 
    -- TODO de-dupe / de-bounce redraws
    redraw()
    grid_redraw()
  end
end


function draw_sliders()
    if (focus.x > 1 and focus.x < 8 and focus.y < 7) then
    elseif (focus.x == 1 and focus.y < 7) then
    elseif (focus.y == 7 and focus.x > 1) then
    end
end

function draw_frame()
  screen.level(15)
  screen.rect(1, 1, viewport.width-1, viewport.height-1)
  screen.stroke()
end

function draw_pixel(x,y)
  if focus.x == x and focus.y == y then
    screen.level(10)
    screen.rect((x*offset.spacing) + offset.x - 1, (y*offset.spacing) + offset.y - 1, 3, 3)
    screen.stroke()
  end
  if (x > 1) and (y < 7) then
    if (state.route_gates[route_index(y,x-1)] == 1) then
      screen.level(8)
    else 
      screen.level(1)
    end
    screen.pixel((x*offset.spacing) + offset.x, (y*offset.spacing) + offset.y)
    screen.stroke()
  elseif (y == 7) and (x > 1) then
    if (state.out_gates[x-1] == 1) then
      screen.level(8)
    else 
      screen.level(1)
    end
    screen.pixel((x*offset.spacing) + offset.x, (y*offset.spacing) + offset.y)
    screen.stroke()
  elseif (x == 1) and (y < 7) then
    if (state.in_gates[y] == 1) then
      screen.level(8)
    else 
      screen.level(1)
    end
    screen.pixel((x*offset.spacing) + offset.x, (y*offset.spacing) + offset.y)
    screen.stroke()
  end
end

function draw_grid()
  screen.level(1)
  offset = { x = 30, y = 13, spacing = 4 }
  for x=1,7,1 do 
    for y=1,7,1 do 
      draw_pixel(x,y)
    end
  end
  screen.stroke()
end

function draw_values(description, label1,val1,label2,val2)
  if slider_mode > 0 then
    screen.level(15)
  else
    screen.level(1)
  end
  local line_height = 8
  local offset = {x = 70, y = 20}
  screen.move(offset.x,offset.y + line_height * 0)
  screen.text(description)
  screen.move(offset.x,offset.y + line_height * 1)
  print(label1)
  print(val1)
  screen.text(label1 .. ":" .. val1)
  if (label2 ~= nil and val2 ~= nil) then
  screen.move(offset.x,offset.y + line_height * 2)
    screen.text(label2 .. ":" .. val2)
  end
  screen.stroke()
end

function draw_params() 
    if (slider_mode == 2) then
      draw_values("global mults", "feedback", state.route_level_mult, "in", state.in_level_mult)
    elseif (focus.x > 1 and focus.x < 8 and focus.y < 7) then
      local idx = route_index(focus.y, focus.x - 1)
      draw_values("fb " .. (focus.x-1) .. "->" .. focus.y, "level", state.route_levels[idx], "time", state.delay_times[focus.y])
    elseif (focus.x == 1 and focus.y < 7) then
      draw_values("in " .. focus.y, "level", state.in_levels[focus.y], "pan", state.in_pans[focus.y])
    elseif (focus.y == 7 and focus.x > 1) then
      draw_values("out " .. (focus.x-1), "level", state.out_levels[focus.x-1], "pan", state.out_pans[focus.x-1])
    end
end

function redraw()
  print("redraw start")
  screen.clear()
  draw_frame()
  draw_grid()
  draw_params()
  screen.stroke()
  screen.update()
  print("redraw end")
end