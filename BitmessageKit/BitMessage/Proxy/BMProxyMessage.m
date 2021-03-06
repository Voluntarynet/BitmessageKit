//
//  BMProxyMessage.m
//  Bitmarket
//
//  Created by Steve Dekorte on 1/25/14.
//  Copyright (c) 2014 voluntary.net. All rights reserved.
//

#import "BMProxyMessage.h"
#import "XMLRPCEventBasedParser.h"
#import <FoundationCategoriesKit/FoundationCategoriesKit.h>
#import "BMServerProcess.h"
#import "BMClient.h"

@implementation BMProxyMessage

- (id)init
{
    self = [super init];
    BMServerProcess *server = [BMServerProcess sharedBMServerProcess];
    self.username = [server username];
    self.password = [server password];
    self.host = [server host];
    self.port = [server apiPort];
    self.parameters = [NSArray array];
    self.debug = NO;
    return self;
}

- (void)setError:(NSError *)error
{
    if (error)
    {
        NSLog(@"BMProxy error: %@", error);
    }
    _error = error;
}

- (void)composeRequest
{
    NSString *urlString = [NSString stringWithFormat:@"http://%@:%@/", self.host, self.port];
    self.requestUrl = [NSURL URLWithString:urlString];
    self.request = [[XMLRPCRequest alloc] initWithURL:self.requestUrl];
    
    [self composeAuth];
    [self.request setMethod:self.methodName withParameters:self.parameters];

    if (self.debug)
    {
        NSLog(@"Request body: %@\n", [self.request body]);
    }
}

- (void)composeAuth
{
    NSString *authString = [NSString stringWithFormat:@"%@:%@", self.username, self.password];
    NSString *auth = [@"Basic " stringByAppendingString:[authString encodedBase64]];
    [self.request setValue:auth forHTTPHeaderField: @"Authorization"];
}

- (void)sendSync
{
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPushNotification" object:self];
    [self composeRequest];
    
    if (!BMClient.sharedBMClient.server.isRunning) // start server if needed
    {
        [NSException raise:@"Error" format:@"Bitmessage server not running"];
    }
        
    NSError *error;
    self.response = [XMLRPCConnection sendSynchronousXMLRPCRequest:self.request error:&error];
    self.error = error;
    
    if (self.debug || error)
    {
        //NSLog(@"\n\nResponse: %@", self.response);
        NSLog(@"\n\nresponseValue: %@\n", [self responseValue]);

        if (self.error)
        {
            NSLog(@"\n\nerror %@\n", self.error);
        }
    }
    
    [NSNotificationCenter.defaultCenter postNotificationName:@"ProgressPopNotification" object:self];
}

- (id)responseValue
{
    if (self.response)
    {
        return self.response.object;
    }
    
    return nil;
}

- (id)parsedResponseValue
{
    if (self.response)
    {
        NSString *s = self.response.object;
        
        if (s == nil)
        {
            return nil;
        }
        
        NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
        
        NSError *error = nil;
        id object = [NSJSONSerialization
                     JSONObjectWithData:data
                     options:0
                     error:&error];
        
        if(error)
        {
            self.error = error;
        }

        
        return object;
    }
    
    return nil;
}

/*
- (void)sendAsync
{
    [self composeRequest];
    XMLRPCConnectionManager *manager = [XMLRPCConnectionManager sharedManager];
    [manager spawnConnectionWithXMLRPCRequest:self.request delegate: self];
}

 // for asnyc calls
 
 - (void)request: (XMLRPCRequest *)request didReceiveResponse: (XMLRPCResponse *)response
{
    NSLog(@"\n\nResponse: %@", response);
}

- (void)request: (XMLRPCRequest *)request didSendBodyData: (float)percent
{
    NSLog(@"didSendBodyData %f", percent);
}

- (void)request: (XMLRPCRequest *)request didFailWithError: (NSError *)error
{
    NSLog(@"didFailWithError %@", error);
}

- (BOOL)request: (XMLRPCRequest *)request
    canAuthenticateAgainstProtectionSpace: (NSURLProtectionSpace *)protectionSpace
{
    return YES;
}

- (void)request: (XMLRPCRequest *)request
    didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge
{
    NSLog(@"didReceiveAuthenticationChallenge");
}

- (void)request: (XMLRPCRequest *)request
    didCancelAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge
{
    NSLog(@"didCancelAuthenticationChallenge");
}
*/


@end
