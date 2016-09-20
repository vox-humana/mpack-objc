//
// Created by Arthur Semenyutin on 02/06/16.
//
// This source code is licensed under the MIT-style license found in the
// LICENSE file in the root directory of this source tree.
//

@import Foundation;

@interface NSData (MPackObjc)
- (nullable id)mpo_parseMessagePackData;
@end

@interface NSObject(MPackObjc)
- (nullable NSData *)mpo_messagePackData;
@end
