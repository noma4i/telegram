//
//  RBLPopover.m
//  Rebel
//
//  Created by Danny Greg on 13/09/2012.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RBLPopover.h"

#import "NSColor+RBLCGColorAdditions.h"
#import "NSView+RBLAnimationAdditions.h"

//***************************************************************************

// We'll use this as RBLPopover's backing window. Since it's borderless, we
// just override the `isKeyWindow` method to make it behave in the way that
// `canBecomeKey` demands.


//***************************************************************************

@interface RBLPopoverBackgroundView ()

@property (nonatomic) CGRect screenOriginRect;

+ (instancetype)backgroundViewForContentSize:(CGSize)contentSize popoverEdge:(CGRectEdge)popoverEdge originScreenRect:(CGRect)originScreenRect;

- (CGRectEdge)arrowEdgeForPopoverEdge:(CGRectEdge)popoverEdge;

@end

//***************************************************************************

@interface RBLPopover ()

// The window we are using to display the popover.
@property (nonatomic, strong) RBLPopoverWindow *popoverWindow;

// The identifier for the event monitor we are using to watch for mouse clicks
// outisde of the popover.
// We are not responsible for its memory management.
@property (nonatomic, copy) NSSet *transientEventMonitors;

// The size the content view was before the popover was shown.
@property (nonatomic) CGSize originalViewSize;

@property (nonatomic, strong, readwrite) RBLPopoverBackgroundView *backgroundView;

// Used in semi-transient popovers to make sure we allow a click into the parent
// window to make it key as opposed to closing the popover immediately.
@property (nonatomic) BOOL parentWindowResignedKey;

// Correctly removes our event monitor watching for mouse clicks external to the
// popover.
- (void)removeEventMonitors;

@end

//***************************************************************************

// A class which forcably draws `NSClearColor.clearColor` around a given path,
// effectively clipping any views to the path. You can think of it like a
// `maskLayer` on a `CALayer`.
@interface RBLPopoverClippingView : NSView

// The path which the view will clip to.
@property (nonatomic) CGPathRef clippingPath;

@end

@implementation RBLPopoverClippingView

- (void)setClippingPath:(CGPathRef)clippingPath {
	if (clippingPath == _clippingPath) return;
	
	CGPathRelease(_clippingPath);
	_clippingPath = clippingPath;
	CGPathRetain(_clippingPath);
}

- (void)drawRect:(NSRect)dirtyRect {
	if (self.clippingPath == NULL) return;
	
	CGContextRef currentContext = NSGraphicsContext.currentContext.graphicsPort;
	CGContextAddRect(currentContext, self.bounds);
	CGContextAddPath(currentContext, self.clippingPath);
	CGContextSetBlendMode(currentContext, kCGBlendModeCopy);
	[NSColor.clearColor set];
	CGContextEOFillPath(currentContext);
    
//    [NSColorFromRGB(0xdedede) set];
//    CGContextAddPath(currentContext, self.clippingPath);
//    CGContextStrokePath(currentContext);
}

@end

//***************************************************************************

@implementation RBLPopoverWindow

- (BOOL)canBecomeKeyWindow {
	return self.canBeKey;
}



@end

//***************************************************************************

@interface RBLPopover()
@property (nonatomic, strong) NSWindow *shadowWindow;
@property (nonatomic, strong) NSView *positioningView;
@end

@implementation RBLPopover

- (instancetype)initWithContentViewController:(NSViewController *)viewController {
	self = [super init];
	if (self == nil)
		return nil;
	
	_contentViewController = viewController;
	_backgroundViewClass = RBLPopoverBackgroundView.class;
    _behavior = RBLPopoverBehaviorTransient;
	_animates = YES;
	_fadeDuration = 0.1;

	return self;
}

- (void)dealloc {
	[self.popoverWindow close];
}

#pragma mark -
#pragma mark Derived Properties

- (BOOL)isShown {
	return self.popoverWindow.isVisible;
}


- (void)setHoverView:(BTRControl *)hoverView {
    _hoverView = hoverView;
    
    [hoverView addTarget:self action:@selector(hoverViewExit:) forControlEvents:BTRControlEventMouseExited];
}

