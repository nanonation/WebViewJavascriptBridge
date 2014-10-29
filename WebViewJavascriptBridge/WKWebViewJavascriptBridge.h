//
//  WKWebViewJavascriptBridge.h
//
//  Created by Loki Meyburg on 10/15/14.
//  Copyright (c) 2014 Loki Meyburg. All rights reserved.
//

#if (__MAC_OS_X_VERSION_MAX_ALLOWED > __MAC_10_9 || __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_7_1)
#define supportsWKWebKit
#endif

#if defined(supportsWKWebKit )

#import <Foundation/Foundation.h>
#define kMessageSeparator       @"__WVJB_MESSAGE_SEPERATOR__"
#define kCustomProtocolScheme @"wvjbscheme"
#define kConsoleQueueHasMessage @"__WVJB_CONSOLE_QUEUE_MESSAGE__"
#define kQueueHasMessage      @"__WVJB_QUEUE_MESSAGE__"

#import <WebKit/WebKit.h>
typedef void (^WVJBResponseCallback)(id responseData);
typedef void (^WVJBHandler)(id data, WVJBResponseCallback responseCallback);
typedef void (^WVJBJSConsoleMessageHandler)(NSString* type, NSString* message);

@interface WKWebViewJavascriptBridge : NSObject<WKNavigationDelegate>

+ (instancetype)bridgeForWebView:(WKWebView*)webView handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)handler resourceBundle:(NSBundle*)bundle;

+ (void)enableLogging;

- (void)setJSConsoleMessageHandler:(WVJBJSConsoleMessageHandler)handler;
- (void)setShouldLogJSConsoleMessagesToNSLog:(BOOL)shouldLog;

- (void)send:(id)message;
- (void)send:(id)message responseCallback:(WVJBResponseCallback)responseCallback;
- (void)registerHandler:(NSString*)handlerName handler:(WVJBHandler)handler;
- (void)callHandler:(NSString*)handlerName;
- (void)callHandler:(NSString*)handlerName data:(id)data;
- (void)callHandler:(NSString*)handlerName data:(id)data responseCallback:(WVJBResponseCallback)responseCallback;
- (void)reset;

@end

#endif
