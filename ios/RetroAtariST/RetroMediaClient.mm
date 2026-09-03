#import "RetroMediaClient.h"

#import <CommonCrypto/CommonDigest.h>
#import <MetalKit/MetalKit.h>
#import <Security/Security.h>

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

#include "frontend.h"

namespace {

NSString* const kBaseURL = @"https://media.crownparkcomputing.com";
NSString* const kSystem = @"atarist";
NSString* const kKeychainService = @"com.crownparkcomputing.retroatarist.retromedia.session";
NSString* const kRememberedEmail = @"RetroMediaEmail";

NSString* SafeString(id value) {
	return [value isKindOfClass:NSString.class] ? value : @"";
}

NSString* ApiError(NSHTTPURLResponse* response, NSData* data) {
	NSDictionary* json = data.length > 0
	    ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	NSString* message = SafeString(json[@"error"]);
	return message.length > 0 ? message
	                          : [NSString stringWithFormat:@"RetroMedia returned HTTP %ld",
	                                                       (long)response.statusCode];
}

NSString* EncodeComponent(NSString* value) {
	NSMutableCharacterSet* allowed = NSCharacterSet.alphanumericCharacterSet.mutableCopy;
	[allowed addCharactersInString:@"-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

NSString* EncodeRelativePath(NSString* value) {
	NSMutableArray<NSString*>* parts = NSMutableArray.array;
	for (NSString* part in [value componentsSeparatedByString:@"/"]) {
		[parts addObject:EncodeComponent(part)];
	}
	return [parts componentsJoinedByString:@"/"];
}

NSString* Sha256(NSString* value) {
	NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH]{};
	CC_SHA256(data.bytes, static_cast<CC_LONG>(data.length), digest);
	NSMutableString* result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (unsigned char byte : digest) [result appendFormat:@"%02x", byte];
	return result;
}

NSString* CanonicalName(NSString* value) {
	NSString* name = value.stringByDeletingPathExtension.lowercaseString;
	for (NSString* pattern in @[@"\\([^)]*\\)", @"\\[[^]]*\\]"]) {
		NSRegularExpression* expression =
		    [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
		if (expression != nil) {
			name = [expression stringByReplacingMatchesInString:name options:0
			                                        range:NSMakeRange(0, name.length)
			                                 withTemplate:@" "];
		}
	}
	name = [[name componentsSeparatedByCharactersInSet:
	              [NSCharacterSet alphanumericCharacterSet].invertedSet]
	              componentsJoinedByString:@" "];
	NSArray<NSString*>* words = [name componentsSeparatedByCharactersInSet:
	                                   NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSMutableArray<NSString*>* compact = NSMutableArray.array;
	for (NSString* word in words) if (word.length > 0) [compact addObject:word];
	return [compact componentsJoinedByString:@" "];
}

double Similarity(NSString* leftValue, NSString* rightValue) {
	const std::string left = leftValue.UTF8String ?: "";
	const std::string right = rightValue.UTF8String ?: "";
	if (left == right) return 1.0;
	if (left.empty() || right.empty()) return 0.0;
	std::vector<int> previous(right.size() + 1), current(right.size() + 1);
	for (std::size_t index = 0; index <= right.size(); ++index) {
		previous[index] = static_cast<int>(index);
	}
	for (std::size_t row = 1; row <= left.size(); ++row) {
		current[0] = static_cast<int>(row);
		for (std::size_t column = 1; column <= right.size(); ++column) {
			current[column] = std::min({current[column - 1] + 1, previous[column] + 1,
			                            previous[column - 1] + (left[row - 1] == right[column - 1] ? 0 : 1)});
		}
		std::swap(previous, current);
	}
	return 1.0 - static_cast<double>(previous.back()) / std::max(left.size(), right.size());
}

NSDictionary* BestMatch(NSString* localName, NSArray<NSDictionary*>* catalogue) {
	NSString* wanted = CanonicalName(localName);
	NSDictionary* best = nil;
	double score = 0.0;
	for (NSDictionary* game in catalogue) {
		NSString* candidate = CanonicalName(SafeString(game[@"title"]));
		if (candidate.length == 0) candidate = CanonicalName(SafeString(game[@"name"]));
		const double value = Similarity(wanted, candidate);
		if (value > score) { score = value; best = game; }
		if (value == 1.0) break;
	}
	return score >= 0.86 ? best : nil;
}

NSData* KeychainSession() {
	NSDictionary* query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
	                        (__bridge id)kSecAttrService: kKeychainService,
	                        (__bridge id)kSecReturnData: @YES,
	                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
	CFTypeRef result = nullptr;
	if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
	return CFBridgingRelease(result);
}

void SaveKeychainSession(NSString* session) {
	NSDictionary* match = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
	                        (__bridge id)kSecAttrService: kKeychainService};
	SecItemDelete((__bridge CFDictionaryRef)match);
	if (session.length == 0) return;
	NSMutableDictionary* item = match.mutableCopy;
	item[(__bridge id)kSecValueData] = [session dataUsingEncoding:NSUTF8StringEncoding];
	item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
	SecItemAdd((__bridge CFDictionaryRef)item, nullptr);
}

NSString* SessionString() {
	NSData* data = KeychainSession();
	return data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}

}  // namespace

typedef void (^RetroMediaReply)(NSHTTPURLResponse* _Nullable, NSData* _Nullable, NSError* _Nullable);

@interface RetroMediaClient () {
	MTKTextureLoader* _textureLoader;
	NSString* _artworkDirectory;
	NSMutableDictionary<NSString*, id<MTLTexture>>* _textures;
}
@end

@implementation RetroMediaClient

- (instancetype)initWithDevice:(id<MTLDevice>)device {
	self = [super init];
	if (self != nil) {
		_textureLoader = [[MTKTextureLoader alloc] initWithDevice:device];
		NSURL* support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
		                                                 inDomains:NSUserDomainMask].firstObject;
		_artworkDirectory = [[support URLByAppendingPathComponent:@"RetroMedia" isDirectory:YES] path];
		[NSFileManager.defaultManager createDirectoryAtPath:_artworkDirectory
		                     withIntermediateDirectories:YES attributes:nil error:nil];
		_textures = NSMutableDictionary.dictionary;
	}
	return self;
}

- (void)request:(NSString*)method path:(NSString*)path body:(NSDictionary* _Nullable)body
	authenticated:(BOOL)authenticated completion:(RetroMediaReply)completion {
	NSURL* url = [NSURL URLWithString:[kBaseURL stringByAppendingString:path]];
	NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = method;
	request.timeoutInterval = 60.0;
	[request setValue:@"application/json, image/*, application/zip" forHTTPHeaderField:@"Accept"];
	[request setValue:@"Retro-AtariST/1.0 RetroMedia client" forHTTPHeaderField:@"User-Agent"];
	if (authenticated) {
		NSString* session = SessionString();
		if (session.length > 0) [request setValue:session forHTTPHeaderField:@"Cookie"];
	}
	if (body != nil) {
		request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
		[request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
	}
	[[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:
	  ^(NSData* data, NSURLResponse* response, NSError* error) {
		completion((NSHTTPURLResponse*)response, data, error);
	}] resume];
}

- (NSDictionary*)json:(NSData*)data {
	id value = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

- (void)publishAccount:(NSDictionary*)account ok:(BOOL)ok message:(NSString*)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString* email = SafeString(account[@"email"]);
		retro_atarist::retro_media_account(ok, email.length > 0, email.UTF8String,
		    [account[@"credits"] intValue], [account[@"freeRemainingToday"] intValue],
		    [account[@"isAdmin"] boolValue], message.UTF8String);
	});
}

