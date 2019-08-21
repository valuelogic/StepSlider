//
//  StepSlider.m
//  StepSlider
//
//  Created by Nick on 10/15/15.
//  Copyright © 2015 spromicky. All rights reserved.
//

#import "StepSlider.h"
#import "SliderTrackLayer.h"

#define GENERATE_SETTER(PROPERTY, TYPE, SETTER, UPDATER) \
- (void)SETTER:(TYPE)PROPERTY { \
if (_##PROPERTY != PROPERTY) { \
_##PROPERTY = PROPERTY; \
UPDATER \
[self setNeedsLayout]; \
} \
}

static NSString * const kTrackAnimation = @"kTrackAnimation";

typedef void (^withoutAnimationBlock)(void);
void withoutCAAnimation(withoutAnimationBlock code)
{
    [CATransaction begin];
    [CATransaction setValue: (id) kCFBooleanTrue forKey: kCATransactionDisableActions];
    code();
    [CATransaction commit];
}

@interface StepSlider ()
{
    SliderTrackLayer *_trackLayer;
    CAShapeLayer *_trackMaskLayer;
    CAGradientLayer *_trackGradientLayer;
    CAShapeLayer *_sliderCircleLayer;
    NSMutableArray <CAShapeLayer *> *_trackCirclesArray;
    NSMutableArray <CATextLayer *> *_trackLabelsArray;
    NSMutableDictionary <NSNumber *, UIImage *> *_trackCircleImages;
    
    UIImpactFeedbackGenerator* _selectFeedback;
    
    BOOL animateLayouts;
    
    CGFloat maxRadius;
    CGFloat diff;
    
    CGPoint startTouchPosition;
    CGPoint startSliderPosition;
    
    CGSize contentSize;
}

@end

@implementation StepSlider

#pragma mark - Init

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self generalSetup];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self generalSetup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self addLayers];
    }
    return self;
}

- (void)addLayers
{
    _dotsInteractionEnabled = YES;
    _trackCirclesArray = [[NSMutableArray alloc] init];
    _trackLabelsArray  = [[NSMutableArray alloc] init];
    _trackCircleImages = [[NSMutableDictionary alloc] init];
    
    _sliderCircleLayer = [CAShapeLayer layer];
    _sliderCircleLayer.contentsScale = [UIScreen mainScreen].scale;
    
    [self.layer addSublayer:_sliderCircleLayer];
    
    _trackLayer = [SliderTrackLayer layer];
    [self.layer addSublayer:_trackLayer];
    
    _trackGradientLayer = [CAGradientLayer layer];
    _trackGradientLayer.startPoint = CGPointMake(0.0, 0.5);
    _trackGradientLayer.endPoint = CGPointMake(1.0, 0.5);
    [self.layer addSublayer:_trackGradientLayer];
    
    _trackMaskLayer = [CAShapeLayer layer];
    _trackMaskLayer.fillColor = [UIColor blackColor].CGColor;
    
    _labelFont = [UIFont systemFontOfSize:15.f];
    contentSize = self.bounds.size;
}

- (void)generalSetup
{
    [self addLayers];
    
    _maxCount               = 4;
    _index                  = 2;
    _trackCircleRadius      = 5.f;
    _sliderCircleRadius     = 12.5f;
    _trackTintStartColor    = [UIColor blueColor];
    _trackTintEndColor      = [UIColor yellowColor];
    _sliderCircleColor      = [UIColor whiteColor];
    _labelOffset            = 20.f;
    _labelColor             = [UIColor whiteColor];
    [self updateMaxRadius];
    
    [self setNeedsLayout];
}

- (CGSize)intrinsicContentSize
{
    return contentSize;
}

#pragma mark - Draw

- (void)prepareForInterfaceBuilder
{
    [self updateMaxRadius];
    [super prepareForInterfaceBuilder];
}

