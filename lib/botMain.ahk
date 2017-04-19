﻿#NoEnv
SendMode Input

__Log("------------- idolBot by Hachifac -------------")
__Log("------- Crusaders of The Lost Idols bot -------")

FileCreateDir, logs
FileCreateDir, settings
FileCreateDir, stats

Gosub, _BotLoadSettings

Gosub, _BotSetHotkeys

statsChestsThisRun = 0
statsChestsThisSession = 0
statsIdolsThisSession = 0

Gosub, _BotLoadStats

; Include the lists
#include lib/listCrusaders.ahk
#include lib/listKeys.ahk
#include lib/listCampaigns.ahk

; Include the GUIs
#include lib/guiMain.ahk

CoordMode, Pixel, Client
CoordMode, Mouse, Client

lastProgressCheck = 0

SetTimer, _GUIPos, 100 ; Every 100ms we position the GUI below the game
SetTimer, _BotScanForChests, 1000

botLookingForCursor := false ; Quite important little bool, set to true when the _BotGetCurrentLevel timer occurs, it pauses the loot items phase because threads gets messy
botLevelCursorCoords := [1, 2, 3, 4, 5]
botLevelCursorCoords[1] := [744, 10, 781, 127]
botLevelCursorCoords[2] := [788, 10, 825, 127]
botLevelCursorCoords[3] := [832, 10, 869, 127]
botLevelCursorCoords[4] := [872, 10, 909, 127]
botLevelCursorCoords[5] := [912, 10, 949, 127]
botLevelCurrentCursor = 0
botLevelPreviousCursor = 0
botCurrentLevel = 0

rightKeyInterrupt := false

SetTimer, _BotGetCurrentLevel, 2000
SetTimer, _BotNextLevel, 100

botPhase = -1 ; -1 = bot not launched, 0 = bot in campaign selection screen, 1 = initial stuff like looking for overlays, waiting for the game to fully load, 2 = maxing the levels/ main dps and upgrades, 3 = reset phase
botRunLaunchTime := __UnixTime(A_Now)
botLaunchTime := __UnixTime(A_Now)
botSession = 0

now = 0
botRelaunching = false

botMaxAllCount = 0

botSkipToReset := false
optLastoptChatRoom := optChatRoom

global currentCIndex := [1, 1]
global currentCCoords := [36, 506]
global crusaderPixels := Object()
global crusaderPixelsTemp := Object()
global levelCapPixels := Object()

