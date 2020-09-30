// module implementations.imgui.imgui_impl_sdl;

// // dear imgui: Platform Binding for SDL2
// // This needs to be used along with a Renderer (e.g. DirectX11, OpenGL3, Vulkan..)
// // (Info: SDL2 is a cross-platform general purpose library for handling windows, inputs, graphics context creation, etc.)
// // (Requires: SDL 2.0. Prefer SDL 2.0.4+ for full feature support.)

// // Implemented features:
// //  [X] Platform: Mouse cursor shape and visibility. Disable with 'io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange'.
// //  [X] Platform: Clipboard support.
// //  [X] Platform: Keyboard arrays indexed using SDL_SCANCODE_* codes, e.g. igIsKeyPressed(SDL_SCANCODE_SPACE).
// //  [X] Platform: Gamepad support. Enabled with 'io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad'.
// // Missing features:
// //  [ ] Platform: SDL2 handling of IME under Windows appears to be broken and it explicitly disable the regular Windows IME. You can restore Windows IME by compiling SDL with SDL_DISABLE_WINDOWS_IME.

// // You can copy and use unmodified imgui_impl_* files in your project. See main.cpp for an example of using this.
// // If you are new to dear imgui, read examples/README.txt and read the documentation at the top of imgui.cpp.
// // https://github.com/ocornut/imgui

// // CHANGELOG
// // (minor and older changes stripped away, please see git history for details)
// //  2020-05-25: Misc: Report a zero display-size when window is minimized, to be consistent with other backends.
// //  2020-02-20: Inputs: Fixed mapping for ImGuiKey_KeyPadEnter (using SDL_SCANCODE_KP_ENTER instead of SDL_SCANCODE_RETURN2).
// //  2019-12-17: Inputs: On Wayland, use SDL_GetMouseState (because there is no global mouse state).
// //  2019-12-05: Inputs: Added support for ImGuiMouseCursor_NotAllowed mouse cursor.
// //  2019-07-21: Inputs: Added mapping for ImGuiKey_KeyPadEnter.
// //  2019-04-23: Inputs: Added support for SDL_GameController (if ImGuiConfigFlags_NavEnableGamepad is set by user application).
// //  2019-03-12: Misc: Preserve DisplayFramebufferScale when main window is minimized.
// //  2018-12-21: Inputs: Workaround for Android/iOS which don't seem to handle focus related calls.
// //  2018-11-30: Misc: Setting up io.BackendPlatformName so it can be displayed in the About Window.
// //  2018-11-14: Changed the signature of ImGui_ImplSDL2_ProcessEvent() to take a 'const SDL_Event*'.
// //  2018-08-01: Inputs: Workaround for Emscripten which doesn't seem to handle focus related calls.
// //  2018-06-29: Inputs: Added support for the ImGuiMouseCursor_Hand cursor.
// //  2018-06-08: Misc: Extracted imgui_impl_sdl.cpp/.h away from the old combined SDL2+OpenGL/Vulkan examples.
// //  2018-06-08: Misc: ImGui_ImplSDL2_InitForOpenGL() now takes a SDL_GLContext parameter.
// //  2018-05-09: Misc: Fixed clipboard paste memory leak (we didn't call SDL_FreeMemory on the data returned by SDL_GetClipboardText).
// //  2018-03-20: Misc: Setup io.BackendFlags ImGuiBackendFlags_HasMouseCursors flag + honor ImGuiConfigFlags_NoMouseCursorChange flag.
// //  2018-02-16: Inputs: Added support for mouse cursors, honoring igGetMouseCursor() value.
// //  2018-02-06: Misc: Removed call to igShutdown() which is not available from 1.60 WIP, user needs to call CreateContext/DestroyContext themselves.
// //  2018-02-06: Inputs: Added mapping for ImGuiKey_Space.
// //  2018-02-05: Misc: Using SDL_GetPerformanceCounter() instead of SDL_GetTicks() to be able to handle very high framerate (1000+ FPS).
// //  2018-02-05: Inputs: Keyboard mapping is using scancodes everywhere instead of a confusing mixture of keycodes and scancodes.
// //  2018-01-20: Inputs: Added Horizontal Mouse Wheel support.
// //  2018-01-19: Inputs: When available (SDL 2.0.4+) using SDL_CaptureMouse() to retrieve coordinates outside of client area when dragging. Otherwise (SDL 2.0.3 and before) testing for SDL_WINDOW_INPUT_FOCUS instead of SDL_WINDOW_MOUSE_FOCUS.
// //  2018-01-18: Inputs: Added mapping for ImGuiKey_Insert.
// //  2017-08-25: Inputs: MousePos set to -FLT_MAX,-FLT_MAX when mouse is unavailable/missing (instead of -1,-1).
// //  2016-10-15: Misc: Added a void* user_data parameter to Clipboard function handlers.