- (void)hoverViewExit:(BTRControl *)button {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if(!_hoverView.hovered && self.isShown) {
            if([self isMouseInPopover]) {
                [self hoverViewExit:button];
            } else {
                [self close];
            }
        }
    });
}

- (BOOL)isMouseInPopover {
    NSPoint globalLocation = [ NSEvent mouseLocation ];
    NSPoint windowLocation = [ self.popoverWindow convertScreenToBase: globalLocation ];
    NSPoint viewLocation = [ self.popoverWindow.contentView convertPoint: windowLocation fromView: nil ];
    if( NSPointInRect( viewLocation, [ self.popoverWindow.contentView bounds ] ) ) {
        return YES;
    }
    return NO;
}

#pragma mark -
#pragma mark Showing

- (void)showRelativeToRect:(CGRect)positioningRect ofView:(NSView *)positioningView preferredEdge:(CGRectEdge)preferredEdge {
	if (CGRectEqualToRect(positioningRect, CGRectZero)) {
		positioningRect = [positioningView bounds];
	}
    
    self.positioningView = positioningView;
    
	NSRect windowRelativeRect = [positioningView convertRect:positioningRect toView:nil];
	CGRect screenPositioningRect = [positioningView.window convertRectToScreen:windowRelativeRect];
	self.originalViewSize = self.contentViewController.view.frame.size;
	CGSize contentViewSize = (CGSizeEqualToSize(self.contentSize, CGSizeZero) ? self.contentViewController.view.frame.size : self.contentSize);
	
	CGRect (^popoverRectForEdge)(CGRectEdge) = ^(CGRectEdge popoverEdge) {
		CGSize popoverSize = [self.backgroundViewClass sizeForBackgroundViewWithContentSize:contentViewSize popoverEdge:popoverEdge];
		CGRect returnRect = NSMakeRect(0.0, 0.0, popoverSize.width, popoverSize.height);
		if (popoverEdge == CGRectMinYEdge) {
			CGFloat xOrigin = NSMidX(screenPositioningRect) - floor(popoverSize.width / 2.0);
			CGFloat yOrigin = NSMinY(screenPositioningRect) - popoverSize.height;
			returnRect.origin = NSMakePoint(xOrigin, yOrigin);
		} else if (popoverEdge == CGRectMaxYEdge) {
			CGFloat xOrigin = NSMidX(screenPositioningRect) - floor(popoverSize.width / 2.0);
			returnRect.origin = NSMakePoint(xOrigin, NSMaxY(screenPositioningRect));
		} else if (popoverEdge == CGRectMinXEdge) {
			CGFloat xOrigin = NSMinX(screenPositioningRect) - popoverSize.width;
			CGFloat yOrigin = NSMidY(screenPositioningRect) - floor(popoverSize.height / 2.0);
			returnRect.origin = NSMakePoint(xOrigin, yOrigin);
		} else if (popoverEdge == CGRectMaxXEdge) {
			CGFloat yOrigin = NSMidY(screenPositioningRect) - floor(popoverSize.height / 2.0);
			returnRect.origin = NSMakePoint(NSMaxX(screenPositioningRect), yOrigin);
		} else {
			returnRect = CGRectZero;
		}
		
		return returnRect;
	};
	
	BOOL (^checkPopoverSizeForScreenWithPopoverEdge)(CGRectEdge) = ^(CGRectEdge popoverEdge) {
		CGRect popoverRect = popoverRectForEdge(popoverEdge);
		return NSContainsRect(positioningView.window.screen.visibleFrame, popoverRect);
	};
	
	//This is as ugly as sin… but it gets the job done. I couldn't think of a nice way to code this but still get the desired behavior
	__block CGRectEdge popoverEdge = preferredEdge;
	CGRect (^popoverRect)() = ^{
		CGRectEdge (^nextEdgeForEdge)(CGRectEdge) = ^CGRectEdge (CGRectEdge currentEdge)
		{
			if (currentEdge == CGRectMaxXEdge) {
				return (preferredEdge == CGRectMinXEdge ? CGRectMaxYEdge : CGRectMinXEdge);
			} else if (currentEdge == CGRectMinXEdge) {
				return (preferredEdge == CGRectMaxXEdge ? CGRectMaxYEdge : CGRectMaxXEdge);
			} else if (currentEdge == CGRectMaxYEdge) {
				return (preferredEdge == CGRectMinYEdge ? CGRectMaxXEdge : CGRectMinYEdge);
			} else if (currentEdge == CGRectMinYEdge) {
				return (preferredEdge == CGRectMaxYEdge ? CGRectMaxXEdge : CGRectMaxYEdge);
			}
			
			return currentEdge;
		};
		
		CGRect (^fitRectToScreen)(CGRect) = ^CGRect (CGRect proposedRect) {
			NSRect screenRect = positioningView.window.screen.visibleFrame;
			
			if (proposedRect.origin.y < NSMinY(screenRect)) {
				proposedRect.origin.y = NSMinY(screenRect);
			}
			if (proposedRect.origin.x < NSMinX(screenRect)) {
				proposedRect.origin.x = NSMinX(screenRect);
			}
			
			if (NSMaxY(proposedRect) > NSMaxY(screenRect)) {
				proposedRect.origin.y = (NSMaxY(screenRect) - NSHeight(proposedRect));
			}
			if (NSMaxX(proposedRect) > NSMaxX(screenRect)) {
				proposedRect.origin.x = (NSMaxX(screenRect) - NSWidth(proposedRect));
			}
			
			return proposedRect;
		};
		
		NSUInteger attemptCount = 0;
		while (!checkPopoverSizeForScreenWithPopoverEdge(popoverEdge)) {
			if (attemptCount >= 4) {
				popoverEdge = preferredEdge;
				return fitRectToScreen(popoverRectForEdge(popoverEdge));
				break;
			}
			
			popoverEdge = nextEdgeForEdge(popoverEdge);
			attemptCount ++;
		}
		
		return popoverRectForEdge(popoverEdge);
	};
	
	CGRect popoverScreenRect = popoverRect();
	
	if (self.shown) {
		if (self.backgroundView.popoverEdge == popoverEdge) {
			[self.popoverWindow setFrame:popoverScreenRect display:YES];
			return;
		}
		
		[self.popoverWindow close];
		self.popoverWindow = nil;
	}
	
	//TODO: Create RBLViewController with viewWillAppear
	//[self.contentViewController viewWillAppear:YES]; //this will always be animated… in the current implementation
	
	if (self.willShowBlock != nil) self.willShowBlock(self);
	
	if (self.behavior != NSPopoverBehaviorApplicationDefined) {
		[self removeEventMonitors];
				
		__weak RBLPopover *weakSelf = self;
		void (^monitor)(NSEvent *event) = ^(NSEvent *event) {
			RBLPopover *strongSelf = weakSelf;
			if (strongSelf.popoverWindow == nil)
                return;
			BOOL shouldClose = NO;
			BOOL mouseInPopoverWindow = NSPointInRect(NSEvent.mouseLocation, strongSelf.popoverWindow.frame);
			if (strongSelf.behavior == RBLPopoverBehaviorTransient) {
				shouldClose = !mouseInPopoverWindow;
			} else {
				shouldClose = strongSelf.popoverWindow.parentWindow.isKeyWindow && NSPointInRect(NSEvent.mouseLocation, strongSelf.popoverWindow.parentWindow.frame) && !mouseInPopoverWindow && !strongSelf.parentWindowResignedKey;
				
				if (strongSelf.popoverWindow.parentWindow.isKeyWindow)
                    self.parentWindowResignedKey = NO;
			}
			
            
            
            if (shouldClose) {
                id mouseDownView = [((AppDelegate *)[NSApp delegate]).window.contentView hitTest:event.locationInWindow];
                if(mouseDownView != self.positioningView) {
                    [strongSelf close];
                }
            }
		};
		
		NSInteger mask = 0;
		if (self.behavior == RBLPopoverBehaviorTransient) {
			mask = NSLeftMouseDownMask | NSRightMouseDownMask;
		} else {
			mask = NSLeftMouseUpMask | NSRightMouseUpMask;
		}
		
		NSMutableSet *newMonitors = [[NSMutableSet alloc] init];
		if (self.behavior == RBLPopoverBehaviorTransient) {
			[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appResignedActive:) name:NSApplicationDidResignActiveNotification object:NSApp];
			id globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:monitor];
			[newMonitors addObject:globalMonitor];
		}
		
		if (self.behavior == RBLPopoverBehaviorSemiTransient) {
			[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(parentWindowResignedKey:) name:NSWindowDidResignKeyNotification object:self.popoverWindow.parentWindow];
		}
		
		id localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^(NSEvent *event) {
			monitor(event);
			return event;
		}];
		[newMonitors addObject:localMonitor];
		self.transientEventMonitors = newMonitors;
	}
	
	self.backgroundView = [self.backgroundViewClass backgroundViewForContentSize:contentViewSize popoverEdge:popoverEdge originScreenRect:screenPositioningRect];
	
	CGRect contentViewFrame = [self.backgroundViewClass contentViewFrameForBackgroundFrame:self.backgroundView.bounds popoverEdge:popoverEdge];
	self.contentViewController.view.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
	self.contentViewController.view.frame = contentViewFrame;
	[self.backgroundView addSubview:self.contentViewController.view];
	self.popoverWindow = [[RBLPopoverWindow alloc] initWithContentRect:popoverScreenRect styleMask:NSTexturedBackgroundWindowMask backing:NSBackingStoreBuffered defer:NO];
    self.popoverWindow.popover = self;
    self.popoverWindow.hasShadow = NO;
	self.popoverWindow.releasedWhenClosed = NO;
    self.popoverWindow.opaque = NO;
	self.popoverWindow.backgroundColor = NSColor.clearColor;
	self.popoverWindow.contentView = self.backgroundView;
    [self.popoverWindow setMovable:NO];
	self.popoverWindow.canBeKey = self.canBecomeKey;
	
    
    
    
	// We're using a dummy button to capture the escape key equivalent when it
	// isn't handled by the first responder. This is bad and I feel bad.
	NSButton *closeButton = [[NSButton alloc] initWithFrame:CGRectMake(-1, -1, 0, 0)];
	closeButton.keyEquivalent = @"\E";
	closeButton.target = self;
	closeButton.action = @selector(performClose:);
	[self.popoverWindow.contentView addSubview:closeButton];
	
	RBLPopoverClippingView *clippingView = [[RBLPopoverClippingView alloc] initWithFrame:self.backgroundView.bounds];
    RBLPopoverClippingView *shadowClippingView = [[RBLPopoverClippingView alloc] initWithFrame:self.backgroundView.bounds];

	CGPathRef clippingPath = [self.backgroundView newPopoverPathForEdge:popoverEdge inFrame:clippingView.bounds];
    CGPathRef clippingPath2 = CGPathCreateCopy(clippingPath);
	clippingView.clippingPath = clippingPath;
    shadowClippingView.clippingPath = clippingPath2;
    CGPathRelease(clippingPath);
    CGPathRelease(clippingPath2);

	
	[self.backgroundView addSubview:clippingView];
	
    
    //Shadow window
    self.shadowWindow = [[RBLPopoverWindow alloc] initWithContentRect:popoverScreenRect styleMask:NSTexturedBackgroundWindowMask backing:NSBackingStoreBuffered defer:NO];
    [self.shadowWindow setOpaque:NO];
    [self.shadowWindow setAlphaValue:0.3];
    [self.shadowWindow setMovable:NO];
    [self.shadowWindow setReleasedWhenClosed:NO];
    TMView *shadowView = [[TMView alloc] initWithFrame:self.backgroundView.bounds];
    [self.shadowWindow setContentView:shadowView];
    [shadowView addSubview:shadowClippingView];
    
    
    if (self.animates) {
        self.popoverWindow.alphaValue = 0.0;
        self.shadowWindow.alphaValue = 0.0;
    }
    
    //insertShadow
    [positioningView.window addChildWindow:self.shadowWindow ordered:NSWindowAbove];
    [self.shadowWindow makeKeyAndOrderFront:self];

	[positioningView.window addChildWindow:self.popoverWindow ordered:NSWindowAbove];
	[self.popoverWindow makeKeyAndOrderFront:self];

	void (^postDisplayBlock)(void) = ^{
		if (self.didShowBlock != NULL) self.didShowBlock(self);
	};
	
	if (self.animates) {
		[NSView rbl_animateWithDuration:self.fadeDuration animations:^{
			[self.popoverWindow.animator setAlphaValue:1.0];
            [self.shadowWindow.animator setAlphaValue:0.3];
		} completion:postDisplayBlock];
	} else {
		postDisplayBlock();
	}
}

