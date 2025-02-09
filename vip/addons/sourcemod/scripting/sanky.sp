#pragma semicolon 1;
#pragma newdecls required;

#include <sourcemod>
#include <clientprefs>
#include <basecomm>
#include <vip_core>
#include <sdktools>
#include <karyuu/plugin/chatprocessor>

// ************************** Author & Description ***************************

public Plugin myinfo =
{
	name = "[VIP] Sanky Sounds",
	author = "xSLOW, edited by .NiGHT",
	description = "Custom Entry & Chat sounds",
	version = "3.0",
	url = "https://github.com/NiGHT757/sanky-sounds"
};

// ************************** Variables ***************************
ConVar g_cvAntiSpam_GlobalTime;

StringMap g_hSoundList;
StringMap g_hEntryList;
StringMap g_hEntryChances;
StringMap g_hMessages;

int g_iAntiSpam_GlobalTime,
	g_iSoundsDeelayGlobal,
	g_iEntryListSize,
    g_iSoundsDeelay[MAXPLAYERS + 1],
	g_iClientDeelay[MAXPLAYERS + 1];

Menu g_hMenu;

Handle g_hCookie = null;

bool    g_bHasEntry[MAXPLAYERS + 1],
		g_bHasEntryOn[MAXPLAYERS+1],
		g_bEnable[MAXPLAYERS + 1],
		g_bEnabled,
		g_bLateLoaded;

float g_fVolume[MAXPLAYERS+1], g_fEntryVolume[MAXPLAYERS+1];

static const char g_sFeature[] = "Sanks";

// ************************** OnPluginStart ***************************

public void OnPluginStart()
{
	if(VIP_IsVIPLoaded())
	{
		VIP_OnVIPLoaded();
	}

	g_hSoundList = new StringMap();
	g_hEntryList = new StringMap();
	g_hEntryChances = new StringMap();
	g_hMessages = new StringMap();

	HookEventEx("cs_win_panel_match", Disable, EventHookMode_PostNoCopy);
	HookEventEx("round_end", Disable, EventHookMode_PostNoCopy);

	HookEventEx("round_start", Enable, EventHookMode_PostNoCopy);

	RegConsoleCmd("sm_sounds", cmd_sanky);
	RegConsoleCmd("sm_sank", cmd_sanky);
	RegConsoleCmd("sm_sankvol", cmd_sankvol);
	RegConsoleCmd("sm_entryvol", cmd_entryvol);

	RegAdminCmd("sm_sanksounds_reloadcfg", Command_ReloadCfg, ADMFLAG_ROOT);

	g_hCookie = RegClientCookie("SankSounds", "Turn it ON/OFF", CookieAccess_Protected);

	g_cvAntiSpam_GlobalTime = CreateConVar("sm_sanksounds_playedsound", "10", "Time interval to play sounds");
	g_cvAntiSpam_GlobalTime.AddChangeHook(OnSettingsChanged);

	if(g_bLateLoaded)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			OnClientCookiesCached(i);
			VIP_OnVIPClientLoaded(i);
		}
		g_bEnabled = true;
	}
	SetCookieMenuItem(sanky_options, 0, "Sank & Entry Sounds");

	AutoExecConfig(true, "SankSounds");
	LoadTranslations("sankysounds.phrases");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoaded = late;
	return APLRes_Success;
}

// ************************** OnSettingsChanged ***************************
public void OnSettingsChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
	g_iAntiSpam_GlobalTime = g_cvAntiSpam_GlobalTime.IntValue;
}

public void OnConfigsExecuted()
{
	g_iAntiSpam_GlobalTime = g_cvAntiSpam_GlobalTime.IntValue;
}

// ************************** VIP ***************************
public void OnPluginEnd()
{
	VIP_UnregisterMe();
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;

		SaveClientOptions(i);
	}
}

public void VIP_OnVIPLoaded()
{
	VIP_RegisterFeature(g_sFeature, INT, _, OnToggleItem, OnItemDisplay);
}

public void VIP_OnVIPClientLoaded(int iClient)
{
	g_bEnable[iClient] = VIP_IsClientFeatureUse(iClient, g_sFeature);
	g_iClientDeelay[iClient] = VIP_GetClientFeatureInt(iClient, g_sFeature);
}

