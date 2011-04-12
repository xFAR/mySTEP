/*
 NSLayoutManager.m
 
 Author:	H. N. Schaller <hns@computer.org>
 Date:	Jun 2006
 
 This file is part of the mySTEP Library and is provided
 under the terms of the GNU Library General Public License.
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTypesetter.h>

#import "NSBackendPrivate.h"

@implementation NSGlyphGenerator

+ (id) sharedGlyphGenerator;
{ // a single shared instance
	static NSGlyphGenerator *sharedGlyphGenerator;
	if(!sharedGlyphGenerator)
		sharedGlyphGenerator=[[self alloc] init];
	return sharedGlyphGenerator;
}

- (void) generateGlyphsForGlyphStorage:(id <NSGlyphStorage>) storage
			 desiredNumberOfCharacters:(unsigned int) num
							glyphIndex:(unsigned int *) glyph
						characterIndex:(unsigned int *) index;
{
	BACKEND;
}

@end

@implementation NSLayoutManager

- (NSGlyph *) _glyphsAtIndex:(unsigned) idx;
{
	return &_glyphs[idx];
}

#if 0

- (void) _layout
{ // calculate layout
	NSTextContainer *container=[self textContainerForGlyphAtIndex:glyphsToShow.location effectiveRange:NULL];
	NSSize containerSize=[container containerSize];
	NSString *str=[_textStorage string];								// raw characters
	unsigned length=[str length];
	NSPoint pos=NSZeroPoint;
	unsigned lastLine=0;
	_numberOfGlyphs=0;
	while(_numberOfGlyphs < length)
			{
				NSGlyph glyph=NSNullGlyph;
				NSRect box={ pos, NSZeroSize };
				NSParagraphStyle *style=[textStorage attribute:NSParagraphStyleAttributeName atIndex:_numberOfGlyphs effectiveRange:NULL];
				NSFont *font=[textStorage attribute:NSFontAttributeName atIndex:_numberOfGlyphs effectiveRange:NULL];
				switch([str characterAtIndex:_numberOfGlyphs])
					{
						case NSAttachmentCharacter:
							{
							}
						case '\t':
							{
								pos = 
								glyph = space
							}
						default:
							{
							// check if we need to hyphenate/wrap
							}
						case '\n':
							{
								// get paragraph style
								// adjust left/right etc. in a second pass starting at lastLine
								// advance to next line - get max height of any character
								// check for default advancements etc.
								pos.y+=12;
								box.size.height=12;
							}
						case '\r':
							pos.x=0;
							break;
					}
				_glyphs[_numberOfGlyphs].glyph=glyph;
				_glyphs[_numberOfGlyphs].box=box;
				_numberOfGlyphs++;	// one more
			}
}

// draw: get other atributes (color, underlining) from string and just draw at given positions
// boundingBox for range: build union of all boxes (except NSNullGlyph)
// locate point: find first box

#endif

/*
 * this is currently our core layout and drawing method
 * it works quite well but has 3 limitations
 *
 * 1. it reclculates the layout for each call since there is no caching
 * 2. it can't properly align vertically if font size is variable
 * 3. it can't handle horizontal alignment
 *
 * some minor limitations
 * 4. can't handle more than one text container
 * 5. recalculates for invisible ranges
 * 6. may line-break words at attribute run sections instead of hyphenation positions
 *
 * all this can be easily solved by separating the layout and the drawing phases
 * and by caching the glyph positions
 *
 * [_glyphGenerator generateGlyphsForGlyphStorage:self desiredNumberOfCharacters:attribRange.length glyphIndex:0 characterIndex:attribRange.location];
 */

//
// FIXME: optimize/cache for large NSTextStorages and multiple NSTextContainers
//
// FIXME: use and update glyph cache if needed
// well, we should move that to the shared NSGlyphGenerator which does the layout
// and make it run in the background
//
// 1. split into paragraphs
// 2. split into lines
// 3. split into words and try to fill line and hyphenate / line break
// 4. split words into attribute ranges
//
// drawing should look like
// [ctxt _setFont:xxx]; 
// [ctxt _beginText];
// [ctxt _newLine]; or [ctxt _setTextPosition:...];
// [ctxt _setBaseline:xxx]; 
// [ctxt _setHorizontalScale:xxx]; 
// [ctxt _drawGlyphs:(NSGlyph *)glyphs count:(unsigned)cnt;	// -> (string) Tj
// [ctxt _endText];
//

