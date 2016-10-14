import Cocoa
import Hangouts
import WebKit

public class Authenticator {
	
	private static let GROUP_DOMAIN = "group.com.avaidyam.Parrot"
	private static let ACCESS_TOKEN = "access_token"
	private static let REFRESH_TOKEN = "refresh_token"
	
	private static let OAUTH2_SCOPE = "https%3A%2F%2Fwww.google.com%2Faccounts%2FOAuthLogin+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.email"
                                    //"https://www.google.com/accounts/OAuthLogin+https://www.googleapis.com/auth/userinfo.email"
	private static let OAUTH2_CLIENT_ID = "936475272427.apps.googleusercontent.com"
	private static let OAUTH2_CLIENT_SECRET = "KWsJlkaMn1jGLxQpWxMnOox-"
	private static let OAUTH2_LOGIN_URL = "https://accounts.google.com/o/oauth2/programmatic_auth?client_id=\(OAUTH2_CLIENT_ID)&scope=\(OAUTH2_SCOPE)"
	private static let OAUTH2_TOKEN_REQUEST_URL = "https://accounts.google.com/o/oauth2/token"
	
	private static var window: NSWindow? = nil
	private static var validURL: URL? = nil
	private static var handler: ((_ oauth_code: String) -> Void)? = nil
	private static var delegate = WebDelegate()
	
	class WebDelegate: NSObject, WebPolicyDelegate, WebResourceLoadDelegate {
		/*
        func webView(
			_ webView: WebView!,
			decidePolicyForNavigationAction actionInformation: [NSObject : AnyObject]!,
			request: URLRequest!,
			frame: WebFrame!,
			decisionListener listener: WebPolicyDecisionListener!) {
				guard	let url = request.url?.absoluteString,
						let val = validURL?.absoluteString
				else { listener.use(); return }
			// TEMP FIX
            log.info("auth: \(url)")
				if url.contains(val) && url.contains("from_login=1") {
					listener.ignore()
					handler?(request)
					window?.close()
				} else {
					listener.use()
				}
		}
        */
        
        func webView(_ sender: WebView!, resource identifier: Any!, didFinishLoadingFrom dataSource: WebDataSource!) {
            guard   let cookiejar = dataSource.response as? HTTPURLResponse,
                    let cookies = cookiejar.allHeaderFields["Set-Cookie"] as? String,
                    let cookie = cookies.substring(between: "oauth_code=", and: ";")
            else { return }
            handler?(cookie)
            sender.close()
        }
	}
	
	/**
	Load access_token and refresh_token for OAuth2.
	- returns: Tuple containing tokens, or nil on failure.
	*/
	public class func loadTokens() -> (access_token: String, refresh_token: String)? {
		let at = SecureSettings[ACCESS_TOKEN, domain: GROUP_DOMAIN] as? String
		let rt = SecureSettings[REFRESH_TOKEN, domain: GROUP_DOMAIN] as? String
		
		if let at = at, let rt = rt {
			return (access_token: at, refresh_token: rt)
		} else {
			clearTokens()
			return nil
		}
	}
	
	/**
	Store access_token and refresh_token for OAuth2.
	- parameter access_token the OAuth2 access token
	- parameter refresh_token the OAuth2 refresh token
	*/
	public class func saveTokens(_ access_token: String, refresh_token: String) {
		SecureSettings[ACCESS_TOKEN, domain: GROUP_DOMAIN] = access_token
		SecureSettings[REFRESH_TOKEN, domain: GROUP_DOMAIN] = refresh_token
	}
	
	/**
	Clear the existing auth_token and refresh_token for OAuth2.
	*/
	public class func clearTokens() {
		SecureSettings[ACCESS_TOKEN, domain: GROUP_DOMAIN] = nil
		SecureSettings[REFRESH_TOKEN, domain: GROUP_DOMAIN] = nil
	}
	
	public class func authenticateClient(_ cb: @escaping (_ configuration: URLSessionConfiguration) -> Void) {
		
		// Prepare the manager for any requests.
		let cfg = URLSessionConfiguration.default
		cfg.httpCookieStorage = HTTPCookieStorage.shared
		cfg.httpAdditionalHeaders = _defaultHTTPHeaders
		let session = URLSession(configuration: cfg)
		
