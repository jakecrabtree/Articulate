//
//  HomeViewController.m
//  LLSimpleCameraExample
//
//  Created by Ömer Faruk Gül on 29/10/14.
//  Copyright (c) 2014 Ömer Faruk Gül. All rights reserved.
//

#import "HomeViewController.h"
#import "ViewUtils.h"
#import "ImageViewController.h"
#import "VideoViewController.h"
#include "precomp.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface HomeViewController ()
@property (strong, nonatomic) LLSimpleCamera *camera;
@property (strong, nonatomic) UILabel *errorLabel;
@property (strong, nonatomic) UIButton *snapButton;
@property (strong, nonatomic) UIButton *switchButton;
@property (strong, nonatomic) UIButton *flashButton;
//@property (strong, nonatomic) UISegmentedControl *segmentedControl;
@property (nonatomic, readonly)  NSString*               subscriptionKey;
@property (nonatomic, readonly)  NSString*               luisAppId;
@property (nonatomic, readonly)  NSString*               luisSubscriptionID;
@property (nonatomic, readonly)  NSString*               authenticationUri;
@property (nonatomic, readonly)  bool                    useMicrophone;
@property (nonatomic, readonly)  bool                    wantIntent;
@property (nonatomic, readonly)  SpeechRecognitionMode   mode;
@property (nonatomic, readonly)  NSString*               defaultLocale;
@property (nonatomic, readonly)  NSString*               shortWaveFile;
@property (nonatomic, readonly)  NSString*               longWaveFile;
@property (nonatomic, readonly)  NSDictionary*           settings;
@property (nonatomic, readwrite) NSArray*                buttonGroup;
@property (nonatomic, readonly)  NSUInteger              modeIndex;
@property (strong, nonatomic) AVAudioPlayer *player;
@end
NSString* ConvertSpeechRecoConfidenceEnumToString(Confidence confidence);
NSString* ConvertSpeechErrorToString(int errorCode);
NSMutableString* textOnScreen;
DataRecognitionClient* dataClient;
MicrophoneRecognitionClient* micClient;

@implementation HomeViewController


/**
 * Gets or sets subscription key
 */
-(NSString*)subscriptionKey {
    return [self.settings objectForKey:(@"primaryKey")];
}

/**
 * Gets the LUIS application identifier.
 * @return The LUIS application identifier.
 */
-(NSString*)luisAppId {
    return [self.settings objectForKey:(@"luisAppID")];
}

/**
 * Gets the LUIS subscription identifier.
 * @return The LUIS subscription identifier.
 */
-(NSString*)luisSubscriptionID {
    return [self.settings objectForKey:(@"luisSubscriptionID")];
}

/**
 * Gets the Cognitive Service Authentication Uri.
 * @return The Cognitive Service Authentication Uri.  Empty if the global default is to be used.
 */
-(NSString*)authenticationUri {
    return [self.settings objectForKey:(@"authenticationUri")];
}

/**
 * Gets a value indicating whether or not to use the microphone.
 * @return true if [use microphone]; otherwise, false.
 */
-(bool)useMicrophone {
    auto index = self.modeIndex;
    return index < 3;
}

/**
 * Gets a value indicating whether LUIS results are desired.
 * @return true if LUIS results are to be returned otherwise, false.
 */
-(bool)wantIntent {
    auto index = self.modeIndex;
    return index == 2 || index == 5;
}

/**
 * Gets the current speech recognition mode.
 * @return The speech recognition mode.
 */
-(SpeechRecognitionMode)mode {
    return SpeechRecognitionMode_LongDictation;
}

/**
 * Gets the default locale.
 * @return The default locale.
 */
-(NSString*)defaultLocale {
    return @"en-us";
}

/**
 * Gets the short wave file path.
 * @return The short wave file.
 */
-(NSString*)shortWaveFile {
    return @"whatstheweatherlike";
}

/**
 * Gets the long wave file path.
 * @return The long wave file.
 */
-(NSString*)longWaveFile {
    return @"batman";
}

/**
 * Gets the current bundle settings.
 * @return The settings dictionary.
 */