- (void)layoutLayersAnimated:(BOOL)animated
{
    NSInteger indexDiff = fabsf(roundf([self indexCalculate]) - self.index);
    BOOL left = (roundf([self indexCalculate]) - self.index) < 0;
    
    CGFloat contentWidth = self.bounds.size.width - 2 * maxRadius;
    CGFloat stepWidth = contentWidth;
    
    if (self.maxCount - 1 > 0) {
        stepWidth /= (self.maxCount - 1);
    }
    
    CGFloat sliderHeight = fmaxf(maxRadius, self.trackHeight / 2.f) * 2.f;
    CGFloat labelsHeight = [self labelHeightWithMaxWidth:stepWidth] + self.labelOffset;
    CGFloat totalHeight  = sliderHeight + labelsHeight;
    
    contentSize = CGSizeMake(fmaxf(44.f, self.bounds.size.width), fmaxf(44.f, totalHeight));
    if (!CGSizeEqualToSize(self.bounds.size, contentSize)) {
        if (self.constraints.count) {
            [self invalidateIntrinsicContentSize];
        } else {
            CGRect newFrame = self.frame;
            newFrame.size = contentSize;
            self.frame = newFrame;
        }
    }
    
    CGFloat contentFrameY = (self.bounds.size.height - totalHeight) / 2.f;
    
    if (self.labelOrientation == StepSliderTextOrientationUp && self.labels.count) {
        contentFrameY += labelsHeight;
    }
    
    CGRect contentFrame = CGRectMake(maxRadius, contentFrameY, contentWidth, sliderHeight);
    
    CGFloat circleFrameSide = self.trackCircleRadius * 2.f;
    CGFloat sliderDiameter  = self.sliderCircleRadius * 2.f;
    
    CGPoint oldPosition = _sliderCircleLayer.position;
    CGPathRef oldPath   = _trackMaskLayer.path;
    
    CGFloat labelsY     = self.labelOrientation ? (self.bounds.size.height - totalHeight) / 2.f : (CGRectGetMaxY(contentFrame) + self.labelOffset);
    
    if (!animated) {
        [CATransaction begin];
        [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    }
    
    _sliderCircleLayer.path     = NULL;
    _sliderCircleLayer.contents = nil;
    
    if (self.sliderCircleImage) {
        _sliderCircleLayer.frame    = CGRectMake(0.f, 0.f, fmaxf(self.sliderCircleImage.size.width, 44.f), fmaxf(self.sliderCircleImage.size.height, 44.f));
        _sliderCircleLayer.contents = (__bridge id)self.sliderCircleImage.CGImage;
        _sliderCircleLayer.contentsGravity = kCAGravityCenter;
    } else {
        CGFloat sliderFrameSide = fmaxf(self.sliderCircleRadius * 2.f, 44.f);
        CGRect  sliderDrawRect  = CGRectMake((sliderFrameSide - sliderDiameter) / 2.f, (sliderFrameSide - sliderDiameter) / 2.f, sliderDiameter, sliderDiameter);
        
        _sliderCircleLayer.frame     = CGRectMake(0.f, 0.f, sliderFrameSide, sliderFrameSide);
        _sliderCircleLayer.path      = [UIBezierPath bezierPathWithRoundedRect:sliderDrawRect cornerRadius:sliderFrameSide / 2].CGPath;
        _sliderCircleLayer.fillColor = [self.sliderCircleColor CGColor];
    }
    _sliderCircleLayer.position = CGPointMake(contentFrame.origin.x + stepWidth * self.index, CGRectGetMidY(contentFrame));
    
    if (animated) {
        CABasicAnimation *basicSliderAnimation = [CABasicAnimation animationWithKeyPath:@"position"];
        basicSliderAnimation.duration = [CATransaction animationDuration];
        basicSliderAnimation.fromValue = [NSValue valueWithCGPoint:(oldPosition)];
        [_sliderCircleLayer addAnimation:basicSliderAnimation forKey:@"position"];
    }

    CGSize trackSize = [_trackLayer sizeThatFits:CGSizeMake(self.bounds.size.width, CGFLOAT_MAX)];
    CGPoint origin = CGPointMake(0.0, CGRectGetMidY(contentFrame) - trackSize.height * 0.5f);
    CGRect frame = CGRectMake(origin.x, origin.y, trackSize.width, trackSize.height);
    
    _trackLayer.frame = frame;
    
    _trackMaskLayer.path = [self fillingPath];
    
    _trackGradientLayer.colors = self.trackTintColors;
    _trackGradientLayer.frame = frame;
    [_trackGradientLayer setMask:_trackMaskLayer];
    
    if (animated) {
        CABasicAnimation *basicTrackAnimation = [CABasicAnimation animationWithKeyPath:@"path"];
        basicTrackAnimation.duration = [CATransaction animationDuration];
        basicTrackAnimation.fromValue = (__bridge id _Nullable)(oldPath);
        [_trackMaskLayer addAnimation:basicTrackAnimation forKey:@"path"];
    }
    
    _trackCirclesArray = [self clearExcessLayers:_trackCirclesArray];
    
    CGFloat currentWidth = self.adjustLabel ? _trackLabelsArray.firstObject.bounds.size.width * 2 : _trackLabelsArray.firstObject.bounds.size.width;
    if ((currentWidth > 0 && currentWidth != stepWidth) || !self.labels.count) {
        [self removeLabelLayers];
    }
    
    NSTimeInterval animationTimeDiff = 0;
    if (indexDiff > 0) {
        animationTimeDiff = (left ? [CATransaction animationDuration] : -[CATransaction animationDuration]) / indexDiff;
    }
    NSTimeInterval animationTime = left ? animationTimeDiff : [CATransaction animationDuration] + animationTimeDiff;
    CGFloat circleAnimation      = circleFrameSide / _trackLayer.frame.size.width;
    
    for (NSUInteger i = 0; i < self.maxCount; i++) {
        CAShapeLayer *trackCircle;
        CATextLayer *trackLabel;
        
        if (self.labels.count) {
            trackLabel = [self textLayerWithSize:CGSizeMake([self roundForTextDrawing:stepWidth], labelsHeight - self.labelOffset) index:i];
        }
        
        if (i < _trackCirclesArray.count) {
            trackCircle = _trackCirclesArray[i];
        } else {
            trackCircle = [CAShapeLayer layer];
            
            [self.layer addSublayer:trackCircle];
            
            [_trackCirclesArray addObject:trackCircle];
        }
        
        
        trackCircle.bounds   = CGRectMake(0.f, 0.f, circleFrameSide, circleFrameSide);
        trackCircle.position = CGPointMake(contentFrame.origin.x + stepWidth * i, CGRectGetMidY(contentFrame));
        
        CGImageRef trackCircleImage = [self trackCircleImage:trackCircle];
        if (!trackCircleImage) {
            trackCircle.path = [UIBezierPath bezierPathWithRoundedRect:trackCircle.bounds cornerRadius:circleFrameSide / 2].CGPath;
            trackCircle.contents = nil;
        } else {
            trackCircle.path = NULL;
        }
        
        trackLabel.position        = CGPointMake(contentFrame.origin.x + stepWidth * i, labelsY);
        
        if (i == _index){
            trackLabel.foregroundColor = self.selectedLabelColor.CGColor;
        } else {
            trackLabel.foregroundColor = self.labelColor.CGColor;
        }
        
        if (animated) {
            if (trackCircleImage) {
                CGImageRef oldImage = (__bridge CGImageRef)(trackCircle.contents);
                
                if (oldImage != trackCircleImage) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(animationTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        trackCircle.contents = (__bridge id _Nullable)(trackCircleImage);
                        
                        CABasicAnimation *basicTrackCircleAnimation = [CABasicAnimation animationWithKeyPath:kTrackAnimation];
                        basicTrackCircleAnimation.duration = [CATransaction animationDuration] * circleAnimation;
                        basicTrackCircleAnimation.fromValue = (__bridge id _Nullable)(oldImage);
                        [trackCircle addAnimation:basicTrackCircleAnimation forKey:kTrackAnimation];
                    });
                    
                    animationTime += animationTimeDiff;
                }
            } else {
                CGColorRef newColor = [self trackCircleColor:trackCircle];
                CGColorRef oldColor = trackCircle.fillColor;
                
                if (!CGColorEqualToColor(newColor, trackCircle.fillColor)) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(animationTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        trackCircle.fillColor = newColor;
                        
                        CABasicAnimation *basicTrackCircleAnimation = [CABasicAnimation animationWithKeyPath:kTrackAnimation];
                        basicTrackCircleAnimation.duration = [CATransaction animationDuration] * circleAnimation;
                        basicTrackCircleAnimation.fromValue = (__bridge id _Nullable)(oldColor);
                        [trackCircle addAnimation:basicTrackCircleAnimation forKey:kTrackAnimation];
                    });
                    
                    animationTime += animationTimeDiff;
                }
            }
        } else {
            if (trackCircleImage) {
                trackCircle.contents = (__bridge id _Nullable)(trackCircleImage);
            } else {
                trackCircle.fillColor = [self trackCircleColor:trackCircle];
            }
        }
        
    }
    
    if (!animated) {
        [CATransaction commit];
    }
    
    [_sliderCircleLayer removeFromSuperlayer];
    [self.layer addSublayer:_sliderCircleLayer];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    [self layoutLayersAnimated:animateLayouts];
    animateLayouts = NO;
}

