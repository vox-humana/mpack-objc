//
// Created by Arthur Semenyutin on 02/06/16.
//
// This source code is licensed under the MIT-style license found in the
// LICENSE file in the root directory of this source tree.
//

#import "MPackObjc.h"
#import "mpack.h"

#pragma mark - Parsing
static id parseElement(mpack_reader_t *reader) {
    mpack_tag_t val = mpack_read_tag(reader);
    if (mpack_reader_error(reader) != mpack_ok)
        return nil;

    switch (val.type) {
        case mpack_type_nil:
            return [NSNull null];
        case mpack_type_bool:
            return @(val.v.b);
        case mpack_type_float:
            return [[NSNumber alloc] initWithFloat:val.v.f];
        case mpack_type_double:
            return [[NSNumber alloc] initWithDouble:val.v.d];

        case mpack_type_int:
            return [[NSNumber alloc] initWithLongLong:val.v.i];
        case mpack_type_uint:
            return [[NSNumber alloc] initWithUnsignedLongLong:val.v.u];

        case mpack_type_bin:
        {
            // TODO: use external tmp buffer for small chunks
            void *buffer = malloc(val.v.l);
            if (buffer == NULL) {
                mpack_skip_bytes(reader, val.v.l);
                mpack_done_bin(reader);
                return nil;
            }
            mpack_read_bytes(reader, buffer, val.v.l);
            mpack_done_bin(reader);
            return [[NSData alloc] initWithBytesNoCopy:buffer length:val.v.l freeWhenDone:YES];
        }

        case mpack_type_ext:
            // just ignore
            mpack_skip_bytes(reader, val.v.l);
            mpack_done_ext(reader);
            return nil;

        case mpack_type_str:
        {
            // TODO: use external tmp buffer for small chunks
            void *buffer = malloc(val.v.l);
            if (buffer == NULL) {
                mpack_skip_bytes(reader, val.v.l);
                mpack_done_bin(reader);
                return nil;
            }
            mpack_read_utf8(reader, buffer, val.v.l);
            if (mpack_reader_error(reader) != mpack_ok) {
                mpack_done_str(reader);
                return nil;
            }

            mpack_done_str(reader);
            return [[NSString alloc] initWithBytesNoCopy:buffer length:val.v.l encoding:NSUTF8StringEncoding freeWhenDone:YES];
        }

        case mpack_type_array:
        {
            NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:val.v.n];
            for (size_t i = 0; i < val.v.n; ++i) {
                id obj = parseElement(reader);
                if (!obj) {
                    NSCAssert(NO, @"Could not read element from message pack");
                    continue;
                }
                [array addObject:obj];
            }
            mpack_done_array(reader);
            return [array copy];
        }

        case mpack_type_map:
        {
            NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithCapacity:val.v.n];
            for (size_t i = 0; i < val.v.n; ++i) {
                id key = parseElement(reader);
                id value = parseElement(reader);
                if (!key) {
                    NSCAssert(NO, @"Could not read key for element from message pack");
                    continue;
                }
                if (!value) {
                    NSCAssert(NO, @"Could not read value for %@ from message pack", key);
                    continue;
                }
                dictionary[key] = value;
            }
            mpack_done_map(reader);
            return [dictionary copy];
        }

        default:
            NSCAssert(NO, @"Unknown message pack type: %@", @(val.type));
            return nil;
    }
}

@implementation NSData (MPackObjc)

- (nullable id)mpo_parseMessagePackData {
    if (self.length == 0) {
        return nil;
    }

    mpack_reader_t reader;
    mpack_reader_init_data(&reader, self.bytes, self.length);
    id obj = parseElement(&reader);
    mpack_reader_destroy(&reader);
    return obj;
}

@end


#pragma mark - Packing
@implementation NSObject(MPackObjc)

- (void)_mpoPackToWriter:(mpack_writer_t *)writer {
    [NSException raise:NSInternalInconsistencyException format:@"Abstract method called %@::%@", NSStringFromClass(self.class), NSStringFromSelector(_cmd)];
}

