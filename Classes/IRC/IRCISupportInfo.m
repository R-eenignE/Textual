/* ********************************************************************* 
				   _____         _               _
				  |_   _|____  _| |_ _   _  __ _| |
                    | |/ _ \ \/ / __| | | |/ _` | |
                    | |  __/>  <| |_| |_| | (_| | |
                    |_|\___/_/\_\\__|\__,_|\__,_|_|

 Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 Copyright (c) 2010 - 2015 Codeux Software, LLC & respective contributors.
        Please see Acknowledgements.pdf for additional information.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Textual and/or "Codeux Software, LLC", nor the 
      names of its contributors may be used to endorse or promote products 
      derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.

 *********************************************************************** */

NS_ASSUME_NONNULL_BEGIN

#define _channelUserModeValue		100

NSString * const IRCISupportRawSuffix = @"are supported by this server";

@interface IRCISupportInfo ()
@property (nonatomic, weak) IRCClient *client;
@property (nonatomic, copy) NSArray<NSDictionary *> *cachedConfiguration;
@property (nonatomic, assign, readwrite) NSUInteger maximumNicknameLength;
@property (nonatomic, assign, readwrite) NSUInteger maximumModeCount;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *channelNamePrefixes;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSNumber *> *channelModes;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSArray *> *userModeSymbols;
@property (nonatomic, copy, readwrite, nullable) NSString *networkName;
@property (nonatomic, copy, readwrite, nullable) NSString *networkNameFormatted;
@property (nonatomic, copy, readwrite, nullable) NSString *privateMessageNicknamePrefix;
@end

@implementation IRCISupportInfo

ClassWithDesignatedInitializerInitMethod

- (instancetype)initWithClient:(IRCClient *)client
{
	NSParameterAssert(client != nil);

	if ((self = [super init])) {
		self.client = client;

		[self prepareInitialState];

		return self;
	}
	
	return nil;
}

- (void)prepareInitialState
{
	[self reset];
}

- (void)reset
{
    self.cachedConfiguration = @[];
    
	self.serverAddress = nil;
	
	self.networkName = nil;
	self.networkNameFormatted = nil;

	self.channelNamePrefixes = @[@"#"];

	self.maximumModeCount = TXMaximumNodesPerModeCommand;
	self.maximumNicknameLength = IRCProtocolDefaultNicknameMaximumLength;

	self.userModeSymbols = @{
		@"modeSymbols" : @[@"o", @"v"],
		@"characters" : @[@"@", @"+"]
	};

	self.channelModes = @{
		@"o" : @(_channelUserModeValue),
		@"v" : @(_channelUserModeValue)
	};
	
	self.privateMessageNicknamePrefix = nil;
}