// // SDL
import cimgui;
import bindbc.sdl;
import imgui.imgui_impl_opengl3 : IM_ASSERT, IM_ARRAYSIZE;
import core.stdc.string : memset, strncpy, strncmp;
enum SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE =     sdlSupport >= SDLSupport.sdl204;
enum SDL_HAS_VULKAN                   =     sdlSupport >= SDLSupport.sdl206;

// // Data
static SDL_Window*  g_Window = null;
static Uint64       g_Time = 0;
static bool[3]      g_MousePressed = [false, false, false];
static SDL_Cursor*[ImGuiMouseCursor_COUNT]  g_MouseCursors;
static char*        g_ClipboardTextData = null;
static bool         g_MouseCanUseGlobalState = true;


enum MAP_BUTTON_SDL(ImGuiIO* io, float NAV_NO, SDL_GameControllerButton BUTTON_NO)
{
    io.NavInputs[NAV_NO] = (SDL_GameControllerGetButton(game_controller, BUTTON_NO) != 0) ? 1.0f : 0.0f;
}
enum MAP_ANALOG_SDL(ImGuiIO* io, float NAV_NO, SDL_GameControllerAxis AXIS_NO, int V0, int V1)
{
    float vn = cast(float)(SDL_GameControllerGetAxis(game_controller, AXIS_NO) - V0) / cast(float)(V1 - V0);
    if (vn > 1.0f) 
        vn = 1.0f; 
    if (vn > 0.0f && io.NavInputs[NAV_NO] < vn) 
        io.NavInputs[NAV_NO] = vn;
}


/// SDL_gamecontroller.h suggests using this value.
enum thumb_dead_zone = 8000;


static const (char)* ImGui_ImplSDL2_GetClipboardText(void*)
{
    if (g_ClipboardTextData)
        SDL_free(g_ClipboardTextData);
    g_ClipboardTextData = SDL_GetClipboardText();
    return g_ClipboardTextData;
}


static void ImGui_ImplSDL2_SetClipboardText(void*, const char* text)
{
    SDL_SetClipboardText(text);
}

