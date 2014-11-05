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

#import "ConversationListViewController.h"
#import "ChatViewController.h"
#import "EditConnectionViewController.h"
#import "AddConversationViewController.h"
#import "IRCConversation.h"
#import "IRCChannel.h"
#import "IRCClient.h"
#import "IRCUser.h"
#import "IRCMessage.h"
#import "AppPreferences.h"
#import "ConversationItemView.h"
#import "UITableView+Methods.h"
#import "AppPreferences.h"
#import "SSKeychain.h"
#import "IRCCertificateTrust.h"
#import "UIAlertView+Methods.h"
#import "UIBarButtonItem+Methods.h"
#import "CertificateInfoViewController.h"
#import "CertificateItemRow.h"
#import "IRCCommands.h"

@implementation ConversationListViewController

- (id)init
{
    if (!(self = [super init]))
        return nil;
    
    self.connections = [[NSMutableArray alloc] init];
    self.chatViewController = [[ChatViewController alloc] init];
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.navigationController.navigationBar.tintColor = [UIColor lightGrayColor];
    self.navigationController.navigationBar.barStyle = UIBarStyleBlackOpaque;
    self.navigationController.navigationBar.translucent = NO;
    
    self.title = NSLocalizedString(@"Conversations", @"Conversations");
    
    // Do any additional setup after loading the view, typically from a nib.
    UIBarButtonItem *settingsButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Settings", @"Left navigation button in the conversation list")
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(showSettings:)];
    [settingsButton setTintColor:[UIColor lightGrayColor]];
    self.navigationItem.leftBarButtonItem = settingsButton;
    
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addConversation:)];
    [addButton setTintColor:[UIColor lightGrayColor]];
    self.navigationItem.rightBarButtonItem = addButton;
    
    [self.tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
    
    NSArray *configurations = [[AppPreferences sharedPrefs] getConnectionConfigurations];
    for (NSDictionary *dict in configurations) {
        IRCConnectionConfiguration *configuration = [[IRCConnectionConfiguration alloc] initWithDictionary:dict];
        IRCClient *client = [[IRCClient alloc] initWithConfiguration:configuration];
        
        // Load channels
        for (IRCChannelConfiguration *config in configuration.channels)
            [client addChannel:[[IRCChannel alloc] initWithConfiguration:config withClient:client]];
        
        // Load queries
        for (IRCChannelConfiguration *config in configuration.queries)
            [client addQuery:[[IRCConversation alloc] initWithConfiguration:config withClient:client]];
             
        [self.connections addObject:client];
        if (client.configuration.automaticallyConnect) {
            [client connect];
        }
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedMessage:) name:@"messageReceived" object:nil];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadClient:(IRCClient *)client
{
    int i=0;
    for (IRCClient *cl in self.connections) {
        if([cl.configuration.uniqueIdentifier isEqualToString:client.configuration.uniqueIdentifier]) {
            [self.tableView reloadData];
            break;
        }
        i++;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)showSettings:(id)sender
{
    NSLog(@"Show Settings");
}

- (void)addConversation:(id)sender
{
    if(self.connections.count == 0) {
        [self editConnection:nil];
    } else {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Add Conversation", @"Add Conversation")
                                                           delegate:self
                                                  cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
                                             destructiveButtonTitle:nil
                                                  otherButtonTitles:NSLocalizedString(@"Join a Channel", @"Join a Channel"), NSLocalizedString(@"Message a User", @"Message a User"), NSLocalizedString(@"Add Connection", @"Add Connection"), nil];
        [sheet setTag:-1];
        [sheet showInView:self.view];
    }
}

- (void)reloadData
{
    [self.tableView reloadData];
}

- (void)editConnection:(IRCConnectionConfiguration *)connection
{
        
    EditConnectionViewController *editController = [[EditConnectionViewController alloc] init];
    
    if (connection) {
        editController.connection = connection;
        editController.edit = YES;
    }
    
    editController.conversationsController = self;
    
    
    UINavigationController *navigationController = [[UINavigationController alloc]
                                                    
                                                    initWithRootViewController:editController];
    
    [self presentViewController:navigationController animated:YES completion: nil];
}

- (void)addItemWithTag:(NSInteger)tag
{
    AddConversationViewController *addController = [[AddConversationViewController alloc] init];
    addController.target = self;
    addController.action = @selector(conversationAdded:);
    addController.connections = _connections;

    // add Query
    if(tag == 1)
        addController.addChannel = NO;
        
    UINavigationController *navigationController = [[UINavigationController alloc]
                                                    
                                                    initWithRootViewController:addController];
    
    [self presentViewController:navigationController animated:YES completion: nil];
}