-(NSDictionary*)settings {
    NSString* path = [[NSBundle mainBundle] pathForResource:@"settings" ofType:@"plist"];
    NSDictionary* settings = [[NSDictionary alloc] initWithContentsOfFile:path];
    return settings;
}

/**
 * Gets the current zero-based mode index.
 * @return The current mode index.
 */
-(NSUInteger)modeIndex {
    for(NSUInteger i = 0; i < self.buttonGroup.count; ++i) {
        UNIVERSAL_BUTTON* buttonSel = (UNIVERSAL_BUTTON*)self.buttonGroup[i];
        if (UNIVERSAL_BUTTON_GETCHECKED(buttonSel)) {
            return i;
        }
    }
    
    return 0;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    
    self.view.backgroundColor = [UIColor blackColor];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    
    // ----- initialize camera -------- //
    
    // create camera vc
    self.camera = [[LLSimpleCamera alloc] initWithQuality:AVCaptureSessionPresetHigh
                                                 position:LLCameraPositionRear
                                             videoEnabled:YES];
    
    // attach to a view controller
    [self.camera attachToViewController:self withFrame:CGRectMake(0, 0, screenRect.size.width, screenRect.size.height)];
    
    // read: http://stackoverflow.com/questions/5427656/ios-uiimagepickercontroller-result-image-orientation-after-upload
    // you probably will want to set this to YES, if you are going view the image outside iOS.
    self.camera.fixOrientationAfterCapture = NO;
    
    // take the required actions on a device change
    __weak typeof(self) weakSelf = self;
    [self.camera setOnDeviceChange:^(LLSimpleCamera *camera, AVCaptureDevice * device) {
        
        NSLog(@"Device changed.");
        
        // device changed, check if flash is available
        if([camera isFlashAvailable]) {
            weakSelf.flashButton.hidden = NO;
            
            if(camera.flash == LLCameraFlashOff) {
                weakSelf.flashButton.selected = NO;
            }
            else {
                weakSelf.flashButton.selected = YES;
            }
        }
        else {
            weakSelf.flashButton.hidden = YES;
        }
    }];
    
    [self.camera setOnError:^(LLSimpleCamera *camera, NSError *error) {
        NSLog(@"Camera error: %@", error);
        
        if([error.domain isEqualToString:LLSimpleCameraErrorDomain]) {
            if(error.code == LLSimpleCameraErrorCodeCameraPermission ||
               error.code == LLSimpleCameraErrorCodeMicrophonePermission) {
                
                if(weakSelf.errorLabel) {
                    [weakSelf.errorLabel removeFromSuperview];
                }
                
                UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
                label.text = @"We need permission for the camera.\nPlease go to your settings.";
                label.numberOfLines = 2;
                label.lineBreakMode = NSLineBreakByWordWrapping;
                label.backgroundColor = [UIColor clearColor];
                label.font = [UIFont fontWithName:@"AvenirNext-DemiBold" size:13.0f];
                label.textColor = [UIColor whiteColor];
                label.textAlignment = NSTextAlignmentCenter;
                [label sizeToFit];
                label.center = CGPointMake(screenRect.size.width / 2.0f, screenRect.size.height / 2.0f);
                weakSelf.errorLabel = label;
                [weakSelf.view addSubview:weakSelf.errorLabel];
            }
        }
    }];

    // ----- camera buttons -------- //
    
    // snap button to capture image
    self.snapButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.snapButton.frame = CGRectMake(0, 0, 70.0f, 70.0f);
    self.snapButton.clipsToBounds = YES;
    self.snapButton.layer.cornerRadius = self.snapButton.width / 2.0f;
    self.snapButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.snapButton.layer.borderWidth = 2.0f;
    self.snapButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    self.snapButton.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.snapButton.layer.shouldRasterize = YES;
    [self.snapButton addTarget:self action:@selector(snapButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.snapButton];
    
    // button to toggle flash
    self.flashButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.flashButton.frame = CGRectMake(0, 0, 16.0f + 20.0f, 24.0f + 20.0f);
    self.flashButton.tintColor = [UIColor whiteColor];
    [self.flashButton setImage:[UIImage imageNamed:@"camera-flash.png"] forState:UIControlStateNormal];
    self.flashButton.imageEdgeInsets = UIEdgeInsetsMake(10.0f, 10.0f, 10.0f, 10.0f);
    [self.flashButton addTarget:self action:@selector(flashButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.flashButton];
    
    if([LLSimpleCamera isFrontCameraAvailable] && [LLSimpleCamera isRearCameraAvailable]) {
        // button to toggle camera positions
        self.switchButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.switchButton.frame = CGRectMake(0, 0, 29.0f + 20.0f, 22.0f + 20.0f);
        self.switchButton.tintColor = [UIColor whiteColor];
        [self.switchButton setImage:[UIImage imageNamed:@"camera-switch.png"] forState:UIControlStateNormal];
        self.switchButton.imageEdgeInsets = UIEdgeInsetsMake(10.0f, 10.0f, 10.0f, 10.0f);
        [self.switchButton addTarget:self action:@selector(switchButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:self.switchButton];
    }
    
 /*   self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Picture",@"Video"]];
    self.segmentedControl.frame = CGRectMake(12.0f, screenRect.size.height - 67.0f, 120.0f, 32.0f);
    self.segmentedControl.selectedSegmentIndex = 0;
    self.segmentedControl.tintColor = [UIColor whiteColor];
    [self.segmentedControl addTarget:self action:@selector(segmentedControlValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentedControl];*/
}

- (void)segmentedControlValueChanged:(UISegmentedControl *)control
{
    NSLog(@"Segment value changed!");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // start the camera
    [self.camera start];
}

/* camera button methods */

- (void)switchButtonPressed:(UIButton *)button
{
    [self.camera togglePosition];
}

- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (void)flashButtonPressed:(UIButton *)button
{
    if(self.camera.flash == LLCameraFlashOff) {
        BOOL done = [self.camera updateFlashMode:LLCameraFlashOn];
        if(done) {
            self.flashButton.selected = YES;
            self.flashButton.tintColor = [UIColor yellowColor];
        }
    }
    else {
        BOOL done = [self.camera updateFlashMode:LLCameraFlashOff];
        if(done) {
            self.flashButton.selected = NO;
            self.flashButton.tintColor = [UIColor whiteColor];
        }
    }
}

- (void)snapButtonPressed:(UIButton *)button
{
        if(!self.camera.isRecording) {
            
            [self logRecognitionStart];
            
            if (self.useMicrophone) {
                if (micClient == nil) {
                    if (!self.wantIntent) {
                        [self WriteLine:(@"--- Start microphone dictation with Intent detection ----")];
                        printf("OPTIONS 1:\n");
                        micClient = [SpeechRecognitionServiceFactory createMicrophoneClient:(self.mode)
                                                                               withLanguage:(self.defaultLocale)
                                                                                    withKey:(self.subscriptionKey)
                                                                               withProtocol:(self)];
                    }
                    
                    micClient.AuthenticationUri = self.authenticationUri;
                }
                
                OSStatus status = [micClient startMicAndRecognition];
                if (status) {
                    [self WriteLine:[[NSString alloc] initWithFormat:(@"Error starting audio. %@"), ConvertSpeechErrorToString(status)]];
                }
            }
            
            self.flashButton.hidden = YES;
            self.switchButton.hidden = YES;
            
            self.snapButton.layer.borderColor = [UIColor redColor].CGColor;
            self.snapButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
            
            // start recording
            NSURL *outputURL = [[[self applicationDocumentsDirectory]
                                 URLByAppendingPathComponent:@"test1"] URLByAppendingPathExtension:@"mov"];
            [self.camera startRecordingWithOutputUrl:outputURL didRecord:^(LLSimpleCamera *camera, NSURL *outputFileUrl, NSError *error) {
                if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum (outputFileUrl.relativePath))
                {
                    UISaveVideoAtPathToSavedPhotosAlbum (outputFileUrl.relativePath,self, nil, nil);
                }
               // VideoViewController *vc = [[VideoViewController alloc] initWithVideoUrl:outputFileUrl];
                UIViewController * vc = [self.storyboard instantiateViewControllerWithIdentifier:@"SpeechViewController"];
                [self presentViewController:vc animated:YES completion:nil];
            }];
            
        } else {
            [micClient endMicAndRecognition];
            self.flashButton.hidden = NO;
            self.switchButton.hidden = NO;
            
            self.snapButton.layer.borderColor = [UIColor whiteColor].CGColor;
            self.snapButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
            
            [self.camera stopRecording];
        }
    }


/* other lifecycle methods */

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    self.camera.view.frame = self.view.contentBounds;
    
    self.snapButton.center = self.view.contentCenter;
    self.snapButton.bottom = self.view.height - 15.0f;
    
    self.flashButton.center = self.view.contentCenter;
    self.flashButton.top = 5.0f;
    
    self.switchButton.top = 5.0f;
    self.switchButton.right = self.view.width - 5.0f;
    
    //self.segmentedControl.left = 12.0f;
  //  self.segmentedControl.bottom = self.view.height - 35.0f;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UIInterfaceOrientation) preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}


/**
 * Logs the recognition start.
 */
-(void)logRecognitionStart {
    NSString* recoSource;
    if (self.useMicrophone) {
        recoSource = @"microphone";
    } else if (self.mode == SpeechRecognitionMode_ShortPhrase) {
        recoSource = @"short wav file";
    } else {
        recoSource = @"long wav file";
    }
    
    [self WriteLine:[[NSString alloc] initWithFormat:(@"\n--- Start speech recognition using %@ with %@ mode in %@ language ----\n\n"),
                     recoSource,
                     self.mode == SpeechRecognitionMode_ShortPhrase ? @"Short" : @"Long",
                     self.defaultLocale]];
}

/**
 * Speech recognition with data (for example from a file or audio source).
 * The data is broken up into buffers and each buffer is sent to the Speech Recognition Service.
 * No modification is done to the buffers, so the user can apply their own Silence Detection
 * @param filename The audio file to send.
 */
-(void)sendAudioHelper:(NSString*)filename {
    NSFileHandle* fileHandle = nil;
    @try {
        
        NSBundle* mainResouceArea = [NSBundle mainBundle];
        NSString* filePathAndName = [mainResouceArea pathForResource:(filename)
                                                              ofType:(@"wav")];
        NSURL* fileURL = [[NSURL alloc] initFileURLWithPath:(filePathAndName)];
        
        fileHandle = [NSFileHandle fileHandleForReadingFromURL:(fileURL)
                                                         error:(nil)];
        
        NSData* buffer;
        int bytesRead = 0;
        
        do {
            // Get  Audio data to send into byte buffer.
            buffer = [fileHandle readDataOfLength:(1024)];
            bytesRead = (int)[buffer length];
            
            if (buffer != nil && bytesRead != 0) {
                // Send of audio data to service.
                [dataClient sendAudio:(buffer)
                           withLength:(bytesRead)];
            }
        } while (buffer != nil && bytesRead != 0);
    }
    @catch(NSException* ex) {
        NSLog(@"%@", ex);
    }
    @finally {
        [dataClient endAudio];
        if (fileHandle != nil) {
            [fileHandle closeFile];
        }
    }
}

/**
 * Called when a final response is received.
 * @param response The final result.
 */
-(void)onFinalResponseReceived:(RecognitionResult*)response {
    bool isFinalDicationMessage = self.mode == SpeechRecognitionMode_LongDictation &&
    (response.RecognitionStatus == RecognitionStatus_EndOfDictation); //||
    //response.RecognitionStatus == RecognitionStatus_DictationEndSilenceTimeout);
    if (nil != micClient && self.useMicrophone && ((self.mode == SpeechRecognitionMode_ShortPhrase) || isFinalDicationMessage)) {
        // we got the final result, so it we can end the mic reco.  No need to do this
        // for dataReco, since we already called endAudio on it as soon as we were done
        // sending all the data.
        [micClient endMicAndRecognition];
    }
    
    if ((self.mode == SpeechRecognitionMode_ShortPhrase) || isFinalDicationMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            //[[self startButton] setEnabled:YES];
        });
    }
    
    if (!isFinalDicationMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self WriteLine:(@"********* Final n-BEST Results *********")];
            for (int i = 0; i < [response.RecognizedPhrase count]; i++) {
                RecognizedPhrase* phrase = response.RecognizedPhrase[i];
                [self WriteLine:[[NSString alloc] initWithFormat:(@"[%d] Confidence=%@ Text=\"%@\""),
                                 i,
                                 ConvertSpeechRecoConfidenceEnumToString(phrase.Confidence),
                                 phrase.DisplayText]];
            }
            
            [self WriteLine:(@"")];
        });
    }
}

