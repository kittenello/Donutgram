#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

ANIMATION_IMPLEMENTATION

@interface TestDelegate : NSObject <CAAnimationDelegate>
@end
@implementation TestDelegate
@end

int main(void) {
    @autoreleasepool {
        CABasicAnimation *source = [CABasicAnimation animationWithKeyPath:@"opacity"];
        source.fromValue = @0;
        source.toValue = @1;
        source.duration = 2;
        source.beginTime = 100;
        source.repeatCount = HUGE_VALF;
        source.repeatDuration = 100;
        source.autoreverses = true;
        source.speed = 0;
        source.timeOffset = 1;
        source.removedOnCompletion = false;
        source.fillMode = kCAFillModeForwards;
        TestDelegate *delegate = [[TestDelegate alloc] init];
        source.delegate = delegate;
        CABasicAnimation *result = (CABasicAnimation *)animationForEnhancedPowerSaving(source);
        NSCAssert(result.duration == 0 && result.beginTime == 0 && result.timeOffset == 0, @"transition did not settle immediately");
        NSCAssert(result.repeatCount == 0 && result.repeatDuration == 0 && !result.autoreverses && result.speed == 1, @"repeating animation was not stopped");
        NSCAssert(result.delegate == delegate && [result.toValue isEqual:@1], @"completion or resting value was lost");
        NSCAssert(!result.removedOnCompletion && [result.fillMode isEqual:kCAFillModeForwards], @"persistent final state was lost");
        NSCAssert(source.duration == 2 && source.repeatCount == HUGE_VALF, @"source animation was mutated");
        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[source];
        group.duration = 5;
        CAAnimationGroup *resolved = (CAAnimationGroup *)animationForEnhancedPowerSaving(group);
        NSCAssert(resolved.duration == 0 && resolved.animations.firstObject.duration == 0, @"group still animates");
        NSLog(@"Animation timing, groups, completion delegates and final values passed.");
    }
    return 0;
}
