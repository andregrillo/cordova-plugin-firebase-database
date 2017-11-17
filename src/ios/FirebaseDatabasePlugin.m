#import "FirebaseDatabasePlugin.h"
@import Firebase;

@implementation FirebaseDatabasePlugin

- (void)pluginInitialize {
    NSLog(@"Starting Firebase Database plugin");

    self.listeners = [NSMutableDictionary dictionary];
}

- (FIRDatabase *)getDb:(NSString *)url {
    if ([url length] == 0) {
        return [FIRDatabase database];
    } else {
        return [FIRDatabase databaseWithURL:url];
    }
}

- (void)setOnline:(CDVInvokedUrlCommand *)command {
    NSString *url = [command argumentAtIndex:0];
    FIRDatabase* database = [self getDb:url];
    BOOL enabled = [[command argumentAtIndex:1] boolValue];

    if (enabled) {
        [database goOnline];
    } else {
        [database goOffline];
    }
}

- (void)set:(CDVInvokedUrlCommand *)command {
    NSString *url = [command argumentAtIndex:0];
    FIRDatabase* database = [self getDb:url];
    NSString *path = [command argumentAtIndex:1];
    id value = [command argumentAtIndex:2];
    FIRDatabaseReference *ref = [database referenceWithPath:path];

    [ref setValue:value withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult *pluginResult;
            if (error) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{
                        @"code": @(error.code),
                        @"message": error.description
                }];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:path];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        });
    }];
}

- (void)update:(CDVInvokedUrlCommand *)command {
    NSString *url = [command argumentAtIndex:0];
    FIRDatabase* database = [self getDb:url];
    NSString *path = [command argumentAtIndex:1];
    NSDictionary *values = [command argumentAtIndex:2 withDefault:@{} andClass:[NSDictionary class]];
    FIRDatabaseReference *ref = [database referenceWithPath:path];

    [ref updateChildValues:values withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult *pluginResult;
            if (error) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{
                        @"code": @(error.code),
                        @"message": error.description
                }];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:path];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        });
    }];
}

- (void)push:(CDVInvokedUrlCommand *)command {
    NSString *url = [command argumentAtIndex:0];
    FIRDatabase* database = [self getDb:url];
    NSString *path = [command argumentAtIndex:1];
    id value = [command argumentAtIndex:2];
    FIRDatabaseReference *ref = [database referenceWithPath:path];

    [[ref childByAutoId] setValue:value withCompletionBlock:^(NSError *error, FIRDatabaseReference *ref) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult *pluginResult;
            if (error) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:@{
                        @"code": @(error.code),
                        @"message": error.description
                }];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[NSString stringWithFormat:@"%@/%@", path, [ref key]]];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        });
    }];
}

- (void)on:(CDVInvokedUrlCommand *)command {
    NSString *url = [command argumentAtIndex:0];
    FIRDatabase* database = [self getDb:url];
    NSString *path = [command argumentAtIndex:1];
    FIRDataEventType type = [self stringToType:[command.arguments objectAtIndex:2]];
    FIRDatabaseReference *ref = [database referenceWithPath:path];

    NSDictionary* orderBy = [command.arguments objectAtIndex:3];
    NSArray* includes = [command.arguments objectAtIndex:4];
    NSDictionary* limit = [command.arguments objectAtIndex:5];
    FIRDatabaseQuery *query = [self createQuery:ref withOrderBy:orderBy];
    for (NSDictionary* condition in includes) {
        query = [self filterQuery:query withCondition:condition];
    }
    query = [self limitQuery:query withCondition:limit];

    NSString *uid = [command.arguments objectAtIndex:6];
    BOOL keepCallback = [uid length] > 0 ? YES : NO;
    id handler = ^(FIRDataSnapshot *_Nonnull snapshot) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{
                @"key": snapshot.key,
                @"value": snapshot.value,
                @"priority": snapshot.priority
            }];
            [pluginResult setKeepCallbackAsBool:keepCallback];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        });
    };

    if (keepCallback) {
        FIRDatabaseHandle handle = [query observeEventType:type withBlock:handler];
        [self.listeners setObject:@(handle) forKey:uid];
    } else {
        [query observeSingleEventOfType:type withBlock:handler];
    }
}

- (void)off:(CDVInvokedUrlCommand *)command {
    NSString *url = [command argumentAtIndex:0];
    FIRDatabase* database = [self getDb:url];
    NSString *path = [command argumentAtIndex:1];
    NSString *uid = [command.arguments objectAtIndex:2];
    FIRDatabaseReference *ref = [database referenceWithPath:path];
    id handlePtr = [self.listeners objectForKey:uid];
    // dereference handlePtr to get FIRDatabaseHandle value
    [ref removeObserverWithHandle:[handlePtr intValue]];
    [self.listeners removeObjectForKey:uid];

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (FIRDatabaseQuery *)createQuery:(FIRDatabaseReference *)ref withOrderBy:(NSDictionary *)orderBy {
    if ([orderBy class] != [NSNull class]) {
        if ([orderBy objectForKey:@"key"]) {
            return [ref queryOrderedByKey];
        } else if ([orderBy objectForKey:@"value"]) {
            return [ref queryOrderedByValue];
        } else if ([orderBy objectForKey:@"priority"]) {
            return [ref queryOrderedByPriority];
        } else {
            NSString* path = [orderBy objectForKey:@"child"];
            if (path) {
                return [ref queryOrderedByChild:path];
            }
        }
    }

    return ref;
}

- (FIRDatabaseQuery *)filterQuery:(FIRDatabaseQuery *)query withCondition:(NSDictionary *)condition {
    if ([condition class] != [NSNull class]) {
        NSString* childKey = [condition objectForKey:@"key"];

        if (condition[@"startAt"]) {
            return [query queryStartingAtValue:condition[@"startAt"] childKey:childKey];
        } else if (condition[@"endAt"]) {
            return [query queryEndingAtValue:condition[@"endAt"] childKey:childKey];
        } else if (condition[@"equalTo"]) {
            return [query queryEqualToValue:condition[@"equalTo"] childKey:childKey];
        } // else throw error?
    }

    return query;
}

- (FIRDatabaseQuery *)limitQuery:(FIRDatabaseQuery *)query withCondition:(NSDictionary *)condition {
    if ([condition class] != [NSNull class]) {
        id first = [condition objectForKey:@"first"];
        id last = [condition objectForKey:@"last"];

        if (first) {
            return [query queryLimitedToFirst:[first integerValue]];
        } else if (last) {
            return [query queryLimitedToLast:[last integerValue]];
        }
    }

    return query;
}

- (FIRDataEventType)stringToType:(NSString *)type {
    if ([type isEqualToString:@"value"]) {
        return FIRDataEventTypeValue;
    } else if ([type isEqualToString:@"child_added"]) {
        return FIRDataEventTypeChildAdded;
    } else if ([type isEqualToString:@"child_removed"]) {
        return FIRDataEventTypeChildRemoved;
    } else if ([type isEqualToString:@"child_changed"]) {
        return FIRDataEventTypeChildChanged;
    } else if ([type isEqualToString:@"child_moved"]) {
        return FIRDataEventTypeChildMoved;
    } else {
        return NULL;
    }
}

@end
