#import "RMQConstants.h"
#import "RMQFrame.h"
#import "RMQMethods.h"
#import "RMQProtocolHeader.h"
#import "RMQURI.h"
#import "RMQConnection.h"
#import "RMQHandshaker.h"
#import "RMQMultipleChannelAllocator.h"
#import "RMQReaderLoop.h"
#import "RMQTCPSocketTransport.h"
#import "RMQGCDSerialQueue.h"
#import "RMQSemaphoreWaiterFactory.h"
#import "RMQQueuingConnectionDelegateProxy.h"

@interface RMQConnection ()
@property (copy, nonatomic, readwrite) NSString *vhost;
@property (strong, nonatomic, readwrite) id <RMQTransport> transport;
@property (nonatomic, readwrite) RMQTable *clientProperties;
@property (nonatomic, readwrite) NSString *mechanism;
@property (nonatomic, readwrite) NSString *locale;
@property (nonatomic, readwrite) RMQConnectionConfig *config;
@property (nonatomic, readwrite) RMQReaderLoop *readerLoop;
@property (nonatomic, readwrite) id <RMQChannelAllocator> channelAllocator;
@property (nonatomic, readwrite) id <RMQChannel> channelZero;
@property (nonatomic, readwrite) id <RMQFrameHandler> frameHandler;
@property (nonatomic, readwrite) NSMutableDictionary *userChannels;
@property (nonatomic, readwrite) NSNumber *frameMax;
@property (nonatomic, weak, readwrite) id<RMQConnectionDelegate> delegate;
@property (nonatomic, readwrite) id<RMQLocalSerialQueue> commandQueue;
@property (nonatomic, readwrite) id<RMQWaiterFactory> waiterFactory;
@property (nonatomic, readwrite) NSNumber *handshakeTimeout;
@property (nonatomic, readwrite) BOOL closeRequested;
@end

@implementation RMQConnection

- (instancetype)initWithTransport:(id<RMQTransport>)transport
                             user:(NSString *)user
                         password:(NSString *)password
                            vhost:(NSString *)vhost
                       channelMax:(NSNumber *)channelMax
                         frameMax:(NSNumber *)frameMax
                        heartbeat:(NSNumber *)heartbeat
                 handshakeTimeout:(NSNumber *)handshakeTimeout
                 channelAllocator:(nonnull id<RMQChannelAllocator>)channelAllocator
                     frameHandler:(nonnull id<RMQFrameHandler>)frameHandler
                         delegate:(id<RMQConnectionDelegate>)delegate
                     commandQueue:(nonnull id<RMQLocalSerialQueue>)commandQueue
                    waiterFactory:(nonnull id<RMQWaiterFactory>)waiterFactory {
    self = [super init];
    if (self) {
        RMQCredentials *credentials = [[RMQCredentials alloc] initWithUsername:user
                                                                      password:password];
        self.config = [[RMQConnectionConfig alloc] initWithCredentials:credentials
                                                            channelMax:channelMax
                                                              frameMax:frameMax
                                                             heartbeat:heartbeat];
        self.handshakeTimeout = handshakeTimeout;
        self.frameMax = frameMax;
        self.vhost = vhost;
        self.transport = transport;
        self.transport.delegate = self;
        self.channelAllocator = channelAllocator;
        self.channelAllocator.sender = self;
        self.frameHandler = frameHandler;
        RMQTable *capabilities = [[RMQTable alloc] init:@{@"publisher_confirms": [[RMQBoolean alloc] init:YES],
                                                          @"consumer_cancel_notify": [[RMQBoolean alloc] init:YES],
                                                          @"exchange_exchange_bindings": [[RMQBoolean alloc] init:YES],
                                                          @"basic.nack": [[RMQBoolean alloc] init:YES],
                                                          @"connection.blocked": [[RMQBoolean alloc] init:YES],
                                                          @"authentication_failure_close": [[RMQBoolean alloc] init:YES]}];
        self.clientProperties = [[RMQTable alloc] init:
                                 @{@"capabilities" : capabilities,
                                   @"product"     : [[RMQLongstr alloc] init:@"RMQClient"],
                                   @"platform"    : [[RMQLongstr alloc] init:@"iOS"],
                                   @"version"     : [[RMQLongstr alloc] init:@"0.0.1"],
                                   @"information" : [[RMQLongstr alloc] init:@"https://github.com/rabbitmq/rabbitmq-objc-client"]}];
        self.mechanism = @"PLAIN";
        self.locale = @"en_GB";
        self.readerLoop = [[RMQReaderLoop alloc] initWithTransport:self.transport frameHandler:self];

        self.userChannels = [NSMutableDictionary new];
        self.delegate = delegate;
        self.commandQueue = commandQueue;
        self.waiterFactory = waiterFactory;
        self.closeRequested = NO;

        self.channelZero = [self.channelAllocator allocate];
        [self.channelZero activateWithDelegate:self.delegate];
    }
    return self;
}

