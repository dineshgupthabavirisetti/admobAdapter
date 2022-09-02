//
//  GADMAdapterInMobiBannerAd.m
//  IMAdMobAdapter
//
//  Created by Bavirisetti.Dinesh on 01/09/22.
//

#import "GADMAdapterInMobiBannerAd.h"
#import <InMobiSDK/IMSdk.h>
#include <stdatomic.h>
#import "GADInMobiExtras.h"
#import "GADMAdapterInMobiConstants.h"
#import "GADMAdapterInMobiInitializer.h"
#import "GADMAdapterInMobiUtils.h"
#import "GADMInMobiConsent.h"
#import "GADMediationAdapterInMobi.h"

/// Find closest supported ad size from a given ad size.
static CGSize GADMAdapterInMobiSupportedAdSizeFromGADAdSize(GADAdSize gadAdSize) {
  // Supported sizes
  // 320 x 50
  // 300 x 250
  // 728 x 90

  NSArray<NSValue *> *potentialSizeValues =
      @[ @(GADAdSizeBanner), @(GADAdSizeMediumRectangle), @(GADAdSizeLeaderboard) ];

  GADAdSize closestSize = GADClosestValidSizeForAdSizes(gadAdSize, potentialSizeValues);
  return CGSizeFromGADAdSize(closestSize);
}

@implementation GADMAdapterInMobiBannerAd {
    
    id<GADMediationBannerAdEventDelegate> _bannerAdEventDelegate;
    
    /// Ad Configuration for the banner ad to be rendered.
    GADMediationBannerAdConfiguration *_bannerAdConfig;
    
    GADMediationBannerLoadCompletionHandler _bannerRenderCompletionHandler;
    
    /// InMobi banner ad object.
    IMBanner *_adView;
    
    /// InMobi Placement identifier.
    NSNumber *_placementIdentifier;
}

-(instancetype)initWithPlacementIdentifier:(NSNumber *)placementIdentifier {
    self = [super init];
    if (self) {
      _placementIdentifier = placementIdentifier;
    }
    return self;
}

- (void)loadBannerForAdConfiguration:(nonnull GADMediationBannerAdConfiguration *)adConfiguration
                   completionHandler:(nonnull GADMediationBannerLoadCompletionHandler)completionHandler {
    _bannerAdConfig = adConfiguration;
    __block atomic_flag completionHandlerCalled = ATOMIC_FLAG_INIT;
    
    __block GADMediationBannerLoadCompletionHandler originalCompletionHandler =
    [completionHandler copy];
    _bannerRenderCompletionHandler =
    ^id<GADMediationBannerAdEventDelegate>(id<GADMediationBannerAd> bannerAd, NSError *error) {
        if (atomic_flag_test_and_set(&completionHandlerCalled)) {
            return nil;
        }
        id<GADMediationBannerAdEventDelegate> delegate = nil;
        if (originalCompletionHandler) {
            delegate = originalCompletionHandler(bannerAd, error);
        }
        originalCompletionHandler = nil;
        return delegate;
    };
    
    
    GADMAdapterInMobiBannerAd *__weak weakSelf = self;
    NSString *accountID = _bannerAdConfig.credentials.settings[GADMAdapterInMobiAccountID];
    [GADMAdapterInMobiInitializer.sharedInstance
     initializeWithAccountID:accountID
     completionHandler:^(NSError *_Nullable error) {
        GADMAdapterInMobiBannerAd *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        if (error) {
            NSLog(@"[InMobi] Initialization failed: %@", error.localizedDescription);
            strongSelf->_bannerRenderCompletionHandler(nil, error);
            return;
        }
        
        [strongSelf requestBannerWithSize:strongSelf->_bannerAdConfig.adSize];
    }];
}

- (void)getBannerWithSize:(GADAdSize)adSize {
    NSString *accountID = _bannerAdConfig.credentials.settings[GADMAdapterInMobiAccountID];
    
    GADMAdapterInMobiBannerAd *__weak weakSelf = self;
    [GADMAdapterInMobiInitializer.sharedInstance
     initializeWithAccountID:accountID
     completionHandler:^(NSError *_Nullable error) {
        GADMAdapterInMobiBannerAd *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        if (error) {
            NSLog(@"[InMobi] Initialization failed: %@", error.localizedDescription);
            strongSelf->_bannerRenderCompletionHandler(nil, error);
            return;
        }
        
        [strongSelf requestBannerWithSize:adSize];
    }];
}

