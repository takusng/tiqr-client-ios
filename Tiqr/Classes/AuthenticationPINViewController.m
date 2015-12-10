/*
 * Copyright (c) 2010-2011 SURFnet bv
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of SURFnet bv nor the names of its contributors 
 *    may be used to endorse or promote products derived from this 
 *    software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
 * GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
 * IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
 * IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "AuthenticationPINViewController.h"
#import "AuthenticationSummaryViewController.h"
#import "AuthenticationFallbackViewController.h"
#import "OCRAWrapper.h"
#import "OCRAWrapper_v1.h"
#import "MBProgressHUD.h"
#import "ErrorViewController.h"
#import "OCRAProtocol.h"
#import "ServiceContainer.h"

@interface AuthenticationPINViewController ()

@property (nonatomic, strong) AuthenticationChallenge *challenge;
@property (nonatomic, copy) NSString *response;
@property (nonatomic, copy) NSString *PIN;

@end

@implementation AuthenticationPINViewController

- (instancetype)initWithAuthenticationChallenge:(AuthenticationChallenge *)challenge {
    self = [super init];
    if (self != nil) {
        self.challenge = challenge;
        self.delegate = self;
    }
	
	return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    self.subtitle = NSLocalizedString(@"login_intro", @"Authentication PIN title");
    self.pinDescription = NSLocalizedString(@"enter_four_digit_pin", @"You need to enter your 4-digit PIN to login.");
}

- (void)showFallback {
    AuthenticationFallbackViewController *viewController = [[AuthenticationFallbackViewController alloc] initWithAuthenticationChallenge:self.challenge response:self.response];
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)authenticationConfirmationRequestDidFinish:(AuthenticationConfirmationRequest *)request {
    [ServiceContainer.sharedInstance.identityService upgradeIdentity:self.challenge.identity withPIN:self.PIN];
    
    self.PIN = nil;

	[MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];    
    AuthenticationSummaryViewController *viewController = [[AuthenticationSummaryViewController alloc] initWithAuthenticationChallenge:self.challenge];
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)authenticationConfirmationRequest:(AuthenticationConfirmationRequest *)request didFailWithError:(NSError *)error {
    self.PIN = nil;

	[MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
    
    switch ([error code]) {
        case TIQRACRConnectionError:
            [self showFallback];
            break;
        case TIQRACRAccountBlockedErrorTemporary: {
            UIViewController *viewController = [[ErrorViewController alloc] initWithErrorTitle:[error localizedDescription] errorMessage:[error localizedFailureReason]];
            [self.navigationController pushViewController:viewController animated:YES];
            break;
        }
        case TIQRACRAccountBlockedError: {
            self.challenge.identity.blocked = @YES;
            [ServiceContainer.sharedInstance.identityService saveIdentities];
            UIViewController *viewController = [[ErrorViewController alloc] initWithErrorTitle:[error localizedDescription] errorMessage:[error localizedFailureReason]];
            [self.navigationController pushViewController:viewController animated:YES];
            break;
        }            
        case TIQRACRInvalidResponseError: {
            NSNumber *attemptsLeft = [error userInfo][TIQRACRAttemptsLeftErrorKey];
            if (attemptsLeft != nil && [attemptsLeft intValue] == 0) {
                [ServiceContainer.sharedInstance.identityService blockAllIdentities];
                [ServiceContainer.sharedInstance.identityService saveIdentities];
                UIViewController *viewController = [[ErrorViewController alloc] initWithErrorTitle:[error localizedDescription] errorMessage:[error localizedFailureReason]];
                [self.navigationController pushViewController:viewController animated:YES];
            } else {
                [self clear];
                [self showErrorWithTitle:[error localizedDescription] message:[error localizedFailureReason]];
            }
            break;
        }
        default: {
            UIViewController *viewController = [[ErrorViewController alloc] initWithErrorTitle:[error localizedDescription] errorMessage:[error localizedFailureReason]];
            [self.navigationController pushViewController:viewController animated:YES];
        }
    }
}

- (NSString *)calculateOTPResponseForPIN:(NSString *)PIN {
    NSObject<OCRAProtocol> *ocra;
    if (self.challenge.protocolVersion && [self.challenge.protocolVersion intValue] >= 2) {
        ocra = [[OCRAWrapper alloc] init];
    } else {
        ocra = [[OCRAWrapper_v1 alloc] init];
    }
    
    NSError *error = nil;
    NSData *secret = [ServiceContainer.sharedInstance.secretService secretForIdentity:self.challenge.identity withPIN:PIN];
    NSString *response = [ocra generateOCRA:self.challenge.identityProvider.ocraSuite secret:secret challenge:self.challenge.challenge sessionKey:self.challenge.sessionKey error:&error];
    if (response == nil) {
        [MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
        UIViewController *viewController = [[ErrorViewController alloc] 
                                            initWithErrorTitle:[error localizedDescription]
                                            errorMessage:[error localizedFailureReason]];
        [self.navigationController pushViewController:viewController animated:YES];
    }

    return response;
}

- (void)PINViewController:(PINViewController *)pinViewController didFinishWithPIN:(NSString *)PIN {
    self.response = [self calculateOTPResponseForPIN:PIN];
    if (self.response == nil) {
        return;
    }
    self.PIN = PIN;

	[MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];    
    AuthenticationConfirmationRequest *request = [[AuthenticationConfirmationRequest alloc] initWithAuthenticationChallenge:self.challenge response:self.response];
    request.delegate = self;
    [request send];
}


@end