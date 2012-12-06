//
//  SlateFileConfig.m
//  Slate
//
//  Created by Tristan Hume on 2012-12-05.
//
//

#import "SlateFileConfig.h"

#import "Binding.h"
#import "Constants.h"
#import "Layout.h"
#import "LayoutOperation.h"
#import "ScreenState.h"
#import "ScreenWrapper.h"
#import "StringTokenizer.h"
#import "Snapshot.h"
#import "SnapshotList.h"
#import "JSONKit.h"
#import "SlateLogger.h"
#import "NSFileManager+ApplicationSupport.h"
#import "NSString+Indicies.h"
#import "ActivateSnapshotOperation.h"

@implementation SlateFileConfig

- (void)loadConfigFile {
  if (![self loadConfigFileWithPath:@"~/.slate"]) {
    SlateLogger(@"  ERROR Could not load ~/.slate");
    NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Continue", @"Quit", nil]];
    [alert setMessageText:@"Could not load ~/.slate"];
    [alert setInformativeText:@"The default configuration will be used. You can find the default .slate file at https://github.com/jigish/slate/blob/master/Slate/default.slate"];
    if ([alert runModal] == NSAlertSecondButtonReturn) {
      SlateLogger(@"User selected exit");
      [NSApp terminate:nil];
    }
    [self loadConfigFileWithPath:[[NSBundle mainBundle] pathForResource:@"default" ofType:@"slate"]];
  }
}

