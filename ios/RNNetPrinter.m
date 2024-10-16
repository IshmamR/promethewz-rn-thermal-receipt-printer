//
//  RNNetPrinter.m
//  RNThermalReceiptPrinter
//
//  Created by MTT on 06/11/19.
//  Copyright © 2019 Facebook. All rights reserved.
//


#import "RNNetPrinter.h"
#import "PrinterSDK.h"
#include <ifaddrs.h>
#include <arpa/inet.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTLog.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSString *const EVENT_SCANNER_RESOLVED = @"scannerResolved";
NSString *const EVENT_SCANNER_RUNNING = @"scannerRunning";

@interface PrivateIP : NSObject

@end

@implementation PrivateIP

- (NSString *)getIPAddress {

    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];

                }

            }

            temp_addr = temp_addr->ifa_next;
        }
    }
    // Free memory
    freeifaddrs(interfaces);
    return address;

}

@end

@implementation RNNetPrinter

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}
RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents
{
    return @[EVENT_SCANNER_RESOLVED, EVENT_SCANNER_RUNNING];
}

RCT_EXPORT_METHOD(init:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    connected_ip = nil;
    is_scanning = NO;
    _printerArray = [NSMutableArray new];
    successCallback(@[@"Init successful"]);
}

RCT_EXPORT_METHOD(getDeviceList:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePrinterConnectedNotification:) name:PrinterConnectedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleBLEPrinterConnectedNotification:) name:@"BLEPrinterConnected" object:nil];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self scan:successCallback];
    });
}

// concurrency
// - (void) scan: (RCTResponseSenderBlock)successCallback {
//     @try {
//         PrivateIP *privateIP = [[PrivateIP alloc]init];
//         NSString *localIP = [privateIP getIPAddress];
//         is_scanning = YES;
//         [self sendEventWithName:EVENT_SCANNER_RUNNING body:@YES];
        
//         // Use a local array to collect results
//         NSMutableArray *localPrinterArray = [NSMutableArray new];

//         NSString *prefix = [localIP substringToIndex:([localIP rangeOfString:@"." options:NSBackwardsSearch].location)];
//         NSInteger suffix = [[localIP substringFromIndex:([localIP rangeOfString:@"." options:NSBackwardsSearch].location)] intValue];

//         // Create a dispatch group to manage concurrent connections
//         dispatch_group_t group = dispatch_group_create();

//         for (NSInteger i = 1; i < 255; i++) {
//             if (i == suffix) continue;
//             NSString *testIP = [NSString stringWithFormat:@"%@.%ld", prefix, (long)i];
//             current_scan_ip = testIP;

//             // Enter the group before starting the connection
//             dispatch_group_enter(group);
//             dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                 // Attempt to connect and handle success/failure
//                 if ([[PrinterSDK defaultPrinterSDK] connectIP:testIP]) {
//                     @synchronized (localPrinterArray) {
//                         [localPrinterArray addObject:testIP]; // Add discovered printer to local array
//                     }
//                 } else {
//                     NSLog(@"Failed to connect to %@", testIP);
//                 }
//                 // Use a delay if necessary, but consider alternatives
//                 [NSThread sleepForTimeInterval:0.5];
//                 // Leave the group after the connection attempt
//                 dispatch_group_leave(group);
//             });
//         }

//         // Wait for all connections to finish
//         dispatch_group_notify(group, dispatch_get_main_queue(), ^{
//             NSOrderedSet *orderedSet = [NSOrderedSet orderedSetWithArray:localPrinterArray];
//             NSArray *arrayWithoutDuplicates = [orderedSet array];
//             _printerArray = (NSMutableArray *)arrayWithoutDuplicates; // Update the main array after all connections

//             [self sendEventWithName:EVENT_SCANNER_RESOLVED body:_printerArray];
//             successCallback(@[_printerArray]);
//             [[PrinterSDK defaultPrinterSDK] disconnect]; // Move disconnect here
//             is_scanning = NO;
//             [self sendEventWithName:EVENT_SCANNER_RUNNING body:@NO];
//         });

