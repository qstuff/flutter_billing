//
// Created by Ralph Bergmann on 25.05.18.
//

#import <Foundation/Foundation.h>


@interface Purchase : NSObject

@property(readonly) NSString *productId;
@property(readonly) double purchaseDate;
@property(readonly) double expiresDate;

- (instancetype)initWithProductId:(NSString *)aProductId
                     purchaseDate:(double)aPurchaseDate
                      expiresDate:(double)anExpiresDate;

+ (instancetype)purchaseWithProductId:(NSString *)aProductId
                         purchaseDate:(double)aPurchaseDate
                          expiresDate:(double)anExpiresDate;

- (BOOL)isEqual:(id)other;

- (BOOL)isEqualToPurchase:(Purchase *)purchase;

- (NSUInteger)hash;


@end