- (void)fail:(NSString*)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		retro_atarist::retro_media_operation_finished(false, message.UTF8String);
	});
}

- (void)fetchAccount:(NSString*)message {
	[self request:@"GET" path:@"/api/me" body:nil authenticated:YES completion:
	 ^(NSHTTPURLResponse* response, NSData* data, NSError* error) {
		if (error != nil) { [self fail:error.localizedDescription]; return; }
		if (response.statusCode == 401 || response.statusCode == 403) {
			SaveKeychainSession(@"");
			[self publishAccount:@{} ok:NO message:@"Session expired — sign in again"];
			return;
		}
		if (response.statusCode != 200) { [self fail:ApiError(response, data)]; return; }
		[self publishAccount:[self json:data][@"account"] ?: @{} ok:YES message:message];
	}];
}

- (void)restoreWithBootstrapEmail:(NSString*)email password:(NSString*)password {
	if (SessionString().length > 0) {
		[self fetchAccount:@"Connected"];
	} else if (email.length > 0 && password.length > 0) {
		[self signInWithEmail:email password:password];
	} else {
		NSString* remembered = [NSUserDefaults.standardUserDefaults stringForKey:kRememberedEmail] ?: @"";
		dispatch_async(dispatch_get_main_queue(), ^{
			retro_atarist::retro_media_account(true, false, remembered.UTF8String, 0, 0, false,
			                                 "Not signed in");
		});
	}
}

