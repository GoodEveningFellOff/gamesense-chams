local ffi = require("ffi");
local bit = require("bit");
ffi.cdef([[
    typedef struct {
        int id;
        int version;
        int checksum;
        char name[64];
    } studiohdr_t;

    typedef struct {
        studiohdr_t* studio_hdr;
        void* hardware_data;
        int32_t decals;
        int32_t skin;
        int32_t body;
        int32_t hitbox_set;
        void*** renderable;
    } DrawModelInfo_t;
]])


local MaterialIndexing = {
    base = {
        ["Off"] = 0;
        ["Invisible"] = 1;
        ["Material"] = 2;
        ["Color"] = 3;
        ["Flat"] = 4;
    };

    animated = {
        ["Disabled"] = 0;
        ["Tazer Beam"] = 1; 
        ["Hemisphere Height"] = 2; 
        ["Zone Warning"] = 3; 
        ["Bendybeam"] = 4; 
        ["Dreamhack"] = 5;
    };
};

local function CreateConfigGroup(name, file_extention)
    local n = "[" .. name .. "] ";

    local tbl = {
        main_option = ui.new_combobox("VISUALS", "Colored models", n .. "Base", {"Off", "Invisible", "Material", "Color", "Flat"});
        main_color = ui.new_color_picker("VISUALS", "Colored models", n .. "Base Color", 255, 255, 255, 255);
        main_pearlescense = ui.new_slider("VISUALS", "Colored models", n .. "Pearlescense", -100, 100, 0, true, "%", 1, {[0] = "Off"});
        main_rimglow = ui.new_slider("VISUALS", "Colored models", n .. "Rimglow", 0, 100, 0, true, "%", 1, {[0] = "Off"});
        main_reflectivity = ui.new_slider("VISUALS", "Colored models", n .. "Reflectivity", 0, 100, 0, true, "%", 1, {[0] = "Off"});

        spacer_1 = ui.new_label("VISUALS", "Colored models", " ");

        animated_option = ui.new_combobox("VISUALS", "Colored models", n .. "Animated", {"Disabled", "Tazer Beam", "Hemisphere Height", "Zone Warning", "Bendybeam", "Dreamhack"});
        animated_color = ui.new_color_picker("VISUALS", "Colored models", n .. "Animated Color", 255, 255, 255, 255);

        spacer_2 = ui.new_label("VISUALS", "Colored models", " ");

        glow_fill = ui.new_slider("VISUALS", "Colored models", n .. "Glow Fill", 0, 100, 0, true, "%", 1, {[0] = "Off"});
        glow_color = ui.new_color_picker("VISUALS", "Colored models", n .. "Glow Color", 255, 255, 255, 255);

        __wireframe = ui.new_multiselect("VISUALS", "Colored models", n .. "Wireframe", { "Main", "Animated", "Glow" });
        wireframe = {false, false, false};

        main_material = {[0] = nil; [1] = nil; [2] = nil;};
        pmain_material = {[0] = nil; [1] = nil; [2] = nil;};

        animated_material = {[0] = nil; [1] = nil; [2] = nil; [3] = nil; [4] = nil;};
        panimated_material = {[0] = nil; [1] = nil; [2] = nil; [3] = nil; [4] = nil;};

        glow_material =  nil;
        pglow_material = nil;

        set_visible = function(self, visible)
            ui.set_visible(self.main_option, visible)
            ui.set_visible(self.main_color, visible)
            ui.set_visible(self.main_pearlescense, visible)
            ui.set_visible(self.main_rimglow, visible)
            ui.set_visible(self.main_reflectivity, visible)
            ui.set_visible(self.spacer_1, visible)
            ui.set_visible(self.animated_option, visible)
            ui.set_visible(self.animated_color, visible)
            ui.set_visible(self.spacer_2, visible)
            ui.set_visible(self.glow_fill, visible)
            ui.set_visible(self.glow_color, visible)
            ui.set_visible(self.__wireframe, visible)
        end;
    };

    if name ~= "wp" then
        tbl:set_visible(false)
    end

    ui.set_callback(tbl.__wireframe, function()
        local wf = {false, false, false};

        for _, name in pairs(ui.get(tbl.__wireframe)) do
            wf[(name=="Main") and 1 or (name=="Animated") and 2 or 3] = true;
        end

        tbl.wireframe = wf;
    end)

    return tbl
