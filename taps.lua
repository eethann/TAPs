-- TAPs: delay matrix for norns
-- tap apt pats
local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/mg_128" or grid
g = grid.connect()

-- TODO allow 7 switchable configurations (may rework data structure into just 2 matrices)
-- TODO refactor this into a UI lib
local viewport = { width = 128, height = 64, frame = 0 }
local focus = { x = 1, y = 1, brightness = 15 }
local keys_status = {0,0,0}
local sliders = {}
local slider_mode = 0
local grid_slider_mode = 0

in_states = {}
out_states = {}
route_states = {}

in_level_mult = 1.0
in_levels = {}
out_levels = {}
route_levels = {}
route_level_mult = 1.0

in_pans = {}
out_pans = {}

delay_times = {}

function init()
  -- TODO refactor this to be 0 indexed, 1 base is a pain
  for i=1,6 do
    in_states[i] = 0
    in_levels[i] = 0.9
    out_states[i] = 1
    out_levels[i] = 0.9
    out_pans[i] = -0.75 + 0.75 * (i % 3)
    in_pans[i] = 0.75 - 1.5 * (i % 2)
    delay_times[i] = 0.25*i
    for j=1,6 do
      route_levels[route_index(i,j)] = 0.75
      route_states[route_index(i,j)] = 0
    end
  end
  in_states[1] = 1;
  for i=0,5 do
    route_states[route_index(((i+1)%6)+1,i+1)] = 1
  end
  screen_init()
  softcut_init()
  softcut_update()
  redraw()
  grid_redraw()
end

function route_index(destination, source) 
  return destination * 6 + source
end

function loop_start_time(ch)
  return (ch - 1) * 36 + 1
end

function loop_end_time(ch) 
  return loop_start_time(ch) + util.clamp(delay_times[ch]*clock.get_beat_sec(),0,35)
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

  for playhead=1,6 do
    softcut.buffer(playhead, 1)
    softcut.enable(playhead, 1)
    -- set loop points for each head so they are separate delays
    softcut.loop_start(playhead,loop_start_time(playhead))
    softcut.loop_end(playhead,loop_end_time(playhead))
    softcut.position(playhead, loop_start_time(playhead))
    softcut.loop(playhead, 1)
    -- TODO determine if we can use level_cut_cut(X,X) for feedback or need to use pre_level
    softcut.pre_level(playhead, 0)
    softcut.rec_level(playhead, 1)
    softcut.play(playhead, 1)
    softcut.rec(playhead, 1)
    softcut.rate(playhead, 1)
    softcut.level(playhead, 0) 
    softcut.fade_time(playhead, 0.02)
    softcut.level_slew_time(playhead, 0.01)
    softcut.rate_slew_time(playhead, 0.01)
    softcut.filter_dry(playhead, 1)
    -- softcut.filter_fc(playhead, 0)
    softcut.filter_lp(playhead, 0)
    softcut.filter_bp(playhead, 0)
    softcut.filter_rq(playhead, 0)
  end
end

function softcut_update() 
  for playhead=1,6 do
    -- TODO offer option for speed (tape) or buffer len (digital) time control
    softcut.loop_end(playhead,loop_end_time(playhead))
    -- TODO immplement proper panning
    softcut.level_input_cut(1,playhead,util.linlin(-1,1,0,1,in_pans[playhead]) * in_states[playhead] * in_levels[playhead] * in_level_mult)
    softcut.level_input_cut(2,playhead,util.linlin(1,-1,0,1,in_pans[playhead]) * in_states[playhead] * in_levels[playhead] * in_level_mult)
    softcut.level(playhead, out_states[playhead] * out_levels[playhead])
    softcut.pan(playhead, out_pans[playhead]) 
    for source=1,6 do
      route_level = route_level_mult*route_states[route_index(playhead,source)]*route_levels[route_index(playhead,source)]
      if (source == playhead) then
        softcut.pre_level(playhead,route_level)
      else
        softcut.level_cut_cut(source,playhead,route_level)
      end
    end
  end
end

function is_connected()
  return g.device ~= nil
end