public void VIP_OnVIPClientRemoved(int iClient, const char[] szReason, int iAdmin)
{
	g_bEnable[iClient] = false;
}

public Action OnToggleItem(int iClient, const char[] sFeatureName, VIP_ToggleState OldStatus, VIP_ToggleState &NewStatus)
{
	g_bEnable[iClient] = (NewStatus == ENABLED);
	g_iClientDeelay[iClient] = VIP_GetClientFeatureInt(iClient, g_sFeature);
	return Plugin_Continue;
}

public bool OnItemDisplay(int iClient, const char[] szFeature, char[] szDisplay, int iMaxLength)
{
	if (g_bEnable[iClient])
	{
		FormatEx(szDisplay, iMaxLength, "%s [%d seconds]", g_sFeature, g_iClientDeelay[iClient]);
		return true;
	}
	
	return false;
}

public void Disable(Event event, const char[] name, bool db)
{
	g_bEnabled = false;
}

public void Enable(Event event, const char[] name, bool db)
{
	g_bEnabled = true;

	for(int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if(g_iClientDeelay[iClient] == -1)
			g_iSoundsDeelay[iClient] = 0;
	}
}

public void OnMapEnd()
{
	g_bEnabled = false;
}

// ************************** OnMapStart ***************************

public void OnMapStart()
{
	g_bEnabled = false;
	LoadConfig();
}

// ************************** OnClientsCookiesCached ***************************

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client)) return;

	static char sBuffer[16];
	static char sExplode[3][12];

	GetClientCookie(client, g_hCookie, sBuffer, sizeof(sBuffer));
	ExplodeString(sBuffer, ":", sExplode, sizeof(sExplode), sizeof(sExplode[]));

	if(!sExplode[0][0])
		g_fEntryVolume[client] = 1.0;
	else g_fEntryVolume[client] = StringToFloat(sExplode[0]);

	if(!sExplode[1][0])
		g_fVolume[client] = 1.0;
	else g_fVolume[client] = StringToFloat(sExplode[1]);

	if(!sExplode[2][0])
		g_bHasEntryOn[client] = true;
	else g_bHasEntryOn[client] = view_as<bool>(StringToInt(sExplode[2][0]));
}

// ************************** OnClientPostAdminCheck ***************************

public void OnClientPostAdminCheck(int client)
{
	g_bEnable[client] = false;
	if(!g_iEntryListSize || !client || IsFakeClient(client))
	{
		return;
	}

	static char sAuthID[32], sData[128];
	GetClientAuthId(client, AuthId_Steam2, sAuthID, sizeof(sAuthID));

	int iValue;
	if(g_hEntryChances.GetValue(sAuthID, iValue))
	{
		if(g_bHasEntryOn[client] && iValue >= GetRandomInt(0, 100))
		{
			DataPack pack;
			g_hEntryList.GetString(sAuthID, sData, sizeof(sData));
			CreateDataTimer(5.0, Timer_LoadEntry, pack, TIMER_FLAG_NO_MAPCHANGE);

			pack.WriteCell(GetClientUserId(client));
			pack.WriteString(sData);
			g_hMessages.GetString(sAuthID, sData, sizeof(sData));
			pack.WriteString(sData);
		}
		g_bHasEntry[client] = true;
	}
}

// ************************** Command_ReloadCfg ***************************

public Action Command_ReloadCfg(int client, int args)
{
	LoadConfig();
	return Plugin_Handled;
}

public Action cmd_sankvol(int client, int args)
{
	if(!client || !IsClientInGame(client))
		return Plugin_Handled;

	if(args != 1)
	{
		CPrintToChat(client, "%T", "Volume Error", client);
		return Plugin_Handled;
	}

	char arg1[6];
	GetCmdArg(1, arg1, sizeof(arg1));

	float volume;
	volume = StringToFloat(arg1);

	if(volume > 1.0 || volume < 0.0)
	{
		CPrintToChat(client, "%T", "Volume Error", client);
		return Plugin_Handled;
	}

	g_fVolume[client] = StringToFloat(arg1);
	CPrintToChat(client, "%T", "Option Saved", client, g_fVolume[client]);

	SaveClientOptions(client);
	return Plugin_Handled;
}

