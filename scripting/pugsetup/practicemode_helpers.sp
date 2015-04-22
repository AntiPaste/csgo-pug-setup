public ConVar GetCvar(const char[] name) {
    ConVar cvar = FindConVar(name);
    if (cvar == null) {
        SetFailState("Failed to find cvar: \"%s\"", name);
    }
    return cvar;
}

public bool IsGrenadeProjectile(const char[] className) {
    static char projectileTypes[][] = {
        "hegrenade_projectile",
        "smokegrenade_projectile",
        "decoy_projectile",
        "flashbang_projectile",
        "molotov_projectile",
    };

    return FindStringInArray2(projectileTypes, sizeof(projectileTypes), className) >= 0;
}

public bool IsGrenadeWeapon(const char[] weapon) {
    static char grenades[][] = {
        "incgrenade",
        "molotov",
        "hegrenade",
        "decoy",
        "flashbang",
        "smokegrenade",
    };

    return FindStringInArray2(grenades, sizeof(grenades), weapon) >= 0;
}

public void TeleportToGrenadeHistoryPosition(int client, int index) {
    float origin[3];
    float angles[3];
    float velocity[3];
    g_GrenadeHistoryPositions[client].GetArray(index, origin, sizeof(origin));
    g_GrenadeHistoryAngles[client].GetArray(index, angles, sizeof(angles));
    TeleportEntity(client, origin, angles, velocity);
}

public void UpdatePlayerColor(int client) {
    QueryClientConVar(client, "cl_color", QueryClientColor, client);
}

public void QueryClientColor(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue) {
    int color = StringToInt(cvarValue);
    GetColor(view_as<ClientColor>(color), g_ClientColors[client]);
}

public void GetColor(ClientColor c, int array[4]) {
    int r, g, b;
    switch(c) {
        case ClientColor_Green:  { r = 0;   g = 255; b = 0; }
        case ClientColor_Purple: { r = 128; g = 0;   b = 128; }
        case ClientColor_Blue:   { r = 0;   g = 0;   b = 255; }
        case ClientColor_Orange: { r = 255; g = 128; b = 0; }
        case ClientColor_Yellow: { r = 255; g = 255; b = 0; }
    }
    array[0] = r;
    array[1] = g;
    array[2] = b;
    array[3] = 255;
}

public bool TeleportToSavedGrenadePosition(int client, const char[] auth, const char[] nadeIdStr) {
    float origin[3];
    float angles[3];
    float velocity[3];
    char description[GRENADE_DESCRIPTION_LENGTH];
    bool success = false;

    // update the client's current grenade id, if it was their grenade
    char clientAuth[AUTH_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, clientAuth, sizeof(clientAuth));
    if (StrEqual(clientAuth, auth)) {
        g_CurrentSavedGrenadeId[client] = StringToInt(nadeIdStr);
    } else {
        g_CurrentSavedGrenadeId[client] = -1;
    }

    if (g_GrenadeLocationsKv.JumpToKey(auth)) {
        if (g_GrenadeLocationsKv.JumpToKey(nadeIdStr)) {
            success = true;
            g_GrenadeLocationsKv.GetVector("origin", origin);
            g_GrenadeLocationsKv.GetVector("angles", angles);
            g_GrenadeLocationsKv.GetString("description", description, sizeof(description));
            TeleportEntity(client, origin, angles, velocity);

            if (!StrEqual(description, ""))
                PugSetupMessage(client, "Description: %s", description);
            g_GrenadeLocationsKv.GoBack();
        }
        g_GrenadeLocationsKv.GoBack();
    }

    return success;
}

