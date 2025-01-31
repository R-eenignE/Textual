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

#import "IRCMessageInternal.h"

NS_ASSUME_NONNULL_BEGIN

@implementation IRCMessage

DESIGNATED_INITIALIZER_EXCEPTION_BODY_BEGIN
- (instancetype)init
{
	ObjectIsAlreadyInitializedAssert

	if ((self = [super init])) {
		[self populateDefaultsPostflight];

		return self;
	}

	return nil;
}

- (nullable instancetype)initWithLine:(NSString *)line
{
	return [self initWithLine:line onClient:nil];
}
DESIGNATED_INITIALIZER_EXCEPTION_BODY_END

- (nullable instancetype)initWithLine:(NSString *)line onClient:(IRCClient *)client
{
	ObjectIsAlreadyInitializedAssert

	if ((self = [super init])) {
		BOOL parseResult = [self parseLine:line forClient:client];

		if (parseResult == NO) {
			return nil;
		}

		[self populateDefaultsPostflight];

		return self;
	}

	return nil;
}

- (void)populateDefaultsPostflight
{
	SetVariableIfNilCopy(self->_command, NSStringEmptyPlaceholder)
	SetVariableIfNilCopy(self->_messageTags, @{})
	SetVariableIfNilCopy(self->_params, @[])
	SetVariableIfNilCopy(self->_receivedAt, [NSDate date])
	SetVariableIfNilCopy(self->_sender, [IRCPrefix new])
}

- (NSUInteger)paramsCount
{
	return self.params.count;
}

- (NSString *)paramAt:(NSUInteger)index
{
	if (index < self.params.count) {
		return self.params[index];
	}

	return NSStringEmptyPlaceholder;
}

- (NSString *)sequence
{
	if (self.params.count < 2) {
		return [self sequence:0];
	} else {
		return [self sequence:1];
	}
}

- (NSString *)sequence:(NSUInteger)index
{
	NSMutableString *sequence = [NSMutableString string];

	NSArray *params = self.params;

	NSUInteger paramsCount = params.count;

	for (NSUInteger i = index; i < paramsCount; i++) {
		NSString *param = params[i];
		
		if (i != index) {
			[sequence appendString:NSStringWhitespacePlaceholder];
		}
		
		[sequence appendString:param];
	}
	
	return [sequence copy];
}

- (void)markAsNotHistoric
{
	self->_isHistoric = NO;
}

- (nullable NSString *)senderNickname
{
	return self.sender.nickname;
}

- (nullable NSString *)senderUsername
{
	return self.sender.username;
}

- (nullable NSString *)senderAddress
{
	return self.sender.address;
}

- (nullable NSString *)senderHostmask
{
	return self.sender.hostmask;
}

- (BOOL)senderIsServer
{
	return self.sender.isServer;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
	IRCMessage *object = [[IRCMessage allocWithZone:zone] init];

	object->_batchToken = [self.batchToken copyWithZone:zone];
	object->_command = [self.command copyWithZone:zone];
	object->_commandNumeric = self.commandNumeric;
	object->_isHistoric = self.isHistoric;
	object->_isEventOnlyMessage = self.isEventOnlyMessage;
	object->_isPrintOnlyMessage = self.isPrintOnlyMessage;
	object->_messageTags = [self.messageTags copyWithZone:zone];
	object->_params = [self.params copyWithZone:zone];
	object->_receivedAt = [self.receivedAt copyWithZone:zone];
	object->_sender = [self.sender copyWithZone:zone];

	return object;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
	IRCMessageMutable *object = [[IRCMessageMutable allocWithZone:zone] init];

	object.batchToken = self.batchToken;
	object.command = self.command;
	object.commandNumeric = self.commandNumeric;
	object.isHistoric = self.isHistoric;
	object.isEventOnlyMessage = self.isEventOnlyMessage;
	object.isPrintOnlyMessage = self.isPrintOnlyMessage;
	object.messageTags = self.messageTags;
	object.params = self.params;
	object.receivedAt = self.receivedAt;
	object.sender = self.sender;

	return object;
}

- (BOOL)isMutable
{
	return NO;
}

@end

#pragma mark -

@implementation IRCMessage (IRCMessageLineParser)

