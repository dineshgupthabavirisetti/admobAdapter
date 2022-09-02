//
//  GADMAdapterInMobi.m
//
//  Copyright (c) 2015 InMobi. All rights reserved.
//

#import "GADMAdapterInMobi.h"

#import <InMobiSDK/IMSdk.h>

#import "GADInMobiExtras.h"
#import "GADMAdapterInMobiConstants.h"
#import "GADMAdapterInMobiInitializer.h"
#import "GADMAdapterInMobiUnifiedNativeAd.h"
#import "GADMAdapterInMobiUtils.h"
#import "GADMInMobiConsent.h"
#import "GADMediationAdapterInMobi.h"
#import "NativeAdKeys.h"

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

@implementation GADMAdapterInMobi {
    
    id<GADMediationBannerAdEventDelegate> _bannerAdEventDelegate;
    
    id<GADMediationInterstitialAdEventDelegate> _interstitalAdEventDelegate;
    
    
    
    /// Ad Configuration for the banner ad to be rendered.
    GADMediationBannerAdConfiguration *_bannerAdConfig;
    
    /// Ad Configuration for the nterstitial ad to be rendered.
    GADMediationInterstitialAdConfiguration *_interstitialAdConfig;
    
    GADMediationBannerLoadCompletionHandler _bannerRenderCompletionHandler;
    GADMediationInterstitialLoadCompletionHandler _interstitialRenderCompletionHandler;
    
    
    /// InMobi banner ad object.
    IMBanner *_adView;
    
    /// InMobi interstitial ad object.
    IMInterstitial *_interstitial;
    
    /// Google Mobile Ads unified native ad wrapper.
    GADMAdapterInMobiUnifiedNativeAd *_nativeAd;
}

+ (nonnull Class<GADMediationAdapter>)mainAdapterClass {
  return [GADMediationAdapterInMobi class];
}

+ (nonnull NSString *)adapterVersion {
  return GADMAdapterInMobiVersion;
}

+ (nullable Class<GADAdNetworkExtras>)networkExtrasClass {
  return [GADInMobiExtras class];
}

//- (nonnull instancetype)initWithGADMAdNetworkConnector:(nonnull id)connector {
//  if (self = [super init]) {
//    _connector = connector;
//  }
//  return self;
//}

//- (void)getNativeAdWithAdTypes:(nonnull NSArray<GADAdLoaderAdType> *)adTypes
//                       options:(nullable NSArray<GADAdLoaderOptions *> *)options {
//  id<GADMAdNetworkConnector> strongConnector = _connector;
//  id<GADMAdNetworkAdapter> strongSelf = self;
//  if (!strongConnector || !strongSelf) {
//    return;
//  }
//
//  _nativeAd =
//      [[GADMAdapterInMobiUnifiedNativeAd alloc] initWithGADMAdNetworkConnector:strongConnector
//                                                                       adapter:strongSelf];
//  [_nativeAd requestNativeAdWithOptions:options];
//}

- (BOOL)handlesUserImpressions {
  return YES;
}

- (BOOL)handlesUserClicks {
  return NO;
}

- (void)getInterstitial {
    NSString *accountID = _interstitialAdConfig.credentials.settings[GADMAdapterInMobiAccountID];
  GADMAdapterInMobi *__weak weakSelf = self;
  [GADMAdapterInMobiInitializer.sharedInstance
      initializeWithAccountID:accountID
            completionHandler:^(NSError *_Nullable error) {
              GADMAdapterInMobi *strongSelf = weakSelf;
              if (!strongSelf) {
                return;
              }

              if (error) {
                NSLog(@"[InMobi] Initialization failed: %@", error.localizedDescription);
                  strongSelf->_interstitialRenderCompletionHandler(nil,error);
                return;
              }

              [strongSelf requestInterstitialAd];
            }];
}