- (instancetype)initWithUri:(NSString *)uri
                 channelMax:(NSNumber *)channelMax
                   frameMax:(NSNumber *)frameMax
                  heartbeat:(NSNumber *)heartbeat
                syncTimeout:(NSNumber *)syncTimeout
                   delegate:(id<RMQConnectionDelegate>)delegate
              delegateQueue:(dispatch_queue_t)delegateQueue {
    NSError *error = NULL;
    RMQURI *amqURI = [RMQURI parse:uri error:&error];
    RMQTCPSocketTransport *transport = [[RMQTCPSocketTransport alloc] initWithHost:amqURI.host port:amqURI.portNumber];
    RMQMultipleChannelAllocator *allocator = [[RMQMultipleChannelAllocator alloc] initWithChannelSyncTimeout:syncTimeout];
    RMQQueuingConnectionDelegateProxy *delegateProxy = [[RMQQueuingConnectionDelegateProxy alloc] initWithDelegate:delegate
                                                                                                             queue:delegateQueue];
    return [self initWithTransport:transport
                              user:amqURI.username
                          password:amqURI.password
                             vhost:amqURI.vhost
                        channelMax:channelMax
                          frameMax:frameMax
                         heartbeat:heartbeat
                  handshakeTimeout:syncTimeout
                  channelAllocator:allocator
                      frameHandler:allocator
                          delegate:delegateProxy
                      commandQueue:[RMQGCDSerialQueue new]
                     waiterFactory:[RMQSemaphoreWaiterFactory new]];
}