/**
 * Called when a final response is received and its intent is parsed
 * @param result The intent result.
 */
-(void)onIntentReceived:(IntentResult*) result {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self WriteLine:(@"--- Intent received by onIntentReceived ---")];
        [self WriteLine:(result.Body)];
        [self WriteLine:(@"")];
    });
}

/**
 * Called when a partial response is received
 * @param response The partial result.
 */
-(void)onPartialResponseReceived:(NSString*) response {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self WriteLine:(@"--- Partial result received by onPartialResponseReceived ---")];
        __block NSString *lastWord = nil;
        
        [response enumerateSubstringsInRange:NSMakeRange(0, [response length]) options:NSStringEnumerationByWords | NSStringEnumerationReverse usingBlock:^(NSString *substring, NSRange subrange, NSRange enclosingRange, BOOL *stop) {
            lastWord = substring;
            *stop = YES;
        }];
        NSArray *myArray = @[@"um", @"so", @"because", @"alright", @"like"];
        if ([myArray containsObject:lastWord]) {
            //NSString *soundPath = [[NSBundle mainBundle] pathForResource:@"beep" ofType:@"m4a"];
            //CFURLRef soundURL = (__bridge CFURLRef)[NSURL fileURLWithPath:soundPath];
            //AudioServicesCreateSystemSoundID(soundURL, &sounds[0]);
            //AudioServicesPlaySystemSound(sounds[0]);
            
            NSString *soundFilePath = [[NSBundle mainBundle] pathForResource:@"beep"  ofType:@"m4a"];
            NSURL *soundFileURL = [NSURL fileURLWithPath:soundFilePath];
            _player = [[AVAudioPlayer alloc] initWithContentsOfURL:soundFileURL error:nil];
            _player.numberOfLoops = 1; //Infinite
            
            [_player play];
            
            [self WriteLine:lastWord];
            
        }
        AudioServicesPlaySystemSound(1053);
        //[self WriteLine:lastWord];
    });
}

