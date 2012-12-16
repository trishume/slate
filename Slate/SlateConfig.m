//
//  SlateConfig.m
//  Slate
//
//  Created by Jigish Patel on 5/18/11.
//  Copyright 2011 Jigish Patel. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see http://www.gnu.org/licenses

#import "Binding.h"
#import "Constants.h"
#import "Layout.h"
#import "LayoutOperation.h"
#import "ScreenState.h"
#import "ScreenWrapper.h"
#import "SlateConfig.h"
#import "StringTokenizer.h"
#import "Snapshot.h"
#import "SnapshotList.h"
#import "JSONKit.h"
#import "SlateLogger.h"
#import "NSFileManager+ApplicationSupport.h"
#import "NSString+Indicies.h"
#import "ActivateSnapshotOperation.h"
#import "SlateFileConfig.h"

@implementation SlateConfig

@synthesize configs;
@synthesize configDefaults;
@synthesize bindings;
@synthesize modalBindings;
@synthesize layouts;
@synthesize defaultLayouts;
@synthesize aliases;
@synthesize snapshots;
@synthesize appConfigs;

static SlateConfig *_instance = nil;

+ (SlateConfig *)getInstance {
  @synchronized([SlateConfig class]) {
    if (!_instance) {
      [ScreenWrapper updateStatics];
      _instance = [[[SlateFileConfig class] alloc] init];
    }
    return _instance;
  }
}

- (id)init {
  self = [super init];
  if (self) {
    [self setupDefaultConfigs];
    [self setBindings:[NSMutableArray arrayWithCapacity:10]];
    [self setModalBindings:[NSMutableDictionary dictionary]];
    [self setLayouts:[NSMutableDictionary dictionary]];
    [self setDefaultLayouts:[NSMutableArray array]];
    [self setAliases:[NSMutableDictionary dictionary]];
    [self setSnapshots:[NSMutableDictionary dictionary]];

    // Listen for screen change notifications
    NSNotificationCenter *nc = [NSDistributedNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onScreenChange:) name:NOTIFICATION_SCREEN_CHANGE object:nil];
    [nc addObserver:self selector:@selector(onScreenChange:) name:NOTIFICATION_SCREEN_CHANGE_LION object:nil];
    //[nc addObserver:self selector:@selector(processNotification:) name:nil object:nil];
  }
  return self;
}

- (BOOL)getBoolConfig:(NSString *)key {
  return [[configs objectForKey:key] boolValue];
}

- (NSInteger)getIntegerConfig:(NSString *)key {
  return [[configs objectForKey:key] integerValue];
}

- (double)getDoubleConfig:(NSString *)key {
  return [[configs objectForKey:key] doubleValue];
}

- (float)getFloatConfig:(NSString *)key {
  return [[configs objectForKey:key] floatValue];
}

- (NSArray *)getArrayConfig:(NSString *)key {
  return [[configs objectForKey:key] componentsSeparatedByString:SEMICOLON];
}

- (NSString *)getConfig:(NSString *)key {
  return [configs objectForKey:key];
}

- (NSString *)getConfigDefault:(NSString *)key {
  return [configDefaults objectForKey:key];
}

- (NSString *)getConfig:(NSString *)key app:(NSString *)app {
  NSMutableDictionary *configsForApp = [appConfigs objectForKey:app];
  if (configsForApp == nil) return [self getConfigDefault:key];
  NSString *config = [configsForApp objectForKey:key];
  if (config == nil) return [self getConfigDefault:key];
  return config;
}

+ (NSAlert *)warningAlertWithKeyEquivalents:(NSArray *)titles {
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setAlertStyle:NSWarningAlertStyle];
  for (NSString *title in titles) {
    [[alert addButtonWithTitle:title] setKeyEquivalent:[[title substringToIndex: 1] lowercaseString]];
  }
  return alert;
}

