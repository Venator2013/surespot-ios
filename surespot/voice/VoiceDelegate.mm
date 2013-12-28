//
//  VoiceDelegate.m
//  surespot
//
//  Created by Adam on 12/27/13.
//  Copyright (c) 2013 2fours. All rights reserved.
//

#import "VoiceDelegate.h"
#import "DDLog.h"
#import "IdentityController.h"
#import "EncryptionController.h"
#import "UIUtils.h"
#import "NSData+Base64.h"
#import "ChatController.h"
#import "ChatDataSource.h"
#import "NetworkController.h"
#import "AudioUnit/AudioUnit.h"
#import "CAXException.h"
#import "SurespotAppDelegate.h"

#ifdef DEBUG
static const int ddLogLevel = LOG_LEVEL_INFO;
#else
static const int ddLogLevel = LOG_LEVEL_OFF;
#endif



@interface VoiceDelegate()
@property (nonatomic, strong) NSString * username;
@property (nonatomic, strong) NSString * theirUsername;
@property (nonatomic, strong) NSString * ourVersion;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *player;
@end

@implementation VoiceDelegate

//@synthesize window;
@synthesize view;

@synthesize rioUnit;
@synthesize unitIsRunning;
@synthesize unitHasBeenCreated;
@synthesize inputProc;




- (id) initWithUsername: (NSString *) username
             ourVersion:(NSString *) ourVersion


{
    // Call superclass's initializer
    self = [super init];
    if( !self ) return nil;
    _username = username;
    _ourVersion = ourVersion;
    return self;
}

-(void) prepareRecording {
    
    NSArray *pathComponents = [NSArray arrayWithObjects:
                               [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                               @"MyAudioMemo.m4a",
                               nil];
    NSURL *outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];
    
    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    
    // Define the recorder setting
    NSMutableDictionary *recordSetting = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithInt:kAudioFormatMPEG4AAC] , AVFormatIDKey,
                                          [NSNumber numberWithInteger: 12000], AVEncoderBitRateKey,
                                          [NSNumber numberWithFloat: 12000],AVSampleRateKey,
                                          [NSNumber numberWithInt:1],AVNumberOfChannelsKey, nil];
    
    // Initiate and prepare the recorder
    //    _recorder = [[AVAudioRecorder alloc] initWithURL:outputFileURL settings:recordSetting error:nil];
    //    _recorder.delegate = self;
    //    _recorder.meteringEnabled = YES;
    //    [_recorder prepareToRecord];
    
    [self initScope];
}

-(void) startRecordingUsername: (NSString *) username {
    DDLogInfo(@"start recording");
    if (_player.playing) {
        [_player stop];
    }
    
    if (!_recorder.recording) {
        _theirUsername = username;
        //AVAudioSession *session = [AVAudioSession sharedInstance];
        //  [session setActive:YES error:nil];
        
        // Start recording
        //     [_recorder record];
        //  [recordPauseButton setTitle:@"Pause" forState:UIControlStateNormal];
        
        AudioSessionSetActive(true);
        
    }
}

-(void) stopRecordingSend: (BOOL) send {
    DDLogInfo(@"stop recording");
    if (_recorder.recording) {
        [_recorder stop];
        
        
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        [audioSession setActive:NO error:nil];
        
        _player = [[AVAudioPlayer alloc] initWithContentsOfURL:_recorder.url error:nil];
        [_player setDelegate:self];
        [_player play];
        
        
        
        if (send) {
            [self uploadVoiceUrl:_recorder.url];
        }
        
        else {
            //todo delete file
        }
        
        
    }
}