-(void)keyDown:(NSEvent *)theEvent {
    [super keyDown:theEvent];
}

#pragma mark -
#pragma mark Closing

- (void)close {
	if (!self.shown) return;
	
	[self removeEventMonitors];
	
	if (self.willCloseBlock != nil) self.willCloseBlock(self);
	
	void (^windowTeardown)(void) = ^{
        
        
        
        [self.shadowWindow.parentWindow removeChildWindow:self.shadowWindow];
        [self.shadowWindow close];
        
		[self.popoverWindow.parentWindow removeChildWindow:self.popoverWindow];
		[self.popoverWindow close];
		
		if (self.didCloseBlock != nil) self.didCloseBlock(self);
		
		self.contentViewController.view.frame = CGRectMake(self.contentViewController.view.frame.origin.x, self.contentViewController.view.frame.origin.y, self.originalViewSize.width, self.originalViewSize.height);
	};
	
	if (self.animates) {
		[NSView rbl_animateWithDuration:self.fadeDuration animations:^{
			[self.popoverWindow.animator setAlphaValue:0.0];
            [self.shadowWindow.animator setAlphaValue:0.0];
		} completion:windowTeardown];
	} else {
		windowTeardown();
	}
}

- (IBAction)performClose:(id)sender {
	[self close];
}

