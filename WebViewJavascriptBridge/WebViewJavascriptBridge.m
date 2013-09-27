//
//  WebViewJavascriptBridge.m
//  ExampleApp-iOS
//
//  Created by Marcus Westin on 6/14/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import "WebViewJavascriptBridge.h"

#if __has_feature(objc_arc_weak)
    #define WVJB_WEAK __weak
#else
    #define WVJB_WEAK __unsafe_unretained
#endif


@implementation WebViewJavascriptBridge {
    WVJB_WEAK WVJB_WEBVIEW_TYPE* _webView;
    WVJB_WEAK id _webViewDelegate;
    NSMutableArray* _startupMessageQueue;
    NSMutableDictionary* _responseCallbacks;
    NSMutableDictionary* _messageHandlers;
    long _uniqueId;
    WVJBHandler _messageHandler;
    BOOL _shouldLogConsoleMessagesToNSLog;
    WVJBJSConsoleMessageHandler _consoleLogHandler;
    
#if defined WVJB_PLATFORM_IOS
    NSUInteger _numRequestsLoading;
#endif
    
}

/* API
 *****/

static bool logging = false;
+ (void)enableLogging { logging = true; }

+ (instancetype)bridgeForWebView:(WVJB_WEBVIEW_TYPE*)webView handler:(WVJBHandler)handler {
    return [self bridgeForWebView:webView webViewDelegate:nil handler:handler];
}