/**
 * Called when an error is received
 * @param errorMessage The error message.
 * @param errorCode The error code.  Refer to SpeechClientStatus for details.
 */
-(void)onError:(NSString*)errorMessage withErrorCode:(int)errorCode {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self WriteLine:(@"--- Error received by onError ---")];
        [self WriteLine:[[NSString alloc] initWithFormat:(@"%@ %@"), errorMessage, ConvertSpeechErrorToString(errorCode)]];
        [self WriteLine:@""];
    });
}

/**
 * Called when the microphone status has changed.
 * @param recording The current recording state
 */
-(void)onMicrophoneStatus:(Boolean)recording {
    if (!recording) {
        [micClient endMicAndRecognition];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!recording) {
            //[[self startButton] setEnabled:YES];
        }
        [self WriteLine:[[NSString alloc] initWithFormat:(@"********* Microphone status: %d *********"), recording]];
    });
}

/**
 * Callback invoked when the speaker status changes
 * @param speaking A flag indicating whether the speaker output is enabled
 */
-(void)onSpeakerStatus:(Boolean)speaking
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self WriteLine:[[NSString alloc] initWithFormat:(@"********* Speaker status: %d *********"), speaking]];
    });
}


/**
 * Writes the line.
 * @param text The line to write.
 */
-(void)WriteLine:(NSString*)text {
    //[textOnScreen appendString:(text)];
    //[textOnScreen appendString:(@"\n")];
    //[self setText:textOnScreen];
}