// // You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
// // - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application.
// // - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application.
// // Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
// // If you have multiple SDL events and some of them are not meant to be used by dear imgui, you may need to filter events based on their windowID field.
bool ImGui_ImplSDL2_ProcessEvent(const SDL_Event* event)
{
    ImGuiIO* io = igGetIO();
    switch (event.type)
    {
        case SDL_MOUSEWHEEL:
        {
            if (event.wheel.x > 0) io.MouseWheelH += 1;
            if (event.wheel.x < 0) io.MouseWheelH -= 1;
            if (event.wheel.y > 0) io.MouseWheel += 1;
            if (event.wheel.y < 0) io.MouseWheel -= 1;
            return true;
        }
        case SDL_MOUSEBUTTONDOWN:
        {
            if (event.button.button == SDL_BUTTON_LEFT) g_MousePressed[0] = true;
            if (event.button.button == SDL_BUTTON_RIGHT) g_MousePressed[1] = true;
            if (event.button.button == SDL_BUTTON_MIDDLE) g_MousePressed[2] = true;
            return true;
        }
        case SDL_TEXTINPUT:
        {
            io.AddInputCharactersUTF8(event.text.text);
            return true;
        }
        case SDL_KEYDOWN:
        case SDL_KEYUP:
        {
            int key = event.key.keysym.scancode;
            IM_ASSERT(key >= 0 && key < IM_ARRAYSIZE(io.KeysDown));
            io.KeysDown[key] = (event.type == SDL_KEYDOWN);
            io.KeyShift = ((SDL_GetModState() & KMOD_SHIFT) != 0);
            io.KeyCtrl = ((SDL_GetModState() & KMOD_CTRL) != 0);
            io.KeyAlt = ((SDL_GetModState() & KMOD_ALT) != 0);
            version(Win32)
            {
                io.KeySuper = false;
            }
            else
            {
                io.KeySuper = ((SDL_GetModState() & KMOD_GUI) != 0);
            }
            return true;
        }
    }
    return false;
}

static bool ImGui_ImplSDL2_Init(SDL_Window* window)
{
    g_Window = window;

    // Setup back-end capabilities flags
    ImGuiIO* io = igGetIO();
    io.BackendFlags |= ImGuiBackendFlags_HasMouseCursors;       // We can honor GetMouseCursor() values (optional)
    io.BackendFlags |= ImGuiBackendFlags_HasSetMousePos;        // We can honor io.WantSetMousePos requests (optional, rarely used)
    io.BackendPlatformName = "imgui_impl_sdl";

    // Keyboard mapping. ImGui will use those indices to peek into the io.KeysDown[] array.
    io.KeyMap[ImGuiKey_Tab] = SDL_SCANCODE_TAB;
    io.KeyMap[ImGuiKey_LeftArrow] = SDL_SCANCODE_LEFT;
    io.KeyMap[ImGuiKey_RightArrow] = SDL_SCANCODE_RIGHT;
    io.KeyMap[ImGuiKey_UpArrow] = SDL_SCANCODE_UP;
    io.KeyMap[ImGuiKey_DownArrow] = SDL_SCANCODE_DOWN;
    io.KeyMap[ImGuiKey_PageUp] = SDL_SCANCODE_PAGEUP;
    io.KeyMap[ImGuiKey_PageDown] = SDL_SCANCODE_PAGEDOWN;
    io.KeyMap[ImGuiKey_Home] = SDL_SCANCODE_HOME;
    io.KeyMap[ImGuiKey_End] = SDL_SCANCODE_END;
    io.KeyMap[ImGuiKey_Insert] = SDL_SCANCODE_INSERT;
    io.KeyMap[ImGuiKey_Delete] = SDL_SCANCODE_DELETE;
    io.KeyMap[ImGuiKey_Backspace] = SDL_SCANCODE_BACKSPACE;
    io.KeyMap[ImGuiKey_Space] = SDL_SCANCODE_SPACE;
    io.KeyMap[ImGuiKey_Enter] = SDL_SCANCODE_RETURN;
    io.KeyMap[ImGuiKey_Escape] = SDL_SCANCODE_ESCAPE;
    io.KeyMap[ImGuiKey_KeyPadEnter] = SDL_SCANCODE_KP_ENTER;
    io.KeyMap[ImGuiKey_A] = SDL_SCANCODE_A;
    io.KeyMap[ImGuiKey_C] = SDL_SCANCODE_C;
    io.KeyMap[ImGuiKey_V] = SDL_SCANCODE_V;
    io.KeyMap[ImGuiKey_X] = SDL_SCANCODE_X;
    io.KeyMap[ImGuiKey_Y] = SDL_SCANCODE_Y;
    io.KeyMap[ImGuiKey_Z] = SDL_SCANCODE_Z;

    io.SetClipboardTextFn = &ImGui_ImplSDL2_SetClipboardText;
    io.GetClipboardTextFn = &ImGui_ImplSDL2_GetClipboardText;
    io.ClipboardUserData = null;

    // Load mouse cursors
    g_MouseCursors[ImGuiMouseCursor_Arrow] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
    g_MouseCursors[ImGuiMouseCursor_TextInput] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_IBEAM);
    g_MouseCursors[ImGuiMouseCursor_ResizeAll] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZEALL);
    g_MouseCursors[ImGuiMouseCursor_ResizeNS] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZENS);
    g_MouseCursors[ImGuiMouseCursor_ResizeEW] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZEWE);
    g_MouseCursors[ImGuiMouseCursor_ResizeNESW] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZENESW);
    g_MouseCursors[ImGuiMouseCursor_ResizeNWSE] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_SIZENWSE);
    g_MouseCursors[ImGuiMouseCursor_Hand] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_HAND);
    g_MouseCursors[ImGuiMouseCursor_NotAllowed] = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_NO);

    // Check and store if we are on Wayland
    g_MouseCanUseGlobalState = strncmp(SDL_GetCurrentVideoDriver(), "wayland", 7) != 0;

    version(Win32)
    {
        SDL_SysWMinfo wmInfo;
        SDL_VERSION(&wmInfo.version_);
        SDL_GetWindowWMInfo(window, &wmInfo);
        io.ImeWindowHandle = wmInfo.info.win.window;
    }
    else
    {
        cast(void)window;
    }
    return true;
}

