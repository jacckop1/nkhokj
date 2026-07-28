#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdlib.h>
#import "WGTranslations.h"

/*
 * WhitegramArabic NodeFix v8
 *
 * v7 restored translation by writing directly into Swift stored properties.
 * That is unsafe on Whitegram 12.9.2 because ImmediateTextNode.attributedText
 * is a Swift-owned field whose ownership/layout is not represented safely to
 * the Objective-C runtime. The write corrupted objects and caused crashes in
 * Settings, registration and other screens.
 *
 * v8 never reads or writes Swift ivars. Telegram's ItemList rows create their
 * visible text as immutable NSAttributedString instances. We translate exact
 * dictionary matches while those immutable strings are being constructed, then
 * keep the stable UIKit hooks for labels, buttons, titles and placeholders.
 * No NSBundle hook, no UITextView hook, no _ASDisplayView hook and no private
 * object_setIvar path are used.
 */

#pragma mark - Immutable attributed-string construction hook

static SEL WGOriginalAttributedInitSelector(void) {
    return sel_registerName("wg_nf_original_initWithString:attributes:");
}

static id WGAttributedInitWithStringAndAttributes(id self,
                                                   SEL _cmd,
                                                   NSString *string,
                                                   NSDictionary<NSAttributedStringKey, id> *attributes) {
    (void)_cmd;

    NSString *source = [string isKindOfClass:NSString.class] ? string : @"";
    NSString *translated = WGArabicTranslateStringExact(source);
    if (!translated) {
        translated = source;
    }

    SEL originalSelector = WGOriginalAttributedInitSelector();
    return ((id (*)(id, SEL, NSString *, NSDictionary *))objc_msgSend)(self,
                                                                       originalSelector,
                                                                       translated,
                                                                       attributes);
}

