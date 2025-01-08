--[[
    Created by: Good.Evening#3081
    Source: https://raw.githubusercontent.com/GoodEveningFellOff/gamesense-chams/main/chams.lua
]]

local ffi = require("ffi");
local bit = require("bit");
ffi.cdef([[
    typedef struct {
        char __pad[12];
        char name[64];
    } studiohdr_t;

    typedef struct {
        studiohdr_t* m_pStudioHdr;
        char __pad[20];
        void* m_pClientEntity;
    } DrawModelInfo_t;
]])

local EBaseMaterials = { 
    ["Off"]       = 0;
    ["Invisible"] = 1;
    ["Material"]  = 2;
    ["Color"]     = 3;
    ["Flat"]      = 4; 
};

local EAnimatedMaterials = { 
    ["Disabled"]          = 0;
    ["Tazer Beam"]        = 1; 
    ["Hemisphere Height"] = 2; 
    ["Zone Warning"]      = 3; 
    ["Bendybeam"]         = 4; 
    ["Dreamhack"]         = 5;
};

local EWeaponTypes = {
    ["CFlashbang"] = 1;
    ["CHEGrenade"] = 1;
    ["CDecoyGrenade"] = 1;
    ["CSmokeGrenade"] = 1;
    ["CMolotovGrenade"] = 1;
    ["CIncendiaryGrenade"] = 1;
    ["CWeaponSG556"] = 2;
    ["CWeaponAug"] = 2;
};

local function WritePointerToAddress(...) end
do
    local pTrampoline = client.find_signature("client.dll", "\x51\xC3")

    -- Address to the virtual protect function.
    local fnVirtualProtect = ffi.cast("uintptr_t (__thiscall*)(void*, uintptr_t, const char*)", pTrampoline)(
        ffi.cast("void***", ffi.cast("char*", client.find_signature("client.dll", "\x50\xFF\x15\xCC\xCC\xCC\xCC\x85\xC0\x0F\x84\xCC\xCC\xCC\xCC\x6A\x00")) + 3)[0][0],
        ffi.cast("uintptr_t(__thiscall*)(void*, const char*)", pTrampoline)(
            ffi.cast("void***", ffi.cast("uintptr_t", client.find_signature("client.dll", "\xC6\x06\x00\xFF\x15\xCC\xCC\xCC\xCC\x50")) + 5)[0][0], 
            "kernel32.dll"
        ), --> Returns Kernel32.dll base address <
        "VirtualProtect"
    ); --> Returns VirtualProtect Memoryapi address <

    -- We will call it with our trampoline so we prepare it by casting it to the virtual protect function type.
    pTrampoline = ffi.cast("uintptr_t (__thiscall*)(uintptr_t, void*, uintptr_t, uintptr_t, uintptr_t*)", pTrampoline);

    function WritePointerToAddress(lpAddress, lpValue)
        local lpflOldProtect = ffi.new("unsigned long[1]");
        pTrampoline(fnVirtualProtect, lpAddress, 4, 0x4, lpflOldProtect);
        lpAddress[0] = ffi.cast("void*", lpValue);
        pTrampoline(fnVirtualProtect, lpAddress, 4, 0x4, lpflOldProtect);
    end
end

-- Engine client interface, used to fix glow on hdr disabled maps.
local IEngineClient = {
    m_pInterface = ffi.cast(ffi.typeof("void***"), client.create_interface("engine.dll", "VEngineClient014"));
};
do
    fnIsHdrEnabled = ffi.cast("bool(__thiscall*)(void*)", IEngineClient.m_pInterface[0][109]);
    function IEngineClient:IsHdrEnabled()
        return fnIsHdrEnabled(self.m_pInterface);
    end
end

