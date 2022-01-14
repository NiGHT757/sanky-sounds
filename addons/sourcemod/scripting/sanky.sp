#include <sourcemod>
#include <emitsoundany>
#include <clientprefs>
#include <basecomm>
#include <vip_core>
#include <multicolors>

#pragma semicolon 1;
#pragma newdecls required;

// ************************** Author & Description ***************************

public Plugin myinfo =
{
	name = "Sanky Sounds",
	author = "xSLOW, edited by .NiGHT",
	description = "Play chat sounds",
	version = "2.1",
	url = "https://steamcommunity.com/profiles/76561193897443537"
};

// ************************** Variables ***************************
ConVar  g_CvAntiSpam_Time,
        g_cvAntiSpam_GlobalTime;

StringMap g_hSoundList;
StringMap g_hEntryList;
StringMap g_hEntryChances;

int g_iAntiSpam_Time,
	g_iAntiSpam_GlobalTime,
	g_iSoundsDeelayGlobal,
    g_iSoundsDeelay[MAXPLAYERS + 1];

Menu g_hMenu;

Handle g_hCookie = null;

bool    g_bHasEntry[MAXPLAYERS + 1] = false,
		g_bHasEntryOn[MAXPLAYERS+1] = {true, ...},
		g_bEnable[MAXPLAYERS + 1] = false,
		g_bEnabled = false,
		g_bLateLoaded = false;

float g_fVolume[MAXPLAYERS+1] = 1.0, g_fEntryVolume[MAXPLAYERS+1] = 1.0;

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
	g_CvAntiSpam_Time.AddChangeHook(OnSettingsChanged);
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
	if(convar == g_CvAntiSpam_Time)
	{
		g_iAntiSpam_Time = convar.IntValue;
	}
	else if(convar == g_cvAntiSpam_GlobalTime)
	{
		g_iAntiSpam_GlobalTime = convar.IntValue;
	}
}

public void OnConfigsExecuted()
{
	g_iAntiSpam_Time = g_CvAntiSpam_Time.IntValue;
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
	VIP_RegisterFeature(g_sFeature, BOOL, _, OnToggleItem);
}

public Action OnToggleItem(int iClient, const char[] sFeatureName, VIP_ToggleState OldStatus, VIP_ToggleState &NewStatus)
{
	g_bEnable[iClient] = (NewStatus == ENABLED);
	return Plugin_Continue;
}

public void VIP_OnVIPClientLoaded(int iClient)
{
	g_bEnable[iClient] = VIP_IsClientFeatureUse(iClient, g_sFeature);
}

// enable/disable
public void Disable(Event event, const char[] name, bool db)
{
	g_bEnabled = false;
}

