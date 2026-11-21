#pragma once

// parent object names that mark a player model; tune from the log
static const char *kPlayerMarkers[] = {
    "Player", "Bot", "Character", "Human", "Avatar", "Soldier", NULL
};

// objects whose parent chain contains these are skipped (viewmodel, hands)
static const char *kIgnoreMarkers[] = {
    "Weapon", "ViewModel", "Arms", "Hands", "Camera", NULL
};

// class names the skinchanger will consider
static const char *kSkinClasses[] = {
    "Weapon", "WeaponParameters", "SkinManager", "WeaponSkin",
    "PlayerWeapon", "WeaponView", NULL
};

// setter names (1 int arg)
static const char *kSkinSetters[] = {
    "SetSkin", "SetSkinId", "ApplySkin", "set_SkinId", NULL
};

// getter names (0 args, returns int) - overridden on the way out
static const char *kSkinGetters[] = {
    "get_SkinId", "get_CurrentSkin", "get_Skin", NULL
};

// default cham color
#define CHAM_R 1.0f
#define CHAM_G 0.10f
#define CHAM_B 0.85f
#define CHAM_A 0.85f