- (void)requestInterstitialAd {
  id<GADMediationInterstitialAdEventDelegate> strongDelegate = _interstitalAdEventDelegate;
  if (!strongDelegate) {
    return;
  }

  long long placementId =
    [_interstitialAdConfig.credentials.settings[GADMAdapterInMobiPlacementID] longLongValue];
  if (placementId == 0) {
    NSError *error = GADMAdapterInMobiErrorWithCodeAndDescription(
        GADMAdapterInMobiErrorInvalidServerParameters,
        @"[InMobi] Error - Placement ID not specified.");
      _interstitialRenderCompletionHandler(nil,error);
    return;
  }

  if ([_interstitialAdConfig isTestRequest]) {
    NSLog(@"[InMobi] Please enter your device ID in the InMobi console to receive test ads from "
          @"InMobi");
  }

  _interstitial = [[IMInterstitial alloc] initWithPlacementId:placementId];

  GADInMobiExtras *extras =  _interstitialAdConfig.extras;
  if (extras && extras.keywords) {
    [_interstitial setKeywords:extras.keywords];
  }

  GADMAdapterInMobiSetTargetingFromAdConfiguration(_interstitialAdConfig);
  NSDictionary<NSString *, id> *requestParameters =
    GADMAdapterInMobiCreateRequestParametersFromAdConfiguration(_interstitialAdConfig);
  [_interstitial setExtras:requestParameters];

  _interstitial.delegate = self;
  [_interstitial load];
}

- (void)getBannerWithSize:(GADAdSize)adSize {
    NSString *accountID = _bannerAdConfig.credentials.settings[GADMAdapterInMobiAccountID];
    
  GADMAdapterInMobi *__weak weakSelf = self;
  [GADMAdapterInMobiInitializer.sharedInstance
      initializeWithAccountID:accountID
            completionHandler:^(NSError *_Nullable error) {
              GADMAdapterInMobi *strongSelf = weakSelf;
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
  _interstitial.delegate = nil;
}

- (void)presentInterstitialFromRootViewController:(nonnull UIViewController *)rootViewController {
  if ([_interstitial isReady]) {
    [_interstitial showFromViewController:rootViewController
                            withAnimation:kIMInterstitialAnimationTypeCoverVertical];
  }
}

- (BOOL)isBannerAnimationOK:(GADMBannerAnimationType)animType {
  return [_interstitial isReady];
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

#pragma mark IMAdInterstitialDelegate methods

- (void)interstitialDidFinishLoading:(nonnull IMInterstitial *)interstitial {
  NSLog(@"<<<< interstitialDidFinishRequest >>>>");
    _interstitialRenderCompletionHandler(self, nil);
}

- (void)interstitial:(nonnull IMInterstitial *)interstitial
    didFailToLoadWithError:(IMRequestStatus *)error {
    _interstitialRenderCompletionHandler(nil, error);
}

- (void)interstitialWillPresent:(nonnull IMInterstitial *)interstitial {
  NSLog(@"<<<< interstitialWillPresentScreen >>>>");
  [_interstitalAdEventDelegate willPresentFullScreenView];
}

- (void)interstitialDidPresent:(nonnull IMInterstitial *)interstitial {
  NSLog(@"<<<< interstitialDidPresent >>>>");
}

- (void)interstitial:(nonnull IMInterstitial *)interstitial
    didFailToPresentWithError:(IMRequestStatus *)error {
    _interstitialRenderCompletionHandler(nil,error);
}

- (void)interstitialWillDismiss:(nonnull IMInterstitial *)interstitial {
  NSLog(@"<<<< interstitialWillDismiss >>>>");
    [_interstitalAdEventDelegate willDismissFullScreenView];
}

- (void)interstitialDidDismiss:(nonnull IMInterstitial *)interstitial {
  NSLog(@"<<<< interstitialDidDismiss >>>>");
    [_interstitalAdEventDelegate didDismissFullScreenView];
}

- (void)interstitial:(nonnull IMInterstitial *)interstitial
    didInteractWithParams:(nonnull NSDictionary *)params {
  NSLog(@"<<<< interstitialDidInteract >>>>");
    [_interstitalAdEventDelegate reportClick];
}

- (void)userWillLeaveApplicationFromInterstitial:(nonnull IMInterstitial *)interstitial {
  NSLog(@"<<<< userWillLeaveApplicationFromInterstitial >>>>");
    [_interstitalAdEventDelegate willBackgroundApplication];
}

- (void)interstitialDidReceiveAd:(nonnull IMInterstitial *)interstitial {
  NSLog(@"InMobi AdServer returned a response.");
}

-(void)interstitialAdImpressed:(IMInterstitial *)interstitial {
    [_interstitalAdEventDelegate reportImpression];
}

@end