- (NSRect) _draw:(BOOL) draw 
						glyphsForGlyphRange:(NSRange)glyphsToShow 
						atPoint:(NSPoint)origin		// top left of the text container (in flipped coordinates)
						findPoint:(NSPoint) find
						foundAtPos:(unsigned int *) foundAtPos
{ // this is the core text drawing interface and all string additions are based on this call!
	NSGraphicsContext *ctxt=draw?[NSGraphicsContext currentContext]:(NSGraphicsContext *) [NSNull null];
	NSTextContainer *container=[self textContainerForGlyphAtIndex:glyphsToShow.location effectiveRange:NULL];	// this call could fill the cache if needed...
	NSSize containerSize=[container containerSize];
	NSString *str=[_textStorage string];								// raw characters
	NSRange rangeLimit=NSMakeRange(0, [str length]);		// all
	NSPoint pos;
	NSAffineTransform *tm;		// text matrix
#if 0
	NSFont *font=(NSFont *) [NSNull null];				// check for internal errors
#else
	NSFont *font;				// current font attribute
#endif
	NSColor *foreGround;
	BOOL flipped=draw?[ctxt isFlipped]:NO;
	NSRect box=NSZeroRect;
	NSRect clipBox;
//	BOOL outside=YES;
	if(foundAtPos)
		*foundAtPos=NSMaxRange(glyphsToShow);	// default to maximum
	if(draw)
		{
		clipBox=[ctxt _clipBox];
#if 0	// testing
		[[NSColor redColor] set];
		if(flipped)
			NSRectFill((NSRect) { origin, containerSize });
		else
			NSRectFill((NSRect) { { origin.x, origin.y-containerSize.height }, containerSize });
		[[NSColor yellowColor] set];
		if(flipped)
			NSRectFill((NSRect) { origin, { 2.0, 2.0 } });
		else
			NSRectFill((NSRect) { { origin.x, origin.y-containerSize.height }, { 2.0, 2.0 } });
#endif
		[ctxt setCompositingOperation:NSCompositeCopy];
		[ctxt _beginText];			// starts at position (0,0)
		}
	pos=origin;							// tracks current drawing position (top left of the line) - Note: PDF needs to position to the baseline

	while(rangeLimit.location < NSMaxRange(glyphsToShow))
		{ // parse and process white-space separated words resp. fragments with same attributes
		NSRange attribRange;	// range with constant attributes
		NSString *substr;		// substring (without attributes)
		unsigned int i;
		NSDictionary *attr;		// the attributes
		NSParagraphStyle *para;
		id attrib;				// some individual attribute
		unsigned style;			// underline and strike-through mask
		NSRange wordRange;		// to find word that fits into line
		float width;			// width of the substr with given font
		float baseline;
		if(foundAtPos && rangeLimit.location > 0 && pos.y > find.y)
				{ // was before current position (i.e. end of line)
					*foundAtPos=rangeLimit.location-1;
					foundAtPos=NULL;	// we have found it, so don't update again 
				}
		switch([str characterAtIndex:rangeLimit.location])
			{
			case NSAttachmentCharacter:
				{
				NSTextAttachment *att=[_textStorage attribute:NSAttachmentAttributeName atIndex:rangeLimit.location effectiveRange:NULL];
				id <NSTextAttachmentCell> cell = [att attachmentCell];
				if(cell)
					{
					NSRect rect=[cell cellFrameForTextContainer:container
										   proposedLineFragment:(NSRect) { pos, { 12.0, 12.0 } }
												  glyphPosition:pos
												 characterIndex:rangeLimit.location];
					if(flipped)
						;
					if(pos.x+rect.size.width > origin.x+containerSize.width)
						; // FIXME: needs to start on a new line
					if(draw && NSLocationInRange(rangeLimit.location, glyphsToShow))
						{
#if 0
						NSLog(@"drawing attachment (%@): %@ %@", NSStringFromRect(rect), att, cell);
#endif
						[cell drawWithFrame:rect
									 inView:[container textView]
							 characterIndex:rangeLimit.location
							  layoutManager:self];
						}
					else if(NSLocationInRange(rangeLimit.location, glyphsToShow))
						box=NSUnionRect(box, rect);
					pos.x += rect.size.width;
					if(foundAtPos && pos.y+rect.size.height >= find.y && pos.x >= find.x)
							{ // was the attachment
								*foundAtPos=rangeLimit.location;
								foundAtPos=NULL;	// we have found it, so don't update again 
							}
					}
				rangeLimit.location++;
				rangeLimit.length--;
				continue;
				}
			case '\t':
				{
					float tabwidth;
					font=[_textStorage attribute:NSFontAttributeName atIndex:rangeLimit.location effectiveRange:NULL];
					if(!font)
						font=[NSFont userFontOfSize:0.0];		// use default system font
					tabwidth=8.0*[font widthOfString:@"x"];	// approx. 8 characters
					// draw space glyph + characterspacing
					tabwidth=origin.x+(1+(int)((pos.x-origin.x)/tabwidth))*tabwidth-pos.x;	// width of complete tab
					if(pos.x+tabwidth <= origin.x+containerSize.width)
						{ // still fits into remaining line
							if(!draw && NSLocationInRange(rangeLimit.location, glyphsToShow))
								box=NSUnionRect(box, NSMakeRect(pos.x, pos.y, tabwidth, [self defaultLineHeightForFont:font]));
							pos.x+=tabwidth;
							if(foundAtPos && pos.y+[self defaultLineHeightForFont:font] >= find.y && pos.x >= find.x)
									{ // was in last fragment
										*foundAtPos=rangeLimit.location;
										foundAtPos=NULL;	// we have found it, so don't update again 
									}
						rangeLimit.location++;
						rangeLimit.length--;
						continue;
						}
					// treat as a newline
				}
			case '\n':
				{ // go to a new line
					para=[_textStorage attribute:NSParagraphStyleAttributeName atIndex:rangeLimit.location effectiveRange:NULL];
					float advance;
					float nlwidth;	// "width" of newline
					font=[_textStorage attribute:NSFontAttributeName atIndex:rangeLimit.location effectiveRange:NULL];
					if(!font)
						font=[NSFont userFontOfSize:0.0];		// use default system font
					nlwidth=origin.x+containerSize.width-pos.x;
					advance=[self defaultLineHeightForFont:font];
					if(para)
						advance+=[para paragraphSpacing];
					if(!draw && NSLocationInRange(rangeLimit.location, glyphsToShow))
						box=NSUnionRect(box, NSMakeRect(pos.x, pos.y, nlwidth, [self defaultLineHeightForFont:font]));
					pos.x+=20.0;
					pos.y+=advance;		// go down one line
					if(foundAtPos && pos.y >= find.y && pos.x >= find.x)
							{ // was in last fragment
								*foundAtPos=rangeLimit.location;
								foundAtPos=NULL;	// we have found it, so don't update again 
							}
				}
			case '\r':
				{ // start over at beginning of line but not a new line
					pos.x=origin.x;
					rangeLimit.location++;
					rangeLimit.length--;
					continue;
				}
			case ' ':
				{ // advance to next character position but don't draw a glyph
					float spacewidth;
					font=[_textStorage attribute:NSFontAttributeName atIndex:rangeLimit.location effectiveRange:NULL];
					if(!font)
						font=[NSFont userFontOfSize:0.0];		// use default system font
					spacewidth=[font widthOfString:@" "];		// width of space
					if(!draw && NSLocationInRange(rangeLimit.location, glyphsToShow))
						box=NSUnionRect(box, NSMakeRect(pos.x, pos.y, spacewidth, [self defaultLineHeightForFont:font]));
					pos.x+=spacewidth;
					if(foundAtPos && pos.y+[self defaultLineHeightForFont:font] >= find.y && pos.x >= find.x)
							{ // was in last fragment
								*foundAtPos=rangeLimit.location;
								foundAtPos=NULL;	// we have found it, so don't update again 
							}
					rangeLimit.location++;
					rangeLimit.length--;
					continue;
				}
			}
		attr=[_textStorage attributesAtIndex:rangeLimit.location longestEffectiveRange:&attribRange inRange:rangeLimit];
		para=[attr objectForKey:NSParagraphStyleAttributeName];
		if([para textBlocks])
			{ // table layout
				// get table
				// draw border&backgrounds
				// etc...
			}
		wordRange=[str rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] options:0 range:attribRange];	// embedded space in this range?
		if(wordRange.length != 0)
			{ // any whitespace found within attribute range - reduce attribute range to this word
			if(wordRange.location > attribRange.location)	
				attribRange.length=wordRange.location-attribRange.location;
			else
				attribRange.length=1;	// limit to the whitespace character itself
			}
		if(attribRange.location < glyphsToShow.location && NSMaxRange(attribRange) > glyphsToShow.location)
			attribRange.length=glyphsToShow.location-attribRange.location;	// vountarily stop at glyphsToShow.location
		else if(NSMaxRange(attribRange) > NSMaxRange(glyphsToShow))
			attribRange.length=NSMaxRange(glyphsToShow)-attribRange.location;	// voluntarily stop at NSMaxRange(glyphsToShow)
		// FIXME: this algorithm does not really word-wrap (only) if attributes change within a word
		substr=[str substringWithRange:attribRange];
		font=[attr objectForKey:NSFontAttributeName];
		if(!font)
			font=[NSFont userFontOfSize:0.0];		// use default system font
		width=[font widthOfString:substr];			// use metrics of unsubstituted font
		if(pos.x+width > origin.x+containerSize.width)
			{ // new word fragment does not fit into remaining line
			if(pos.x > origin.x)
				{ // we didn't just start on a newline, so insert another newline
				float advance=[self defaultLineHeightForFont:font];
#if 0
				NSLog(@"more");
#endif
				if(para)
					advance+=[para paragraphSpacing];
				switch([para lineBreakMode])
					{
						case NSLineBreakByWordWrapping:
						case NSLineBreakByCharWrapping:
						case NSLineBreakByClipping:
						case NSLineBreakByTruncatingHead:
						case NSLineBreakByTruncatingMiddle:
						case NSLineBreakByTruncatingTail:
							// FIXME: we can't handle that here because it is too late
							break;
					}
				pos.x=origin.x;
				pos.y+=advance;
				}
			while(width > containerSize.width && attribRange.length > 1)
				{ // does still not fit into box at all - we must truncate
				attribRange.length--;	// try with one character less
				substr=[str substringWithRange:attribRange];
				width=[font widthOfString:substr]; // get new width
				}
			}
		if(draw && NSLocationInRange(rangeLimit.location, glyphsToShow))
			{ // we want to draw really
				float alignment;
			if([ctxt isDrawingToScreen])
				font=[self substituteFontForFont:font];
			if(!font)
				NSLog(@"no screen font available");
			[font setInContext:ctxt];	// set font
			foreGround=[attr objectForKey:NSForegroundColorAttributeName];
#if 0
			NSLog(@"text color=%@", attrib);
#endif
			if(!foreGround)
				foreGround=[NSColor blackColor];
			[foreGround setStroke];
			[[attr objectForKey:NSStrokeColorAttributeName] setStroke];			// overwrite stroke color if defined differently
			[[attr objectForKey:NSBackgroundColorAttributeName] setFill];		// overwrite fill color
			baseline=0.0;
			if((attrib=[attr objectForKey:NSBaselineOffsetAttributeName]))
				baseline=[attrib floatValue];
			if((attrib=[attr objectForKey:NSSuperscriptAttributeName]))
				baseline+=3.0*[attrib intValue];
			[ctxt _setBaseline:baseline];	// update baseline
				
				switch([para alignment])
						{
							case NSLeftTextAlignment:
							case NSNaturalTextAlignment:
								alignment=0.0;
								break;
							case NSRightTextAlignment:
							case NSCenterTextAlignment:
							case NSJustifiedTextAlignment:
								// FIXME: we can't handle that here because it is too late
								alignment=0.0;
								break;
						}
				tm=[NSAffineTransform transform];	// identity
				if(flipped)
					[tm translateXBy:pos.x+alignment yBy:pos.y+[font ascender]];
				else
					[tm translateXBy:pos.x+alignment yBy:pos.y-[font ascender]];
				[ctxt _setTM:tm];
			_numberOfGlyphs=[substr length];
			if(!_glyphs || _numberOfGlyphs >= _glyphBufferCapacity)
				_glyphs=(NSGlyph *) objc_realloc(_glyphs, sizeof(_glyphs[0])*(_glyphBufferCapacity=_numberOfGlyphs+20));
			for(i=0; i<_numberOfGlyphs; i++)
				_glyphs[i]=[font _glyphForCharacter:[substr characterAtIndex:i]];		// translate and copy to glyph buffer
			
			[ctxt _drawGlyphs:[self _glyphsAtIndex:0] count:_numberOfGlyphs];	// -> (string) Tj
			
			/* FIXME:
				should be part of - (void) underlineGlyphRange:(NSRange)glyphRange 
underlineType:(int)underlineVal 
lineFragmentRect:(NSRect)lineRect 
lineFragmentGlyphRange:(NSRange)lineGlyphRange 
containerOrigin:(NSPoint)containerOrigin;
			
			should be part of - (void) strikeThroughGlyphRange:(NSRange)glyphRange 
underlineType:(int)underlineVal 
lineFragmentRect:(NSRect)lineRect 
lineFragmentGlyphRange:(NSRange)lineGlyphRange 
containerOrigin:(NSPoint)containerOrigin;
			
			- (void) drawStrikethroughForGlyphRange:(NSRange)glyphRange
strikethroughType:(int)strikethroughVal
baselineOffset:(float)baselineOffset
lineFragmentRect:(NSRect)lineRect
lineFragmentGlyphRange:(NSRange)lineGlyphRange
containerOrigin:(NSPoint)containerOrigin;
			
			and not be called here directly
				*/
			
			// fixme: setLineWidth:[font underlineThickness]
			if((style=[[attr objectForKey:NSUnderlineStyleAttributeName] intValue]))
				{ // underline
				float posy=pos.y+[font defaultLineHeightForFont]+baseline+[font underlinePosition];
#if 0
				NSLog(@"underline %x", style);
#endif
				[foreGround setStroke];
				[[attr objectForKey:NSUnderlineColorAttributeName] setStroke];		// change stroke color if defined differently
				[NSBezierPath strokeLineFromPoint:NSMakePoint(pos.x, posy) toPoint:NSMakePoint(pos.x+width, posy)];
				}
			if((style=[[attr objectForKey:NSStrikethroughStyleAttributeName] intValue]))
				{ // strike through
				float posy=pos.y+[font ascender]+baseline-[font xHeight]/2.0;
#if 0
				NSLog(@"strike through %x", style);
#endif
				[foreGround setStroke];
				[[attr objectForKey:NSStrikethroughColorAttributeName] setStroke];		// change stroke color if defined differently
				[NSBezierPath strokeLineFromPoint:NSMakePoint(pos.x, posy) toPoint:NSMakePoint(pos.x+width, posy)];
				}
			if((attrib=[attr objectForKey:NSLinkAttributeName]))
				{ // link
				float posy=pos.y+[font defaultLineHeightForFont]+baseline+[font underlinePosition];
				[[NSColor blueColor] setStroke];
				[NSBezierPath strokeLineFromPoint:NSMakePoint(pos.x, posy) toPoint:NSMakePoint(pos.x+width, posy)];
				}
			}
		if(!draw && NSLocationInRange(rangeLimit.location, glyphsToShow))
			box=NSUnionRect(box, NSMakeRect(pos.x, pos.y, width, [self defaultLineHeightForFont:font])); // increase bounding box
		pos.x+=width;	// advance to next fragment
		if(foundAtPos && pos.y+[self defaultLineHeightForFont:font] >= find.y && pos.x >= find.x)
				{ // was in last fragment
					float posx=pos.x-width;
					*foundAtPos=rangeLimit.location;
					while(YES)
							{ // find exact position
								substr=[str substringWithRange:NSMakeRange(*foundAtPos, 1)];	// get character
								posx+=[font widthOfString:substr];			// use metrics of current font
								if(posx >= find.x)
									break;
								(*foundAtPos)++;	// try next
							}
					foundAtPos=NULL;	// we have found it, so don't update again 
				}
		rangeLimit.location=NSMaxRange(attribRange);	// handle next fragment
		rangeLimit.length-=attribRange.length;
		}
	if(draw)
		{
		[ctxt _endText];
#if 0		// testing
		[[NSColor redColor] set];
		if(flipped)
			NSFrameRect((NSRect) { origin, containerSize });
		else
			NSFrameRect((NSRect) { { origin.x, origin.y-containerSize.height }, containerSize });
#endif	
		}
	return box;
}