-(void) uploadVoiceUrl: (NSURL *) url {
    //    if (!image) {
    //        [self stopProgress];
    //        [UIUtils showToastKey:NSLocalizedString(@"could_not_upload_image", nil) duration:2];
    //        return;
    //    }
    //
    
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [[IdentityController sharedInstance] getTheirLatestVersionForUsername:_theirUsername callback:^(NSString *version) {
            if (version) {
                //encrypt and upload the voice data
                NSData * voiceData = [NSData dataWithContentsOfURL: url];
                NSData * iv = [EncryptionController getIv];
                
                //encrypt
                [EncryptionController symmetricEncryptData:voiceData
                                                ourVersion:_ourVersion
                                             theirUsername:_theirUsername
                                              theirVersion:version
                                                        iv:iv
                                                  callback:^(NSData * encryptedImageData) {
                                                      if (encryptedImageData) {
                                                          //create message
                                                          SurespotMessage * message = [SurespotMessage new];
                                                          message.from = _username;
                                                          message.fromVersion = _ourVersion;
                                                          message.to = _theirUsername;
                                                          message.toVersion = version;
                                                          message.mimeType = MIME_TYPE_M4A;
                                                          message.iv = [iv base64EncodedStringWithSeparateLines:NO];
                                                          //      NSString * key = [@"voiceKey_" stringByAppendingString: message.iv];
                                                          //    message.data = key;
                                                          
                                                          //                                                          DDLogInfo(@"adding local image to cache %@", key);
                                                          //                                                          [[[SDWebImageManager sharedManager] imageCache] storeImage:scaledImage imageData:encryptedImageData forKey:key toDisk:YES];
                                                          
                                                          //add message locally before we upload it
                                                          ChatDataSource * cds = [[ChatController sharedInstance] getDataSourceForFriendname:_theirUsername];
                                                          if (cds) {
                                                              [cds addMessage:message refresh:YES];
                                                          }
                                                          
                                                          //upload image to server
                                                          //     DDLogInfo(@"uploading image %@ to server", key);
                                                          [[NetworkController sharedInstance] postFileStreamData:encryptedImageData
                                                                                                      ourVersion:_ourVersion
                                                                                                   theirUsername:_theirUsername
                                                                                                    theirVersion:version
                                                                                                          fileid:[iv SR_stringByBase64Encoding]
                                                                                                        mimeType:MIME_TYPE_M4A
                                                                                                    successBlock:^(AFHTTPRequestOperation *operation, id responseObject) {
                                                                                                        //  DDLogInfo(@"uploaded voice %@ to server successfully", key);
                                                                                                        //[self stopProgress];
                                                                                                    } failureBlock:^(AFHTTPRequestOperation *operation, NSError *error) {
                                                                                                        //    DDLogInfo(@"uploaded voice %@ to server failed, statuscode: %d", key, operation.response.statusCode);
                                                                                                        //  [self stopProgress];
                                                                                                        if (operation.response.statusCode == 402) {
                                                                                                            message.errorStatus = 402;
                                                                                                        }
                                                                                                        else {
                                                                                                            message.errorStatus = 500;
                                                                                                        }
                                                                                                        
                                                                                                        [cds postRefresh];
                                                                                                    }];
                                                      }
                                                      else {
                                                          //  [self stopProgress];
                                                          [UIUtils showToastKey:NSLocalizedString(@"could_not_upload_image", nil) duration:2];
                                                          
                                                      }
                                                  }];
                
            }
            else {
                [UIUtils showToastKey:NSLocalizedString(@"could_not_upload_image", nil) duration:2];
            }
        }];
    });
}



#pragma mark-