-- Studio render interface, used for the draw model hook along with modulation and rendering of materials.
local IStudioRender = {
    m_pInterface = ffi.cast("void***", client.create_interface("studiorender.dll", "VStudioRender026"));
    m_aDrawModelContext = {};
};
do
    function IStudioRender:StartHook(fnDetour)
        local T = "void (__fastcall*)(void*, void*, void*, const DrawModelInfo_t&, void*, float*, float*, float[3], const int32_t)";
        
        self.m_fnDrawModel = ffi.cast(T, self.m_pInterface[0][29]);
        WritePointerToAddress(self.m_pInterface[0] + 29, ffi.cast(T, fnDetour));
    end

    function IStudioRender:StopHook()
        if(self.m_fnDrawModel)then
            WritePointerToAddress(self.m_pInterface[0] + 29, self.m_fnDrawModel);
        end
    end

    local fnSetColorModulation = ffi.cast("void(__thiscall*)(void*, float[3])", IStudioRender.m_pInterface[0][27]);
    function IStudioRender:SetColorModulation(flR, flG, flB)
        fnSetColorModulation(self.m_pInterface, ffi.new("float[3]", flR, flG, flB));
    end

    local fnSetAlphaModulation = ffi.cast("void(__thiscall*)(void*, float)", IStudioRender.m_pInterface[0][28]);
    function IStudioRender:SetAlphaModulation(flAlpha)
        fnSetAlphaModulation(self.m_pInterface, flAlpha);
    end

    function IStudioRender:DrawModel()
        self.m_fnDrawModel(self.m_pInterface, unpack(self.m_aDrawModelContext));
    end

    local fnForcedMaterialOverride = ffi.cast("void(__thiscall*)(void*, void*, const int32_t, const int32_t)", IStudioRender.m_pInterface[0][33]);
    function IStudioRender:ForcedMaterialOverride(mat)
        if(not mat)then
            fnForcedMaterialOverride(self.m_pInterface, ffi.cast("void*", ffi.cast("uintptr_t", 0)), 0, -1);
            return;
        end

        fnForcedMaterialOverride(self.m_pInterface, ffi.cast("void*", mat), 0, -1);
        self:DrawModel();
    end
end


local IClientRenderable  = {
    New = function(self, this)
        local class = { [0] = this; };
        setmetatable(class, self);
        self.__index = self;
        return class;
    end;
};
do -- IClientRenderable // START

    -- Goes through IClientUnknown to get the entity handle and uses that to get the base entity. 
    local ENT_ENTRY_MASK = bit.lshift(1, 12) - 1;
    local fnGetIClientUnknown = nil;
    local fnGetRefEHandle = nil;
    function IClientRenderable:GetEntityIndex()
        if(self[0] == nil)then
            return -1;
        end

        if(not fnGetIClientUnknown)then
            fnGetIClientUnknown = ffi.cast("void*(__thiscall*)(void*)", ffi.cast("void***", self[0])[0][0]);
        end

        local pClientUnknown = fnGetIClientUnknown(self[0]);
        if(not pClientUnknown)then
            return -1;
        end

        if(not fnGetRefEHandle)then
            fnGetRefEHandle = ffi.cast("uint32_t*(__thiscall*)(void*)", ffi.cast("void***", pClientUnknown)[0][2]);
        end

        local iIndex = bit.band(fnGetRefEHandle(pClientUnknown)[0], ENT_ENTRY_MASK);
        return iIndex;--(iIndex > entity_list.get_highest_entity_index()) and -1 or iIndex;
    end

    local fnGetShadowParent = nil;
    function IClientRenderable:GetOwnerIndex()
        if(self[0] == nil)then
            return -1;
        end

        if(not fnGetShadowParent)then
            fnGetShadowParent = ffi.cast("void*(__thiscall*)(void*)", ffi.cast("void***", self[0])[0][25]);
        end

        return (IClientRenderable:New(fnGetShadowParent(self[0]))):GetEntityIndex();
    end
end -- IClientRenderable // END

local IMaterial = {
    New = function(self, this)
        local class = { [0] = this; };
        setmetatable(class, self);
        self.__index = self;
        return class;
    end;
};
do -- IMaterial // START
    local fnIncrementReferenceCount = nil;
    function IMaterial:IncrementReferenceCount()
        if(self[0] == nil)then
            return;
        end

        if(not fnIncrementReferenceCount)then
            fnIncrementReferenceCount = ffi.cast("void*(__thiscall*)(void*)", ffi.cast("void***", self[0])[0][12]);
        end

        fnIncrementReferenceCount(self[0]);
    end

    local fnDecrementReferenceCount = nil;
    function IMaterial:DecrementReferenceCount()
        if(self[0] == nil)then
            return;
        end

        if(not fnDecrementReferenceCount)then
            fnDecrementReferenceCount = ffi.cast("void*(__thiscall*)(void*)", ffi.cast("void***", self[0])[0][13]);
        end

        fnDecrementReferenceCount(self[0]);
    end
