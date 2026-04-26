#import <Cocoa/Cocoa.h>
#import <FinderSync/FinderSync.h>

@interface NewFileFinderExtension : FIFinderSync
@end

extern int NSExtensionMain(int argc, const char *argv[]);

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        return NSExtensionMain(argc, argv);
    }
}

@implementation NewFileFinderExtension

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURL *root = [NSURL fileURLWithPath:@"/" isDirectory:YES];
        [FIFinderSyncController defaultController].directoryURLs = [NSSet setWithObject:root];
        [self writeLog:@"initialized; watching /"];
    }
    return self;
}

- (NSMenu *)menuForMenuKind:(FIMenuKind)menuKind {
    [self writeLog:[NSString stringWithFormat:@"menu requested: %lu", (unsigned long)menuKind]];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"New File from Clipboard"
                                                  action:@selector(createNewFileFromClipboard:)
                                           keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return menu;
}

- (void)createNewFileFromClipboard:(id)sender {
    NSString *clipboard = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
    NSURL *directory = [self targetDirectory];
    NSString *title = [self suggestedTitleFromText:clipboard];
    NSURL *fileURL = [self availableFileURLInDirectory:directory title:title];
    [self writeLog:[NSString stringWithFormat:@"creating file at %@", fileURL.path]];

    BOOL accessed = [directory startAccessingSecurityScopedResource];
    NSError *error = nil;
    BOOL wrote = [clipboard writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (accessed) {
        [directory stopAccessingSecurityScopedResource];
    }

    if (!wrote) {
        [self writeLog:[NSString stringWithFormat:@"create failed: %@", error.localizedDescription]];
        [self showError:[NSString stringWithFormat:@"Could not create the file:\n%@", error.localizedDescription]];
        return;
    }

    [self writeLog:@"create succeeded"];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[fileURL]];
    [[NSWorkspace sharedWorkspace] openURL:fileURL];
}

- (NSURL *)targetDirectory {
    FIFinderSyncController *controller = [FIFinderSyncController defaultController];
    NSURL *target = controller.targetedURL;
    if (target) {
        return [self isDirectoryURL:target] ? target : target.URLByDeletingLastPathComponent;
    }

    NSURL *selected = controller.selectedItemURLs.firstObject;
    if (selected) {
        return [self isDirectoryURL:selected] ? selected : selected.URLByDeletingLastPathComponent;
    }

    return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"] isDirectory:YES];
}

- (BOOL)isDirectoryURL:(NSURL *)url {
    NSNumber *isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    return isDirectory.boolValue || url.hasDirectoryPath;
}