bool ImGui_ImplSDL2_InitForOpenGL(SDL_Window* window, void* sdl_gl_context)
{
    cast(void)sdl_gl_context; // Viewport branch will need this.
    return ImGui_ImplSDL2_Init(window);
}

bool ImGui_ImplSDL2_InitForVulkan(SDL_Window* window)
{
    static if(!SDL_HAS_VULKAN)
    {
        IM_ASSERT(0 && "Unsupported");
    }
    return ImGui_ImplSDL2_Init(window);
}

bool ImGui_ImplSDL2_InitForD3D(SDL_Window* window)
{
    version(Windows){}
    else
    {
        IM_ASSERT(0 && "Unsupported");
    }
    return ImGui_ImplSDL2_Init(window);
}

bool ImGui_ImplSDL2_InitForMetal(SDL_Window* window)
{
    return ImGui_ImplSDL2_Init(window);
}

void ImGui_ImplSDL2_Shutdown()
{
    g_Window = null;

    // Destroy last known clipboard data
    if (g_ClipboardTextData)
        SDL_free(g_ClipboardTextData);
    g_ClipboardTextData = null;

    // Destroy SDL mouse cursors
    for (ImGuiMouseCursor cursor_n = 0; cursor_n < ImGuiMouseCursor_COUNT; cursor_n++)
        SDL_FreeCursor(g_MouseCursors[cursor_n]);
    memset(g_MouseCursors, 0, g_MouseCursors.sizeof);
}