end -- IMaterial // END

local IMaterialSystem = {
    m_pInterface = ffi.cast("void***", client.create_interface("materialsystem.dll", "VMaterialSystem080"));
};
do -- IMaterialsSystem // START
    local fnFindMaterial = ffi.cast("void* (__thiscall*)(void*, const char*, const char*, bool, const char*)", IMaterialSystem.m_pInterface[0][84]);
    function IMaterialSystem:FindMaterial(sName)
        return IMaterial:New(fnFindMaterial(self.m_pInterface, sName, "", true, ""));
    end
end -- IMaterialsSystem // END

local sTab = "LUA";
local sContainer = "A";

local UI = {
    Visuals = {
        Enable = ui.reference("VISUALS", "Colored models", "Local player");
        Transparency = ui.reference("VISUALS", "Colored models", "Local player transparency");
        Fake = ui.reference("VISUALS", "Colored models", "Local player fake");
        Hands = ui.reference("VISUALS", "Colored models", "Hands");
        Weapon = ui.reference("VISUALS", "Colored models", "Weapon viewmodel");
    };

    m_guiGroup = ui.new_combobox(sTab, sContainer, "Group\nCHAMS", {"Hide", "Player", "Desync", "Arms", "Sleeves", "Weapon", "Attachments", "Mask"});
    m_guiDesync = ui.new_checkbox(sTab, sContainer, "Local Fake\nCHAMS");
    m_guiTransparencyOptions = ui.new_multiselect(sTab, sContainer, "Transparency Options\nCHAMS", { "Scoped", "Grenades", "Interpolate" });
    m_guiSpacer = ui.new_label(sTab, sContainer, " \nCHAMS_SPACER");

    m_groupPlayer      = {};
    m_groupDesync      = {};
    m_groupArms        = {};
    m_groupSleeves     = {};
    m_groupWeapon      = {};
    m_groupAttachments = {};
    m_groupMask        = {};

    Organize = function(self, bUnload)
        local sActiveGroup = ui.get(self.m_guiGroup);

        self.m_groupPlayer:SetVisible(     sActiveGroup == "Player");
        self.m_groupDesync:SetVisible(     sActiveGroup == "Desync");
        self.m_groupArms:SetVisible(       sActiveGroup == "Arms");
        self.m_groupSleeves:SetVisible(    sActiveGroup == "Sleeves");
        self.m_groupWeapon:SetVisible(     sActiveGroup == "Weapon");
        self.m_groupAttachments:SetVisible(sActiveGroup == "Attachments");
        self.m_groupMask:SetVisible(       sActiveGroup == "Mask");

        ui.set_visible(self.Visuals.Enable, bUnload);
        ui.set_visible(self.Visuals.Enable, Transparency);
        ui.set_visible(self.Visuals.Enable, Fake);
        ui.set_visible(self.Visuals.Enable, Hands);
        ui.set_visible(self.Visuals.Enable, Weapon);
    end;

    SetElementOverrides = function(self)
        ui.set(self.Visuals.Enable, false);
        ui.set(self.Visuals.Transparency, {});
        ui.set(self.Visuals.Fake, ui.get(self.m_guiDesync));
        ui.set(self.Visuals.Hands, false);
        ui.set(self.Visuals.Weapon, false);
    end;
};