public Action cmd_entryvol(int client, int args)
{
	if(!client || !IsClientInGame(client))
		return Plugin_Handled;

	if(args != 1)
	{
		CPrintToChat(client, "%T", "Volume Error", client);
		return Plugin_Handled;
	}

	char arg1[6];
	GetCmdArg(1, arg1, sizeof(arg1));

	float volume;
	volume = StringToFloat(arg1);

	if(volume > 1.0 || volume < 0.0)
	{
		CPrintToChat(client, "%T", "Volume Error", client);
		return Plugin_Handled;
	}

	g_fEntryVolume[client] = StringToFloat(arg1);
	CPrintToChat(client, "%T", "Option Saved", client, g_fEntryVolume[client]);

	SaveClientOptions(client);
	return Plugin_Handled;
}

public Action Timer_LoadEntry(Handle timer, DataPack pack)
{
	pack.Reset();

	int client;
	char sSound[PLATFORM_MAX_PATH];
	char sText[128];

	client = GetClientOfUserId(pack.ReadCell());
	pack.ReadString(sSound, sizeof(sSound));
	pack.ReadString(sText, sizeof(sText));

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}
		if(g_bEnabled)
			EmitSoundToClient(i, sSound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, g_fEntryVolume[i]);
		
		CPrintToChat(i, "{lightgreen}—————————————————————————————————");
		CPrintToChat(i, sText, client);
		CPrintToChat(i, "{lightgreen}—————————————————————————————————");
	}
	return Plugin_Stop;
}
// ************************** OnClientSayCommand_Post ***************************

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if(!client || !g_bEnabled || !g_bEnable[client] || !g_fVolume[client] || !sArgs[1] || sArgs[0] == '/' || sArgs[0] == '!' || BaseComm_IsClientGagged(client))
		return;
	
	static char szSound[PLATFORM_MAX_PATH];
	if(g_hSoundList.GetString(sArgs, szSound, PLATFORM_MAX_PATH))
	{
		if(g_iClientDeelay[client] == -1)
		{
			if(!g_iSoundsDeelay[client])
			{
				int	iDeelay = (GetTime() - g_iSoundsDeelayGlobal);
				if(iDeelay > g_iAntiSpam_GlobalTime)
				{
					for(int iClient = 1; iClient <= MaxClients; iClient++)
					{
						if(!IsClientInGame(iClient))
						{
							continue;
						}
						EmitSoundToClient(iClient, szSound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, g_fVolume[iClient]);
					}
					g_iSoundsDeelay[client] = 1;
					g_iSoundsDeelayGlobal = GetTime();
				}
				else CPrintToChat(client, "%T", "Global Already Played", client, g_iAntiSpam_GlobalTime - iDeelay);
			}
			else CPrintToChat(client, "%T", "Round Already Played", client);
		}
		else{
			int iTime = GetTime();
			int iDeelay = (iTime - g_iSoundsDeelay[client]);
			if(iDeelay > g_iClientDeelay[client])
			{
				iDeelay = (iTime - g_iSoundsDeelayGlobal);
				if(iDeelay > g_iAntiSpam_GlobalTime)
				{
					for(int iClient = 1; iClient <= MaxClients; iClient++)
					{
						if(!IsClientInGame(iClient))
						{
							continue;
						}
						EmitSoundToClient(iClient, szSound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, g_fVolume[iClient]);
					}
					g_iSoundsDeelay[client] = iTime;
					g_iSoundsDeelayGlobal = iTime;
				}
				else CPrintToChat(client, "%T", "Global Already Played", client, g_iAntiSpam_GlobalTime - iDeelay);
			}
			else CPrintToChat(client, "%T", "Already Played", client, g_iClientDeelay[client] - iDeelay);
		}
	}
}
// ************************** Menu ***************************

public Action cmd_sanky(int client, int args)
{
    if(!client || !IsClientInGame(client))
    {
    	return Plugin_Handled;
    }
    ShowCommand(client);

    return Plugin_Handled;
}

