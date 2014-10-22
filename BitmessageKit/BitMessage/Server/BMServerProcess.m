//
//  BMServerProcess.m
//  Bitmessage
//
//  Created by Steve Dekorte on 2/17/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "BMServerProcess.h"
#import <SystemInfoKit/SystemInfoKit.h>
#import <FoundationCategoriesKit/FoundationCategoriesKit.h>
#import "BMProxyMessage.h"

@implementation BMServerProcess

static BMServerProcess *shared = nil;


+ (BMServerProcess *)sharedBMServerProcess
{
    if (!shared)
    {
        shared = [BMServerProcess alloc];
        shared = [shared init];
    }
    
    return shared;
}

- (id)init
{
    self = [super init];
    
    self.useTor = YES;
    self.debug = NO;
    
    if (self.useTor)
    {
        _torProcess = [[TorProcess alloc] init];
    }
    
    self.keysFile = [[BMKeysFile alloc] init];

    [self moveOldBitmessageFilesIfNeeded];

    [SIProcessKiller sharedSIProcessKiller]; // to end old processes

    return self;
}

- (NSBundle *)bundle
{
    return [NSBundle bundleForClass:self.class];
}

- (void)moveOldBitmessageFilesIfNeeded
{
    NSString *oldDataPath = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *newDataPath = [self bundleDataPath];

    NSArray *fileNames = @[@"debug.log",
                           @"keys.dat",
                           @"keys_backups",
                           @"knownnodes.dat",
                           @"messages.dat",
                           @"readMessagesDB.json",
                           @"deletedMessagesDB.json"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSString *fileName in fileNames)
    {
        BOOL isDir;
        NSString *filePath = [oldDataPath stringByAppendingPathComponent:fileName];
        
        if ([fm fileExistsAtPath:filePath isDirectory:&isDir])
        {
            NSString *newFilePath = [newDataPath stringByAppendingPathComponent:fileName];
            NSError *error;
            [fm moveItemAtPath:filePath toPath:newFilePath error:&error];
            
            if (error)
            {
                NSLog(@"warning: %@", error);
            }
        }
    }
}

- (NSString *)justBundleDataPath
{
    NSString *supportFolder = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *bundleName = [self.bundle.bundleIdentifier componentsSeparatedByString:@"."].lastObject;
    NSString *path = [supportFolder stringByAppendingPathComponent:bundleName];
    return path;
}

- (NSString *)bundleDataPath
{
    NSString *path = self.justBundleDataPath;
        
    NSError *error;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    return path;
}

// keys.dat config

- (NSString *)host
{
    return @"127.0.0.1";
}

- (NSNumber *)port
{
    return self.keysFile.port.asNumber;
}

- (NSNumber *)apiPort
{
    return self.keysFile.apiport.asNumber;
}

- (NSString *)username
{
    return self.keysFile.apiusername;
}

- (NSString *)password
{
    return self.keysFile.apipassword;
}

// keys.dat

- (void)setupKeysDat
{
    [self.keysFile backup];
    [self.keysFile setupForDaemon];
    
    if (!self.useTor)
    {
        [self.keysFile setupForNonTor];
        NSLog(@"*** WARNING: setting up Bitmessage for non Tor use");
        [self.keysFile setSOCKSPort:@0];
    }
    else
    {
        [self.keysFile setupForTor];
        _torProcess.debug = self.debug;
        [_torProcess launch];
        assert(_torProcess.isRunning);
        assert(_torProcess.torSocksPort != nil); // need to launch tor first so it picks a port
        [self.keysFile setSOCKSPort:_torProcess.torSocksPort];
        NSLog(@"*** setup Bitmessage for Tor on port %@", _torProcess.torSocksPort);
    }
    
    NSMutableArray *openPorts = [SINetwork.sharedSINetwork openPortsBetween:@9000 and:@9100];
    
    // chose open ports
    [self.keysFile setPort:[openPorts popFirst]];
    [self.keysFile setApiPort:[openPorts popFirst]];
    
    // randomize login
    [self.keysFile setApiUsername:NSNumber.entropyNumber.asUnsignedIntegerString];
    [self.keysFile setApiPassword:NSNumber.entropyNumber.asUnsignedIntegerString];
    
    [self.keysFile setDefaultnoncetrialsperbyte:@1024];
    //[self.keysFile setDefaultnoncetrialsperbyte:@16384];

}

- (void)assertIsRunning
{
    if (!self.isRunning)
    {
        [NSException raise:@"Server not running" format:nil];
    }
}

- (BOOL)setLabel:(NSString *)aLabel onAddress:(NSString *)anAddress
{
    [self assertIsRunning];
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPush" object:self];
    [self terminate];
    [self.keysFile setLabel:aLabel onAddress:anAddress];
    [self launch];
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPop" object:self];
    return YES;
}