#pragma mark - Helpers

- (NSMutableArray *)clearExcessLayers:(NSMutableArray *)layers
{
    if (layers.count > self.maxCount) {
        
        for (NSUInteger i = self.maxCount; i < layers.count; i++) {
            [layers[i] removeFromSuperlayer];
        }
        
        return [[layers subarrayWithRange:NSMakeRange(0, self.maxCount)] mutableCopy];
    }
    
    return layers;
}

- (CGFloat)labelHeightWithMaxWidth:(CGFloat)maxWidth
{
    if (self.labels.count) {
        CGFloat labelHeight = 0.f;
        
        for (NSUInteger i = 0; i < self.labels.count; i++) {
            CGSize size;
            if (self.adjustLabel && (i == 0 || i == self.labels.count - 1)) {
                size = CGSizeMake([self roundForTextDrawing:maxWidth / 2.f + maxRadius], CGFLOAT_MAX);
            } else {
                size = CGSizeMake([self roundForTextDrawing:maxWidth], CGFLOAT_MAX);
            }
            
            CGFloat height = [self.labels[i] boundingRectWithSize:size
                                                          options:NSStringDrawingUsesLineFragmentOrigin
                                                       attributes:@{NSFontAttributeName : self.labelFont}
                                                          context:nil].size.height;
            labelHeight = fmax(ceil(height), labelHeight);
        }
        return labelHeight;
    }
    
    return 0;
}

