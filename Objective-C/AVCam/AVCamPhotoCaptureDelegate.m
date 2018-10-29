/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implements the photo capture delegate.
*/


#import "AVCamPhotoCaptureDelegate.h"

@import Photos;

@interface AVCamPhotoCaptureDelegate ()

@property (nonatomic, readwrite) AVCapturePhotoSettings* requestedPhotoSettings;
@property (nonatomic) void (^willCapturePhotoAnimation)(void);
@property (nonatomic) void (^livePhotoCaptureHandler)(BOOL capturing);
@property (nonatomic) void (^completionHandler)(AVCamPhotoCaptureDelegate* photoCaptureDelegate);

@property (nonatomic) NSData* photoData;
@property (nonatomic) NSURL* livePhotoCompanionMovieURL;
@property (nonatomic) NSData* portraitEffectsMatteData;

@end

@implementation AVCamPhotoCaptureDelegate

- (instancetype) initWithRequestedPhotoSettings:(AVCapturePhotoSettings*)requestedPhotoSettings willCapturePhotoAnimation:(void (^)(void))willCapturePhotoAnimation livePhotoCaptureHandler:(void (^)(BOOL))livePhotoCaptureHandler completionHandler:(void (^)(AVCamPhotoCaptureDelegate*))completionHandler
{
    self = [super init];
    if ( self ) {
        self.requestedPhotoSettings = requestedPhotoSettings;
        self.willCapturePhotoAnimation = willCapturePhotoAnimation;
        self.livePhotoCaptureHandler = livePhotoCaptureHandler;
        self.completionHandler = completionHandler;
    }
    return self;
}

- (void) didFinish
{
    if ( [[NSFileManager defaultManager] fileExistsAtPath:self.livePhotoCompanionMovieURL.path] ) {
        NSError* error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.livePhotoCompanionMovieURL.path error:&error];
        
        if ( error ) {
            NSLog( @"Could not remove file at url: %@", self.livePhotoCompanionMovieURL.path );
        }
    }
    
    self.completionHandler( self );
}

- (void) captureOutput:(AVCapturePhotoOutput*)captureOutput willBeginCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings*)resolvedSettings
{
    if ( ( resolvedSettings.livePhotoMovieDimensions.width > 0 ) && ( resolvedSettings.livePhotoMovieDimensions.height > 0 ) ) {
        self.livePhotoCaptureHandler( YES );
    }
}

- (void) captureOutput:(AVCapturePhotoOutput*)captureOutput willCapturePhotoForResolvedSettings:(AVCaptureResolvedPhotoSettings*)resolvedSettings
{
    self.willCapturePhotoAnimation();
}

- (void) captureOutput:(AVCapturePhotoOutput*)captureOutput didFinishProcessingPhoto:(AVCapturePhoto*)photo error:(nullable NSError*)error
{
    if ( error != nil ) {
        NSLog( @"Error capturing photo: %@", error );
        return;
    }
    
    self.photoData = [photo fileDataRepresentation];
    
    // Portrait Effects Matte only gets generated if there is a face
    if ( photo.portraitEffectsMatte != nil ) {
        CGImagePropertyOrientation orientation = [[photo.metadata objectForKey:(NSString*)kCGImagePropertyOrientation] intValue];
        AVPortraitEffectsMatte* portraitEffectsMatte = [photo.portraitEffectsMatte portraitEffectsMatteByApplyingExifOrientation:orientation];
        CVPixelBufferRef portraitEffectsMattePixelBuffer = [portraitEffectsMatte mattingImage];
        CIImage* portraitEffectsMatteImage = [CIImage imageWithCVPixelBuffer:portraitEffectsMattePixelBuffer options:@{ kCIImageAuxiliaryPortraitEffectsMatte : @(YES) }];
        CIContext* context = [CIContext context];
        CGColorSpaceRef linearColorSpace = CGColorSpaceCreateWithName( kCGColorSpaceLinearSRGB );
        self.portraitEffectsMatteData = [context HEIFRepresentationOfImage:portraitEffectsMatteImage format:kCIFormatRGBA8 colorSpace:linearColorSpace options:@{ (id)kCIImageRepresentationPortraitEffectsMatteImage : portraitEffectsMatteImage} ];
    }
    else {
        self.portraitEffectsMatteData = nil;
    }
}

- (void) captureOutput:(AVCapturePhotoOutput*)captureOutput didFinishRecordingLivePhotoMovieForEventualFileAtURL:(NSURL*)outputFileURL resolvedSettings:(AVCaptureResolvedPhotoSettings*)resolvedSettings
{
    self.livePhotoCaptureHandler(NO);
}

- (void) captureOutput:(AVCapturePhotoOutput*)captureOutput didFinishProcessingLivePhotoToMovieFileAtURL:(NSURL*)outputFileURL duration:(CMTime)duration photoDisplayTime:(CMTime)photoDisplayTime resolvedSettings:(AVCaptureResolvedPhotoSettings*)resolvedSettings error:(NSError*)error
{
    if ( error != nil ) {
        NSLog( @"Error processing Live Photo companion movie: %@", error );
        return;
    }
    
    self.livePhotoCompanionMovieURL = outputFileURL;
}

- (void) captureOutput:(AVCapturePhotoOutput*)captureOutput didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings*)resolvedSettings error:(NSError*)error
{
    if ( error != nil ) {
        NSLog( @"Error capturing photo: %@", error );
        [self didFinish];
        return;
    }
    
    if ( self.photoData == nil ) {
        NSLog( @"No photo data resource" );
        [self didFinish];
        return;
    }
    
    [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
        if ( status == PHAuthorizationStatusAuthorized ) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                PHAssetResourceCreationOptions* options = [[PHAssetResourceCreationOptions alloc] init];
                options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType;
                PHAssetCreationRequest* creationRequest = [PHAssetCreationRequest creationRequestForAsset];
                [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:self.photoData options:options];
                
                if ( self.livePhotoCompanionMovieURL ) {
                    PHAssetResourceCreationOptions* livePhotoCompanionMovieResourceOptions = [[PHAssetResourceCreationOptions alloc] init];
                    livePhotoCompanionMovieResourceOptions.shouldMoveFile = YES;
                    [creationRequest addResourceWithType:PHAssetResourceTypePairedVideo fileURL:self.livePhotoCompanionMovieURL options:livePhotoCompanionMovieResourceOptions];
                }
                
                // Save Portrait Effects Matte to Photos Library only if it was generated
                if ( self.portraitEffectsMatteData ) {
                    PHAssetCreationRequest* creationRequest = [PHAssetCreationRequest creationRequestForAsset];
                    [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:self.portraitEffectsMatteData options:nil];
                }
                
            } completionHandler:^( BOOL success, NSError* _Nullable error ) {
                if ( ! success ) {
                    NSLog( @"Error occurred while saving photo to photo library: %@", error );
                }
                
                [self didFinish];
            }];
        }
        else {
            NSLog( @"Not authorized to save photo" );
            [self didFinish];
        }
    }];
}

@end
