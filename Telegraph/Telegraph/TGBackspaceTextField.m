#import "TGBackspaceTextField.h"

@interface TGBackspaceTextField ()

@end

@implementation TGBackspaceTextField

@synthesize customPlaceholderLabel = _customPlaceholderLabel;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
    {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    _customPlaceholderLabel = [[UILabel alloc] init];
    _customPlaceholderLabel.backgroundColor = [UIColor clearColor];
    _customPlaceholderLabel.font = [UIFont systemFontOfSize:15];
    _customPlaceholderLabel.text = TGLocalized(@"Compose.TokenListPlaceholder");
    [_customPlaceholderLabel sizeToFit];
    _customPlaceholderLabel.userInteractionEnabled = false;
    _customPlaceholderLabel.textColor = UIColorRGB(0x8d9298);
}

- (void)setShowPlaceholder:(bool)showPlaceholder animated:(bool)animated
{
    if (showPlaceholder != _customPlaceholderLabel.alpha > FLT_EPSILON)
    {
        if (animated)
        {
            [UIView animateWithDuration:0.2 animations:^
            {
                _customPlaceholderLabel.alpha = showPlaceholder ? 1.0f : 0.0f;
            }];
        }
        else
            _customPlaceholderLabel.alpha = showPlaceholder ? 1.0f : 0.0f;
    }
}

- (void)setText:(NSString *)text
{
    [super setText:text];
    
    _customPlaceholderLabel.hidden = text.length != 0;
}

- (void)deleteBackward
{
    bool wasEmpty = self.text.length == 0;
    
    [super deleteBackward];
    
    if (wasEmpty && iosMajorVersion() >= 6)
        [self deleteLastBackward];
}

- (void)deleteLastBackward
{
    id delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(textFieldDidHitLastBackspace)])
        [delegate performSelector:@selector(textFieldDidHitLastBackspace)];
}

- (BOOL)becomeFirstResponder
{
    if ([super becomeFirstResponder])
    {
        id delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(textFieldDidBecomeFirstResponder)])
            [delegate performSelector:@selector(textFieldDidBecomeFirstResponder)];
        return true;
    }
    return false;
}

- (BOOL)resignFirstResponder
{
    if ([super resignFirstResponder])
    {
        id delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(textFieldDidResignFirstResponder)])
            [delegate performSelector:@selector(textFieldDidResignFirstResponder)];
        return true;
    }
    return false;
}

- (CGRect)textRectForBounds:(CGRect)bounds
{
    return CGRectOffset([super textRectForBounds:bounds], 0.0f, 10.0f);
}

- (CGRect)editingRectForBounds:(CGRect)bounds
{
    return CGRectOffset([super editingRectForBounds:bounds], 0.0f, 10.0f);
}

@end