- (void)sortConversationsForClientAtIndex:(NSInteger)index
{
    IRCClient *client = _connections[index];
    if(client != nil) {
        [client sortChannelItems];
        [client sortQueryItems];
        [[AppPreferences sharedPrefs] setChannels:client.getChannels andQueries:client.getQueries forConnectionConfiguration:client.configuration];
        [self.tableView reloadData];        
    }
}

- (void)selectConversationWithIdentifier:(NSString *)identifier
{
    IRCClient *client;
    IRCConversation *conversation;
    for (client in _connections) {
        for (conversation in client.getQueries) {
            if ([conversation.configuration.uniqueIdentifier isEqualToString:identifier]) {
                _chatViewController.isChannel = NO;
                _chatViewController.conversation = conversation;
                break;
            }
        }
        if (conversation == nil) {
            for (conversation in client.getChannels) {
                NSLog(@"ID: %@", identifier);
                NSLog(@"ID2: %@", conversation.configuration.uniqueIdentifier);
                NSLog(@"CONVO: %@", conversation.name);
                if ([conversation.configuration.uniqueIdentifier isEqualToString:identifier]) {
                    _chatViewController.isChannel = YES;
                    _chatViewController.conversation = conversation;
                    break;
                }
            }
        }
    }

    [self.navigationController popToRootViewControllerAnimated:YES];
    [self.navigationController pushViewController:_chatViewController animated:YES];
}

#pragma mark - Table View

- (NSIndexPath *) tableView:(UITableView *) tableView willSelectRowAtIndexPath:(NSIndexPath *) indexPath {
    return indexPath;
}

- (void) tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath
{
    IRCClient *client = [self.connections objectAtIndex:indexPath.section];
    
    IRCConversation *conversation;
    if ((int)indexPath.row > (int)client.getChannels.count-1) {
        NSInteger index = indexPath.row - client.getChannels.count;
        conversation = client.getQueries[index];
        _chatViewController.isChannel = NO;
    } else {
        conversation = client.getChannels[indexPath.row];
        _chatViewController.isChannel = YES;
    }
    
    _chatViewController.conversation = conversation;
    
    [self.navigationController pushViewController:_chatViewController animated:YES];

}


- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    if(self.connections.count > 0) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    
        // Remove old stuff
        for (UIView *v in header.contentView.subviews) {
            if ([v isKindOfClass:[UIButton class]] || [v isKindOfClass:[UIActivityIndicatorView class]]) {
                [v removeFromSuperview];
            }
        }

        // Set colors
        [header.textLabel setTextColor:[UIColor darkGrayColor]];
        header.contentView.backgroundColor = [UIColor whiteColor];
        
        // Set Label
        IRCClient *client = [self.connections objectAtIndex:section];
        header.textLabel.text = client.configuration.connectionName;
        header.tag = section;
        
        if (client.isAttemptingConnection || client.isAttemptingRegistration) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            spinner.frame = CGRectMake(header.bounds.size.width-40, 0, header.bounds.size.height, header.bounds.size.height);
            [header.contentView addSubview:spinner];
            [spinner startAnimating];
        }
        
        if (client.isConnectedAndCompleted) {
            UIButton *checkmark = [UIButton buttonWithType:UIButtonTypeCustom];
            
            // Define unicode character
            unichar *code = malloc(sizeof(unichar) * 1);
            code[0] = (unichar)0x2713;
            
            checkmark.frame = CGRectMake(header.bounds.size.width-40, 0, header.bounds.size.height, header.bounds.size.height);
            checkmark.titleLabel.font = [UIFont fontWithName:@"Symbola" size:16.0];
            [checkmark setTitle:[NSString stringWithCharacters:code length:1] forState:UIControlStateNormal];
            [checkmark setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            [header.contentView addSubview:checkmark];
            free(code);
        }
        
        // Add Tap Event
        UITapGestureRecognizer *singleTapRecogniser = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerViewSelected:)];
        [singleTapRecogniser setDelegate:self];
        singleTapRecogniser.numberOfTouchesRequired = 1;
        singleTapRecogniser.numberOfTapsRequired = 1;
        [header addGestureRecognizer:singleTapRecogniser];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    
    return 30.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return _connections.count;
    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    IRCClient *client = [_connections objectAtIndex:section];
    return client.getChannels.count + client.getQueries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    static NSString *CellIdentifier = @"cell";
    ConversationItemView *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[ConversationItemView alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
    }
    
    
    IRCClient *client = [_connections objectAtIndex:indexPath.section];
    NSArray *channels = client.getChannels;
    if((int)indexPath.row > (int)channels.count-1) {
        NSInteger index;
        index = indexPath.row - client.getChannels.count;
        IRCConversation *query = [client.getQueries objectAtIndex:index];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.enabled = query.conversationPartnerIsOnline;
        cell.name = query.name;
        cell.isChannel = NO;
        cell.previewMessages = query.previewMessages;
        cell.unreadCount = query.unreadCount;
        
    } else {
        IRCChannel *channel = [client.getChannels objectAtIndex:indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.enabled = channel.isJoinedByUser;
        cell.name = channel.name;
        cell.isChannel = YES;
        cell.unreadCount = channel.unreadCount;
        cell.previewMessages = channel.previewMessages;
    }

    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    IRCClient *client = _connections[indexPath.section];
    NSInteger index = indexPath.row;
    if ((int)indexPath.row > (int)client.getChannels.count-1) {
        index = indexPath.row - client.getChannels.count;
        IRCConversation *query = client.getQueries[index];
        [client removeQuery:query];
        
        // Remove from prefs
        [[AppPreferences sharedPrefs] deleteQueryWithName:query.name forConnectionConfiguration:client.configuration];
    } else {
        IRCChannel *channel = client.getChannels[index];
        [client removeChannel:channel];
        
        // Remove from prefs
        [[AppPreferences sharedPrefs] deleteChannelWithName:channel.name forConnectionConfiguration:client.configuration];
    }
    [[AppPreferences sharedPrefs] save];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)headerViewSelected:(UIGestureRecognizer *)sender
{
    // Get relevant client
    IRCClient *client = [self.connections objectAtIndex:sender.view.tag];

    UIActionSheet *sheet;
    
    if([client isConnected]) {
        sheet = [[UIActionSheet alloc] initWithTitle:client.configuration.connectionName
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:NSLocalizedString(@"Disconnect", @"Disconnect server"),
                 NSLocalizedString(@"Sort Conversations", "Sort Conversations"),
                 NSLocalizedString(@"Edit", @"Edit Connection"), nil];
        [sheet setDestructiveButtonIndex:0];
    } else {
        sheet = [[UIActionSheet alloc] initWithTitle:client.configuration.connectionName
                                        delegate:self
                               cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
                          destructiveButtonTitle:nil
                               otherButtonTitles:NSLocalizedString(@"Connect", @"Connect server"),
                 NSLocalizedString(@"Sort Conversations", "Sort Conversations"),
                 NSLocalizedString(@"Edit", @"Edit Connection"),
                 NSLocalizedString(@"Delete", @"Delete connection"), nil];
        [sheet setDestructiveButtonIndex:3];
    }
    
    [sheet setTag:sender.view.tag];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (actionSheet.tag == -1) {
        // Conversations action sheet
        switch (buttonIndex) {
            case 0:
                // Join a Channel
                [self addItemWithTag:buttonIndex];
                break;
            case 1:
                // Message a User
                [self addItemWithTag:buttonIndex];
                break;
            case 2:
                // Add Connection
                [self editConnection:nil];
                break;
            default:
                break;
        }
    } else {
        // Connections action sheet
        IRCClient *client = [self.connections objectAtIndex:actionSheet.tag];
        UIAlertView *alertView;
        
        switch (buttonIndex) {
            case 0:
                // Connect or disconnect
                if(client.isConnected) {
                   [client disconnect];
                } else {
                    [client connect];
                    [self.tableView reloadData];
                }
                break;
            case 1:
                // Sort Conversations
                [self sortConversationsForClientAtIndex:actionSheet.tag];
                break;
            case 2:
                // Edit
                [self editConnection:client.configuration];
                break;
            case 3:
                // Delete
                if(!client.isConnected) {
                    alertView = [[UIAlertView alloc] initWithTitle:client.configuration.connectionName
                                                           message:NSLocalizedString(@"Do you really want to delete this connection?", @"Delete connection confirmation")
                                                          delegate:self
                                                 cancelButtonTitle:NSLocalizedString(@"No", @"no")
                                                 otherButtonTitles:NSLocalizedString(@"Yes", @"yes"), nil];
                    alertView.tag = actionSheet.tag;
                    [alertView show];
                }
                break;
            default:
                break;
        }
    }
}