end

local reload_materials = function() end;

local config = {
    [0] = ui.new_label("VISUALS", "Colored models", "====== [ Better Chams ] =====");
    selection = ui.new_combobox("VISUALS", "Colored models", "Group", { "Weapon", "Arms", "Sleeves", "Facemask", "Player" });

    weapon = CreateConfigGroup("wp", "wpn");
    arms = CreateConfigGroup("ar", "arm");
    sleeves = CreateConfigGroup("sl", "slv");
    facemask = CreateConfigGroup("ms", "msk");
    player = CreateConfigGroup("pl", "arm");

    __scoped_transparency = ui.new_slider("VISUALS", "Colored models", "Transparency In Scope", 0, 100, 0, true, "%", 1, {[0] = "Off";[100] = "Full"});
    scoped_transparency = 1;

    reload_materials = ui.new_button("VISUALS", "Colored models", "Reload Textures", function()
        reload_materials()
    end);
    
    [1] = ui.new_label("VISUALS", "Colored models", "====== [ Better Chams ] ======");
};

local menu_references = {
    local_player = ui.reference("VISUALS", "Colored models", "Local player");
    local_player_transparency = ui.reference("VISUALS", "Colored models", "Local player transparency");
    fake = ui.reference("VISUALS", "Colored models", "Local player fake");
    hands = ui.reference("VISUALS", "Colored models", "Hands");
    weapon_viewmodel = nil;
    weapon_viewmodel_color = nil;
    weapon_viewmodel_type = nil;
};

menu_references.weapon_viewmodel, menu_references.weapon_viewmodel_color, menu_references.weapon_viewmodel_type = ui.reference("VISUALS", "Colored models", "Weapon viewmodel");

local interfaces = {
    material_system = ffi.cast("void***", client.create_interface("materialsystem.dll", "VMaterialSystem080"));
    studio_render = ffi.cast("void***", client.create_interface("studiorender.dll", "VStudioRender026"));
};

local client_proxy = { -- Thank you NEZU https://github.com/nezu-cc/ServerCrasher/blob/main/GS/Crasher.lua
    --call    sub_10996300 ; 51 C3
    __address = client.find_signature("client.dll", "\x51\xC3");

    cast = function(self, typeof)
        return ffi.cast(ffi.typeof(typeof), self.__address)
    end;

    bind = function(self, typeof, address)
        local cast = self:cast(typeof);

        return function(...)
            return cast(address, ...)
        end
    end;

    call = function(self, typeof, address, ...)
        return self:cast(typeof)(address, ...)
    end;
};

local Memoryapi = {
    __VirtualProtect = client_proxy:bind(
        "uintptr_t (__thiscall*)(uintptr_t, void*, uintptr_t, uintptr_t, uintptr_t*)", 

        client_proxy:call(
            "uintptr_t (__thiscall*)(void*, uintptr_t, const char*)",
            ffi.cast("void***", ffi.cast("char*", client.find_signature("client.dll", "\x50\xFF\x15\xCC\xCC\xCC\xCC\x85\xC0\x0F\x84\xCC\xCC\xCC\xCC\x6A\x00")) + 3)[0][0],

            client_proxy:call(
                "uintptr_t (__thiscall*)(void*, const char*)",
                ffi.cast("void***", ffi.cast("char*", client.find_signature("client.dll", "\xC6\x06\x00\xFF\x15\xCC\xCC\xCC\xCC\x50")) + 5)[0][0],
                "kernel32.dll"
            ), --> Returns Kernel32.dll base address <
            
            "VirtualProtect"
        ) --> Returns VirtualProtect Memoryapi address <
    );

    VirtualProtect = function(self, lpAddress, dwSize, flNewProtect, lpflOldProtect)
        return self.__VirtualProtect(ffi.cast("void*", lpAddress), dwSize, flNewProtect, lpflOldProtect)
    end;
};