- (void) addTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)range;
{
	NIMP;
}

- (void) addTextContainer:(NSTextContainer *)container;
{
	[_textContainers addObject:container];
}

- (NSSize) attachmentSizeForGlyphAtIndex:(unsigned)index;
{
	NIMP;
	return NSZeroSize;
}

- (BOOL) backgroundLayoutEnabled; { return _backgroundLayoutEnabled; }

- (NSRect) boundingRectForGlyphRange:(NSRange) glyphRange 
					 inTextContainer:(NSTextContainer *) container;
{
	glyphRange=NSIntersectionRange(glyphRange, [self glyphRangeForTextContainer:container]);	// only the range drawn in this container
	return [self _draw:NO glyphsForGlyphRange:glyphRange atPoint:NSZeroPoint findPoint:NSZeroPoint foundAtPos:NULL];
}

- (NSRect) boundsRectForTextBlock:(NSTextBlock *)block atIndex:(unsigned)index effectiveRange:(NSRangePointer)range;
{
	NIMP;
	return NSZeroRect;
}

- (NSRect) boundsRectForTextBlock:(NSTextBlock *)block glyphRange:(NSRange)range;
{
	NIMP;
	return NSZeroRect;
}

- (unsigned) characterIndexForGlyphAtIndex:(unsigned)glyphIndex;
{
	// FIXME:
	return glyphIndex;
}