- (void)requestBannerWithSize:(GADAdSize)adSize {
    id<GADMediationBannerAdEventDelegate> strongDelegate = _bannerAdEventDelegate;
    
    if (!strongDelegate) {
        return;
    }
    
    long long placementId =
    [_bannerAdConfig.credentials.settings[GADMAdapterInMobiPlacementID] longLongValue];
    
    if (placementId == 0) {
        NSError *error = GADMAdapterInMobiErrorWithCodeAndDescription(
                                                                      GADMAdapterInMobiErrorInvalidServerParameters,
                                                                      @"[InMobi] Error - Placement ID not specified.");
        _bannerRenderCompletionHandler(nil, error);
        return;
    }
    
    if (_bannerAdConfig.isTestRequest) {
        NSLog(@"[InMobi] Please enter your device ID in the InMobi console to recieve test ads from "
              @"Inmobi");
    }
    
    CGSize size = GADMAdapterInMobiSupportedAdSizeFromGADAdSize(adSize);
    if (CGSizeEqualToSize(size, CGSizeZero)) {
        NSString *description =
        [NSString stringWithFormat:@"Invalid size for InMobi mediation adapter. Size: %@",
         NSStringFromGADAdSize(adSize)];
        NSError *error = GADMAdapterInMobiErrorWithCodeAndDescription(
                                                                      GADMAdapterInMobiErrorBannerSizeMismatch, description);
        _bannerRenderCompletionHandler(nil, error);
        return;
    }
    
    _adView = [[IMBanner alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)
                                  placementId:placementId];
    
    // Let Mediation do the refresh.
    [_adView shouldAutoRefresh:NO];
    _adView.transitionAnimation = UIViewAnimationTransitionNone;
    
    GADInMobiExtras *extras = _bannerAdConfig.extras;
    if (extras && extras.keywords) {
        [_adView setKeywords:extras.keywords];
    }
    
    GADMAdapterInMobiSetTargetingFromAdConfiguration(_bannerAdConfig);
    NSDictionary<NSString *, id> *requestParameters =
    GADMAdapterInMobiCreateRequestParametersFromAdConfiguration(_bannerAdConfig);
    [_adView setExtras:requestParameters];
    
    _adView.delegate = self;
    [_adView load];
}

- (void)stopBeingDelegate {
  _adView.delegate = nil;
}

#pragma mark -
#pragma mark IMBannerDelegate methods

- (void)bannerDidFinishLoading:(nonnull IMBanner *)banner {
  NSLog(@"<<<<<ad request completed>>>>>");
  [_bannerAdEventDelegate willPresentFullScreenView];
}

- (void)banner:(nonnull IMBanner *)banner didFailToLoadWithError:(nonnull IMRequestStatus *)error {
    _bannerRenderCompletionHandler(nil, error);
}

- (void)banner:(nonnull IMBanner *)banner didInteractWithParams:(nonnull NSDictionary *)params {
  NSLog(@"<<<< bannerDidInteract >>>>");
    [_bannerAdEventDelegate reportClick];
}

- (void)userWillLeaveApplicationFromBanner:(nonnull IMBanner *)banner {
  NSLog(@"<<<< bannerWillLeaveApplication >>>>");
  [_bannerAdEventDelegate willBackgroundApplication];
}

- (void)bannerWillPresentScreen:(nonnull IMBanner *)banner {
  NSLog(@"<<<< bannerWillPresentScreen >>>>");
  [_bannerAdEventDelegate willPresentFullScreenView];
}

- (void)bannerDidPresentScreen:(nonnull IMBanner *)banner {
  NSLog(@"InMobi banner did present screen");
}

- (void)bannerWillDismissScreen:(nonnull IMBanner *)banner {
  NSLog(@"<<<< bannerWillDismissScreen >>>>");
  [_bannerAdEventDelegate willDismissFullScreenView];
}

- (void)bannerDidDismissScreen:(nonnull IMBanner *)banner {
  NSLog(@"<<<< bannerDidDismissScreen >>>>");
  [_bannerAdEventDelegate didDismissFullScreenView];
}

- (void)banner:(nonnull IMBanner *)banner
    rewardActionCompletedWithRewards:(nonnull NSDictionary *)rewards {
  NSLog(@"InMobi banner reward action completed with rewards: %@", rewards.description);
}

-(void)bannerAdImpressed:(IMBanner *)banner {
  [_bannerAdEventDelegate reportImpression];
}

- (nonnull UIView *)view {
  return _adView;
}

@end
