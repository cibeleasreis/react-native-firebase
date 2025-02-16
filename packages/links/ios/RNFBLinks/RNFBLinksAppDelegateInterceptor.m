/**
 * Copyright (c) 2016-present Invertase Limited & Contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this library except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import "RNFBLinksAppDelegateInterceptor.h"
#import <RNFBApp/RNFBRCTEventEmitter.h>
#import <GoogleUtilities/GULAppDelegateSwizzler.h>

@implementation RNFBLinksAppDelegateInterceptor

+ (instancetype)shared {
  static dispatch_once_t once;
  static RNFBLinksAppDelegateInterceptor *sharedInstance;
  dispatch_once(&once, ^{
    sharedInstance = [[RNFBLinksAppDelegateInterceptor alloc] init];
    sharedInstance.initialLink = nil;
  });
  return sharedInstance;
}

+ (void)load {
  [GULAppDelegateSwizzler proxyOriginalDelegate];
  [GULAppDelegateSwizzler registerAppDelegateInterceptor:[self shared]];
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)URL
            options:(NSDictionary<NSString *, id> *)options {
  FIRDynamicLink *dynamicLink = [[FIRDynamicLinks dynamicLinks] dynamicLinkFromCustomSchemeURL:URL];
  if (!dynamicLink) return NO;
  if (dynamicLink.url) {
    if (!_initialLink) _initialLink = dynamicLink.url.absoluteString;
    [[RNFBRCTEventEmitter shared] sendEventWithName:LINK_RECEIVED_EVENT body:@{
        @"url": dynamicLink.url.absoluteString,
    }];
  }
  return YES;
}

#pragma mark - User Activities overridden handler methods

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray *restorableObjects))restorationHandler {
  __block BOOL retried = NO;

  id completion = ^(FIRDynamicLink *_Nullable dynamicLink, NSError *_Nullable error) {
    if (!error && dynamicLink && dynamicLink.url) {
      if (!_initialLink) _initialLink = dynamicLink.url.absoluteString;
      [[RNFBRCTEventEmitter shared] sendEventWithName:LINK_RECEIVED_EVENT body:@{
          @"url": dynamicLink.url.absoluteString,
      }];
    }

    // Per Apple Tech Support, a network failure could occur when returning from background on iOS 12.
    // https://github.com/AFNetworking/AFNetworking/issues/4279#issuecomment-447108981
    // So we'll retry the request once
    if (error && !retried && [NSPOSIXErrorDomain isEqualToString:error.domain] && error.code == 53) {
      retried = YES;
      [[FIRDynamicLinks dynamicLinks] handleUniversalLink:userActivity.webpageURL completion:completion];
    }

    if (error) NSLog(@"RNFBLinks: Unknown error occurred when attempting to handle a universal link: %@", error);
  };

  return [[FIRDynamicLinks dynamicLinks] handleUniversalLink:userActivity.webpageURL completion:completion];
}

@end