- (void)signInWithEmail:(NSString*)email password:(NSString*)password {
	email = [email stringByTrimmingCharactersInSet:
	               NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (email.length == 0 || password.length == 0) { [self fail:@"Enter your RetroMedia email and password"]; return; }
	[self request:@"GET" path:@"/api/auth/config" body:nil authenticated:NO completion:
	 ^(NSHTTPURLResponse* configResponse, NSData* configData, NSError* configError) {
		if (configError != nil) { [self fail:configError.localizedDescription]; return; }
		if (configResponse.statusCode != 200) { [self fail:ApiError(configResponse, configData)]; return; }
		NSDictionary* firebase = [self json:configData][@"firebase"];
		NSString* apiKey = SafeString(firebase[@"apiKey"]);
		if (![firebase[@"enabled"] boolValue] || apiKey.length == 0) {
			[self fail:@"RetroMedia Firebase sign-in is not configured"];
			return;
		}
		NSString* identity = [NSString stringWithFormat:
		    @"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%@",
		    EncodeComponent(apiKey)];
		NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:identity]];
		request.HTTPMethod = @"POST";
		request.timeoutInterval = 60.0;
		request.HTTPBody = [NSJSONSerialization dataWithJSONObject:
		    @{@"email": email, @"password": password, @"returnSecureToken": @YES}
		    options:0 error:nil];
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:
		  ^(NSData* identityData, NSURLResponse* identityResponse, NSError* identityError) {
			NSHTTPURLResponse* http = (NSHTTPURLResponse*)identityResponse;
			if (identityError != nil) { [self fail:identityError.localizedDescription]; return; }
			NSDictionary* identityJson = [self json:identityData];
			if (http.statusCode != 200) {
				NSString* code = SafeString(identityJson[@"error"][@"message"]);
				[self fail:[code containsString:@"INVALID"] ? @"Wrong RetroMedia email or password" : code];
				return;
			}
			NSString* token = SafeString(identityJson[@"idToken"]);
			[self request:@"POST" path:@"/api/auth/firebase" body:@{@"id_token": token}
			 authenticated:NO completion:
			 ^(NSHTTPURLResponse* loginResponse, NSData* loginData, NSError* loginError) {
				if (loginError != nil) { [self fail:loginError.localizedDescription]; return; }
				if (loginResponse.statusCode != 200) { [self fail:ApiError(loginResponse, loginData)]; return; }
				NSString* session = @"";
				for (NSHTTPCookie* cookie in [NSHTTPCookie cookiesWithResponseHeaderFields:
				         loginResponse.allHeaderFields forURL:loginResponse.URL]) {
					if ([cookie.name isEqualToString:@"rm_session"]) {
						session = [NSString stringWithFormat:@"%@=%@", cookie.name, cookie.value];
						break;
					}
				}
				if (session.length == 0) { [self fail:@"RetroMedia did not return a session"]; return; }
				SaveKeychainSession(session);
				[NSUserDefaults.standardUserDefaults setObject:email forKey:kRememberedEmail];
				[self publishAccount:[self json:loginData][@"account"] ?: @{} ok:YES message:@"Signed in"];
			}];
		}] resume];
	}];
}

- (void)signOut {
	[self request:@"POST" path:@"/api/auth/logout" body:@{} authenticated:YES completion:
	 ^(NSHTTPURLResponse* response, NSData* data, NSError* error) {
		(void)response; (void)data; (void)error;
		SaveKeychainSession(@"");
		dispatch_async(dispatch_get_main_queue(), ^{
			retro_atarist::retro_media_account(true, false,
			    ([NSUserDefaults.standardUserDefaults stringForKey:kRememberedEmail] ?: @"").UTF8String,
			    0, 0, false, "Signed out");
		});
	}];
}

- (NSString*)metadataKey:(NSString*)mediaType {
	return [@"RetroMediaArtwork." stringByAppendingString:mediaType];
}