#pragma mark -
#pragma mark Event Monitor

- (void)removeEventMonitors {
	for (id eventMonitor in self.transientEventMonitors) {
		[NSEvent removeMonitor:eventMonitor];
	}
	self.transientEventMonitors = nil;
	[NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationDidResignActiveNotification object:NSApp];
	[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
}

- (void)appResignedActive:(NSNotification *)notification {
	if (self.behavior == RBLPopoverBehaviorTransient) [self close];
}

- (void)parentWindowResignedKey:(NSNotification *)notification {
	if (self.behavior != RBLPopoverBehaviorSemiTransient) return;
	
	self.parentWindowResignedKey = YES;
}

@end

//***************************************************************************

static CGFloat const RBLPopoverBackgroundViewBorderRadius = 6.0;
static CGFloat const RBLPopoverBackgroundViewArrowHeight = 12.0;
static CGFloat const RBLPopoverBackgroundViewArrowWidth = 24.0;

//***************************************************************************

@implementation RBLPopoverBackgroundView

+ (CGSize)sizeForBackgroundViewWithContentSize:(CGSize)contentSize popoverEdge:(CGRectEdge)popoverEdge {
	CGSize returnSize = contentSize;
	if (popoverEdge == CGRectMaxXEdge || popoverEdge == CGRectMinXEdge) {
		returnSize.width += RBLPopoverBackgroundViewArrowHeight;
	} else {
		returnSize.height += RBLPopoverBackgroundViewArrowHeight;
	}
	
	returnSize.width += 2.0;
	returnSize.height += 2.0;
	
	return returnSize;
}

+ (CGRect)contentViewFrameForBackgroundFrame:(CGRect)backgroundFrame popoverEdge:(CGRectEdge)popoverEdge {
	CGRect returnFrame = NSInsetRect(backgroundFrame, 1.0, 1.0);
	switch (popoverEdge) {
		case CGRectMinXEdge:
			returnFrame.size.width -= RBLPopoverBackgroundViewArrowHeight;
			break;
		case CGRectMinYEdge:
			returnFrame.size.height -= RBLPopoverBackgroundViewArrowHeight;
			break;
		case CGRectMaxXEdge:
			returnFrame.size.width -= RBLPopoverBackgroundViewArrowHeight;
			returnFrame.origin.x += RBLPopoverBackgroundViewArrowHeight;
			break;
		case CGRectMaxYEdge:
			returnFrame.size.height -= RBLPopoverBackgroundViewArrowHeight;
			returnFrame.origin.y += RBLPopoverBackgroundViewArrowHeight;
			break;
		default:
			NSAssert(NO, @"Failed to pass in a valid CGRectEdge");
			break;
	}
	
	return returnFrame;
}

+ (instancetype)backgroundViewForContentSize:(CGSize)contentSize popoverEdge:(CGRectEdge)popoverEdge originScreenRect:(CGRect)originScreenRect {
	CGSize size = [self sizeForBackgroundViewWithContentSize:contentSize popoverEdge:popoverEdge];
	RBLPopoverBackgroundView *returnView = [[self.class alloc] initWithFrame:NSMakeRect(0.0, 0.0, size.width, size.height) popoverEdge:popoverEdge originScreenRect:originScreenRect];
	return returnView;
}

- (CGPathRef)newPopoverPathForEdge:(CGRectEdge)popoverEdge inFrame:(CGRect)frame {
	CGRectEdge arrowEdge = [self arrowEdgeForPopoverEdge:popoverEdge];
	
	CGRect contentRect = CGRectIntegral([self.class contentViewFrameForBackgroundFrame:frame popoverEdge:self.popoverEdge]);
	CGFloat minX = NSMinX(contentRect);
	CGFloat maxX = NSMaxX(contentRect);
	CGFloat minY = NSMinY(contentRect);
	CGFloat maxY = NSMaxY(contentRect);

	CGRect windowRect = [self.window convertRectFromScreen:self.screenOriginRect];
	CGRect originRect = [self convertRect:windowRect fromView:nil];
	CGFloat midOriginY = floor(NSMidY(originRect));
	CGFloat midOriginX = floor(NSMidX(originRect));
	
	CGFloat maxArrowX = 0.0;
	CGFloat minArrowX = 0.0;
	CGFloat minArrowY = 0.0;
	CGFloat maxArrowY = 0.0;
	
	// Even I have no idea at this point… :trollface:
	// So we don't have a weird arrow situation we need to make sure we draw it within the radius.
	// If we have to nudge it then we have to shrink the arrow as otherwise it looks all wonky and weird.
	// That is what this complete mess below does.
	
	if (arrowEdge == CGRectMinYEdge || arrowEdge == CGRectMaxYEdge) {
		maxArrowX = floor(midOriginX + (RBLPopoverBackgroundViewArrowWidth / 2.0));
		CGFloat maxPossible = (NSMaxX(contentRect) - RBLPopoverBackgroundViewBorderRadius);
		if (maxArrowX > maxPossible) {
			CGFloat delta = maxArrowX - maxPossible;
			maxArrowX = maxPossible;
			minArrowX = maxArrowX - (RBLPopoverBackgroundViewArrowWidth - delta);
		} else {
			minArrowX = floor(midOriginX - (RBLPopoverBackgroundViewArrowWidth / 2.0));
			if (minArrowX < RBLPopoverBackgroundViewBorderRadius) {
				CGFloat delta = RBLPopoverBackgroundViewBorderRadius - minArrowX;
				minArrowX = RBLPopoverBackgroundViewBorderRadius;
				maxArrowX = minArrowX + (RBLPopoverBackgroundViewArrowWidth - (delta * 2));
			}
		}
	} else {
		minArrowY = floor(midOriginY - (RBLPopoverBackgroundViewArrowWidth / 2.0));
		if (minArrowY < RBLPopoverBackgroundViewBorderRadius) {
			CGFloat delta = RBLPopoverBackgroundViewBorderRadius - minArrowY;
			minArrowY = RBLPopoverBackgroundViewBorderRadius;
			maxArrowY = minArrowY + (RBLPopoverBackgroundViewArrowWidth - (delta * 2));
		} else {
			maxArrowY = floor(midOriginY + (RBLPopoverBackgroundViewArrowWidth / 2.0));
			CGFloat maxPossible = (NSMaxY(contentRect) - RBLPopoverBackgroundViewBorderRadius);
			if (maxArrowY > maxPossible) {
				CGFloat delta = maxArrowY - maxPossible;
				maxArrowY = maxPossible;
				minArrowY = maxArrowY - (RBLPopoverBackgroundViewArrowWidth - delta);
			}
		}
	}
	
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, minX, floor(minY + RBLPopoverBackgroundViewBorderRadius));
	if (arrowEdge == CGRectMinXEdge) {
		CGPathAddLineToPoint(path, NULL, minX, minArrowY);
		CGPathAddLineToPoint(path, NULL, floor(minX - RBLPopoverBackgroundViewArrowHeight), midOriginY);
		CGPathAddLineToPoint(path, NULL, minX, maxArrowY);
	}
	
	CGPathAddArc(path, NULL, floor(minX + RBLPopoverBackgroundViewBorderRadius), floor(minY + contentRect.size.height - RBLPopoverBackgroundViewBorderRadius), RBLPopoverBackgroundViewBorderRadius, M_PI, M_PI / 2, 1);
	if (arrowEdge == CGRectMaxYEdge) {
		CGPathAddLineToPoint(path, NULL, minArrowX, maxY);
		CGPathAddLineToPoint(path, NULL, midOriginX, floor(maxY + RBLPopoverBackgroundViewArrowHeight));
		CGPathAddLineToPoint(path, NULL, maxArrowX, maxY);
	}
	
	CGPathAddArc(path, NULL, floor(minX + contentRect.size.width - RBLPopoverBackgroundViewBorderRadius), floor(minY + contentRect.size.height - RBLPopoverBackgroundViewBorderRadius), RBLPopoverBackgroundViewBorderRadius, M_PI / 2, 0.0, 1);
	if (arrowEdge == CGRectMaxXEdge) {
		CGPathAddLineToPoint(path, NULL, maxX, maxArrowY);
		CGPathAddLineToPoint(path, NULL, floor(maxX + RBLPopoverBackgroundViewArrowHeight), midOriginY);
		CGPathAddLineToPoint(path, NULL, maxX, minArrowY);
	}
	
	CGPathAddArc(path, NULL, floor(contentRect.origin.x + contentRect.size.width - RBLPopoverBackgroundViewBorderRadius), floor(minY + RBLPopoverBackgroundViewBorderRadius), RBLPopoverBackgroundViewBorderRadius, 0.0, -M_PI / 2, 1);
	if (arrowEdge == CGRectMinYEdge) {
		CGPathAddLineToPoint(path, NULL, maxArrowX, minY);
		CGPathAddLineToPoint(path, NULL, midOriginX, floor(minY - RBLPopoverBackgroundViewArrowHeight));
		CGPathAddLineToPoint(path, NULL, minArrowX, minY);
	}
    
	CGPathAddArc(path, NULL, floor(minX + RBLPopoverBackgroundViewBorderRadius), floor(minY + RBLPopoverBackgroundViewBorderRadius), RBLPopoverBackgroundViewBorderRadius, -M_PI / 2, M_PI, 1);
    
	return path;
}

- (instancetype)initWithFrame:(CGRect)frame popoverEdge:(CGRectEdge)popoverEdge originScreenRect:(CGRect)originScreenRect {
	self = [super initWithFrame:frame];
	if (self == nil) return nil;
	
	_popoverEdge = popoverEdge;
	_screenOriginRect = originScreenRect;
	_fillColor = NSColor.whiteColor;
	
	return self;
}

- (void)drawRect:(NSRect)rect {
	[super drawRect:rect];
	[self.fillColor set];
	NSRectFill(rect);
}

- (CGRectEdge)arrowEdgeForPopoverEdge:(CGRectEdge)popoverEdge {
	CGRectEdge arrowEdge = CGRectMinYEdge;
	switch (popoverEdge) {
		case CGRectMaxXEdge:
			arrowEdge = CGRectMinXEdge;
			break;
		case CGRectMaxYEdge:
			arrowEdge = CGRectMinYEdge;
			break;
		case CGRectMinXEdge:
			arrowEdge = CGRectMaxXEdge;
			break;
		case CGRectMinYEdge:
			arrowEdge = CGRectMaxYEdge;
			break;
		default:
			break;
	}
	
	return arrowEdge;
}

- (BOOL)isOpaque {
	return NO;
}

@end
