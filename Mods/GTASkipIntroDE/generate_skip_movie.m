#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

static void fail(NSError *error, int code) {
    if (error != nil) {
        fprintf(stderr, "%s (%s %ld)\n%s\n",
                error.localizedDescription.UTF8String,
                error.domain.UTF8String,
                (long)error.code,
                error.userInfo.description.UTF8String);
    } else {
        fprintf(stderr, "generator failed at step %d without an NSError\n", code);
    }
    exit(code);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: generate_skip_movie source.mp4 output.mp4\n");
            return 64;
        }

        NSURL *sourceURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSURL *outputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        NSArray *formatDescriptions = track.formatDescriptions;
        if (track == nil || formatDescriptions.count == 0) fail(nil, 1);

        NSError *error = nil;
        AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
        if (reader == nil) fail(error, 2);
        AVAssetReaderTrackOutput *readerOutput =
            [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
        readerOutput.alwaysCopiesSampleData = NO;
        if (![reader canAddOutput:readerOutput]) fail(reader.error, 3);
        [reader addOutput:readerOutput];

        AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:outputURL
                                                           fileType:AVFileTypeMPEG4
                                                              error:&error];
        if (writer == nil) fail(error, 4);
        CMFormatDescriptionRef formatHint =
            (__bridge CMFormatDescriptionRef)formatDescriptions.firstObject;
        AVAssetWriterInput *writerInput =
            [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                           outputSettings:nil
                                         sourceFormatHint:formatHint];
        writerInput.expectsMediaDataInRealTime = NO;
        if (![writer canAddInput:writerInput]) fail(writer.error, 5);
        [writer addInput:writerInput];

        if (![reader startReading]) fail(reader.error, 6);
        if (![writer startWriting]) fail(writer.error, 7);
        [writer startSessionAtSourceTime:kCMTimeZero];

        CMSampleBufferRef sample = NULL;
        while (sample == NULL || CMSampleBufferGetTotalSampleSize(sample) == 0) {
            if (sample != NULL) CFRelease(sample);
            sample = [readerOutput copyNextSampleBuffer];
            if (sample == NULL) fail(reader.error, 8);
        }
        CMFormatDescriptionRef sampleDescription = CMSampleBufferGetFormatDescription(sample);
        if (sampleDescription == NULL) {
            CFRelease(sample);
            fail(nil, 9);
        }
        if (![writerInput appendSampleBuffer:sample]) {
            CFRelease(sample);
            fail(writer.error, 10);
        }
        CFRelease(sample);
        [writerInput markAsFinished];

        __block BOOL completed = NO;
        [writer finishWritingWithCompletionHandler:^{ completed = YES; }];
        while (!completed) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        }
        if (writer.status != AVAssetWriterStatusCompleted) fail(writer.error, 11);
    }
    return 0;
}
