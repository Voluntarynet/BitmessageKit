//
//  BMContacts.m
//  Bitmarket
//
//  Created by Steve Dekorte on 1/31/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "BMContacts.h"
#import "BMProxyMessage.h"

@implementation BMContacts

- (id)init
{
    self = [super init];
    self.nodeShouldSelectChildOnAdd = @YES;
    
    {
        NavActionSlot *slot = [self.navMirror newActionSlotWithName:@"add"];
        [slot setVisibleName:@"add"];
    }
    
    return self;
}

- (NSString *)nodeTitle
{
    return @"Contacts";
}

- (void)fetch
{
    [self setChildren:[self listAddressBookEntries]];
    [self sortChildren];
}


- (NSMutableArray *)listAddressBookEntries // contacts
{
    BMProxyMessage *message = [[BMProxyMessage alloc] init];
    [message setMethodName:@"listAddressBookEntries"];
    NSArray *params = [NSArray array];
    [message setParameters:params];
    [message sendSync];
    
    NSMutableArray *contacts = [NSMutableArray array];
    
    //NSLog(@"\n[message parsedResponseValue] = %@", [message parsedResponseValue]);
    
    NSArray *dicts = [[message parsedResponseValue] objectForKey:@"addresses"];
    
    
    for (NSDictionary *dict in dicts)
    {
        BMContact *contact = [BMContact withDict:dict];
        [contacts addObject:contact];
    }
    
    //NSLog(@"\n\n contacts = %@", contacts);
    
    return contacts;
}

- (BMContact *)justAdd
{
    BMContact *newContact = [[BMContact alloc] init];
    [newContact setLabel:@"Enter Name"];
    [newContact setAddress:@"Enter Bitmessage Address"];
    //[newContact insert];
    [self addChild:newContact];
    return newContact;
}

- (void)add
{
    [self justAdd];
    [self postSelfChanged];
}

@end
