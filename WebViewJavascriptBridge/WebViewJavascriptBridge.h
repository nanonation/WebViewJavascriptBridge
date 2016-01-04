//
//  WebViewJavascriptBridge.h
//  ExampleApp-iOS
//
//  Created by Marcus Westin on 6/14/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface WebViewJavascriptBridge : WVJB_WEBVIEW_DELEGATE_TYPE

+ (instancetype)bridgeForWebView:(WVJB_WEBVIEW_TYPE*)webView handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWebView:(WVJB_WEBVIEW_TYPE*)webView webViewDelegate:(WVJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(WVJBHandler)handler;
+ (instancetype)bridgeForWebView:(WVJB_WEBVIEW_TYPE*)webView webViewDelegate:(WVJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(WVJBHandler)handler resourceBundle:(NSBundle*)bundle;
+ (void)enableLogging;

- (void)setJSConsoleMessageHandler:(WVJBJSConsoleMessageHandler)handler;
- (void)setShouldLogJSConsoleMessagesToNSLog:(BOOL)shouldLog;

- (void)send:(id)message;
- (void)send:(id)message responseCallback:(WVJBResponseCallback)responseCallback;
- (void)registerHandler:(NSString*)handlerName handler:(WVJBHandler)handler;
- (void)callHandler:(NSString*)handlerName;
- (void)callHandler:(NSString*)handlerName data:(id)data;
- (void)callHandler:(NSString*)handlerName data:(id)data responseCallback:(WVJBResponseCallback)responseCallback;

@end