- (instancetype)initWithUri:(NSString *)uri
                   delegate:(id<RMQConnectionDelegate>)delegate {
    return [self initWithUri:uri
                  channelMax:@(RMQChannelLimit)
                    frameMax:@131072
                   heartbeat:@0
                 syncTimeout:@10
                    delegate:delegate
               delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
}

- (instancetype)initWithDelegate:(id<RMQConnectionDelegate>)delegate {
    return [self initWithUri:@"amqp://guest:guest@localhost" delegate:delegate];
}

- (instancetype)init
{
    return [self initWithDelegate:nil];
}

- (void)start {
    NSError *connectError = NULL;

    [self.transport connectAndReturnError:&connectError];
    if (connectError) {
        [self.delegate connection:self failedToConnectWithError:connectError];
    } else {
        [self.transport write:[RMQProtocolHeader new].amqEncoded];

        [self.commandQueue enqueue:^{
            id<RMQWaiter> handshakeCompletion = [self.waiterFactory makeWithTimeout:self.handshakeTimeout];

            RMQHandshaker *handshaker = [[RMQHandshaker alloc] initWithSender:self
                                                                       config:self.config
                                                            completionHandler:^{
                                                                [handshakeCompletion done];
                                                                [self.readerLoop runOnce];
                                                            }];
            RMQReaderLoop *handshakeLoop = [[RMQReaderLoop alloc] initWithTransport:self.transport
                                                                       frameHandler:handshaker];
            handshaker.readerLoop = handshakeLoop;
            [handshakeLoop runOnce];

            if (handshakeCompletion.timesOut) {
                NSError *error = [NSError errorWithDomain:RMQErrorDomain
                                                     code:RMQConnectionErrorHandshakeTimedOut
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Handshake timed out."}];
                [self.delegate connection:self failedToConnectWithError:error];
            }
        }];
    }
}

- (id<RMQChannel>)createChannel {
    id<RMQChannel> ch = self.channelAllocator.allocate;
    self.userChannels[ch.channelNumber] = ch;

    [self.commandQueue enqueue:^{
        [ch activateWithDelegate:self.delegate];
    }];

    [ch open];

    return ch;
}

- (void)close {
    self.closeRequested = YES;
    for (RMQOperation operation in self.closeOperations) {
        [self.commandQueue enqueue:operation];
    }
}

- (void)blockingClose {
    self.closeRequested = YES;
    for (RMQOperation operation in self.closeOperations) {
        [self.commandQueue blockingEnqueue:operation];
    }
}

# pragma mark - RMQSender

- (void)sendMethod:(id<RMQMethod>)amqMethod channelNumber:(NSNumber *)channelNumber {
    RMQFrameset *frameset = [[RMQFrameset alloc] initWithChannelNumber:channelNumber method:amqMethod];
    [self sendFrameset:frameset];
    if ([self shouldSendNextRequest:amqMethod]) {
        id<RMQMethod> followOn = [(id <RMQOutgoingPrecursor>)amqMethod nextRequest];
        [self sendMethod:followOn channelNumber:channelNumber];
    }
}

- (void)sendFrameset:(RMQFrameset *)frameset {
    [self.transport write:frameset.amqEncoded];
}

# pragma mark - RMQFrameHandler

- (void)handleFrameset:(RMQFrameset *)frameset {
    id method = frameset.method;

    if ([self shouldReply:method]) {
        id<RMQMethod> reply = [method replyWithConfig:self.config];
        [self sendMethod:reply channelNumber:frameset.channelNumber];
    }

    if ([method isKindOfClass:[RMQConnectionClose class]]) {
        [self.transport close:^{}];
    } else {
        [self.frameHandler handleFrameset:frameset];
        [self.readerLoop runOnce];
    }
}

# pragma mark - RMQTransportDelegate

- (void)transport:(id<RMQTransport>)transport failedToWriteWithError:(NSError *)error {
    [self.delegate connection:self failedToWriteWithError:error];
}

- (void)transport:(id<RMQTransport>)transport disconnectedWithError:(NSError *)error {
    if (!self.closeRequested) {
        [self.delegate connection:self disconnectedWithError:error];
    }
}

# pragma mark - Private

- (NSArray *)closeOperations {
    return @[^{[self closeAllChannels];},
              ^{[self sendFrameset:[[RMQFrameset alloc] initWithChannelNumber:@0 method:self.amqClose]];},
              ^{[self.channelZero blockingWaitOn:[RMQConnectionCloseOk class]];},
              ^{[self.transport close:^{}];}];
}

- (void)closeAllChannels {
    for (id<RMQChannel> ch in self.userChannels.allValues) {
        [ch blockingClose];
    }
}

- (RMQConnectionClose *)amqClose {
    return [[RMQConnectionClose alloc] initWithReplyCode:[[RMQShort alloc] init:200]
                                               replyText:[[RMQShortstr alloc] init:@"Goodbye"]
                                                 classId:[[RMQShort alloc] init:0]
                                                methodId:[[RMQShort alloc] init:0]];
}

- (BOOL)shouldReply:(id<RMQMethod>)amqMethod {
    return [amqMethod conformsToProtocol:@protocol(RMQIncomingSync)];
}

- (BOOL)shouldSendNextRequest:(id<RMQMethod>)amqMethod {
    return [amqMethod conformsToProtocol:@protocol(RMQOutgoingPrecursor)];
}

@end