- (NSData *)mpo_messagePackData {
    char *data;
    size_t size;
    mpack_writer_t writer;
    mpack_writer_init_growable(&writer, &data, &size);

    [self _mpoPackToWriter:&writer];
    if (mpack_writer_destroy(&writer) != mpack_ok) {
        NSCAssert(NO, @"An error '%@' occurred encoding the data", @(mpack_error_to_string(writer.error)));
        return nil;
    }
    
    return [NSData dataWithBytesNoCopy:data length:size freeWhenDone:YES];
}

@end

static void packNullToWriter(mpack_writer_t *writer) {
    mpack_write_nil(writer);
}

static void packNumber(NSNumber *number, mpack_writer_t *writer) {
    CFNumberType numberType = CFNumberGetType((__bridge CFNumberRef)number);
    switch (numberType)	{
        case kCFNumberSInt8Type:
            mpack_write_i8(writer, number.charValue);
            break;
        case kCFNumberSInt16Type:
        case kCFNumberShortType:
            mpack_write_i16(writer, number.shortValue);
            break;
        case kCFNumberSInt32Type:
        case kCFNumberIntType:
        case kCFNumberLongType:
        case kCFNumberCFIndexType:
        case kCFNumberNSIntegerType:
            mpack_write_i32(writer, number.intValue);
            break;
        case kCFNumberSInt64Type:
        case kCFNumberLongLongType:
            mpack_write_i64(writer, number.longLongValue);
            break;
        case kCFNumberFloat32Type:
        case kCFNumberFloatType:
        case kCFNumberCGFloatType:
            mpack_write_float(writer, number.floatValue);
            break;
        case kCFNumberFloat64Type:
        case kCFNumberDoubleType:
            mpack_write_double(writer, number.doubleValue);
            break;
        case kCFNumberCharType: {
            char value = number.charValue;
            if (value == 0)
                mpack_write_false(writer);
            else if (value == 1)
                mpack_write_true(writer);
            else
                mpack_write_i8(writer, value);
        }
            break;
        default:
            NSCAssert(NO, @"Unknown number type: %@", number);
    }

}

static void packString(NSString *string, mpack_writer_t *writer) {
    mpack_write_cstr(writer, string.UTF8String);
}

static void packData(NSData *data, mpack_writer_t *writer) {
    NSCAssert(data.length < UINT32_MAX, @"Got data with %@ bytes", @(data.length));
    mpack_write_bin(writer, data.bytes, (uint32_t)data.length);
}

static void packArray(NSArray *array, mpack_writer_t *writer) {
    NSCAssert(array.count < UINT32_MAX, @"Got huge array with %@ elements", @(array.count));
    mpack_start_array(writer, (uint32_t)array.count);
    for (id obj in array) {
        [obj _mpoPackToWriter:writer];
    }
    mpack_finish_array(writer);
}

static void packDictionary(NSDictionary *dictionary, mpack_writer_t *writer) {
    NSCAssert(dictionary.count < UINT32_MAX, @"Got huge dictionary with %@ elements", @(dictionary.count));
    mpack_start_map(writer, (uint32_t)dictionary.count);
    for (id key in dictionary) {
        [key _mpoPackToWriter:writer];
        [dictionary[key] _mpoPackToWriter:writer];
    }
    mpack_finish_map(writer);
}

@implementation NSNull(MPackObjcPackerVisitor)
- (void)_mpoPackToWriter:(mpack_writer_t *)writer {
    packNullToWriter(writer);
}
@end

@implementation NSNumber(MPackObjcPackerVisitor)
- (void)_mpoPackToWriter:(mpack_writer_t *)writer {
    packNumber(self, writer);
}
@end

@implementation NSString(MPackObjcPackerVisitor)
- (void)_mpoPackToWriter:(mpack_writer_t *)writer {
    packString(self, writer);
}
@end

@implementation NSData(MPackObjcPackerVisitor)
- (void)_mpoPackToWriter:(mpack_writer_t *)writer {
    packData(self, writer);
}
@end

@implementation NSArray(MPackObjcPackerVisitor)
- (void)_mpoPackToWriter:(mpack_writer_t *)writer {
    packArray(self, writer);
}
@end

@implementation NSDictionary(MPackObjcPackerVisitor)
- (void)_mpoPackToWriter:(mpack_writer_t *)writer {
    packDictionary(self, writer);
}
@end