; Bot loop
idolBot:
	FileGetSize, Output, logs/logs.txt, M
	if (Output >= 10) {
		FileMove, logs/logs.txt, logs/logs_old.txt
		FileDelete, logs/logs.txt
	}
	IfWinExist, Crusaders of The Lost Idols
	{
		WinActivate, Crusaders of The Lost Idols
		if (optMoveGameWindow > 0) {
			Gosub, _BotMoveGame
		}
		; Self-explanatory
		if (botPhase = -1) {
			__GUIShowPause(true)
			Loop {
				if (botPhase = 0) {
					Break
				}
			}
		}
		; Campaign selection, the bot will either start a campaign or realize one is already started
		if (botPhase = 0) {
			__Log("Launching bot.")
			Gosub, _BotCampaignStart
			botPhase = 1
		}
		; Campaign selected/game screen loaded/game running
		if (botPhase > 0) {
			__Log("Bot launched.")
			; We look for overlays throughout phase 1 & 2
			Loop {
				WinActivate, Crusaders of The Lost Idols
				if (botPhase = 1 or botPhase = 2) {
					Gosub, _BotCloseWindows
				}
				if (botPhase = 1) {
					botRelaunching = false
					MouseMove, 550, 50
					__Log("Waiting for the campaign to load.")
					; We look at the left arrow in the crusaders bar, if it's there it means the screen is fully loaded
					PixelGetColor, Output, 15, 585, RGB
					if (Output = 0xA07107 or Output = 0xFFB103) {
						__Log("Campaign loaded.")
						; Press space bar to close the events/sales tabs
						Send, {Space}
						; If the left arrow is gold, it means we're not at the beginning of the characters bar, we're moving back until we detect the gold color
						if (Output != 0xA07107) {
							__Log("Moving the characters bar to the beginning.")
							__BotMoveToFirstPage()
						}
						; Open options window to see if auto progress is on
						__Log("Initial auto progress check...")
						if (optResetType = 2 or optAutoProgressCheck = 1) {
							_BotSetAutoProgress(true)
						} else {
							_BotSetAutoProgress(false)
						}
						Loop {
							; We look at Jim's buy button to know if we can select the formation
							PixelGetColor, Output, 244, 595, RGB
							; If it's not green, we first look if the right arrow is gold, if it is it means the game already started long ago and Jim is probably maxed, meaning we need to put the formation in right now
							; then we click the monsters until we get some cash to initiate the formation
							; If it's green, in a few seconds the bot will max all levels and some crusaders will get in formation, eventually the formation set will kick in
							__Log("Looking for Jim's status.")
							if (Output != 0x45D402) {
								; Auto click until Jim lvl up button turns green
								MouseMove, 695, 325
								Click
								Sleep, 40
								MouseMove, 750, 325
								Click
								Sleep, 40
							} else {
								Break
							}
						}
						; We look at Jim's buy button one last time, if it's green we're good to go to phase 2
						PixelGetColor, Output, 244, 595, RGB
						if (Output = 0x45D402 or Output = 0x226A01) {
							botPhase = 2
						}
						Send, {%optFormationKey%}
						; Set Chat Room to optChatRoom
						if (optChatRoom > 0 and botSession = 0) {
							__Log("Setting chat room to " . optChatRoom . ".")
							Gosub, _BotSetChatRoom
						}
					} else {
						Sleep, 1000
					}
				}
				; Sometimes we get a server failed error, shit happens. We search for it and if it pops up, we relaunch the game.
				ImageSearch, OutputX, OutputY, 0, 0, 997, 671, *100 images/game/serverfailed.png
				if (ErrorLevel = 0) {
					__Log("Server failed error. Relaunching the game.")
					Gosub, _BotRelaunch
				}
				; Upgrade all/max all/max main dps. Final phase until reset phase.
				if (botPhase = 2 or botDelayReset = true) {
					if (botSession = 0) {
						botSession = 1
					}
					if (optLastoptChatRoom != optChatRoom and optChatRoom > 0) {
						Gosub, _BotSetChatRoom
					}
					; Max all levels
					__BotMaxLevels()
					botMaxAllCount++
					; If the bot did optUpgAllUntil max all levels, do one buy all upgrades
					if (botMaxAllCount >= optUpgAllUntil) {
						__BotUpgAll()
						botMaxAllCount = 0
					}
					__Log("Get the gold and quest items for " . optLootItemsDuration . " seconds.")
					now = % __UnixTime(A_Now)
					if (optClicking = 1) {
						delay := optClickDelay
					} else {
						delay = 20
					}
					SendEvent {Click 660, 320, 0}
					SetDefaultMouseSpeed, 2
					while (__UnixTime(A_Now) - now <= optLootItemsDuration) {
						if (botSkipToReset = true) {
							Break
						}
						SendEvent {Click 910, 320, 0}
						SendEvent {Click 660, 320, 0}
						if (optClicking = 1) {
							click
						}
						Sleep, %delay%
					}
					SetDefaultMouseSpeed, 0
					if (optResetType = 1 or optResetType = 2 or optResetType = 5 or optResetType = 6) {
						
					}
					; If the last time we did an auto progress check is >= than autoProgressCheckDelay, we initiate an auto progress check
					if ((optResetType = 2 or optAutoProgressCheck = 1) and __UnixTime(A_Now) - lastProgressCheck >= optAutoProgressCheckDelay) {
						; Every autoProgressCheckDelay seconds we take a look if Auto Progress is still activated, if it's not it means we died so achieved the highest zone we could, we have to reset
						lastProgressCheck = % __UnixTime(A_Now)
						Log("Auto progress check for max progress.")
						if (__BotCheckAutoProgress() = false) {
							if (__UnixTime(A_Now) - botRunLaunchTime < 60) {
								; Stuck at beginning, might be the formation not active
								Log("Might be stuck at the beginning.")
								send, {%optFormationKey%}
								Sleep, 100
								Send, {g}
							} else {
								botPhase = 3
							}
						}
					}
					if (optResetType = 3) {
						if (levelCapResetCheck = true) {
							__BotMoveToLastPage()
							Sleep, 500
							PixelGetColor, Output, 872, 594, RGB
							if (Output = 0x7D2E0C) {
								PixelGetColor, Output, 872, 508, RGB
								if (Output = 0x979797) {
									__Log("Level cap reached.")
									botPhase = 3
									botSkipToReset := true
								}
							} else if (Output = 0x979797) {
								__Log("Level cap reached.")
								botPhase = 3
								botSkipToReset := true
							}
						} else {
							__BotMoveToFirstPage()
							PixelGetColor, Output, 242, 508, RGB
							if (Output = 0x979797) {
								__Log("Bush is maxed.")
								levelCapResetCheck := true
							}
						}
					}
					if (optResetType = 6) {
						if (botCurrentLevel >= optResetOnLevel) {
							__Log("Level " . optResetOnLevel . " reached.")
							botSkipToReset := true
							botPhase = 3
						}
					}
					if (botSkipToReset = false) {
						if (optStormRiderMagnify = 0) {
							__BotUseSkill(0)
						} else {
							PixelSearch, OutputX, OutputY, 382, 449, 421, 488, 0x0000FE,, Fast
							if (ErrorLevel != 0) {
								PixelSearch, OutputX, OutputY, 582, 449, 621, 488, 0x0000FE,, Fast
								if (ErrorLevel != 0) {
									Send, {%optStormRiderFormationKey%}
									Sleep, 1000
									__BotMaxLevels()
									__BotUpgAll()
									Sleep, 3000
									Send, {%optStormRiderFormationKey%}
									Sleep, 3000
									PixelGetColor, Output, 390, 466, RGB
									if (Output != 0x3A3A3A) {
										PixelGetColor, Output, 590, 466, RGB
										if (Output != 0x3A3A3A) {
											Send, 2
											Sleep, 25
											Send, 7
											Sleep, 25
										}
									}
								}
							}
							__BotUseSkill(1)
							__BotUseSkill(3)
							__BotUseSkill(4)
							__BotUseSkill(5)
							__BotUseSkill(6)
							__BotUseSkill(8)
						}
					}
				}
				; If optRunTime time elapsed or phase is set at 3, we reset
				if (((optResetType = 5 and __UnixTime(A_Now) - botRunLaunchTime >= (optRunTime * 60)) or botPhase = 3) and optResetType > 1) {
					botDelayReset := false
					resetPhase = 0
					__Log("Cannot progress further, time to reset.")
					MouseMove, 985, 630
					Click
					Sleep, 500
					; Move to reset crusader
					if (resetPhase = 0) {
						resetAttempt = 0
						Loop {
							Click
							__Log("Moving to reset crusader.")
							__BotMoveToFirstPage()
							Sleep, 500
							__BotMoveToCrusader("nate")
							Sleep, 2000
							; Get pixel color on optResetCrusader skills to know where the reset button is
							__Log("Searching for that reset skill.")
							ImageSearch, resetOutputX, resetOutputY, 657, 631, 869, 665, *100 images/game/nateReset.png
							if (ErrorLevel = 0) {
								resetPhase = 1
							} else {
								ImageSearch, resetOutputX, resetOutputY, 657, 631, 869, 665, *100 images/game/rudolphReset.png
								if (ErrorLevel = 0) {
									resetPhase = 1
								} else {
									ImageSearch, resetOutputX, resetOutputY, 657, 631, 869, 665, *100 images/game/kizReset.png
									if (ErrorLevel = 0) {
										resetPhase = 1
									} else {
										botDelayReset := true
										botSkipToReset := false
										Break
									}
								}
							}
							if (resetPhase = 1) {
								__Log("Found. Reset inbound.")
								Break
							}
						}
					}
					if (resetPhase = 1) {
						Loop {
							MouseMove, resetOutputX + 3, resetOutputY + 3
							Sleep, 25
							Click
							Sleep, 1000
							__Log("Reset warning window.")
							ImageSearch, OutputX, OutputY, 281, 116, 717, 235, *150 images/game/resetwarning.png
							if (ErrorLevel = 0) {
								__Log("Reset warning window found.")
								resetPhase = 2
								Break
							}
						}
					}
					if (resetPhase = 2) {
						resetPhase = 3
						Loop {
							; Reset button
							MouseMove, 407, 516
							Sleep, 500
							Click
							Sleep, 500
							; Big red button
							__Log("Searching for the big red button.")
							ImageSearch, OutputX, OutputY, 439, 479, 671, 601, *150 images/game/redbutton.png
							if (ErrorLevel = 0) {
								__Log("Clicking the red button.")
								MouseMove, 509, 546
								Sleep, 500
								Click
								Sleep, 500
							}
							; Idols screen
							__Log("Waiting for the idols screen.")
							ImageSearch, OutputX, OutputY, 439, 479, 671, 601, *100 images/game/idolscontinue.png
							if (ErrorLevel = 0) {
								__Log("Calculating the idols.")
								idolsCount := __BotGetIdolsCount()
								FileAppend, % __UnixTime(A_Now) . ":" . idolsCount, stats/idols.txt
								statsIdolsPastDay := 0
								Loop, read, stats/idols.txt
								{
									break := StrSplit(A_LoopReadLine, ":")
									if (__UnixTime(A_Now) - break[1] <= 86400) {
										FileAppend, % break[1] . ":" . break[2] . "`n", stats/idols_temp.txt
										statsIdolsPastDay := statsIdolsPastDay + break[2]
									}
								}
								FileDelete, stats/idols.txt
								FileMove, stats/idols_temp.txt, stats/idols.txt
								
								IniRead, statsIdolsAllTime, stats/stats.txt, Idols, alltime, 0
								statsIdolsAllTime += idolsCount
								statsIdolsThisSession += idolsCount
								
								optRunTime := __UnixTime(A_Now) - botRunLaunchTime
								
								IniWrite, % statsIdolsAllTime, stats/stats.txt, Idols, alltime
								IniWrite, % statsIdolsPastDay, stats/stats.txt, Idols, pastday
								IniWrite, % idolsCount, stats/stats.txt, Idols, lastrun
								IniWrite, % optRunTime, stats/stats.txt, Idols, lastruntime
								
								IniWrite, % statsChestsThisRun, stats/stats.txt, Chests, lastrun
								IniWrite, % optRunTime, stats/stats.txt, Chests, lastruntime
								statsChestsThisRun = 0
								
								botLevelCurrentCursor = 0
								botLevelPreviousCursor = 0
								botCurrentLevel = 0
								
								MouseMove, 507, 550
								Sleep, 500
								Click
								Sleep, 500
								Break
							}
						}
					}
					if (resetPhase = 3) {
						__Log("Start a new campaign.")
						Gosub, _BotCampaignStart
						Sleep, 100
						botPhase = 1
					}
				}
			}
		}
	}
	IfWinNotExist, Crusaders of The Lost Idols
	{
		__Log("Game not found.")
	}
	Return

