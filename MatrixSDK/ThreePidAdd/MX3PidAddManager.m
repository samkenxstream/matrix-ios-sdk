/*
 Copyright 2019 The Matrix.org Foundation C.I.C

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MX3PidAddManager.h"

#import "MXSession.h"
#import "MXTools.h"

NSString *const MX3PidAddManagerErrorDomain = @"org.matrix.sdk.MX3PidAddManagerErrorDomain";

@interface MX3PidAddManager()
{
    MXSession *mxSession;

    BOOL doesServerSupportSeparateAddAndBind;
}

@end

@implementation MX3PidAddManager

- (instancetype)initWithMatrixSession:(MXSession *)session
{
    self = [super init];
    if (self)
    {
        mxSession = session;
    }
    return self;
}

- (void)cancel3PidAddSession:(MX3PidAddSession*)threePidAddSession
{
    NSLog(@"[MX3PidAddManager] cancel3PidAddSession: threePid: %@", threePidAddSession);

    [threePidAddSession.httpOperation cancel];
    threePidAddSession.httpOperation = nil;
}


#pragma mark - Add Email

- (MX3PidAddSession*)startAddEmailSessionWithEmail:(NSString*)email
                                          nextLink:(nullable NSString*)nextLink
                                           success:(void (^)(void))success
                                           failure:(void (^)(NSError * _Nonnull))failure
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumEmail andAddress:email];

    NSLog(@"[MX3PidAddManager] startAddEmailSessionWithEmail: threePid: %@", threePidAddSession);

    threePidAddSession.httpOperation = [self checkIdentityServerRequirementForAdding3PidWithSuccess:^{

        MXHTTPOperation *operation = [self->mxSession.matrixRestClient requestTokenForEmail:email isDuringRegistration:NO clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nextLink success:^(NSString *sid) {

            NSLog(@"[MX3PidAddManager] startAddEmailSessionWithEmail: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.httpOperation = nil;

            threePidAddSession.sid = sid;
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }
        
    } failure:^(NSError * _Nonnull error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];

    return threePidAddSession;
}

- (void)tryFinaliseAddEmailSession:(MX3PidAddSession*)threePidAddSession
                           success:(void (^)(void))success
                           failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] tryFinaliseAddEmailSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail]);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    if (doesServerSupportSeparateAddAndBind)
    {
        // https://gist.github.com/jryans/839a09bf0c5a70e2f36ed990d50ed928#2b-adding-a-3pid-to-hs-account-after-registration-post-msc2290
        threePidAddSession.httpOperation = [mxSession.matrixRestClient add3PIDOnlyWithSessionId:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret success:^{

            NSLog(@"[MX3PidAddManager] tryFinaliseAddEmailSession: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.httpOperation = nil;
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];
    }
    else
    {
        // https://gist.github.com/jryans/839a09bf0c5a70e2f36ed990d50ed928#2a-adding-a-3pid-to-hs-account-after-registration-pre-msc2290
        threePidAddSession.httpOperation = [mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:NO success:^{
            threePidAddSession.httpOperation = nil;

            NSLog(@"[MX3PidAddManager] tryFinaliseAddEmailSession: DONE: threePid: %@", threePidAddSession);

            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];
    }
}


#pragma mark - Add MSISDN

- (MX3PidAddSession*)startAddPhoneNumberSessionWithPhoneNumber:(NSString*)phoneNumber
                                                   countryCode:(nullable NSString*)countryCode
                                                       success:(void (^)(void))success
                                                       failure:(void (^)(NSError * _Nonnull))failure
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumMSISDN andAddress:phoneNumber];
    threePidAddSession.countryCode = countryCode;

    NSLog(@"[MX3PidAddManager] startAddPhoneNumberSessionWithPhoneNumber: threePid: %@", threePidAddSession);

    threePidAddSession.httpOperation = [self checkIdentityServerRequirementForAdding3PidWithSuccess:^{

        MXHTTPOperation *operation = [self->mxSession.matrixRestClient requestTokenForPhoneNumber:phoneNumber isDuringRegistration:NO countryCode:countryCode clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString *sid, NSString *msisdn) {

            NSLog(@"[MX3PidAddManager] startAddPhoneNumberSessionWithPhoneNumber: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.httpOperation = nil;

            threePidAddSession.sid = sid;
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError * _Nonnull error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];

    return threePidAddSession;
}

- (void)finaliseAddPhoneNumberSession:(MX3PidAddSession*)threePidAddSession
                            withToken:(NSString*)token
                              success:(void (^)(void))success
                              failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] finaliseAddPhoneNumberSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumMSISDN]);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    MXWeakify(self);
    threePidAddSession.httpOperation = [self submitValidationToken:token for3PidAddSession:threePidAddSession success:^{
        MXStrongifyAndReturnIfNil(self);

        MXHTTPOperation *operation;
        if (self->doesServerSupportSeparateAddAndBind)
        {
            // https://gist.github.com/jryans/839a09bf0c5a70e2f36ed990d50ed928#2b-adding-a-3pid-to-hs-account-after-registration-post-msc2290
            operation = [self->mxSession.matrixRestClient add3PIDOnlyWithSessionId:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret success:^{

                NSLog(@"[MX3PidAddManager] finaliseAddPhoneNumberSession: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.httpOperation = nil;
                success();

            } failure:^(NSError *error) {
                threePidAddSession.httpOperation = nil;
                failure(error);
            }];
        }
        else
        {
            // https://gist.github.com/jryans/839a09bf0c5a70e2f36ed990d50ed928#2a-adding-a-3pid-to-hs-account-after-registration-pre-msc2290
            operation = [self->mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:NO success:^{

                NSLog(@"[MX3PidAddManager] finaliseAddPhoneNumberSession: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.httpOperation = nil;
                success();

            } failure:^(NSError *error) {
                threePidAddSession.httpOperation = nil;
                failure(error);
            }];
        }

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError *error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];
}


#pragma mark - Bind Email

- (MX3PidAddSession*)startIdentityServerEmailSessionWithEmail:(NSString*)email
                                                         bind:(BOOL)bind
                                                      success:(void (^)(BOOL needValidation))success
                                                      failure:(void (^)(NSError * _Nonnull))failure
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumEmail andAddress:email];
    threePidAddSession.bind = bind;

    NSLog(@"[MX3PidAddManager] startIdentityServerEmailSessionWithEmail (bind:%@) : threePid: %@", @(bind), threePidAddSession);

    [self startIdentityServer3PidSession:threePidAddSession success:success failure:failure];

    return threePidAddSession;
}

- (void)tryFinaliseIdentityServerEmailSession:(MX3PidAddSession*)threePidAddSession
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] tryFinaliseIdentityServerEmailSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail]);

    if (doesServerSupportSeparateAddAndBind)
    {
        [self tryFinaliseIdentityServer3PidSessionWithNewHomeserver:threePidAddSession withToken:nil success:success failure:failure];
    }
    else
    {
        [self tryFinaliseIdentityServer3PidSessionWithOldHomeserver:threePidAddSession withToken:nil success:success failure:failure];
    }
}


#pragma mark - Bind Phone Number

- (MX3PidAddSession*)startIdentityServerPhoneNumberSessionWithPhoneNumber:(NSString*)phoneNumber
                                                              countryCode:(nullable NSString*)countryCode
                                                                     bind:(BOOL)bind
                                                                  success:(void (^)(BOOL needValidation))success
                                                                  failure:(void (^)(NSError * _Nonnull))failure
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumMSISDN andAddress:phoneNumber];
    threePidAddSession.countryCode = countryCode;
    threePidAddSession.bind = bind;

    NSLog(@"[MX3PidAddManager] startIdentityServerPhoneNumberSessionWithPhoneNumber (bind: %@): threePid: %@", @(bind), threePidAddSession);

    [self startIdentityServer3PidSession:threePidAddSession success:success failure:failure];

    return threePidAddSession;
}

- (void)finaliseIdentityServerPhoneNumberSession:(MX3PidAddSession*)threePidAddSession
                                       withToken:(NSString*)token
                                         success:(void (^)(void))success
                                         failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] finaliseIdentityServerPhoneNumberSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumMSISDN]);


    if (doesServerSupportSeparateAddAndBind)
    {
        [self tryFinaliseIdentityServer3PidSessionWithNewHomeserver:threePidAddSession withToken:token success:success failure:failure];
    }
    else
    {
        [self tryFinaliseIdentityServer3PidSessionWithOldHomeserver:threePidAddSession withToken:token success:success failure:failure];
    }
}


#pragma mark - Private methods -

- (MXHTTPOperation *)checkIdentityServerRequirementForAdding3PidWithSuccess:(void (^)(void))success
                                                                    failure:(void (^)(NSError * _Nonnull))failure
{
    MXWeakify(self);
    return [mxSession.matrixRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {
        MXStrongifyAndReturnIfNil(self);

        NSLog(@"[MX3PidAddManager] checkIdentityServerRequirement: %@", matrixVersions.doesServerRequireIdentityServerParam ? @"YES": @"NO");

        NSLog(@"[MX3PidAddManager] doesServerSupportSeparateAddAndBind: %@", matrixVersions.doesServerSupportSeparateAddAndBind ? @"YES": @"NO");
        self->doesServerSupportSeparateAddAndBind = matrixVersions.doesServerSupportSeparateAddAndBind;

        if (matrixVersions.doesServerRequireIdentityServerParam
            && !self->mxSession.matrixRestClient.identityServer)
        {
            NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                                 code:MX3PidAddManagerErrorDomainIdentityServerRequired
                                             userInfo:nil];
            failure(error);
        }
        else
        {
            success();
        }

    } failure:failure];
}

- (MXHTTPOperation *)doesServerSupportSeparateAddAndBind:(void (^)(BOOL doesServerSupportSeparateAddAndBind))success
                                                 failure:(void (^)(NSError * _Nonnull))failure
{
    __block MXHTTPOperation *operation;
    if (doesServerSupportSeparateAddAndBind)
    {
        success(doesServerSupportSeparateAddAndBind);
        operation = [MXHTTPOperation new];
    }
    else
    {
        MXWeakify(self);
        operation = [mxSession.identityService accessTokenWithSuccess:^(NSString * _Nullable accessToken) {
            MXStrongifyAndReturnIfNil(self);

            if (accessToken)
            {
                MXHTTPOperation *operation2 = [self->mxSession.matrixRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {

                    NSLog(@"[MX3PidAddManager] doesServerSupportSeparateAddAndBind: %@", matrixVersions.doesServerSupportSeparateAddAndBind ? @"YES": @"NO");
                    self->doesServerSupportSeparateAddAndBind = matrixVersions.doesServerSupportSeparateAddAndBind;
                    success(self->doesServerSupportSeparateAddAndBind);

                } failure:failure];

                if (operation2)
                {
                    [operation mutateTo:operation2];
                }
            }
            else
            {
                // If the IS does not support v2, use legacy APIs
                NSLog(@"[MX3PidAddManager] doesServerSupportSeparateAddAndBind: NO because v1 identity server");
                success(NO);
            }

        } failure:failure];
    }

    return operation;
}

- (nullable MXHTTPOperation *)submitValidationToken:(NSString *)token
                                  for3PidAddSession:(MX3PidAddSession*)threePidAddSession
                                            success:(void (^)(void))success
                                            failure:(void (^)(NSError * _Nonnull))failure
{
    MXHTTPOperation *operation;
    if (mxSession.identityService)
    {
        operation = [mxSession.identityService submit3PIDValidationToken:token
                                                                  medium:threePidAddSession.medium
                                                            clientSecret:threePidAddSession.clientSecret
                                                                     sid:threePidAddSession.sid
                                                                 success:success
                                                                 failure:failure];
    }
    else
    {
        NSLog(@"[MX3PidAddManager] submitValidationToken: ERROR: Failed to submit validation token for 3PID: %@, identity service is not set", threePidAddSession);

        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainIdentityServerRequired
                                         userInfo:nil];
        failure(error);
    }

    return operation;
}


#pragma mark - Bind to Identity Server -

// https://gist.github.com/jryans/839a09bf0c5a70e2f36ed990d50ed928#3b-changing-the-bind-status-of-a-3pid-post-msc2290
- (void)startIdentityServer3PidSession:(MX3PidAddSession*)threePidAddSession
                     success:(void (^)(BOOL needValidation))success
                     failure:(void (^)(NSError * _Nonnull))failure
{
    if (!mxSession.identityService)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainIdentityServerRequired
                                         userInfo:nil];
        failure(error);
        return;
    }

    MXWeakify(self);
    threePidAddSession.httpOperation = [self doesServerSupportSeparateAddAndBind:^(bool doesServerSupportSeparateAddAndBind) {
        MXStrongifyAndReturnIfNil(self);

        MXHTTPOperation *operation;
        if (doesServerSupportSeparateAddAndBind)
        {
            if (threePidAddSession.bind)
            {
                operation = [self startIdentityServer3PidSessionWithNewHomeserver:threePidAddSession success:^{
                    threePidAddSession.httpOperation = nil;
                    success(YES);
                } failure:^(NSError *error) {
                    threePidAddSession.httpOperation = nil;
                    failure(error);
                }];
            }
            else
            {
                // No need of 3Pid validation in this configuration
                operation = [self->mxSession.matrixRestClient unbind3PidWithAddress:threePidAddSession.address medium:threePidAddSession.medium success:^{

                    threePidAddSession.httpOperation = nil;

                    NSLog(@"[MX3PidAddManager] startIdentityServer3PidSession: DONE: threePid: %@", threePidAddSession);
                    success(NO);

                } failure:^(NSError *error) {
                    threePidAddSession.httpOperation = nil;
                    failure(error);
                }];
            }
        }
        else
        {
            operation = [self startBind3PidSessionWithOldHomeserver:threePidAddSession success:^{
                threePidAddSession.httpOperation = nil;
                success(YES);
            } failure:^(NSError *error) {
                threePidAddSession.httpOperation = nil;
                failure(error);
            }];
        }

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError * _Nonnull error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];
}


- (MXHTTPOperation *)startIdentityServer3PidSessionWithNewHomeserver:(MX3PidAddSession*)threePidAddSession
                                                             success:(void (^)(void))success
                                                             failure:(void (^)(NSError * _Nonnull))failure
{
    MXIdentityService *identityService = mxSession.identityService;
    MXHTTPOperation *operation;
    if ([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail])
    {
        operation = [identityService requestEmailValidation:threePidAddSession.address clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString * _Nonnull sid) {

            NSLog(@"[MX3PidAddManager] startIdentityServer3PidSessionWithNewHomeserver: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.sid = sid;
            success();

        } failure:^(NSError *error) {
            NSLog(@"[MX3PidAddManager] startIdentityServer3PidSessionWithNewHomeserver: threePid: %@. ERROR: requestTokenForEmail failed: %@", threePidAddSession, error);
            failure(error);
        }];
    }
    else
    {
        operation = [identityService requestPhoneNumberValidation:threePidAddSession.address countryCode:threePidAddSession.countryCode clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString * _Nonnull sid, NSString * _Nonnull msisdn) {

            NSLog(@"[MX3PidAddManager] startIdentityServer3PidSessionWithNewHomeserver: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.sid = sid;
            success();

        } failure:^(NSError *error) {
            NSLog(@"[MX3PidAddManager] startIdentityServer3PidSessionWithNewHomeserver: threePid: %@. ERROR: requestTokenForEmail failed: %@", threePidAddSession, error);
            failure(error);
        }];
    }

    return operation;
}

- (void)tryFinaliseIdentityServer3PidSessionWithNewHomeserver:(MX3PidAddSession*)threePidAddSession
                                                    withToken:(nullable NSString*)token
                                                      success:(void (^)(void))success
                                                      failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] tryFinaliseIdentityServer3PidSessionWithNewHomeserver: threePid: %@", threePidAddSession);

    NSParameterAssert(threePidAddSession.bind);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    if ([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail])
    {
        threePidAddSession.httpOperation = [mxSession.matrixRestClient bind3PidWithSessionId:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret success:^{

            threePidAddSession.httpOperation = nil;

            NSLog(@"[MX3PidAddManager] tryFinaliseIdentityServer3PidSessionWithNewHomeserver: DONE: threePid: %@", threePidAddSession);
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];
    }
    else if ([threePidAddSession.medium isEqualToString:kMX3PIDMediumMSISDN])
    {
        MXWeakify(self);
        threePidAddSession.httpOperation = [self submitValidationToken:token for3PidAddSession:threePidAddSession success:^{
            MXStrongifyAndReturnIfNil(self);

            MXHTTPOperation *operation = [self->mxSession.matrixRestClient bind3PidWithSessionId:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret success:^{

                NSLog(@"[MX3PidAddManager] tryFinaliseIdentityServer3PidSessionWithNewHomeserver: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.httpOperation = nil;
                success();

            } failure:^(NSError *error) {
                threePidAddSession.httpOperation = nil;
                failure(error);
            }];

            if (operation)
            {
                [threePidAddSession.httpOperation mutateTo:operation];
            }

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];
    }
}




#pragma mark - Legacy implementation
// TODO: To remove once these are abandonned

// https://gist.github.com/jryans/839a09bf0c5a70e2f36ed990d50ed928#3a-changing-the-bind-status-of-a-3pid-pre-msc2290
- (MXHTTPOperation *)startBind3PidSessionWithOldHomeserver:(MX3PidAddSession*)threePidAddSession
                                                   success:(void (^)(void))success
                                                   failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@", threePidAddSession);

    MXWeakify(self);
    MXHTTPOperation *operation;
    operation = [mxSession.matrixRestClient remove3PID:threePidAddSession.address medium:threePidAddSession.medium success:^{
        MXStrongifyAndReturnIfNil(self);

        MXHTTPOperation *operation2;
        if ([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail])
        {
            operation2 = [self->mxSession.matrixRestClient requestTokenForEmail:threePidAddSession.address isDuringRegistration:NO clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString *sid) {

                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.sid = sid;
                success();

            } failure:^(NSError *error) {
                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@. ERROR: requestTokenForEmail failed: %@", threePidAddSession, error);
                failure(error);
            }];
        }
        else
        {
            operation2 = [self->mxSession.matrixRestClient requestTokenForPhoneNumber:threePidAddSession.address isDuringRegistration:NO countryCode:threePidAddSession.countryCode clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString *sid, NSString *msisdn) {

                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.sid = sid;
                success();

            } failure:^(NSError *error) {
                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@. ERROR: requestTokenForEmail failed: %@", threePidAddSession, error);
                failure(error);
            }];
        }

        if (operation2)
        {
            [operation mutateTo:operation2];
        }


    } failure:^(NSError *error) {

        NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@. ERROR: remove3PID failed: %@", threePidAddSession, error);
        failure(error);
    }];

    return operation;
}

- (void)tryFinaliseIdentityServer3PidSessionWithOldHomeserver:(MX3PidAddSession*)threePidAddSession
                                                    withToken:(nullable NSString*)token
                                                      success:(void (^)(void))success
                                                      failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] tryFinaliseIdentityServer3PidSessionWithOldHomeserver: threePid: %@", threePidAddSession);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    if ([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail])
    {
        threePidAddSession.httpOperation = [mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:threePidAddSession.bind success:^{
            threePidAddSession.httpOperation = nil;

            NSLog(@"[MX3PidAddManager] tryFinaliseIdentityServer3PidSessionWithOldHomeserver: DONE: threePid: %@", threePidAddSession);
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];
    }
    else if ([threePidAddSession.medium isEqualToString:kMX3PIDMediumMSISDN])
    {
        MXWeakify(self);
        threePidAddSession.httpOperation = [self submitValidationToken:token for3PidAddSession:threePidAddSession success:^{
            MXStrongifyAndReturnIfNil(self);

            MXHTTPOperation *operation = [self->mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:threePidAddSession.bind success:^{

                NSLog(@"[MX3PidAddManager] tryFinaliseIdentityServer3PidSessionWithOldHomeserver: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.httpOperation = nil;
                success();

            } failure:^(NSError *error) {
                threePidAddSession.httpOperation = nil;
                failure(error);
            }];

            if (operation)
            {
                [threePidAddSession.httpOperation mutateTo:operation];
            }

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];
    }
}


@end