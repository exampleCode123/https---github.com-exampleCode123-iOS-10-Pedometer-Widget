//
//  ViewController.m
//  LineChart
//

#import <HealthKit/HealthKit.h>
#import "MainViewController.h"
#import "WDLineChartView.h"
#import "AppDelegate.h"
#import "UIViewController_NavigationBar.h"

@interface MainViewController () <WDLineChartViewDataSource, WDLineChartViewDelegate> {
    NSArray *_elementValues;
    NSArray *_elementLables;
    NSArray *_elementDistances;
    NSArray *_elementFlights;
    NSUInteger _numberCount;
    NSUInteger _lastSelected;
    NSDateFormatter *_formatter;
    NSString *_unit;
    NSUserDefaults *_shared;
    BOOL _errorOccurred;
    BOOL _firstTimeLoaded;
    BOOL _currentMax;
}

@property (weak, nonatomic) IBOutlet WDLineChartView *lineChartView;
@property (weak, nonatomic) IBOutlet UILabel *label;
@property (weak, nonatomic) IBOutlet UISwitch *unitSwitch;
@property (weak, nonatomic) IBOutlet UILabel *kmLabel;
@property (weak, nonatomic) IBOutlet UILabel *miLabel;
@property (weak, nonatomic) IBOutlet UILabel *statLabel;
@property (nonatomic, strong) HKHealthStore *healthStore;

@end

@implementation MainViewController

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _errorOccurred = NO;
        _firstTimeLoaded = YES;
        _numberCount = 7;
        _lastSelected = _numberCount - 1;
        _currentMax = 0;
        _shared = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.example.steps"];
        _formatter = [[NSDateFormatter alloc] init];
        [_formatter setDateFormat:@"M/d"];
        self.healthStore = [[HKHealthStore alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Steps";
    [self.unitSwitch addTarget:self action:@selector(unitSwitched:) forControlEvents:UIControlEventValueChanged];
    [self.lineChartView setDataSource:self];
    [self.lineChartView setDelegate:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)checkUnitState {
    NSString *unit = [_shared stringForKey:@"unit"];
    if (unit != nil) {
        _unit = unit;
        if ([_unit isEqualToString:@"km"]) {
            self.unitSwitch.on = YES;
            self.kmLabel.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1];
            self.miLabel.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1];
        } else {
            self.unitSwitch.on = NO;
            self.miLabel.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1];
            self.kmLabel.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1];
        }
    } else {
        _unit = @"km";
        [_shared setObject:_unit forKey:@"unit"];
        [_shared synchronize];
    }
}

- (BOOL)hasCustomNavigationBar {
    return YES;
}

- (void)reload {
    if (!_firstTimeLoaded) {
        [self.lineChartView setAnimated:NO];
    }
    _firstTimeLoaded = NO;
    [self checkUnitState];
    [self readHealthKitData];
}

- (void)unitSwitched:(id)sender {
    if ([sender isOn]) {
        self.kmLabel.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1];
        self.miLabel.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1];
        _unit = @"km";
    } else {
        self.miLabel.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.4 alpha:1];
        self.kmLabel.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1];
        _unit = @"mi";
    }
    [_shared setObject:_unit forKey:@"unit"];
    [_shared synchronize];
    [self readHealthKitData];
    [(AppDelegate*)[[UIApplication sharedApplication] delegate] createShortcutItems];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - HealthKit methods