CGPathRef CreateRoundedRectPath(CGRect RECT, CGFloat cornerRadius)
{
	CGMutablePathRef		path;
	path = CGPathCreateMutable();
	
	double		maxRad = MAX(CGRectGetHeight(RECT) / 2., CGRectGetWidth(RECT) / 2.);
	
	if (cornerRadius > maxRad) cornerRadius = maxRad;
	
	CGPoint		bl, tl, tr, br;
	
	bl = tl = tr = br = RECT.origin;
	tl.y += RECT.size.height;
	tr.y += RECT.size.height;
	tr.x += RECT.size.width;
	br.x += RECT.size.width;
	
	CGPathMoveToPoint(path, NULL, bl.x + cornerRadius, bl.y);
	CGPathAddArcToPoint(path, NULL, bl.x, bl.y, bl.x, bl.y + cornerRadius, cornerRadius);
	CGPathAddLineToPoint(path, NULL, tl.x, tl.y - cornerRadius);
	CGPathAddArcToPoint(path, NULL, tl.x, tl.y, tl.x + cornerRadius, tl.y, cornerRadius);
	CGPathAddLineToPoint(path, NULL, tr.x - cornerRadius, tr.y);
	CGPathAddArcToPoint(path, NULL, tr.x, tr.y, tr.x, tr.y - cornerRadius, cornerRadius);
	CGPathAddLineToPoint(path, NULL, br.x, br.y + cornerRadius);
	CGPathAddArcToPoint(path, NULL, br.x, br.y, br.x - cornerRadius, br.y, cornerRadius);
	
	CGPathCloseSubpath(path);
	
	CGPathRef				ret;
	ret = CGPathCreateCopy(path);
	CGPathRelease(path);
	return ret;
}

void cycleOscilloscopeLines()
{
	// Cycle the lines in our draw buffer so that they age and fade. The oldest line is discarded.
	int drawBuffer_i;
	for (drawBuffer_i=(kNumDrawBuffers - 2); drawBuffer_i>=0; drawBuffer_i--)
		memmove(drawBuffers[drawBuffer_i + 1], drawBuffers[drawBuffer_i], drawBufferLen);
}

#pragma mark -Audio Session Interruption Listener

void rioInterruptionListener(void *inClientData, UInt32 inInterruption)
{
    try {
        printf("Session interrupted! --- %s ---", inInterruption == kAudioSessionBeginInterruption ? "Begin Interruption" : "End Interruption");
        
        VoiceDelegate *THIS = (__bridge VoiceDelegate*)inClientData;
        
        if (inInterruption == kAudioSessionEndInterruption) {
            // make sure we are again the active session
            XThrowIfError(AudioSessionSetActive(true), "couldn't set audio session active");
            XThrowIfError(AudioOutputUnitStart(THIS->rioUnit), "couldn't start unit");
        }
        
        if (inInterruption == kAudioSessionBeginInterruption) {
            XThrowIfError(AudioOutputUnitStop(THIS->rioUnit), "couldn't stop unit");
        }
    } catch (CAXException e) {
        char buf[256];
        fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
    }
}

#pragma mark -Audio Session Property Listener

void propListener(	void *                  inClientData,
                  AudioSessionPropertyID	inID,
                  UInt32                  inDataSize,
                  const void *            inData)
{
	VoiceDelegate *THIS = (__bridge VoiceDelegate*)inClientData;
	if (inID == kAudioSessionProperty_AudioRouteChange)
	{
		try {
            UInt32 isAudioInputAvailable;
            UInt32 size = sizeof(isAudioInputAvailable);
            XThrowIfError(AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &size, &isAudioInputAvailable), "couldn't get AudioSession AudioInputAvailable property value");
            
            if(THIS->unitIsRunning && !isAudioInputAvailable)
            {
                XThrowIfError(AudioOutputUnitStop(THIS->rioUnit), "couldn't stop unit");
                THIS->unitIsRunning = false;
            }
            
            else if(!THIS->unitIsRunning && isAudioInputAvailable)
            {
                XThrowIfError(AudioSessionSetActive(true), "couldn't set audio session active\n");
                
                if (!THIS->unitHasBeenCreated)	// the rio unit is being created for the first time
                {
                    XThrowIfError(SetupRemoteIO(THIS->rioUnit, THIS->inputProc, THIS->thruFormat), "couldn't setup remote i/o unit");
                    THIS->unitHasBeenCreated = true;
                    
                    THIS->dcFilter = new DCRejectionFilter[THIS->thruFormat.NumberChannels()];
                    
                    UInt32 maxFPS;
                    size = sizeof(maxFPS);
                    XThrowIfError(AudioUnitGetProperty(THIS->rioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, &size), "couldn't get the remote I/O unit's max frames per slice");
                    
                 //   THIS->fftBufferManager = new FFTBufferManager(maxFPS);
                   // THIS->l_fftData = new int32_t[maxFPS/2];
                    
                    THIS->oscilLine = (GLfloat*)malloc(drawBufferLen * 2 * sizeof(GLfloat));
                }
                
                XThrowIfError(AudioOutputUnitStart(THIS->rioUnit), "couldn't start unit");
                THIS->unitIsRunning = true;
            }
            
			// we need to rescale the sonogram view's color thresholds for different input
			CFStringRef newRoute;
			size = sizeof(CFStringRef);
			XThrowIfError(AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &size, &newRoute), "couldn't get new audio route");
			if (newRoute)
			{
				CFShow(newRoute);
			}
		} catch (CAXException e) {
			char buf[256];
			fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		}
		
	}
}