- (BOOL)append:(NSString *)configString {
  if (configString == nil)
    return NO;
  NSArray *lines = [configString componentsSeparatedByString:@"\n"];
  
  NSEnumerator *e = [lines objectEnumerator];
  NSString *line = [e nextObject];
  while (line) {
    line = [self stripComments:line];
    if (line == nil || [line length] == 0) { line = [e nextObject]; continue; }
    @try {
      line = [self replaceAliases:line];
    } @catch (NSException *ex) {
      SlateLogger(@"   ERROR %@",[ex name]);
      NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
      [alert setMessageText:[ex name]];
      [alert setInformativeText:[ex reason]];
      if ([alert runModal] == NSAlertFirstButtonReturn) {
        SlateLogger(@"User selected exit");
        [NSApp terminate:nil];
      }
    }
    NSMutableArray *tokens = [[NSMutableArray alloc] initWithCapacity:10];
    [StringTokenizer tokenize:line into:tokens];
    if ([tokens count] >= 3 && [[tokens objectAtIndex:0] isEqualToString:CONFIG]) {
      // config <key>[:<app>] <value>
      SlateLogger(@"  LoadingC: %@",line);
      NSArray *splitKey = [[tokens objectAtIndex:1] componentsSeparatedByString:@":"];
      NSString *key = [splitKey count] > 1 ? [splitKey objectAtIndex:0] : [tokens objectAtIndex:1];
      if ([configs objectForKey:key] == nil) {
        SlateLogger(@"   ERROR Unrecognized config '%@'",[tokens objectAtIndex:1]);
        NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
        [alert setMessageText:[NSString stringWithFormat:@"Unrecognized Config '%@'",[tokens objectAtIndex:1]]];
        [alert setInformativeText:line];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
          SlateLogger(@"User selected exit");
          [NSApp terminate:nil];
        }
      } else {
        if ([splitKey count] > 1 && [[splitKey objectAtIndex:1] length] > 2) {
          NSString *appName = [[splitKey objectAtIndex:1] substringWithRange:NSMakeRange(1, [[splitKey objectAtIndex:1] length] - 2)];
          SlateLogger(@"    Found App Config for App: '%@' Key: %@", appName, key);
          NSMutableDictionary *configsForApp = [appConfigs objectForKey:appName];
          if (configsForApp == nil) { configsForApp = [NSMutableDictionary dictionary]; }
          [configsForApp setObject:[tokens objectAtIndex:2] forKey:key];
          [appConfigs setObject:configsForApp forKey:appName];
        } else {
          [configs setObject:[tokens objectAtIndex:2] forKey:[tokens objectAtIndex:1]];
        }
      }
    } else if ([tokens count] >= 3 && [[tokens objectAtIndex:0] isEqualToString:BIND]) {
      // bind <key:modifiers|modal-key> <op> <parameters>
      @try {
        SlateLogger(@"  LoadingB: %@",line);
        Binding *bind = [[Binding alloc] initWithString:line];
        if ([bind modalKey] != nil) {
          NSMutableArray *theBindings = [modalBindings objectForKey:[bind modalHashKey]];
          if (theBindings == nil) theBindings = [NSMutableArray array];
          [theBindings addObject:bind];
          [modalBindings setObject:theBindings forKey:[bind modalHashKey]];
        } else {
          [bindings addObject:bind];
        }
      } @catch (NSException *ex) {
        SlateLogger(@"   ERROR %@",[ex name]);
        NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
        [alert setMessageText:[ex name]];
        [alert setInformativeText:[ex reason]];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
          SlateLogger(@"User selected exit");
          [NSApp terminate:nil];
        }
      }
    } else if ([tokens count] >= 4 && [[tokens objectAtIndex:0] isEqualToString:LAYOUT]) {
      // layout <name> <app name> <op+params> (| <op+params>)*
      @try {
        if ([layouts objectForKey:[tokens objectAtIndex:1]] == nil) {
          Layout *layout = [[Layout alloc] initWithString:line];
          SlateLogger(@"  LoadingL: %@",line);
          [layouts setObject:layout forKey:[layout name]];
        } else {
          Layout *layout = [layouts objectForKey:[tokens objectAtIndex:1]];
          [layout addWithString:line];
          SlateLogger(@"  LoadingL: %@",line);
        }
      } @catch (NSException *ex) {
        SlateLogger(@"   ERROR %@",[ex name]);
        NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
        [alert setMessageText:[ex name]];
        [alert setInformativeText:[ex reason]];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
          SlateLogger(@"User selected exit");
          [NSApp terminate:nil];
        }
      }
    } else if ([tokens count] >= 3 && [[tokens objectAtIndex:0] isEqualToString:DEFAULT]) {
      // default <name> <screen-setup>
      @try {
        ScreenState *state = [[ScreenState alloc] initWithString:line];
        if (state == nil) {
          SlateLogger(@"   ERROR Loading default layout");
          NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
          [alert setMessageText:@"Error loading default layout"];
          [alert setInformativeText:line];
          if ([alert runModal] == NSAlertFirstButtonReturn) {
            SlateLogger(@"User selected exit");
            [NSApp terminate:nil];
          }
        } else {
          [defaultLayouts addObject:state];
          SlateLogger(@"  LoadingDL: %@",line);
        }
      } @catch (NSException *ex) {
        SlateLogger(@"   ERROR %@",[ex name]);
        NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
        [alert setMessageText:[ex name]];
        [alert setInformativeText:[ex reason]];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
          SlateLogger(@"User selected exit");
          [NSApp terminate:nil];
        }
      }
    } else if ([tokens count] >= 3 && [[tokens objectAtIndex:0] isEqualToString:ALIAS]) {
      // alias <name> <value>
      @try {
        [self addAlias:line];
        SlateLogger(@"  LoadingA: %@",line);
      } @catch (NSException *ex) {
        SlateLogger(@"   ERROR %@",[ex name]);
        NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
        [alert setMessageText:[ex name]];
        [alert setInformativeText:[ex reason]];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
          SlateLogger(@"User selected exit");
          [NSApp terminate:nil];
        }
      }
    } else if ([tokens count] >= 2 && [[tokens objectAtIndex:0] isEqualToString:SOURCE]) {
      // source filename optional:if_exists
      SlateLogger(@"  LoadingS: %@",line);
      if (![self loadConfigFileWithPath:[tokens objectAtIndex:1]]) {
        if ([tokens count] >= 3 && [[tokens objectAtIndex:2] isEqualToString:IF_EXISTS]) {
          SlateLogger(@"   Could not find file '%@' but that's ok. User specified if_exists.",[tokens objectAtIndex:1]);
        } else {
          SlateLogger(@"   ERROR Sourcing file '%@'",[tokens objectAtIndex:1]);
          NSAlert *alert = [SlateConfig warningAlertWithKeyEquivalents: [NSArray arrayWithObjects:@"Quit", @"Skip", nil]];
          [alert setMessageText:[NSString stringWithFormat:@"ERROR Sourcing file '%@'",[tokens objectAtIndex:1]]];
          [alert setInformativeText:@"I dunno. Figure it out."];
          if ([alert runModal] == NSAlertFirstButtonReturn) {
            SlateLogger(@"User selected exit");
            [NSApp terminate:nil];
          }
        }
      }
    }
    line = [e nextObject];
  }
  return YES;
}

- (NSString *)replaceAliases:(NSString *)line {
  NSArray *aliasNames = [aliases allKeys];
  for (NSInteger i = 0; i < [aliasNames count]; i++) {
    line = [line stringByReplacingOccurrencesOfString:[aliasNames objectAtIndex:i] withString:[aliases objectForKey:[aliasNames objectAtIndex:i]]];
  }
  if ([line rangeOfString:@"${"].length > 0) {
    @throw([NSException exceptionWithName:@"Unrecognized Alias" reason:[NSString stringWithFormat:@"Unrecognized alias in '%@'", line] userInfo:nil]);
  }
  return line;
}

- (NSString *)stripComments:(NSString *)line {
  if (line == nil) { return nil; }
  NSString *theLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:WHITESPACE]];
  if ([theLine length] == 0 || [theLine characterAtIndex:0] == COMMENT_CHARACTER) {
    return nil;
  }
  NSInteger idx = [theLine indexOfChar:COMMENT_CHARACTER];
  if (idx < 0) { return theLine; }
  return [[theLine substringToIndex:idx] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:WHITESPACE]];
}

@end