static BOOL WGClassHasOwnMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int index = 0; index < count; index++) {
        if (method_getName(methods[index]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

static void WGInstallAttributedInitHookOnClass(Class cls) {
    if (!cls) {
        return;
    }

    SEL originalSelector = @selector(initWithString:attributes:);
    SEL aliasSelector = WGOriginalAttributedInitSelector();

    if (WGClassHasOwnMethod(cls, aliasSelector)) {
        return;
    }

    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    if (!originalMethod) {
        return;
    }

    IMP originalImplementation = method_getImplementation(originalMethod);
    const char *types = method_getTypeEncoding(originalMethod);
    if (!originalImplementation || !types) {
        return;
    }

    if (!class_addMethod(cls, aliasSelector, originalImplementation, types)) {
        return;
    }

    class_replaceMethod(cls,
                        originalSelector,
                        (IMP)WGAttributedInitWithStringAndAttributes,
                        types);
}

static void WGInstallAttributedStringHooks(void) {
    /*
     * NSAttributedString is a class cluster. Capture both the allocation class
     * and the initialized immutable concrete class before installing hooks.
     * Concrete classes are hooked first so their alias always points to Apple's
     * original initializer, never to a hook inherited from the abstract base.
     */
    NSMutableOrderedSet *classes = [NSMutableOrderedSet orderedSet];

    id allocated = [NSAttributedString alloc];
    Class allocationClass = allocated ? object_getClass(allocated) : Nil;
    NSAttributedString *sample = [allocated initWithString:@"WGArabicProbe"
                                                 attributes:@{}];
    Class sampleClass = sample ? object_getClass(sample) : Nil;

    // Hook the initialized concrete class before the allocation/placeholder
    // class. If one inherits from the other, this preserves the true original
    // initializer in each alias and prevents an alias from pointing at our hook.
    if (sampleClass) {
        [classes addObject:sampleClass];
    }
    if (allocationClass) {
        [classes addObject:allocationClass];
    }

    for (id value in classes) {
        Class cls = (Class)value;
        if (cls != NSAttributedString.class) {
            WGInstallAttributedInitHookOnClass(cls);
        }
    }
    WGInstallAttributedInitHookOnClass(NSAttributedString.class);
}

#pragma mark - Stable UIKit hooks

static void WGScheduleSafeUIKitScan(NSTimeInterval delay);

@interface UILabel (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text;
- (void)wg_nf_setAttributedText:(NSAttributedString *)text;
@end

@implementation UILabel (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text {
    NSString *translated = WGArabicTranslateString(text);
    [self wg_nf_setText:translated];
    if (text && ![translated isEqualToString:text]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        self.textAlignment = NSTextAlignmentNatural;
    }
}

- (void)wg_nf_setAttributedText:(NSAttributedString *)text {
    NSAttributedString *translated = WGArabicTranslateAttributedString(text);
    [self wg_nf_setAttributedText:translated];
    if (text && ![translated.string isEqualToString:text.string]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        self.textAlignment = NSTextAlignmentNatural;
    }
}
@end

@interface UIButton (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title forState:(UIControlState)state;
- (void)wg_nf_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state;
@end

@implementation UIButton (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title forState:(UIControlState)state {
    NSString *translated = WGArabicTranslateString(title);
    [self wg_nf_setTitle:translated forState:state];
    if (title && ![translated isEqualToString:title]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
}

- (void)wg_nf_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state {
    NSAttributedString *translated = WGArabicTranslateAttributedString(title);
    [self wg_nf_setAttributedTitle:translated forState:state];
    if (title && ![translated.string isEqualToString:title.string]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
}
@end

@interface UITextField (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder;
@end

@implementation UITextField (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder {
    [self wg_nf_setPlaceholder:WGArabicTranslateString(placeholder)];
}
@end

@interface UISearchBar (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder;
@end

@implementation UISearchBar (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder {
    [self wg_nf_setPlaceholder:WGArabicTranslateString(placeholder)];
}
@end

@interface UINavigationItem (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title;
@end

@implementation UINavigationItem (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title {
    [self wg_nf_setTitle:WGArabicTranslateString(title)];
}
@end

@interface UIViewController (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title;
- (void)wg_nf_viewDidAppear:(BOOL)animated;
@end

@implementation UIViewController (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title {
    [self wg_nf_setTitle:WGArabicTranslateString(title)];
}

- (void)wg_nf_viewDidAppear:(BOOL)animated {
    [self wg_nf_viewDidAppear:animated];
    WGScheduleSafeUIKitScan(0.08);
}
@end

@interface UIAlertController (WGArabicNodeFix)
+ (instancetype)wg_nf_alertControllerWithTitle:(NSString *)title
                                        message:(NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle;
@end

@implementation UIAlertController (WGArabicNodeFix)
+ (instancetype)wg_nf_alertControllerWithTitle:(NSString *)title
                                        message:(NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle {
    return [self wg_nf_alertControllerWithTitle:WGArabicTranslateString(title)
                                        message:WGArabicTranslateString(message)
                                 preferredStyle:preferredStyle];
}
@end

@interface UIBarButtonItem (WGArabicNodeFix)
- (instancetype)wg_nf_initWithTitle:(NSString *)title
                              style:(UIBarButtonItemStyle)style
                             target:(id)target
                             action:(SEL)action;
@end

@implementation UIBarButtonItem (WGArabicNodeFix)
- (instancetype)wg_nf_initWithTitle:(NSString *)title
                              style:(UIBarButtonItemStyle)style
                             target:(id)target
                             action:(SEL)action {
    return [self wg_nf_initWithTitle:WGArabicTranslateString(title)
                               style:style
                              target:target
                              action:action];
}
@end

#pragma mark - Safe UIKit-only fallback scan

static NSUInteger WGTranslateUIKitView(UIView *view) {
    NSUInteger changes = 0;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.attributedText.length > 0) {
            NSAttributedString *translated = WGArabicTranslateAttributedString(label.attributedText);
            if (![translated.string isEqualToString:label.attributedText.string]) {
                label.attributedText = translated;
                label.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
                label.textAlignment = NSTextAlignmentNatural;
                changes++;
            }
        } else if (label.text.length > 0) {
            NSString *translated = WGArabicTranslateString(label.text);
            if (![translated isEqualToString:label.text]) {
                label.text = translated;
                label.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
                label.textAlignment = NSTextAlignmentNatural;
                changes++;
            }
        }
    } else if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        if (field.placeholder.length > 0) {
            NSString *translated = WGArabicTranslateString(field.placeholder);
            if (![translated isEqualToString:field.placeholder]) {
                field.placeholder = translated;
                changes++;
            }
        }
    } else if ([view isKindOfClass:UISearchBar.class]) {
        UISearchBar *searchBar = (UISearchBar *)view;
        if (searchBar.placeholder.length > 0) {
            NSString *translated = WGArabicTranslateString(searchBar.placeholder);
            if (![translated isEqualToString:searchBar.placeholder]) {
                searchBar.placeholder = translated;
                changes++;
            }
        }
    }

    return changes;
}

static NSUInteger WGScanUIKitTree(UIView *view, NSUInteger depth, NSUInteger *visited) {
    if (!view || depth > 80 || *visited > 2200) {
        return 0;
    }

    (*visited)++;
    NSUInteger changes = WGTranslateUIKitView(view);
    for (UIView *subview in view.subviews) {
        changes += WGScanUIKitTree(subview, depth + 1, visited);
    }
    return changes;
}

static NSArray<UIWindow *> *WGVisibleWindows(void) {
    UIApplication *application = UIApplication.sharedApplication;
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.hidden && window.alpha > 0.01) {
                    [windows addObject:window];
                }
            }
        }
    }

    if (windows.count == 0) {
        for (UIWindow *window in application.windows) {
            if (!window.hidden && window.alpha > 0.01) {
                [windows addObject:window];
            }
        }
    }

    return windows.array;
}

static BOOL WGSafeScanPending = NO;

static void WGRunSafeUIKitScan(void) {
    if (!WGArabicLocalizationEnabled()) {
        return;
    }

    NSUInteger visited = 0;
    for (UIWindow *window in WGVisibleWindows()) {
        WGScanUIKitTree(window, 0, &visited);
    }
}

static void WGScheduleSafeUIKitScan(NSTimeInterval delay) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WGScheduleSafeUIKitScan(delay);
        });
        return;
    }

    if (WGSafeScanPending) {
        return;
    }
    WGSafeScanPending = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WGRunSafeUIKitScan();
        WGSafeScanPending = NO;
    });
}

#pragma mark - Swizzle installation

static void WGSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        return;
    }

    BOOL added = class_addMethod(cls,
                                 original,
                                 method_getImplementation(replacementMethod),
                                 method_getTypeEncoding(replacementMethod));
    if (added) {
        class_replaceMethod(cls,
                            replacement,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

static void WGSwizzleClass(Class cls, SEL original, SEL replacement) {
    WGSwizzle(object_getClass(cls), original, replacement);
}

static void WGInstallUIKitHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WGSwizzle(UILabel.class, @selector(setText:), @selector(wg_nf_setText:));
        WGSwizzle(UILabel.class, @selector(setAttributedText:), @selector(wg_nf_setAttributedText:));
        WGSwizzle(UIButton.class, @selector(setTitle:forState:), @selector(wg_nf_setTitle:forState:));
        WGSwizzle(UIButton.class,
                  @selector(setAttributedTitle:forState:),
                  @selector(wg_nf_setAttributedTitle:forState:));
        WGSwizzle(UITextField.class, @selector(setPlaceholder:), @selector(wg_nf_setPlaceholder:));
        WGSwizzle(UISearchBar.class, @selector(setPlaceholder:), @selector(wg_nf_setPlaceholder:));
        WGSwizzle(UINavigationItem.class, @selector(setTitle:), @selector(wg_nf_setTitle:));
        WGSwizzle(UIViewController.class, @selector(setTitle:), @selector(wg_nf_setTitle:));
        WGSwizzle(UIViewController.class, @selector(viewDidAppear:), @selector(wg_nf_viewDidAppear:));
        WGSwizzleClass(UIAlertController.class,
                       @selector(alertControllerWithTitle:message:preferredStyle:),
                       @selector(wg_nf_alertControllerWithTitle:message:preferredStyle:));
        WGSwizzle(UIBarButtonItem.class,
                  @selector(initWithTitle:style:target:action:),
                  @selector(wg_nf_initWithTitle:style:target:action:));
    });
}

#pragma mark - Entry point

__attribute__((constructor))
static void WGArabicNodeFixEntryPoint(void) {
    @autoreleasepool {
        WGInstallAttributedStringHooks();
        WGInstallUIKitHooks();

        dispatch_async(dispatch_get_main_queue(), ^{
            WGScheduleSafeUIKitScan(0.30);
        });
    }
}