; Set the GUI below the game
_GUIPos:
	IfWinExist, Crusaders of The Lost Idols
	{
		WinGetPos, X, Y, W, H, Crusaders of The Lost Idols
		if (X != oldX or Y != oldY) {
			oldX := X
			oldY := Y
			nY := A_ScreenHeight - (A_ScreenHeight - Y) + H - 2
			nW := W
			nX := X + W / 2 - 225 / 2 + 2
			Gui, BotGUI: Show, x%nX% y%nY% w227 h35 NoActivate, BotGUI
		}
	}
	IfWinNotExist, Crusaders of The Lost Idols
	{
		if (botRelaunching = false) {
			Pause,, 1
			__GUIShowPause(1)
			__Log("[GUI] Game not found.")
		}
	}
	Return

; Pause key
_BotPause:
	CoordMode, Pixel, Client
	CoordMode, Mouse, Client
	if (botPhase = -1) {
		botPhase = 0
		__GUIShowPause(false)
	} else {
		Pause,, 1
		if (botPhase = 2 and !A_IsPaused) {
			rightKeyInterrupt := true
			if (optPromptCurrentLevel = 1 and optResetType = 6) {
				Gosub, _GUICurrentLevel
			}
			rightKeyInterrupt := false
		}
	}
	if (botPhase >= 0) {
		if (A_IsPaused) {
			__Log("Paused.")
			__GUIShowPause(true)
		} else {
			__Log("Unpaused.")
			__GUIShowPause(false)
			if ((botPhase = 1 or botPhase = 2) and optResetType != 2 and optAutoProgressCheck = 0) {
				Gosub, _BotCloseWindows
				_BotSetAutoProgress(false)
			}
		}
	}
	WinActivate, Crusaders of The Lost Idols
	Return

