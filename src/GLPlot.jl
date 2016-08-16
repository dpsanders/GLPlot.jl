__precompile__(true)
module GLPlot

export glplot

using GLVisualize, GLWindow, ModernGL, Reactive, GLAbstraction, Colors
using FixedPointNumbers, FreeType, SignedDistanceFields, Images, Packing
using GeometryTypes, GLFW, FileIO, FixedSizeArrays, Quaternions
import GLVisualize: toggle_button, toggle, button

export imload


include("editing.jl")

function imload(name)
    rotl90(Matrix{BGRA{U8}}(load(Pkg.dir("GLPlot", "src", "icons", name))))
end

const w_dividor = 32

toolbar_area(pa) = SimpleRectangle(0, 0, round(Int, pa.w/w_dividor), pa.h)
viewing_area(area_l, area_r) = SimpleRectangle(area_l.w, 0, area_r.x-area_l.w, area_r.h)
function edit_rectangle(visible, area, tarea, arrow_pos_s)
    w = visible ? div(area.w,4) : 0
    x = area.w-w
    push!(arrow_pos_s, [Point2f0(x-tarea.w, area.h/2)])
    SimpleRectangle(x, 0, w, area.h)
end

function item_area(la, deleted, item_height)
    y = la.y-item_height-2
    deleted && return SimpleRectangle(la.x, la.y, la.w, 0)
    return SimpleRectangle(la.x, y, la.w, item_height)
end

function edit_item_area(la, item_height)
    y = la.y-item_height-2
    return SimpleRectangle(3, y, la.w, item_height)
end
layout_pos_ho(i) = map(icon_percent) do ip
    SimpleRectangle{Float32}(0, i*ip + i*2, ip, ip)
end
layout_pos_ver(i, border) = map(icon_percent) do ip
    SimpleRectangle{Float32}(i*ip + i*border, 0, ip, ip)
end
function glplot(arg1, style=:default; kw_args...)
    visible_button, visible_toggle = toggle_button(
        imload("showing.png"), imload("notshowing.png"), edit_screen
    )
    delete_button, del_signal = button(
        imload("delete.png"), edit_screen
    )
    edit_button, no_edit_signal = toggle_button(
        imload("play.png"), rotr90(imload("play.png")), edit_screen
    )
    item_height = Signal(0)
    robj = visualize(arg1, style; visible=visible_toggle, kw_args...).children[]
    _view(robj, viewing_screen)
    not_del_signal = droprepeats(foldp(false, del_signal) do v0, to_delete
        v0 && return v0
        to_delete && delete!(viewing_screen, robj)
        return to_delete
    end)
    scroll = edit_screen.inputs[:menu_scroll]
    icon_size = map(Int, icon_percent)
    if isempty(edit_screen.children)
        last_area = map(edit_screen.area, not_del_signal, icon_size, scroll) do a, deleted, ih, s
            deleted && return SimpleRectangle(3, a.h+s, a.w-6, 0)
            return SimpleRectangle(3, a.h-ih+s, a.w-6, ih)
        end
    else
        last_area = last(edit_screen.children).area
    end
    edit_signal = map(!, no_edit_signal)
    itemarea = map(item_area, last_area, not_del_signal, icon_size)
    edititemarea = map(edit_item_area, itemarea, item_height)
    new_item_screen = Screen(edit_screen, area=itemarea)
    edit_item_screen = Screen(edit_screen, area=edititemarea)
    offset = 0f0
    for elem in (visible_button, delete_button, edit_button)
        layout!(layout_pos_ver(offset, 2), elem)
        _view(elem, new_item_screen, camera=:fixed_pixel)
        offset += 1
    end
    preserve(foldp((false, value(item_height)), edit_signal) do v0, edit
        if edit
            if !v0[1] # only do this at the first time
                new_heights = extract_edit_menu(robj, edit_item_screen, edit_signal)
                nh = ceil(Int, new_heights)
                push!(item_height, nh)
                return true, nh
            else
                push!(item_height, v0[2])
            end
        else
            push!(item_height, 0)
        end
        return v0
    end)

    robj
end

function save_record(frames)
    path = joinpath(homedir(), "Desktop")
    GLVisualize.create_video(frames, "test.webm", path, 1)
end

const _compute_callbacks = []
register_compute(f) = push!(_compute_callbacks, f)
export register_compute

