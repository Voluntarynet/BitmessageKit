//
//  BMTorProcess.m
//  BitmessageKit
//
//  Created by Steve Dekorte on 8/22/14.
//  Copyright (c) 2014 Adam Thorsen. All rights reserved.
//

#import "BMTorProcess.h"
#import "BMProcesses.h"

@implementation BMTorProcess

static id sharedBMTorProcess = nil;

+ (BMProcesses *)sharedBMTorProcess
{
    if (sharedBMTorProcess == nil)
    {
        sharedBMTorProcess = [[self.class alloc] init];
    }
    
    return sharedBMTorProcess;
}

- (id)init
{
    self = [super init];
    self.debug = NO;
    return self;
}

/*
- (NSString *)torPidFilePath
{
    return [[[self serverDataFolder] stringByAppendingPathComponent:@"tor"] stringByAppendingPathExtension:@"pid"];
    
}

- (NSString *)torPid
{
    return [[NSString alloc] initWithContentsOfFile:self.torPidFilePath encoding:NSUTF8StringEncoding error:NULL];
}
*/


- (void)launch
{
    NSLog(@"*** launching Tor ***");
    
    // Check for pre-existing process
    NSString *torPidFilePath = [[[self serverDataFolder] stringByAppendingPathComponent:@"tor"] stringByAppendingPathExtension:@"pid"];
    NSString *torPid = [[NSString alloc] initWithContentsOfFile:torPidFilePath encoding:NSUTF8StringEncoding error:NULL];
    
    if (nil != torPid)
    {
        BOOL processExists = [BMProcesses.sharedBMProcesses isProcessRunningWithName:@"tor" pid:[torPid intValue]];
        if(processExists)
        {
            NSLog(@"killing old tor process with pid: %@", torPid);
            
            // Kill process
            kill([torPid intValue], SIGKILL);
        }
    }
    
    _torTask = [[NSTask alloc] init];
    _inpipe = [NSPipe pipe];
    
    // Set the path to the python executable
    NSBundle *mainBundle = [NSBundle bundleForClass:self.class];
    NSString * torPath = [mainBundle pathForResource:@"tor" ofType:@"" inDirectory: @"tor"];
    NSString * torConfigPath = [mainBundle pathForResource:@"torrc" ofType:@"" inDirectory: @"tor"];
    NSString * torDataDirectory = [[self serverDataFolder] stringByAppendingPathComponent: @".tor"];
    [_torTask setLaunchPath:torPath];

    [_torTask setStandardInput: (NSFileHandle *) _inpipe];
    
    if (self.debug)
    {
        [_torTask setStandardOutput:[NSFileHandle fileHandleWithStandardOutput]];
        [_torTask setStandardError:[NSFileHandle fileHandleWithStandardOutput]];
    }
    else
    {
        [_torTask setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
        [_torTask setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    }
    
    [_torTask setArguments:@[ @"-f", torConfigPath,
                              @"--DataDirectory", torDataDirectory,
                              @"--PidFile", torPidFilePath,
                              @"--SOCKSPort", self.torPort ]];
    
    NSLog(@"*** launching Tor on port %@ ***", self.torPort);
    
    [_torTask launch];
    
    if (![_torTask isRunning])
    {
        NSLog(@"tor task not running after launch");
    }
}

- (void)terminate
{
    NSLog(@"Killing tor process...");
    [_torTask terminate];
    self.torTask = nil;
}

- (BOOL)isRunning
{
    return (_torTask && [_torTask isRunning]);
}


@end