- (NSRange) characterRangeForGlyphRange:(NSRange)glyphRange actualGlyphRange:(NSRangePointer)actualGlyphRange;
{
	// FIXME:
	return glyphRange;
}

- (NSImageScaling) defaultAttachmentScaling; { return _defaultAttachmentScaling; }

- (float) defaultLineHeightForFont:(NSFont *) font;
{
	return [font defaultLineHeightForFont];
}

- (id) delegate; { return _delegate; }

- (void) deleteGlyphsInRange:(NSRange)glyphRange;
{
	// check range
	memcpy(&_glyphs[glyphRange.location], &_glyphs[NSMaxRange(glyphRange)], sizeof(_glyphs[0])*glyphRange.length);
	_numberOfGlyphs-=glyphRange.length;
}

- (void) drawBackgroundForGlyphRange:(NSRange)glyphsToShow 
							 atPoint:(NSPoint)origin;
{ // draw selection range background
	if(glyphsToShow.length > 0)
			{
				NSTextContainer *textContainer=[self textContainerForGlyphAtIndex:glyphsToShow.location effectiveRange:NULL];	// this call could fill the cache if needed...
			// FIXME - should be done line by line!
				NSRect r=[self boundingRectForGlyphRange:glyphsToShow inTextContainer:textContainer];
				NSColor *color=[NSColor selectedTextBackgroundColor];
				[color set];
				// FIXME: this is correct only for single lines...
				[self fillBackgroundRectArray:&r count:1 forCharacterRange:glyphsToShow color:color];
			}
}