_BotSetHotkeys:
	if (optPauseHotkey2) {
		optPauseHotkey = %optPauseHotkey1% & %optPauseHotkey2%
	} else {
		optPauseHotkey := optPauseHotkey1
	}
	Hotkey, %optPauseHotkey%, _BotPause
	if (optReloadHotkey2) {
		optReloadHotkey = %optReloadHotkey1% & %optReloadHotkey2%
	} else {
		optReloadHotkey := optReloadHotkey1
	}
	Hotkey, %optReloadHotkey%, _BotReload
	if (optExitHotkey2) {
		optExitHotkey = %optExitHotkey1% & %optExitHotkey2%
	} else {
		optExitHotkey := optExitHotkey1
	}
	Hotkey, %optExitHotkey%, _BotExit
	Return
	
; Self-explanatory
__GUIShowPause(status) {
	if (status = false) {
		GuiControl, BotGUI:, BotStatus, images/gui/running.png
	} else {
		GuiControl, BotGUI:, BotStatus, images/gui/paused.png
	}
	Return
}

_BotCloseWindows:
	PixelGetColor, Output, 15, 585, RGB
	if (Output = 0x503803) {
		__Log("Found an overlay.")
		ImageSearch, OutputX, OutputY, 0, 0, 997, 671, *100 images/game/close.png
		if (ErrorLevel = 0) {
			__Log("Overlay closed.")
			MouseMove, OutputX + 10, OutputY + 10
			Sleep, 100
			Click
		}
	}
	Return

; Relaunch the game, pretty much self-explanatory
_BotRelaunch:
	__Log("Closing the game.")
	botRelaunching = true;
	WinClose, Crusaders of The Lost Idols
	__Log("Waiting on the game to close.")
	WinWaitClose, Crusaders of The Lost Idols,,180
	Loop {
		Process, Exist, Crusaders of the Lost Idols.exe
		if (ErrorLevel > 0) {
			Process, Close, ErrorLevel
		} else {
			Break
		}
		Sleep, 500
	}
	__Log("Game closed. Relaunching.")
	Run, steam://Rungameid/402840,,UseErrorLevel
	__Log("Waiting on the game to launch.")
	WinWait, Crusaders of The Lost Idols,,300
	botRelaunching = false
	WinActivate, Crusaders of The Lost Idols
	WinMove, Crusaders of The Lost Idols,,15,15
	seen = 0
	__Log("Searching for start button.")
	Loop {
		ImageSearch, OutputX, OutputY, 358, 512, 640, 560, *150 images/game/start.png
		if (ErrorLevel = 0) {
			seen = 1
			MouseMove, 498, 540
			Sleep, 500
			Click
		} else {
			if (seen = 1) {
				botPhase = 1
				Break
			}
		}
		Sleep, 1000
	}
	Return

_BotMoveGame:
	WinGetPos,,, OutputW, OutputH
	SysGet, OutputX, 76
	SysGet, OutputX2, 78
	SysGet, OutputY, MonitorWorkArea, 1
	centerX := (A_ScreenWidth - OutputW) / 2
	centerY := (OutputYBottom - OutputH) / 2
	if (optMoveGameWindow = 2) {
		WinMove, OutputX, centerY
	} else if (optMoveGameWindow = 3) {
		WinMove, OutputX, OutputYTop
	} else if (optMoveGameWindow = 4) {
		WinMove, centerX, OutputYTop
	} else if (optMoveGameWindow = 5) {
		WinMove, OutputX2 + OutputX - OutputW, OutputYTop
	} else if (optMoveGameWindow = 6) {
		WinMove, OutputX2 + OutputX - OutputW, centerY
	} else if (optMoveGameWindow = 7) {
		WinMove, centerX, centerY
	}
	Return
	
