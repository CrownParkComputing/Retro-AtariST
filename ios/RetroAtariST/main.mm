#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMediaTiming.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <cstdint>
#include <string>

#include "frontend.h"
#include "imgui.h"
#include "imgui_impl_metal.h"
#import "RetroMediaClient.h"

#if __has_include("LocalCredentials.h")
#include "LocalCredentials.h"
#else
#define RETRO_ATARIST_BOOTSTRAP_EMAIL ""
#define RETRO_ATARIST_BOOTSTRAP_PASSWORD ""
#endif

@interface RetroAtariSTViewController : UIViewController <MTKViewDelegate, UIDocumentPickerDelegate> {
	id<MTLCommandQueue> _commandQueue;
	id<MTLTexture> _frameTexture;
	id<MTLTexture> _brandTexture;
	uint64_t _uploadedGeneration;
	CFTimeInterval _lastFrameTime;
	retro_atarist::ImportKind _importKind;
	NSString* _tosDirectory;
	NSString* _gamesDirectory;
	RetroMediaClient* _retroMedia;
}
- (void)openDocumentPicker:(retro_atarist::ImportKind)kind;
- (void)restoreRetroMedia;
- (void)signInRetroMedia:(NSString*)email password:(NSString*)password;
- (void)signOutRetroMedia;
- (void)loadRetroMediaArtwork:(NSString*)mediaType;
- (void)syncRetroMediaArtwork:(NSString*)mediaType gameNames:(NSString*)gameNames;
@end

static __weak RetroAtariSTViewController* g_controller = nil;

static int AtariScancodeForHid(const NSInteger usage) {
	// USB HID usages. Letter entries are deliberately physical-position
	// mappings; games read Atari IKBD make/break codes rather than characters.
	static const int letters[26] = {
		0x1e, 0x30, 0x2e, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26,
		0x32, 0x31, 0x18, 0x19, 0x10, 0x13, 0x1f, 0x14, 0x16, 0x2f, 0x11, 0x2d,
		0x15, 0x2c,
	};
	if (usage >= 4 && usage <= 29) return letters[usage - 4];
	static const int digits[10] = {0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b};
	if (usage >= 30 && usage <= 39) return digits[usage - 30];
	switch (usage) {
		case 40: return 0x1c; // Return
		case 41: return 0x01; // Escape
		case 42: return 0x0e; // Backspace
		case 43: return 0x0f; // Tab
		case 44: return 0x39; // Space
		case 79: return 0x4d; // Right
		case 80: return 0x4b; // Left
		case 81: return 0x50; // Down
		case 82: return 0x48; // Up
		default: return -1;
	}
}

@implementation RetroAtariSTViewController