- (void)queryHealthData
{
    NSMutableArray *arrayForValues = [NSMutableArray arrayWithCapacity:_numberCount];
    NSMutableArray *arrayForLabels = [NSMutableArray arrayWithCapacity:_numberCount];
    NSMutableArray *arrayForDistances = [NSMutableArray arrayWithCapacity:_numberCount];
    NSMutableArray *arrayForFlights = [NSMutableArray arrayWithCapacity:_numberCount];
    for (NSUInteger i = 0; i < _numberCount; i++) {
        [arrayForValues addObject:@(0)];
        [arrayForLabels addObject:@""];
        [arrayForDistances addObject:@(0)];
        [arrayForFlights addObject:@(0)];
    }
    _elementValues = (NSArray*)arrayForValues;
    
    dispatch_group_t hkGroup = dispatch_group_create();
    
    HKQuantityType *stepType =[HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierStepCount];
    HKQuantityType *distanceType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierDistanceWalkingRunning];
    HKQuantityType *flightsType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierFlightsClimbed];
    
    NSDate *day = [NSDate date];
    NSCalendar *calendar = [NSCalendar autoupdatingCurrentCalendar];
    
    for (NSUInteger i = 0; i < _numberCount; i++) {
        [arrayForLabels setObject:[_formatter stringFromDate:day] atIndexedSubscript:_numberCount - 1 - i];
        
        NSDateComponents *components = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:day];
        components.hour = components.minute = components.second = 0;
        NSDate *beginDate = [calendar dateFromComponents:components];
        NSDate *endDate = day;
        if (i != 0) {
            components.hour = 24;
            components.minute = components.second = 0;
            endDate = [calendar dateFromComponents:components];
        }
        NSPredicate *predicate = [HKQuery predicateForSamplesWithStartDate:beginDate endDate:endDate options:HKQueryOptionStrictStartDate];
        
        HKStatisticsQuery *squery = [[HKStatisticsQuery alloc]
                                     initWithQuantityType:stepType
                                     quantitySamplePredicate:predicate
                                     options:HKStatisticsOptionCumulativeSum
                                     completionHandler:^(HKStatisticsQuery *query, HKStatistics *result, NSError *error) {
                if (error != nil) _errorOccurred = YES;
                HKQuantity *quantity = result.sumQuantity;
                double step = [quantity doubleValueForUnit:[HKUnit countUnit]];
                [arrayForValues setObject:[NSNumber numberWithDouble:step] atIndexedSubscript:_numberCount - 1 - i];
                if (step > _currentMax) _currentMax = step;
                dispatch_group_leave(hkGroup);
        }];
        HKStatisticsQuery *fquery = [[HKStatisticsQuery alloc]
                                     initWithQuantityType:flightsType
                                     quantitySamplePredicate:predicate
                                     options:HKStatisticsOptionCumulativeSum
                                     completionHandler:^(HKStatisticsQuery *query, HKStatistics *result, NSError *error) {
                if (error != nil) _errorOccurred = YES;
                HKQuantity *quantity = result.sumQuantity;
                double flight = [quantity doubleValueForUnit:[HKUnit countUnit]];
                [arrayForFlights setObject:[NSNumber numberWithDouble:flight] atIndexedSubscript:_numberCount - 1 - i];
                dispatch_group_leave(hkGroup);
        }];
        HKStatisticsQuery *dquery = [[HKStatisticsQuery alloc]
                                     initWithQuantityType:distanceType
                                     quantitySamplePredicate:predicate
                                     options:HKStatisticsOptionCumulativeSum
                                     completionHandler:^(HKStatisticsQuery *query, HKStatistics *result, NSError *error) {
                if (error != nil) _errorOccurred = YES;
                HKQuantity *quantity = result.sumQuantity;
                double distance = [quantity doubleValueForUnit:[HKUnit unitFromString:_unit]];
                [arrayForDistances setObject:[NSNumber numberWithDouble:distance] atIndexedSubscript:_numberCount - 1 - i];
                dispatch_group_leave(hkGroup);
        }];
        dispatch_group_enter(hkGroup);
        [self.healthStore executeQuery:squery];
        dispatch_group_enter(hkGroup);
        [self.healthStore executeQuery:fquery];
        dispatch_group_enter(hkGroup);
        [self.healthStore executeQuery:dquery];
        
        day = [day dateByAddingTimeInterval: -3600 * 24];
    }
    dispatch_group_notify(hkGroup, dispatch_get_main_queue(),^{
        if (!_errorOccurred && _currentMax > 0) {
            _elementValues = (NSArray*)arrayForValues;
            _elementDistances = (NSArray*)arrayForDistances;
            _elementFlights = (NSArray*)arrayForFlights;
            _elementLables = (NSArray*)arrayForLabels;
            [self.lineChartView loadDataWithSelectedKept];
            [self changeTextWithNodeAtIndex:_lastSelected];
            self.statLabel.text = [NSString stringWithFormat:@"Daily Average: %.0f steps, Total: %.0f steps", [self averageValue], [self totalValue]];
        } else if (!_errorOccurred && _currentMax <= 0) {
            self.label.text = @"No data";
        } else {
            self.label.text = @"Some error occured";
        }
    });
}

- (void)readHealthKitData
{
    if ([HKHealthStore isHealthDataAvailable]) {
        HKQuantityType *stepType =[HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierStepCount];
        HKQuantityType *distanceType = [HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierDistanceWalkingRunning];
        HKQuantityType *flightsType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierFlightsClimbed];
        [self.healthStore requestAuthorizationToShareTypes:nil readTypes:[NSSet setWithObjects:stepType, distanceType, flightsType, nil] completion:^(BOOL success, NSError *error) {
            if (success) {
                [self queryHealthData];
            } else {
                self.label.text = @"Health Data Permission Denied";
            }
        }];
    } else {
        self.label.text = @"Health Data Not Available";
    }
}

#pragma mark - LineChartViewDataSource methods

- (NSUInteger)numberOfElements {
    return _numberCount;
}

- (CGFloat)maxValue {
    return [[_elementValues valueForKeyPath:@"@max.self"] doubleValue];
}

- (CGFloat)minValue {
    return [[_elementValues valueForKeyPath:@"@min.self"] doubleValue];
}

- (CGFloat)averageValue {
    return [[_elementValues valueForKeyPath:@"@avg.self"] doubleValue];
}

- (CGFloat)totalValue {
    return [[_elementValues valueForKeyPath:@"@sum.self"] doubleValue];
}

- (CGFloat)valueForElementAtIndex:(NSUInteger)index {
    return [(NSNumber*)_elementValues[index] floatValue];
}

- (NSString*)labelForElementAtIndex:(NSUInteger)index {
    return (NSString*)_elementLables[index];
}

#pragma mark - LineChartViewDelegate methods

- (void)clickedNodeAtIndex:(NSUInteger)index {
    [self changeTextWithNodeAtIndex:index];
    _lastSelected = index;
}

- (void)changeTextWithNodeAtIndex:(NSUInteger)index {
    NSString *result = [NSString stringWithFormat:@"\uF3BB  %.0f   \uE801  %.2f %@   \uF148  %.0f F", [(NSNumber*)_elementValues[index] floatValue], [(NSNumber*)_elementDistances[index] floatValue], _unit, [(NSNumber*)_elementFlights[index] floatValue]];
    self.label.text = result;
}

@end