local function GenerateChamGroup(sConfigName, sMaterialPrefix, iGroup, bIsThirdPerson)
    local sTab = "LUA";     -- "VISUALS"
    local sContainer = "A"; -- "Colored models"

    local stConfig = {};
    local aBaseMaterials = {};
    local aAnimatedMaterials = {};
    for k, v in pairs(EBaseMaterials) do
        aBaseMaterials[v + 1] = k;
    end

    for k, v in pairs(EAnimatedMaterials) do
        aAnimatedMaterials[v + 1] = k;
    end
    
    stConfig.m_guiBaseMaterial = ui.new_combobox(sTab, sContainer, "Base Material\n" ..  sConfigName, aBaseMaterials);
	stConfig.m_guiBaseColor = ui.new_color_picker(sTab, sContainer, "Base Color\n" .. sConfigName, 255, 255, 255, 255);
    stConfig.m_guiPearlescent = ui.new_slider(sTab, sContainer, "Pearlescent\n" .. sConfigName, -100, 100, 0, true, "%", 1, {[0] = "Off"});
    stConfig.m_guiRimlight = ui.new_slider(sTab, sContainer, "Rimlight\n" .. sConfigName, 0, 100, 0, true, "%", 1, {[0] = "Off"});
    stConfig.m_guiReflectivity = ui.new_slider(sTab, sContainer, "Reflectivity\n" .. sConfigName, 0, 100, 0, true, "%", 1, {[0] = "Off"});
    stConfig.m_guiReflectivityColor = ui.new_color_picker(sTab, sContainer, "Reflectivity Color\n" .. sConfigName, 255, 255, 255, 255);
	stConfig.m_guiSpacer1 = ui.new_label(sTab, sContainer, " \n1_" .. sConfigName);

    stConfig.m_guiAnimatedMaterial = ui.new_combobox(sTab, sContainer, "Animated Material\n" .. sConfigName, aAnimatedMaterials);
	stConfig.m_guiAnimatedColor = ui.new_color_picker(sTab, sContainer, "Anim Color\n" .. sConfigName, 255, 255, 255, 255);
	stConfig.m_guiScale = ui.new_slider(sTab, sContainer, "Texture Scale\n" .. sConfigName, 0, 1000, 100, true, "%", 1);
	stConfig.m_guiAngle = ui.new_slider(sTab, sContainer, "Texture Angle\n" .. sConfigName, -180, 180, 0, true, "°", 1);
	stConfig.m_guiScroll = ui.new_slider(sTab, sContainer, "Anim Angle\n" .. sConfigName, -180, 180, 0, true, "°", 1);
	stConfig.m_guiSpeed = ui.new_slider(sTab, sContainer, "Anim Speed\n" .. sConfigName, 0, 500, 100, true, "%", 1);
	stConfig.m_guiSpacer2 = ui.new_label(sTab, sContainer, " \n2_" .. sConfigName);
	
	stConfig.m_guiFill = ui.new_slider(sTab, sContainer, "Glow Fill\n" .. sConfigName, 0, 100, 0, true, "%", 1, {[0] = "Off"});
    stConfig.m_guiGlow = ui.new_color_picker(sTab, sContainer, "Glow Color\n" .. sConfigName, 255, 255, 255, 255);
    stConfig.m_guiWireframe = ui.new_multiselect(sTab, sContainer, "Wireframe\n" .. sConfigName, {"Base", "Animated", "Glow"});
    stConfig.m_guiSpacer3 = ui.new_label(sTab, sContainer, " \n3_" .. sConfigName);

    stConfig.m_guiTransparencyPercent = ui.new_slider(sTab, sContainer, "Transparency Percent\n" .. sConfigName, 0, 100, 0, true, "%", 1);
    stConfig.m_guiTransparencyOriginal = ui.new_checkbox(sTab, sContainer, "Use Original\n" .. sConfigName);
    
    stConfig.m_flAlphaOverride = 1;

    stConfig.m_bIsThirdPerson = bIsThirdPerson;
	stConfig.m_bIsVisible = true;
    stConfig.m_bIsDisabled = false;
    stConfig.m_sGroup = tostring(iGroup);
    stConfig.m_aMainMaterials = {};
    stConfig.m_aRawMainMaterials = {};
    stConfig.m_aAnimatedMaterials = {};
    stConfig.m_aRawAnimatedMaterials = {};

    function stConfig:SetVisible(bVisible)
        if(self.m_bIsVisible == bVisible)then
            return;
        end

        self.m_bIsVisible = bVisible;
        for k, v in pairs(self) do
            if(tostring(k):find("m_gui"))then
                ui.set_visible(v, bVisible);
            end
        end
	end;

    function stConfig:Unload()
        for _, v in pairs(self.m_aRawMainMaterials)do
            v:DecrementReferenceCount();
        end

        for _, v in pairs(self.m_aRawAnimatedMaterials)do
            v:DecrementReferenceCount();
        end

        if(self.m_pGlowMaterial)then
            self.m_pGlowMaterial:DecrementReferenceCount();
        end
    end;

    function stConfig:Load()
        self.m_aMainMaterials = {
            [0] = materialsystem.find_material("custom_chams/" .. self.m_sGroup .. "_modulate.vmt", true);
            [1] = materialsystem.find_material("custom_chams/" .. self.m_sGroup .. "_vertexlit.vmt", true);
            [2] = materialsystem.find_material("custom_chams/" .. self.m_sGroup .. "_unlitgeneric.vmt", true);
        };
    
        self.m_aRawMainMaterials = {
            [0] = IMaterialSystem:FindMaterial("custom_chams/" .. self.m_sGroup .. "_modulate.vmt");
            [1] = IMaterialSystem:FindMaterial("custom_chams/" .. self.m_sGroup .. "_vertexlit.vmt");
            [2] = IMaterialSystem:FindMaterial("custom_chams/" .. self.m_sGroup .. "_unlitgeneric.vmt");
        };

        for k, v in pairs(self.m_aRawMainMaterials) do
            v:IncrementReferenceCount();
        end
    
        for i = 0, 4 do
            self.m_aAnimatedMaterials[i] = materialsystem.find_material("custom_chams/" .. self.m_sGroup .. "_animated_" .. tostring(i) .. ".vmt", true);
            self.m_aRawAnimatedMaterials[i] = IMaterialSystem:FindMaterial("custom_chams/" .. self.m_sGroup .. "_animated_" .. tostring(i) .. ".vmt");
            self.m_aRawAnimatedMaterials[i]:IncrementReferenceCount();
        end
    
        self.m_materialGlow =  materialsystem.find_material("custom_chams/" .. self.m_sGroup .. "_glow.vmt", true);
        self.m_pGlowMaterial = IMaterialSystem:FindMaterial("custom_chams/" .. self.m_sGroup .. "_glow.vmt");
        self.m_pGlowMaterial:IncrementReferenceCount();
    end

    function stConfig:Reload()
        self:Unload();
        self:Load();
    end;
    
    stConfig:Reload();

    return stConfig;
