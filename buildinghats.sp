#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#pragma newdecls required

#define PLUGIN_VERSION "3.0"

ArrayList g_hHatInfo;

public Plugin myinfo =
{
	name		= "Building Hats",
	author		= "VoiDeD, Pelipoika",
	description	= "",
	version		= PLUGIN_VERSION,
	url			= "http://saxtonhell.com",
};

public void OnPluginStart()
{
	HookEvent("player_builtobject", OnObjectBuilt);
	HookEvent("player_carryobject", OnObjectPickedUp);
	HookEvent("player_dropobject", OnObjectDropped);
	HookEvent("player_upgradedobject", OnObjectUpgraded);
	
	g_hHatInfo = new ArrayList(PLATFORM_MAX_PATH, 1);
}

public void OnMapStart()
{
	if (!Config_Load())
		SetFailState("Unable to load config");

	if (Config_GetNumHats() == 0)
		SetFailState("No hats defined in config");
		
	PrintToServer("Config loaded (%i hats)", Config_GetNumHats());
}

public void OnMapEnd()
{
	Config_Unload();
}

public Action OnObjectBuilt(Event event, const char[] name, bool dontBroadcast)
{
	int objectEnt = event.GetInt("index");

	if (!IsHattableObject(TF2_GetObjectType(objectEnt)))
		return;

	if (IsValidEntity(GetObjectHat(objectEnt)))
	{
		// this object already has a hat, we don't want to attach another
		return;
	}

	int hatIndex = GetRandomInt(0, Config_GetNumHats() - 1) * 4;

	char hatModel[PLATFORM_MAX_PATH];
	float modelScale, modelOffset;
	Config_GetHat(hatIndex, hatModel, modelScale, modelOffset);

	GiveObjectHat(objectEnt, hatModel);
	
	if(TF2_GetObjectType(objectEnt) == TFObject_Sentry && GetEntProp(objectEnt, Prop_Send, "m_bMiniBuilding"))
	{
		SetVariantInt(2);
		AcceptEntityInput(objectEnt, "SetBodyGroup");
		SDKHook(objectEnt, SDKHook_GetMaxHealth, ThinkLightsOff);
	}
}

public Action OnObjectPickedUp(Event event, const char[] name, bool dontBroadcast)
{
	int objectEnt = event.GetInt("index");

	if (!IsHattableObject(TF2_GetObjectType(objectEnt)))
		return;

	int hatProp = GetObjectHat(objectEnt);

	if (IsValidEntity(hatProp))
	{
		AcceptEntityInput(hatProp, "TurnOff");
	}
}

public Action OnObjectDropped(Event event, const char[] name, bool dontBroadcast)
{
	int objectEnt = event.GetInt("index");

	if (!IsHattableObject(TF2_GetObjectType(objectEnt)))
		return;

	int hatProp = GetObjectHat(objectEnt);

	if (IsValidEntity(hatProp))
	{
		AcceptEntityInput(hatProp, "TurnOn");
		
		if(TF2_GetObjectType(objectEnt) == TFObject_Sentry && GetEntProp(objectEnt, Prop_Send, "m_bMiniBuilding"))
		{
			SetVariantInt(2);
			AcceptEntityInput(objectEnt, "SetBodyGroup");
			
			SDKHook(objectEnt, SDKHook_GetMaxHealth, ThinkLightsOff);
		}
	}
}

public Action ThinkLightsOff(int iEnt)
{
	float flPercentageConstructed = GetEntPropFloat(iEnt, Prop_Send, "m_flPercentageConstructed");
	
	if(flPercentageConstructed >= 1.0)
	{
		SDKUnhook(iEnt, SDKHook_GetMaxHealth, ThinkLightsOff);
		RequestFrame(TurnOffLight, iEnt);	//One more frame
	}
}

public void TurnOffLight(int iEnt)
{
	SetVariantInt(2);
	AcceptEntityInput(iEnt, "SetBodyGroup");
}