/*
 Calculate distance from trackCircle center to point where circle cross track line.
 */
- (void)updateDiff
{
    diff = sqrtf(fmaxf(0.f, powf(self.trackCircleRadius, 2.f) - pow(self.trackHeight / 2.f, 2.f)));
}

- (void)updateMaxRadius
{
    maxRadius = fmaxf(self.trackCircleRadius, self.sliderCircleRadius);
}

- (void)updateIndex
{
    NSAssert(self.maxCount > 1, @"Elements count must be greater than 1!");
    if (_index > (self.maxCount - 1)) {
        _index = self.maxCount - 1;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

- (CGPathRef)fillingPath
{
    CGRect fillRect = CGRectMake(0.0f, _trackLayer.bounds.size.height - self.trackHeight,
                                 self.sliderPosition, self.trackHeight);
    return [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:self.trackHeight * 0.5f].CGPath;
}

- (CGFloat)sliderPosition
{
    return _sliderCircleLayer.position.x - maxRadius;
}

- (CGFloat)trackCirclePosition:(CAShapeLayer *)trackCircle
{
    return trackCircle.position.x - maxRadius;
}

- (CGFloat)indexCalculate
{
    return self.sliderPosition / (_trackLayer.bounds.size.width / (self.maxCount - 1));
}

- (BOOL)trackCircleIsSeleceted:(CAShapeLayer *)trackCircle
{
    return self.sliderPosition + diff >= [self trackCirclePosition:trackCircle];
}

- (NSArray *)trackTintColors
{
    if (_trackTintStartColor != nil && _trackTintEndColor != nil) {
        return @[(id)_trackTintStartColor.CGColor, (id)_trackTintEndColor.CGColor];
    } else if (_trackTintStartColor != nil) {
        return @[(id)_trackTintStartColor.CGColor];
    } else if (_trackTintEndColor != nil) {
        return @[(id)_trackTintEndColor.CGColor];
    }
    return @[];
}


#pragma mark - Track circle

- (CGColorRef)trackCircleColor:(CAShapeLayer *)trackCircle
{
    return [self trackCircleIsSeleceted:trackCircle] ? self.tintColor.CGColor : self.trackColor.CGColor;
}

- (CGImageRef)trackCircleImage:(CAShapeLayer *)trackCircle
{
    return [self trackCircleImageForState:[self trackCircleIsSeleceted:trackCircle] ? UIControlStateSelected : UIControlStateNormal].CGImage;
}

- (void)setTrackCircleImage:(UIImage *)image forState:(UIControlState)state
{
    _trackCircleImages[@(state)] = image;
    [self setNeedsLayout];
}

- (UIImage *)trackCircleImageForState:(UIControlState)state
{
    return _trackCircleImages[@(state)] ? : _trackCircleImages[@(UIControlStateNormal)];
}

#pragma mark - Touches

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    startTouchPosition = [touch locationInView:self];
    startSliderPosition = _sliderCircleLayer.position;
    
    if (self.enableHapticFeedback && ![[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
        _selectFeedback = [[UIImpactFeedbackGenerator alloc] init];
    }
    
    [_selectFeedback prepare];
    if (CGRectContainsPoint(_sliderCircleLayer.frame, startTouchPosition)) {
        return YES;
    } else {
        if (self.isDotsInteractionEnabled) {
            for (NSUInteger i = 0; i < _trackCirclesArray.count; i++) {
                CALayer *dot = _trackCirclesArray[i];
                
                CGFloat dotRadiusDiff = 22 - self.trackCircleRadius;
                CGRect frameToCheck = dotRadiusDiff > 0 ? CGRectInset(dot.frame, -dotRadiusDiff, -dotRadiusDiff) : dot.frame;
                
                if (CGRectContainsPoint(frameToCheck, startTouchPosition)) {
                    NSUInteger oldIndex = _index;
                    
                    _index = i;
                    
                    if (oldIndex != _index) {
                        [self sendActionsForControlEvents:UIControlEventValueChanged];
                        [_selectFeedback impactOccurred];
                        [_selectFeedback prepare];
                    }
                    animateLayouts = YES;
                    [self setNeedsLayout];
                    return NO;
                }
            }
            for (NSUInteger i = 0; i < _trackLabelsArray.count; i++) {
                CATextLayer *textLayer = _trackLabelsArray[i];
                CGRect frameToCheck = CGRectInset(textLayer.frame, -10.0, -10.0);
                
                if (CGRectContainsPoint(frameToCheck, startTouchPosition)) {
                    NSUInteger oldIndex = _index;
                    
                    _index = i;
                    
                    if (oldIndex != _index) {
                        [self sendActionsForControlEvents:UIControlEventValueChanged];
                        [_selectFeedback impactOccurred];
                        [_selectFeedback prepare];
                    }
                    animateLayouts = YES;
                    [self setNeedsLayout];
                    return NO;
                }
            }
            return NO;
        }
    }
    return NO;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGFloat position = startSliderPosition.x - (startTouchPosition.x - [touch locationInView:self].x);
    CGFloat limitedPosition = fminf(fmaxf(maxRadius, position), self.bounds.size.width - maxRadius);
    
    withoutCAAnimation(^{
        self->_sliderCircleLayer.position = CGPointMake(limitedPosition, self->_sliderCircleLayer.position.y);
        self->_trackMaskLayer.path = [self fillingPath];
        
        NSUInteger index = (self.sliderPosition + self->diff) / (self->_trackLayer.bounds.size.width / (self.maxCount - 1));
        if (self->_index != index) {
            for (CAShapeLayer *trackCircle in self->_trackCirclesArray) {
                CGImageRef trackCircleImage = [self trackCircleImage:trackCircle];
                
                if (trackCircleImage) {
                    trackCircle.contents = (__bridge id _Nullable)(trackCircleImage);
                } else {
                    trackCircle.fillColor = [self trackCircleColor:trackCircle];
                }
            }
            self->_index = index;
            [self sendActionsForControlEvents:UIControlEventValueChanged];
            [self->_selectFeedback impactOccurred];
            [self->_selectFeedback prepare];
        }
    });
    
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    [self endTouches];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event
{
    [self endTouches];
}

- (void)endTouches
{
    NSUInteger newIndex = roundf([self indexCalculate]);
    
    if (newIndex != _index) {
        _index = newIndex;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    
    animateLayouts = YES;
    [self setNeedsLayout];
    _selectFeedback = nil;
}

#pragma mark - Texts

- (CATextLayer *)textLayerWithSize:(CGSize)size index:(NSUInteger)index
{
    if (index >= _trackLabelsArray.count) {
        CATextLayer *trackLabel = [CATextLayer layer];
        
        CGPoint anchorPoint = CGPointMake(0.5f, 0.f);
        NSString *alignmentMode = kCAAlignmentCenter;
        
        if (self.adjustLabel) {
            if (index == 0) {
                alignmentMode = kCAAlignmentLeft;
                size.width = size.width / 2.f + maxRadius;
                anchorPoint.x = maxRadius / size.width;
            } else if (index == self.labels.count - 1) {
                alignmentMode = kCAAlignmentRight;
                size.width = size.width / 2.f + maxRadius;
                anchorPoint.x = 1.f - maxRadius / size.width;
            }
        }
        
        trackLabel.alignmentMode = alignmentMode;
        trackLabel.wrapped       = YES;
        trackLabel.contentsScale = [UIScreen mainScreen].scale;
        trackLabel.anchorPoint   = anchorPoint;
        
        CFStringRef fontName = (__bridge CFStringRef)self.labelFont.fontName;
        CGFontRef fontRef    = CGFontCreateWithFontName(fontName);
        
        trackLabel.font     = fontRef;
        trackLabel.fontSize = self.labelFont.pointSize;
        CGFontRelease(fontRef);
        
        trackLabel.string = self.labels[index];
        trackLabel.bounds = CGRectMake(0.f, 0.f, size.width, size.height);

        [self.layer addSublayer:trackLabel];
        [_trackLabelsArray addObject:trackLabel];
        
        return trackLabel;
    } else {
        return _trackLabelsArray[index];
    }
}

- (void)removeLabelLayers
{
    for (CALayer *label in _trackLabelsArray) {
        [label removeFromSuperlayer];
    }
    [_trackLabelsArray removeAllObjects];
}

- (CGFloat)roundForTextDrawing:(CGFloat)value
{
    return floor(value * [UIScreen mainScreen].scale) / [UIScreen mainScreen].scale;
}

#pragma mark - Access methods

- (void)setTrackHeight:(CGFloat)trackHeight {
    _trackLayer.trackHeight = trackHeight;
    
    [self updateDiff];
}

- (CGFloat)trackHeight {
    return _trackLayer.trackHeight;
}

- (void)setStepLineWidth:(CGFloat)stepLineWidth {
    _trackLayer.stepLineWidth = stepLineWidth;
}

- (CGFloat)stepLineWidth {
    return _trackLayer.stepLineWidth;
}

- (void)setStepLinesEdgePadding:(CGFloat)stepLinesEdgePadding {
    _trackLayer.stepLinesEdgePadding = stepLinesEdgePadding;
}

- (CGFloat)stepLinesEdgePadding {
    return _trackLayer.stepLinesEdgePadding;
}

- (void)setIndex:(NSUInteger)index animated:(BOOL)animated
{
    animateLayouts = animated;
    self.index = index;
}

- (void) setTrackColor:(UIColor *)trackColor {
    _trackLayer.trackColor = trackColor;
}

- (UIColor *) trackColor {
    return _trackLayer.trackColor;
}

- (void)setTintColor:(UIColor *)tintColor
{
    [super setTintColor:tintColor];
    [self setNeedsLayout];
}

- (void)setLabels:(NSArray<NSString *> *)labels
{
    NSAssert(labels.count != 1, @"Labels count can not be equal to 1!");
    if (_labels != labels) {
        _labels = labels;
        
        if (_labels.count > 0) {
            _maxCount = _labels.count;
        }
        _trackLayer.numberOfSteps = labels.count;
        
        [self updateIndex];
        [self removeLabelLayers];
        [self setNeedsLayout];
    }
}

- (void)setMaxCount:(NSUInteger)maxCount
{
    if (_maxCount != maxCount && !self.labels.count) {
        _maxCount = maxCount;
        [self updateIndex];
        [self setNeedsLayout];
    }
}

GENERATE_SETTER(index, NSUInteger, setIndex, [self updateIndex]; [self sendActionsForControlEvents:UIControlEventValueChanged];);

GENERATE_SETTER(trackCircleRadius, CGFloat, setTrackCircleRadius, [self updateDiff]; [self updateMaxRadius];);
GENERATE_SETTER(trackTintStartColor, UIColor*, setTrackTintStartColor, );
GENERATE_SETTER(trackTintEndColor, UIColor*, setTrackTintEndColor, );

GENERATE_SETTER(sliderCircleRadius, CGFloat, setSliderCircleRadius, [self updateMaxRadius];);
GENERATE_SETTER(sliderCircleColor, UIColor*, setSliderCircleColor, );
GENERATE_SETTER(sliderCircleImage, UIImage*, setSliderCircleImage, );

GENERATE_SETTER(labelFont, UIFont*, setLabelFont, [self removeLabelLayers];);
GENERATE_SETTER(labelColor, UIColor*, setLabelColor, );
GENERATE_SETTER(labelOffset, CGFloat, setLabelOffset, );
GENERATE_SETTER(labelOrientation, StepSliderTextOrientation, setLabelOrientation, );
GENERATE_SETTER(adjustLabel, BOOL, setAdjustLabel, );

@end
