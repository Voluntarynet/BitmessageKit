//
//  BMClient.m
//  Bitmarket
//
//  Created by Steve Dekorte on 1/31/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "BMClient.h"
#import "BMAddressed.h"
#import "BMAboutNode.h"
//#import "BMArchive.h"

@implementation BMClient

static BMClient *sharedBMClient;

+ (BMClient *)sharedBMClient
{
    if (!sharedBMClient)
    {
        sharedBMClient = [BMClient alloc];
        sharedBMClient = [sharedBMClient init];
    }
    
    return sharedBMClient;
}

- (id)init
{
    self = [super init];
    self.refreshInterval = 14;
    [self startServer];
    
    self.nodeShouldSortChildren = @NO;
    
    self.identities    = [[BMIdentities alloc] init];
    self.contacts      = [[BMContacts alloc] init];
    self.messages      = [[BMMessages alloc] init];
    self.subscriptions = [[BMSubscriptions alloc] init];
    self.channels      = [[BMChannels alloc] init];
    
    [self addChild:self.messages.received];
    [self addChild:self.messages.sent];
    [self addChild:self.contacts];
    [self addChild:self.identities];
    [self addChild:self.channels];
    [self addChild:self.subscriptions];

    self.readMessagesDB = [[BMDatabase alloc] init];
    [self.readMessagesDB setName:@"readMessagesDB"];
    
    self.deletedMessagesDB = [[BMDatabase alloc] init];
    [self.deletedMessagesDB setName:@"deletedMessagesDB"];
    
    self.sentMessagesDB = [[BMDatabase alloc] init];
    [self.sentMessagesDB setName:@"sentMessagesDB"];
    
    self.deletedSentMessagesDB = [[BMDatabase alloc] init];
    [self.sentMessagesDB setName:@"deletedSentMessagesDB"];
    

    // fetch these addresses first so we can filter messages
    // when we fetch them
    
    [self.identities fetch];
    [self.channels fetch];
    [self.subscriptions fetch];
    
    [self deepFetch];

    [self registerForNotifications];
    [self.messages.received changedUnreadCount];
    
    self.nodeAbout = [[BMAboutNode alloc] init];
    return self;
}

- (void)registerForNotifications
{
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(stopServer)
                                               name:NSApplicationWillTerminateNotification
                                             object:nil];
    
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(unreadCountChanged:)
                                               name:@"BMReceivedMessagesUnreadCountChanged"
                                             object:self.messages.received];
}

- (void)unreadCountChanged:(NSNotification *)aNote
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setObject:@(self.messages.received.unreadCount) forKey:@"number"];
    
    [NSNotificationCenter.defaultCenter
        postNotificationName:@"NavDocTileUpdate"
        object:self
        userInfo:aNote.userInfo];
}

- (NSNumber *)nodeSuggestedWidth
{
    return @150.0;
}

- (NSString *)labelForAddress:(NSString *)addressString
{
    for (BMAddressed *child in self.allAddressed)
    {
        //NSLog(@"child.label '%@' '%@'", child.label, child.address);
        if ([child.address isEqualToString:addressString])
        {
            return child.label;
        }
    }
    
    return addressString;
}

- (NSString *)addressForLabel:(NSString *)labelString // returns nil if none found
{
    for (BMAddressed *child in self.allAddressedArray)
    {
        if ([child.label isEqualToString:labelString])
        {
            return child.address;
        }
    }
    
    return nil;
}

- (NSString *)identityAddressForLabel:(NSString *)labelString // returns nil if none found
{
    for (BMAddressed *child in self.identities.children)
    {
        if ([child.label isEqualToString:labelString])
        {
            return child.address;
        }
    }
    
    return nil;
}

- (NSString *)identityOrChannelAddressForLabel:(NSString *)labelString // returns nil if none found
{
    NSMutableArray *array = [NSMutableArray arrayWithArray:self.identities.children];
    [array addObjectsFromArray:self.channels.children];
    
    for (BMAddressed *child in array)
    {
        if ([child.label isEqualToString:labelString])
        {
            return child.address;
        }
    }
    
    return nil;
}

- (NSSet *)identityAddressLabels
{
    return self.identities.childrenLabelSet;
}

- (NSSet *)fromAddressLabels
{
    NSMutableSet *fromLabels = [NSMutableSet set];
    [fromLabels unionSet:self.identities.childrenLabelSet];
    [fromLabels unionSet:self.subscriptions.childrenLabelSet];
    [fromLabels unionSet:self.channels.childrenLabelSet];
    return fromLabels;
}

- (NSSet *)allAddressed // careful - address can be the same for subscription and identity
{
    NSMutableSet *results = [NSMutableSet setWithSet:[self nonIdentityAddressed]];
    [results addObjectsFromArray:self.identities.children];
    return results;
}

- (NSArray *)allAddressedArray
{
    NSMutableArray *results = [NSMutableArray array];
    [results addObjectsFromArray:self.contacts.children];
    [results addObjectsFromArray:self.subscriptions.children];
    [results addObjectsFromArray:self.channels.children];
    [results addObjectsFromArray:self.identities.children];
    return results;
}