//     } @catch (NSException *exception) {
//         NSLog(@"No connection: %@", exception);
//     }
// }

- (void) scan: (RCTResponseSenderBlock)successCallback {
    @try {
        PrivateIP *privateIP = [[PrivateIP alloc]init];
        NSString *localIP = [privateIP getIPAddress];
        is_scanning = YES;
        [self sendEventWithName:EVENT_SCANNER_RUNNING body:@YES];
        _printerArray = [NSMutableArray new];

        NSString *prefix = [localIP substringToIndex:([localIP rangeOfString:@"." options:NSBackwardsSearch].location)];
        NSInteger suffix = [[localIP substringFromIndex:([localIP rangeOfString:@"." options:NSBackwardsSearch].location)] intValue];

        for (NSInteger i = 1; i < 255; i++) {
            if (i == suffix) continue;
            NSString *testIP = [NSString stringWithFormat:@"%@.%ld", prefix, (long)i];
            current_scan_ip = testIP;
            [[PrinterSDK defaultPrinterSDK] connectIP:testIP];
            [NSThread sleepForTimeInterval:0.5];
        }

        NSOrderedSet *orderedSet = [NSOrderedSet orderedSetWithArray:_printerArray];
        NSArray *arrayWithoutDuplicates = [orderedSet array];
        _printerArray = (NSMutableArray *)arrayWithoutDuplicates;

        [self sendEventWithName:EVENT_SCANNER_RESOLVED body:_printerArray];

        successCallback(@[_printerArray]);
    } @catch (NSException *exception) {
        NSLog(@"No connection");
    }
    [[PrinterSDK defaultPrinterSDK] disconnect];
    is_scanning = NO;
    [self sendEventWithName:EVENT_SCANNER_RUNNING body:@NO];
}

- (void)handlePrinterConnectedNotification:(NSNotification*)notification
{
    if (is_scanning) {
        [_printerArray addObject:@{@"host": current_scan_ip, @"port": @9100}];
    }
}

- (void)handleBLEPrinterConnectedNotification:(NSNotification*)notification
{
    connected_ip = nil;
}

RCT_EXPORT_METHOD(connectPrinter:(NSString *)host
                  withPort:(nonnull NSNumber *)port
                  success:(RCTResponseSenderBlock)successCallback
                  fail:(RCTResponseSenderBlock)errorCallback) {
    // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //     @try {

    //         BOOL isConnectSuccess = [[PrinterSDK defaultPrinterSDK] connectIP:host];

    //         if (!isConnectSuccess) {
    //             dispatch_async(dispatch_get_main_queue(), ^{
    //                 errorCallback(@[@"Can't connect to printer"]);
    //             });
    //             return;
    //         }

    //         connected_ip = host;
    //         // [[NSNotificationCenter defaultCenter] postNotificationName:@"NetPrinterConnected" object:nil];
    //         // successCallback(@[[NSString stringWithFormat:@"Connecting to printer %@", host]]);

    //         dispatch_async(dispatch_get_main_queue(), ^{
    //             successCallback(@[@"Connecting to printer"]);
    //         });
    //     } @catch (NSException *exception) {
    //         dispatch_async(dispatch_get_main_queue(), ^{
    //             errorCallback(@[exception.reason]);
    //         });
    //     }
    // });

    @try {
        BOOL isConnectSuccess = [[PrinterSDK defaultPrinterSDK] connectIP:host];
        !isConnectSuccess ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer %@", host] : nil;

        connected_ip = host;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetPrinterConnected" object:nil];
        successCallback(@[[NSString stringWithFormat:@"Connecting to printer %@", host]]);

    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printRawData:(NSString *)text
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSNumber* beepPtr = [options valueForKey:@"beep"];
            NSNumber* cutPtr = [options valueForKey:@"cut"];

            BOOL beep = (BOOL)[beepPtr intValue];
            BOOL cut = (BOOL)[cutPtr intValue];

            if (!connected_ip) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    errorCallback(@[@"Can't connect to printer"]);
                });
                return;
            }

            [[PrinterSDK defaultPrinterSDK] printText:text];
            if (beep) {
                [[PrinterSDK defaultPrinterSDK] beep];
            }
            if (cut) {
                [[PrinterSDK defaultPrinterSDK] cutPaper];
            }

            // dispatch_async(dispatch_get_main_queue(), ^{
            //     successCallback(@[@"Printing completed successfully"]);
            // });
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                errorCallback(@[exception.reason]);
            });
        }
    });

    // @try {
    //     NSNumber* beepPtr = [options valueForKey:@"beep"];
    //     NSNumber* cutPtr = [options valueForKey:@"cut"];

    //     BOOL beep = (BOOL)[beepPtr intValue];
    //     BOOL cut = (BOOL)[cutPtr intValue];

    //     !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;

    //     // [[PrinterSDK defaultPrinterSDK] printTestPaper];
    //     [[PrinterSDK defaultPrinterSDK] printText:text];
    //     beep ? [[PrinterSDK defaultPrinterSDK] beep] : nil;
    //     cut ? [[PrinterSDK defaultPrinterSDK] cutPaper] : nil;
    // } @catch (NSException *exception) {
    //     errorCallback(@[exception.reason]);
    // }
}