- (BOOL)load {
  SlateLogger(@"Loading config...");

  // Reset configs and bindings in case we are calling from menu
  [self setupDefaultConfigs];
  [self setBindings:[[NSMutableArray alloc] initWithCapacity:10]];
  [self setLayouts:[[NSMutableDictionary alloc] init]];
  [self setDefaultLayouts:[[NSMutableArray alloc] init]];
  [self setAliases:[[NSMutableDictionary alloc] init]];

  [self loadConfigFile];

  if (![self loadSnapshots]) {
    SlateLogger(@"  ERROR Could not load %@", SNAPSHOTS_FILE);
    NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
    [alert setMessageText:[NSString stringWithFormat:@"ERROR Could not load %@", SNAPSHOTS_FILE]];
    [alert setInformativeText:[NSString stringWithFormat:@"I dunno. Figure it out. Maybe try deleting %@", SNAPSHOTS_FILE]];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
      SlateLogger(@"User selected exit");
      [NSApp terminate:nil];
    }
    return NO;
  }

  if ([[SlateConfig getInstance] getBoolConfig:CHECK_DEFAULTS_ON_LOAD]) {
    SlateLogger(@"Config loaded. Checking defaults...");
    [self checkDefaults];
    SlateLogger(@"Defaults loaded.");
  } else {
    SlateLogger(@"Config loaded.");
  }

  return YES;
}

// implemented by subclasses
// should load the file of the appropriate name
- (void)loadConfigFile {
  [self doesNotRecognizeSelector:_cmd];
}

- (BOOL)loadConfigFileWithPath:(NSString *)file {
  if (file == nil) return NO;
  NSString *configFile = file;
  if ([file rangeOfString:SLASH].location != 0 && [file rangeOfString:TILDA].location != 0)
    configFile = [NSString stringWithFormat:@"~/%@", file];
  NSString *fileString = [NSString stringWithContentsOfFile:[configFile stringByExpandingTildeInPath] encoding:NSUTF8StringEncoding error:nil];
  return [self append:fileString];
}

// This must be implemented in a subclass
- (BOOL)append:(NSString *)configString {
  [self doesNotRecognizeSelector:_cmd];
  return NO;
}

- (void)snapshotsFromDictionary:(NSDictionary *)snapshotsDict {
  NSArray *keys = [snapshotsDict allKeys];
  for (NSString *name in keys) {
    SnapshotList *list = [SnapshotList snapshotListFromDictionary:[snapshotsDict objectForKey:name]];
    [snapshots setObject:list forKey:[list name]];
  }
}

- (BOOL)loadSnapshots {
  NSString *fileString = [NSString stringWithContentsOfURL:[SlateConfig snapshotsFile] encoding:NSUTF8StringEncoding error:nil];
  if (fileString == nil || [fileString isEqualToString:EMPTY])
    return YES;
  id iShouldBeADictionary = [fileString objectFromJSONString];
  if (![iShouldBeADictionary isKindOfClass:[NSDictionary class]]) return NO;
  NSDictionary *snapshotsDict = iShouldBeADictionary;
  [self snapshotsFromDictionary:snapshotsDict];
  return YES;
}

- (void)addAlias:(NSString *)line {
  NSMutableArray *tokens = [[NSMutableArray alloc] initWithCapacity:10];
  [StringTokenizer tokenize:line into:tokens maxTokens:3];
  [aliases setObject:[tokens objectAtIndex:2] forKey:[NSString stringWithFormat:@"${%@}",[tokens objectAtIndex:1]]];
}

/*- (void)processNotification:(id)notification {
  SlateLogger(@"Notification: %@", notification);
  SlateLogger(@"Notification Name: <%@>", [notification name]);
}*/

- (void)activateLayoutOrSnapshot:(NSString *)name {
  if ([layouts objectForKey:name] != nil) {
    [LayoutOperation activateLayout:name];
  } else if ([snapshots objectForKey:name] != nil) {
    [ActivateSnapshotOperation activateSnapshot:name remove:NO];
  }
}

- (void)checkDefaults {
  ScreenWrapper *sw = [[ScreenWrapper alloc] init];
  NSInteger screenCount = [sw getScreenCount];
  NSMutableArray *resolutions = [[NSMutableArray alloc] initWithCapacity:10];
  [sw getScreenResolutionStrings:resolutions];
  [resolutions sortUsingSelector:@selector(compare:)];
  for (NSInteger i = 0; i < [defaultLayouts count]; i++) {
    ScreenState *state = [defaultLayouts objectAtIndex:i];
    // Check count
    if ([state type] == TYPE_COUNT && [state count] == screenCount) {
      SlateLogger(@"onScreenChange count found");
      [self activateLayoutOrSnapshot:[state layout]];
      break;
    }
    // Check resolutions
    if ([resolutions count] == [[state resolutions] count]) {
      SlateLogger(@"onScreenChange resolution counts equal. Check %@ vs %@",resolutions,[state resolutions]);
      BOOL isEqual = YES;
      for (NSInteger j = 0; j < [resolutions count]; j++) {
        if (![[resolutions objectAtIndex:j] isEqualToString:[[state resolutions] objectAtIndex:j]]) {
          isEqual = NO;
          break;
        }
      }
      if (isEqual) {
        SlateLogger(@"onScreenChange resolution found");
        [self activateLayoutOrSnapshot:[state layout]];
        break;
      }
    }
  }

}

