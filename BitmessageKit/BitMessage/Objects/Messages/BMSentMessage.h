//
//  BMSentMessage.h
//  Bitmessage
//
//  Created by Steve Dekorte on 2/19/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "BMMessage.h"

@interface BMSentMessage : BMMessage

- (BOOL)notFound;
- (BOOL)wasSent;
- (NSString *)getStatus;
- (NSString *)getHumanReadbleStatus;

@end