- (void)launch
{
    if (self.isRunning)
    {
        NSLog(@"Attempted to launch BM server more than once.");
        return;
    }
    
    // Launch tor client
    
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPush" object:self];
    
    if (self.useTor && !self.torProcess.isRunning)
    {
        [self.torProcess launch];

        if (!self.torProcess.isRunning)
        {
            [NSException raise:@"tor not running" format:nil];
        }
    }
    

    BOOL hasRunBefore = self.keysFile.doesExist;
    
    if (hasRunBefore)
    {
        [self setupKeysDat];
    }
    
    
    //if (self.debug)
    {
        NSLog(@"launching Bitmessage with keys.dat:");
        NSLog(@"    port: %@", self.port);
        NSLog(@"    apiport: %@", self.apiPort);
        //NSLog(@"    username: %@", self.username);
        //NSLog(@"    password: %@", self.password);
    }
    
    _bitmessageTask = [[NSTask alloc] init];
    _inpipe = [NSPipe pipe];
    NSDictionary *environmentDict = [[NSProcessInfo processInfo] environment];
    NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:environmentDict];
    //NSLog(@"%@", [environment valueForKey:@"PATH"]);
    
    // Set environment variables containing api username and password
    if (hasRunBefore)
    {
        [environment setObject:self.username forKey:@"PYBITMESSAGE_USER"];
        [environment setObject:self.password forKey:@"PYBITMESSAGE_PASSWORD"];
    }
    else
    {
        [environment setObject:@"default" forKey:@"PYBITMESSAGE_USER"];
        [environment setObject:@"default" forKey:@"PYBITMESSAGE_PASSWORD"];
    }
    
    [environment setObject:self.bundleDataPath forKey:@"BITMESSAGE_HOME"];

    [_bitmessageTask setEnvironment: environment];
    
    // Set the path to the python executable
    NSBundle *mainBundle = [NSBundle bundleForClass:self.class];
    NSString * pythonPath       = [mainBundle pathForResource:@"python" ofType:@"exe" inDirectory: @"static-python"];
    NSString * pybitmessagePath = [mainBundle pathForResource:@"bitmessagemain" ofType:@"py" inDirectory: @"pybitmessage"];
    [_bitmessageTask setLaunchPath:pythonPath];
    
    //[_bitmessageTask setStandardInput: (NSFileHandle *) _inpipe];
    
    if (self.debug)
    {
        [_bitmessageTask setStandardOutput:[NSFileHandle fileHandleWithStandardOutput]];
        [_bitmessageTask setStandardError:[NSFileHandle fileHandleWithStandardOutput]];
    }
    else
    {
        [_bitmessageTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
        [_bitmessageTask setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    }
    
    [_bitmessageTask setArguments:@[pybitmessagePath]];
   
    if (self.debug)
    {
        NSLog(@"*** launching _pyBitmessage ***");
    }
    
    [_bitmessageTask launch];
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPop" object:self];
    
    if (!hasRunBefore)
    {
        NSLog(@"first launch - relaunching in 3 seconds to complete keys.dat setup...");
        sleep(3);
        [self terminate];
        sleep(3); // would be nice to wait for shutdown instead
        [self launch];
        return;
    }
    
    sleep(2);

    if (![_bitmessageTask isRunning])
    {
        NSLog(@"pybitmessage task not running after launch");
    }
    else
    {
        [SIProcessKiller.sharedSIProcessKiller onRestartKillTask:_bitmessageTask];
        sleep(2);
        [self waitOnConnect];
    }
}

- (BOOL)waitOnConnect
{
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPush" object:self];
    
    for (int i = 0; i < 100; i ++)
    {
        if ([self canConnect])
        {
            if (self.debug)
            {
                NSLog(@"connected to server");
            }
            
            [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPop" object:self];
            return YES;
        }
        
        NSLog(@"waiting to connect to server...");
        sleep(1);
    }
    
    [NSException raise:@"unable to connect to Bitmessage server" format:nil];
    
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPop" object:self];
    
    return NO;
}

- (void)terminate
{
    if (_bitmessageTask)
    {
        NSLog(@"Killing bitmessage process...");
        [SIProcessKiller.sharedSIProcessKiller removeKillTask:_bitmessageTask];
        [_bitmessageTask terminate];
        self.bitmessageTask = nil;
    }

    [self.torProcess terminate];
}

- (BOOL)isRunning
{
    if (!_bitmessageTask.isRunning)
    {
        return NO;
    }
    
    if (self.useTor && !_torProcess.isRunning)
    {
        return NO;
    }
    
    return YES;
}

- (BOOL)canConnect
{
    BMProxyMessage *message = [[BMProxyMessage alloc] init];
    [message setMethodName:@"helloWorld"];
    NSArray *params = [NSArray arrayWithObjects:@"hello", @"world", nil];
    [message setParameters:params];
    //message.debug = YES;
    [message sendSync];
    
    NSString *response = [message responseValue];
    return [response isEqualToString:@"hello-world"];
}

@end