- (void)onScreenChange:(id)notification {
  SlateLogger(@"onScreenChange");
  if (![ScreenWrapper hasScreenConfigChanged]) return;
  [self checkDefaults];
}

- (NSDictionary *)snapshotsToDictionary {
  NSMutableDictionary *snapshotDict = [NSMutableDictionary dictionary];
  NSArray *keys = [snapshots allKeys];
  for (NSString *name in keys) {
    SnapshotList *list = [snapshots objectForKey:name];
    if (![list saveToDisk]) continue;
    [snapshotDict setObject:[list toDictionary] forKey:name];
  }
  return snapshotDict;
}

- (void)saveSnapshots {
  // Build NSDictionary with snapshots
  NSDictionary *snapshotDict = [self snapshotsToDictionary];

  // Get NSData from NSDictionary
  NSData *jsonData = [snapshotDict JSONData];

  // Save NSData to file
  [jsonData writeToURL:[SlateConfig snapshotsFile] atomically:YES];
}

- (void)addSnapshot:(Snapshot *)snapshot name:(NSString *)name saveToDisk:(BOOL)saveToDisk isStack:(BOOL)isStack stackSize:(NSUInteger)stackSize {
  SnapshotList *list = [snapshots objectForKey:name];
  if (list == nil) {
    list = [[SnapshotList alloc] initWithName:name saveToDisk:saveToDisk isStack:isStack];
  } else {
    [list setName:name];
    [list setSaveToDisk:saveToDisk];
    [list setIsStack:isStack];
  }
  [list addSnapshot:snapshot];
  [snapshots setObject:list forKey:name];

  [self saveSnapshots];
}

- (void)deleteSnapshot:(NSString *)name pop:(BOOL)pop {
  if (pop) {
    SnapshotList *list = [snapshots objectForKey:name];
    if (list) {
      [list popSnapshot:YES];
    }
  } else {
    [snapshots removeObjectForKey:name];
  }

  [self saveSnapshots];
}

- (Snapshot *)popSnapshot:(NSString *)name remove:(BOOL)remove {
  SnapshotList *list = [snapshots objectForKey:name];
  Snapshot *snapshot = nil;
  if (list) {
    snapshot = [list popSnapshot:remove];
  }
  [self saveSnapshots];
  return snapshot;
}