end

UI.m_groupPlayer      = GenerateChamGroup("Player",      "plr",       1, true );
UI.m_groupDesync      = GenerateChamGroup("Desync",      "dsnc",      2, true );
UI.m_groupArms        = GenerateChamGroup("Arms",        "arms",      1, false);
UI.m_groupSleeves     = GenerateChamGroup("Sleeves",     "slvs",      2, false);
UI.m_groupWeapon      = GenerateChamGroup("Weapon",      "wpn",       3, false);
UI.m_groupAttachments = GenerateChamGroup("Attachments", "attchmnts", 3, true );
UI.m_groupMask        = GenerateChamGroup("Mask",        "msk",       4, true );

GenerateChamGroup = nil;

-->> Create Main Cham Override Table <<
local g_MaterialOverride = {
    m_iGlowMultiplier = 1;
    m_bInGame = false;
    m_flAlphaPercent = 1;
    m_bIsThirdPerson = false;

    UpdateGlowMultiplier = function(self)
        local bIsInGame = globals.mapname() ~= nil;
        if(self.m_bInGame == bIsInGame)then
            return;
        end

        self.m_bInGame = bIsInGame;
        if(not bIsInGame)then
            return;
        end

        self.m_iGlowMultiplier = IEngineClient:IsHdrEnabled() and 1 or 15;
    end;

    UpdateAlphaPercent = function(self, bShouldBeTransparent)
        local flGoal = bShouldBeTransparent and 1 or 0;
        local bInterpolate = false;
        for _, v in pairs(ui.get(UI.m_guiTransparencyOptions))do
            if(v == "Interpolate") then
                bInterpolate = true;
                break;
            end
        end

        if(not bInterpolate)then
            self.m_flAlphaPercent = flGoal;
            return;
        end

        local flDelta = flGoal - self.m_flAlphaPercent;
        if(math.abs(flDelta) < 0.05)then
            self.m_flAlphaPercent = flGoal;
            return;
        end

        self.m_flAlphaPercent = self.m_flAlphaPercent + flDelta * globals.frametime() * 20;
        if(self.m_flAlphaPercent < 0)then
            self.m_flAlphaPercent = 0;

        elseif(self.m_flAlphaPercent > 1)then
            self.m_flAlphaPercent = 1;
        end
    end;

    UpdateMaterialSettings = function(self, stGroup)
        local bStatus, sError = pcall(function()
            local iBaseMaterial, iAnimMaterial, bGlow = EBaseMaterials[ui.get(stGroup.m_guiBaseMaterial)] - 1, EAnimatedMaterials[ui.get(stGroup.m_guiAnimatedMaterial)], ui.get(stGroup.m_guiFill) > 0;
            local guiWireframe = stGroup.m_guiWireframe;

            local aWireframe = { false, false, false };
            for _, v in pairs(ui.get(stGroup.m_guiWireframe)) do
                if(v == "Base")then
                    aWireframe[1] = true;
                elseif(v ==  "Animated")then
                    aWireframe[2] = true;
                elseif(v == "Glow")then
                    aWireframe[3] = true;
                end
            end

            stGroup.m_flAlphaOverride = 1 + (1 - ui.get(stGroup.m_guiTransparencyPercent) / 100 - 1) * self.m_flAlphaPercent;
            stGroup.m_bIsDisabled = (iBaseMaterial == -1 and iAnimMaterial == 0 and not bGlow) or (self.m_flAlphaPercent > 0.5 and ui.get(stGroup.m_guiTransparencyOriginal));

            if(iBaseMaterial >= 1)then
                local mat = stGroup.m_aMainMaterials[iBaseMaterial - 1];
                local iR, iG, iB, iA = ui.get(stGroup.m_guiBaseColor);

                if(iBaseMaterial ~= 1)then
                    local flRRef, flGRef, flBRef, flARef = ui.get(stGroup.m_guiReflectivityColor);
                    flARef = flARef / 2.55;

                    mat:set_shader_param("$pearlescentinput", ui.get(stGroup.m_guiPearlescent)); 
                    mat:set_shader_param("$rimlightinput",   (ui.get(stGroup.m_guiRimlight) * 0.5)^2);
                    mat:set_shader_param("$phongr", flRRef * flARef);
                    mat:set_shader_param("$phongg", flGRef * flARef); 
                    mat:set_shader_param("$phongb", flBRef * flARef);
                    mat:set_shader_param("$phonga", flARef * (ui.get(stGroup.m_guiReflectivity) * 0.01))
                end
                
                mat:color_modulate(iR, iG, iB);
                mat:alpha_modulate(iA * stGroup.m_flAlphaOverride);
                mat:set_material_var_flag(28, aWireframe[1]);
            end

            if(iAnimMaterial >= 1)then
                local mat = stGroup.m_aAnimatedMaterials[iAnimMaterial - 1];
                local iR, iG, iB, iA = ui.get(stGroup.m_guiAnimatedColor);

                mat:color_modulate(iR, iG, iB);
                mat:alpha_modulate(iA * stGroup.m_flAlphaOverride);
                mat:set_shader_param("$scaleinput", ui.get(stGroup.m_guiScale));
                mat:set_shader_param("$angle", ui.get(stGroup.m_guiAngle));
                mat:set_shader_param("$texturescrollangle", ui.get(stGroup.m_guiScroll));
                mat:set_shader_param("$texturescrollinput", ui.get(stGroup.m_guiSpeed));
                mat:set_material_var_flag(28, aWireframe[2]);
            end
        
            if(bGlow)then
                local mat = stGroup.m_materialGlow;
                local iR, iG, iB, iA = ui.get(stGroup.m_guiGlow);
        
                mat:set_shader_param("$envmaptintr", iR);
                mat:set_shader_param("$envmaptintg", iG);
                mat:set_shader_param("$envmaptintb", iB);
                mat:set_shader_param("$envmapfresnelbrightness", (iA / 2.55) * self.m_iGlowMultiplier * stGroup.m_flAlphaOverride);
                mat:set_shader_param("$envmapfresnelfill", 100 - ui.get(stGroup.m_guiFill));
                mat:set_material_var_flag(28, aWireframe[3]);
            end
        end);

        if(not bStatus)then
            stGroup:Reload();
        end
    end;

    OnFrameEnd = function(self)
        if(self.m_bIsThirdPerson)then
            for _, stGroup in pairs({UI.m_groupPlayer, UI.m_groupDesync, UI.m_groupAttachments, UI.m_groupMask}) do
                self:UpdateMaterialSettings(stGroup);
            end
        else
            for _, stGroup in pairs({UI.m_groupArms, UI.m_groupSleeves, UI.m_groupWeapon}) do
                self:UpdateMaterialSettings(stGroup);
            end
        end
    end;

    Set = function(self, bDisable, stGroup)
        if(stGroup.m_bIsThirdPerson ~= self.m_bIsThirdPerson)then
            self.m_bIsThirdPerson = stGroup.m_bIsThirdPerson;
            self:OnFrameEnd();
        end

        if(bDisable or stGroup.m_bIsDisabled)then
            IStudioRender:SetAlphaModulation(stGroup.m_flAlphaOverride);
            IStudioRender:DrawModel();
            return;
        end

        local iBaseMaterial = EBaseMaterials[ui.get(stGroup.m_guiBaseMaterial)] - 1;
        if(iBaseMaterial < 1)then
            if(iBaseMaterial == -1)then
                IStudioRender:SetAlphaModulation(stGroup.m_flAlphaOverride);
                IStudioRender:DrawModel();
            end

        else

            
            if(iBaseMaterial == 1)then
                IStudioRender:SetAlphaModulation(({ui.get(stGroup.m_guiBaseColor)})[4] / 255 * stGroup.m_flAlphaOverride);
                IStudioRender:DrawModel();
            end

            IStudioRender:SetAlphaModulation(1);
            IStudioRender:ForcedMaterialOverride(stGroup.m_aRawMainMaterials[iBaseMaterial - 1][0]);
        end

        local iAnimMaterial = EAnimatedMaterials[ui.get(stGroup.m_guiAnimatedMaterial)];
        if(iAnimMaterial >= 1)then
            IStudioRender:SetAlphaModulation(1);
            IStudioRender:ForcedMaterialOverride(stGroup.m_aRawAnimatedMaterials[iAnimMaterial - 1][0]);
        end
    
        if(ui.get(stGroup.m_guiFill) > 0)then
            IStudioRender:SetAlphaModulation(1);
            IStudioRender:ForcedMaterialOverride(stGroup.m_pGlowMaterial[0]);
        end

        IStudioRender:SetAlphaModulation(1);
        IStudioRender:ForcedMaterialOverride();
    end;
};