function glplot_renderloop(window, compute_s, record_s)
    was_recording = false
    frames = []
    i = 1
    while isopen(window)
        if !value(compute_s) && !isempty(_compute_callbacks)
            _compute_callbacks[end](i)
            i += 1
        end
        render_frame(window)
        record = !value(record_s)
        if record
            push!(frames, screenbuffer(window))
        elseif was_recording && !record
            save_record(frames)
            frames = []
            gc()
        end
        GLFW.PollEvents()
        was_recording = record
        yield()
        GLWindow.swapbuffers(window)
    end
    destroy!(window)
end


function get_dpi(window)
    monitor = GLFW.GetPrimaryMonitor()
    props = GLWindow.MonitorProperties(monitor)
    props.dpi
end
function init()

    w = glscreen("GLPlot")
    dpi = (285/get_dpi(w)[1])

    global const icon_percent = Signal(round(Int, 50dpi))
    w.inputs[:key_pressed] = const_lift(GLAbstraction.singlepressed,
        w.inputs[:mouse_buttons_pressed],
        GLFW.MOUSE_BUTTON_LEFT
    )
    button_pos = Signal([Point2f0(w.area.value.w, w.area.value.h/2)])
    edit_screen_show_button = visualize(
        (SimpleRectangle(-15,-15, 15, 30), button_pos),
        color=RGBA{Float32}(0.6,0.6,0.6,1)
    )
    tarea = map(toolbar_area, w.area)

    show_edit_screen = toggle(edit_screen_show_button, w, false)
    edit_screen_area = map(edit_rectangle,
        show_edit_screen, w.area, tarea, Signal(button_pos)
    )


    global const viewing_screen = Screen(w,
        area=map(viewing_area, tarea, edit_screen_area),
        color=RGBA{Float32}(1,1,1,1)
    )
    global const toolbar_screen = Screen(w, area=tarea)
    global const edit_screen = Screen(
        w, area=edit_screen_area,
        color=RGBA{Float32}(0.9,0.9,0.9,1)
    )

    play_record, record_sig = toggle_button(imload("record.png"), imload("break.png"), w)
    compute_record, compute_sig = toggle_button(imload("play.png"), imload("break.png"), w)
    persp_ortho, persp_ortho_toggle_sig = toggle_button(imload("perspective.png"), imload("ortho.png"), w)
    persp_ortho_sig = map(persp_ortho_toggle_sig) do isp
        isp && return GLAbstraction.PERSPECTIVE
        GLAbstraction.ORTHOGRAPHIC
    end
    cube = cubecamera(viewing_screen, persp_ortho_sig)

    image_names = ["center", "screenshot"]
    tools = Matrix{BGRA{U8}}[imload("$name.png") for name in image_names]
    center_b, center_s = button(tools[1], w)
    screenshot_b, screenshot_s = button(tools[2], w)

    tools = [center_b, screenshot_b, play_record, persp_ortho, compute_record]
    tools_robjs = Any[]

    i = 0
    for tool in tools
        robj = layout!(layout_pos_ho(i), visualize(tool))
        _view(robj, toolbar_screen, camera=:fixed_pixel)
        push!(tools_robjs, robj.children[])
        i += 1
    end
    preserve(map(center_s) do pressed
        if pressed
            center!(viewing_screen)
        end
        nothing
    end)
    preserve(map(screenshot_s) do pressed
        if pressed
            screenshot(viewing_screen, path=joinpath(homedir(), "Desktop", "glplot.png"))
        end
        nothing
    end)
    rot = cube.children[][:model]

    cube.children[][:model] = map(rot, icon_percent) do r, ip
        half = ip/2
        translationmatrix(Vec3f0(half,i*ip + i*2 + half,0))*r*scalematrix(Vec3f0(half))
    end
    _view(cube, toolbar_screen, camera=:fixed_pixel)
    _view(edit_screen_show_button, viewing_screen, camera=:fixed_pixel)
    @materialize scroll, mouseposition = edit_screen.inputs
    should_scroll = map(mouseposition) do mb
        isinside(value(w.area), mb...)
    end
    scroll = filterwhen(should_scroll, value(scroll), scroll)
    edit_screen.inputs[:menu_scroll] = foldp(0, scroll) do v0, s
        v0+(ceil(Int, s[2])*15)
    end
    @async glplot_renderloop(w, compute_sig, record_sig)
    viewing_screen
end


include("glp_userimg.jl")

end