- (NSString *)suggestedTitleFromText:(NSString *)text {
    NSString *shortcut = [self shortcutSuggestedTitleFromText:text];
    if (shortcut.length > 0) {
        return shortcut;
    }

    NSString *source = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    source = [self replacePattern:@"<[^>]+>" inString:source withString:@" "];

    NSString *markdown = [self firstMatchInString:source pattern:@"\\[([^\\]\\n]{4,90})\\]\\(https?://[^\\s)]+\\)" group:1];
    if (markdown.length > 0) {
        return [self sanitizedTitle:markdown];
    }

    NSString *urlTitle = [self titleFromURLInString:source];
    if (urlTitle.length > 0) {
        return [self sanitizedTitle:urlTitle];
    }

    source = [self replacePattern:@"(?m)^\\s*[-*+]\\s+" inString:source withString:@""];
    source = [self replacePattern:@"(?m)^\\s*#{1,6}\\s+" inString:source withString:@""];

    NSArray<NSString *> *rawLines = [source componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in rawLines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) {
            [lines addObject:trimmed];
        }
    }

    NSString *usefulLine = @"";
    for (NSString *line in lines) {
        if (line.length < 4) {
            continue;
        }
        if ([self firstMatchInString:line pattern:@"^(from|to|subject|sent|date):" group:0].length > 0) {
            continue;
        }
        usefulLine = line;
        break;
    }
    if (usefulLine.length == 0) {
        usefulLine = [lines componentsJoinedByString:@" "];
    }

    usefulLine = [self replacePattern:@"\\s+" inString:usefulLine withString:@" "];
    NSSet<NSString *> *stopWords = [NSSet setWithArray:@[@"the", @"and", @"but", @"for", @"from", @"with", @"that", @"this", @"your", @"you", @"are", @"was", @"were", @"have", @"has", @"not", @"into", @"onto", @"about"]];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *word in [usefulLine componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (word.length > 1 && ![stopWords containsObject:word.lowercaseString]) {
            [words addObject:word];
        }
    }
    if (words.count == 0) {
        [words addObjectsFromArray:[usefulLine componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    }

    NSUInteger count = MIN(words.count, 8);
    NSString *title = count > 0 ? [[words subarrayWithRange:NSMakeRange(0, count)] componentsJoinedByString:@" "] : [self timestampTitle];
    return [self sanitizedTitle:title];
}

- (NSString *)shortcutSuggestedTitleFromText:(NSString *)text {
    static NSString *cachedShortcut = nil;
    static dispatch_once_t resolveOnce;
    dispatch_once(&resolveOnce, ^{
        NSArray<NSString *> *candidates = @[@"Suggest File Name from Clipboard", @"Suggest Filename from Clipboard", @"Name Clipboard File"];
        NSString *names = [self runCommand:@"/usr/bin/shortcuts" arguments:@[@"list"] input:nil];
        NSArray<NSString *> *available = [names componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        for (NSString *candidate in candidates) {
            if ([available containsObject:candidate]) {
                cachedShortcut = candidate;
                break;
            }
        }
    });
    if (!cachedShortcut) {
        return nil;
    }

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *raw = [self runCommand:@"/usr/bin/shortcuts" arguments:@[@"run", cachedShortcut, @"--input-path", path] input:nil];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSString *firstLine = [raw componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject;
    NSString *trimmed = [firstLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }
    return [self sanitizedTitle:trimmed];
}

- (NSString *)titleFromURLInString:(NSString *)text {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"https?://(?:www\\.)?([^/\\s?#]+)(/[^\\s?#]*)?" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) {
        return nil;
    }
    NSString *host = [text substringWithRange:[match rangeAtIndex:1]];
    NSString *path = [match rangeAtIndex:2].location != NSNotFound ? [text substringWithRange:[match rangeAtIndex:2]] : @"";
    host = [self replacePattern:@"\\.[a-z]{2,}$" inString:host withString:@""];
    path = [self replacePattern:@"[-_]" inString:path withString:@" "];
    path = [self replacePattern:@"\\.[a-z0-9]{1,8}$" inString:path withString:@""];
    path = [self replacePattern:@"/+" inString:path withString:@" "];
    NSString *joined = [[host stringByAppendingString:@" "] stringByAppendingString:path];
    return joined.capitalizedString;
}

- (NSString *)sanitizedTitle:(NSString *)raw {
    NSString *title = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    title = [self replacePattern:@"[\\r\\n\\t]+" inString:title withString:@" "];
    title = [self replacePattern:@"[/\\\\:]" inString:title withString:@"-"];
    title = [self replacePattern:@"[<>|?*\"\\\\]+" inString:title withString:@""];
    title = [self replacePattern:@"\\s+" inString:title withString:@" "];
    title = [title stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". "]];

    if (title.length > 72) {
        title = [title substringToIndex:72];
        NSRange lastSpace = [title rangeOfString:@" " options:NSBackwardsSearch];
        if (lastSpace.location != NSNotFound) {
            title = [title substringToIndex:lastSpace.location];
        }
    }

    return title.length > 0 ? title : [self timestampTitle];
}

- (NSString *)timestampTitle {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"Clipboard yyyy-MM-dd HH.mm.ss";
    return [formatter stringFromDate:NSDate.date];
}

- (NSURL *)availableFileURLInDirectory:(NSURL *)directory title:(NSString *)title {
    NSURL *candidate = [[directory URLByAppendingPathComponent:title] URLByAppendingPathExtension:@"txt"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        return candidate;
    }

    for (NSUInteger index = 2; index <= 9999; index++) {
        NSString *name = [NSString stringWithFormat:@"%@ %lu", title, (unsigned long)index];
        candidate = [[directory URLByAppendingPathComponent:name] URLByAppendingPathExtension:@"txt"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
            return candidate;
        }
    }
    NSString *fallback = [NSString stringWithFormat:@"%@ %@", title, [self timestampTitle]];
    return [[directory URLByAppendingPathComponent:fallback] URLByAppendingPathExtension:@"txt"];
}

- (NSString *)replacePattern:(NSString *)pattern inString:(NSString *)string withString:(NSString *)replacement {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [regex stringByReplacingMatchesInString:string options:0 range:NSMakeRange(0, string.length) withTemplate:replacement];
}

- (NSString *)firstMatchInString:(NSString *)string pattern:(NSString *)pattern group:(NSUInteger)group {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match || group >= match.numberOfRanges || [match rangeAtIndex:group].location == NSNotFound) {
        return nil;
    }
    return [string substringWithRange:[match rangeAtIndex:group]];
}

- (NSString *)runCommand:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments input:(NSString *)input {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    task.arguments = arguments;
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = [NSPipe pipe];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return @"";
    }
    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)showError:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"New File from Clipboard";
        alert.informativeText = message;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    });
}

- (void)writeLog:(NSString *)message {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [directory stringByAppendingPathComponent:@"NewFileFromClipboard.log"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

@end
