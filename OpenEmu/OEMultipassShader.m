/*
 Copyright (c) 2013, OpenEmu Team

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "OEMultipassShader.h"
#import "OEShaderPlugin.h"
#import "OECGShader.h"
#import "OEGameShader_ForSubclassEyesOnly.h"

@implementation OEMultipassShader
{
    NSMutableArray *_shaders;
}

- (void)compileShaders
{
    if(![self isCompiled])
    {
        if(![self parseCGPFile]) return;

        for(OECGShader *x in _shaders)
            [x compileShaders];

        [self setCompiled:YES];
    }
}

- (NSTextCheckingResult *)checkRegularExpression:(NSString *)regexTerm inString:(NSString *)input withError:(NSError *)error
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexTerm options:NSRegularExpressionAnchorsMatchLines error:&error];
    NSRange inputRange = NSMakeRange(0, [input length]);
    return [regex firstMatchInString:input options:0 range:inputRange];
}

- (BOOL)parseCGPFile
{
    NSError  *error = nil;
    NSString *input = [NSString stringWithContentsOfFile:[self filePath] encoding:NSUTF8StringEncoding error:&error];

    if(input == nil)
    {
        NSLog(@"Couldn't read shader source file of %@: %@", [self shaderName], error);
        return NO;
    }

    // Remove whitespace
    NSArray  *seperateByWhitespace = [input componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *strippedInput = [seperateByWhitespace componentsJoinedByString:@""];

    // Parse the number of shaders
    NSTextCheckingResult *result = [self checkRegularExpression:@"(?<=shaders=).*$" inString:strippedInput withError:error];
    if(result.range.location == NSNotFound)
    {
        NSLog(@"Couldn't find \"shaders\" argument of %@: %@", [self shaderName], error);
        return NO;
    }

    _numberOfPasses = [[strippedInput substringWithRange:result.range] integerValue];

    if(_numberOfPasses > 10)
    {
        NSLog(@"Too many shader passes in %@: %@", [self shaderName], error);
        return NO;
    }

    _shaders = [NSMutableArray arrayWithCapacity:_numberOfPasses];

    // We need to find that many shader sources
    for(NSUInteger i = 0; i < _numberOfPasses; ++i)
    {
        result = [self checkRegularExpression:[NSString stringWithFormat:@"(?<=shader%ld=).*(?=.cg)", i] inString:strippedInput withError:error];
        if(result.range.location == NSNotFound)
        {
            NSLog(@"Couldn't find \"shader%ld\" argument of %@: %@", i, [self shaderName], error);
            return NO;
        }

        NSString *name = [[strippedInput substringWithRange:result.range] stringByReplacingOccurrencesOfString:@"\"" withString:@""];

        // Create shader
        OECGShader *shader = [[OECGShaderPlugin pluginWithName:name] shaderWithContext:[self shaderContext]];

        // Check if linear filtering is to be used
        result = [self checkRegularExpression:[NSString stringWithFormat:@"(?<=filter_linear%ld=).*", i] inString:strippedInput withError:error];
        NSString *otherArguments = [[strippedInput substringWithRange:result.range] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        if([otherArguments isEqualToString:@"true"] || [otherArguments isEqualToString:@"1"])
        {
            [shader setLinearFiltering:YES];
        }

        // Check how the shader should scale
        result = [self checkRegularExpression:[NSString stringWithFormat:@"(?<=scale_type%ld=).*", i] inString:strippedInput withError:error];
        if(result.range.location != NSNotFound)
        {
            otherArguments = [[strippedInput substringWithRange:result.range] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
            if([otherArguments isEqualToString:@"viewport"])
                [shader setScaleType:OEScaleTypeViewPort];
            else if([otherArguments isEqualToString:@"absolute"])
                [shader setScaleType:OEScaleTypeAbsolute];
            else
                [shader setScaleType:OEScaleTypeSource];
        }

        // Check for the scaling factor
        result = [self checkRegularExpression:[NSString stringWithFormat:@"(?<=scale%ld=).*", i] inString:strippedInput withError:error];
        if(result.range.location != NSNotFound)
        {
            otherArguments = [[strippedInput substringWithRange:result.range] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
            [shader setScaler:CGSizeMake([otherArguments floatValue], [otherArguments floatValue])];
        }

        // Add the shader to the shaders array
        [_shaders addObject:shader];
    }

    _NTSCFilter = OENTSCFilterTypeNone;

    result = [self checkRegularExpression:@"(?<=ntsc_filter=).*" inString:strippedInput withError:error];
    if(result.range.location != NSNotFound)
    {
         NSString *ntscString = [[strippedInput substringWithRange:result.range] stringByReplacingOccurrencesOfString:@"\"" withString:@""];

        if([ntscString isEqualToString:@"composite"])
            _NTSCFilter = OENTSCFilterTypeComposite;
        else if([ntscString isEqualToString:@"svideo"])
            _NTSCFilter = OENTSCFilterTypeSVideo;
        else if([ntscString isEqualToString:@"rgb"])
            _NTSCFilter = OENTSCFilterTypeRGB;
    }

    return YES;
}

- (NSArray *)shaders
{
    return _shaders;
}

@end