/**
 * Event handler for when the current mode has changed.
 * @param sender The sending caller.
 */
-(IBAction)RadioButton_Click:(id)sender {
    NSUInteger index = [self.buttonGroup indexOfObject:sender];
    for(NSUInteger i = 0; i < self.buttonGroup.count; ++i) {
        UNIVERSAL_BUTTON* buttonSel = (UNIVERSAL_BUTTON*)self.buttonGroup[i];
        UNIVERSAL_BUTTON_SETCHECKED(buttonSel, (index == i) ? TRUE : FALSE);
    }
    
    if (micClient != nil) {
        [micClient finalize];
        micClient = nil;
    }
    
    if (dataClient != nil) {
        [dataClient finalize];
        dataClient = nil;
    }
    
    //[self showMenu:FALSE];
}

/**
 * Converts an integer error code to an error string.
 * @param errorCode The error code
 * @return The string representation of the error code.
 */
NSString* ConvertSpeechErrorToString(int errorCode) {
    switch ((SpeechClientStatus)errorCode) {
        case SpeechClientStatus_SecurityFailed:         return @"SpeechClientStatus_SecurityFailed";
        case SpeechClientStatus_LoginFailed:            return @"SpeechClientStatus_LoginFailed";
        case SpeechClientStatus_Timeout:                return @"SpeechClientStatus_Timeout";
        case SpeechClientStatus_ConnectionFailed:       return @"SpeechClientStatus_ConnectionFailed";
        case SpeechClientStatus_NameNotFound:           return @"SpeechClientStatus_NameNotFound";
        case SpeechClientStatus_InvalidService:         return @"SpeechClientStatus_InvalidService";
        case SpeechClientStatus_InvalidProxy:           return @"SpeechClientStatus_InvalidProxy";
        case SpeechClientStatus_BadResponse:            return @"SpeechClientStatus_BadResponse";
        case SpeechClientStatus_InternalError:          return @"SpeechClientStatus_InternalError";
        case SpeechClientStatus_AuthenticationError:    return @"SpeechClientStatus_AuthenticationError";
        case SpeechClientStatus_AuthenticationExpired:  return @"SpeechClientStatus_AuthenticationExpired";
        case SpeechClientStatus_LimitsExceeded:         return @"SpeechClientStatus_LimitsExceeded";
        case SpeechClientStatus_AudioOutputFailed:      return @"SpeechClientStatus_AudioOutputFailed";
        case SpeechClientStatus_MicrophoneInUse:        return @"SpeechClientStatus_MicrophoneInUse";
        case SpeechClientStatus_MicrophoneUnavailable:  return @"SpeechClientStatus_MicrophoneUnavailable";
        case SpeechClientStatus_MicrophoneStatusUnknown:return @"SpeechClientStatus_MicrophoneStatusUnknown";
        case SpeechClientStatus_InvalidArgument:        return @"SpeechClientStatus_InvalidArgument";
    }
    
    return [[NSString alloc] initWithFormat:@"Unknown error: %d\n", errorCode];
}

/**
 * Converts a Confidence value to a string
 * @param confidence The confidence value.
 * @return The string representation of the confidence enumeration.
 */
NSString* ConvertSpeechRecoConfidenceEnumToString(Confidence confidence) {
    switch (confidence) {
        case SpeechRecoConfidence_None:
            return @"None";
            
        case SpeechRecoConfidence_Low:
            return @"Low";
            
        case SpeechRecoConfidence_Normal:
            return @"Normal";
            
        case SpeechRecoConfidence_High:
            return @"High";
    }
}

/**
 * Event handler for when the user wants to display the list of modes.
 * @param sender The sending caller.
 */
-(IBAction)ChangeModeButton_Click:(id)sender {
    //[self showMenu:TRUE];
}

/**
 * Appends text to the edit control.
 * @param text The text to set.
 */
- (void)setText:(NSString*)text {
    NSLog(@"%@", text);
    //UNIVERSAL_TEXTVIEW_SETTEXT(self.quoteText, text);
    //[self.quoteText scrollRangeToVisible:NSMakeRange([text length] - 1, 1)];
}

@end
