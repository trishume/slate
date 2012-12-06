//
//  SlateFileConfig.h
//  Slate
//
//  Created by Tristan Hume on 2012-12-05.
//
//

#import "SlateConfig.h"

@interface SlateFileConfig : SlateConfig

- (BOOL)append:(NSString *)configString;
- (NSString *)stripComments:(NSString *)line;
- (NSString *)replaceAliases:(NSString *)line;
@end
