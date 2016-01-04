#import "ExampleAppDelegate.h"
#import "ExampleAppViewController.h"
#import "WebViewJavascriptBridge.h"

@interface ExampleAppDelegate ()
{
    WebViewJavascriptBridge* _bridge;
}

@end

@implementation ExampleAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UIWebView* webView = [[UIWebView alloc] initWithFrame:self.window.bounds];
    [self.window addSubview:webView];
    
    [WebViewJavascriptBridge enableLogging];
    
    _bridge = [WebViewJavascriptBridge bridgeForWebView:webView handler:^(id data, WVJBResponseCallback responseCallback) {
        NSLog(@"ObjC received message from JS: %@", data);
        responseCallback(@"Response for message from ObjC");
    }];

    [_bridge setShouldLogJSConsoleMessagesToNSLog:NO];
    
    [_bridge setJSConsoleMessageHandler:^(NSString* type, NSString* message){
        NSLog(@"ExampleAppDelegate:JSConsoleLog: '%@' - %@", type, message);
    }];
    
    [_bridge registerHandler:@"testObjcCallback" handler:^(id data, WVJBResponseCallback responseCallback) {
        NSLog(@"testObjcCallback called: %@", data);
        responseCallback(@"Response from testObjcCallback");
    }];
    
    [_bridge send:@"A string sent from ObjC before Webview has loaded." responseCallback:^(id responseData) {
        NSLog(@"objc got response! %@", responseData);
    }];
    
    [_bridge callHandler:@"testJavascriptHandler" data:[NSDictionary dictionaryWithObject:@"before ready" forKey:@"foo"]];
    
//    [self renderButtons:webView];
//    [self loadExamplePage:webView];
    
    [_bridge send:@"A string sent from ObjC after Webview has loaded."];
    
    [self.window makeKeyAndVisible];
    return YES;
}

@end
