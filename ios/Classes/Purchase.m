//
// Created by Ralph Bergmann on 25.05.18.
//

#import "Purchase.h"


@implementation Purchase

@synthesize productId;
@synthesize purchaseDate;
@synthesize expiresDate;

- (instancetype)initWithProductId:(NSString *)aProductId
                     purchaseDate:(double)aPurchaseDate
                      expiresDate:(double)anExpiresDate
{
    self = [super init];
    if (self)
    {
        productId = aProductId;
        purchaseDate = aPurchaseDate;
        expiresDate = anExpiresDate;
    }

    return self;
}

+ (instancetype)purchaseWithProductId:(NSString *)aProductId
                         purchaseDate:(double)aPurchaseDate
                          expiresDate:(double)anExpiresDate
{
    return [[self alloc] initWithProductId:aProductId purchaseDate:aPurchaseDate expiresDate:anExpiresDate];
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
    {
        return YES;
    }
    if (!other || ![[other class] isEqual:[self class]])
    {
        return NO;
    }

    return [self isEqualToPurchase:other];
}

- (BOOL)isEqualToPurchase:(Purchase *)purchase
{
    if (self == purchase)
    {
        return YES;
    }
    if (purchase == nil)
    {
        return NO;
    }
    if (self.productId != purchase.productId && ![self.productId isEqualToString:purchase.productId])
    {
        return NO;
    }
    if (self.purchaseDate != purchase.purchaseDate)
    {
        return NO;
    }
    if (self.expiresDate != purchase.expiresDate)
    {
        return NO;
    }
    return YES;
}

- (NSUInteger)hash
{
    NSUInteger hash = [self.productId hash];
    hash = hash * 31u + [@(self.purchaseDate) hash];
    hash = hash * 31u + [@(self.expiresDate) hash];
    return hash;
}


@end