-->> Local Vars <<
local g_iFrames = 32;
local g_aFrameInformation = {};
for i = 1, g_iFrames do
    g_aFrameInformation[#g_aFrameInformation + 1] = { 
        -10,    -- iLocalPlayerIndex
        -10,    -- iLocalWeaponIndex
        -10,    -- iLocalViewmodelIndex
        false  -- bDisableWeaponChams
    };
end

-->> Create Callbacks <<
client.set_event_callback("paint", function()
    local iFrame = (globals.framecount() + 1) % g_iFrames + 1;
    if(ui.is_menu_open())then
        UI:Organize(false);
    end

    local aFrame = { -10, -10, -10, -10, false };

    UI:SetElementOverrides();
    g_MaterialOverride:UpdateGlowMultiplier();
    if(not g_MaterialOverride.m_bInGame)then
        g_aFrameInformation[iFrame] = aFrame;
        return;
    end
    
    local iLocalPlayerIndex = entity.get_local_player();
    if(not iLocalPlayerIndex)then
        g_aFrameInformation[iFrame] = aFrame;
        return;
    end

    -- Make this shit work when spectating.
    if(not entity.is_alive(iLocalPlayerIndex))then
        g_aFrameInformation[iFrame] = aFrame;
        return;
    end
    aFrame[1] = iLocalPlayerIndex;

    local iLocalWeaponIndex = entity.get_player_weapon(iLocalPlayerIndex);
    if(iLocalWeaponIndex)then
        local iWeaponWorldModelIndex = entity.get_prop(iLocalWeaponIndex, "m_hWeaponWorldModel");
        aFrame[2] = iWeaponWorldModelIndex or -10;

        local bIsScoped = entity.get_prop(iLocalPlayerIndex, "m_bIsScoped") == 1;
        local eWeaponType = EWeaponTypes[entity.get_classname(iLocalWeaponIndex)] or 0;

        aFrame[4] = bIsScoped and eWeaponType == 2;
        
        local bShouldBeTransparent = false;
        local aTransparencyOptions = { false, false, false };
        for _, v in pairs(ui.get(UI.m_guiTransparencyOptions))do
            if((v == "Scoped" and bIsScoped) or (v == "Grenades" and eWeaponType == 1))then
                bShouldBeTransparent = true;
            end
        end

        -- Transparency whilst scoped / with grenades
        g_MaterialOverride:UpdateAlphaPercent(bShouldBeTransparent);
    end

    -- Get the viewmodel entity so we can draw all of our viewmodel chams.
    local aViewmodels = entity.get_all("CPredictedViewModel");
    if(aViewmodels)then
        for _, iEntityIndex in pairs(aViewmodels) do
            local iOwnerIndex = entity.get_prop(iEntityIndex, "m_hOwner");
            if(iOwnerIndex == iLocalPlayerIndex)then
                aFrame[3] = iEntityIndex;
                break;
            end
        end
    end

    g_aFrameInformation[iFrame] = aFrame;

    -- Update all of our materials for the next time DrawModel is called.
    g_MaterialOverride:OnFrameEnd();
end);