; Campaign screen, well at least triggered when we think it's the campaign screen or we just did a reset
_BotCampaignStart:
	__Log("Searching for campaign header.")
	Loop {
		; If the campaign.png is found (which is the big campaign text at the top of the screen), we know for sure that's where we are
		; If not found, we look for the cog (settings button), we're instead still/already in the game
		ImageSearch, OutputX, OutputY, 257, 57, 428, 110, *150 images/game/campaign.png
		if (ErrorLevel = 0) {
			__Log("Found the campaign header.")
			__BotSetCampaign(optCampaign)
			botRunLaunchTime = % __UnixTime(A_Now)
			botMaxAllCount = 0
			botSkipToReset := false
			if (botPhase = 1 and optRelaunchGame = 1) {
				__Log("Relaunching CoTLI.")
				Gosub, _BotRelaunch
			}
			Break
		} else {
			__Log("Searching for the cog.")
			ImageSearch, OutputX, OutputY, 298, 90, 340, 130, *150 images/game/cog.png
			if (ErrorLevel = 0) {
				__Log("Found the cog.")
				Break
			} else {
				__Log("Didn't find the cog, looking for left arrow instead.")
				PixelGetColor, Output, 15, 585, RGB
				if (Output = 0x503803) {
					Break
				} else {
					__Log("Left arrow not found, looking for the Start button.")
					ImageSearch, OutputX, OutputY, 358, 512, 640, 560, *150 images/game/start.png
					if (ErrorLevel = 0) {
						MouseMove, 498, 540
						Sleep, 500
						Click
					}
				}
			}
		}
	}
	Return

; Browse the campaign screen to find the desired one, will scan up and down until the proper campaign image is found
; Once the campaign is found, we set the objective by calling the function __BotSetObjective
__BotSetCampaign(c) {
	Global listCampaigns
	__Log("Setting the campaign.")
	if (c = 1) {
		MouseMove, 535, 195
		Sleep, 500
		Click
		__Log("Starting the event campaign.")
		Return
	} else {
		MouseMove, 585, 165
		Loop, 10 {
			Click
			Sleep, 25
		}
		__Log("Setting the campaign.")
		fpX = 540
		__Log("Determining if an event is going on.")
		ImageSearch, wwX, wwY, 34, 153, 175, 263, *150 images/game/ww.png
		if (ErrorLevel = 0) {
			__Log("No event is going on.")
			down = 1
			fpY = 2
		} else {
			__Log("An event is going on.")
			down = 3
			fpY = 4
		}
		MouseMove, 585, 605
		Loop, % listCampaigns[c][down] {
			Click
			Sleep, 100
		}
		Sleep, 500
		MouseMove, fpX, listCampaigns[c][fpY]
		Click
		Sleep, 100
		MouseMove, 785, 570
		Sleep, 25
		Click
	}
}

; Navigate the crusaders bar to find the desired crusader
; c = crusader
__BotMoveToCrusader(c) {
	global currentCCoords
	global crusaders
	currentCIndex[2] := crusaders[c][2]
	nX := crusaders[c][1] - currentCIndex[1]
	pagesToMove := 0
	if (currentCIndex[1] < crusaders[c][1]) {
		currentCIndex[1] := crusaders[c][1]
		if (nX > 2) {
			pagesToMove := nX - 2
			currentCIndex[1] -= 2
		} else {
			currentCIndex[1] -= nX
		}
	} else {
		currentCIndex[1] := crusaders[c][1]
		pagesToMove := nX
	}
	if (pagesToMove != 0) {
		__BotMoveToPage(pagesToMove)
	}
	currentCCoords[1] := 37 + 315 * (nX - pagesToMove)
	currentCCoords[2] := 506 + 86 * (currentCIndex[2] - 1)
	Return
}

__BotMoveToFirstPage() {
	currentCIndex := [1, 1]
	Loop {
		PixelGetColor, Output, 15, 585, RGB
		if (Output = 0xA07107) {
			Break
		}
		MouseMove, 15, 585
		Click
		Sleep, 50
	}
	Return
}

__BotMoveToLastPage() {
	Loop {
		PixelGetColor, Output, 985, 585, RGB
		if (Output = 0xA07107) {
			Break
		}
		MouseMove, 985, 585
		Click
		Sleep, 50
	}
	Return
}

__BotMoveToPage(p) {
	if (p > 0) {
		aX = 985
		d = 1
	} else {
		aX = 15
		p *= -1
		d = 0
	}
	Loop, %p% {
		MouseMove, aX, 585
		PixelGetColor, Output, aX, 585, RGB
		if (Output != 0x000000) {
			Click
		}
		Sleep, 200
	}
	Return
}

__BotSetCrusadersPixels() {
	Sleep, 1000
	initialX = 42
	i = 0
	j = 0
	Loop, 24 {
		if (A_Index = 9 or A_Index = 17) {
			j++
			i = 0
		}
		i++
		PixelGetColor, Output, initialX + (i - 1) * 4, 506 + j * 2, RGB
		crusaderPixels[A_Index] := Output
	}
	Return
}

__BotCompareCrusadersPixels() {
	initialX = 42
	i = 0
	j = 0
	Loop, 24 {
		if (A_Index = 9 or A_Index = 17) {
			j++
			i = 0
		}
		i++
		PixelGetColor, Output, initialX + (i - 1) * 4, 506 + j * 2, RGB
		crusaderPixelsTemp[A_Index] := Output
	}
	j = 0
	for i, e in crusaderPixelsTemp {
		if (crusaderPixels[i] = crusaderPixelsTemp[i]) {
			j++
		}
	}
	if (j = crusaderPixels.MaxIndex()) {
		Return, true
	}
	Return, false
}