		if let code = loadTokens() {
			
			// If we already have the tokens stored, authenticate.
			//  - second: authenticate(manager, refresh_token)
			authenticate(session: session, refresh_token: code.refresh_token) { (access_token: String, refresh_token: String) in
				saveTokens(access_token, refresh_token: refresh_token)
				
				let url = "https://accounts.google.com/accounts/OAuthLogin?source=hangups&issueuberauth=1"
				var request = URLRequest(url: URL(string: url)! as URL)
				request.setValue("Bearer \(access_token)", forHTTPHeaderField: "Authorization")
				
				session.request(request: request) {
					guard let data = $0.data else {
						log.info("Request failed with error: \($0.error!)")
						return
					}
					
					var uberauth = NSString(data: data, encoding: String.Encoding.utf8.rawValue)! as String
					uberauth.replaceSubrange(uberauth.index(uberauth.endIndex, offsetBy: -1) ..< uberauth.endIndex, with: "")
                    
                    let url = "https://accounts.google.com/MergeSession?service=mail&continue=http://www.google.com&uberauth=\(uberauth)"
                    var request = URLRequest(url: URL(string: url)!)
                    request.setValue("Bearer \(access_token)", forHTTPHeaderField: "Authorization")
                    
                    session.request(request: request) {
                        guard let _ = $0.data else {
                            log.info("Request failed with error: \($0.error!)")
                            return
                        }
                        cb(session.configuration)
                    }
				}
			}
		} else {
			
			// Otherwise, we need to authenticate, so use the callback to do so.
			let a = URL(string: OAUTH2_LOGIN_URL)!
			let b = URL(string: "https://accounts.google.com/o/oauth2/programmatic_auth")!
			
			prompt(url: a, valid: b) { oauth_code in
                //  - first: authenticate(auth_code)
                authenticate(auth_code: oauth_code, cb: { (access_token, refresh_token) in
                    saveTokens(access_token, refresh_token: refresh_token)
                    cb(session.configuration)
                })
			}
		}
	}
	
	/**
	Authenticate OAuth2 using an authentication code.
	- parameter auth_code the authentication code
	- parameter cb a callback to execute upon completion
	*/
	private class func authenticate(auth_code: String, cb: @escaping (_ access_token: String, _ refresh_token: String) -> Void) {
		let token_request_data = [
			"client_id": OAUTH2_CLIENT_ID,
			"client_secret": OAUTH2_CLIENT_SECRET,
			"code": auth_code,
			"grant_type": "authorization_code",
			"redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
		]
		
		// Make request first.
		var req = URLRequest(url: URL(string: OAUTH2_TOKEN_REQUEST_URL)! as URL)
		req.httpMethod = "POST"
		req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		req.httpBody = query(parameters: token_request_data).data(using: .utf8)
		
		URLSession.shared.request(request: req) {
			guard let data = $0.data else {
				log.info("Request failed with error: \($0.error!)")
				return
			}
			
			do {
				let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]
				if let access = json[ACCESS_TOKEN] as? String, let refresh = json[REFRESH_TOKEN] as? String  {
					cb(access, refresh)
				} else {
					log.info("JSON was invalid (auth): \(json)")
				}
			} catch let error as NSError {
				log.info("JSON returned invalid data: \(error.localizedDescription)")
			}
		}
	}
	
	/**
	Authenticate OAuth2 using a refresh_token.
	- parameter manager the Alamofire manager for the OAuth2 request
	- parameter refresh_token the specified refresh_token
	- parameter cb a callback to execute upon completion
	*/
	private class func authenticate(session: URLSession, refresh_token: String, cb: @escaping (_ access_token: String, _ refresh_token: String) -> Void) {
		let token_request_data = [
			"client_id": OAUTH2_CLIENT_ID,
			"client_secret": OAUTH2_CLIENT_SECRET,
			"grant_type": REFRESH_TOKEN,
			REFRESH_TOKEN: refresh_token,
		]
		
		// Make request first.
		var req = URLRequest(url: URL(string: OAUTH2_TOKEN_REQUEST_URL)! as URL)
		req.httpMethod = "POST"
		req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
		req.httpBody = query(parameters: token_request_data).data(using: .utf8)
		
		session.request(request: req) {
			guard let data = $0.data else {
				log.info("Request failed with error: \($0.error!)")
				return
			}
			
			do {
				let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String: Any]
				if let access = json[ACCESS_TOKEN] as? String  {
					cb(access, refresh_token)
				} else {
					log.info("JSON was invalid (refresh): \(json)")
				}
			} catch let error as NSError {
				log.info("JSON returned invalid data: \(error.localizedDescription)")
			}
		}
	}
	
	private class func prompt(url: URL, valid: URL, cb: @escaping (_ oauth_code: String) -> Void) {
		validURL = valid as URL
		handler = cb
		
		let webView = WebView(frame: NSMakeRect(0, 0, 386, 512))
		webView.autoresizingMask = [.viewHeightSizable, .viewWidthSizable]
		//webView.policyDelegate = delegate
        webView.resourceLoadDelegate = delegate
		
		window = NSWindow(contentRect: NSMakeRect(0, 0, 386, 512),
			styleMask: [.titled, .closable],
			backing: .buffered, defer: false)
		window?.title = "Login to Parrot"
		window?.isOpaque = false
		window?.isMovableByWindowBackground = true
		window?.contentView = webView
		window?.center()
		window?.titlebarAppearsTransparent = true
		window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
		window?.standardWindowButton(.zoomButton)?.isHidden = true
		window?.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
		window?.makeKeyAndOrderFront(nil)
        
        // load at the end!
        webView.mainFrame.load(URLRequest(url: url as URL))
	}
}