- (void)conversationAdded:(AddConversationViewController *)sender
{

    NSMutableArray *connections = [sender.connections mutableCopy];
    
    IRCClient *client;
    int i;
    for (i=0; i<_connections.count; i++) {
        client = [_connections objectAtIndex:i];
        if([client.configuration.uniqueIdentifier isEqualToString:sender.client.configuration.uniqueIdentifier])
            break;
    }
    if(client != nil) {
        if(sender.addChannel) {
            IRCChannel *channel = [[IRCChannel alloc] initWithConfiguration:sender.configuration withClient:sender.client];
            [client addChannel:channel];
            
            // Save config
            if([sender.configuration.passwordReference isEqualToString:@""] == NO) {
                NSString *identifier = [[NSUUID UUID] UUIDString];
                [SSKeychain setPassword:sender.configuration.passwordReference forService:@"conversation" account:identifier];
                sender.configuration.passwordReference = identifier;
            }
            [[AppPreferences sharedPrefs] addChannelConfiguration:sender.configuration forConnectionConfiguration:sender.client.configuration];
            
        } else {
            IRCConversation *query = [[IRCConversation alloc] initWithConfiguration:sender.configuration withClient:sender.client];
            [client addQuery:query];
            
            // Save config
            [[AppPreferences sharedPrefs] addQueryConfiguration:sender.configuration forConnectionConfiguration:sender.client.configuration];
            
        }
        
    }
    IRCConnectionConfiguration *config = [[IRCConnectionConfiguration alloc] initWithDictionary:[[[AppPreferences sharedPrefs] getConnectionConfigurations] objectAtIndex:i]];
    client.configuration = config;
    _connections = connections;
    
    [self.tableView reloadData];
    [[AppPreferences sharedPrefs] save];
    
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    // Delete connection
    if(buttonIndex == YES) {
        IRCClient *client = [self.connections objectAtIndex:alertView.tag];
        if(client.isConnected)
            [client disconnect];
        [[AppPreferences sharedPrefs] deleteConnectionWithIdentifier:client.configuration.uniqueIdentifier];
        [self.connections removeObjectAtIndex:alertView.tag];
        [self.tableView reloadData];
    }
}

- (NSString *)joinChannelWithName:(NSString *)name onClient:(IRCClient *)client
{
    for (IRCConversation *channel in client.getChannels) {
        if ([channel.name isEqualToString:name]) {
            return channel.configuration.uniqueIdentifier;
        }
    }
    
    IRCChannelConfiguration *configuration = [[IRCChannelConfiguration alloc] init];
    configuration.name = name;
    IRCChannel *channel = [[IRCChannel alloc] initWithConfiguration:configuration withClient:client];
    
    [client addChannel:channel];
    
    [self.tableView reloadData];
    [[AppPreferences sharedPrefs] addChannelConfiguration:configuration forConnectionConfiguration:client.configuration];
    [[AppPreferences sharedPrefs] save];
    return configuration.uniqueIdentifier;
}

- (NSString *)createConversationWithName:(NSString *)name onClient:(IRCClient *)client
{
    IRCChannelConfiguration *configuration = [[IRCChannelConfiguration alloc] init];
    configuration.name = name;
    IRCConversation *query = [[IRCConversation alloc] initWithConfiguration:configuration withClient:client];
    [client addQuery:query];

    [self.tableView reloadData];
    [[AppPreferences sharedPrefs] addQueryConfiguration:configuration forConnectionConfiguration:client.configuration];
    [[AppPreferences sharedPrefs] save];

    return configuration.uniqueIdentifier;
}

- (void) receivedMessage:(NSNotification *) notification
{
    IRCMessage *message = notification.object;
    
    if (message.messageType != ET_PRIVMSG && message.messageType != ET_ACTION)
        return;
    
    // Make sender's nick bold
    NSMutableAttributedString *string;
    UIFont *font = [UIFont fontWithName:@"Helvetica-Bold" size:14];
    if (message.messageType == ET_ACTION) {
        string = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"*%@ %@", message.sender.nick, message.message]];
        [string addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, message.sender.nick.length+message.message.length+2)];
    } else {
        string = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: %@", message.sender.nick, message.message]];
        [string addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, message.sender.nick.length+1)];
    }
    
    [message.conversation addPreviewMessage:string];
    message.conversation.unreadCount++;
    [self.tableView reloadData];
}