public void Enable(Event event, const char[] name, bool db)
{
	g_bEnabled = true;

	if(!g_iAntiSpam_Time)
	{
		for(int iClient = 0; iClient <= MaxClients; iClient++)
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
	if(!g_hEntryList.Size || !client || IsFakeClient(client))
	{
		return;
	}

	g_bEnable[client] = false;
	static char sAuthID[128];
	GetClientAuthId(client, AuthId_Steam2, sAuthID, 128);

	int iValue;
	if(g_hEntryChances.GetValue(sAuthID, iValue))
	{
		if(g_bHasEntryOn[client] && iValue >= GetRandomInt(0, 100))
		{
			g_hEntryList.GetString(sAuthID, sAuthID, 128);
			DataPack pack = new DataPack();
			pack.WriteCell(GetClientUserId(client));
			pack.WriteString(sAuthID);
			CreateTimer(4.0, Timer_LoadEntry, pack, TIMER_FLAG_NO_MAPCHANGE);
		}
		g_bHasEntry[client] = true;
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
	if(FileExists("addons/sourcemod/configs/SankSounds.cfg"))
	{
		KeyValues kv = new KeyValues("Settings");

		if(!kv.ImportFromFile("addons/sourcemod/configs/SankSounds.cfg"))
		{
			SetFailState("Unable to parse key values");
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

		g_hMenu = new Menu(Menu_SoundsList);

		char SoundPath[PLATFORM_MAX_PATH], SoundName[128], SoundDownload[PLATFORM_MAX_PATH];
		char ExplodedString[12][64];
		int ExplodeCounter;
		do
		{
			kv.GetSectionName(SoundName, sizeof(SoundName));
			kv.GetString("file", SoundPath, sizeof(SoundPath));
			if(StrContains(SoundName, "|", false))
			{
				ExplodeCounter = ExplodeString(SoundName, "|", ExplodedString, sizeof(ExplodedString), sizeof(ExplodedString[]));

				for(int i = 0; i < ExplodeCounter; i++)
				{
					FormatEx(SoundDownload, 128, "sound/%s", SoundPath);
					if(FileExists(SoundDownload))
					{
						g_hSoundList.SetString(ExplodedString[i], SoundPath);
					}
				}
			}
			else{
				FormatEx(SoundDownload, 128, "sound/%s", SoundPath);
				if(FileExists(SoundDownload))
				{
					g_hSoundList.SetString(SoundName, SoundPath);
				}
			}
			if(FileExists(SoundDownload))
			{
				g_hSoundList.SetString(SoundName, SoundPath);
				g_hMenu.AddItem(SoundPath, SoundName);
				AddFileToDownloadsTable(SoundDownload);
				PrecacheSound(SoundPath);
			}
			else LogError("Missing sank sound file: %s", SoundPath);
		} while (kv.GotoNextKey());
		kv.Rewind();

		g_hMenu.SetTitle("%t", "Sounds List SubMenuText", g_hSoundList.Size);
		g_hMenu.ExitBackButton = true;

		if(kv.JumpToKey("EntrySounds") && kv.GotoFirstSubKey())
		{
			do
			{
				kv.GetString("sound", SoundPath, sizeof(SoundPath));
				kv.GetSectionName(SoundName, sizeof(SoundName));
				g_hEntryChances.SetValue(SoundName, kv.GetNum("chance", 100)); // steamid + entry chance
				g_hEntryList.SetString(SoundName, SoundPath); // steamid + soundpath
				// precache & download
				FormatEx(SoundDownload, 128, "sound/%s", SoundPath);
				if(FileExists(SoundDownload))
				{
					AddFileToDownloadsTable(SoundDownload);
					PrecacheSound(SoundPath);
				}
				else LogError("Missing sank sound file: %s", SoundPath);
			}while(kv.GotoNextKey());
		}
		delete kv;
	}
	else SetFailState("Config files not found. Check if config files are missing.");
}

public Action cmd_sankvol(int client, int args)
{
	if(!client || !IsClientInGame(client))
		return Plugin_Handled;

	if(args != 1)
	{
		CPrintToChat(client, "%t", "Volume Error");
		return Plugin_Handled;
	}
	char arg1[6];
	GetCmdArg(1, arg1, sizeof(arg1));
	float volume;
	volume = StringToFloat(arg1);
	if(volume > 1.0 || volume < 0.0)
	{
		CPrintToChat(client, "%t", "Volume Error");
		return Plugin_Handled;
	}
	g_fVolume[client] = StringToFloat(arg1);
	SaveClientOptions(client);
	CPrintToChat(client, "%t", "Option Saved", g_fVolume[client]);
	return Plugin_Handled;
}

public Action cmd_entryvol(int client, int args)
{
	if(!client || !IsClientInGame(client))
		return Plugin_Handled;

	if(args != 1)
	{
		CPrintToChat(client, "%t", "Volume Error");
		return Plugin_Handled;
	}
	char arg1[6];
	GetCmdArg(1, arg1, sizeof(arg1));
	float volume;
	volume = StringToFloat(arg1);
	if(volume > 1.0 || volume < 0.0)
	{
		CPrintToChat(client, "%t", "Volume Error");
		return Plugin_Handled;
	}
	g_fEntryVolume[client] = StringToFloat(arg1);
	CPrintToChat(client, "%t", "Option Saved", g_fEntryVolume[client]);
	SaveClientOptions(client);
	return Plugin_Handled;
}

public Action Timer_LoadEntry(Handle timer, DataPack pack)
{
	char sSound[PLATFORM_MAX_PATH];
	int client;

	pack.Reset();

	client = GetClientOfUserId(pack.ReadCell());
	pack.ReadString(sSound, sizeof(sSound));

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
		{
			continue;
		}
		if(g_bEnabled)
			EmitSoundToClient(i, sSound, SOUND_FROM_PLAYER, SNDCHAN_STATIC, SNDLEVEL_NONE, _, g_fEntryVolume[i]);
		switch(GetRandomInt(1,3))
		{
			case 1:
			{
				PrintToChat(i, "*\x04 *************************");
				PrintToChat(i, "*\x04 P0RNST4R\x05  %N\x04  JOINED", client);
			}
			case 2:
			{
				PrintToChat(i, "*\x09 *************************");
				PrintToChat(i, "*\x09 M0NST3R\x05  %N\x09  JOINED", client);
			}
			case 3:
			{
				PrintToChat(i, "*\x02 *************************");
				PrintToChat(i, "*\x02 BOSS\x05  %N\x02  JOINED", client);
			}
		}
	}
	delete pack;
}
// ************************** OnClientSayCommand_Post ***************************

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if(!client || !g_bEnabled || !IsClientInGame(client) || !g_bEnable[client] || g_fVolume[client] == 0.0 || BaseComm_IsClientGagged(client))
		return;

	if(!sArgs[2] || sArgs[0] == '/' || sArgs[0] == '!')
		return;
	
	static char szSound[PLATFORM_MAX_PATH];
	if(g_hSoundList.GetString(sArgs, szSound, 192))
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
				else CPrintToChat(client, "%t", "Global Already Played", g_iAntiSpam_GlobalTime - iDeelay);
			}
			else CPrintToChat(client, "%t", "Round Already Played");
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
				else CPrintToChat(client, "%t", "Global Already Played", g_iAntiSpam_GlobalTime - iDeelay);
			}
			else CPrintToChat(client, "%t", "Already Played", g_iAntiSpam_Time - iDeelay);
		}
	}
}
// ************************** Main Menu ***************************