-- TODO handle connect and disconnect, assign key func on connect
g.key = function(x,y,z)
  if y == 8 and x == 8 then
    grid_slider_mode = z
  elseif (grid_slider_mode == 0) then
    if z == 1 then
      if y < 7 then
        if (x == 1) then
          in_states[y] = toggle(in_states[y])
        elseif (x > 1) and (x < 8) then
          route_states[route_index(y,x-1)] = toggle(route_states[route_index(y,x-1)])
        end
      elseif y == 7 then
        out_states[x-1] = toggle(out_states[x-1])
      end
      focus = { x = x, y = y}
    end
  else
    if z == 1 then
      if x < 8 and y < 8 then
        focus = { x = x, y = y}
      elseif x == 8 and y < 8 then
        update_slider_val(1,-1*(y-4))
      elseif y == 8 and x < 8 then
        update_slider_val(2,(x-4))
      end
    end
  end
  redraw()
  softcut_update()
  grid_redraw()
end

function grid_redraw()
  if is_connected() ~= true then return end
  g:all(0)
  for i=1,6 do
    g:led(1,i,in_states[i] == 1 and 15 or 1)
    for j=1,6 do
      g:led(j+1,i,route_states[route_index(i,j)] == 1 and 15 or 1)
    end
    g:led(i+1,7,out_states[i] == 1 and 15 or 1)
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
        route_states[route_index(focus.x - 1,focus.y)] = toggle(route_states[route_index(focus.x - 1, focus.y)])
      elseif (focus.x == 1 and focus.y < 7) then
        in_states[focus.y] = toggle(in_states[focus.y])
      elseif (focus.y == 7 and focus.x > 1) then
        out_states[focus.x-1] = toggle(out_states[focus.x-1])
      end
    end 
  end
  -- may trigger unneeded updates
  softcut_update()
  grid_redraw()
  redraw()
end

function update_slider_val(n,d)
  local step_size = 0.05
  print("updating slider " .. n .. " " .. d)
  if (focus.x > 1 and focus.x < 8 and focus.y < 7) then
    local idx = route_index(focus.y, focus.x - 1)
    if n == 1 then
      route_levels[idx] = util.clamp(route_levels[idx]+(d*step_size),0.0,1.0) 
    elseif n == 2 then
      delay_times[focus.y] = util.clamp(delay_times[focus.y]+(d*0.25),0.0,16.0) 
    end
  elseif (focus.x == 1 and focus.y < 7) then
    if n == 1 then
      in_levels[focus.y] = util.clamp(in_levels[focus.y]+(d*step_size),0.0,1.0) 
    elseif n == 2 then
      in_pans[focus.y] = util.clamp(in_pans[focus.y]+(d*step_size),-1.0,1.0) 
    end
  elseif (focus.y == 7 and focus.x > 1) then
    if n == 1 then
      out_levels[focus.x-1] = util.clamp(out_levels[focus.x-1]+(d*step_size),0.0,1.0) 
    elseif n == 2 then
      out_pans[focus.x-1] = util.clamp(out_pans[focus.x-1]+(d*step_size),-1.0,1.0) 
    end
  elseif (focus.y==7 and focus.x==1) then
    -- TODO implement dry/wet balance
    if n == 1 then
    elseif n == 2 then
    end
  end
  softcut_update()
  redraw()
  grid_redraw()
end

-- TODO implement encode functionality via 8th col on grid
function enc(n,d)
  if (slider_mode == 2) then
    if n == 2 then
      route_level_mult = util.clamp(route_level_mult+(d*step_size),0.0,1.0) 
    elseif n == 3 then
      in_level_mult = util.clamp(in_level_mult+(d*step_size),0.0,1.0) 
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
    if (route_states[route_index(y,x-1)] == 1) then
      screen.level(8)
    else 
      screen.level(1)
    end
    screen.pixel((x*offset.spacing) + offset.x, (y*offset.spacing) + offset.y)
    screen.stroke()
  elseif (y == 7) and (x > 1) then
    if (out_states[x-1] == 1) then
      screen.level(8)
    else 
      screen.level(1)
    end
    screen.pixel((x*offset.spacing) + offset.x, (y*offset.spacing) + offset.y)
    screen.stroke()
  elseif (x == 1) and (y < 7) then
    if (in_states[y] == 1) then
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
      draw_values("global mults", "feedback", route_level_mult, "in", in_level_mult)
    elseif (focus.x > 1 and focus.x < 8 and focus.y < 7) then
      local idx = route_index(focus.y, focus.x - 1)
      draw_values("fb " .. (focus.x-1) .. "->" .. focus.y, "level", route_levels[idx], "time", delay_times[focus.y])
    elseif (focus.x == 1 and focus.y < 7) then
      draw_values("in " .. focus.y, "level", in_levels[focus.y], "pan", in_pans[focus.y])
    elseif (focus.y == 7 and focus.x > 1) then
      draw_values("out " .. (focus.x-1), "level", out_levels[focus.x-1], "pan", out_pans[focus.x-1])
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