; Max levels
__BotMaxLevels() {
	global optFormationKey
	global optResetType
	global botPhase
	__Log("Max all levels.")
	MouseMove, 985, 630
	Click
	Sleep, 100
	i = 0
	Loop {
		PixelGetColor, Output, 985, 610, RGB
		if (Output != 0x226501) {
			Break
		}
		Sleep, 10
	}
	Send, {%optFormationKey%}
	Return
}

; Upgrade all
__BotUpgAll() {
	__Log("Buy all upgrades.")
	MouseMove, 985, 540
	Click
	Sleep, 100
	Loop {
		PixelGetColor, Output, 985, 515, RGB
		if (Output != 0x194D80) {
			Break
		}
		Sleep, 10
	}
	Return
}

; Use a skill, 0 to use all skills
__BotUseSkill(s) {
	if (s = 0) {
		Loop, 8 {
			Send, %A_Index%
			Sleep, 25
		}
	} else {
		Send, %s%
	}
	Return
}

; Sets the auto progress to false
_BotSetAutoProgress(s) {
	__Log("Auto progress check at startup")
	Global lastProgressCheck
	lastProgressCheck = % __UnixTime(A_Now)
	if (__BotCheckAutoProgress() != s) {
		Send, {g}
	}
	Return
}

; Check if the auto progress is set to true or false
__BotCheckAutoProgress() {
	Loop {
		MouseMove, 317, 111
		Sleep, 100
		Click
		Sleep, 500
		ImageSearch, OutputX2, OutputY2, 417, 203, 543, 242, *150 images/game/options.png
		Sleep, 500
		; If the big options header is found, it means the options window is open
		if (ErrorLevel = 0) {
			c = 0
			; Here I use a loop because I've had lots of trouble with AHK giving me the wrong color, so now the bot loops until it finds the proper color
			; (will get stuck here infinitely until the color is found, this seriously can take a few seconds)
			Loop {
				PixelGetColor, Output, 212, 337, RGB
				if (Output = 0xE8CDC5) {
					Break
				} else {
					if (Output = 0x742814 or Output = 0xF7EDEA) {
						c++
						Break
					}
				}
			}
			ImageSearch, OutputX, OutputY, 712, 177, 758, 219, *150 images/game/close.png
			Loop {
				ImageSearch, OutputX, OutputY, 712, 177, 758, 219, *150 images/game/close.png
				if (ErrorLevel = 0) {
					MouseMove, OutputX + 10, OutputY + 10
					Click
					Sleep, 50
					Break
				}
			}
			if (c = 0) {
				Break
			} else {
				__Log("Auto progress check returned false.")
				Return, false
			}
		}
	}
	__Log("Auto progress check returned true.")
	Return, true
}

_BotSetChatRoom:
	MouseMove, 1135, 10
	Sleep, 100
	Click
	if (optChatRoom > 10) {
		optChatRoom = 10
	}
	MouseMove, 1135, 18 + (21 * optChatRoom)
	Sleep, 100
	Click
	optLastoptChatRoom := optChatRoom
	Return

__BotGetIdolsCount() {
	Loop {
		ImageSearch, lastX, lastY, 415, 205, 720, 285, *100 images/game/iplus.png
		if (ErrorLevel = 0) {
			idols := null
			lastX += 15
			Loop, 9 {
				i := 0
				Loop, 10 {
					WinActivate, Crusaders of The Lost Idols
					ImageSearch, OutputX, OutputY, lastX, lastY - 5, lastX + 20, lastY + 23, *100 images/game/i%i%.png
					if (ErrorLevel = 0) {
						idols := idols . i
						lastX := OutputX + 8
						Break
					}
					i++
				}
				if (ErrorLevel = 1) {
					Break
				}
			}
		}
		__Log("Idols: " . idols)
		Return, idols
	}
}

_BotGetCurrentLevel:
	if (botPhase = 2) {
		botLookingForCursor := true
		CoordMode, Pixel, Client
		CoordMode, Mouse, Client
		i = 1
		Loop {
			PixelGetColor, Output, 308, 104, RGB
			if (Output != 0x290F07) {
				if (i > 5) {
					i = 1
				}
				ImageSearch, OutputX, OutputY, botLevelCursorCoords[i][1], botLevelCursorCoords[i][2], botLevelCursorCoords[i][3], botLevelCursorCoords[i][4], *25 images/game/lArrow.png
				if (ErrorLevel = 0) {
					if (botLevelCurrentCursor = 0) {
						botLevelPreviousCursor := i
						botCurrentLevel := i
					}
					botLevelCurrentCursor := i
					botLookingForCursor := false
					Break
				} else {
					i++
				}
				Sleep, 25
			} else {
				Break
			}
		}
		if (botLevelCurrentCursor > botLevelPreviousCursor) {
			if (botLevelCurrentCursor = 5 and botLevelPreviousCursor = 1) {
				botCurrentLevel--
				botLevelPreviousCursor = 5
			} else {
				if (botLevelCurrentCursor - botLevelPreviousCursor > 1) { ; Lost count
					__Log("Lost level count... Reset might not occur.")
					botLevelPreviousCursor := botLevelCurrentCursor
				} else {
					botCurrentLevel++
					botLevelPreviousCursor++
				}
			}
		} else if (botLevelCurrentCursor < botLevelPreviousCursor) {
			if (botLevelCurrentCursor = 1 and botLevelPreviousCursor = 5) {
				botCurrentLevel++
				botLevelPreviousCursor = 1
			} else {
				if (botLevelPreviousCursor - botLevelCurrentCursor > 1) { ; Lost count
					__Log("Lost level count... Reset might not occur.")
					botLevelPreviousCursor := botLevelCurrentCursor
				} else {
					botCurrentLevel--
					botLevelPreviousCursor := botLevelCurrentCursor
				}
			}
		}
	}
	Return