+ (instancetype)bridgeForWebView:(WVJB_WEBVIEW_TYPE*)webView webViewDelegate:(WVJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(WVJBHandler)messageHandler {
    WebViewJavascriptBridge* bridge = [[WebViewJavascriptBridge alloc] init];
    [bridge _platformSpecificSetup:webView webViewDelegate:webViewDelegate handler:messageHandler];
    [bridge reset];
    return bridge;
}

- (void)send:(NSDictionary *)data {
    [self send:data responseCallback:nil];
}

- (void)send:(NSDictionary *)data responseCallback:(WVJBResponseCallback)responseCallback {
    [self _sendData:data responseCallback:responseCallback handlerName:nil];
}

- (void)callHandler:(NSString *)handlerName {
    [self callHandler:handlerName data:nil responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data {
    [self callHandler:handlerName data:data responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data responseCallback:(WVJBResponseCallback)responseCallback {
    [self _sendData:data responseCallback:responseCallback handlerName:handlerName];
}

- (void)registerHandler:(NSString *)handlerName handler:(WVJBHandler)handler {
    _messageHandlers[handlerName] = [handler copy];
}

- (void)setJSConsoleMessageHandler:(WVJBJSConsoleMessageHandler)handler {
    _consoleLogHandler = handler;
}

- (void)setShouldLogJSConsoleMessagesToNSLog:(BOOL)shouldLog {
    _shouldLogConsoleMessagesToNSLog = shouldLog;
}

- (void)reset {
    _startupMessageQueue = [NSMutableArray array];
    _responseCallbacks = [NSMutableDictionary dictionary];
    _uniqueId = 0;
}

/* Platform agnostic internals
 *****************************/

- (void)dealloc {
    [self _platformSpecificDealloc];
    
    _webView = nil;
    _webViewDelegate = nil;
    _startupMessageQueue = nil;
    _responseCallbacks = nil;
    _messageHandlers = nil;
    _messageHandler = nil;
    _consoleLogHandler = nil;
}

- (void)_sendData:(NSDictionary *)data responseCallback:(WVJBResponseCallback)responseCallback handlerName:(NSString*)handlerName {
    NSMutableDictionary* message = [NSMutableDictionary dictionaryWithObject:data forKey:@"data"];
    
    if (responseCallback) {
        NSString* callbackId = [NSString stringWithFormat:@"objc_cb_%ld", ++_uniqueId];
        _responseCallbacks[callbackId] = [responseCallback copy];
        message[@"callbackId"] = callbackId;
    }
    
    if (handlerName) {
        message[@"handlerName"] = handlerName;
    }
    [self _queueMessage:message];
}

- (void)_queueMessage:(NSDictionary *)message {
    if (_startupMessageQueue) {
        [_startupMessageQueue addObject:message];
    } else {
        [self _dispatchMessage:message];
    }
}

- (void)_dispatchMessage:(NSDictionary *)message {
    NSString *messageJSON = [self _serializeMessage:message];
    [self _log:@"sending" json:messageJSON];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\'" withString:@"\\\'"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\f" withString:@"\\f"];

    NSString* javascriptCommand = [NSString stringWithFormat:@"WebViewJavascriptBridge._handleMessageFromObjC('%@');", messageJSON];
    if ([[NSThread currentThread] isMainThread]) {
        [_webView stringByEvaluatingJavaScriptFromString:javascriptCommand];
    } else {
        __strong WVJB_WEBVIEW_TYPE* strongWebView = _webView;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [strongWebView stringByEvaluatingJavaScriptFromString:javascriptCommand];
        });
    }
}

- (void)_flushMessageQueue {
    NSString *messageQueueString = [_webView stringByEvaluatingJavaScriptFromString:@"WebViewJavascriptBridge._fetchQueue();"];
    
    NSArray* messages = [messageQueueString componentsSeparatedByString:kMessageSeparator];
    for (NSString *messageJSON in messages) {
        [self _log:@"receivd" json:messageJSON];
        
        NSDictionary* message = [self _deserializeMessageJSON:messageJSON];
        
        NSString* responseId = message[@"responseId"];
        if (responseId) {
            WVJBResponseCallback responseCallback = _responseCallbacks[responseId];
            responseCallback(message[@"responseData"]);
            [_responseCallbacks removeObjectForKey:responseId];
        } else {
            WVJBResponseCallback responseCallback = NULL;
            NSString* callbackId = message[@"callbackId"];
            if (callbackId) {
                responseCallback = ^(id responseData) {
                    NSDictionary* msg = @{ @"responseId":callbackId, @"responseData":responseData };
                    [self _queueMessage:msg];
                };
            } else {
                responseCallback = ^(id ignoreResponseData) {
                    // Do nothing
                };
            }
            
            WVJBHandler handler;
            if (message[@"handlerName"]) {
                handler = _messageHandlers[message[@"handlerName"]];
                if (!handler) {
                    NSLog(@"WVJB Warning: No handler for %@", message[@"handlerName"]);
                    return responseCallback(@{});
                }
            } else {
                handler = _messageHandler;
            }
            
            @try {
                NSDictionary* data = message[@"data"];
                if (!data || ((id)data) == [NSNull null]) { data = [NSDictionary dictionary]; }
                handler(data, responseCallback);
            }
            @catch (NSException *exception) {
                NSLog(@"WebViewJavascriptBridge: WARNING: objc handler threw. %@ %@", message, exception);
            }
        }
    }
}

- (void)_flushConsoleMessageQueue
{
    NSString *messageQueueString = [_webView stringByEvaluatingJavaScriptFromString:@"WebViewJavascriptBridge._fetchConsoleQueue();"];
    
    NSArray* messages = [messageQueueString componentsSeparatedByString:kMessageSeparator];
    for (NSString* messageJSON in messages) {
        NSDictionary* messageDict = [self _deserializeMessageJSON:messageJSON];
        if (_shouldLogConsoleMessagesToNSLog)
            NSLog(@"WVJB:JSConsoleLog: %@: %@",messageDict[@"type"],messageDict[@"message"]);
        if (_consoleLogHandler)
            _consoleLogHandler(messageDict[@"type"],messageDict[@"message"]);
    }
}

- (NSString *)_serializeMessage:(NSDictionary *)message {
#if defined _JSONKIT_H_
    return [message JSONString];
#else
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] encoding:NSUTF8StringEncoding];
#endif
}

- (NSDictionary *)_deserializeMessageJSON:(NSString *)messageJSON {
#if defined _JSONKIT_H_
    return [messageJSON objectFromJSONString];
#else
    return [NSJSONSerialization JSONObjectWithData:[messageJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
#endif
}

- (void)_log:(NSString *)action json:(NSString *)json {
    if (!logging) { return; }
    if (json.length > 500) {
        NSLog(@"WVJB %@: %@", action, [[json substringToIndex:500] stringByAppendingString:@" [...]"]);
    } else {
        NSLog(@"WVJB %@: %@", action, json);
    }
}



/* Platform specific internals: OSX
 **********************************/
#if defined WVJB_PLATFORM_OSX

- (void) _platformSpecificSetup:(WVJB_WEBVIEW_TYPE*)webView webViewDelegate:(WVJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(WVJBHandler)messageHandler {
    _messageHandler = messageHandler;
    _webView = webView;
    _webViewDelegate = webViewDelegate;
    _messageHandlers = [NSMutableDictionary dictionary];
    
    _webView.frameLoadDelegate = self;
    _webView.resourceLoadDelegate = self;
    _webView.policyDelegate = self;
}

- (void) _platformSpecificDealloc {
    _webView.frameLoadDelegate = nil;
    _webView.resourceLoadDelegate = nil;
    _webView.policyDelegate = nil;
}

- (void)webView:(WebView *)webView didFinishLoadForFrame:(WebFrame *)frame
{
    if (webView != _webView) { return; }
    
    if (![[webView stringByEvaluatingJavaScriptFromString:@"typeof WebViewJavascriptBridge == 'object'"] isEqualToString:@"true"]) {
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"WebViewJavascriptBridge.js" ofType:@"txt"];
        NSString *js = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        [webView stringByEvaluatingJavaScriptFromString:js];
    }
    
    if (_startupMessageQueue) {
        for (id queuedMessage in _startupMessageQueue) {
            [self _dispatchMessage:queuedMessage];
        }
        _startupMessageQueue = nil;
    }
    
    if (_webViewDelegate && [_webViewDelegate respondsToSelector:@selector(webView:didFinishLoadForFrame:)]) {
        [_webViewDelegate webView:webView didFinishLoadForFrame:frame];
    }
}

- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    if (webView != _webView) { return; }
    
    NSURL *url = [request URL];
    if ([[url scheme] isEqualToString:kCustomProtocolScheme]) {
        if ([[url host] isEqualToString:kQueueHasMessage]) {
            [self _flushMessageQueue];
        } else if ([[url host] isEqualToString:kConsoleQueueHasMessage]) {
            [self _flushConsoleMessageQueue];
        } else {
            NSLog(@"WebViewJavascriptBridge: WARNING: Received unknown WebViewJavascriptBridge command %@", [url absoluteString]);
        }
        [listener ignore];
    } else if (_webViewDelegate && [_webViewDelegate respondsToSelector:@selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:)]) {
        [_webViewDelegate webView:webView decidePolicyForNavigationAction:actionInformation request:request frame:frame decisionListener:listener];
    } else {
        [listener use];
    }
}


/* Platform specific internals: OSX
 **********************************/
#elif defined WVJB_PLATFORM_IOS

- (void) _platformSpecificSetup:(WVJB_WEBVIEW_TYPE*)webView webViewDelegate:(id<UIWebViewDelegate>)webViewDelegate handler:(WVJBHandler)messageHandler {
    _messageHandler = messageHandler;
    _webView = webView;
    _webViewDelegate = webViewDelegate;
    _messageHandlers = [NSMutableDictionary dictionary];
    _webView.delegate = self;
}

- (void) _platformSpecificDealloc {
    _webView.delegate = nil;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (webView != _webView) { return; }
    
    _numRequestsLoading--;
    
    if (_numRequestsLoading == 0 && ![[webView stringByEvaluatingJavaScriptFromString:@"typeof WebViewJavascriptBridge == 'object'"] isEqualToString:@"true"]) {
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"WebViewJavascriptBridge.js" ofType:@"txt"];
        NSString *js = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        [webView stringByEvaluatingJavaScriptFromString:js];
    }
    
    if (_startupMessageQueue) {
        for (id queuedMessage in _startupMessageQueue) {
            [self _dispatchMessage:queuedMessage];
        }
        _startupMessageQueue = nil;
    }
    
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [strongDelegate webViewDidFinishLoad:webView];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (webView != _webView) { return; }
    
    _numRequestsLoading--;
    
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [strongDelegate webView:webView didFailLoadWithError:error];
    }
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    if (webView != _webView) { return YES; }
    NSURL *url = [request URL];
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;
    if ([[url scheme] isEqualToString:kCustomProtocolScheme]) {
        if ([[url host] isEqualToString:kQueueHasMessage]) {
            [self _flushMessageQueue];
        } else if ([[url host] isEqualToString:kConsoleQueueHasMessage]) {
            [self _flushConsoleMessageQueue];
        } else {
            NSLog(@"WebViewJavascriptBridge: WARNING: Received unknown WebViewJavascriptBridge command %@", [url absoluteString]);
        }
        return NO;
    } else if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
        return [strongDelegate webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
    } else {
        return YES;
    }
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
    if (webView != _webView) { return; }
    
    _numRequestsLoading++;
    
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [strongDelegate webViewDidStartLoad:webView];
    }
}

