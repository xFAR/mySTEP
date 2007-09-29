//
//  NSSystemServer.h
//  mySTEP / AppKit
//
//  Private interfaces used internally in AppKit implementation only
//  to communicate with a single, shared loginwindow process to provide
//  global services (e.g. list of all applications, inking etc.)
//
//  Created by Dr. H. Nikolaus Schaller on Thu Jan 05 2006.
//  Copyright (c) 2006 DSITRI. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSSound.h>
#import <AppKit/NSWorkspace.h>

@protocol _NSApplicationRemoteControlProtocol	// basic communication of workspace server with any application

- (BOOL) _application:(in NSApplication *) app openURLs:(in bycopy NSArray *) urls withOptions:(in bycopy NSWorkspaceLaunchOptions) opts;	// handle open
- (void) activate;
- (void) deactivate;
- (void) hide;
- (void) unhide;
- (void) echo;

@end

#define NSWorkspaceServerPort @"com.quantum-step.mySTEP.loginwindow"	// NSMessagePort to contact

@protocol _NSWorkspaceServerProtocol	// communication with distributed workspace server (which should be the loginwindow process)

/* application management */

- (bycopy NSArray *) launchedApplications;		// return info about all applications (array of NSDictionary)
- (bycopy NSDictionary *) activeApplication;	// return info about active application
- (oneway void) makeActiveApplication:(int) pid;			// make this the active application
- (oneway void) registerApplication:(int) pid
							   name:(bycopy NSString *) name		// name
							   path:(bycopy NSString *) path		// full path
							  NSApp:(byref NSApplication *) app;	// creates NSDistantObject to remotely access NSApp
- (oneway void) unRegisterApplication:(int) mypid;	// unregister (pid should be pid of sender!)
- (oneway void) hideApplicationsExcept:(int) mypid;	// send hide: to all other applications
- (oneway void) hideApplication:(in byref NSApplication *) app;		// hide specific application
- (oneway void) terminateApplication:(in byref NSApplication *) app;	// terminate specific application

	/* system menu */

- (oneway void) showShutdownDialog;
- (oneway void) showRestartDialog;
- (oneway void) showForceQuitDialog;	// show the force-quit dialog
- (oneway void) reallyLogout;			// immediately log out
- (oneway void) logout;					// request a logout
- (oneway void) shutdown;				// request a shutdown
- (oneway void) restart;				// request a restart
- (oneway void) sleep;					// request to sleep
- (oneway void) showAbout;				// show About panel
- (oneway void) showKillApplications;	// show Applications list panel

	/* system wide sound generator */

- (bycopy NSArray *) soundFileTypes;
- (oneway void) play:(byref NSSound *) sound;	// mix sound into currently playing sounds or schedule to end of queue
- (oneway void) pause:(byref NSSound *) sound;
- (oneway void) resume:(byref NSSound *) sound;
- (oneway void) stop:(byref NSSound *) sound;
- (BOOL) isPlaying:(byref NSSound *) sound;

	/* global window list / window levels */

- (int []) windowList;
- (int []) windowsAtLevel:(int) level;

	/* request&cancel user attention for a given application */

- (int) requestUserAttention:(NSRequestUserAttentionType) requestType forApplication:(byref NSApplication *) app;
- (oneway void) cancelUserAttentionRequest:(int) request;

	/* system wide inking service */

- (oneway void) startInkingForApplication:(byref NSApplication *) app atScreenPosition:(NSPoint) point;	// calls back [app postEvent:] with keyboard events

- (oneway void) enableASR:(BOOL) flag;	// enable automatic speech recognition
- (oneway void) enableOCR:(BOOL) flag;	// enable OCR
- (oneway void) enableVKBD:(BOOL) flag;	// enable virtual keyboard

@end

@interface NSWorkspace (NSWorkspaceServer)

+ (id <_NSWorkspaceServerProtocol>) _distributedWorkspace;	// get distributed object to contact loginwindow

@end