- (void)displayPasswordEntryDialog:(IRCClient *)client
{
    
    UIAlertView *alert = [[UIAlertView alloc]
                          initWithTitle:NSLocalizedString(@"Please enter a password", @"Please enter a password")
                          message:NSLocalizedString(@"You haven't specified a password or the entered password did not match", @"You haven't specified a password or the entered password did not match")
                          delegate:self
                          cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel")
                          otherButtonTitles:NSLocalizedString(@"Retry", @"Retry"), nil ];
    
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField* answerField = [alert textFieldAtIndex:0];
    answerField.keyboardType = UIKeyboardTypeNumberPad;
    answerField.placeholder = @"Password";
    
    __block ConversationListViewController *blockself = self;
    [alert showWithCompletion:^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex == 1) {
            if (answerField.text.length) {
                if (client.configuration.serverPasswordReference.length) {
                    NSString *password = [SSKeychain passwordForService:@"conversation" account:client.configuration.serverPasswordReference];
                    if (password.length)
                        [SSKeychain deletePasswordForService:@"conversation" account:client.configuration.serverPasswordReference];
                }
                NSString *identifier = [[NSUUID UUID] UUIDString];
                [SSKeychain setPassword:answerField.text forService:@"conversation" account:identifier];
                client.configuration.serverPasswordReference = identifier;
                IRCClient *cl;
                int i;
                for (i=0; i<blockself.connections.count; i++) {
                    cl = [blockself.connections objectAtIndex:i];
                    if([client.configuration.uniqueIdentifier isEqualToString:cl.configuration.uniqueIdentifier])
                        break;
                }
                [blockself.connections setObject:client atIndexedSubscript:i];
                [[AppPreferences sharedPrefs] setConnectionConfiguration:client.configuration atIndex:i];
                if ([client isConnected]) {
                    [IRCCommands sendServerPasswordForClient:client];
                } else {
                    [client connect];
                }
            }
        }
    }];
}

- (void)requestUserTrustForCertificate:(IRCCertificateTrust *)trustRequest
{
    CertificateItemRow *commonName =  [trustRequest.issuerInformation objectAtIndex:5];
    NSString *message = [NSString stringWithFormat:@"%@ %@ %@", NSLocalizedString(@"Conversation cannot verify the identity of", @"Conversation cannot verify the identity of"), [commonName itemDescription], NSLocalizedString(@"Would you like to continue anyway?", @"Would you like to continue anyway?")];
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cannot verify Server Identity", @"Cannot verify Server Identity")
                                                            message:message
                                                           delegate:self
                                                  cancelButtonTitle:nil
                                                  otherButtonTitles:NSLocalizedString(@"Cancel", @"Cancel"),
                                                                    NSLocalizedString(@"Continue", @"Continue"),
                                                                    NSLocalizedString(@"Details", @"Details"), nil];
    [alertView setCancelButtonIndex:1];

    [alertView showWithCompletion:^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (buttonIndex == 0) {
            [trustRequest receivedTrustFromUser:NO];
        } else if (buttonIndex == 1) {
            [trustRequest receivedTrustFromUser:YES];
        } else if (buttonIndex == 2) {
            
            CertificateInfoViewController *certificateInfoController = [[CertificateInfoViewController alloc] initWithStyle:UITableViewStyleGrouped];
            certificateInfoController.title = NSLocalizedString(@"Certificate Details", @"Certificate Details");
            
            __block id blockself = self;
            UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           block:^(__strong id object){
                                                                                               [trustRequest receivedTrustFromUser:NO];
                                                                                               [blockself dismissViewControllerAnimated:YES completion:nil];
                                                                                           }];
            
            UIBarButtonItem *trustButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Trust", @"Trust")
                                                                            style:UIBarButtonItemStylePlain
                                                                            block:^(__strong id object){
                                                                                [trustRequest receivedTrustFromUser:YES];
                                                                                [blockself dismissViewControllerAnimated:YES completion:nil];
                                                                            }];
            
            certificateInfoController.subjectInformation = trustRequest.subjectInformation;
            certificateInfoController.issuerInformation = trustRequest.issuerInformation;
            certificateInfoController.certificateInformation = trustRequest.certificateInformation;

            certificateInfoController.navigationItem.rightBarButtonItem = trustButton;
            certificateInfoController.navigationItem.leftBarButtonItem = cancelButton;
            
            UINavigationController *navigationController = [[UINavigationController alloc]
                                                            initWithRootViewController:certificateInfoController];
            
            [self presentViewController:navigationController animated:YES completion:nil];

        }
        
    }];
}

@end
