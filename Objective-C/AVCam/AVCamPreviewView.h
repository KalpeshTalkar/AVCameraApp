/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Provides the header for the camera preview view that shows capture output.
*/

@import UIKit;

@class AVCaptureSession;

@interface AVCamPreviewView : UIView

@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *videoPreviewLayer;

@property (nonatomic) AVCaptureSession *session;

@end