#endif

// John Turnipseed <johnt@me.com> - 09/27/2013
//
// These methods were added in order to relay delegate methods to the WebViewDelegate that WebViewJavascriptBridge doesn't
// actually implement. In order to do this, it either has to implement every possible delegate method and forward them the
// actual delegate if it responds to them. This approach would be tedious and liable to break whenever new delegate methods
// are added.
//
// The alternative is the approach below which overrides "respondsToSelector:" and lies to the runtime by telling it we support
// anything that our delegate supports. When the runtime tries to call the selector and finds it doesn't really exists, it then
// calls methodSignatureForSelector: and forwardInvocation: where we then relay the calls to our delegate

- (BOOL)respondsToSelector:(SEL)aSelector
{
    // It may not be obvious, but calling [super respondsToSelector:xxx] actually invokes NSObject's implementation
    // of the respondsToSelector: method, which still checks our subclass... not just our NSObject superclass.
    if ([super respondsToSelector:aSelector] || [_webViewDelegate respondsToSelector:aSelector])
        return YES;
    
//  Uncommenting the line below may yeild tales of some interesting WebView delegate methods... "here be dragons"
//  NSLog(@"WebViewJavascriptBridge:respondsToSelector: called for unsupported selector: '%@'", NSStringFromSelector(aSelector));
    return NO;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    if ([_webViewDelegate respondsToSelector:aSelector])
        return [_webViewDelegate methodSignatureForSelector:aSelector];
    
    // This shouldn't happen, but if it ever does, we need to return a dummy NSMethodSignage. Returning nil would raise
    // an exception. The dummy invocation will do nothing if invoked.
    NSLog(@"WebViewJavascriptBridge:methodSignatureForSelector: called for unhandled selector: '%@'", NSStringFromSelector(aSelector));
    return [NSMethodSignature signatureWithObjCTypes:"@^v^c"];;
}

- (void)forwardInvocation:(NSInvocation *)invocation;
{
    if ([_webViewDelegate respondsToSelector:[invocation selector]])
    {
        [invocation invokeWithTarget:_webViewDelegate];
        return;
    }
    
    [invocation invokeWithTarget:nil];
}

@end