- (void) drawGlyphsForGlyphRange:(NSRange)glyphsToShow 
						 atPoint:(NSPoint)origin;		// top left of the text container (in flipped coordinates)
{
	[self _draw:YES glyphsForGlyphRange:glyphsToShow atPoint:origin findPoint:NSZeroPoint foundAtPos:NULL];
}

- (BOOL) drawsOutsideLineFragmentForGlyphAtIndex:(unsigned)index;
{
	NIMP;
	return NO;
}

- (void) drawStrikethroughForGlyphRange:(NSRange)glyphRange
					  strikethroughType:(int)strikethroughVal
						 baselineOffset:(float)baselineOffset
					   lineFragmentRect:(NSRect)lineRect
				 lineFragmentGlyphRange:(NSRange)lineGlyphRange
						containerOrigin:(NSPoint)containerOrigin;
{
	NIMP;
#if 0
	float posy=pos.y+[font ascender]+baselineOffset-[font xHeight]/2.0;
#if 0
	NSLog(@"strike through %x", style);
#endif
	[foreGround setStroke];
	[[attr objectForKey:NSStrikethroughColorAttributeName] setStroke];		// change stroke color if defined differently
	[NSBezierPath strokeLineFromPoint:NSMakePoint(pos.x, posy) toPoint:NSMakePoint(pos.x+width, posy)];
#endif				
}

- (void) drawUnderlineForGlyphRange:(NSRange)glyphRange 
					  underlineType:(int)underlineVal 
					 baselineOffset:(float)baselineOffset 
				   lineFragmentRect:(NSRect)lineRect 
			 lineFragmentGlyphRange:(NSRange)lineGlyphRange 
					containerOrigin:(NSPoint)containerOrigin;
{
	NIMP;
#if 0
	float posy=pos.y+[font defaultLineHeightForFont]+baselineOffset+[font underlinePosition];
#if 0
	NSLog(@"underline %x", style);
#endif
	[foreGround setStroke];
	[[attr objectForKey:NSUnderlineColorAttributeName] setStroke];		// change stroke color if defined differently
	[NSBezierPath strokeLineFromPoint:NSMakePoint(pos.x, posy) toPoint:NSMakePoint(pos.x+width, posy)];
#endif
}

- (NSRect) extraLineFragmentRect; { return _extraLineFragmentRect; }
- (NSTextContainer *) extraLineFragmentTextContainer; { return _extraLineFragmentContainer; }
- (NSRect) extraLineFragmentUsedRect; { return _extraLineFragmentUsedRect; }

- (void) fillBackgroundRectArray:(NSRectArray) rectArray count:(NSUInteger) rectCount forCharacterRange:(NSRange) charRange color:(NSColor *) color;
{ // charRange and color are for informational purposes - color must already be set
	NSRectFillList(rectArray, rectCount);
}

- (NSTextView *) firstTextView;
{
	if(!_firstTextView)
		{
		if([_textContainers count] == 0)
			return nil;
		_firstTextView=[[_textContainers objectAtIndex:0] textView];
		}
	return _firstTextView;
}

- (unsigned) firstUnlaidCharacterIndex;
{
	return _firstUnlaidCharacterIndex;
}

- (unsigned) firstUnlaidGlyphIndex;
{
	return _firstUnlaidGlyphIndex;
}

- (float) fractionOfDistanceThroughGlyphForPoint:(NSPoint)aPoint inTextContainer:(NSTextContainer *)aTextContainer;
{
	NIMP;
	return 0;
}

- (void) getFirstUnlaidCharacterIndex:(unsigned *)charIndex 
						   glyphIndex:(unsigned *)glyphIndex;
{
	*charIndex=_firstUnlaidCharacterIndex;
	*glyphIndex=_firstUnlaidGlyphIndex;
}

- (unsigned) getGlyphs:(NSGlyph *)glyphArray range:(NSRange)glyphRange;
{
	NSAssert(NSMaxRange(glyphRange) <= _numberOfGlyphs, @"invalid glyph range");
	// if(NSMaxRange(glyphRange) > _firstUnlaidGlyphIndex)
	//   do layout
	// don't copy non-printing glyphs (newline)
	memcpy(glyphArray, &_glyphs[glyphRange.location], sizeof(*glyphArray)*glyphRange.length);
	glyphArray[glyphRange.length]=0;	// adds 0-termination (buffer must have enough capacity!)
	return glyphRange.length;	// FIXME: don't include newlines
}

- (unsigned) getGlyphsInRange:(NSRange)glyphsRange
					   glyphs:(NSGlyph *)glyphBuffer
			 characterIndexes:(unsigned *)charIndexBuffer
			glyphInscriptions:(NSGlyphInscription *)inscribeBuffer
				  elasticBits:(BOOL *)elasticBuffer;
{
	NIMP;
	return 0;
}