- (void)processConfigurationData:(NSString *)configurationData
{
	NSParameterAssert(configurationData != nil);

	if ([configurationData hasSuffix:IRCISupportRawSuffix]) {
		configurationData = [configurationData substringToIndex:(configurationData.length - IRCISupportRawSuffix.length)];
	}

	configurationData = configurationData.trim;

	if (configurationData.length == 0) {
		return;
	}

	IRCClient *client = self.client;

    NSMutableDictionary *configuration = [NSMutableDictionary dictionary];

	NSArray *segments = [configurationData componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	for (NSString *segment in segments) {
		if (segment.length == 0) { // Blank
			continue;
		}

		NSString *segmentKey = segment;
		NSString *segmentValue = nil;

		NSInteger equalSignPosition = [segment stringPosition:@"="];

		if (equalSignPosition > 0) {
			segmentKey = [segment substringToIndex:equalSignPosition];
			segmentValue = [segment substringAfterIndex:equalSignPosition];

			if (segmentValue.length == 0) {
				segmentValue = nil;
			}
		}

		if (segmentValue) {
			configuration[segmentKey] = segmentValue;
		} else {
			configuration[segmentKey] = @(YES);
		}

		if (segmentValue) {
			if ([segmentKey isEqualIgnoringCase:@"PREFIX"]) {
				[self parseUserModeSymbols:segmentValue];
			} else if ([segmentKey isEqualIgnoringCase:@"CHANMODES"]) {
				[self parseChannelModes:segmentValue];
			} else if ([segmentKey isEqualIgnoringCase:@"MODES"]) {
				NSInteger maximumModesCount = segmentValue.integerValue;

				if (maximumModesCount > 0) {
					self.maximumModeCount = maximumModesCount;
				}
			} else if ([segmentKey isEqualIgnoringCase:@"NICKLEN"]) {
				NSInteger maximumNicknameLength = segmentValue.integerValue;

				if (maximumNicknameLength > 0) {
					self.maximumNicknameLength = maximumNicknameLength;
				}
			} else if ([segmentKey isEqualIgnoringCase:@"NETWORK"]) {
				self.networkName = segmentValue;
				self.networkNameFormatted = TXTLS(@"IRC[1067]", segmentValue);
			} else if ([segmentKey isEqualIgnoringCase:@"CHANTYPES"]) {
				NSArray *channelNamePrefixes = segmentValue.characterStringBuffer;

				if (channelNamePrefixes.count > 0) {
					self.channelNamePrefixes = channelNamePrefixes;
				}
			} else if ([segmentKey isEqualIgnoringCase:@"ZNCPREFIX"]) {
				self.privateMessageNicknamePrefix = segmentValue;
			}
		}

		if ([segmentKey isEqualIgnoringCase:@"MONITOR"]) {
			// freenode advertises support for MONITOR but does not respond to command
			if ([self.serverAddress hasSuffix:@".freenode.net"]) {
				continue;
			}

			[client enableCapacity:ClientIRCv3SupportedCapacityMonitorCommand];
		} else if ([segmentKey isEqualIgnoringCase:@"WATCH"]) {
			[client enableCapacity:ClientIRCv3SupportedCapacityWatchCommand];
		} else if ([segmentKey isEqualIgnoringCase:@"NAMESX"]) {
			if ([client isCapacityEnabled:ClientIRCv3SupportedCapacityMultiPreifx] == NO) {
				[client sendLine:@"PROTOCTL NAMESX"];

				[client enableCapacity:ClientIRCv3SupportedCapacityMultiPreifx];
			}
		} else if ([segmentKey isEqualIgnoringCase:@"UHNAMES"]) {
			if ([client isCapacityEnabled:ClientIRCv3SupportedCapacityUserhostInNames] == NO) {
				[client sendLine:@"PROTOCTL UHNAMES"];

				[client enableCapacity:ClientIRCv3SupportedCapacityUserhostInNames];
			}
		}
	} // while()

    self.cachedConfiguration = [self.cachedConfiguration arrayByAddingObject:configuration];
}

- (nullable NSString *)stringValueForConfiguration:(NSDictionary<NSString *, id> *)configuration
{
	NSParameterAssert(configuration != nil);

	/* This takes our cached configuration data and builds it into what it would look like if we
	 were to receive an actual 005. The only difference is this method formats each token that
	 is in our configuration cache to make them easier to see. We use bold for the tokens. 
	 This is pretty much only used in developer mode, but it could have other uses? */

	if (configuration.count == 0) {
		return nil;
	}

	NSMutableString *stringValue = [NSMutableString string];

	NSArray *sortedKeys = configuration.sortedDictionaryKeys;

	for (NSString *key in sortedKeys) {
		id value = configuration[key];

		if ([value isKindOfClass:[NSString class]]) {
			[stringValue appendFormat:@"\002%@\002=%@ ", key, value];
		} else {
			[stringValue appendFormat:@"\002%@ \002", key];
		}
	}

	[stringValue appendString:IRCISupportRawSuffix];

	return [stringValue copy];
}

- (nullable NSString *)stringValueForLastUpdate
{
	NSDictionary *configuration = self.cachedConfiguration.lastObject;

	if (configuration == nil) {
		return nil;
	}

	return [self stringValueForConfiguration:configuration];
}

- (NSArray<IRCModeInfo *> *)parseModes:(NSString *)modeString
{
	NSParameterAssert(modeString != nil);

	NSMutableArray<IRCModeInfo *> *modes = [NSMutableArray array];
	
	NSMutableString *modeStringMutable = [modeString mutableCopy];
	
	BOOL modeIsSet = NO;
	
	do {
		NSString *nextToken = modeStringMutable.token;

		if (nextToken.length == 0) {
			break;
		}

		UniChar nextCharacter = [nextToken characterAtIndex:0];

		if (nextCharacter != '+' && nextCharacter != '-') {
			continue;
		}

		modeIsSet = (nextCharacter == '+');

		nextToken = [nextToken substringFromIndex:1];
		
		for (NSUInteger i = 0; i < nextToken.length; i++) {
			nextCharacter = [nextToken characterAtIndex:i];

			if (nextCharacter == '-') {
				modeIsSet = NO;
			} else if (nextCharacter == '+') {
				modeIsSet = YES;
			} else {
				NSString *modeSymbol = [NSString stringWithUniChar:nextCharacter];

				IRCModeInfoMutable *mode = [IRCModeInfoMutable new];

				mode.modeSymbol = modeSymbol;
				mode.modeIsSet = modeIsSet;

				if ([self modeHasParameter:modeSymbol whenModeIsSet:modeIsSet]) {
					mode.modeParameter = modeStringMutable.token;
				}

				[modes addObject:[mode copy]];
			}
		}
	} while (modeStringMutable.length > 0);
	
	return [modes copy];
}

- (void)parseUserModeSymbols:(NSString *)modeString
{
	NSParameterAssert(modeString != nil);

	// Format: (qaohv)~&@%+

	/* Perform validaton on placement of parentheses */
	NSInteger openingParenthesesPosition = [modeString stringPosition:@"("];
	NSInteger closingParenthesesPosition = [modeString stringPosition:@")"];

	if (openingParenthesesPosition != 0 &&
		openingParenthesesPosition >= closingParenthesesPosition)
	{
		return;
	}

	/* Extract relevant information and ensure that they are equal lenght */
	NSString *modeSymbols = [modeString substringWithRange:NSMakeRange(1, (closingParenthesesPosition - 1))];

	NSString *characters = [modeString substringAfterIndex:closingParenthesesPosition];

	if (modeSymbols.length != characters.length) {
		return;
	}

	/* Begin processing modes */
	/* The mode symbols and characters are stored in separate arrays because
	 NSDictionary has no sense of order and the order of the user mode
	 symbols is very important to establish rank. */
	NSArray *modeSymbolsArray = modeSymbols.characterStringBuffer;
	NSArray *charactersArray = characters.characterStringBuffer;

	self.userModeSymbols = @{
		 @"modeSymbols" : modeSymbolsArray,
		 @"characters" : charactersArray
	};

	/* Update channel modes array so that we know these mode symbols are for user */
	NSMutableDictionary *channelModes = [self.channelModes mutableCopy];

	for (NSString *modeSymbol in modeSymbolsArray) {
		channelModes[modeSymbol] = @(_channelUserModeValue);
	}

	self.channelModes = channelModes;
}

- (BOOL)modeHasParameter:(NSString *)modeSymbol whenModeIsSet:(BOOL)whenModeIsSet
{
	NSParameterAssert(modeSymbol != nil);

	// Input: CHANMODES=A,B,C,D
	//
	// A = Always has a parameter.			Index: 1
	// B = Always has a parameter.			Index: 2
	// C = Only has a parameter when set.	Index: 3
	// D = Never has a parameter.			Index: 4

	NSUInteger modeIndex = [self.channelModes unsignedIntegerForKey:modeSymbol];

	if (modeIndex == 1 || modeIndex == 2 || modeIndex == _channelUserModeValue) {
		return YES;
	} else if (modeIndex == 3) {
		return whenModeIsSet;
	}

	return NO;
}

- (void)parseChannelModes:(NSString *)modeString
{
	NSParameterAssert(modeString != nil);

	// Input: CHANMODES=A,B,C,D
	//
	// A = Always has a parameter.			Index: 1
	// B = Always has a parameter.			Index: 2
	// C = Only has a parameter when set.	Index: 3
	// D = Never has a parameter.			Index: 4

	NSMutableDictionary *channelModes = [self.channelModes mutableCopy];

	NSArray *modes = [modeString split:@","];

	for (NSUInteger i = 0; i < modes.count; i++) {
		NSString *modeSet = modes[i];
		
		for (NSUInteger j = 0; j < modeSet.length; j++) {
			NSString *modeSymbol = [modeSet stringCharacterAtIndex:j];

			channelModes[modeSymbol] = @(i + 1);
		}
	}

	self.channelModes = channelModes;
}

- (nullable NSString *)userPrefixForModeSymbol:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	NSArray *modeSymbols = self.userModeSymbols[@"modeSymbols"];

	NSUInteger modeSymbolIndex = [modeSymbols indexOfObject:modeSymbol];

	if (modeSymbolIndex == NSNotFound) {
		return 0;
	}

	NSArray *characters = self.userModeSymbols[@"characters"];

	return characters[modeSymbolIndex];
}