local hook = (function()
    local vmt_hook = {hooks = {}};

    function vmt_hook.new(vt)
        local virtual_table, original_table = ffi.cast("intptr_t**", vt)[0], {};
        local lpflOldProtect = ffi.new("unsigned long[1]");
        local rtn = {}; 

        rtn.hook = function(cast, func, method)
            original_table[method] = virtual_table[method];

            Memoryapi:VirtualProtect(virtual_table + method, 4, 0x4, lpflOldProtect)
            virtual_table[method] = ffi.cast("intptr_t", ffi.cast(cast, func))

            Memoryapi:VirtualProtect(virtual_table + method, 4, lpflOldProtect[0], lpflOldProtect)
            return ffi.cast(cast, original_table[method])
        end

        rtn.unhook_method = function(method)
            Memoryapi:VirtualProtect(virtual_table + method, 4, 0x4, lpflOldProtect)
            virtual_table[method] = original_table[method];

            Memoryapi:VirtualProtect(virtual_table + method, 4, lpflOldProtect[0], lpflOldProtect)
            original_table[method] = nil;
        end

        rtn.unhook = function()
            for method, _ in pairs(original_table) do
                rtn.unhook_method(method)
            end
        end

        table.insert(vmt_hook.hooks, rtn.unhook)
        return rtn
    end


    return vmt_hook
end)();

local IMaterialSystem = {
    __find_material = ffi.cast("void* (__thiscall*)(void*, const char*, const char*, bool, const char*)", interfaces.material_system[0][84]);

    find_material = function(self, name)
        return self.__find_material(interfaces.material_system, name, "", true, "")
    end;
};