public Action OnObjectUpgraded(Event event, const char[] name, bool dontBroadcast)
{
	int objectEnt = event.GetInt("index");

	if (!IsHattableObject(TF2_GetObjectType(objectEnt)))
		return;

	if (TF2_GetObjectType(objectEnt) == TFObject_Dispenser && GetEntProp(objectEnt, Prop_Send, "m_iUpgradeLevel") == 1)
	{
		// don't need to re-parent hat if we're sitting on a level 1 dispenser as the attachment point doesn't move
		return;
	}

	int hatProp = GetObjectHat(objectEnt);

	if (IsValidEntity(hatProp))
	{
		// hide the hat while we re-parent it to the new model
		AcceptEntityInput(hatProp, "TurnOff");

		// need to delay some time for the upgrade animation to complete
		CreateTimer(2.0, Timer_ReparentHat, hatProp, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_ReparentHat(Handle hTimer, int data)
{
	int hatProp = data;

	if (!IsValidEntity(hatProp))
	{
		// hat prop disappeared
		return;
	}

	int objectEnt = GetEntPropEnt(hatProp, Prop_Data, "m_hMoveParent");

	if (!IsValidEntity(objectEnt))
		return;

	ParentHat(hatProp, objectEnt);

	// display the hat again
	AcceptEntityInput(hatProp, "TurnOn");
}

stock void GiveObjectHat(int objectEnt, const char hatModel[PLATFORM_MAX_PATH])
{
	int hatProp = CreateEntityByName("prop_dynamic_override");

	if (IsValidEntity(hatProp))
	{
		SetEntityModel(hatProp, hatModel);
		DispatchSpawn(hatProp);

		AcceptEntityInput(hatProp, "DisableCollision");
		AcceptEntityInput(hatProp, "DisableShadow");

		ParentHat(hatProp, objectEnt);
	}
}

stock int GetObjectHat(int objectEnt)
{
	int ent = -1;

	while((ent = FindEntityByClassname(ent, "prop_dynamic")) != -1)
	{
		int parent = GetEntPropEnt(ent, Prop_Data, "m_hMoveParent");

		if (parent == objectEnt)
		{
			// prop is parented to our object, so it's most likely our hat
			return ent;
		}
	}

	return -1;
}

stock void ParentHat(int hatProp, int objectEnt)
{
	char hatModel[PLATFORM_MAX_PATH];
	GetEntPropString(hatProp, Prop_Data, "m_ModelName", hatModel, sizeof(hatModel));

	float modelScale = 1.0;
	float modelOffset = 0.0;

	if (!Config_GetHatByModel(hatModel, modelOffset, modelScale))
	{
		LogError("Unable to find hat config for hat: %s", hatModel);
		return;
	}
	
	int iBuilder = GetEntPropEnt(objectEnt, Prop_Send, "m_hBuilder");
	
	SetEntProp(hatProp, Prop_Send, "m_nSkin", GetClientTeam(iBuilder) - 2);
	SetEntPropFloat(hatProp, Prop_Send, "m_flModelScale", modelScale);

	char attachmentName[128];
	GetAttachmentName(objectEnt, attachmentName, sizeof(attachmentName));

	SetVariantString("!activator");
	AcceptEntityInput(hatProp, "SetParent", objectEnt);

	SetVariantString(attachmentName);
	AcceptEntityInput(hatProp, "SetParentAttachment", objectEnt);

	float vecPos[3], angRot[3];
	GetEntPropVector(hatProp, Prop_Send, "m_vecOrigin", vecPos);
	GetEntPropVector(hatProp, Prop_Send, "m_angRotation", angRot);

	// apply z offset
	vecPos[2] += modelOffset;

	// apply position/angle fixes based on object type
	OffsetAttachmentPosition(objectEnt, vecPos, angRot);

	TeleportEntity(hatProp, vecPos, angRot, NULL_VECTOR);
}

stock void GetAttachmentName(int objectEnt, char[] attachmentBuffer, int maxBuffer)
{
	switch (TF2_GetObjectType(objectEnt))
	{
		case TFObject_Dispenser:
			strcopy(attachmentBuffer, maxBuffer, "build_point_0");

		case TFObject_Sentry:
		{
			if (GetEntProp(objectEnt, Prop_Send, "m_iUpgradeLevel") < 3)
			{
				strcopy(attachmentBuffer, maxBuffer, "build_point_0");
			}
			else
			{
				// for level 3 sentries we can use the rocket launcher attachment
				strcopy(attachmentBuffer, maxBuffer, "rocket_r");
			}
		}
	}
}

stock void OffsetAttachmentPosition(int objectEnt, float pos[3], float ang[3])
{
	switch (TF2_GetObjectType(objectEnt))
	{
		case TFObject_Dispenser:
		{
			pos[2] += 13.0; // build_point_0 is a little low on the dispenser, bring it up
			ang[1] += 180.0; // turn the hat around to face the builder

			if (GetEntProp(objectEnt, Prop_Send, "m_iUpgradeLevel") == 3)
				pos[2] += 8.0; // level 3 dispenser is even taller
		}

		case TFObject_Sentry:
		{
			if (GetEntProp(objectEnt, Prop_Send, "m_iUpgradeLevel") == 3)
			{
				pos[2] += 6.5;
				pos[0] -= 11.0;
			}
		}
	}
}

stock bool IsHattableObject(TFObjectType objectEnt)
{
	// only parent hats to sentries and dispensers
	return objectEnt == TFObject_Sentry || objectEnt == TFObject_Dispenser;
}

stock bool Config_Load()
{
	char strPath[PLATFORM_MAX_PATH];
	char strFileName[PLATFORM_MAX_PATH];
	Format(strFileName, sizeof(strFileName), "configs/buildinghats.cfg");
	BuildPath(Path_SM, strPath, sizeof(strPath), strFileName);

	if (FileExists(strPath, true))
	{
		KeyValues kvConfig = new KeyValues("TF2_Buildinghats");
		
		if (!FileToKeyValues(kvConfig, strPath)) 
		{
			SetFailState("[Building Hats] Error while parsing the configuration file.");
			return false;
		}
		
		kvConfig.GotoFirstSubKey();

		do
		{
			char strMpath[PLATFORM_MAX_PATH], strOffz[16], strScale[16], strAnima[128]; 
			
			kvConfig.GetString("modelpath",  strMpath, sizeof(strMpath));
			kvConfig.GetString("offset",     strOffz,  sizeof(strOffz));
			kvConfig.GetString("modelscale", strScale, sizeof(strScale));
			kvConfig.GetString("animation",  strAnima, sizeof(strAnima));
			
			PrecacheModel(strMpath);
			
			g_hHatInfo.PushString(strMpath);
			g_hHatInfo.PushString(strOffz);
			g_hHatInfo.PushString(strScale);
			g_hHatInfo.PushString(strAnima);			
		}
		while (kvConfig.GotoNextKey());

		delete kvConfig;
		
		return true;
	}
	
	return false;
}

stock int Config_GetNumHats()
{
	return GetArraySize(g_hHatInfo) / 4;
}

stock void Config_Unload()
{
	g_hHatInfo.Resize(1);
}

stock bool Config_GetHatByModel(char hatModel[PLATFORM_MAX_PATH], float &modelOffset, float &modelScale)
{
	int index = g_hHatInfo.FindString(hatModel);
	if(index > -1)
	{
		char strScale[8], strOffset[8];
		g_hHatInfo.GetString(index+1, strOffset, sizeof(strOffset));
		g_hHatInfo.GetString(index+2, strScale,  sizeof(strScale));
		
		modelScale = StringToFloat(strScale);
		modelOffset = StringToFloat(strOffset);
		
		return true;
	}
	
	return false;
}

stock void Config_GetHat(int hatIndex, char hatModel[PLATFORM_MAX_PATH], float &modelScale, float &modelOffset)
{
	char strModel[PLATFORM_MAX_PATH], strScale[8], strOffset[8];
	g_hHatInfo.GetString(hatIndex+1, strModel,  sizeof(strModel));
	g_hHatInfo.GetString(hatIndex+2, strOffset, sizeof(strOffset));
	g_hHatInfo.GetString(hatIndex+3, strScale,  sizeof(strScale));
	
	hatModel = strModel;
	modelScale = StringToFloat(strScale);
	modelOffset = StringToFloat(strOffset);
}