static void ImGui_ImplSDL2_UpdateMousePosAndButtons()
{
    ImGuiIO* io = igGetIO();

    // Set OS mouse position if requested (rarely used, only when ImGuiConfigFlags_NavEnableSetMousePos is enabled by user)
    if (io.WantSetMousePos)
        SDL_WarpMouseInWindow(g_Window, cast(int)io.MousePos.x, cast(int)io.MousePos.y);
    else
        io.MousePos = ImVec2(-igGET_FLT_MAX(), -igGET_FLT_MAX());

    int mx, my;
    Uint32 mouse_buttons = SDL_GetMouseState(&mx, &my);
    io.MouseDown[0] = g_MousePressed[0] || (mouse_buttons & SDL_BUTTON!SDL_BUTTON_LEFT)) != 0;  // If a mouse press event came, always pass it as "mouse held this frame", so we don't miss click-release events that are shorter than 1 frame.
    io.MouseDown[1] = g_MousePressed[1] || (mouse_buttons & SDL_BUTTON!SDL_BUTTON_RIGHT)) != 0;
    io.MouseDown[2] = g_MousePressed[2] || (mouse_buttons & SDL_BUTTON!SDL_BUTTON_MIDDLE)) != 0;
    g_MousePressed[0] = g_MousePressed[1] = g_MousePressed[2] = false;

    static if(SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE)
    {
        SDL_Window* focused_window = SDL_GetKeyboardFocus();
        if (g_Window == focused_window)
        {
            if (g_MouseCanUseGlobalState)
            {
                // SDL_GetMouseState() gives mouse position seemingly based on the last window entered/focused(?)
                // The creation of a new windows at runtime and SDL_CaptureMouse both seems to severely mess up with that, so we retrieve that position globally.
                // Won't use this workaround when on Wayland, as there is no global mouse position.
                int wx, wy;
                SDL_GetWindowPosition(focused_window, &wx, &wy);
                SDL_GetGlobalMouseState(&mx, &my);
                mx -= wx;
                my -= wy;
            }
            io.MousePos = ImVec2(cast(float)mx, cast(float)my);
        }

        // SDL_CaptureMouse() let the OS know e.g. that our imgui drag outside the SDL window boundaries shouldn't e.g. trigger the OS window resize cursor.
        // The function is only supported from SDL 2.0.4 (released Jan 2016)
        bool any_mouse_button_down = igIsAnyMouseDown();
        SDL_CaptureMouse(any_mouse_button_down ? SDL_TRUE : SDL_FALSE);

    }
    else
    {
        if (SDL_GetWindowFlags(g_Window) & SDL_WINDOW_INPUT_FOCUS)
            io.MousePos = ImVec2(cast(float)mx, cast(float)my);
    }
}

static void ImGui_ImplSDL2_UpdateMouseCursor()
{
    ImGuiIO* io = igGetIO();
    if (io.ConfigFlags & ImGuiConfigFlags_NoMouseCursorChange)
        return;

    ImGuiMouseCursor imgui_cursor = igGetMouseCursor();
    if (io.MouseDrawCursor || imgui_cursor == ImGuiMouseCursor_None)
    {
        // Hide OS mouse cursor if imgui is drawing it or if it wants no cursor
        SDL_ShowCursor(SDL_FALSE);
    }
    else
    {
        // Show OS mouse cursor
        SDL_SetCursor(g_MouseCursors[imgui_cursor] ? g_MouseCursors[imgui_cursor] : g_MouseCursors[ImGuiMouseCursor_Arrow]);
        SDL_ShowCursor(SDL_TRUE);
    }
}