- (unsigned) getGlyphsInRange:(NSRange)glyphsRange
					   glyphs:(NSGlyph *)glyphBuffer
			 characterIndexes:(unsigned *)charIndexBuffer
			glyphInscriptions:(NSGlyphInscription *)inscribeBuffer
				  elasticBits:(BOOL *)elasticBuffer
				   bidiLevels:(unsigned char *)bidiLevelBuffer;
{
	NIMP;
	return 0;
}

- (NSGlyph) glyphAtIndex:(unsigned)glyphIndex;
{
	if(glyphIndex < _numberOfGlyphs)
		return _glyphs[glyphIndex];
	// raise NSRangeException
	return NSNullGlyph;
}

- (NSGlyph) glyphAtIndex:(unsigned)glyphIndex isValidIndex:(BOOL *)isValidIndex;
{
	BOOL isValid=glyphIndex < _numberOfGlyphs;
	if(isValidIndex)
		*isValidIndex=isValid;
	if(isValid)
		return _glyphs[glyphIndex];
	return NSNullGlyph;
}

- (NSGlyphGenerator *) glyphGenerator;
{
	if(!_glyphGenerator)
		_glyphGenerator=[[NSGlyphGenerator sharedGlyphGenerator] retain];
	return _glyphGenerator;
}

- (unsigned int) glyphIndexForPoint:(NSPoint)aPoint inTextContainer:(NSTextContainer *)aTextContainer;
{
	return [self glyphIndexForPoint:aPoint inTextContainer:aTextContainer fractionOfDistanceThroughGlyph:NULL];
}

- (unsigned int) glyphIndexForPoint:(NSPoint)aPoint
				inTextContainer:(NSTextContainer *)textContainer
 fractionOfDistanceThroughGlyph:(float *)partialFraction;
{
	unsigned int pos;
	[self _draw:NO glyphsForGlyphRange:[self glyphRangeForTextContainer:textContainer] atPoint:NSZeroPoint findPoint:aPoint foundAtPos:&pos];
	if(partialFraction)
		*partialFraction=0.0;
	return pos;
}

- (NSRange) glyphRangeForBoundingRect:(NSRect)bounds 
					  inTextContainer:(NSTextContainer *)container;
{
	// if needs layout...
	return [self glyphRangeForBoundingRectWithoutAdditionalLayout:bounds inTextContainer:container];
}

- (NSRange) glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)bounds 
											 inTextContainer:(NSTextContainer *)container;
{
	// FIXME:
	NSRange rng=[self glyphRangeForTextContainer:container];
	// reduce range for first and last character as needed
	return rng;
}

- (NSRange) glyphRangeForCharacterRange:(NSRange)charRange actualCharacterRange:(NSRange *)actualCharRange;
{
	// FIXME:
	if(actualCharRange)
		*actualCharRange=charRange;
#if 0
	NSLog(@"glyphRangeForCharacterRange = %@", NSStringFromRange(charRange));
#endif
	return charRange;
}

- (NSRange) glyphRangeForTextContainer:(NSTextContainer *)container;
{
	// FIXME:
	// is this a basic or a derived method?
	// I guess it is a quite basic mapping from text containers to glyph ranges
	// it may be based on glyphRangeForBoundingRectWithoutAdditionalLayout?
	return NSMakeRange(0, [_textStorage length]);	// assume we have only one text container
}

- (float) hyphenationFactor; { return _hyphenationFactor; }

- (id) init;
{
	if((self=[super init]))
		{
		_textContainers=[NSMutableArray new];
		_usesScreenFonts=NO;
		}
	return self;
}

- (void) dealloc;
{
	if(_glyphs)
		objc_free(_glyphs);
	[_glyphGenerator release];
	[_textContainers release];
	[_typesetter release];
	[super dealloc];
}

- (void) insertGlyph:(NSGlyph)glyph atGlyphIndex:(unsigned)glyphIndex characterIndex:(unsigned)charIndex;
{
	[self insertGlyphs:&glyph length:1 forStartingGlyphAtIndex:glyphIndex characterIndex:charIndex];
}

- (void) insertTextContainer:(NSTextContainer *)container atIndex:(unsigned)index;
{
	[_textContainers insertObject:container atIndex:index];
	if(index == 0)
		_firstTextView=[container textView];	// has changed
}

- (int) intAttribute:(int)attributeTag forGlyphAtIndex:(unsigned)glyphIndex;
{
	NIMP;
	return 0;
}

- (void) invalidateDisplayForCharacterRange:(NSRange)charRange;
{
	[self invalidateGlyphsForCharacterRange:charRange changeInLength:0 actualCharacterRange:NULL];
}

- (void) invalidateDisplayForGlyphRange:(NSRange)glyphRange;
{
	NIMP;
	// [textview setNeedsDisplayInRect: ]
}

- (void) invalidateGlyphsForCharacterRange:(NSRange)charRange changeInLength:(int)delta actualCharacterRange:(NSRange *)actualCharRange;
{
	NIMP;
}

- (void) invalidateLayoutForCharacterRange:(NSRange)charRange isSoft:(BOOL)flag actualCharacterRange:(NSRange *)actualCharRange;
{
	NIMP;
}

- (BOOL) isValidGlyphIndex:(unsigned)glyphIndex;
{
	return glyphIndex < _numberOfGlyphs;
}

- (BOOL) layoutManagerOwnsFirstResponderInWindow:(NSWindow *)aWindow;
{ // check if firstResponder is a NSTextView and we are the layoutManager
	NSResponder *f=[aWindow firstResponder];
	if([f respondsToSelector:@selector(layoutManager)])
		return [(NSTextView *) f layoutManager] == self;
	return NO;
}

- (NSRect) layoutRectForTextBlock:(NSTextBlock *)block
						  atIndex:(unsigned)glyphIndex
				   effectiveRange:(NSRangePointer)effectiveGlyphRange;
{
	NIMP;
	return NSZeroRect;
}

