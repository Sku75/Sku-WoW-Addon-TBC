#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

static CGWindowID wowWindow(void) {
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *w in windows) {
        NSString *owner = [w[(id)kCGWindowOwnerName] lowercaseString] ?: @"";
        // The Anniversary macOS client registers its actual game window with
        // WindowServer as "Wow", although NSWorkspace exposes the application
        // as "World of Warcraft Classic".
        if ([owner isEqualToString:@"wow"] || [owner containsString:@"world of warcraft"] || [owner containsString:@"wowclassic"])
            return [w[(id)kCGWindowNumber] unsignedIntValue];
    }
    return kCGNullWindowID;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        CGWindowID wid = wowWindow();
        if (!wid) { fprintf(stderr, "World of Warcraft wurde nicht gefunden.\n"); return 2; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, wid, kCGWindowImageBoundsIgnoreFraming);
#pragma clang diagnostic pop
        if (!image) { fprintf(stderr, "Bildschirmaufnahme ist nicht freigegeben.\n"); return 3; }
        if (argc > 2 && strcmp(argv[1], "--image") == 0) {
            NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
            CGImageDestinationRef out = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
            if (out) { CGImageDestinationAddImage(out, image, NULL); CGImageDestinationFinalize(out); CFRelease(out); }
        }
        VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;
        request.recognitionLanguages = @[@"de-DE", @"en-US"];
        NSError *error = nil;
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
        BOOL ok = [handler performRequests:@[request] error:&error]; CGImageRelease(image);
        if (!ok) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 4; }
        NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [observation topCandidates:1].firstObject; if (!candidate) continue;
            CGRect b = observation.boundingBox;
            [items addObject:@{@"text":candidate.string, @"x":@(b.origin.x), @"y":@(b.origin.y), @"width":@(b.size.width), @"height":@(b.size.height)}];
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"items":items} options:0 error:&error];
        if (!json) return 5; fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
    }
    return 0;
}