#pragma mark -RIO Render Callback

static OSStatus	PerformThru(
							void						*inRefCon,
							AudioUnitRenderActionFlags 	*ioActionFlags,
							const AudioTimeStamp 		*inTimeStamp,
							UInt32 						inBusNumber,
							UInt32 						inNumberFrames,
							AudioBufferList 			*ioData)
{
	VoiceDelegate *THIS = (__bridge VoiceDelegate *)inRefCon;
	OSStatus err = AudioUnitRender(THIS->rioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, ioData);
	if (err) { printf("PerformThru: error %d\n", (int)err); return err; }
	
	// Remove DC component
	for(UInt32 i = 0; i < ioData->mNumberBuffers; ++i)
		THIS->dcFilter[i].InplaceFilter((Float32*)(ioData->mBuffers[i].mData), inNumberFrames);
	
    // The draw buffer is used to hold a copy of the most recent PCM data to be drawn on the oscilloscope
    if (drawBufferLen != drawBufferLen_alloced)
    {
        int drawBuffer_i;
        
        // Allocate our draw buffer if needed
        if (drawBufferLen_alloced == 0)
            for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
                drawBuffers[drawBuffer_i] = NULL;
        
        // Fill the first element in the draw buffer with PCM data
        for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
        {
            drawBuffers[drawBuffer_i] = (SInt8 *)realloc(drawBuffers[drawBuffer_i], drawBufferLen);
            bzero(drawBuffers[drawBuffer_i], drawBufferLen);
        }
        
        drawBufferLen_alloced = drawBufferLen;
    }
    
    int i;
    
    //Convert the floating point audio data to integer (Q7.24)
    err = AudioConverterConvertComplexBuffer(THIS->audioConverter, inNumberFrames, ioData, THIS->drawABL);
    if (err) { printf("AudioConverterConvertComplexBuffer: error %d\n", (int)err); return err; }
    
    SInt8 *data_ptr = (SInt8 *)(THIS->drawABL->mBuffers[0].mData);
    for (i=0; i<inNumberFrames; i++)
    {
        if ((i+drawBufferIdx) >= drawBufferLen)
        {
            cycleOscilloscopeLines();
            drawBufferIdx = -i;
        }
        drawBuffers[0][i + drawBufferIdx] = data_ptr[2];
        data_ptr += 4;
    }
    drawBufferIdx += inNumberFrames;
	
	return err;
}

#pragma mark-