public int ShowMainMenuHandler(Menu MainMenu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			switch(param2)
			{
				case 0: // Sank Sounds Volume
				{
					Menu menu = new Menu(Handler_SankVolume);
					menu.SetTitle("%T", "Sanky Sounds SubMenuTitle", client, g_fVolume[client]);

					menu.AddItem("0.0", "Mute");
					menu.AddItem("0.2", "20%");
					menu.AddItem("0.4", "40%");
					menu.AddItem("0.6", "60%");
					menu.AddItem("0.8", "80%");
					menu.AddItem("1.0", "100%");
					
					menu.ExitBackButton = true;
					menu.Display(client, 0);
				}
				case 1: // Entry Sounds
				{
					Menu menu = new Menu(Handler_EntryVolume);
					menu.SetTitle("%T", "Entry Sounds SubMenuTitle", client, g_fEntryVolume[client]);

					menu.AddItem("0.0", "Mute");
					menu.AddItem("0.2", "20%");
					menu.AddItem("0.4", "40%");
					menu.AddItem("0.6", "60%");
					menu.AddItem("0.8", "80%");
					menu.AddItem("1.0", "100%");

					menu.ExitBackButton = true;
					menu.Display(client, 0);
				}
				case 2:
				{
					g_bHasEntryOn[client] = !g_bHasEntryOn[client];
					SaveClientOptions(client);
					CPrintToChat(client, "%T", "Entry Sounds OptionSaved", client, g_bHasEntryOn[client] ? "\x04ENABLED":"\x02DISABLED");
				}
				case 3: // Sank Sounds list
				{
					g_hMenu.Display(client, 0);
				}
			}
		}
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				ShowCookieMenu(client);
		}
		case MenuAction_End:
		{
			delete MainMenu;
		}
	}
	return 0;
}

public int Handler_SankVolume(Menu menu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char fVolume[8];
			menu.GetItem(param2, fVolume, sizeof(fVolume));
			g_fVolume[client] = StringToFloat(fVolume);
			SaveClientOptions(client);
			CPrintToChat(client, "%T", "Option Saved", client, g_fVolume[client]);
		}
		case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_ExitBack)
			{
				ShowCommand(client);
			}
        }
		case MenuAction_End: delete menu;
	}
	return 0;
}

public int Handler_EntryVolume(Menu menu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char fVolume[8];
			menu.GetItem(param2, fVolume, sizeof(fVolume));
			g_fEntryVolume[client] = StringToFloat(fVolume);
			SaveClientOptions(client);
			CPrintToChat(client, "%T", "Option Saved", client, g_fEntryVolume[client]);
		}
		case MenuAction_Cancel:
        {
            if(param2 == MenuCancel_ExitBack)
			{
				ShowCommand(client);
			}
        }
		case MenuAction_End: delete menu;
	}
	return 0;
}

public int Menu_SoundsList(Menu menu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char szSound[PLATFORM_MAX_PATH];
			menu.GetItem(param2, szSound, PLATFORM_MAX_PATH);
			EmitSoundToClient(client, szSound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, g_fVolume[client]);
			g_hMenu.DisplayAt(client, g_hMenu.Selection, MENU_TIME_FOREVER);
		}
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
			{
				ShowCommand(client);
			}
		}
	}
	return 0;
}

// ************************** sanky_options ***************************

public void sanky_options(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if(action == CookieMenuAction_SelectOption)
	{
		ShowCommand(client);
	}
}

// ************************** ShowCommand ***************************

