//
//  Ganzbot.m
//  Ganzbot Controller
//
//  Created by Jeremy Gillick on 1/15/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "Ganzbot.h"
#import "GanzbotPrefs.h"
#import "AudioDevices.h"
#import "RegexKitLite.h"

#define DEFAULT_RATE 130.0

@implementation Ganzbot
@synthesize queue;

- (id)init {
	self = [super init];
	
	if(self){
		prefs = [GanzbotPrefs loadPrefs];
		
		// Synth and speech file
		speechFile = @"/Users/jeremy/speech.aif";
		synth = [[NSSpeechSynthesizer alloc] init];
		[synth setDelegate:self];
		
	}
	
	return self;
}

- (id) initWithQueue: (GanzbotQueue *)useQueue {
	queue = useQueue;
	return [self init];
}


/**
 * Queue up a message to be spoken
 */
- (void)say: (NSString *)message {	
	NSDictionary *msg = [self decodeMessage:message];
	NSString *text = [msg objectForKey:@"text"];
	text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if([text isEqualTo:@""]){
		return;
	}
	
	[self say:[msg objectForKey:@"text"]
	withVoice:[msg objectForKey:@"voice"] 
	 withRate:[msg objectForKey:@"rate"] ];
}

/**
 * Add a message with rate and voice values
 */
- (void) say: (NSString *)message withVoice:(NSString *)voiceName withRate:(NSNumber *)rate{
	[queue add:message voice:voiceName rate:rate];
	[self speakNextInQueue];
}

/**
 * Extract and set the voice and rate markers from the message
 */
- (NSDictionary *) decodeMessage: (NSString *)encoded{
	NSMutableDictionary *details = [[NSMutableDictionary alloc] init];
	
	// Separate message from synth options
	NSString *regexString = @"^\\s*(\\[(r|v)[^\\]]*\\])?(.*)$";
	NSString *synthValues = [encoded stringByMatching:regexString capture:1L];
	NSString *message = [encoded stringByMatching:regexString capture:3L];
	
	// Extract rate and voice
	float useRate;
	NSString *useVoice = nil;
	NSString *voice = [synthValues stringByMatching:@"v('|\")([a-zA-Z ]*)('|\")" capture:2L];
	NSString *rate = [synthValues stringByMatching:@"r([0-9]*)" capture:1L];
	
	// Set values we can use
	if(!rate || rate == 0){
		useRate = DEFAULT_RATE;
	}
	else{
		useRate = [rate floatValue];
	}
	
	if(voice && ![voice isEqualToString:@""]){
		// Get voice ID from name
		voice = [voice lowercaseString];
		NSArray *voices = [NSSpeechSynthesizer availableVoices];
		for (NSInteger i = 0; i < [voices count]; i++) {
			NSString *voiceId = [voices objectAtIndex:i];
			NSDictionary *voiceAttr = [NSSpeechSynthesizer attributesForVoice: voiceId];
			NSString *name = (NSString *)[voiceAttr valueForKey: @"VoiceName"];
			name = [name lowercaseString];
			
			NSLog(@"%@ = %@", name, voice);
			
			if([name isEqualTo:voice]){
				useVoice = name;
				break;
			}
		}
	}
	if(!useVoice){
		useVoice = [prefs stringForKey: @"voice"];	
	}
	
	// Put it all together
	[details setObject:message forKey:@"text"];
	[details setObject:useVoice forKey:@"voice"];
	[details setObject:[NSNumber numberWithFloat: useRate] forKey:@"rate"];
	
	return details;
}

/**
 * Return the voice ID for the short name
 */
- (NSDictionary *)getVoiceForName: (NSString *)name {
	NSDictionary *voiceAttr = nil;
	
	// Empty name
	if([name isEqualToString:@""]){
		return nil;
	}
	
	// Is the name actually the ID
	voiceAttr = [NSSpeechSynthesizer attributesForVoice: name];
	if(voiceAttr){
		return voiceAttr;
	}
	
	// Loop through the voices
	name = [name lowercaseString];
	NSArray *voices = [NSSpeechSynthesizer availableVoices];
	for (NSInteger i = 0; i < [voices count]; i++) {
		NSString *voiceId = [voices objectAtIndex:i];
		voiceAttr = [NSSpeechSynthesizer attributesForVoice: voiceId];
		NSString *voiceName = (NSString *)[voiceAttr valueForKey: @"VoiceName"];
		voiceName = [voiceName lowercaseString];
		
		NSLog(@"%@ = %@", voiceName, name);
		
		if([name isEqualTo:voiceName]){
			return voiceAttr;
		}
	}
	
	return nil;
}

/**
 * Read the next item in the queue
 */
- (void)speakNextInQueue {
	if( [synth isSpeaking] || (sound && [sound isPlaying]) ){
		NSLog(@"Currently speaking");
		return;
	}
	
	// Create audio file
	currentMessage = [queue getNextInQueue];
	if (currentMessage) {
		NSURL *url = [NSURL fileURLWithPath:speechFile];
		NSNumber *rate = [currentMessage valueForKey:@"rate"];
		NSString *message = [currentMessage valueForKey:@"text"];
		NSString *voice = [currentMessage valueForKey:@"voice"];
		NSDictionary *voiceAttr = [self getVoiceForName:voice];
		
		// Voice ID
		if(voiceAttr){
			voice = [voiceAttr objectForKey:@"VoiceIdentifier"];
		}
		else{
			voice = [prefs stringForKey: @"voice"];
		}
		
		// Empty message?
		message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([message isEqualTo:@""]){
			[queue markAsSpoken:currentMessage];
			[self speakNextInQueue];
			return;
		}
		
		// Zero rate
		if([rate floatValue] == 0.0){
			rate = [NSNumber numberWithFloat:DEFAULT_RATE];
		}
		
		// Synth speech properties
		[synth setVoice: voice];
		[synth setRate: [rate floatValue]];
		
		// Save synth to audio file
		[synth startSpeakingString:message toURL:url];
	}
}

/**
 * Played the saved speech synthesised message
 */
- (void)speechSynthesizer:(NSSpeechSynthesizer *)sender didFinishSpeaking:(BOOL)success {
	sound = [[NSSound alloc] initWithContentsOfFile:speechFile byReference:YES];
	
	NSDictionary *device = [GanzbotPrefs getAudioDevice];
	[sound setPlaybackDeviceIdentifier: [device valueForKey:@"uid"] ];
	[sound setDelegate:self];
	[sound play];
}

/**
 * Message done, play the next in queue
 */
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finishedPlaying {
	if (currentMessage) {
		[queue markAsSpoken:currentMessage];
	}
	[self speakNextInQueue];
}

- (void) setRate: (float) speed {
	[synth setRate: speed];
}
	   
- (void)dealloc {
	[synth release];
	
	if(sound){
		[sound release];
	}
	
	[super dealloc];
}

@end
