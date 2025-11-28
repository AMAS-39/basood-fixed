import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../core/utils/jwt_utils.dart';
import 'auth/auth_controller.dart';
import '../../services/notification_service.dart';

class WebViewScreen extends ConsumerStatefulWidget {
  const WebViewScreen({super.key});

  @override
  ConsumerState<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends ConsumerState<WebViewScreen> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  final _storage = const FlutterSecureStorage();
  PullToRefreshController? _pullToRefreshController;

  String? _initialUrl;
  String? _currentUrl;
  bool _isLoggingOut = false; // Flag to prevent logout loops

  @override
  void initState() {
    super.initState();
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        enabled: true,
      ),
      onRefresh: () async {
        if (_webViewController != null) {
          await _webViewController!.reload();
        }
      },
    );
    
    // Register callback for notification taps to refresh WebView
    NotificationService.setNotificationTapCallback(() {
      if (mounted && _webViewController != null) {
        _webViewController!.reload();
      }
    });
    
    // Defer provider reads until after build completes to prevent Riverpod errors
    Future.microtask(() {
      _requestPermissionsAndInitialize();
    });
  }
  
  @override
  void dispose() {
    // Clear notification callback when screen is disposed
    NotificationService.setNotificationTapCallback(null);
    super.dispose();
  }

  Future<void> _requestPermissionsAndInitialize() async {
    // Request camera and microphone permissions at runtime before loading WebView
    await _requestPermissions();
    // Initialize URL after permissions are requested
    await _initializeUrl();
  }

  Future<void> _requestPermissions() async {
    try {
      final permissions = await [
        Permission.camera,
        Permission.microphone,
      ].request();
      
      debugPrint('Camera permission: ${permissions[Permission.camera]}');
      debugPrint('Microphone permission: ${permissions[Permission.microphone]}');
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      // Continue anyway - WebView will handle permission requests natively
    }
  }

  Future<void> _initializeUrl() async {
    if (!mounted) return;
    
    // Also check token from storage as backup (don't read provider during init)
    final accessToken = await _storage.read(key: 'access_token');
    
    // Determine URL based on token validity
    if (accessToken != null && !JwtUtils.isTokenExpired(accessToken)) {
      _initialUrl = 'https://basood-order-test-2025-2026.netlify.app/';
    } else {
      _initialUrl = 'https://basood-order-test-2025-2026.netlify.app/login';
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _injectLogoutListener(InAppWebViewController controller) async {
    // Inject JavaScript to listen for logout button clicks ONLY
    // DO NOT automatically detect /login URL - that causes infinite loops
    await controller.evaluateJavascript(source: '''
      (function() {
        // Only listen for logout button clicks - don't auto-detect /login URL
        document.addEventListener('click', function(e) {
          var target = e.target;
          // Check if clicked element or parent contains logout text
          while (target) {
            var text = target.textContent || target.innerText || '';
            var href = target.href || '';
            var className = target.className || '';
            
            if (text.toLowerCase().includes('logout') || 
                text.toLowerCase().includes('خروج') ||
                href.toLowerCase().includes('logout') ||
                className.toLowerCase().includes('logout')) {
              // Notify Flutter app only when user clicks logout button
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('logout');
              }
              break;
            }
            target = target.parentElement;
          }
        });
      })();
    ''');
  }

  Future<void> _injectLoginSyncListener(InAppWebViewController controller) async {
    // Inject JavaScript to detect login and sync tokens
    await controller.evaluateJavascript(source: '''
      (function() {
        // Function to extract token from cookies
        function getCookie(name) {
          var value = "; " + document.cookie;
          var parts = value.split("; " + name + "=");
          if (parts.length == 2) return parts.pop().split(";").shift();
          return null;
        }
        
        // Function to extract token from localStorage
        function getFromLocalStorage(key) {
          try {
            return localStorage.getItem(key);
          } catch (e) {
            return null;
          }
        }
        
        // Function to sync tokens to Flutter
        function syncTokensToFlutter() {
          // Try to get access token from various possible locations
          var accessToken = getCookie('access_token') || 
                          getCookie('accessToken') || 
                          getCookie('token') ||
                          getFromLocalStorage('access_token') ||
                          getFromLocalStorage('accessToken') ||
                          getFromLocalStorage('token');
          
          var refreshToken = getCookie('refresh_token') || 
                            getCookie('refreshToken') ||
                            getFromLocalStorage('refresh_token') ||
                            getFromLocalStorage('refreshToken');
          
          // Also check Authorization header if stored
          if (!accessToken) {
            try {
              var authHeader = getFromLocalStorage('Authorization');
              if (authHeader && authHeader.startsWith('Bearer ')) {
                accessToken = authHeader.substring(7);
              }
            } catch (e) {}
          }
          
          // If we found tokens, send them to Flutter
          if (accessToken && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('syncTokens', {
              accessToken: accessToken,
              refreshToken: refreshToken || ''
            });
          }
        }
        
        // Monitor URL changes to detect successful login
        var lastUrl = window.location.href;
        var checkInterval = setInterval(function() {
          var currentUrl = window.location.href;
          
          // If URL changed from /login to something else, user likely logged in
          if (lastUrl.includes('/login') && !currentUrl.includes('/login')) {
            // Wait a bit for tokens to be set, then sync
            setTimeout(syncTokensToFlutter, 1000);
          }
          
          // Also periodically check for tokens (every 5 seconds)
          if (currentUrl && !currentUrl.includes('/login')) {
            syncTokensToFlutter();
          }
          
          lastUrl = currentUrl;
        }, 2000);
        
        // Also sync immediately on page load if not on login page
        if (!window.location.href.includes('/login')) {
          setTimeout(syncTokensToFlutter, 2000);
        }
      })();
    ''');
  }

  void _handleLogout() {
    // Prevent multiple logout calls
    if (_isLoggingOut) return;
    
    // Defer provider state modification to prevent Riverpod errors
    Future.microtask(() {
      if (!mounted || _isLoggingOut) return;
      
      final currentUrl = _currentUrl ?? '';
      final isAlreadyOnLogin = currentUrl.contains('/login');
      
      // Only reload if we're not already on login page
      if (!isAlreadyOnLogin) {
        _isLoggingOut = true;
        
        // Call logout from auth controller
        ref.read(authControllerProvider.notifier).logout();
        
        // Reload webview to show login page
        _webViewController?.loadUrl(
          urlRequest: URLRequest(
            url: WebUri('https://basood-order-test-2025-2026.netlify.app/login'),
          ),
        );
        
        // Reset flag after a delay
        Future.delayed(const Duration(seconds: 2), () {
          _isLoggingOut = false;
        });
      } else {
        // Already on login page, just clear auth state
        ref.read(authControllerProvider.notifier).logout();
      }
    });
  }

  void _handleTokenSync(List<dynamic> args) {
    // Handle token sync from WebView login
    if (args.isEmpty) return;
    
    try {
      final data = args[0] as Map<String, dynamic>?;
      if (data == null) return;
      
      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      
      if (accessToken == null || accessToken.isEmpty) return;
      
      // Defer to avoid Riverpod errors
      Future.microtask(() async {
        if (!mounted) return;
        
        try {
          debugPrint('🔄 Syncing tokens from WebView login...');
          
          // Check if token is valid
          if (JwtUtils.isTokenExpired(accessToken)) {
            debugPrint('⚠️ Token from WebView is expired, ignoring');
            return;
          }
          
          // Store tokens in secure storage
          await _storage.write(key: 'access_token', value: accessToken);
          if (refreshToken != null && refreshToken.isNotEmpty) {
            await _storage.write(key: 'refresh_token', value: refreshToken);
          }
          
          // Update provider state
          ref.read(authControllerProvider.notifier).syncTokensFromWebView(
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
          
          debugPrint('✅ Tokens synced successfully from WebView');
        } catch (e) {
          debugPrint('❌ Error syncing tokens: $e');
        }
      });
    } catch (e) {
      debugPrint('❌ Error handling token sync: $e');
    }
  }

  Future<void> _checkCookiesForTokens(InAppWebViewController controller) async {
    // Backup method: Check cookies directly from Flutter side
    try {
      final cookieManager = CookieManager.instance();
      final url = WebUri('https://basood-order-test-2025-2026.netlify.app');
      
      // Get all cookies for the domain
      final cookies = await cookieManager.getCookies(url: url);
      
      String? accessToken;
      String? refreshToken;
      
      // Look for common token cookie names
      for (final cookie in cookies) {
        final name = cookie.name.toLowerCase();
        final value = cookie.value;
        
        if (name.contains('access') && name.contains('token')) {
          accessToken = value;
        } else if (name.contains('refresh') && name.contains('token')) {
          refreshToken = value;
        } else if (name == 'token' && accessToken == null) {
          accessToken = value;
        }
      }
      
      // If we found tokens in cookies, sync them
      if (accessToken != null && accessToken.isNotEmpty) {
        // Check if we already have this token stored
        final storedToken = await _storage.read(key: 'access_token');
        if (storedToken != accessToken && !JwtUtils.isTokenExpired(accessToken)) {
          debugPrint('🔄 Found tokens in cookies, syncing...');
          await _storage.write(key: 'access_token', value: accessToken);
          if (refreshToken != null && refreshToken.isNotEmpty) {
            await _storage.write(key: 'refresh_token', value: refreshToken);
          }
          
          // Update provider state
          ref.read(authControllerProvider.notifier).syncTokensFromWebView(
            accessToken: accessToken,
            refreshToken: refreshToken,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error checking cookies: $e');
      // Don't throw - this is a backup method
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          if (_webViewController != null) {
            final canGoBack = await _webViewController!.canGoBack();
            if (canGoBack) {
              _webViewController!.goBack();
            } else {
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            }
          } else {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          top: true,
          bottom: true,
          child: _initialUrl == null
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : Stack(
                  children: [
                    InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_initialUrl!),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      iframeAllow: "camera; microphone",
                      iframeAllowFullscreen: true,
                      useHybridComposition: true,
                      safeBrowsingEnabled: true,
                      domStorageEnabled: true,
                      // Camera and media access settings
                      thirdPartyCookiesEnabled: true,
                      // Respect system UI insets (status bar, navigation bar)
                      useShouldOverrideUrlLoading: true,
                      verticalScrollBarEnabled: true,
                      horizontalScrollBarEnabled: true,
                    ),
                    pullToRefreshController: _pullToRefreshController,
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                      // Add JavaScript handler for logout
                      controller.addJavaScriptHandler(
                        handlerName: 'logout',
                        callback: (args) {
                          _handleLogout();
                        },
                      );
                      // Add JavaScript handler to sync tokens from WebView login
                      controller.addJavaScriptHandler(
                        handlerName: 'syncTokens',
                        callback: (args) {
                          _handleTokenSync(args);
                        },
                      );
                    },
                    onLoadStart: (controller, url) {
                      final urlString = url.toString();
                      final previousUrl = _currentUrl ?? '';
                      
                      setState(() {
                        _isLoading = true;
                        _hasError = false;
                        _errorMessage = null;
                        _currentUrl = urlString;
                      });
                      
                      // Only logout if user navigated FROM authenticated page TO login page
                      // Don't logout if already on login page or if we're logging out
                      if (urlString.contains('/login') && 
                          previousUrl.isNotEmpty &&
                          !previousUrl.contains('/login') &&
                          !_isLoggingOut) {
                        // User navigated to login page from authenticated area, logout
                        Future.microtask(() {
                          _handleLogout();
                        });
                      }
                    },
                    onLoadStop: (controller, url) async {
                      setState(() {
                        _isLoading = false;
                        _currentUrl = url.toString();
                      });
                      _pullToRefreshController?.endRefreshing();
                      
                      // Reset logout flag when page loads successfully
                      _isLoggingOut = false;
                      
                      // Inject JavaScript to listen for logout
                      await _injectLogoutListener(controller);
                      
                      // Inject JavaScript to sync tokens from WebView login
                      await _injectLoginSyncListener(controller);
                      
                      // Also check cookies directly as backup (if not on login page)
                      if (!url.toString().contains('/login')) {
                        _checkCookiesForTokens(controller);
                      }
                    },
                    onReceivedError: (controller, request, error) {
                      debugPrint('WebView error: ${error.description}');
                      setState(() {
                        _isLoading = false;
                        _hasError = true;
                        _errorMessage = error.description;
                      });
                    },
                    androidOnPermissionRequest: (controller, origin, resources) async {
                      // Grant camera and microphone permissions automatically on Android
                      debugPrint('Android Permission request from $origin: ${resources.join(", ")}');
                      
                      // Check if camera permission is already granted
                      final cameraStatus = await Permission.camera.status;
                      if (!cameraStatus.isGranted) {
                        final result = await Permission.camera.request();
                        debugPrint('Camera permission requested: $result');
                      }
                      
                      // Check if microphone permission is already granted
                      final micStatus = await Permission.microphone.status;
                      if (!micStatus.isGranted) {
                        final result = await Permission.microphone.request();
                        debugPrint('Microphone permission requested: $result');
                      }
                      
                      return PermissionRequestResponse(
                        resources: resources,
                        action: PermissionRequestResponseAction.GRANT,
                      );
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      debugPrint('WebView Console: ${consoleMessage.message}');
                    },
                    onReceivedServerTrustAuthRequest: (controller, challenge) async {
                      return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                    },
                    // JavaScript handler for logout from webview
                    onJsAlert: (controller, jsAlertRequest) async {
                      // Check if it's a logout message
                      final message = jsAlertRequest.message?.toLowerCase() ?? '';
                      if (message.contains('logout')) {
                        _handleLogout();
                        return JsAlertResponse(handledByClient: true);
                      }
                      return JsAlertResponse(handledByClient: false);
                    },
                  ),
                  if (_isLoading)
              Container(
                color: Colors.white,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_hasError && !_isLoading)
              Container(
                color: Colors.white,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Network Error',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage?.contains('ERR_NAME_NOT_RESOLVED') == true
                              ? 'Unable to connect to the server. Please check your internet connection.'
                              : _errorMessage ?? 'An error occurred while loading the page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _hasError = false;
                              _errorMessage = null;
                              _isLoading = true;
                            });
                            _webViewController?.reload();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
                ],
              ),
        ),
      ),
    );
  }
}
