/*
 Copyright (c) 2014, Tobias Pollmann, Alex Sørlie Glomsaas.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.
 
 3. Neither the name of the copyright holders nor the names of its contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ChatViewController.h"
#import "ChatMessageView.h"
#import "IRCMessage.h"
#import "UserListView.h"
#import "InputCommands.h"
#import "ChannelInfoViewController.h"
#import <UIActionSheet+Blocks/UIActionSheet+Blocks.h>
#import <ImgurAnonymousAPIClient/ImgurAnonymousAPIClient.h>
#import <GTScrollNavigationBar/GTScrollNavigationBar.h>


@interface ChatViewController ()
@property (readonly, nonatomic) UIView *container;
@property (readonly, nonatomic) PHFComposeBarView *composeBarView;
@property (readonly, nonatomic) UserListView *userListView;
@property (readonly, nonatomic) UIBarButtonItem *backButton;
@property (readonly, nonatomic) UIBarButtonItem *joinButton;
@property (readonly, nonatomic) UIBarButtonItem *userlistButton;
@end

CGRect const kInitialViewFrame = { 0.0f, 0.0f, 320.0f, 480.0f };

@implementation ChatViewController

- (id)init
{
    if (!(self = [super init]))
        return nil;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(messageReceived:)
                                                 name:@"messageReceived"
                                               object:nil];
    
    _backButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ChannelIcon_Light"] style:UIBarButtonItemStylePlain target:self action:@selector(goBack:)];
    
    _joinButton = [[UIBarButtonItem alloc] initWithTitle:@"Join" style:UIBarButtonItemStylePlain target:self action:@selector(join:)];
    
    _userlistButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Userlist"]
                                                       style:UIBarButtonItemStylePlain
                                                      target:self
                                                      action:@selector(showUserList:)];

    self.navigationItem.leftBarButtonItem = _backButton;
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"messageReceived"
                                                  object:nil];
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}

- (void)loadView
{

    UIView *view = [[UIView alloc] initWithFrame:kInitialViewFrame];
    [view setBackgroundColor:[UIColor whiteColor]];

    UIView *container = [self container];
    [container addSubview:[self composeBarView]];
    
    self.navigationController.scrollNavigationBar.scrollView = _conversation.contentView;
    
    [view addSubview:container];
    self.view = view;
    
    [self setEdgesForExtendedLayout:UIRectEdgeNone];
    
    [self setView:view];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (_isChannel && [(IRCChannel*)_conversation isJoinedByUser])
        self.navigationItem.rightBarButtonItem = _userlistButton;
    else if (_isChannel == NO) {
        self.navigationItem.rightBarButtonItem = nil;
    } else {
        self.navigationItem.rightBarButtonItem = _joinButton;
    }
    
    self.title = _conversation.name;
    
    if(!_conversation.contentView) {
        
        CGRect screenRect = [[UIScreen mainScreen] bounds];
        
        UIView *container = [self container];
        
        // Clear container
        for (UIView *view in container.subviews) {
            if ([NSStringFromClass(view.class) isEqualToString:@"UIScrollView"]) {
                [view removeFromSuperview];
            }
        }
        
        CGRect frame = CGRectMake(0.0,
                                  0.0,
                                  screenRect.size.width,
                                  kInitialViewFrame.size.height - PHFComposeBarViewInitialHeight);
        
        _conversation.contentView = [[UIScrollView alloc] initWithFrame:frame];
        _conversation.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _conversation.contentView.delegate = self;
        
        UITapGestureRecognizer *singleTapRecogniser = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideAccessories:)];
        [singleTapRecogniser setDelegate:self];
        singleTapRecogniser.numberOfTouchesRequired = 1;
        singleTapRecogniser.numberOfTapsRequired = 1;
        [_conversation.contentView addGestureRecognizer:singleTapRecogniser];
        
        UIScreenEdgePanGestureRecognizer *swipeLeftRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft:)];
        [swipeLeftRecognizer setEdges:UIRectEdgeRight];
        [swipeLeftRecognizer setDelegate:self];
        [_conversation.contentView addGestureRecognizer:swipeLeftRecognizer];

        for (IRCMessage *message in _conversation.messages) {
            [self addMessage:message];
        }
        
        [container addSubview:_conversation.contentView];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillToggle:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillToggle:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        
        //[self.navigationController performSegueWithIdentifier:@"modal" sender:nil];
    });

    [self scrollToBottom:NO];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self hideAccessories:nil];    
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillShowNotification
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillHideNotification
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardDidShowNotification
                                                  object:nil];
    
}

- (void)scrollToBottom:(BOOL)animated
{
    if (_conversation.contentView.contentSize.height > _conversation.contentView.bounds.size.height) {
        CGPoint bottomOffset = CGPointMake(0, _conversation.contentView.contentSize.height - _conversation.contentView.bounds.size.height);
        [_conversation.contentView setContentOffset:bottomOffset animated:animated];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGRect frame = self.view.frame;
    CGFloat height = frame.origin.y;
    frame.origin.y = 0.0;
    frame.size.height += height;
    self.view.frame = frame;
}

- (void)addMessage:(IRCMessage *)message
{
    ChatMessageView *lastMsg;

    // Get last message object
    for (UIView *view in _conversation.contentView.subviews) {
        if([NSStringFromClass(view.class) isEqualToString:@"ChatMessageView"]) {
            lastMsg = (ChatMessageView *)view;
        }
    }
    
    CGFloat oldY = lastMsg.frame.origin.y;
    CGFloat posY;
    
    if (message.messageType == ET_PRIVMSG)
        posY = lastMsg.frame.origin.y + lastMsg.bounds.size.height + 5.0;
    else
        posY = lastMsg.frame.origin.y + lastMsg.bounds.size.height;
    
    ChatMessageView *messageView = [[ChatMessageView alloc] initWithFrame:CGRectMake(0, posY, _conversation.contentView.bounds.size.width, 15.0)
                                                                  message:message
                                                             conversation:_conversation];
    messageView.chatViewController = self;
    
    messageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_conversation.contentView addSubview:messageView];
    _conversation.contentView.contentSize = CGSizeMake(_container.bounds.size.width, posY);
    
    // Scroll to bottom if content is bigger than view and user didnt scroll up
    if (_conversation.contentView.contentSize.height > _conversation.contentView.bounds.size.height &&
        (_conversation.contentView.contentOffset.y == 0.0 ||
         _conversation.contentView.contentOffset.y > _conversation.contentView.contentSize.height - _conversation.contentView.bounds.size.height - oldY - posY)) {
        
        [self scrollToBottom:YES];
    }
}

- (void)join:(id)sender
{
    // Connect client if it isn't already connected

    if (_conversation.client.isConnected == NO)
        [_conversation.client connect];
    
    ConversationListViewController *controller = ((AppDelegate *)[UIApplication sharedApplication].delegate).conversationsController;
    [controller joinChannelWithName:_conversation.name onClient:_conversation.client];

}

- (void)keyboardWillToggle:(NSNotification *)notification
{

    if (_userlistIsVisible)
        [_userListView removeFromSuperview];

    NSDictionary* userInfo = [notification userInfo];
    NSTimeInterval duration;
    UIViewAnimationCurve animationCurve;
    CGRect startFrame;
    CGRect endFrame;
    [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:&duration];
    [[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey]    getValue:&animationCurve];
    [[userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey]        getValue:&startFrame];
    [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey]          getValue:&endFrame];
    
    NSInteger signCorrection = 1;
    if (startFrame.origin.y < 0 || startFrame.origin.x < 0 || endFrame.origin.y < 0 || endFrame.origin.x < 0)
        signCorrection = -1;
    
    CGFloat widthChange  = (endFrame.origin.x - startFrame.origin.x) * signCorrection;
    CGFloat heightChange = (endFrame.origin.y - startFrame.origin.y) * signCorrection;
    
    if (heightChange < 0) {
        _keyboardIsVisible = YES;
    } else {
        _keyboardIsVisible = NO;
    }
    
    CGFloat sizeChange = UIInterfaceOrientationIsLandscape([self interfaceOrientation]) ? widthChange : heightChange;
    
    CGRect newContainerFrame = [[self container] frame];
    newContainerFrame.size.height += sizeChange;
    
    [UIView animateWithDuration:duration
                          delay:0
                        options:(animationCurve << 16)|UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         [[self container] setFrame:newContainerFrame];
                     }
                     completion:NULL];
}

- (void)keyboardDidShow:(id)sender
{
    [self scrollToBottom:NO];
}

- (void)goBack:(id)sender
{
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)showUserList:(id)sender
{
    _userlistIsVisible = YES;
    
    [_composeBarView resignFirstResponder];
    UserListView *userlist = [self userListView];
    
    userlist.channel = (IRCChannel*)_conversation;

    [self.navigationController.view addSubview:userlist];

    CGRect frame = userlist.frame;
    frame.origin.x = _container.frame.size.width - 205.0f;
    
    [UIView animateWithDuration:0.5
                          delay:0.0
         usingSpringWithDamping:0.5
          initialSpringVelocity:0.3
                        options:0 animations:^{
                            userlist.frame = frame;
                            //Animations
                        }
                     completion:nil];
    

}

- (void)composeBarViewDidPressButton:(PHFComposeBarView *)composeBarView
{
    ChannelInfoViewController *channelInfoViewController = [[ChannelInfoViewController alloc] init];
    channelInfoViewController.channel = (IRCChannel *)_conversation;
    
    UINavigationController *navigationController = [[UINavigationController alloc]
                                                    
                                                    initWithRootViewController:channelInfoViewController];
    
    [self presentViewController:navigationController animated:YES completion: nil];
}

- (void)composeBarViewDidPressUtilityButton:(PHFComposeBarView *)composeBarView
{
    
    [self hideAccessories:nil];
    [UIActionSheet showInView:self.view
                    withTitle:NSLocalizedString(@"Photo Source", @"Photo Source")
            cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
       destructiveButtonTitle:nil
            otherButtonTitles:@[NSLocalizedString(@"Camera", @"Camera"), NSLocalizedString(@"Photo Library", @"Photo Library")]
                     tapBlock:^(UIActionSheet *actionSheet, NSInteger buttonIndex) {
                         if (buttonIndex == 0) {
                             UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
                             [imagePicker.view setFrame:CGRectMake(0, 80, 320, 350)];
                             [imagePicker setSourceType:UIImagePickerControllerSourceTypeCamera];
                             [imagePicker setDelegate:(id)self];
                             [self presentViewController:imagePicker animated:YES completion:nil];
                         } else if(buttonIndex == 1) {
                             UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
                             [imagePicker.view setFrame:CGRectMake(0, 80, 320, 350)];
                             [imagePicker setSourceType:UIImagePickerControllerSourceTypeSavedPhotosAlbum];
                             [imagePicker setDelegate:(id)self];
                             [self presentViewController:imagePicker animated:YES completion:nil];
                         }

                     }];
    
}

- (void)sendMessage:(NSString *)message
{
    if ([message hasPrefix:@"/"])
        [InputCommands performCommand:[message substringFromIndex:1] inConversation:_conversation];
    else {
        [InputCommands sendMessage:message toRecipient:_conversation.name onClient:_conversation.client];
        
        IRCMessage *ircmsg = [[IRCMessage alloc] initWithMessage:message
                                                          OfType:ET_PRIVMSG
                                                  inConversation:_conversation
                                                        bySender:_conversation.client.currentUserOnConnection
                                                          atTime:[NSDate date]];
        [self addMessage:ircmsg];
        [_conversation.messages addObject:ircmsg];
    }
    
    [_composeBarView setText:@"" animated:YES];

}


- (BOOL) textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if([text isEqualToString:@"\n"]){
        [self sendMessage:textView.text];
        return NO;
    }else{
        return YES;
    }
}

- (BOOL)hideUserList
{
    if (_userlistIsVisible) {
        
        _userlistIsVisible = NO;
        
        CGRect frame = _userListView.frame;
        frame.origin.x = _container.frame.size.width;
        _userListView.frame = frame;
        
        [_userListView removeFromSuperview];
        
        return YES;
    }
    return NO;
}

- (void)hideAccessories:(UIGestureRecognizer*)sender
{
    if ([self hideUserList])
        return;
    [_composeBarView resignFirstResponder];
}

- (void)messageReceived:(NSNotification *)notification
{
    IRCMessage *message = notification.object;
    if (_isChannel &&
        [(IRCChannel*)_conversation isJoinedByUser] &&
        message.messageType == ET_JOIN &&
        [message.sender.nick isEqualToString:_conversation.client.currentUserOnConnection.nick] &&
        [message.conversation.configuration.uniqueIdentifier isEqualToString:_conversation.configuration.uniqueIdentifier]) {
        
        UIBarButtonItem *userlistButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Userlist"]
                                                                           style:UIBarButtonItemStylePlain
                                                                          target:self
                                                                          action:@selector(showUserList:)];
        self.navigationItem.rightBarButtonItem = userlistButton;
        
    }
    
    if (_userlistIsVisible && (message.messageType == ET_JOIN ||
        message.messageType == ET_PART ||
        message.messageType == ET_NICK ||
        message.messageType == ET_QUIT ||
        message.messageType == ET_KICK)) {

        [self.userListView.tableview reloadData];
    }
    
    if ([message.conversation.configuration.uniqueIdentifier isEqualToString:_conversation.configuration.uniqueIdentifier]) {
        [self addMessage:message];
    }
}

- (void)swipeLeft:(UIScreenEdgePanGestureRecognizer *)recognizer
{
    
    UserListView *userlist = [self userListView];
    
    CGFloat progress = [recognizer translationInView:_conversation.contentView].x;

    __block CGRect frame = userlist.frame;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [self.navigationController.view addSubview:userlist];
    } else if (recognizer.state == UIGestureRecognizerStateChanged) {
        if (frame.origin.x >= _container.frame.size.width - 205.0)
            frame.origin.x = _container.frame.size.width + progress;
    } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
        // Finish or cancel the interactive transition
        if (frame.origin.x < _container.frame.size.width - 100) {
            [UIView animateWithDuration:0.5 animations:^{
                frame.origin.x = _container.frame.size.width - 205.0;
            } completion:^(BOOL finished) {
                _userlistIsVisible = YES;
            }];
        }
        else {
            [UIView animateWithDuration:0.5 animations:^{
                frame.origin.x = _container.frame.size.width;
            } completion:^(BOOL finished) {
                [userlist removeFromSuperview];
            }];
        }
    }
    userlist.frame = frame;
        
}

@synthesize container = _container;
- (UIView *)container {
    if (!_container) {
        _container = [[UIScrollView alloc] initWithFrame:kInitialViewFrame];
        _container.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    }
    
    return _container;
}

@synthesize composeBarView = _composeBarView;
- (PHFComposeBarView *)composeBarView {
    
    if (!_composeBarView) {
        CGRect frame = CGRectMake(0.0f,
                                  kInitialViewFrame.size.height - PHFComposeBarViewInitialHeight,
                                  kInitialViewFrame.size.width,
                                  PHFComposeBarViewInitialHeight);
        
        _composeBarView = [[PHFComposeBarView alloc] initWithFrame:frame];
        [_composeBarView setButtonTitle:nil];
//        [_composeBarView setMaxCharCount:160];
        [_composeBarView setButtonTintColor:[UIColor blackColor]];
        [_composeBarView setMaxLinesCount:5];
        [_composeBarView setPlaceholder:@"Type something..."];
        [_composeBarView setUtilityButtonImage:[UIImage imageNamed:@"Camera"]];
        [_composeBarView setDelegate:self];
        [_composeBarView setEnabled:YES];
        [[_composeBarView textView] setReturnKeyType:UIReturnKeySend];
    }
    return _composeBarView;
}

@synthesize userListView = _userListView;
- (UserListView *)userListView {
    
    if (!_userListView) {
        CGFloat width = 200.0f;
        CGRect frame = CGRectMake(_container.frame.size.width,
                                  30.0f,
                                  width,
                                  _conversation.contentView.frame.size.height);
        
        _userListView = [[UserListView alloc] initWithFrame:frame];
        _userListView.backgroundColor = [UIColor clearColor];
    }
    return _userListView;
}


#pragma mark -
#pragma mark UIImagePickerController Delegate Methods

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    [picker dismissViewControllerAnimated:YES completion:^{
        [_composeBarView becomeFirstResponder];        
    }];
    
    UIButton *cameraButton = [_composeBarView utilityButton];
    cameraButton.hidden = YES;
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    indicator.frame = _composeBarView.utilityButton.frame;
    [indicator setHidesWhenStopped:YES];
    [indicator startAnimating];
    [_composeBarView addSubview:indicator];

    [[ImgurAnonymousAPIClient client] uploadAssetWithURL:info[UIImagePickerControllerReferenceURL] filename:nil completionHandler:^(NSURL *imgurURL, NSError *error) {
        if(error)
            NSLog(@"Error while uploading image: %@", error.description);
        NSString *string;
        if ([_composeBarView.text isEqualToString:@""] == NO)
            string = [[_composeBarView text] stringByAppendingFormat:@" %@", imgurURL.absoluteString];
        else
            string = imgurURL.absoluteString;
        [_composeBarView setText:string];
        [indicator stopAnimating];
        [indicator removeFromSuperview];
        cameraButton.hidden = NO;
    }];

}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:^{
        [_composeBarView becomeFirstResponder];
    }];
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
}

@end