- (void)loadView {
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	MTKView* view = [[MTKView alloc] initWithFrame:UIScreen.mainScreen.bounds device:device];
	view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
	view.preferredFramesPerSecond = 60;
	view.paused = NO;
	view.enableSetNeedsDisplay = NO;
	view.multipleTouchEnabled = YES;
	self.view = view;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	MTKView* view = (MTKView*)self.view;
	_commandQueue = [view.device newCommandQueue];
	view.delegate = self;

	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO();
	io.IniFilename = nullptr;
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;
	io.FontGlobalScale = 1.20f;
	ImGui_ImplMetal_Init(view.device);

	NSFileManager* files = NSFileManager.defaultManager;
	NSURL* support = [files URLsForDirectory:NSApplicationSupportDirectory
	                             inDomains:NSUserDomainMask].firstObject;
	NSURL* documents = [files URLsForDirectory:NSDocumentDirectory
	                               inDomains:NSUserDomainMask].firstObject;
	NSURL* root = [documents URLByAppendingPathComponent:@"AtariST" isDirectory:YES];
	NSURL* tos = [root URLByAppendingPathComponent:@"TOS" isDirectory:YES];
	NSURL* games = [root URLByAppendingPathComponent:@"Games" isDirectory:YES];
	NSURL* work = [support URLByAppendingPathComponent:@"Core" isDirectory:YES];
	for (NSURL* directory in @[root, tos, games, work]) {
		[files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
	}
	NSURL* installedEmuTOS = [tos URLByAppendingPathComponent:@"EmuTOS 1.4 UK.img"];
	if (![files fileExistsAtPath:installedEmuTOS.path]) {
		NSURL* bundledEmuTOS = [NSBundle.mainBundle URLForResource:@"emutos-1.4-uk"
		                                              withExtension:@"img"
		                                               subdirectory:@"EmuTOS"];
		if (bundledEmuTOS != nil) [files copyItemAtURL:bundledEmuTOS toURL:installedEmuTOS error:nil];
	}
	NSURL* installedDemo = [work URLByAppendingPathComponent:@"retro-atarist-core-demo.st"];
	if (![files fileExistsAtPath:installedDemo.path]) {
		NSURL* bundledDemo = [NSBundle.mainBundle URLForResource:@"retro-atarist-core-demo"
		                                           withExtension:@"st"
		                                            subdirectory:@"Demo"];
		if (bundledDemo != nil) [files copyItemAtURL:bundledDemo toURL:installedDemo error:nil];
	}
	_tosDirectory = tos.path;
	_gamesDirectory = games.path;
	g_controller = self;
	_retroMedia = [[RetroMediaClient alloc] initWithDevice:view.device];
	retro_atarist::initialise(work.path.UTF8String, tos.path.UTF8String, games.path.UTF8String);
	NSURL* brandURL = [NSBundle.mainBundle URLForResource:@"retro-atarist-logo" withExtension:@"png"];
	if (brandURL != nil) {
		MTKTextureLoader* loader = [[MTKTextureLoader alloc] initWithDevice:view.device];
		_brandTexture = [loader newTextureWithContentsOfURL:brandURL options:nil error:nil];
		if (_brandTexture != nil) {
			retro_atarist::brand_logo(
			    static_cast<ImTextureID>(reinterpret_cast<intptr_t>((__bridge void*)_brandTexture)),
			    static_cast<int>(_brandTexture.width), static_cast<int>(_brandTexture.height));
		}
	}
	_lastFrameTime = CACurrentMediaTime();
	[self becomeFirstResponder];
}

- (void)dealloc {
	if (g_controller == self) g_controller = nil;
	retro_atarist::shutdown();
	ImGui_ImplMetal_Shutdown();
	ImGui::DestroyContext();
}

- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskLandscape;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
	(void)view;
	(void)size;
}