local IStudioRender = {
    __hook = hook.new(interfaces.studio_render);
    __set_color_modulation = ffi.cast("void (__thiscall*)(void*, float [3])", interfaces.studio_render[0][27]);
    __set_alpha_modulation = ffi.cast("void (__thiscall*)(void*, float)", interfaces.studio_render[0][28]);
    __draw_model = nil;
    __forced_material_override = ffi.cast("void (__thiscall*)(void*, void*, const int32_t, const int32_t)", interfaces.studio_render[0][33]);

    set_color_modulation = function(self, r, g, b)
        self.__set_color_modulation(interfaces.studio_render, ffi.new("float [3]", r, g, b))
    end;

    set_alpha_modulation = function(self, alpha)
        self.__set_alpha_modulation(interfaces.studio_render, alpha)
    end;

    draw_model = function(self, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
        self.__draw_model(interfaces.studio_render, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
    end;

    forced_material_override = function(self, mat)
        self.__forced_material_override(interfaces.studio_render, mat, 0, -1)
    end;
};


local IClientRenderable = {
    __GetClientUnknown = nil;
    __GetClientNetworkable = nil;
    __GetEntIndex = nil;

    GetEntIndex = function(self, renderable)
        return self.__GetEntIndex(self.__GetClientNetworkable(self.__GetClientUnknown(renderable)))
    end;
};

local scoped_transparency = 1;
local local_player_index = -1;
local local_weapons = {};
local ENT_ENTRY_MASK = bit.lshift(1, 12) - 1; --> entity_handle & ENT_ENTRY_MASK = entity_index <

client.set_event_callback("setup_command", function()
    ui.set(menu_references.local_player, false)
    ui.set(menu_references.local_player_transparency, "");
    ui.set(menu_references.fake, false)
    ui.set(menu_references.hands, false)
    ui.set(menu_references.weapon_viewmodel, true)
    ui.set(menu_references.weapon_viewmodel_color, 255, 255, 255, math.floor(255*scoped_transparency))
    ui.set(menu_references.weapon_viewmodel_type, "Original")

    local_player_index = entity.get_local_player() or -1;

    if local_player_index == -1 then return end

    scoped_transparency = (entity.get_prop(local_player_index, "m_bIsScoped") == 1) and config.scoped_transparency or 1;

    local_weapons = {};
    for _, entindex in pairs(entity.get_all("CBaseWeaponWorldModel")) do
        local_weapons[entindex] = bit.band(entity.get_prop(entindex, "moveparent"), ENT_ENTRY_MASK) == local_player_index;
    end
end)

local function HideUiElements(visible)
    ui.set_visible(menu_references.local_player, visible)
    ui.set_visible(menu_references.local_player_transparency, visible)
    ui.set_visible(menu_references.fake, visible)
    ui.set_visible(menu_references.hands, visible)
    ui.set_visible(menu_references.weapon_viewmodel, visible)
    ui.set_visible(menu_references.weapon_viewmodel_color, visible)
    ui.set_visible(menu_references.weapon_viewmodel_type, visible)
end

client.set_event_callback("shutdown", function()
    IStudioRender.__hook.unhook()
    HideUiElements(true)
end)

HideUiElements(false)

local function SetModelOverrideSettings(cfg, alpha_mod, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
    local get, floor = ui.get, math.floor;

    local main_option = MaterialIndexing.base[get(cfg.main_option)];
    if main_option ~= 1 then
        if main_option < 3 then
            IStudioRender:set_color_modulation(1, 1, 1)
            IStudioRender:set_alpha_modulation(alpha_mod * 1)
            IStudioRender:draw_model(results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
        end

        if main_option > 1 then
            local mat = cfg.main_material[main_option - 2];
            local r, g, b, a = get(cfg.main_color);

            mat:set_shader_param("$pearlescentinput", get(cfg.main_pearlescense))
            mat:set_shader_param("$rimlightinput", get(cfg.main_rimglow))
            mat:set_shader_param("$phonginput", get(cfg.main_reflectivity) / 2)

            mat:set_material_var_flag(28, cfg.wireframe[1])

            mat:color_modulate(r, g, b)
            mat:alpha_modulate(floor(a*alpha_mod))

            IStudioRender:forced_material_override(cfg.pmain_material[main_option - 2])
            IStudioRender:draw_model(results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
        end
    end
    
    local animated_option = MaterialIndexing.animated[get(cfg.animated_option)];
    if animated_option > 0 then
        local mat = cfg.animated_material[animated_option - 1]
        local r, g, b, a = get(cfg.animated_color);

        mat:set_material_var_flag(28, cfg.wireframe[2])

        mat:color_modulate(r, g, b)
        mat:alpha_modulate(floor(a*alpha_mod))

        IStudioRender:forced_material_override(cfg.panimated_material[animated_option - 1])
        IStudioRender:draw_model(results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
    end

    local glow_fill = get(cfg.glow_fill);
    if glow_fill > 0 then
        local mat = cfg.glow_material;
        local r, g, b, a = get(cfg.glow_color);

        mat:set_shader_param("$envmaptintr", r)
        mat:set_shader_param("$envmaptintg", g)
        mat:set_shader_param("$envmaptintb", b)
        mat:set_shader_param("$envmapfresnelfill", 100 - glow_fill)
        mat:set_shader_param("$envmapfresnelbrightness", a / 2.55)

        mat:set_material_var_flag(28, cfg.wireframe[3])

        mat:color_modulate(255, 255, 255)
        mat:alpha_modulate(floor(a*alpha_mod))

        IStudioRender:forced_material_override(cfg.pglow_material)
        IStudioRender:draw_model(results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
    end
end

client.delay_call(1, function()
    IStudioRender.__draw_model = IStudioRender.__hook.hook("void (__thiscall*)(void*, void*, const DrawModelInfo_t&, void*, float*, float*, void*, const int32_t)", function(this, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
        local mdl = ffi.string(info.studio_hdr.name)
        local entindex = -1;

        pcall(function()
            if info.renderable ~= ffi.NULL then
                if not IClientRenderable.__GetClientUnknown then
                    local IClientUnknown = ffi.cast("void*** (__thiscall*)(void*)", info.renderable[0][0])(info.renderable);
                    local IClientNetworkable = ffi.cast("void*** (__thiscall*)(void*)", IClientUnknown[0][4])(IClientUnknown);

                    IClientRenderable.__GetClientUnknown = ffi.cast("void*** (__thiscall*)(void*)", info.renderable[0][0]);
                    IClientRenderable.__GetClientNetworkable = ffi.cast("void*** (__thiscall*)(void*)", IClientUnknown[0][4])
                    IClientRenderable.__GetEntIndex = ffi.cast("int (__thiscall*)(void*)", IClientNetworkable[0][10])

                    return
                end

                entindex = IClientRenderable:GetEntIndex(info.renderable);
            end
        end)

        if mdl:find("weapons.v_") then
            if not mdl:find("weapons.v_models") then 
                pcall(SetModelOverrideSettings, config.weapon, 1, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
                return

            elseif mdl:find("/arms/glove") then
                pcall(SetModelOverrideSettings, config.arms, 1, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
                return

            else
                pcall(SetModelOverrideSettings, config.sleeves, 1, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
                return

            end
        elseif mdl:find("facemask") then
            pcall(SetModelOverrideSettings, config.facemask, (scoped_transparency > 0) and (scoped_transparency * 0.3 + 0.7) or 0, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
            return

        end
        
        if entindex == -1 then
            IStudioRender:draw_model(results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
            return
        end

        if local_weapons[entindex] then
            pcall(SetModelOverrideSettings, config.weapon, scoped_transparency, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
            return
        
        elseif entindex == local_player_index then
            pcall(SetModelOverrideSettings, config.player, scoped_transparency, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
            return

        end
        
        IStudioRender:draw_model(results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
    end, 29)
end)

reload_materials = function()
    for config_group, file_extention in pairs({
        ["weapon"] = "wpn";
        ["arms"] = "arm";
        ["sleeves"] = "slv";
        ["facemask"] = "msk";
        ["player"] = "arm";
    }) do
        local tbl = config[config_group];

        tbl.main_material = {
            [0] = materialsystem.find_material("custom_chams/" .. file_extention .. "_modulate.vmt", true);
            [1] = materialsystem.find_material("custom_chams/" .. file_extention .. "_vertexlit.vmt", true);
            [2] = materialsystem.find_material("custom_chams/" .. file_extention .. "_unlitgeneric.vmt", true);
        };

        tbl.pmain_material = {
            [0] = IMaterialSystem:find_material("custom_chams/" .. file_extention .. "_modulate.vmt");
            [1] = IMaterialSystem:find_material("custom_chams/" .. file_extention .. "_vertexlit.vmt");
            [2] = IMaterialSystem:find_material("custom_chams/" .. file_extention .. "_unlitgeneric.vmt");
        };

        for i = 0, 4 do
            tbl.animated_material[i] = materialsystem.find_material("custom_chams/" .. file_extention .. "_animated_" .. tostring(i) .. ".vmt", true);
            tbl.panimated_material[i] = IMaterialSystem:find_material("custom_chams/" .. file_extention .. "_animated_" .. tostring(i) .. ".vmt");
        end

        tbl.glow_material =  materialsystem.find_material("custom_chams/" .. file_extention .. "_glow.vmt", true);
        tbl.pglow_material = IMaterialSystem:find_material("custom_chams/" .. file_extention .. "_glow.vmt");
    end
end;

ui.set_callback(config.selection, function()
    local value = ui.get(config.selection);

    config.weapon:set_visible(value == "Weapon")
    config.arms:set_visible(value == "Arms")
    config.sleeves:set_visible(value == "Sleeves")
    config.facemask:set_visible(value == "Facemask")
    config.player:set_visible(value == "Player")
end)

ui.set_callback(config.__scoped_transparency, function()
    config.scoped_transparency = (100 - ui.get(config.__scoped_transparency)) / 100;
end)

config.scoped_transparency = (100 - ui.get(config.__scoped_transparency))  / 100;

ui.set(config.selection, "Weapon")

reload_materials()