- (NSRect) layoutRectForTextBlock:(NSTextBlock *)block
					   glyphRange:(NSRange)glyphRange;
{
	NIMP;
	return NSZeroRect;
}

- (NSRect) lineFragmentRectForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange;
{
	NIMP;
	return NSZeroRect;
}

- (NSRect) lineFragmentUsedRectForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange;
{
	NIMP;
	return NSZeroRect;
}

- (NSPoint) locationForGlyphAtIndex:(unsigned)glyphIndex;
{
	NIMP;
	return NSZeroPoint;
}

- (BOOL) notShownAttributeForGlyphAtIndex:(unsigned) glyphIndex;
{
	NIMP;
	return NO;
}

- (unsigned) numberOfGlyphs;
{
	// generate all glyphs
	return _numberOfGlyphs;
}

- (NSRange) rangeOfNominallySpacedGlyphsContainingIndex:(unsigned)glyphIndex;
{
	NIMP;
	return NSMakeRange(0, 0);
}

- (NSRect*) rectArrayForCharacterRange:(NSRange)charRange 
		  withinSelectedCharacterRange:(NSRange)selCharRange 
					   inTextContainer:(NSTextContainer *)container 
							 rectCount:(unsigned *)rectCount;
{
	static NSRect rect;
	NIMP;
	return &rect;
}

- (NSRect*) rectArrayForGlyphRange:(NSRange)glyphRange 
		  withinSelectedGlyphRange:(NSRange)selGlyphRange 
				   inTextContainer:(NSTextContainer *)container 
						 rectCount:(unsigned *)rectCount;
{
	static NSRect rect;
	NIMP;
	return &rect;
}

- (void) removeTemporaryAttribute:(NSString *)name forCharacterRange:(NSRange)charRange;
{
	NIMP;
}

- (void) removeTextContainerAtIndex:(unsigned)index;
{
	if(index == 0)
		_firstTextView=nil;	// might have changed
	[_textContainers removeObjectAtIndex:index];
}

- (void) replaceGlyphAtIndex:(unsigned)glyphIndex withGlyph:(NSGlyph)newGlyph;
{
	// FIXME: error checking
	_glyphs[glyphIndex]=newGlyph;
}

- (void) replaceTextStorage:(NSTextStorage *)newTextStorage;
{
	[_textStorage removeLayoutManager:self];
	[newTextStorage removeLayoutManager:self];	// this calls setTextStorage
}

- (NSView *) rulerAccessoryViewForTextView:(NSTextView *)aTextView
							paragraphStyle:(NSParagraphStyle *)paraStyle
									 ruler:(NSRulerView *)aRulerView
								   enabled:(BOOL)flag;
{
	return NIMP;
}

- (NSArray*) rulerMarkersForTextView:(NSTextView *)view 
					  paragraphStyle:(NSParagraphStyle *)style 
							   ruler:(NSRulerView *)ruler;
{
	return NIMP;
}

- (void) setAttachmentSize:(NSSize)attachmentSize forGlyphRange:(NSRange)glyphRange;
{
	// DEPRECATED
	NIMP;
}

- (void) setBackgroundLayoutEnabled:(BOOL)flag; { _backgroundLayoutEnabled=flag; }

- (void) setBoundsRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;
{
	NIMP;
}

- (void) setCharacterIndex:(unsigned)charIndex forGlyphAtIndex:(unsigned)glyphIndex;
{
	NIMP;
}

- (void) setDefaultAttachmentScaling:(NSImageScaling)scaling; { _defaultAttachmentScaling=scaling; }

- (void) setDelegate:(id)obj; { _delegate=obj; }

- (void) setDrawsOutsideLineFragment:(BOOL)flag forGlyphAtIndex:(unsigned)glyphIndex;
{
	NIMP;
}

- (void) setExtraLineFragmentRect:(NSRect)fragmentRect usedRect:(NSRect)usedRect textContainer:(NSTextContainer *)container;
{
	NIMP;
}

- (void) setGlyphGenerator:(NSGlyphGenerator *)gg; { ASSIGN(_glyphGenerator, gg); }

- (void) setHyphenationFactor:(float)factor; { _hyphenationFactor=factor; }

- (void) setLayoutRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;
{
	NIMP;
}

- (void) setLineFragmentRect:(NSRect)fragmentRect forGlyphRange:(NSRange)glyphRange usedRect:(NSRect)usedRect;
{
	NIMP;
}

- (void) setLocation:(NSPoint)location forStartOfGlyphRange:(NSRange)glyphRange;
{
	NIMP;
}

- (void) setNotShownAttribute:(BOOL)flag forGlyphAtIndex:(unsigned)glyphIndex;
{
	NIMP;
}

// FIXME: does this trigger relayout?

- (void) setShowsControlCharacters:(BOOL)flag; { if(flag) _layoutOptions |= NSShowControlGlyphs; else _layoutOptions &= ~NSShowControlGlyphs; }

- (void) setShowsInvisibleCharacters:(BOOL)flag; { if(flag) _layoutOptions |= NSShowInvisibleGlyphs; else _layoutOptions &= ~NSShowInvisibleGlyphs; }

- (void) setTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)charRange;
{
	NIMP;
}

- (void) setTextContainer:(NSTextContainer *)container forGlyphRange:(NSRange)glyphRange;
{
	NIMP;
}

- (void) setTextStorage:(NSTextStorage *)ts; { _textStorage=ts; }	// The textStorage owns the layout manager(s)
- (void) setTypesetter:(NSTypesetter *)ts; { ASSIGN(_typesetter, ts); }
- (void) setTypesetterBehavior:(NSTypesetterBehavior)behavior; { _typesetterBehavior=behavior; }
- (void) setUsesScreenFonts:(BOOL)flag; { _usesScreenFonts=flag; }