- (void)drawInMTKView:(MTKView*)view {
	@autoreleasepool {
		const CFTimeInterval now = CACurrentMediaTime();
		retro_atarist::tick(now * 1000.0);
		const retro_atarist::Frame frame = retro_atarist::frame();
		if (frame.pixels != nullptr && frame.width > 0 && frame.height > 0 &&
		    frame.generation != _uploadedGeneration) {
			if (_frameTexture == nil || _frameTexture.width != static_cast<NSUInteger>(frame.width) ||
			    _frameTexture.height != static_cast<NSUInteger>(frame.height)) {
				MTLTextureDescriptor* descriptor =
				    [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
				                                               width:frame.width
				                                              height:frame.height
				                                           mipmapped:NO];
				descriptor.usage = MTLTextureUsageShaderRead;
				descriptor.storageMode = MTLStorageModeShared;
				_frameTexture = [view.device newTextureWithDescriptor:descriptor];
			}
			[_frameTexture replaceRegion:MTLRegionMake2D(0, 0, frame.width, frame.height)
			                 mipmapLevel:0
			                   withBytes:frame.pixels
			                 bytesPerRow:frame.pitch_bytes];
			_uploadedGeneration = frame.generation;
		}

		MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
		id<CAMetalDrawable> drawable = view.currentDrawable;
		if (pass == nil || drawable == nil) return;
		pass.colorAttachments[0].loadAction = MTLLoadActionClear;
		pass.colorAttachments[0].clearColor = MTLClearColorMake(0.018, 0.020, 0.026, 1.0);

		ImGuiIO& io = ImGui::GetIO();
		const CGSize bounds = view.bounds.size;
		io.DisplaySize = ImVec2(bounds.width, bounds.height);
		io.DisplayFramebufferScale = ImVec2(view.drawableSize.width / bounds.width,
		                                     view.drawableSize.height / bounds.height);
		io.DeltaTime = _lastFrameTime > 0.0 ? static_cast<float>(now - _lastFrameTime) : 1.0f / 60.0f;
		_lastFrameTime = now;
		ImGui_ImplMetal_NewFrame(pass);
		ImGui::NewFrame();
		const ImTextureID texture = _frameTexture != nil
		    ? static_cast<ImTextureID>(reinterpret_cast<intptr_t>((__bridge void*)_frameTexture))
		    : ImTextureID_Invalid;
		// The cutout and the home indicator. Without this the top of the UI
		// draws under the Dynamic Island -- the "Machine" tab rendered as
		// "achine" on an iPhone 17 Pro Max. UIKit reports these in points,
		// which is what ImGui is working in here.
		const UIEdgeInsets safe = view.safeAreaInsets;
		retro_atarist::safe_area_insets((float)safe.left, (float)safe.top,
		                                (float)safe.right, (float)safe.bottom);
		retro_atarist::draw(texture, bounds.width, bounds.height);
		ImGui::Render();

		id<MTLCommandBuffer> command = [_commandQueue commandBuffer];
		id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
		ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), command, encoder);
		[encoder endEncoding];
		[command presentDrawable:drawable];
		[command commit];
	}
}

- (void)updateTouch:(NSSet<UITouch*>*)touches down:(BOOL)down {
	UITouch* touch = touches.anyObject;
	if (touch == nil) return;
	const CGPoint point = [touch locationInView:self.view];
	ImGuiIO& io = ImGui::GetIO();
	io.AddMouseSourceEvent(ImGuiMouseSource_TouchScreen);
	io.AddMousePosEvent(point.x, point.y);
	io.AddMouseButtonEvent(0, down);
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
	(void)event;
	[self updateTouch:touches down:YES];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
	(void)event;
	[self updateTouch:touches down:YES];
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
	(void)event;
	[self updateTouch:touches down:NO];
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
	(void)event;
	[self updateTouch:touches down:NO];
}

- (void)sendPresses:(NSSet<UIPress*>*)presses pressed:(BOOL)pressed {
	for (UIPress* press in presses) {
		if (press.key == nil) continue;
		const int scancode = AtariScancodeForHid(press.key.keyCode);
		if (scancode >= 0) retro_atarist::key_event(scancode, pressed);
	}
}

- (void)pressesBegan:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event {
	[self sendPresses:presses pressed:YES];
	[super pressesBegan:presses withEvent:event];
}
- (void)pressesEnded:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event {
	[self sendPresses:presses pressed:NO];
	[super pressesEnded:presses withEvent:event];
}
- (void)pressesCancelled:(NSSet<UIPress*>*)presses withEvent:(UIPressesEvent*)event {
	[self sendPresses:presses pressed:NO];
	[super pressesCancelled:presses withEvent:event];
}

- (void)openDocumentPicker:(retro_atarist::ImportKind)kind {
	_importKind = kind;
	UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
	    initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
	picker.delegate = self;
	picker.allowsMultipleSelection = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)restoreRetroMedia {
	[_retroMedia restoreWithBootstrapEmail:@RETRO_ATARIST_BOOTSTRAP_EMAIL
	                              password:@RETRO_ATARIST_BOOTSTRAP_PASSWORD];
}

- (void)signInRetroMedia:(NSString*)email password:(NSString*)password {
	[_retroMedia signInWithEmail:email password:password];
}

