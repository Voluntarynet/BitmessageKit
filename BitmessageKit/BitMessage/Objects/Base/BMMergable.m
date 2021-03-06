//
//  BMMergable.m
//  BitmessageKit
//
//  Created by Steve Dekorte on 8/15/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "BMMergable.h"

@implementation BMMergable


- (SEL)mergeAttributeSelector
{
    return nil;
}

- (void)prepareToMergeChildren
{
    self.mergingChildren = [NSMutableArray array];
}

- (BOOL)shouldMergeChild:(BMMessage *)aMessage
{
    SEL mergeAttributeSelector = self.mergeAttributeSelector;
    
    if (mergeAttributeSelector)
    {
        NSString *attribute = [aMessage idNoWarningPerformSelector:mergeAttributeSelector];
        
        if ([attribute isEqualToString:self.address])
        {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)mergeChild:(BMMessage *)aMessage
{
    if ([self shouldMergeChild:aMessage])
    {
        [self.mergingChildren addObject:aMessage];
        return YES;
    }
    
    return NO;
}

- (void)completeMergeChildren
{
    [self.children mergeWith:self.mergingChildren];
    [self setChildren:self.children]; // so node parents set
    [self sortChildren];
    [self updateUnreadCount];
    [self postSelfChanged];
    self.mergingChildren = nil;
}

- (void)deleteAllChildren
{
    for (BMMessage *msg in self.children.copy)
    {
        [msg delete];
    }
    
    [self postParentChanged];
}

@end