- (void)initScope
{
    
    
	// Turn off the idle timer, since this app doesn't rely on constant touch input
	[UIApplication sharedApplication].idleTimerDisabled = YES;
	
	// Initialize our remote i/o unit
	
	inputProc.inputProc = PerformThru;
	inputProc.inputProcRefCon = (__bridge void *) self;

	try {
      		
		// Initialize and configure the audio session
		XThrowIfError(AudioSessionInitialize(NULL, NULL, rioInterruptionListener, (__bridge void *) self), "couldn't initialize audio session");
        
		UInt32 audioCategory = kAudioSessionCategory_PlayAndRecord;
		XThrowIfError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(audioCategory), &audioCategory), "couldn't set audio category");
		XThrowIfError(AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, propListener, (__bridge  void *) self), "couldn't set property listener");
        
		Float32 preferredBufferSize = .005;
		XThrowIfError(AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration, sizeof(preferredBufferSize), &preferredBufferSize), "couldn't set i/o buffer duration");
		
		UInt32 size = sizeof(hwSampleRate);
		XThrowIfError(AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate, &size, &hwSampleRate), "couldn't get hw sample rate");
		
		XThrowIfError(AudioSessionSetActive(true), "couldn't set audio session active\n");
        
		XThrowIfError(SetupRemoteIO(rioUnit, inputProc, thruFormat), "couldn't setup remote i/o unit");
		unitHasBeenCreated = true;
        
        drawFormat.SetAUCanonical(2, false);
        drawFormat.mSampleRate = 44100;
        
        XThrowIfError(AudioConverterNew(&thruFormat, &drawFormat, &audioConverter), "couldn't setup AudioConverter");
		
		dcFilter = new DCRejectionFilter[thruFormat.NumberChannels()];
        
		UInt32 maxFPS;
		size = sizeof(maxFPS);
		XThrowIfError(AudioUnitGetProperty(rioUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFPS, &size), "couldn't get the remote I/O unit's max frames per slice");
		
		//fftBufferManager = new FFTBufferManager(maxFPS);
		//l_fftData = new int32_t[maxFPS/2];
        
        drawABL = (AudioBufferList*) malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
        drawABL->mNumberBuffers = 2;
        for (UInt32 i=0; i<drawABL->mNumberBuffers; ++i)
        {
            drawABL->mBuffers[i].mData = (SInt32*) calloc(maxFPS, sizeof(SInt32));
            drawABL->mBuffers[i].mDataByteSize = maxFPS * sizeof(SInt32);
            drawABL->mBuffers[i].mNumberChannels = 1;
        }
		
		oscilLine = (GLfloat*)malloc(drawBufferLen * 2 * sizeof(GLfloat));
        
		XThrowIfError(AudioOutputUnitStart(rioUnit), "couldn't start remote i/o unit");
        
		size = sizeof(thruFormat);
		XThrowIfError(AudioUnitGetProperty(rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &thruFormat, &size), "couldn't get the remote I/O unit's output client format");
		
		unitIsRunning = 1;
	}
	catch (CAXException &e) {
		char buf[256];
		fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		unitIsRunning = 0;
		if (dcFilter) delete[] dcFilter;
        if (drawABL)
        {
            for (UInt32 i=0; i<drawABL->mNumberBuffers; ++i)
                free(drawABL->mBuffers[i].mData);
            free(drawABL);
            drawABL = NULL;
        }
        //	if (url) CFRelease(url);
	}
	catch (...) {
		fprintf(stderr, "An unknown error occurred\n");
		unitIsRunning = 0;
		if (dcFilter) delete[] dcFilter;
        if (drawABL)
        {
            for (UInt32 i=0; i<drawABL->mNumberBuffers; ++i)
                free(drawABL->mBuffers[i].mData);
            free(drawABL);
            drawABL = NULL;
        }
        //	if (url) CFRelease(url);
	}
	
    
    view = [[EAGLView alloc] initWithFrame: CGRectMake(0, 200, 320, 200) ];
    [((SurespotAppDelegate *)[[UIApplication sharedApplication] delegate]).overlayView addSubview:view];
	// Set ourself as the delegate for the EAGLView so that we get drawing and touch events
	view.delegate = self;
	   
	
	// Set up the view to refresh at 20 hz
	[view setAnimationInterval:1./20.];
	[view startAnimation];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	//start animation now that we're in the foreground
    view.applicationResignedActive = NO;
	[view startAnimation];
	AudioSessionSetActive(true);
}

- (void)applicationWillResignActive:(UIApplication *)application {
	//stop animation before going into background
    view.applicationResignedActive = YES;
    [view stopAnimation];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
}