_BotNextLevel:
	if (botPhase = 2 and rightKeyInterrupt = false) {
		Send, {Right}
	}
	Return
	
_BotScanForChests:
	ImageSearch, OutputX, OutputY, 742, 12, 956, 138, *75 images/game/chest1.png
	if (ErrorLevel = 0) {
		FileAppend, % __UnixTime(A_Now) . ":S", stats/chests.txt
		chestsPastDay = 0
		Loop, read, stats/chests.txt
		{
			break := StrSplit(A_LoopReadLine, ":")
			if (__UnixTime(A_Now) - break[1] <= 86400) {
				FileAppend, % break[1] . ":" . break[2] . "`n", stats/chests_temp.txt
				chestsPastDay++
			}
		}
		statsChestsThisRun++
		statsChestsThisSession++
		FileDelete, stats/chests.txt
		FileMove, stats/chests_temp.txt, stats/chests.txt
		IniRead, chestsAllTime, stats/stats.txt, Chests, alltime, 0
		chestsAllTime += 1
		IniWrite, % chestsAllTime, stats/stats.txt, Chests, alltime
		IniWrite, % chestsPastDay, stats/stats.txt, Chests, pastday
		IniWrite, % statsChestsThisRun, stats/stats.txt, Chests, thisrun
		IniWrite, % statsChestsThisSession, stats/stats.txt, Chests, thissession
		Sleep, 9000
	}
	Return