client.set_event_callback("shutdown", function()
    IStudioRender:StopHook();
    UI:Organize(true);


    for _, stGroup in pairs({UI.m_groupPlayer, UI.m_groupDesync, UI.m_groupAttachments, UI.m_groupMask, UI.m_groupArms, UI.m_groupSleeves, UI.m_groupWeapon}) do
        stGroup:Unload();
    end
end);

local function OnDrawModel(sModel, pClientRenderable, bIsFake)
    local iEntityIndex = pClientRenderable:GetEntityIndex();
    local iOwnerIndex = pClientRenderable:GetOwnerIndex();

    local iFrame = globals.framecount() % g_iFrames + 1;
    local aFrame = g_aFrameInformation[iFrame];

    if(iEntityIndex == aFrame[3])then
        g_MaterialOverride:Set(aFrame[4], UI.m_groupWeapon);
        return;

    elseif(iOwnerIndex == aFrame[3])then
        if(sModel:find("weapons/v_models/arms/glove"))then
            g_MaterialOverride:Set(false, UI.m_groupArms);
            
        else
            g_MaterialOverride:Set(false, UI.m_groupSleeves); 
        end

        return;
    
    elseif(iEntityIndex == aFrame[1])then
        -- Water does wierd shit, this is a hacky fix.
        if(not bIsFake)then
            g_MaterialOverride:Set(false, UI.m_groupPlayer);

        else
            IStudioRender:SetColorModulation(1, 1, 1);
            IStudioRender:ForcedMaterialOverride();
            g_MaterialOverride:Set(false, UI.m_groupDesync);
        end

        return;

    elseif(iEntityIndex == aFrame[2] or (iOwnerIndex == aFrame[1] and sModel:find("weapons\\w_")))then
        g_MaterialOverride:Set(false, UI.m_groupAttachments);
        return;

    elseif(iOwnerIndex == aFrame[1] and sModel:find("facemasks"))then
        g_MaterialOverride:Set(false, UI.m_groupMask); 
        return;

    -- This is very hacky for the gloves to work.
    elseif(iOwnerIndex == aFrame[1])then
        g_MaterialOverride:Set(false, UI.m_groupPlayer);
        return;
    end

    IStudioRender:DrawModel();
end 

client.delay_call(1, function()
    IStudioRender:StartHook(function(this, ecx, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags)
        -- Store the context.
        IStudioRender.m_aDrawModelContext = {ecx, results, info, bones, flex_weights, flex_delayed_weights, model_origin, flags};
        if(not info.m_pClientEntity or (flags > 2 and flags ~= 2084))then --STUDIORENDER_DRAW_ENTIRE_MODEL, STUDIORENDER_DRAW_OPAQUE_ONLY, STUDIORENDER_DRAW_TRANSLUCENT_ONLY
            IStudioRender:DrawModel();
            return;
        end

        local bSuccess, sError = pcall(OnDrawModel, ffi.string(info.m_pStudioHdr.name), IClientRenderable:New(info.m_pClientEntity), flags == 2084);
        if(not bSuccess)then
            print(sError);
        end
    end);
end);

ui.set_callback(UI.m_guiGroup, function()
    UI:Organize(false);
end);

UI:Organize(false);