- (NSDictionary*)artworkMetadata:(NSString*)mediaType {
	id value = [NSUserDefaults.standardUserDefaults dictionaryForKey:[self metadataKey:mediaType]];
	return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

- (void)loadArtwork:(NSString*)mediaType {
	NSDictionary* metadata = [self artworkMetadata:mediaType];
	dispatch_async(dispatch_get_main_queue(), ^{
		retro_atarist::retro_media_artwork_begin();
		[_textures removeAllObjects];
		for (NSString* localName in metadata) {
			NSString* path = SafeString(metadata[localName]);
			NSError* error = nil;
			id<MTLTexture> texture = [_textureLoader newTextureWithContentsOfURL:
			    [NSURL fileURLWithPath:path] options:@{MTKTextureLoaderOptionSRGB: @NO} error:&error];
			if (texture == nil) continue;
			_textures[localName] = texture;
			retro_atarist::retro_media_artwork_item(localName.UTF8String,
			    static_cast<ImTextureID>(reinterpret_cast<intptr_t>((__bridge void*)texture)),
			    static_cast<int>(texture.width), static_cast<int>(texture.height));
		}
	});
}

- (void)fetchCatalogueType:(NSString*)mediaType page:(NSInteger)page
	items:(NSMutableArray<NSDictionary*>*)items
	completion:(void (^)(NSArray<NSDictionary*>* _Nullable, NSString* _Nullable))completion {
	NSString* path = [NSString stringWithFormat:
	    @"/api/systems/%@/games?limit=200&page=%ld&type=%@", kSystem, (long)page,
	    EncodeComponent(mediaType)];
	[self request:@"GET" path:path body:nil authenticated:NO completion:
	 ^(NSHTTPURLResponse* response, NSData* data, NSError* error) {
		if (error != nil) { completion(nil, error.localizedDescription); return; }
		if (response.statusCode != 200) { completion(nil, ApiError(response, data)); return; }
		NSDictionary* root = [self json:data];
		NSArray* games = [root[@"games"] isKindOfClass:NSArray.class] ? root[@"games"] : @[];
		[items addObjectsFromArray:games];
		if (games.count > 0 && items.count < [root[@"total"] integerValue] && page < 20) {
			[self fetchCatalogueType:mediaType page:page + 1 items:items completion:completion];
		} else {
			completion(items, nil);
		}
	}];
}

- (void)syncArtwork:(NSString*)mediaType gameNames:(NSString*)gameNames {
	if (SessionString().length == 0) { [self fail:@"Sign in to RetroMedia first"]; return; }
	NSMutableArray<NSDictionary*>* catalogue = NSMutableArray.array;
	[self fetchCatalogueType:mediaType page:1 items:catalogue completion:
	 ^(NSArray<NSDictionary*>* games, NSString* error) {
		if (error != nil) { [self fail:error]; return; }
		NSArray<NSString*>* names = [gameNames componentsSeparatedByCharactersInSet:
		                                  NSCharacterSet.newlineCharacterSet];
		NSMutableDictionary* metadata = [self artworkMetadata:mediaType].mutableCopy;
		__block NSInteger downloaded = 0;
		__block NSInteger missing = 0;
		__block void (^next)(NSInteger);
		next = ^(NSInteger index) {
			if (index >= (NSInteger)names.count) {
				[NSUserDefaults.standardUserDefaults setObject:metadata forKey:[self metadataKey:mediaType]];
				[self loadArtwork:mediaType];
				NSString* message = [NSString stringWithFormat:@"%ld downloaded, %ld not found",
				                     (long)downloaded, (long)missing];
				dispatch_async(dispatch_get_main_queue(), ^{
					retro_atarist::retro_media_operation_finished(true, message.UTF8String);
				});
				next = nil;
				return;
			}
			NSString* localName = names[index];
			if (localName.length == 0) { next(index + 1); return; }
			NSString* existing = SafeString(metadata[localName]);
			if (existing.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:existing]) {
				next(index + 1); return;
			}
			NSDictionary* match = BestMatch(localName, games);
			NSString* preview = SafeString(match[@"preview"]);
			NSString* slug = SafeString(match[@"slug"]);
			if (preview.length == 0 || slug.length == 0) { ++missing; next(index + 1); return; }
			NSString* path = [NSString stringWithFormat:@"/api/systems/%@/games/%@/%@",
			                  kSystem, EncodeComponent(slug), EncodeRelativePath(preview)];
			[self request:@"GET" path:path body:nil authenticated:YES completion:
			 ^(NSHTTPURLResponse* response, NSData* data, NSError* requestError) {
				if (requestError != nil || response.statusCode != 200 || data.length == 0) {
					++missing; next(index + 1); return;
				}
				NSString* folder = [_artworkDirectory stringByAppendingPathComponent:mediaType];
				[NSFileManager.defaultManager createDirectoryAtPath:folder
				                     withIntermediateDirectories:YES attributes:nil error:nil];
				NSString* target = [folder stringByAppendingPathComponent:
				                    [Sha256(localName) stringByAppendingString:@".image"]];
				if (![data writeToFile:target options:NSDataWritingAtomic error:nil]) {
					++missing; next(index + 1); return;
				}
				metadata[localName] = target;
				++downloaded;
				next(index + 1);
			}];
		};
		next(0);
	}];
}

@end