; __Log function
__Log(__Log) {
	FormatTime, TimeOutput, A_Now, yyyy/M/d - HH:mm:ss
	FileAppend, [%TimeOutput%] %__Log%`n, logs/logs.txt
	Return
}

; Transforms YYYYMMDDHH24MISS date format to Unix
__UnixTime(Time) {
	Result := Time
	Result -= 19700101000000, Seconds
	Return, Result
}

; Rounds a number (n) to d decimals
__RoundNumber(n, d) {
	Transform, n, Round, n, d
	e := StrSplit(n, ".")
	if (e[2] != null) {
		e[2] := SubStr(e[2], 1, d)
		n := e[1] . "." . e[2]
	}
	Return, n
}

; Self-explanatory
_BotLoadSettings:
	__Log("Reading settings.")
	IniRead, optCampaign, settings/settings.ini, Settings, campaign, 2
	IniRead, optFormation, settings/settings.ini, Settings, formation, 1
	IniRead, optMainDPS, settings/settings.ini, Settings, maindps, Jim
	IniRead, optClicking, settings/settings.ini, Settings, clicking, 0
	IniRead, optResetType, settings/settings.ini, Settings, resettype, 2
	IniRead, optUpgAllUntil, settings/settings.ini, Settings, upgalluntil, 5
	IniRead, optMainDPSDelay, settings/settings.ini, Settings, maindpsdelay, 60
	IniRead, optChatRoom, settings/settings.ini, Settings, chatroom, 0
	IniRead, optClickDelay, settings/settings.ini, Settings, clickdelay, 20
	IniRead, optRunTime, settings/settings.ini, Settings, runtime, 60
	IniRead, optResetOnLevel, settings/settings.ini, Settings, resetonlevel, 100
	IniRead, optRelaunchGame, settings/settings.ini, Settings, relaunchgame, 0
	IniRead, optMoveGameWindow, settings/settings.ini, Settings, movegamewindow, 1
	IniRead, optAutoProgressCheck, settings/settings.ini, Settings, autoprogresscheck, 0
	IniRead, optAutoProgressCheckDelay, settings/settings.ini, Settings, autoprogresscheckdelay, 120
	IniRead, optPromptCurrentLevel, settings/settings.ini, Settings, promptcurrentlevel, 120
	IniRead, optLootItemsDuration, settings/settings.ini, Settings, lootitemsduration, 30
	IniRead, optStormRiderFormation, settings/settings.ini, Settings, stormriderformation, 0
	IniRead, optStormRiderMagnify, settings/settings.ini, Settings, stormridermagnify, 1
	IniRead, optPauseHotkey1, settings/settings.ini, Settings, pausehotkey1, F8
	IniRead, optPauseHotkey2, settings/settings.ini, Settings, pausehotkey2, %A_Space%
	IniRead, optReloadHotkey1, settings/settings.ini, Settings, reloadhotkey1, F9
	IniRead, optReloadHotkey2, settings/settings.ini, Settings, reloadhotkey2, %A_Space%
	IniRead, optExitHotkey1, settings/settings.ini, Settings, exithotkey1, F10
	IniRead, optExitHotkey2, settings/settings.ini, Settings, exithotkey2, %A_Space%
	IniRead, optCalcIdolsCount, settings/settings.ini, Settings, calcidolscount, 1
	if (optFormation = 1) {
		optFormationKey = q
	}
	if (optFormation = 2) {
		optFormationKey = w
	}
	if (optFormation = 3) {
		optFormationKey = e
	}
	if (optStormRiderFormation = 1) {
		optStormRiderFormationKey = q
	}
	if (optStormRiderFormation = 2) {
		optStormRiderFormationKey = w
	}
	if (optStormRiderFormation = 3) {
		optStormRiderFormationKey = e
	}
	if (optStormRiderFormation = 0) {
		optStormRiderFormationKey = optFormationKey
	}
	StringLower, optMainDPS, optMainDPS
	StringLower, optResetCrusader, optResetCrusader
	optTempCampaign := optCampaign
	optTempFormation := optFormation
	optTempFormationKey := optFormationKey
	optTempMainDPS := optMainDPS
	optTempResetType := optResetType
	optTempClicking := optClicking
	optTempUpgAllUntil := optUpgAllUntil
	optTempMainDPSDelay := optMainDPSDelay
	optTempChatRoom := optChatRoom
	optTempClickDelay := optClickDelay
	optTempRunTime := optRunTime
	optTempResetOnLevel := optResetOnLevel
	optTempRelaunchGame := optRelaunchGame
	optTempMoveGameWindow := optMoveGameWindow
	optTempAutoProgressCheck := optAutoProgressCheck
	optTempAutoProgressCheckDelay := optAutoProgressCheckDelay
	optTempPromptCurrentLevel := optPromptCurrentLevel
	optTempStormRiderFormation := optStormRiderFormation
	optTempStormRiderFormationKey := optStormRiderFormationKey
	optTempStormRiderMagnify := optStormRiderMagnify
	optTempPauseHotkey1 := optPauseHotkey1
	optTempPauseHotkey2 := optPauseHotkey2
	optTempReloadHotkey1 := optReloadHotkey1
	optTempReloadHotkey2 := optReloadHotkey2
	optTempExitHotkey1 := optExitHotkey1
	optTempExitHotkey2 := optExitHotkey2
	Return

; Self-explanatory
_BotRewriteSettings:
	__Log("Settings changed.")
	StringLower, optMainDPS, optMainDPS
	StringLower, optResetCrusader, optResetCrusader
	IniWrite, % optCampaign, settings/settings.ini, Settings, campaign
	IniWrite, % optFormation, settings/settings.ini, Settings, formation
	IniWrite, % optMainDPS, settings/settings.ini, Settings, maindps
	IniWrite, % optClicking, settings/settings.ini, Settings, clicking
	IniWrite, % optResetType, settings/settings.ini, Settings, resettype
	IniWrite, % optUpgAllUntil, settings/settings.ini, Settings, upgalluntil
	IniWrite, % optMainDPSDelay, settings/settings.ini, Settings, maindpsdelay
	IniWrite, % optChatRoom, settings/settings.ini, Settings, chatroom
	IniWrite, % optClickDelay, settings/settings.ini, Settings, clickdelay
	IniWrite, % optRunTime, settings/settings.ini, Settings, runtime
	IniWrite, % optResetOnLevel, settings/settings.ini, Settings, resetonlevel
	IniWrite, % optRelaunchGame, settings/settings.ini, Settings, relaunchgame
	IniWrite, % optMoveGameWindow, settings/settings.ini, Settings, movegamewindow
	IniWrite, % optLootItemsDuration, settings/settings.ini, Settings, lootitemsduration
	IniWrite, % optAutoProgressCheck, settings/settings.ini, Settings, autoprogresscheck
	IniWrite, % optAutoProgressCheckDelay, settings/settings.ini, Settings, autoprogresscheckdelay
	IniWrite, % optPromptCurrentLevel, settings/settings.ini, Settings, promptcurrentlevel
	IniWrite, % optStormRiderFormation, settings/settings.ini, Settings, stormriderformation
	IniWrite, % optStormRiderMagnify, settings/settings.ini, Settings, stormridermagnify
	IniWrite, % optPauseHotkey1, settings/settings.ini, Settings, pausehotkey1
	IniWrite, % optPauseHotkey2, settings/settings.ini, Settings, pausehotkey2
	IniWrite, % optReloadHotkey1, settings/settings.ini, Settings, reloadhotkey1
	IniWrite, % optReloadHotkey2, settings/settings.ini, Settings, reloadhotkey2
	IniWrite, % optExitHotkey1, settings/settings.ini, Settings, exithotkey1
	IniWrite, % optExitHotkey2, settings/settings.ini, Settings, exithotkey2
	Return
	
_BotLoadStats:
	__Log("Reading stats.")
	IniRead, statsIdolsAllTime, stats/stats.txt, Idols, alltime, 0
	IniRead, statsIdolsPastDay, stats/stats.txt, Idols, pastday, 0
	IniRead, statsIdolsLastRun, stats/stats.txt, Idols, lastrun, 0
	IniRead, statsIdolsLastRunTime, stats/stats.txt, Idols, runtime, 0
	IniRead, statsChestsAllTime, stats/stats.txt, Chests, alltime, 0
	IniRead, statsChestsPastDay, stats/stats.txt, Chests, pastday, 0
	IniRead, statsChestsLastRun, stats/stats.txt, Chests, lastrun, 0
	IniRead, statsChestsLastRunTime, stats/stats.txt, Chests, runtime, 0
	Return
	
#include lib/guiLabels.ahk