- (NSSet *)nonIdentityAddressed
{
    NSMutableSet *results = [NSMutableSet set];
    [results addObjectsFromArray:self.contacts.children];
    [results addObjectsFromArray:self.subscriptions.children];
    [results addObjectsFromArray:self.channels.children];
    return results;
}

- (NSSet *)toAddressLabels
{
    NSMutableSet *toLabels = [NSMutableSet set];
    
    for (BMAddressed *child in self.nonIdentityAddressed)
    {
        [toLabels addObject:child.label];
    }
    
    return toLabels;
}

- (NSSet *)allAddressLabels
{
    NSMutableSet *allLabels = [NSMutableSet set];
    [allLabels unionSet:self.fromAddressLabels];
    [allLabels unionSet:self.toAddressLabels];
    return allLabels;
}

- (BOOL)hasNoIdentites
{
    return [self.identities.children count] == 0;
}

// --- server ---

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self stopServer];
}

- (void)startServer
{
    self.server = [BMServerProcess sharedBMServerProcess];
    [self.server launch];
    [self startRefreshTimer];
    
    [self postStartingServer];
}

- (void)postStartingServer
{
    [NSNotificationCenter.defaultCenter
     postNotificationName:@"NavWindowSetTitle"
     object:self
     userInfo:[NSDictionary dictionaryWithObject:@"starting bitmessage server..." forKey:@"windowTitle"]];
}

- (void)stopServer
{
    [self stopRefreshTimer];
    [self.server terminate];
}

// --- timer ---

- (void)startRefreshTimer
{
    [self.refreshTimer invalidate];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:self.refreshInterval
                                                         target:self
                                                       selector:@selector(refresh)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopRefreshTimer
{
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)refresh
{
    if (_server == nil || _server.hasFailed)
    {
        //[self stopRefreshTimer];
        [NSException raise:@"Bitmessage server down" format:@""];
    }
    
    if (_server.isRunning)
    {
        [self.messages.received refresh];
        [self.messages.sent refresh];
        
        [self postClientStatus];
    }
}

- (void)postClientStatus
{
    NSDictionary *status = [self.server clientStatus];
    
    if (status)
    {
        //self.statusCounter ++;
        
        NSMutableDictionary *mStatus = [NSMutableDictionary dictionaryWithDictionary:status];
        
        NSNumber *messagesProcessed = [status objectForKey:@"numberOfMessagesProcessed"];
        NSNumber *networkConnections = [status objectForKey:@"networkConnections"];
        
        NSString *description = @"connecting to bitmessage network...";
        
        if (networkConnections.integerValue > 0 || messagesProcessed.integerValue > 0)
        {
            NSInteger sendingCount = [self.messages.sent messagesDoingPOW].count;
            NSString *sendingStatus = @"";
            
            if (sendingCount == 1)
            {
                sendingStatus = [NSString stringWithFormat:@", sending %li message", (long)sendingCount];
            }
            else if (sendingCount > 1)
            {
                sendingStatus = [NSString stringWithFormat:@", sending %li messages", (long)sendingCount];
            }
            
            description = [NSString stringWithFormat:@"syncing with bitmessage network - %@ connections, %@ messages processed%@",
                            networkConnections, messagesProcessed, sendingStatus];
        }
        
        [mStatus setObject:description forKey:@"windowTitle"];

        [NSNotificationCenter.defaultCenter
             postNotificationName:@"NavWindowSetTitle"
             object:self
             userInfo:mStatus];
    }
}

// addresses

- (NSSet *)receivingAddressSet
{
    NSMutableSet *set = [NSMutableSet set];

    /*
    NSLog(@"self.identities.childrenAddressSet = %@", self.identities.childrenAddressSet);
    NSLog(@"subscriptions = %@", self.subscriptions.childrenAddressSet);
    NSLog(@"channels = %@", self.channels.childrenAddressSet);
    */
    
    [set unionSet:self.identities.childrenAddressSet];
    [set unionSet:self.channels.childrenAddressSet];
    [set unionSet:self.subscriptions.childrenAddressSet];
    
    return set;
}

// archive

/*

- (NSString *)archiveSuffix
{
    return @"bmbox";
}

 - (void)archiveToUrl:(NSURL *)url
 {
 NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970];
 
 NSString *archivedPath = [[url path] stringByAppendingPathComponent:
 [NSString stringWithFormat:@"bitmessage.%i.%@",
 (int)timeStamp, self.archiveSuffix]];
 [self stopServer];
 NSString *serverFolder = [[BMServerProcess sharedBMServerProcess] bundleDataPath];
 [[[BMArchive alloc] init] archiveFromPath:serverFolder toPath:archivedPath];
 [self startServer];
 }
 
 - (void)unarchiveFromUrl:(NSURL *)url
 {
 [self stopServer];
 NSString *serverFolder = [[BMServerProcess sharedBMServerProcess] bundleDataPath];
 [[[BMArchive alloc] init] unarchiveFromPath:[url path] toPath:serverFolder];
 [self startServer];
 [self deepFetch];
 }
 */



@end