- (void)setupDefaultConfigs {
  [self setConfigDefaults:[NSMutableDictionary dictionaryWithCapacity:10]];
  [configDefaults setObject:DEFAULT_TO_CURRENT_SCREEN_DEFAULT forKey:DEFAULT_TO_CURRENT_SCREEN];
  [configDefaults setObject:NUDGE_PERCENT_OF_DEFAULT forKey:NUDGE_PERCENT_OF];
  [configDefaults setObject:RESIZE_PERCENT_OF_DEFAULT forKey:RESIZE_PERCENT_OF];
  [configDefaults setObject:REPEAT_ON_HOLD_OPS_DEFAULT forKey:REPEAT_ON_HOLD_OPS];
  [configDefaults setObject:SECONDS_BEFORE_REPEAT_DEFAULT forKey:SECONDS_BEFORE_REPEAT];
  [configDefaults setObject:SECONDS_BETWEEN_REPEAT_DEFAULT forKey:SECONDS_BETWEEN_REPEAT];
  [configDefaults setObject:CHECK_DEFAULTS_ON_LOAD_DEFAULT forKey:CHECK_DEFAULTS_ON_LOAD];
  [configDefaults setObject:FOCUS_CHECK_WIDTH_DEFAULT forKey:FOCUS_CHECK_WIDTH];
  [configDefaults setObject:FOCUS_CHECK_WIDTH_MAX_DEFAULT forKey:FOCUS_CHECK_WIDTH_MAX];
  [configDefaults setObject:FOCUS_PREFER_SAME_APP_DEFAULT forKey:FOCUS_PREFER_SAME_APP];
  [configDefaults setObject:ORDER_SCREENS_LEFT_TO_RIGHT_DEFAULT forKey:ORDER_SCREENS_LEFT_TO_RIGHT];
  [configDefaults setObject:WINDOW_HINTS_BACKGROUND_COLOR_DEFAULT forKey:WINDOW_HINTS_BACKGROUND_COLOR];
  [configDefaults setObject:WINDOW_HINTS_FONT_COLOR_DEFAULT forKey:WINDOW_HINTS_FONT_COLOR];
  [configDefaults setObject:WINDOW_HINTS_FONT_NAME_DEFAULT forKey:WINDOW_HINTS_FONT_NAME];
  [configDefaults setObject:WINDOW_HINTS_FONT_SIZE_DEFAULT forKey:WINDOW_HINTS_FONT_SIZE];
  [configDefaults setObject:WINDOW_HINTS_HEIGHT_DEFAULT forKey:WINDOW_HINTS_HEIGHT];
  [configDefaults setObject:WINDOW_HINTS_WIDTH_DEFAULT forKey:WINDOW_HINTS_WIDTH];
  [configDefaults setObject:WINDOW_HINTS_DURATION_DEFAULT forKey:WINDOW_HINTS_DURATION];
  [configDefaults setObject:WINDOW_HINTS_ROUNDED_CORNER_SIZE_DEFAULT forKey:WINDOW_HINTS_ROUNDED_CORNER_SIZE];
  [configDefaults setObject:WINDOW_HINTS_IGNORE_HIDDEN_WINDOWS_DEFAULT forKey:WINDOW_HINTS_IGNORE_HIDDEN_WINDOWS];
  [configDefaults setObject:WINDOW_HINTS_TOP_LEFT_X_DEFAULT forKey:WINDOW_HINTS_TOP_LEFT_X];
  [configDefaults setObject:WINDOW_HINTS_TOP_LEFT_Y_DEFAULT forKey:WINDOW_HINTS_TOP_LEFT_Y];
  [configDefaults setObject:WINDOW_HINTS_ORDER_DEFAULT forKey:WINDOW_HINTS_ORDER];
  [configDefaults setObject:WINDOW_HINTS_SHOW_ICONS_DEFAULT forKey:WINDOW_HINTS_SHOW_ICONS];
  [configDefaults setObject:WINDOW_HINTS_ICON_ALPHA_DEFAULT forKey:WINDOW_HINTS_ICON_ALPHA];
  [configDefaults setObject:WINDOW_HINTS_SPREAD_DEFAULT forKey:WINDOW_HINTS_SPREAD];
  [configDefaults setObject:WINDOW_HINTS_SPREAD_SEARCH_WIDTH_DEFAULT forKey:WINDOW_HINTS_SPREAD_SEARCH_WIDTH];
  [configDefaults setObject:WINDOW_HINTS_SPREAD_SEARCH_HEIGHT_DEFAULT forKey:WINDOW_HINTS_SPREAD_SEARCH_HEIGHT];
  [configDefaults setObject:WINDOW_HINTS_SPREAD_PADDING_DEFAULT forKey:WINDOW_HINTS_SPREAD_PADDING];
  [configDefaults setObject:SWITCH_ICON_SIZE_DEFAULT forKey:SWITCH_ICON_SIZE];
  [configDefaults setObject:SWITCH_ICON_PADDING_DEFAULT forKey:SWITCH_ICON_PADDING];
  [configDefaults setObject:SWITCH_BACKGROUND_COLOR_DEFAULT forKey:SWITCH_BACKGROUND_COLOR];
  [configDefaults setObject:SWITCH_SELECTED_BACKGROUND_COLOR_DEFAULT forKey:SWITCH_SELECTED_BACKGROUND_COLOR];
  [configDefaults setObject:SWITCH_SELECTED_BORDER_COLOR_DEFAULT forKey:SWITCH_SELECTED_BORDER_COLOR];
  [configDefaults setObject:SWITCH_SELECTED_BORDER_SIZE_DEFAULT forKey:SWITCH_SELECTED_BORDER_SIZE];
  [configDefaults setObject:SWITCH_ROUNDED_CORNER_SIZE_DEFAULT forKey:SWITCH_ROUNDED_CORNER_SIZE];
  [configDefaults setObject:SWITCH_ORIENTATION_DEFAULT forKey:SWITCH_ORIENTATION];
  [configDefaults setObject:SWITCH_SECONDS_BETWEEN_REPEAT_DEFAULT forKey:SWITCH_SECONDS_BETWEEN_REPEAT];
  [configDefaults setObject:SWITCH_SECONDS_BEFORE_REPEAT_DEFAULT forKey:SWITCH_SECONDS_BEFORE_REPEAT];
  [configDefaults setObject:SWITCH_STOP_REPEAT_AT_EDGE_DEFAULT forKey:SWITCH_STOP_REPEAT_AT_EDGE];
  [configDefaults setObject:SWITCH_ONLY_FOCUS_MAIN_WINDOW_DEFAULT forKey:SWITCH_ONLY_FOCUS_MAIN_WINDOW];
  [configDefaults setObject:SWITCH_FONT_COLOR_DEFAULT forKey:SWITCH_FONT_COLOR];
  [configDefaults setObject:SWITCH_FONT_SIZE_DEFAULT forKey:SWITCH_FONT_SIZE];
  [configDefaults setObject:SWITCH_FONT_NAME_DEFAULT forKey:SWITCH_FONT_NAME];
  [configDefaults setObject:SWITCH_SHOW_TITLES_DEFAULT forKey:SWITCH_SHOW_TITLES];
  [configDefaults setObject:SWITCH_TYPE_DEFAULT forKey:SWITCH_TYPE];
  [configDefaults setObject:SWITCH_SELECTED_PADDING_DEFAULT forKey:SWITCH_SELECTED_PADDING];
  [configDefaults setObject:KEYBOARD_LAYOUT_DEFAULT forKey:KEYBOARD_LAYOUT];
  [configDefaults setObject:SNAPSHOT_TITLE_MATCH_DEFAULT forKey:SNAPSHOT_TITLE_MATCH];
  [configDefaults setObject:GRID_BACKGROUND_COLOR_DEFAULT forKey:GRID_BACKGROUND_COLOR];
  [configDefaults setObject:GRID_ROUNDED_CORNER_SIZE_DEFAULT forKey:GRID_ROUNDED_CORNER_SIZE];
  [configDefaults setObject:GRID_CELL_BACKGROUND_COLOR_DEFAULT forKey:GRID_CELL_BACKGROUND_COLOR];
  [configDefaults setObject:GRID_CELL_SELECTED_COLOR_DEFAULT forKey:GRID_CELL_SELECTED_COLOR];
  [configDefaults setObject:GRID_CELL_ROUNDED_CORNER_SIZE_DEFAULT forKey:GRID_CELL_ROUNDED_CORNER_SIZE];
  [configDefaults setObject:LAYOUT_FOCUS_ON_ACTIVATE_DEFAULT forKey:LAYOUT_FOCUS_ON_ACTIVATE];
  [configDefaults setObject:SNAPSHOT_MAX_STACK_SIZE_DEFAULT forKey:SNAPSHOT_MAX_STACK_SIZE];
  [configDefaults setObject:UNDO_MAX_STACK_SIZE_DEFAULT forKey:UNDO_MAX_STACK_SIZE];
  [configDefaults setObject:UNDO_OPS_DEFAULT forKey:UNDO_OPS];
  [self setConfigs:[NSMutableDictionary dictionary]];
  [self setAppConfigs:[NSMutableDictionary dictionary]];
  [configs setValuesForKeysWithDictionary:configDefaults];
}

+ (NSURL *)snapshotsFile {
  NSFileManager *sharedFM = [NSFileManager defaultManager];
  NSURL *appSupportDir = [sharedFM applicationSupportDirectory];
  NSURL *snapshotsFile = nil;
  if (appSupportDir) {
    snapshotsFile = [appSupportDir URLByAppendingPathComponent:SNAPSHOTS_FILE];
  }
  NSLog(@"TEST ------------- %@", [snapshotsFile absoluteString]);
  return snapshotsFile;
}

@end
