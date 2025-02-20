#include <sourcemod>
#include <clientprefs>
#include <basecomm>
#include <karyuu>
#include <sdktools>

#pragma semicolon 1;
#pragma newdecls required;

// ************************** Author & Description ***************************

public Plugin myinfo =
{
	name = "Sanky Sounds",
	author = "xSLOW, edited by .NiGHT",
	description = "Custom Entry & Chat sounds",
	version = "2.8",
	url = "https://github.com/NiGHT757/sanky-sounds"
};

// ************************** Variables ***************************
ConVar  g_CvAntiSpam_Time,
        g_cvAntiSpam_GlobalTime,
		g_cvFlagAccess;

StringMap g_hSoundList;
StringMap g_hEntryList;
StringMap g_hEntryChances;
StringMap g_hMessages;

int g_iAntiSpam_Time,
	g_iAntiSpam_GlobalTime,
	g_iSoundsDeelayGlobal,
	g_iFlagAccess,
    g_iEntryListSize,
    g_iSoundsDeelay[MAXPLAYERS + 1];

Menu g_hMenu;

Handle g_hCookie = null;

bool    g_bHasEntry[MAXPLAYERS + 1],
		g_bHasEntryOn[MAXPLAYERS+1],
		g_bEnable[MAXPLAYERS + 1],
		g_bEnabled,
		g_bLateLoaded;

float g_fVolume[MAXPLAYERS+1], g_fEntryVolume[MAXPLAYERS+1];

// ************************** OnPluginStart ***************************

public void OnPluginStart()
{
	g_hSoundList = new StringMap();
	g_hEntryList = new StringMap();
	g_hEntryChances = new StringMap();
	g_hMessages = new StringMap();

	HookEventEx("cs_win_panel_match", Disable, EventHookMode_PostNoCopy);
	HookEventEx("round_end", Disable, EventHookMode_PostNoCopy);

	HookEventEx("round_start", Enable, EventHookMode_PostNoCopy);

	RegConsoleCmd("sm_sounds", Command_Sanky);
	RegConsoleCmd("sm_sank", Command_Sanky);
	RegConsoleCmd("sm_sankvol", cmd_sankvol);
	RegConsoleCmd("sm_entryvol", cmd_entryvol);

	RegAdminCmd("sm_sanksounds_reloadcfg", Command_ReloadCfg, ADMFLAG_ROOT);

	g_hCookie = RegClientCookie("SankSounds", "Turn it ON/OFF", CookieAccess_Protected);

	g_CvAntiSpam_Time = CreateConVar("sm_sanksounds_antispam_time", "45", "How often I should reset the anti spam timer per client? 0 - reset on round start");
	g_cvAntiSpam_GlobalTime = CreateConVar("sm_sanksounds_playedsound", "10", "Time interval to play sounds");
	g_cvFlagAccess = CreateConVar("sm_sanksounds_flag", "", "Flags for sank acces , leave blank if no access for flags");

	g_CvAntiSpam_Time.AddChangeHook(OnSettingsChanged);
	g_cvAntiSpam_GlobalTime.AddChangeHook(OnSettingsChanged);
	g_cvFlagAccess.AddChangeHook(OnSettingsChanged);

	if(g_bLateLoaded)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			OnClientCookiesCached(i);
			g_bEnable[i] = CheckCommandAccess(i, "", g_iFlagAccess, true);
		}
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
void OnSettingsChanged(ConVar convar, const char[] oldVal, const char[] newVal)
{
	if(convar == g_CvAntiSpam_Time)
	{
		g_iAntiSpam_Time = convar.IntValue;
	}
	else if(convar == g_cvAntiSpam_GlobalTime)
	{
		g_iAntiSpam_GlobalTime = convar.IntValue;
	}
	else if(convar == g_cvFlagAccess)
	{
        char sFlags[8];
        g_cvFlagAccess.GetString(sFlags, 8);
        ReadFlagString(sFlags, g_iFlagAccess);
        if(g_iFlagAccess)
        {
            for(int iClient = 1; iClient <= MaxClients; iClient++)
            {
                if(!IsClientInGame(iClient) || IsFakeClient(iClient))
                    continue;
                
                g_bEnable[iClient] = CheckCommandAccess(iClient, "", g_iFlagAccess, true);
            }
        }
	} 
}

public void OnConfigsExecuted()
{
	g_iAntiSpam_Time = g_CvAntiSpam_Time.IntValue;
	g_iAntiSpam_GlobalTime = g_cvAntiSpam_GlobalTime.IntValue;

	char sFlags[8];
	g_cvFlagAccess.GetString(sFlags, 8);
	ReadFlagString(sFlags, g_iFlagAccess);
}