RCT_EXPORT_METHOD(printHex:(NSString *)text
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    
    // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //     @try {
    //         NSNumber* beepPtr = [options valueForKey:@"beep"];
    //         NSNumber* cutPtr = [options valueForKey:@"cut"];

    //         BOOL beep = (BOOL)[beepPtr intValue];
    //         BOOL cut = (BOOL)[cutPtr intValue];

    //         if (!connected_ip) {
    //             dispatch_async(dispatch_get_main_queue(), ^{
    //                 errorCallback(@[@"Can't connect to printer"]);
    //             });
    //             return;
    //         }

    //         [[PrinterSDK defaultPrinterSDK] sendHex:text];
    //         if (beep) {
    //             [[PrinterSDK defaultPrinterSDK] beep];
    //         }
    //         if (cut) {
    //             [[PrinterSDK defaultPrinterSDK] cutPaper];
    //         }

    //         // dispatch_async(dispatch_get_main_queue(), ^{
    //         //     successCallback(@[@"Printing completed successfully"]);
    //         // });
    //     } @catch (NSException *exception) {
    //         dispatch_async(dispatch_get_main_queue(), ^{
    //             errorCallback(@[exception.reason]);
    //         });
    //     }
    // });

    @try {
        NSNumber* beepPtr = [options valueForKey:@"beep"];
        NSNumber* cutPtr = [options valueForKey:@"cut"];

        BOOL beep = (BOOL)[beepPtr intValue];
        BOOL cut = (BOOL)[cutPtr intValue];

        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;

        // [[PrinterSDK defaultPrinterSDK] printTestPaper];
        [[PrinterSDK defaultPrinterSDK] sendHex:text];
        // [[PrinterSDK defaultPrinterSDK] printData:text];
        beep ? [[PrinterSDK defaultPrinterSDK] beep] : nil;
        cut ? [[PrinterSDK defaultPrinterSDK] cutPaper] : nil;
    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printImageData:(NSString *)imgUrl
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {

    //  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //     @try {
    //         if (!connected_ip) {
    //             dispatch_async(dispatch_get_main_queue(), ^{
    //                 errorCallback(@[@"Can't connect to printer"]);
    //             });
    //             return;
    //         }

    //         NSURL* url = [NSURL URLWithString:imgUrl];
    //         NSData* imageData = [NSData dataWithContentsOfURL:url];

    //         NSString* printerWidthType = [options valueForKey:@"printerWidthType"];

    //         NSInteger printerWidth = 576;

    //         if(printerWidthType != nil && [printerWidthType isEqualToString:@"58"]) {
    //             printerWidth = 384;
    //         }

    //         if(imageData != nil){
    //             UIImage* image = [UIImage imageWithData:imageData];
    //             UIImage* printImage = [self getPrintImage:image printerOptions:options];

    //             [[PrinterSDK defaultPrinterSDK] setPrintWidth:printerWidth];
    //             [[PrinterSDK defaultPrinterSDK] printImage:printImage ];
    //         }

    //         // dispatch_async(dispatch_get_main_queue(), ^{
    //         //     successCallback(@[@"Printing completed successfully"]);
    //         // });
    //     } @catch (NSException *exception) {
    //         dispatch_async(dispatch_get_main_queue(), ^{
    //             errorCallback(@[exception.reason]);
    //         });
    //     }
    // });

    @try {

        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;
        NSURL* url = [NSURL URLWithString:imgUrl];
        NSData* imageData = [NSData dataWithContentsOfURL:url];

        NSString* printerWidthType = [options valueForKey:@"printerWidthType"];

        NSInteger printerWidth = 576;

        if(printerWidthType != nil && [printerWidthType isEqualToString:@"58"]) {
            printerWidth = 384;
        }

        if(imageData != nil){
            UIImage* image = [UIImage imageWithData:imageData];
            UIImage* printImage = [self getPrintImage:image printerOptions:options];

            [[PrinterSDK defaultPrinterSDK] setPrintWidth:printerWidth];
            [[PrinterSDK defaultPrinterSDK] printImage:printImage ];
        }

    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

RCT_EXPORT_METHOD(printImageBase64:(NSString *)base64Qr
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {

    // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //     @try {
    //         if (!connected_ip) {
    //             dispatch_async(dispatch_get_main_queue(), ^{
    //                 errorCallback(@[@"Can't connect to printer"]);
    //             });
    //             return;
    //         }

    //         if(![base64Qr  isEqual: @""]){
    //             NSString *result = [@"data:image/png;base64," stringByAppendingString:base64Qr];
    //             NSURL *url = [NSURL URLWithString:result];
    //             NSData *imageData = [NSData dataWithContentsOfURL:url];
    //             NSString* printerWidthType = [options valueForKey:@"printerWidthType"];

    //             NSInteger printerWidth = 400;

    //             if(printerWidthType != nil && [printerWidthType isEqualToString:@"58"]) {
    //                 printerWidth = 300;
    //             }

    //             if(imageData != nil){
    //                 UIImage* image = [UIImage imageWithData:imageData];
    //                 UIImage* printImage = [self getPrintImage:image printerOptions:options];

    //                 [[PrinterSDK defaultPrinterSDK] setPrintWidth:printerWidth];
    //                 [[PrinterSDK defaultPrinterSDK] printImage:printImage ];
    //             }
    //         }

    //         // dispatch_async(dispatch_get_main_queue(), ^{
    //         //     successCallback(@[@"Printing completed successfully"]);
    //         // });
    //     } @catch (NSException *exception) {
    //         dispatch_async(dispatch_get_main_queue(), ^{
    //             errorCallback(@[exception.reason]);
    //         });
    //     }
    // });

    @try {
        
        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;
        if(![base64Qr  isEqual: @""]){
            NSString *result = [@"data:image/png;base64," stringByAppendingString:base64Qr];
            NSURL *url = [NSURL URLWithString:result];
            NSData *imageData = [NSData dataWithContentsOfURL:url];
            NSString* printerWidthType = [options valueForKey:@"printerWidthType"];

            NSInteger printerWidth = 400;

            if(printerWidthType != nil && [printerWidthType isEqualToString:@"58"]) {
                printerWidth = 300;
            }

            if(imageData != nil){
                UIImage* image = [UIImage imageWithData:imageData];
                UIImage* printImage = [self getPrintImage:image printerOptions:options];

                [[PrinterSDK defaultPrinterSDK] setPrintWidth:printerWidth];
                [[PrinterSDK defaultPrinterSDK] printImage:printImage ];
            }
        }
    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

-(UIImage *)getPrintImage:(UIImage *)image
           printerOptions:(NSDictionary *)options {

    NSNumber* nWidth = [options valueForKey:@"imageWidth"];
    NSNumber* nPaddingX = [options valueForKey:@"paddingX"];

    CGFloat newWidth = 150;
    if(nWidth != nil) {
        newWidth = [nWidth floatValue];
    }

    CGFloat paddingX = 250;
    if(nPaddingX != nil) {
        paddingX = [nPaddingX floatValue];
    }

    CGFloat newHeight = (newWidth / image.size.width) * image.size.height;
    CGSize newSize = CGSizeMake(newWidth, newHeight);
    UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGImageRef immageRef = image.CGImage;
    CGContextDrawImage(context, CGRectMake(0, 0, newWidth, newHeight), immageRef);
    CGImageRef newImageRef = CGBitmapContextCreateImage(context);
    UIImage* newImage = [UIImage imageWithCGImage:newImageRef];

    CGImageRelease(newImageRef);
    UIGraphicsEndImageContext();

    UIImage* paddedImage = [self addImagePadding:newImage paddingX:paddingX paddingY:0];
    return paddedImage;

}

-(UIImage *)addImagePadding:(UIImage * )image
                   paddingX: (CGFloat) paddingX
                   paddingY: (CGFloat) paddingY
{
    CGFloat width = image.size.width + paddingX;
    CGFloat height = image.size.height + paddingY;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), true, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGFloat originX = (width - image.size.width)/2;
    CGFloat originY = (height -  image.size.height)/2;
    CGImageRef immageRef = image.CGImage;
    CGContextDrawImage(context, CGRectMake(originX, originY, image.size.width, image.size.height), immageRef);
    CGImageRef newImageRef = CGBitmapContextCreateImage(context);
    UIImage* paddedImage = [UIImage imageWithCGImage:newImageRef];

    CGImageRelease(newImageRef);
    UIGraphicsEndImageContext();

    return paddedImage;
}

RCT_EXPORT_METHOD(closeConn) {
    // dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //     @try {
    //         if (!connected_ip) {
    //             // dispatch_async(dispatch_get_main_queue(), ^{
    //             //     errorCallback(@[@"Can't connect to printer"]);
    //             // });

    //             NSLog(@"Can't connect to printer: No active connection");

    //             return;
    //         }

    //         [[PrinterSDK defaultPrinterSDK] disconnect];
    //         connected_ip = nil;

    //         // dispatch_async(dispatch_get_main_queue(), ^{
    //         //     successCallback(@[@"Printing completed successfully"]);
    //         // });
    //     } @catch (NSException *exception) {
    //         // dispatch_async(dispatch_get_main_queue(), ^{
    //         //     errorCallback(@[exception.reason]);
    //         // });

    //         NSLog(@"%@", exception.reason);
    //     }
    // });

    @try {
        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;
        [[PrinterSDK defaultPrinterSDK] disconnect];
        connected_ip = nil;
    } @catch (NSException *exception) {
        NSLog(@"%@", exception.reason);
    }
}

RCT_EXPORT_METHOD(printQrCode:(NSString *)qrCode
                  printerOptions:(NSDictionary *)options
                  fail:(RCTResponseSenderBlock)errorCallback) {
    @try {

        !connected_ip ? [NSException raise:@"Invalid connection" format:@"Can't connect to printer"] : nil;


        NSString* printerWidthType = [options valueForKey:@"printerWidthType"];

        NSInteger printerWidth = 576;

        if(printerWidthType != nil && [printerWidthType isEqualToString:@"58"]) {
            printerWidth = 384;
        }

        if(qrCode != nil){

            [[PrinterSDK defaultPrinterSDK] setPrintWidth:printerWidth];
            [[PrinterSDK defaultPrinterSDK] printQrCode:qrCode ];
        }

    } @catch (NSException *exception) {
        errorCallback(@[exception.reason]);
    }
}

@end