static void ImGui_ImplSDL2_UpdateGamepads()
{
    ImGuiIO* io = igGetIO();
    memset(cast(void*)io.NavInputs, 0, io.NavInputs.sizeof);
    if ((io.ConfigFlags & ImGuiConfigFlags_NavEnableGamepad) == 0)
        return;

    // Get gamepad
    SDL_GameController* game_controller = SDL_GameControllerOpen(0);
    if (!game_controller)
    {
        io.BackendFlags &= ~ImGuiBackendFlags_HasGamepad;
        return;
    }

    // Update gamepad inputs
    MAP_BUTTON_SDL(io,ImGuiNavInput_Activate,      SDL_CONTROLLER_BUTTON_A);               // Cross / A
    MAP_BUTTON_SDL(io,ImGuiNavInput_Cancel,        SDL_CONTROLLER_BUTTON_B);               // Circle / B
    MAP_BUTTON_SDL(io,ImGuiNavInput_Menu,          SDL_CONTROLLER_BUTTON_X);               // Square / X
    MAP_BUTTON_SDL(io,ImGuiNavInput_Input,         SDL_CONTROLLER_BUTTON_Y);               // Triangle / Y
    MAP_BUTTON_SDL(io,ImGuiNavInput_DpadLeft,      SDL_CONTROLLER_BUTTON_DPAD_LEFT);       // D-Pad Left
    MAP_BUTTON_SDL(io,ImGuiNavInput_DpadRight,     SDL_CONTROLLER_BUTTON_DPAD_RIGHT);      // D-Pad Right
    MAP_BUTTON_SDL(io,ImGuiNavInput_DpadUp,        SDL_CONTROLLER_BUTTON_DPAD_UP);         // D-Pad Up
    MAP_BUTTON_SDL(io,ImGuiNavInput_DpadDown,      SDL_CONTROLLER_BUTTON_DPAD_DOWN);       // D-Pad Down
    MAP_BUTTON_SDL(io,ImGuiNavInput_FocusPrev,     SDL_CONTROLLER_BUTTON_LEFTSHOULDER);    // L1 / LB
    MAP_BUTTON_SDL(io,ImGuiNavInput_FocusNext,     SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);   // R1 / RB
    MAP_BUTTON_SDL(io,ImGuiNavInput_TweakSlow,     SDL_CONTROLLER_BUTTON_LEFTSHOULDER);    // L1 / LB
    MAP_BUTTON_SDL(io,ImGuiNavInput_TweakFast,     SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);   // R1 / RB
    MAP_ANALOG_SDL(io,ImGuiNavInput_LStickLeft,    SDL_CONTROLLER_AXIS_LEFTX, -thumb_dead_zone, -32_768);
    MAP_ANALOG_SDL(io,ImGuiNavInput_LStickRight,   SDL_CONTROLLER_AXIS_LEFTX, +thumb_dead_zone, +32_767);
    MAP_ANALOG_SDL(io,ImGuiNavInput_LStickUp,      SDL_CONTROLLER_AXIS_LEFTY, -thumb_dead_zone, -32_767);
    MAP_ANALOG_SDL(io,ImGuiNavInput_LStickDown,    SDL_CONTROLLER_AXIS_LEFTY, +thumb_dead_zone, +32_767);

    io.BackendFlags |= ImGuiBackendFlags_HasGamepad;
}

void ImGui_ImplSDL2_NewFrame(SDL_Window* window)
{
    ImGuiIO* io = igGetIO();
    IM_ASSERT(ImFontAtlas_IsBuilt(io.Fonts) && "Font atlas not built! It is generally built by the renderer back-end. Missing call to renderer _NewFrame() function? e.g. ImGui_ImplOpenGL3_NewFrame().");

    // Setup display size (every frame to accommodate for window resizing)
    int w, h;
    int display_w, display_h;
    SDL_GetWindowSize(window, &w, &h);
    if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED)
        w = h = 0;
    SDL_GL_GetDrawableSize(window, &display_w, &display_h);
    io.DisplaySize = ImVec2(cast(float)w, cast(float)h);
    if (w > 0 && h > 0)
        io.DisplayFramebufferScale = ImVec2(cast(float)display_w / w, cast(float)display_h / h);

    // Setup time step (we don't use SDL_GetTicks() because it is using millisecond resolution)
    static if(staticBinding)
    {
        static Uint64 frequency = SDL_GetPerformanceFrequency();
    }
    else
    {
        Uint64 frequency = SDL_GetPerformanceFrequency();
    }
    Uint64 current_time = SDL_GetPerformanceCounter();
    io.DeltaTime = g_Time > 0 ? cast(float)(cast(double)(current_time - g_Time) / frequency) : cast(float)(1.0f / 60.0f);
    g_Time = current_time;

    ImGui_ImplSDL2_UpdateMousePosAndButtons();
    ImGui_ImplSDL2_UpdateMouseCursor();

    // Update game controllers (if enabled and available)
    ImGui_ImplSDL2_UpdateGamepads();
}