- (void) showAttachmentCell:(NSCell *)cell inRect:(NSRect)rect characterIndex:(unsigned)attachmentIndex;
{
	NIMP;
}

- (void) showPackedGlyphs:(char *) glyphs
									 length:(unsigned) glyphLen
							 glyphRange:(NSRange) glyphRange
									atPoint:(NSPoint) point
										 font:(NSFont *) font
										color:(NSColor *) color
			 printingAdjustment:(NSSize) adjust;
{
	// color and font should already be set
	NIMP;
}

- (BOOL) showsControlCharacters; { return (_layoutOptions&NSShowControlGlyphs) != 0; }
- (BOOL) showsInvisibleCharacters; { return (_layoutOptions&NSShowInvisibleGlyphs) != 0; }

- (void) strikethroughGlyphRange:(NSRange)glyphRange
			   strikethroughType:(int)strikethroughVal
				lineFragmentRect:(NSRect)lineRect
		  lineFragmentGlyphRange:(NSRange)lineGlyphRange
				 containerOrigin:(NSPoint)containerOrigin;
{
	NIMP;
	// call drawStrikeThrough...
}

- (NSFont *) substituteFontForFont:(NSFont *) originalFont;
{
	NSFont *newFont;
	if(_usesScreenFonts)
		{
		// FIXME: check if any NSTextView is scaled or rotated
		newFont=[originalFont screenFontWithRenderingMode:NSFontDefaultRenderingMode];	// use matching screen font based on defaults settings
		if(newFont)
			return newFont;
		}
	return originalFont;
}

- (NSDictionary *) temporaryAttributesAtCharacterIndex:(unsigned)charIndex effectiveRange:(NSRangePointer)effectiveCharRange;
{
	return NIMP;
}

- (void) textContainerChangedGeometry:(NSTextContainer *)container;
{
	NIMP;
}

- (void) textContainerChangedTextView:(NSTextContainer *)container;
{
	NIMP;
}

// FIXME

// we should circle through containers touched by range
// NOTE: the container rect might be very large if the container covers several 10-thousands lines
// therefore, this algorithm must be very efficient
// and there might be several thousand containers...

- (NSTextContainer *) textContainerForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange;
{
	NSTextContainer *container=[_textContainers objectAtIndex:0];	// first one
	NSTextView *tv=[container textView];
	if(_textStorageChanged && tv)
		{
		_textStorageChanged=NO;
#if 0
		NSLog(@"sizing text view to changed textStorage");
#endif
		[tv didChangeText];	// let others know...
		[tv sizeToFit];	// size... - warning: this may be recursive!
		}
	return container;
}

- (NSTextContainer *) textContainerForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRangePointer)effectiveGlyphRange withoutAdditionalLayout:(BOOL)flag
{
	return NIMP;
}

- (NSArray *) textContainers; { return _textContainers; }
- (NSTextStorage *) textStorage; { return _textStorage; }

- (void) textStorage:(NSTextStorage *)str edited:(unsigned)editedMask range:(NSRange)newCharRange changeInLength:(int)delta invalidatedRange:(NSRange)invalidatedCharRange;
{
	if(!_textStorageChanged)
			{ // first call
//				NSRange glyphsToShow=NSMakeRange(0, [str length]);	// all...
//				NSTextContainer *container=[self textContainerForGlyphAtIndex:newCharRange.location effectiveRange:NULL];
//				NSTextView *tv=[container textView];
#if 0
				NSLog(@"textStorage edited");
#endif
				_textStorageChanged=YES;
			}
}

- (NSTextView *) textViewForBeginningOfSelection;
{
	return NIMP;
}

- (NSTypesetter *) typesetter; { return _typesetter; }
- (NSTypesetterBehavior) typesetterBehavior; { return _typesetterBehavior; }

- (void) underlineGlyphRange:(NSRange)glyphRange 
			   underlineType:(int)underlineVal 
			lineFragmentRect:(NSRect)lineRect 
			   lineFragmentGlyphRange:(NSRange)lineGlyphRange 
			 containerOrigin:(NSPoint)containerOrigin;
{
	NIMP;
	// call drawStrikeThrough...
}

- (NSRect) usedRectForTextContainer:(NSTextContainer *)container;
{
	NSRange range=[self glyphRangeForTextContainer:container];
	return [self boundingRectForGlyphRange:range inTextContainer:container];
}

- (BOOL) usesScreenFonts; { return _usesScreenFonts; }

#pragma mark NSCoder

- (void) encodeWithCoder:(NSCoder *) coder;
{
//	[super encodeWithCoder:coder];
}

- (id) initWithCoder:(NSCoder *) coder;
{
	int lmFlags=[coder decodeInt32ForKey:@"NSLMFlags"];
#if 0
	NSLog(@"LMFlags=%d", lmFlags);
	NSLog(@"%@ initWithCoder: %@", self, coder);
#endif
	[self setDelegate:[coder decodeObjectForKey:@"NSDelegate"]];
	_textContainers=[[coder decodeObjectForKey:@"NSTextContainers"] retain];
	_textStorage=[[coder decodeObjectForKey:@"NSTextStorage"] retain];
	_usesScreenFonts=NO;
#if 0
	NSLog(@"%@ done", self);
#endif
	return self;
}

#pragma mark NSGlyphStorage
// methods for @protocol NSGlyphStorage

- (NSAttributedString *) attributedString; { return _textStorage; }

- (unsigned int) layoutOptions; { return _layoutOptions; }

- (void ) insertGlyphs:(const NSGlyph *) glyphs
				length:(unsigned int) length
		forStartingGlyphAtIndex:(unsigned int) glyph
		characterIndex:(unsigned int) index;
{
	// mange _glyphs container
}

- (void) setIntAttribute:(int)attributeTag value:(int)val forGlyphAtIndex:(unsigned)glyphIndex;
{
	// manage _intAttributes container
	NIMP;
}

@end

