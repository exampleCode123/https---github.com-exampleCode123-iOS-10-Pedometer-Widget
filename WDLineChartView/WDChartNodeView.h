//
//  ChartNodeView.h
//  LineChart
//

#import <UIKit/UIKit.h>

@interface WDChartNodeView : UIView

@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, assign) BOOL isActive;

- (void)toggleState;
@end