public int SaveGrenadeToKv(int client, const float origin[3], const float angles[3], const char[] name) {
    g_UpdatedGrenadeKv = true;
    char auth[AUTH_LENGTH];
    char clientName[MAX_NAME_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    GetClientName(client, clientName, sizeof(clientName));
    g_GrenadeLocationsKv.JumpToKey(auth, true);
    g_GrenadeLocationsKv.SetString("name", clientName);
    int nadeId = g_GrenadeLocationsKv.GetNum("nextid", 1);
    g_GrenadeLocationsKv.SetNum("nextid", nadeId + 1);

    char idStr[32];
    IntToString(nadeId, idStr, sizeof(idStr));
    g_GrenadeLocationsKv.JumpToKey(idStr, true);

    g_GrenadeLocationsKv.SetString("name", name);
    g_GrenadeLocationsKv.SetVector("origin", origin);
    g_GrenadeLocationsKv.SetVector("angles", angles);

    g_GrenadeLocationsKv.GoBack();
    g_GrenadeLocationsKv.GoBack();
    return nadeId;
}

public bool DeleteGrenadeFromKv(int client, const char[] nadeIdStr) {
    g_UpdatedGrenadeKv = true;
    char auth[AUTH_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    bool deleted = false;
    if (g_GrenadeLocationsKv.JumpToKey(auth)) {
        char name[GRENADE_NAME_LENGTH];
        if (g_GrenadeLocationsKv.JumpToKey(nadeIdStr)) {
            g_GrenadeLocationsKv.GetString("name", name, sizeof(name));
            g_GrenadeLocationsKv.GoBack();
        }

        deleted = g_GrenadeLocationsKv.DeleteKey(nadeIdStr);
        g_GrenadeLocationsKv.GoBack();
        PugSetupMessage(client, "Deleted grenade id %s, \"%s\".", nadeIdStr, name);
    }
    return deleted;
}

public int AttemptFindTarget(const char[] target) {
    char target_name[MAX_TARGET_LENGTH];
    int target_list[1];
    bool tn_is_ml;
    int flags = COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_BOTS | COMMAND_FILTER_NO_IMMUNITY;

    if (ProcessTargetString(
            target,
            0,
            target_list,
            1,
            flags,
            target_name,
            sizeof(target_name),
            tn_is_ml) > 0) {
        return target_list[0];
    } else {
        return -1;
    }
}

public bool FindTargetInGrenadesKvByName(const char[] inputName, char[] name, int nameLen, char[] auth, int authLen) {
    if (g_GrenadeLocationsKv.GotoFirstSubKey()) {
        do {
            g_GrenadeLocationsKv.GetSectionName(auth, authLen);
            g_GrenadeLocationsKv.GetString("name", name, nameLen);

            if (StrContains(name, inputName) != -1) {
                g_GrenadeLocationsKv.GoBack();
                return true;
            }

        } while (g_GrenadeLocationsKv.GotoNextKey());
        g_GrenadeLocationsKv.GoBack();
    }
    return false;
}

public void UpdateGrenadeDescription(int client, int index, const char[] description) {
    g_UpdatedGrenadeKv = true;
    char auth[AUTH_LENGTH];
    GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
    char nadeIdStr[32];
    IntToString(index, nadeIdStr, sizeof(nadeIdStr));

    if (g_GrenadeLocationsKv.JumpToKey(auth)) {
        if (g_GrenadeLocationsKv.JumpToKey(nadeIdStr)) {
            g_GrenadeLocationsKv.SetString("description", description);
            g_GrenadeLocationsKv.GoBack();
        }
        g_GrenadeLocationsKv.GoBack();
    }
}

public bool FindGrenadeTarget(const char[] nameInput, char[] name, int nameLen, char[] auth, int authLen) {
    int target = AttemptFindTarget(nameInput);
    if (IsPlayer(target) && GetClientAuthId(target, AuthId_Steam2, auth, authLen)) {
        GetClientName(target, name, nameLen);
        GetClientAuthId(target, AuthId_Steam2, auth, authLen);
        return true;
    } else {
        return FindTargetInGrenadesKvByName(nameInput, name, nameLen, auth, authLen);
    }
}