- (void)dealloc
{
	delete[] dcFilter;
	//delete fftBufferManager;
    if (drawABL)
    {
        for (UInt32 i=0; i<drawABL->mNumberBuffers; ++i)
            free(drawABL->mBuffers[i].mData);
        free(drawABL);
        drawABL = NULL;
    }
    
	
	free(oscilLine);
    
}







- (void)clearTextures
{
	bzero(texBitBuffer, sizeof(UInt32) * 512);
}


- (void)drawOscilloscope
{
	// Clear the view
	glClear(GL_COLOR_BUFFER_BIT);
	
    glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE);
	
	glColor4f(0., 0., 0., 1.);
	
	glPushMatrix();
    
//		
//	glEnable(GL_TEXTURE_2D);
//	glEnableClientState(GL_VERTEX_ARRAY);
//	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
//	
//	{
//		// Draw our background oscilloscope screen
//		const GLfloat vertices[] = {
//			0., 0.,
//			320., 0.,
//			0.,  200.,
//			320.,  200.,
//		};
//		const GLshort texCoords[] = {
//			0, 0,
//			1, 0,
//			0, 1,
//			1, 1,
//		};
//		
//		
//		//glBindTexture(GL_TEXTURE_2D, bgTexture);
//		
//		glVertexPointer(2, GL_FLOAT, 0, vertices);
//		glTexCoordPointer(2, GL_SHORT, 0, texCoords);
//		
//		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
//	}
//	
    
    
	GLfloat *oscilLine_ptr;
	GLfloat max = drawBufferLen;
	SInt8 *drawBuffer_ptr;
	
	// Alloc an array for our oscilloscope line vertices
	if (resetOscilLine) {
		oscilLine = (GLfloat*)realloc(oscilLine, drawBufferLen * 2 * sizeof(GLfloat));
		resetOscilLine = NO;
	}
	
//	glPushMatrix();
	
	// Translate to the left side and vertical center of the screen, and scale so that the screen coordinates
	// go from 0 to 1 along the X, and -1 to 1 along the Y
	glTranslatef(1., 100., 0.);
	glScalef(320., 100., 1.);
	
	// Set up some GL state for our oscilloscope lines
	glDisable(GL_TEXTURE_2D);
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisableClientState(GL_COLOR_ARRAY);
	glDisable(GL_LINE_SMOOTH);
	glLineWidth(2.);
	
	int drawBuffer_i;
	// Draw a line for each stored line in our buffer (the lines are stored and fade over time)
	for (drawBuffer_i=0; drawBuffer_i<kNumDrawBuffers; drawBuffer_i++)
	{
		if (!drawBuffers[drawBuffer_i]) continue;
		
		oscilLine_ptr = oscilLine;
		drawBuffer_ptr = drawBuffers[drawBuffer_i];
		
		GLfloat i;
		// Fill our vertex array with points
		for (i=0.; i<max; i=i+1.)
		{
			*oscilLine_ptr++ = i/max;
			*oscilLine_ptr++ = (Float32)(*drawBuffer_ptr++) / 128.;
		}
		
		// If we're drawing the newest line, draw it in solid blue. Otherwise, draw it in a faded blue.
		if (drawBuffer_i == 0)

			glColor4f(0.2, 0.71, 0.898, 1.);
		else
			glColor4f(0.2, 0.71, 0.898, (.24 * (1. - ((GLfloat)drawBuffer_i / (GLfloat)kNumDrawBuffers))));
		
		// Set up vertex pointer,
		glVertexPointer(2, GL_FLOAT, 0, oscilLine);
		
		// and draw the line.
		glDrawArrays(GL_LINE_STRIP, 0, drawBufferLen);
		
	}
	
//	glPopMatrix();
    
	glPopMatrix();
}


- (void)drawView:(id)sender forTime:(NSTimeInterval)time
{
	[self drawOscilloscope];
	
}


@end