public Action Command_Sanky(int client, int args)
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
					menu.SetTitle("%t", "Sanky Sounds SubMenuTitle", g_fVolume[client]);

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
					menu.SetTitle("%t", "Entry Sounds SubMenuTitle", g_fEntryVolume[client]);

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
					CPrintToChat(client, "%t", "Entry Sounds OptionSaved", g_bHasEntryOn[client] ? "\x04ENABLED":"\x02DISABLED");
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
}

void ShowCommand(int client)
{
	char sFormat[32];
	Menu MainMenu = new Menu(ShowMainMenuHandler);
	MainMenu.SetTitle("%t", "Sanky Sounds MainMenuTitle");
	FormatEx(sFormat, sizeof(sFormat), "%t", "Sanky Sounds SubMenuVolume", g_fVolume[client]);
	MainMenu.AddItem("", sFormat);
	FormatEx(sFormat, sizeof(sFormat), "%t", "Entry Sounds SubMenuVolume", g_fEntryVolume[client]);
	MainMenu.AddItem("", sFormat);
	FormatEx(sFormat, sizeof(sFormat), "%t", "Entry Sounds OptionSaved", g_bHasEntryOn[client] ? "ENABLED" : "DISABLED");
	MainMenu.AddItem("", sFormat, g_bHasEntry[client] ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	FormatEx(sFormat, sizeof(sFormat), "%t", "Sound List MainMenuText");
	MainMenu.AddItem("", sFormat, g_bEnable[client] ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	MainMenu.ExitBackButton = true;
	MainMenu.Display(client, 15);
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
			CPrintToChat(client, "%t", "Option Saved", g_fVolume[client]);
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
			CPrintToChat(client, "%t", "Option Saved", g_fEntryVolume[client]);
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
}

public void sanky_options(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
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