// enable/disable
void Disable(Event event, const char[] name, bool db)
{
	g_bEnabled = false;
}

void Enable(Event event, const char[] name, bool db)
{
	g_bEnabled = true;

	if(!g_iAntiSpam_Time)
	{
		for(int iClient = 1; iClient <= MaxClients; iClient++)
		{
			g_iSoundsDeelay[iClient] = 0;
		}
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
	ExplodeString(sBuffer, ":", sExplode, 3, 12, false);

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
	if(!client || IsFakeClient(client))
		return;

	g_bEnable[client] = CheckCommandAccess(client, "", g_iFlagAccess, true);

	if(!g_iEntryListSize)
		return;
	
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

public void OnRebuildAdminCache(AdminCachePart part)
{
    if(g_iFlagAccess)
    {
        for(int iClient = 1; iClient <= MaxClients; iClient++)
        {
            if(!IsClientInGame(iClient) || IsFakeClient(iClient))
                continue;
            
            g_bEnable[iClient] = CheckCommandAccess(iClient, "", g_iFlagAccess, true);
        }
    }
}

public void OnClientDisconnect(int client)
{
	g_bEnable[client] = false;
}

// ************************** Command_ReloadCfg ***************************

public Action Command_ReloadCfg(int client, int args)
{
	LoadConfig();
	return Plugin_Handled;
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
					FormatEx(SoundDownload, 128, "sound/%s", sPath);
					if(FileExists(SoundDownload))
					{
						g_hSoundList.SetString(ExplodedString[i], sPath);
					}
				}
			}
			else{
				FormatEx(SoundDownload, 128, "sound/%s", sPath);
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
				FormatEx(SoundDownload, 128, "sound/%s", sPath);
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

Action cmd_sankvol(int client, int args)
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
	SaveClientOptions(client);
	CPrintToChat(client, "%T", "Option Saved", client, g_fVolume[client]);

	return Plugin_Handled;
}

Action cmd_entryvol(int client, int args)
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

Action Timer_LoadEntry(Handle timer, DataPack pack)
{
	pack.Reset();
	int client;

	client = GetClientOfUserId(pack.ReadCell());
	if(!client)
		return Plugin_Stop;

	char sSound[PLATFORM_MAX_PATH];
	char sText[128];

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
		
		PrintToChat(i, " \x06—————————————————————————————————");
		CPrintToChat(i, sText, client);
		PrintToChat(i, " \x06—————————————————————————————————");
	}

	return Plugin_Stop;
}
// ************************** OnClientSayCommand_Post ***************************

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if(!client || !g_bEnabled || !sArgs[1] || !g_bEnable[client] || !g_fVolume[client] || sArgs[0] == '/' || sArgs[0] == '!' || BaseComm_IsClientGagged(client))
		return;
	
	static char szSound[PLATFORM_MAX_PATH];
	if(g_hSoundList.GetString(sArgs, szSound, PLATFORM_MAX_PATH))
	{
		if(!g_iAntiSpam_Time)
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
			if(iDeelay > g_iAntiSpam_Time)
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
					g_iSoundsDeelay[client] = GetTime();
					g_iSoundsDeelayGlobal = GetTime();
				}
				else CPrintToChat(client, "%T", "Global Already Played", client, g_iAntiSpam_GlobalTime - iDeelay);
			}
			else CPrintToChat(client, "%T", "Already Played", client, g_iAntiSpam_Time - iDeelay);
		}
	}
}
// ************************** Main Menu ***************************

Action Command_Sanky(int client, int args)
{
    if(!client || !IsClientInGame(client))
    {
    	return Plugin_Handled;
    }
    ShowCommand(client);

    return Plugin_Handled;
}

int ShowMainMenuHandler(Menu MainMenu, MenuAction action, int client, int param2)
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

int Handler_SankVolume(Menu menu, MenuAction action, int client, int param2)
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

int Handler_EntryVolume(Menu menu, MenuAction action, int client, int param2)
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

int Menu_SoundsList(Menu menu, MenuAction action, int client, int param2)
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

void sanky_options(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if(action == CookieMenuAction_SelectOption)
	{
		ShowCommand(client);
	}
}

void SaveClientOptions(int client)
{
	char sFormat[24];
	FormatEx(sFormat, sizeof(sFormat), "%.2f:%.2f:%d", g_fVolume[client], g_fEntryVolume[client], g_bHasEntryOn[client]);
	SetClientCookie(client, g_hCookie, sFormat);
}