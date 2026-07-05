import Foundation
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import FirebaseCore

enum AuthError: LocalizedError {
    case missingRootViewController
    case authenticationFailed
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .missingRootViewController: return "Could not find root view controller to present sign in."
        case .authenticationFailed: return "Authentication failed. Please try again."
        case .userCancelled: return "Sign in was cancelled."
        }
    }
}

class AuthManager: NSObject, ObservableObject {
    @Published var currentUser: User?
    
    // For Apple Sign In
    private var currentNonce: String?
    private var appleSignInCompletion: ((Result<AuthDataResult, Error>) -> Void)?
    
    override init() {
        super.init()
        self.currentUser = Auth.auth().currentUser
        
        // Listen to auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
            }
        }
    }
    
    // MARK: - Google Sign In
    
    func signInWithGoogle(completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion(.failure(AuthError.authenticationFailed))
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            completion(.failure(AuthError.missingRootViewController))
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                let nsError = error as NSError
                if nsError.domain == kGIDSignInErrorDomain && nsError.code == GIDSignInError.canceled.rawValue {
                    completion(.failure(AuthError.userCancelled))
                } else {
                    completion(.failure(error))
                }
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                completion(.failure(AuthError.authenticationFailed))
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    completion(.failure(error))
                } else if let authResult = authResult {
                    completion(.success(authResult))
                } else {
                    completion(.failure(AuthError.authenticationFailed))
                }
            }
        }
    }
    
    // MARK: - Apple Sign In
    
    func signInWithApple(completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        self.appleSignInCompletion = completion
        self.currentNonce = randomNonceString()
        
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(currentNonce!)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            completion(.failure(AuthError.missingRootViewController))
            return
        }
        
        controller.presentationContextProvider = window
        controller.performRequests()
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("Error signing out: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            appleSignInCompletion?(.failure(AuthError.authenticationFailed))
            return
        }
        
        let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                  idToken: idTokenString,
                                                  rawNonce: nonce)
        
        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            if let error = error {
                self?.appleSignInCompletion?(.failure(error))
            } else if let authResult = authResult {
                self?.appleSignInCompletion?(.success(authResult))
            } else {
                self?.appleSignInCompletion?(.failure(AuthError.authenticationFailed))
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            appleSignInCompletion?(.failure(AuthError.userCancelled))
        } else {
            appleSignInCompletion?(.failure(error))
        }
    }
}

extension UIWindow: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self
    }
}