- (BOOL)parseLine:(NSString *)line forClient:(nullable IRCClient *)client
{
	NSParameterAssert(line != nil);

	ObjectIsAlreadyInitializedAssert

	NSMutableString *lineMutable = [line mutableCopy];

	/* Parse extension information (if present) */
	if ([lineMutable hasPrefix:@"@"]) {
		NSString *extensionInfo = lineMutable.token;

		if (extensionInfo.length <= 1) {
			return NO;
		}

		extensionInfo = [extensionInfo substringFromIndex:1];

		[self parseExtensions:extensionInfo forClient:client];
	}

	/* Parse sender information (if present) */
	if ([lineMutable hasPrefix:@":"]) {
		NSString *senderInfo = lineMutable.token;

		if (senderInfo.length <= 1) {
			return NO;
		}

		senderInfo = [senderInfo substringFromIndex:1];

		[self parseSender:senderInfo forClient:client];
	} else {
		/* If the line does not have a sender, then we use the 
		 server address as the sender. If that isn't known, then
		 we use the the address the user has configured. */
		NSString *serverAddress = client.serverAddress;

		IRCPrefixMutable *sender = [IRCPrefixMutable new];

		sender.nickname = serverAddress;

		sender.hostmask = serverAddress;

		sender.isServer = YES;

		self->_sender = [sender copy];
	}

	/* Parse command */
	NSString *command = lineMutable.token;

	if (command.length < 1) {
		return NO;
	}

	if (command.isNumericOnly) {
		self->_command = [command copy];

		self->_commandNumeric = command.integerValue;
	} else {
		self->_command = [command.uppercaseString copy];

		self->_commandNumeric = 0;
	}

	/* Parse remaining data */
	NSMutableArray<NSString *> *parameters = [NSMutableArray new];

	while (lineMutable.length > 0) {
		if ([lineMutable hasPrefix:@":"])
		{
			NSString *sequence = [lineMutable substringFromIndex:1];

			[parameters addObject:sequence];

			break;
		}
		else
		{
			NSString *sequence = lineMutable.token;

			[parameters addObject:sequence];
		}
	}

	self->_params = [parameters copy];

	/* Return success */
	return YES;
}

- (void)parseExtensions:(NSString *)extensionInfo forClient:(nullable IRCClient *)client
{
	NSParameterAssert(extensionInfo != nil);

	ObjectIsAlreadyInitializedAssert

	/* Chop the tags up using ; as a divider as defined by the syntax
	 located at: <http://ircv3.net/specs/core/message-tags-3.2.html> */
	/* An example grouping would look like the following:
	 @aaa=bbb;ccc;example.com/ddd=eee */
	/* The specification does not specify what is to happen if the value
	 of an extension will contain a semicolon so at this point we will
	 assume that they will not exist and only be there as a divider. */
	NSArray<NSString *> *extensionsIn = [extensionInfo componentsSeparatedByString:@";"];

	NSMutableDictionary<NSString *, NSString *> *extensionsOut =
	[NSMutableDictionary dictionaryWithCapacity:extensionsIn.count];

	/* We now go through each tag using an equal sign as a divider and
	 placing each into a dictionary. */
	[extensionsIn enumerateObjectsUsingBlock:^(NSString *extension, NSUInteger index, BOOL *stop) {
		NSInteger equalSignPosition = [extension stringPosition:@"="];

		if (equalSignPosition <= 0) {
			return;
		}

		NSString *extensionKey = [extension substringToIndex:equalSignPosition];

		NSString *extensionValue = [extension substringAfterIndex:equalSignPosition];

		extensionsOut[extensionKey] = extensionValue.percentDecodedString;
	}];

	self->_messageTags = [extensionsOut copy];

	/* If there is no client, then further processing is not possible */
	if (client == nil) {
		return;
	}

	/* Check for known capacities */
	if ([client isCapacityEnabled:ClientIRCv3SupportedCapacityServerTime]) {
		/* We support two time extensions. The time= value is the date and
		 time in the format as defined by ISO 8601:2004(E) 4.3.2. */
		/* The t= value is a legacy value in a epoch time. We always favor
		 the new time= format over the old. */
		NSString *dateString = extensionsOut[@"time"];

		if (dateString == nil) {
			dateString = extensionsOut[@"t"];
		}

		if (dateString) {
			NSDate *dateObject = nil;

			if ([dateString onlyContainsCharacters:@"0123456789."]) {
				dateObject = [NSDate dateWithTimeIntervalSince1970:dateString.doubleValue];
			} else {
				dateObject = [TXSharedISOStandardDateFormatter() dateFromString:dateString];
			}

			if (dateObject) {
				self->_receivedAt = [dateObject copy];

				self->_isHistoric = YES;
			}
		}
	}

	if ([client isCapacityEnabled:ClientIRCv3SupportedCapacityBatch]) {
		NSString *batchToken = extensionsOut[@"batch"];

		if ([batchToken onlyContainsCharacters:CS_AtoZUnderscoreDashCharacters]) {
			self->_batchToken = [batchToken copy];
		}
	}
}

