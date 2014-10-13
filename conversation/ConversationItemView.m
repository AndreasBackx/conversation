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

#import "ConversationItemView.h"

@implementation ConversationItemView

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if(!self)
        return nil;
    
    
    return self;
}

- (void) prepareForReuse
{
    [super prepareForReuse];
    
    self.textLabel.text = @"";
}


-(void)layoutSubviews
{
    [super layoutSubviews];
    
    if (self.accessoryType != UITableViewCellAccessoryNone) {
        
        for (UIView *subview in self.subviews) {
            if (subview != self.textLabel &&
                subview != self.detailTextLabel &&
                subview != self.backgroundView &&
                subview != self.contentView &&
                subview != self.selectedBackgroundView &&
                subview != self.imageView) {
                
                // This subview should be the accessory view, change its frame
                CGRect frame = subview.frame;
                frame.origin.y -= 15;
                subview.frame = frame;
                
                if(_unreadCount > 0) {
                    
                    // Add unread count label
                    NSString *value = [NSString stringWithFormat:@"%li", (long)_unreadCount];
                    UILabel *unread = [[UILabel alloc] initWithFrame:CGRectNull];
                    unread.textColor = [UIColor lightGrayColor];
                    unread.font = [UIFont fontWithName:@"Helvetica Neue" size:14.0];
                    unread.text = [NSString stringWithFormat:@"%li", (long)_unreadCount];
                    
                    // Calculate frame size
                    NSDictionary *dict = @{NSFontAttributeName: unread.font };
                    CGSize size = [value sizeWithAttributes:dict];
                    unread.frame = CGRectMake(frame.origin.x-size.width-5, frame.origin.y-2, size.width, size.height);
                    
                    [self.contentView addSubview:unread];
                }
                
                break;
            }
        }
    }
    
    self.textLabel.text = _name;
    
    NSArray *lines = [_detail componentsSeparatedByString:@"\n"];
    self.detailTextLabel.text = [lines objectAtIndex:0];

    CGRect contentRect = self.contentView.frame;
    CGRect nameFrame = self.textLabel.frame;
    nameFrame.origin.y = round((contentRect.size.height / 2.) - 25);
    self.textLabel.frame = nameFrame;
    
    // Add first detail line
    CGRect detailFrame = self.detailTextLabel.frame;
    double width = self.contentView.frame.size.width - self.imageView.frame.size.width - 5;

    [self.detailTextLabel setFont:[UIFont fontWithName:@"Helvetica Neue" size:14.0]];
    [self.detailTextLabel setTextColor:[UIColor lightGrayColor]];
    self.detailTextLabel.frame = CGRectMake(nameFrame.origin.x-5, nameFrame.origin.y+20, width, detailFrame.size.height);

    
    if([lines count] > 1) {
        
        // Add second detail line
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(nameFrame.origin.x, nameFrame.origin.y+35, width, detailFrame.size.height)];
        [label setFont:[UIFont fontWithName:@"Helvetica Neue" size:14.0]];
        [label setTextColor:[UIColor lightGrayColor]];
        label.text = [lines objectAtIndex:1];
        [self.contentView addSubview:label];
        
    }

}


- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end