- (BOOL)modeSymbolIsUserPrefix:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	return ([self userPrefixForModeSymbol:modeSymbol] != nil);
}

- (nullable NSString *)modeSymbolForUserPrefix:(NSString *)character
{
	NSParameterAssert(character != nil);

	NSArray *characters = self.userModeSymbols[@"characters"];

	NSUInteger characterIndex = [characters indexOfObject:character];

	if (characterIndex == NSNotFound) {
		return nil;
	}

	NSArray *modeSymbols = self.userModeSymbols[@"modeSymbols"];

	return modeSymbols[characterIndex];
}

- (BOOL)characterIsUserPrefix:(NSString *)character
{
	NSParameterAssert(character != nil);

	return ([self modeSymbolForUserPrefix:character] != nil);
}

- (NSUInteger)rankForUserPrefixWithMode:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);

	NSArray *modeSymbols = self.userModeSymbols[@"modeSymbols"];

	NSUInteger modeSymbolIndex = [modeSymbols indexOfObject:modeSymbol];

	if (modeSymbolIndex == NSNotFound) {
		return 0;
	}

	return (IRCISupportInfoHighestUserPrefixRank - modeSymbolIndex);
}

- (NSString *)extractUserPrefixFromChannelNamed:(NSString *)channel
{
	NSParameterAssert(channel != nil);

	if (channel.length < 2) {
		return NSStringEmptyPlaceholder;
	}

	NSArray *channelNamePrefixes = self.channelNamePrefixes;

	NSArray *characters = self.userModeSymbols[@"characters"];

	for (NSString *character in characters) {
		if ([channel hasPrefix:character] == NO) {
			continue;
		}

		NSString *nextCharacter = [channel stringCharacterAtIndex:1];

		if ([channelNamePrefixes containsObject:nextCharacter]) {
			return character;
		}
	}

	return NSStringEmptyPlaceholder;
}

- (IRCModeInfo *)createModeWithSymbol:(NSString *)modeSymbol
{
	NSParameterAssert(modeSymbol != nil);
	
	return [[IRCModeInfo alloc] initWithModeSymbol:modeSymbol];
}

- (IRCModeInfo *)createModeWithSymbol:(NSString *)modeSymbol modeIsSet:(BOOL)modeIsSet modeParameter:(nullable NSString *)modeParameter
{
	NSParameterAssert(modeSymbol != nil);

	return [[IRCModeInfo alloc] initWithModeSymbol:modeSymbol modeIsSet:modeIsSet modeParameter:modeParameter];
}

- (BOOL)configurationReceived
{
	return (self.cachedConfiguration.count > 0);
}

@end

NS_ASSUME_NONNULL_END