void ShowCommand(int client)
{
	char sFormat[32];
	Menu MainMenu = new Menu(ShowMainMenuHandler);
	MainMenu.SetTitle("%T", "Sanky Sounds MainMenuTitle", client);
	FormatEx(sFormat, sizeof(sFormat), "%T", "Sanky Sounds SubMenuVolume", client, g_fVolume[client]);
	MainMenu.AddItem("", sFormat);
	FormatEx(sFormat, sizeof(sFormat), "%T", "Entry Sounds SubMenuVolume", client, g_fEntryVolume[client]);
	MainMenu.AddItem("", sFormat);
	FormatEx(sFormat, sizeof(sFormat), "%T", "Entry Sounds OptionSaved", client, g_bHasEntryOn[client] ? "ENABLED" : "DISABLED");
	MainMenu.AddItem("", sFormat, g_bHasEntry[client] ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	FormatEx(sFormat, sizeof(sFormat), "%T", "Sound List MainMenuText", client);
	MainMenu.AddItem("", sFormat, g_bEnable[client] ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	MainMenu.ExitBackButton = true;
	MainMenu.Display(client, 15);
}

// ************************** SaveClientOptions ***************************

void SaveClientOptions(int client)
{
	char sFormat[24];
	FormatEx(sFormat, sizeof(sFormat), "%.2f:%.2f:%d", g_fVolume[client], g_fEntryVolume[client], g_bHasEntryOn[client]);
	SetClientCookie(client, g_hCookie, sFormat);
}

// ************************** LoadConfig ***************************

void LoadConfig()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/SankSounds.cfg");
	if(FileExists(sPath))
	{
		KeyValues kv = new KeyValues("Settings");

		if(!kv.ImportFromFile(sPath))
		{
			SetFailState("Unable to parse key values.");
		}

		if(!kv.JumpToKey("SankSounds"))
		{
			SetFailState("Unable to JumpToKey 'SankSounds'");
		}

		if(!kv.GotoFirstSubKey())
		{
			SetFailState("Unable to find first sub key");
		}

		delete g_hMenu;
		
		g_hSoundList.Clear();
		g_hEntryList.Clear();
		g_hEntryChances.Clear();
		g_hMessages.Clear();
		
		g_hMenu = new Menu(Menu_SoundsList);

		char SectionName[128], SoundDownload[PLATFORM_MAX_PATH];
		char ExplodedString[12][64];
		int ExplodeCounter;
		do
		{
			kv.GetSectionName(SectionName, sizeof(SectionName));
			kv.GetString("file", sPath, sizeof(sPath));
			if(StrContains(SectionName, "|", false))
			{
				ExplodeCounter = ExplodeString(SectionName, "|", ExplodedString, sizeof(ExplodedString), sizeof(ExplodedString[]));

				for(int i = 0; i < ExplodeCounter; i++)
				{
					FormatEx(SoundDownload, sizeof(SoundDownload), "sound/%s", sPath);
					if(FileExists(SoundDownload))
					{
						g_hSoundList.SetString(ExplodedString[i], sPath);
					}
				}
			}
			else{
				FormatEx(SoundDownload, sizeof(SoundDownload), "sound/%s", sPath);
				if(FileExists(SoundDownload))
				{
					g_hSoundList.SetString(SectionName, sPath);
				}
			}
			if(FileExists(SoundDownload))
			{
				g_hSoundList.SetString(SectionName, sPath);
				g_hMenu.AddItem(sPath, SectionName);
				AddFileToDownloadsTable(SoundDownload);
				PrecacheSound(sPath);
			}
			else LogError("Missing sank sound file: %s", sPath);
		} while (kv.GotoNextKey());
		kv.Rewind();

		g_hMenu.SetTitle("%T", "Sounds List SubMenuText", LANG_SERVER, g_hSoundList.Size);
		g_hMenu.ExitBackButton = true;

		if(kv.JumpToKey("EntrySounds") && kv.GotoFirstSubKey())
		{
			char sText[128];
			do
			{
				kv.GetSectionName(SectionName, sizeof(SectionName)); // steamid

				kv.GetString("sound", sPath, sizeof(sPath));
				g_hEntryList.SetString(SectionName, sPath); // soundpath

				g_hEntryChances.SetValue(SectionName, kv.GetNum("chance", 100)); // entry chance

				kv.GetString("text", sText, sizeof(sText)); // entry message
				g_hMessages.SetString(SectionName, sText);

				// precache & download
				FormatEx(SoundDownload, sizeof(SoundDownload), "sound/%s", sPath);
				if(FileExists(SoundDownload))
				{
					AddFileToDownloadsTable(SoundDownload);
					PrecacheSound(sPath);
				}
				else LogError("Missing sank sound file: %s", sPath);
			}while(kv.GotoNextKey());
		}
		delete kv;
	}
	else SetFailState("Config file %s not found. Check if config files are missing.", sPath);

	g_iEntryListSize = g_hEntryList.Size;
}