- (void)parseSender:(NSString *)senderInfo forClient:(nullable IRCClient *)client
{
	NSParameterAssert(senderInfo != nil);

	ObjectIsAlreadyInitializedAssert

	IRCPrefixMutable *sender = [IRCPrefixMutable new];

	NSString *senderNickname = nil;
	NSString *senderUsername = nil;
	NSString *senderAddress = nil;

	sender.hostmask = senderInfo;// Declare entire section as host

	/* Parse the user info into their appropriate sections or return NO if we can't. */
	if ([senderInfo hostmaskComponents:&senderNickname username:&senderUsername address:&senderAddress onClient:client]) {
		sender.nickname = senderNickname;
		sender.username = senderUsername;
		sender.address = senderAddress;
	} else {
		sender.nickname = senderInfo;

		sender.isServer = YES;
	}

	self->_sender = [sender copy];
}

@end

#pragma mark -

@implementation IRCMessageMutable

@dynamic batchToken;
@dynamic command;
@dynamic commandNumeric;
@dynamic isHistoric;
@dynamic isEventOnlyMessage;
@dynamic isPrintOnlyMessage;
@dynamic messageTags;
@dynamic params;
@dynamic receivedAt;
@dynamic sender;

- (BOOL)isMutable
{
	return YES;
}

- (void)setBatchToken:(nullable NSString *)batchToken
{
	if (self->_batchToken != batchToken) {
		self->_batchToken = [batchToken copy];
	}
}

- (void)setCommand:(NSString *)command
{
	NSParameterAssert(command != nil);

	if (self->_command != command) {
		self->_command = [command copy];
	}
}

- (void)setCommandNumeric:(NSUInteger)commandNumeric
{
	if (self->_commandNumeric != commandNumeric) {
		self->_commandNumeric = commandNumeric;
	}
}

- (void)setIsHistoric:(BOOL)isHistoric
{
	if (self->_isHistoric != isHistoric) {
		self->_isHistoric = isHistoric;
	}
}

- (void)setIsEventOnlyMessage:(BOOL)isEventOnlyMessage
{
	if (self->_isEventOnlyMessage != isEventOnlyMessage) {
		self->_isEventOnlyMessage = isEventOnlyMessage;
	}
}

- (void)setIsPrintOnlyMessage:(BOOL)isPrintOnlyMessage
{
	if (self->_isPrintOnlyMessage != isPrintOnlyMessage) {
		self->_isPrintOnlyMessage = isPrintOnlyMessage;
	}
}

- (void)setMessageTags:(nullable NSDictionary<NSString *, NSString *> *)messageTags
{
	if (self->_messageTags != messageTags) {
		self->_messageTags = [messageTags copy];
	}
}

- (void)setParams:(NSArray<NSString *> *)params
{
	NSParameterAssert(params != nil);

	if (self->_params != params) {
		self->_params = [params copy];
	}
}

- (void)setReceivedAt:(NSDate *)receivedAt
{
	NSParameterAssert(receivedAt != nil);

	if (self->_receivedAt != receivedAt) {
		self->_receivedAt = [receivedAt copy];
	}
}

- (void)setSender:(IRCPrefix *)sender
{
	NSParameterAssert(sender != nil);

	if (self->_sender != sender) {
		self->_sender = [sender copy];
	}
}

@end

NS_ASSUME_NONNULL_END