- (void)signOutRetroMedia { [_retroMedia signOut]; }
- (void)loadRetroMediaArtwork:(NSString*)mediaType { [_retroMedia loadArtwork:mediaType]; }
- (void)syncRetroMediaArtwork:(NSString*)mediaType gameNames:(NSString*)gameNames {
	[_retroMedia syncArtwork:mediaType gameNames:gameNames];
}

- (NSURL*)uniqueDestinationFor:(NSURL*)source directory:(NSString*)directory {
	NSFileManager* files = NSFileManager.defaultManager;
	NSString* name = source.lastPathComponent.length > 0 ? source.lastPathComponent : @"imported.bin";
	NSURL* candidate = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
	if (![files fileExistsAtPath:candidate.path]) return candidate;
	NSString* stem = name.stringByDeletingPathExtension;
	NSString* extension = name.pathExtension;
	for (NSInteger index = 2; index < 10000; ++index) {
		NSString* numbered = extension.length > 0
		    ? [NSString stringWithFormat:@"%@ %ld.%@", stem, (long)index, extension]
		    : [NSString stringWithFormat:@"%@ %ld", stem, (long)index];
		candidate = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:numbered]];
		if (![files fileExistsAtPath:candidate.path]) return candidate;
	}
	return nil;
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
	didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls {
	(void)controller;
	NSURL* source = urls.firstObject;
	if (source == nil) return;
	NSString* directory = _importKind == retro_atarist::ImportKind::Rom ? _tosDirectory : _gamesDirectory;
	NSURL* destination = [self uniqueDestinationFor:source directory:directory];
	if (destination == nil) return;
	NSError* error = nil;
	if (![NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:&error]) {
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Import failed"
		    message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	retro_atarist::imported_file(_importKind, destination.path.UTF8String);
}

@end

namespace retro_atarist {

void platform_open_document(const ImportKind kind) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[g_controller openDocumentPicker:kind];
	});
}

void platform_retro_media_restore() {
	dispatch_async(dispatch_get_main_queue(), ^{ [g_controller restoreRetroMedia]; });
}

void platform_retro_media_sign_in(const char* email, const char* password) {
	NSString* user = email != nullptr ? [NSString stringWithUTF8String:email] : @"";
	NSString* secret = password != nullptr ? [NSString stringWithUTF8String:password] : @"";
	dispatch_async(dispatch_get_main_queue(), ^{ [g_controller signInRetroMedia:user password:secret]; });
}

void platform_retro_media_sign_out() {
	dispatch_async(dispatch_get_main_queue(), ^{ [g_controller signOutRetroMedia]; });
}

void platform_retro_media_load_artwork(const char* media_type) {
	NSString* type = media_type != nullptr ? [NSString stringWithUTF8String:media_type] : @"box2d";
	dispatch_async(dispatch_get_main_queue(), ^{ [g_controller loadRetroMediaArtwork:type]; });
}

void platform_retro_media_sync_artwork(const char* media_type, const char* game_names) {
	NSString* type = media_type != nullptr ? [NSString stringWithUTF8String:media_type] : @"box2d";
	NSString* names = game_names != nullptr ? [NSString stringWithUTF8String:game_names] : @"";
	dispatch_async(dispatch_get_main_queue(), ^{ [g_controller syncRetroMediaArtwork:type gameNames:names]; });
}

bool platform_game_downloads_available() { return false; }
void platform_retro_media_browse(const char*) {}
void platform_retro_media_download(const char*) {}

}  // namespace retro_atarist

@interface RetroAtariSTAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation RetroAtariSTAppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options {
	(void)application;
	(void)options;
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [[RetroAtariSTViewController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}
- (void)applicationWillResignActive:(UIApplication*)application {
	(void)application;
	retro_atarist::pause_for_lifecycle(true);
}
- (void)applicationDidBecomeActive:(UIApplication*)application {
	(void)application;
	retro_atarist::pause_for_lifecycle(false);
}
@end

int main(int argc, char** argv) {
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil, NSStringFromClass(RetroAtariSTAppDelegate.class));
	}
}
