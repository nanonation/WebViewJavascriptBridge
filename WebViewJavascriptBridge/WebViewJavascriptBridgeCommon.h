//
//  WebViewJavascriptBridgeCommon.h
//  ExampleApp-iOS
//
//  Created by Marcus Westin on 6/14/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kMessageSeparator       @"__WVJB_MESSAGE_SEPERATOR__"
#define kCustomProtocolScheme   @"wvjbscheme"
#define kQueueHasMessage        @"__WVJB_QUEUE_MESSAGE__"
#define kConsoleQueueHasMessage @"__WVJB_CONSOLE_QUEUE_MESSAGE__"
#define kQueueHasMessage      @"__WVJB_QUEUE_MESSAGE__"

#if !TARGET_OS_IPHONE
    #import <WebKit/WebKit.h>
    #define WVJB_PLATFORM_OSX
    #define WVJB_WEBVIEW_TYPE WebView
    #define WVJB_WEBVIEW_DELEGATE_TYPE NSObject
#else
    #import <UIKit/UIWebView.h>
    #define WVJB_PLATFORM_IOS
    #define WVJB_WEBVIEW_TYPE UIWebView
    #define WVJB_WEBVIEW_DELEGATE_TYPE NSObject<UIWebViewDelegate>
#endif

typedef void (^WVJBResponseCallback)(id responseData);
typedef void (^WVJBHandler)(id data, WVJBResponseCallback responseCallback);
typedef void (^WVJBJSConsoleMessageHandler)(NSString* type, NSString* message);
