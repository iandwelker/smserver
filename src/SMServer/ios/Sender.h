#ifndef Obj_h
#define Obj_h

@interface IPCTextWatcher : NSObject

@property (copy) void(^setTexts)(NSString *);
@property (copy) void(^setTyping)(NSDictionary *);
@property (copy) void(^sentTapback)(int, NSString *);
@property (copy) void(^textRead)(NSString *);
+ (instancetype)sharedInstance;
- (instancetype)init;
- (void)handleReceivedTextWithCallback:(NSString *)chat_id;
- (void)handlePartyTypingWithCallback:(NSDictionary *)vals;
- (void)handleSentTapbackWithCallback:(NSDictionary *)vals;
- (void)handleTextReadWithCallback:(NSString *)guid;

@end

@interface IWSSender : NSObject

@property (strong) MRYIPCCenter* center;

- (id)init;
- (BOOL)sendIPCText:(NSString *)body withSubject:(NSString *)subject toAddress:(NSString *)address withAttachments:(NSArray *)paths;
- (BOOL)markConvoAsRead:(NSString *)chat_id;
- (BOOL)sendTapback:(NSNumber *)tapback forGuid:(NSString *)guid inChat:(NSString *)chat;
- (void)sendTyping:(BOOL)isTyping forChat:(NSString *)chat;
- (BOOL)removeObject:(NSString *)chat text:(NSString *)text;
//- (NSArray *)getPinnedChats;

@end

#endif /* Obj_h */
