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

#define OLD	1

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
							glyphIndex:(unsigned int *) glyphIndex
						characterIndex:(unsigned int *) index;
{
	NSAttributedString *astr=[storage attributedString];	// get string to layout
	NSString *str=[astr string];
	// could be optimized a little by getting and consuming the effective range of attributes
	while(num > 0)
		{
		NSRange attribRange;	// range of same attributes
		NSDictionary *attribs=[astr attributesAtIndex:*index effectiveRange:&attribRange];
		NSFont *font=[attribs objectForKey:NSFontAttributeName];
		attribRange.length-=(*index)-attribRange.location;	// characters with same attributes before we start
		if(!font) font=[NSFont userFontOfSize:0.0];		// use default system font
		font=[(NSLayoutManager *) storage substituteFontForFont:font];
		while(num > 0 && attribRange.length-- > 0)
			{ // process this attribute range but not more than requested
				NSGlyph glyphs[2];
				unichar c=[str characterAtIndex:*index];
				int numGlyphs=1;
				// should map some unicode character ranges (Unicode General Category C* and U200B (ZERO WIDTH SPACE) to NSControlGlyph
				if(c == 0x200b)
					glyphs[0]=NSControlGlyph;
				else
					glyphs[0]=[font _glyphForCharacter:c];
				// if we need multiple glyphs for a single character, insert more than one!
				// but how do we know that??? Does the font ever report that???
				[storage insertGlyphs:glyphs length:numGlyphs forStartingGlyphAtIndex:*glyphIndex characterIndex:*index];
				(*glyphIndex)+=numGlyphs;	// inc. by number of glyphs
				(*index)++;
				num--;
			}
		}
}

@end

@implementation NSTypesetter

+ (NSTypesetterBehavior) defaultTypesetterBehavior;
{
	return NSTypesetterLatestBehavior;
}

+ (NSSize) printingAdjustmentInLayoutManager:(NSLayoutManager *) manager 
				forNominallySpacedGlyphRange:(NSRange) range 
								packedGlyphs:(const unsigned char *) glyphs
									   count:(NSUInteger) count;
{
	NIMP;
	return NSZeroSize;
}

static id _sharedSystemTypesetter;

+ (id) sharedSystemTypesetter;
{
	return [self sharedSystemTypesetterForBehavior:[self defaultTypesetterBehavior]];
}

+ (id) sharedSystemTypesetterForBehavior:(NSTypesetterBehavior) behavior;
{ // FIXME: there should be an array of singletons for all potential behaviors
	if(!_sharedSystemTypesetter)
		{
		_sharedSystemTypesetter=[[self alloc] init];
		[_sharedSystemTypesetter setTypesetterBehavior:[NSTypesetter defaultTypesetterBehavior]];		
		}
	return _sharedSystemTypesetter;
}

- (NSTypesetterControlCharacterAction) actionForControlCharacterAtIndex:(NSUInteger) location;
{ // default action - can be overwritten in subclass typesetter
	// modify action based on
	[_layoutManager showsControlCharacters];
	[_layoutManager showsInvisibleCharacters];
	switch([[_attributedString string] characterAtIndex:location]) {
		case '\t': return NSTypesetterHorizontalTabAction;
		case '\n': return NSTypesetterParagraphBreakAction;
		case ' ': return NSTypesetterWhitespaceAction;
		// case ' ': return NSTypesetterControlCharacterAction;	// how does this relate to NSControlGlyph?
		// case ' ': return NSTypesetterContainerBreakAction;
		case NSAttachmentCharacter: return 0;
	}
	return 0;
}

- (NSAttributedString *) attributedString;
{
	return _attributedString;
}

- (NSDictionary *) attributesForExtraLineFragment;
{
	NSDictionary *d=[[_layoutManager firstTextView] typingAttributes];
	if(!d)
		;
	return d;
}

- (CGFloat) baselineOffsetInLayoutManager:(NSLayoutManager *) manager glyphIndex:(NSUInteger) index;
{
	// FIXME: this depends on the NSFont??
	// or is it stored/cached for each glyph in the typesetter???
	return 0.0;
}

- (void) beginLineWithGlyphAtIndex:(NSUInteger) index;
{
	[self setLineFragmentPadding:[_currentTextContainer lineFragmentPadding]];
	return;
}

- (void) beginParagraph;
{
	_currentParagraphStyle=[_attributedString attribute:NSParagraphStyleAttributeName atIndex:_paragraphCharacterRange.location effectiveRange:&_paragraphCharacterRange];
	if(!_currentParagraphStyle)
		_currentParagraphStyle=[NSParagraphStyle defaultParagraphStyle];	// none specified
	[self setParagraphGlyphRange:[_layoutManager glyphRangeForCharacterRange:_paragraphCharacterRange actualCharacterRange:NULL] separatorGlyphRange:NSMakeRange(0, 0)];
}

- (BOOL) bidiProcessingEnabled;
{
	return _bidiProcessingEnabled;
}

- (NSRect) boundingBoxForControlGlyphAtIndex:(NSUInteger) glyph 
							forTextContainer:(NSTextContainer *) container 
						proposedLineFragment:(NSRect) rect 
							   glyphPosition:(NSPoint) position 
							  characterIndex:(NSUInteger) index;
{
	return NSZeroRect;
}

- (NSRange) characterRangeForGlyphRange:(NSRange) range 
					   actualGlyphRange:(NSRangePointer) rangePt;
{
	return [_layoutManager characterRangeForGlyphRange:range actualGlyphRange:rangePt];
}

- (NSParagraphStyle *) currentParagraphStyle; { return _currentParagraphStyle; }
- (NSTextContainer *) currentTextContainer; { return _currentTextContainer; }

- (void) deleteGlyphsInRange:(NSRange) range;
{
	[_layoutManager deleteGlyphsInRange:range];
}

- (void) endLineWithGlyphRange:(NSRange) range;
{ // do adjustments (left, right, center, justfication) and apply lfr/lfur to line range
	// center: shift used rect right by half difference
	// right: shift used rect right by full difference
	// justify: distribute difference on space characters and kerning
	[_layoutManager setTextContainer:[self currentTextContainer] forGlyphRange:_paragraphGlyphRange];
}

- (void) endParagraph;
{
	NIMP;
}

- (NSUInteger) getGlyphsInRange:(NSRange) range 
						 glyphs:(NSGlyph *) glyphs 
			   characterIndexes:(NSUInteger *) idxs 
			  glyphInscriptions:(NSGlyphInscription *) inscBuffer 
					elasticBits:(BOOL *) flag 
					 bidiLevels:(unsigned char *) bidiLevels;
{
	return [_layoutManager getGlyphsInRange:range
									 glyphs:glyphs
						   characterIndexes:idxs
						  glyphInscriptions:inscBuffer
								elasticBits:flag];
}

- (void) getLineFragmentRect:(NSRectPointer) fragRect 
					usedRect:(NSRectPointer) fragUsedRect 
forParagraphSeparatorGlyphRange:(NSRange) range 
			atProposedOrigin:(NSPoint) origin;
{ // for blank lines
	NSRect rr;
	NSRect proposedRect;
	[self getLineFragmentRect:fragRect
					 usedRect:fragUsedRect
				remainingRect:&rr
	  forStartingGlyphAtIndex:range.location
				 proposedRect:proposedRect
				  lineSpacing:[self lineSpacingAfterGlyphAtIndex:_paragraphGlyphRange.location withProposedLineFragmentRect:proposedRect]
	   paragraphSpacingBefore:[self paragraphSpacingBeforeGlyphAtIndex:_paragraphGlyphRange.location withProposedLineFragmentRect:proposedRect]
		paragraphSpacingAfter:[self paragraphSpacingAfterGlyphAtIndex:_paragraphGlyphRange.location withProposedLineFragmentRect:proposedRect]];
	[self currentParagraphStyle];
	[self lineFragmentPadding];	// why again???
}

- (void) getLineFragmentRect:(NSRectPointer) lineFragmentRect 
					usedRect:(NSRectPointer) lineFragmentUsedRect 
			   remainingRect:(NSRectPointer) remRect 
	 forStartingGlyphAtIndex:(NSUInteger) startIndex 
				proposedRect:(NSRect) propRect	// remaining space needed up to the end of the paragraph
				 lineSpacing:(CGFloat) spacing 
	  paragraphSpacingBefore:(CGFloat) paragSpacBefore 
	   paragraphSpacingAfter:(CGFloat) paragSpacAfter;
{ // for lines
	int sweep;
	// FIXME: should also set up the initial position to the left or right?
	switch([_currentParagraphStyle baseWritingDirection]) {
		case NSWritingDirectionNatural:
		default:
		case NSWritingDirectionLeftToRight: sweep=NSLineSweepRight; break;
		case NSWritingDirectionRightToLeft: sweep=NSLineSweepLeft; break;
	}
	*lineFragmentRect=[_currentTextContainer lineFragmentRectForProposedRect:propRect sweepDirection:sweep movementDirection:NSLineMovesDown remainingRect:remRect];
	*lineFragmentUsedRect=*lineFragmentRect;
	// FIXME: how can this be smaller if we take the proposed rect???
	lineFragmentRect->size.width=MIN(NSWidth(*lineFragmentRect), NSWidth(propRect));	// reduce to what was proposed
	// handle adjustments here by shifting the lfur?
}

- (NSRange) glyphRangeForCharacterRange:(NSRange) range 
				   actualCharacterRange:(NSRangePointer) rangePt;
{
	return [_layoutManager glyphRangeForCharacterRange:range actualCharacterRange:rangePt];
}

- (float) hyphenationFactor;
{
	return [_layoutManager hyphenationFactor];
}

- (float) hyphenationFactorForGlyphAtIndex:(NSUInteger) index;
{ // can be overridden in subclasses
	return [self hyphenationFactor];
}

- (UTF32Char) hyphenCharacterForGlyphAtIndex:(NSUInteger) index;
{
	return '-';
}

- (void) insertGlyph:(NSGlyph) glyph atGlyphIndex:(NSUInteger) index characterIndex:(NSUInteger) charIdx;
{ // used for hyphenation and keeps some caches in sync...
	[_layoutManager insertGlyphs:&glyph length:1 forStartingGlyphAtIndex:index characterIndex:charIdx];
}

- (NSRange) layoutCharactersInRange:(NSRange) range
				   forLayoutManager:(NSLayoutManager *) manager
	   maximumNumberOfLineFragments:(NSUInteger) maxLines;
{ // this is the main layout function - we assume that the Glyphs are already generated and character indexes are assigned
	NSUInteger nextGlyph;
	NSRange r={ 0, [_attributedString length] };
	[self layoutGlyphsInLayoutManager:manager startingAtGlyphIndex:[manager glyphIndexForCharacterAtIndex:range.location] maxNumberOfLineFragments:maxLines nextGlyphIndex:&nextGlyph];
	return r;
}

- (void) layoutGlyphsInLayoutManager:(NSLayoutManager *) manager 
				startingAtGlyphIndex:(NSUInteger) startIndex 
			maxNumberOfLineFragments:(NSUInteger) maxLines 
					  nextGlyphIndex:(NSUInteger *) nextGlyph; 
{ // documentation says that this is the main function called by NSLayoutManager
	_maxNumberOfLineFragments=maxLines;	// set up limitation counter

//	_currentTextContainer=

	/* FIXME:
	appears to setup everything and then call layoutParagraphAtPoint:

	 splitting into pragraphs is probably done here
	 
	 loop over all pragraphs:
	 [self setParagraphGlyphRange:<#(NSRange)paragRange#> separatorGlyphRange:<#(NSRange)sepRange#>];
	 [self layoutParagraphAtPoint:]
	 check if we need a new text container and continue

	*/
		
	// MOVE this to layoutParagraphAtPoint: to lay out current paragraph into current text container starting at current position...
	
	
	NSString *str=[_attributedString string];
	unsigned int options=[manager layoutOptions];	 // NSShowControlGlyphs, NSShowInvisibleGlyphs, NSWantsBidiLevels
	NSGlyph previous=0;
	NSTextContainer *container;
	NSPoint location;	// relative location within line fragment rect
	NSRect lfr;		// current line fragment rect
	_layoutManager=manager;
	if(startIndex > 0)
		{ // continue previous
			container=[_layoutManager textContainerForGlyphAtIndex:startIndex-1 effectiveRange:NULL];
		location=[_layoutManager locationForGlyphAtIndex:startIndex-1];
		// update location!?!
		lfr=[_layoutManager lineFragmentRectForGlyphAtIndex:startIndex-1 effectiveRange:NULL];
		}
	else
		{
		container=[[_layoutManager textContainers] objectAtIndex:0];
		location=NSZeroPoint;
		lfr=(NSRect) { NSZeroPoint, [container containerSize] };
		}

	while(startIndex < [_layoutManager numberOfGlyphs] && _maxNumberOfLineFragments > 0)
		{
		startIndex = [self layoutParagraphAtPoint:&location];
		// check for end due to end of container
		// switch to next container (if possible)
		}
	// we should fill the current TextContainer with line fragment rects
	// and ask the delegate if we need another one
	// if it can be streched, call [textView sizeToFit];	// size... - warning: this may be recursive!
	
	// handle NSTextTable and call -[NSTextTableBlock boundsRectForContentRect:inRect:textContainer:characterRange:]
	
	// FIXME: numberOfGlyphs calls layout!!!
	// FIXME: handle attribute runs like in glyph Generator!
	
	/*
	 In addition to the line fragment rectangle itself, the typesetter returns a
	 rectangle called the used rectangle. This is the portion of the line fragment
	 rectangle that actually contains glyphs or other marks to be drawn. By convention,
	 both rectangles include the line fragment padding and the interline space calculated
	 from the font�s line height metrics and the paragraph�s line spacing parameters.
	 However, the paragraph spacing (before and after) and any space added around the
	 text, such as that caused by center-spaced text, are included only in the line
	 fragment rectangle and not in the used rectangle.
	 */
	
	// if the last character did not end up in a line fragment rect, define an extra line fragment
	// [self getLineFragmentRect:&lfr usedRect:&ulfr forParagraphSeparatorGlyphRange:NSMakeRange(glyph, 0) atProposedOrigin:origin];
	// [_layoutManager setExtraLineFragmentRect:lfr usedRect:ulfr textContainer:aTextContainer];
	_layoutManager=nil;
}

- (NSLayoutManager *) layoutManager;
{
	return _layoutManager;
}

// NOTE: there may be no glyph corresponding to the \n character!!!
// i.e. we can't find a \n character at the location defined by glyphs
// FIXME: make this useable for layout of table cells (which are sub-rects within a NSTextContainer)

- (NSUInteger) layoutParagraphAtPoint:(NSPointPointer) lfrOrigin;
{ // layout glyphs until end of paragraph; creates full line fragments
	NSString *str=[_attributedString string];
	NSUInteger startIndex=_paragraphGlyphRange.location;
	NSRect proposedRect=(NSRect) { *lfrOrigin, [_currentTextContainer containerSize] };
	NSPoint location;
	NSRect lfr, lfur, rr;
	// reduce size?
	[self beginParagraph];
	while(_maxNumberOfLineFragments-- > 0)
		{ // for each line (fragment)
			CGFloat baselineOffset;
			[self beginLineWithGlyphAtIndex:startIndex];
			while(_paragraphCharacterRange.location < [_attributedString length])
				{
				NSRect box;
				NSRect ulfr;	// used line fragment rect
				NSGlyph previous=NSNullGlyph;
				NSRange attribRange;
				NSDictionary *attribs=[_attributedString attributesAtIndex:_paragraphCharacterRange.location effectiveRange:&attribRange];
				NSFont *font=[self substituteFontForFont:[attribs objectForKey:NSFontAttributeName]];
				if(!font) font=[NSFont userFontOfSize:0.0];		// use default system font
				while(attribRange.length > 0)
					{ // character range with same font
						unichar c=[str characterAtIndex:attribRange.location];
						NSGlyph glyph=[_layoutManager glyphAtIndex:startIndex];
						NSTypesetterControlCharacterAction a=0;
						float baseLineOffset;
						if(glyph == NSControlGlyph)
							a=[self actionForControlCharacterAtIndex:attribRange.location];
						if(a&NSTypesetterZeroAdvancementAction)
							;	// invisible and no movement
						else
							{ // normal advancement
								
								NSSize adv;
								if(glyph == NSControlGlyph)
									{
									box=[self boundingBoxForControlGlyphAtIndex:startIndex forTextContainer:_currentTextContainer proposedLineFragment:lfr glyphPosition:location characterIndex:attribRange.location];
									adv=box.size;	
									}
								else if(c == NSAttachmentCharacter)
									{
									// ask cell for its size
									adv=box.size;	
									}
								else
									{
									box=[font boundingRectForGlyph:glyph];
									adv=[font advancementForGlyph:glyph];						
									[attribs objectForKey:NSLigatureAttributeName];
									[attribs objectForKey:NSKernAttributeName];
									if(previous)
										{ // handle kerning
											// check if previous = f and current = l => reduce to single glyph
											NSSize k=[font _kerningBetweenGlyph:previous andGlyph:glyph];
											location.x+=k.width;
											location.y+=k.height;
										}
									}
								[self setLocation:location withAdvancements:(CGFloat *) &adv forStartOfGlyphRange:NSMakeRange(startIndex, 1)];
								// round advancement depending on layout style
								box.origin=location;
								box.origin.y+=[font ascender];
								// apply:
								[attribs objectForKey:NSSuperscriptAttributeName];
								[attribs objectForKey:NSBaselineOffsetAttributeName];
								// advance
								location.x+=adv.width;
								location.y+=adv.height;
								
								// if line is full, check for hyphenation/breaks
								// ask paragraph style for type of line breaks
								// and a |= NSTypesetterLineBreakAction
								// collect fragment rect
							}
						if(a&NSTypesetterHorizontalTabAction)
							{ // advance to next tab
								// if line is full, a |= NSTypesetterLineBreakAction
							}
						if(a&NSTypesetterLineBreakAction)
							{ // advance to beginning of next line (start a new line fragment)
								// apply standard indent
								// ask current container for
								/* check with NSTextContainer:
								 - (NSRect) lineFragmentRectForProposedRect:(NSRect) proposedRect
								 sweepDirection:(NSLineSweepDirection) sweepDirection
								 movementDirection:(NSLineMovementDirection) movementDirection
								 remainingRect:(NSRect *) remainingRect;
								 */
								
								// this may return NSZeroRect if it is not possible to get a rect
								// remaining rect should also be stored
								// if container is completely full, a |= NSTypesetterContainerBreakAction
							}
						if(a&NSTypesetterParagraphBreakAction)
							{ // advance to beginning of next paragraph - apply firstLineHeadIndent
								// if container is full, a |= NSTypesetterContainerBreakAction					
							}
						if(a&NSTypesetterContainerBreakAction)
							{ // advance to beginning of next container
								// may ask [[_layoutManager delegate] layoutManager:_layoutManager didCompleteLayoutForTextContainer: atEnd:]
							}
						// FIXME: update proposedRect
						ulfr=box;
						[self setNotShownAttribute:(a != 0) forGlyphRange:NSMakeRange(startIndex, 1)];
						// FIXME: handle rects
						baseLineOffset=[_layoutManager defaultBaselineOffsetForFont:font];
						[self willSetLineFragmentRect:&lfr forGlyphRange:NSMakeRange(startIndex, 1) usedRect:&ulfr baselineOffset:&baseLineOffset];
						[self setLineFragmentRect:lfr forGlyphRange:NSMakeRange(startIndex, 1) usedRect:ulfr baselineOffset:baseLineOffset];
						previous=glyph;
						startIndex++;
						
						attribRange.location++;
						_paragraphCharacterRange.location++;
						_paragraphCharacterRange.length--;
					}
				
				
				// fill line fragment until we get to a actionForControlCharacter
				// or we fill the width of the text container
				// then
				// do word wrapping/hyphenation etc.
				// fit the fragment rects
				// and create the lfr
				// continue with next line
				}
			[self getLineFragmentRect:&lfr
							 usedRect:&lfur
						remainingRect:&rr
			  forStartingGlyphAtIndex:_paragraphGlyphRange.location
						 proposedRect:proposedRect
						  lineSpacing:[self lineSpacingAfterGlyphAtIndex:_paragraphGlyphRange.location withProposedLineFragmentRect:proposedRect]
			   paragraphSpacingBefore:[self paragraphSpacingBeforeGlyphAtIndex:_paragraphGlyphRange.location withProposedLineFragmentRect:proposedRect]
				paragraphSpacingAfter:[self paragraphSpacingAfterGlyphAtIndex:_paragraphGlyphRange.location withProposedLineFragmentRect:proposedRect]];
			/*			[self getLineFragmentRect:&lfr
			 usedRect:&lfur
			 forParagraphSeparatorGlyphRange:_separatorGlyphRange
			 atProposedOrigin:*lfrOrigin];
			 */
			baselineOffset=[self baselineOffsetInLayoutManager:_layoutManager glyphIndex:startIndex];
			
			// do alignments etc. here
			
			[self willSetLineFragmentRect:&lfr forGlyphRange:_paragraphGlyphRange usedRect:&lfur baselineOffset:&baselineOffset];
			[self setLineFragmentRect:lfr forGlyphRange:_paragraphGlyphRange usedRect:lfur baselineOffset:baselineOffset];
			// prepare next proposedRect on either remainingRect or spacings
			[self endLineWithGlyphRange:_paragraphGlyphRange];
		}
	[self endParagraph];
	return startIndex;	// first index not processed
}

- (CGFloat) lineFragmentPadding;
{
	return _lineFragmentPadding;
}

- (CGFloat) lineSpacingAfterGlyphAtIndex:(NSUInteger) index withProposedLineFragmentRect:(NSRect) fragRect;
{
	[self currentParagraphStyle];
	return 5.0;
}

- (NSRange) paragraphCharacterRange; { return  _paragraphCharacterRange; }
- (NSRange) paragraphGlyphRange; { return _paragraphGlyphRange;	 }
- (NSRange) paragraphSeparatorCharacterRange; { return _separatorCharacterRange; }
- (NSRange) paragraphSeparatorGlyphRange; { return _separatorGlyphRange; }

// CHEKME: do these methods look into the relevant NSParagraphStyle??

- (CGFloat) paragraphSpacingAfterGlyphAtIndex:(NSUInteger) index withProposedLineFragmentRect:(NSRect) fragRect;
{
	return 8.0;
}

- (CGFloat) paragraphSpacingBeforeGlyphAtIndex:(NSUInteger) index withProposedLineFragmentRect:(NSRect) fragRect; 
{
	[self currentParagraphStyle];
	return 12.0;
}

- (void) setAttachmentSize:(NSSize) size forGlyphRange:(NSRange) range; 
{
	[_layoutManager setAttachmentSize:size forGlyphRange:range];
}

- (void) setAttributedString:(NSAttributedString *) attrStr;
{
	_attributedString=attrStr;
}

- (void) setBidiLevels:(const uint8_t *) levels forGlyphRange:(NSRange) range;
{
	NIMP;
}

- (void) setBidiProcessingEnabled:(BOOL) enabled;
{
	_bidiProcessingEnabled=enabled;
}

- (void) setDrawsOutsideLineFragment:(BOOL) flag forGlyphRange:(NSRange) range;
{
	while(range.length-- > 0)
		[_layoutManager setDrawsOutsideLineFragment:flag forGlyphAtIndex:range.location++];
}

- (void) setHardInvalidation:(BOOL) flag forGlyphRange:(NSRange) range;
{
	NIMP;
}

- (void) setHyphenationFactor:(float) value;
{
	[_layoutManager setHyphenationFactor:value];
}

- (void) setLineFragmentPadding:(CGFloat) value;
{
	_lineFragmentPadding=value;
}

- (void) setLineFragmentRect:(NSRect) fragRect 
			   forGlyphRange:(NSRange) range 
					usedRect:(NSRect) rect 
			  baselineOffset:(CGFloat) offset;
{
	[_layoutManager setLineFragmentRect:fragRect forGlyphRange:range usedRect:rect];
	// what do we do with the offset???
}

- (void) setLocation:(NSPoint) loc 
	withAdvancements:(const CGFloat *) advancements 
forStartOfGlyphRange:(NSRange) range;
{
	[_layoutManager setLocation:loc forStartOfGlyphRange:range];
	// apply advancements
}

- (void) setNotShownAttribute:(BOOL) flag forGlyphRange:(NSRange) range;
{ // can be set e.g. for TAB or other control characters that are not shown in Postscript/PDF
	while(range.length-- > 0)
		[_layoutManager setNotShownAttribute:flag forGlyphAtIndex:range.location++];
}

- (void) setParagraphGlyphRange:(NSRange) paragRange separatorGlyphRange:(NSRange) sepRange;
{
	_paragraphGlyphRange=paragRange;
	_separatorGlyphRange=sepRange;
}

- (void) setTypesetterBehavior:(NSTypesetterBehavior) behavior; 
{
	_typesetterBehavior=behavior;
}

- (void) setUsesFontLeading:(BOOL) fontLeading; 
{
	_usesFontLeading=fontLeading;
}

- (BOOL) shouldBreakLineByHyphenatingBeforeCharacterAtIndex:(NSUInteger) index;
{
	return NO;	// we have no hyphenation at the moment
}

- (BOOL) shouldBreakLineByWordBeforeCharacterAtIndex:(NSUInteger) index;
{
	return NO;
}

- (NSFont *) substituteFontForFont:(NSFont *) font;
{
	return [_layoutManager substituteFontForFont:font];
}

- (void) substituteGlyphsInRange:(NSRange) range withGlyphs:(NSGlyph *) glyphs; 
{
	[_layoutManager deleteGlyphsInRange:range];
	[_layoutManager insertGlyphs:glyphs length:range.length forStartingGlyphAtIndex:range.location characterIndex:[_layoutManager characterIndexForGlyphAtIndex:range.location]];
}

- (NSArray *) textContainers;
{
	return [_layoutManager textContainers];
}

- (NSTextTab *) textTabForGlyphLocation:(CGFloat) glyphLoc 
					   writingDirection:(NSWritingDirection) writingDirection 
							maxLocation:(CGFloat) maxLoc; 
{
	NSTextTab *tab;
	NSEnumerator *e;
	NSPoint loc=[_layoutManager locationForGlyphAtIndex:glyphLoc];
	if(writingDirection == NSWritingDirectionNatural)
		writingDirection=NSWritingDirectionLeftToRight;
	if(writingDirection != NSWritingDirectionLeftToRight)
		{
		e=[[_currentParagraphStyle tabStops] objectEnumerator];
		while((tab=[e nextObject]))
			{
			CGFloat tl=[tab location];
			if(tl > maxLoc)
				break;
			if(tl > loc.x)
				return tab;	// first tab beyond this glyph
			}
		}
	else
		{
		e=[[_currentParagraphStyle tabStops] reverseObjectEnumerator];
		CGFloat tl=[tab location];
		if(tl <= maxLoc && tl < loc.x)
			return tab;	// first tab before this glyph
		}
	return nil;
}

- (NSTypesetterBehavior) typesetterBehavior;
{
	return _typesetterBehavior;
}

- (BOOL) usesFontLeading;
{
	return _usesFontLeading;
}

- (void) willSetLineFragmentRect:(NSRectPointer) lineRectPt 
				   forGlyphRange:(NSRange) range 
						usedRect:(NSRectPointer) usedRectPt 
				  baselineOffset:(CGFloat *) offset; 
{
	return;	// no op - can be overridden in subclasses to implement modified layout
	// see: http://www.cocoabuilder.com/archive/cocoa/175380-creating-an-nstypesetter-subclass.html
}

@end

#if OLD

@implementation NSLayoutManager (SimpleVersion)

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

static NSGlyph *_oldGlyphs;
static unsigned int _oldNumberOfGlyphs;
static unsigned int _oldGlyphBufferCapacity;

- (NSGlyph *) _glyphsAtIndex:(unsigned) idx;
{
	return &_oldGlyphs[idx];
}

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
						// [self showAttachmentCell:cell inRect:rect characterIndex:rangeLimit.location];
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
			_oldNumberOfGlyphs=[substr length];
			if(!_oldGlyphs || _oldNumberOfGlyphs >= _oldGlyphBufferCapacity)
				_oldGlyphs=(NSGlyph *) objc_realloc(_oldGlyphs, sizeof(_oldGlyphs[0])*(_oldGlyphBufferCapacity=_oldNumberOfGlyphs+20));
			for(i=0; i<_oldNumberOfGlyphs; i++)
				_oldGlyphs[i]=[font _glyphForCharacter:[substr characterAtIndex:i]];		// translate and copy to glyph buffer
			
			[ctxt _drawGlyphs:[self _glyphsAtIndex:0] count:_oldNumberOfGlyphs];	// -> (string) Tj
			//	[self showPackedGlyphs:[self _glyphsAtIndex:0] length:sizeof(NSGlyph)*_oldNumberOfGlyphs glyphRange:_oldNumberOfGlyphs atPoint:<#(NSPoint)point#> font:<#(NSFont *)font#> color:<#(NSColor *)color#> printingAdjustment:NSZeroSize];
			
			// fixme: setLineWidth:[font underlineThickness]
			if((style=[[attr objectForKey:NSUnderlineStyleAttributeName] intValue]))
				{ // underline
				//	[self underlineGlyphRange:<#(NSRange)glyphRange#> underlineType:<#(int)underlineVal#> lineFragmentRect:<#(NSRect)lineRect#> lineFragmentGlyphRange:<#(NSRange)lineGlyphRange#> containerOrigin:<#(NSPoint)containerOrigin#>];
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
				//	[self strikethroughGlyphRange:<#(NSRange)glyphRange#> strikethroughType:<#(int)strikethroughVal#> lineFragmentRect:<#(NSRect)lineRect#> lineFragmentGlyphRange:<#(NSRange)lineGlyphRange#> containerOrigin:<#(NSPoint)containerOrigin#>];
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

- (NSRect) boundingRectForGlyphRange:(NSRange) glyphRange 
					 inTextContainer:(NSTextContainer *) container;
{
	glyphRange=NSIntersectionRange(glyphRange, [self glyphRangeForTextContainer:container]);	// only the range drawn in this container
	return [self _draw:NO glyphsForGlyphRange:glyphRange atPoint:NSZeroPoint findPoint:NSZeroPoint foundAtPos:NULL];
}

- (unsigned) characterIndexForGlyphAtIndex:(unsigned)glyphIndex;
{
	// FIXME:
	return glyphIndex;
}

- (void) drawGlyphsForGlyphRange:(NSRange)glyphsToShow 
						 atPoint:(NSPoint)origin;		// top left of the text container (in flipped coordinates)
{
	[self _draw:YES glyphsForGlyphRange:glyphsToShow atPoint:origin findPoint:NSZeroPoint foundAtPos:NULL];
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

- (NSRange) glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)bounds 
											 inTextContainer:(NSTextContainer *)container;
{
	return NSMakeRange(0, [_textStorage length]);	// assume we have only one text container and ignore the bounds
}

- (NSRange) glyphRangeForTextContainer:(NSTextContainer *)container;
{
	return NSMakeRange(0, [_textStorage length]);	// assume we have only one text container
}

- (NSTextContainer *) textContainerForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRangePointer)effectiveGlyphRange withoutAdditionalLayout:(BOOL)flag
{
	NSTextContainer *container;
	NSTextView *tv;
	container=[_textContainers objectAtIndex:0];	// first one
	tv=[container textView];
	// FIXME: this is a hack
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

@end

#endif

@implementation NSLayoutManager

static void allocateExtra(struct NSGlyphStorage *g)
{
	if(!g->extra)
		g->extra=(struct NSGlyphStorageExtra *) objc_calloc(1, sizeof(g->extra[0]));
}

- (void) addTemporaryAttribute:(NSString *) attr value:(id) val forCharacterRange:(NSRange) range;
{
	NSMutableDictionary *d=[[self temporaryAttributesAtCharacterIndex:range.location effectiveRange:NULL] mutableCopy];
	if(!d) d=[NSMutableDictionary dictionaryWithCapacity:5];
	[d setObject:val forKey:attr];
	[self addTemporaryAttributes:d forCharacterRange:range];
}

- (void) addTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)range;
{
	//if(glyphIndex >= _numberOfGlyphs)
	//	[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", glyphIndex];
	// check for extra
	// if allocated - set
	NIMP;
}

- (void) addTextContainer:(NSTextContainer *)container;
{
	[_textContainers addObject:container];
}

- (BOOL) allowsNonContiguousLayout; { return _allowsNonContiguousLayout; }

- (NSSize) attachmentSizeForGlyphAtIndex:(unsigned)index;
{
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	NIMP;
	return NSZeroSize;
}

- (BOOL) backgroundLayoutEnabled; { return _backgroundLayoutEnabled; }

- (NSRect) boundingRectForGlyphRange:(NSRange) glyphRange 
					 inTextContainer:(NSTextContainer *) container;
{
	NSRect r=NSZeroRect;
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	[self ensureLayoutForGlyphRange:glyphRange];
	// The range is intersected with the container's range before computing the bounding
	// rectangle. This method can be used to translate glyph ranges into display rectangles
	// for invalidation and redrawing when a range of glyphs changes.
	// Bounding rectangles are always in container coordinates.
	while(glyphRange.length-- > 0)
		{
		if(_glyphs[glyphRange.location].textContainer != container)
			continue;	// skip if not inside this container
		r=NSUnionRect(r, _glyphs[glyphRange.location++].usedLineFragmentRect);
		}
	return r;
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
	if(glyphIndex >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", glyphIndex];
	return _glyphs[glyphIndex].characterIndex;
}

- (NSRange) characterRangeForGlyphRange:(NSRange)glyphRange actualGlyphRange:(NSRangePointer)actualGlyphRange;
{
	NSRange r;
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	r.location=_glyphs[glyphRange.location].characterIndex;
	r.length=_glyphs[NSMaxRange(glyphRange)].characterIndex-r.location;
	if(actualGlyphRange)
		{
			while(glyphRange.location > 0 && _glyphs[glyphRange.location-1].characterIndex==r.location)
				glyphRange.location--, glyphRange.length++;	// previous glyphs belong to the same character (ligature)
			while(NSMaxRange(glyphRange) < _numberOfGlyphs && _glyphs[NSMaxRange(glyphRange)].characterIndex==r.location)
				glyphRange.length++;	// next glyphs belong to the same character index
			*actualGlyphRange=glyphRange;	// may have been extended
		}
#if 0
	NSLog(@"characterRangeForGlyphRange = %@", NSStringFromRange(r));
#endif
	return r;
}

- (void) dealloc;
{
	if(_glyphs)
		{
		[self deleteGlyphsInRange:NSMakeRange(0, _numberOfGlyphs)];
		objc_free(_glyphs);
		}
	[_extraLineFragmentContainer release];
	[_glyphGenerator release];
	[_typesetter release];
	[_textContainers release];
	[super dealloc];
}

- (NSImageScaling) defaultAttachmentScaling; { return _defaultAttachmentScaling; }

- (CGFloat) defaultBaselineOffsetForFont:(NSFont *) font;
{
	// FIXME: ask typesetter behaviour???
	return -[font descender];
}

- (float) defaultLineHeightForFont:(NSFont *) font;
{ // may differ from [font defaultLineHeightForFont]
	float leading=[font leading];
	float height;
	height=floor([font ascender]+0.5)+floor(0.5-[font descender]);
	if(leading > 0)
		height += leading + floor(0.2*height + 0.5);
	return height;
}

- (id) delegate; { return _delegate; }

- (void) deleteGlyphsInRange:(NSRange)glyphRange;
{
	unsigned int i;
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	if(glyphRange.length == 0)
		return;
	for(i=0; i<glyphRange.length; i++)
		{ // release extra records
		if(_glyphs[glyphRange.location+i].extra)
			objc_free(_glyphs[glyphRange.location+i].extra);
		}
	if(_numberOfGlyphs != NSMaxRange(glyphRange))
		memcpy(&_glyphs[glyphRange.location], &_glyphs[NSMaxRange(glyphRange)], sizeof(_glyphs[0])*(_numberOfGlyphs-NSMaxRange(glyphRange)));
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
	// also calls -[NSTextBlock drawBackgroundWithRange... ]
}

- (void) drawGlyphsForGlyphRange:(NSRange)glyphsToShow 
						 atPoint:(NSPoint)origin;		// top left of the text container (in flipped coordinates)
{ // The CircleView shows that this method knows about colors (and fonts) and also draws strikethrough and underline
	NSGraphicsContext *ctxt=[NSGraphicsContext currentContext];
	NSColor *lastColor=nil;
	NSFont *lastFont=nil;
	while(glyphsToShow.length > 0)
		{
		unsigned int cindex=[self characterIndexForGlyphAtIndex:glyphsToShow.location];
		NSRange attribRange;	// range of same attributes
		NSDictionary *attribs=[_textStorage attributesAtIndex:cindex effectiveRange:&attribRange];
		NSColor *color=[attribs objectForKey:NSForegroundColorAttributeName];
		NSFont *font=[attribs objectForKey:NSFontAttributeName];
		int count=0;
		NSGlyph *glyphs;
		NSPoint pos=[self locationForGlyphAtIndex:glyphsToShow.location];
		if(!color) color=[NSColor blackColor];	// default color is black
		if(!font) font=[NSFont userFontOfSize:0.0];		// use default system font
		font=[self substituteFontForFont:font];
		/*
		 NSTextAttachment *attachment=[attributes objectForKey:NSAttachmentAttributeName];
		 if(attachment){
		 id <NSTextAttachmentCell> cell=[attachment attachmentCell];
		 NSRect frame;		 
		 frame.origin=point;
		 frame.size=[cell cellSize];
		 [cell drawWithFrame:frame inView:textView characterIndex:characterRange.location layoutManager:self];
		 */
		while(count < glyphsToShow.length)
			{ // get glyph range with uniform attributes
			if([self characterIndexForGlyphAtIndex:glyphsToShow.location+count] > NSMaxRange(attribRange))
				break;
			if([self notShownAttributeForGlyphAtIndex:glyphsToShow.location+count])
				{ // don't include
					glyphsToShow.length--;
					glyphsToShow.location++;			
					break;
				}
			count++;	// include in this chunk
			}
		if(count > 0)
			{
			pos.x+=origin.x;
			pos.y+=origin.y;	// translate container
			glyphs=objc_malloc(sizeof(*glyphs)*(count+1));	// stores NSNullGlyph at end
			[self getGlyphs:glyphs range:NSMakeRange(glyphsToShow.location, count)];
			if(color != lastColor) [lastColor=color set];
			if(font != lastFont) [lastFont=font set];
			// handle NSStrokeWidthAttributeName
			// handle NSShadowAttributeName
			// handle NSObliquenessAttributeName
			// handle NSExpansionAttributeName
			[ctxt _setTextPosition:pos];
			[ctxt _drawGlyphs:glyphs count:count];	// -> (string) Tj
			objc_free(glyphs);
			glyphsToShow.length-=count;
			glyphsToShow.location+=count;
			[[attribs objectForKey:NSUnderlineColorAttributeName] set];
			[[attribs objectForKey:NSUnderlineStyleAttributeName] intValue];
			/* get underline attribute value
			 [self drawUnderlineForGlyphRange:(NSRange)glyphRange 
			 underlineType:(int)underlineVal 
			 baselineOffset:[_typesetter baselineOffsetInLayoutManager:self glyphIndex:startIndex];
			 lineFragmentRect:(NSRect)lineRect 
			 lineFragmentGlyphRange:(NSRange)lineGlyphRange 
			 containerOrigin:(NSPoint)containerOrigin;
			 */
			/* get strikethrough attribute value
			 [self drawStrikethroughForGlyphRange:(NSRange)glyphRange 
			 strikethroughType:(int)strikethroughVal 
			 baselineOffset:[_typesetter baselineOffsetInLayoutManager:self glyphIndex:startIndex] 
			 lineFragmentRect:(NSRect)lineRect 
			 lineFragmentGlyphRange:(NSRange)lineGlyphRange 
			 containerOrigin:(NSPoint)containerOrigin;
			 */
			}
		}
}

- (BOOL) drawsOutsideLineFragmentForGlyphAtIndex:(unsigned)index;
{
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	return _glyphs[index].drawsOutsideLineFragment;
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
	// how do we get to the font?
	float posy=pos.y+[font defaultLineHeightForFont]+baselineOffset+[font underlinePosition];
#if 0
	NSLog(@"underline %x", style);
#endif
	[foreGround setStroke];
	[[attr objectForKey:NSUnderlineColorAttributeName] setStroke];		// change stroke color if defined differently
	[NSBezierPath strokeLineFromPoint:NSMakePoint(pos.x, posy) toPoint:NSMakePoint(pos.x+width, posy)];
#endif
}

- (void) ensureGlyphsForCharacterRange:(NSRange) range;
{
	if(_glyphsAreValid)
		return;
	[self deleteGlyphsInRange:NSMakeRange(0, _numberOfGlyphs)];	// delete all existing glyphs
	_firstUnlaidGlyphIndex=0;
	_firstUnlaidCharacterIndex=0;
	[_glyphGenerator generateGlyphsForGlyphStorage:self
						 desiredNumberOfCharacters:range.length
										glyphIndex:&_firstUnlaidGlyphIndex
									characterIndex:&_firstUnlaidCharacterIndex];	// generate Glyphs (code but not position!)
	_glyphsAreValid=YES;
}

- (void) ensureGlyphsForGlyphRange:(NSRange) range;
{
	NIMP;
}

- (void) ensureLayoutForBoundingRect:(NSRect) rect inTextContainer:(NSTextContainer *) textContainer;
{
	[self ensureLayoutForTextContainer:textContainer];	
}

- (void) ensureLayoutForCharacterRange:(NSRange) range;
{	
	if(_layoutIsValid)
		return;
	_firstUnlaidCharacterIndex=0;
	[self ensureGlyphsForCharacterRange:range];
	_layoutIsValid=YES;	// avoid recursion
	[_typesetter layoutCharactersInRange:range forLayoutManager:self maximumNumberOfLineFragments:INT_MAX];
}

- (void) ensureLayoutForGlyphRange:(NSRange) range;
{
	[self ensureLayoutForCharacterRange:range];
}

- (void) ensureLayoutForTextContainer:(NSTextContainer *) textContainer;
{
	[self ensureLayoutForCharacterRange:NSMakeRange(0, [_textStorage length])];
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
	float f;
	[self glyphIndexForPoint:aPoint inTextContainer:aTextContainer fractionOfDistanceThroughGlyph:&f];	// ignore index
	return f;
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
	unsigned int idx=0;
	while(glyphRange.length-- > 0)
		{
		if(_glyphs[glyphRange.location].glyph != NSNullGlyph)
			glyphArray[idx++]=_glyphs[glyphRange.location].glyph;
		glyphRange.location++;
		}
	glyphArray[idx]=NSNullGlyph;	// adds 0-termination (buffer must have enough capacity!)
	return idx;
}

- (unsigned) getGlyphsInRange:(NSRange)glyphsRange
					   glyphs:(NSGlyph *)glyphBuffer
			 characterIndexes:(unsigned *)charIndexBuffer
			glyphInscriptions:(NSGlyphInscription *)inscribeBuffer
				  elasticBits:(BOOL *)elasticBuffer;
{
	return [self getGlyphsInRange:glyphsRange glyphs:glyphBuffer
				 characterIndexes:charIndexBuffer glyphInscriptions:inscribeBuffer
					  elasticBits:elasticBuffer bidiLevels:NULL];
}

- (unsigned) getGlyphsInRange:(NSRange)glyphsRange
					   glyphs:(NSGlyph *)glyphBuffer
			 characterIndexes:(unsigned *)charIndexBuffer
			glyphInscriptions:(NSGlyphInscription *)inscribeBuffer
				  elasticBits:(BOOL *)elasticBuffer
				   bidiLevels:(unsigned char *)bidiLevelBuffer;
{
	unsigned cnt=glyphsRange.length;
	while(cnt-- > 0)
		{ // extract from internal data structure
		struct NSGlyphStorageExtra *extra;
		if(glyphBuffer) *glyphBuffer++=_glyphs[glyphsRange.location].glyph;
		if(charIndexBuffer) *charIndexBuffer++=_glyphs[glyphsRange.location].characterIndex;
		extra=_glyphs[glyphsRange.location].extra;
		if(inscribeBuffer) *inscribeBuffer++=extra?extra->inscribeAttribute:0;
		if(elasticBuffer) *elasticBuffer++=extra?extra->elasticAttribute:0;
		if(bidiLevelBuffer) *bidiLevelBuffer++=extra?extra->bidiLevelAttribute:0;
		glyphsRange.location++;
		}
	return glyphsRange.length;
}

- (NSUInteger) getLineFragmentInsertionPointsForCharacterAtIndex:(NSUInteger) index 
											  alternatePositions:(BOOL) posFlag 
												  inDisplayOrder:(BOOL) orderFlag 
													   positions:(CGFloat *) positions 
												characterIndexes:(NSUInteger *) charIds;
{
	NIMP;
	return 0;
}

- (NSGlyph) glyphAtIndex:(unsigned)glyphIndex;
{
	if(glyphIndex >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", glyphIndex];
	return _glyphs[glyphIndex].glyph;
}

- (NSGlyph) glyphAtIndex:(unsigned)glyphIndex isValidIndex:(BOOL *)isValidIndex;
{
	BOOL isValid=glyphIndex < _numberOfGlyphs;
	if(isValidIndex)
		*isValidIndex=isValid;
	if(isValid)
		return _glyphs[glyphIndex].glyph;
	return NSNullGlyph;
}

- (NSGlyphGenerator *) glyphGenerator; { return _glyphGenerator; }

- (NSUInteger) glyphIndexForCharacterAtIndex:(NSUInteger) index;
{
	unsigned int i;
	// generate glyphs if needed
	if(index >= [_textStorage length])
		return index-[_textStorage length]+_numberOfGlyphs;	// extrapolate
	for(i=0; i<_numberOfGlyphs; i++)
		if(_glyphs[i].characterIndex == index)
			return i;	// found
	return NSNotFound;
}

- (unsigned int) glyphIndexForPoint:(NSPoint)aPoint inTextContainer:(NSTextContainer *)aTextContainer;
{
	return [self glyphIndexForPoint:aPoint inTextContainer:aTextContainer fractionOfDistanceThroughGlyph:NULL];
}

- (unsigned int) glyphIndexForPoint:(NSPoint)aPoint
				inTextContainer:(NSTextContainer *)textContainer
 fractionOfDistanceThroughGlyph:(float *)partialFraction;
{
	unsigned int i;
	[self ensureLayoutForTextContainer:textContainer]; // additional layout
	for(i=0; i<_numberOfGlyphs; i++)
		{
		if(_glyphs[i].textContainer != textContainer)
			continue;	// different container
		// check if point is within glyph
		// if(partialFraction)
		// calculate from location and width
		
		}
	return NSNotFound;	
}

- (NSRange) glyphRangeForBoundingRect:(NSRect)bounds 
					  inTextContainer:(NSTextContainer *)container;
{
	[self ensureLayoutForBoundingRect:bounds inTextContainer:container]; // additional layout
	return [self glyphRangeForBoundingRectWithoutAdditionalLayout:bounds inTextContainer:container];
}

- (NSRange) glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)bounds 
											 inTextContainer:(NSTextContainer *)container;
{
	NSRange r;
	for(r.location=0; r.location < _numberOfGlyphs; r.location++)
		if(_glyphs[r.location].textContainer == container && NSIntersectsRect(_glyphs[r.location].lineFragmentRect, bounds))
			break;	// first glyph in this container found that falls into the bounds
	for(r.length=0; NSMaxRange(r) < _numberOfGlyphs; r.length++)
		if(_glyphs[NSMaxRange(r)].textContainer != container)
			break;	// last glyph found because next one belongs to a different container
	// we should trim off all glyphs from the end that are outside of the bounds
	return r;
}

- (NSRange) glyphRangeForCharacterRange:(NSRange)charRange actualCharacterRange:(NSRange *)actualCharRange;
{
	NSRange r;
	if(NSMaxRange(charRange) > [_textStorage length])
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	[self ensureGlyphsForCharacterRange:charRange];
	for(r.location=0; r.location<_numberOfGlyphs; r.location++)
		{
		if(_glyphs[r.location].characterIndex == charRange.location)
			break;	// first in range found
		}
	for(r.length=0; NSMaxRange(r)<_numberOfGlyphs; r.length++)
		{
		if(_glyphs[NSMaxRange(r)].characterIndex == NSMaxRange(charRange))
			break;	// first no longer in range found		
		}
	if(actualCharRange)
		{ // how can it be different from charRange???
		*actualCharRange=charRange;		
		}
#if 0
	NSLog(@"glyphRangeForCharacterRange = %@", NSStringFromRange(r));
#endif
	return r;
}

- (NSRange) glyphRangeForTextContainer:(NSTextContainer *)container;
{ // this can become quite slow if we have 10 Mio characters...
	// so we should have some cache indexed by the container
	NSRange r;
	[self ensureLayoutForTextContainer:container];
	for(r.location=0; r.location < _numberOfGlyphs; r.location++)
		if(_glyphs[r.location].textContainer == container)
			break;	// first glyph in this container found
	for(r.length=0; NSMaxRange(r) < _numberOfGlyphs; r.length++)
		if(_glyphs[NSMaxRange(r)].textContainer != container)
			break;	// last glyph found because next one belongs to a different container
	return r;
}

- (BOOL) hasNonContiguousLayout; { return _hasNonContiguousLayout; }
- (float) hyphenationFactor; { return _hyphenationFactor; }

- (id) init;
{
	if((self=[super init]))
		{
		_textContainers=[NSMutableArray new];
		_typesetter=[[NSTypesetter sharedSystemTypesetter] retain];
		_glyphGenerator=[[NSGlyphGenerator sharedGlyphGenerator] retain];
		_usesScreenFonts=NO;
		}
	return self;
}

- (void) insertGlyph:(NSGlyph)glyph atGlyphIndex:(unsigned)glyphIndex characterIndex:(unsigned)charIndex;
{ // insert a single glyph without attributes
	[self insertGlyphs:&glyph length:1 forStartingGlyphAtIndex:glyphIndex characterIndex:charIndex];
}

- (void) insertTextContainer:(NSTextContainer *)container atIndex:(unsigned)index;
{
	[_textContainers insertObject:container atIndex:index];
	if(index == 0)
		_firstTextView=[container textView];	// has changed
	// invalidate
}

- (int) intAttribute:(int)attributeTag forGlyphAtIndex:(unsigned)glyphIndex;
{
	if(glyphIndex >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", glyphIndex];
	switch(attributeTag) {
		case NSGlyphAttributeSoft:
			if(!_glyphs[glyphIndex].extra) return 0;
			return _glyphs[glyphIndex].extra->softAttribute;
		case NSGlyphAttributeElastic:
			if(!_glyphs[glyphIndex].extra) return 0;
			return _glyphs[glyphIndex].extra->elasticAttribute;
		case NSGlyphAttributeBidiLevel:
			if(!_glyphs[glyphIndex].extra) return 0;
			return _glyphs[glyphIndex].extra->bidiLevelAttribute;
		case NSGlyphAttributeInscribe:
			if(!_glyphs[glyphIndex].extra) return 0;
			return _glyphs[glyphIndex].extra->inscribeAttribute;
		default:
			[NSException raise:@"NSLayoutManager" format:@"unknown intAttribute tag: %u", attributeTag];
			return 0;
	}
}

- (void) invalidateDisplayForCharacterRange:(NSRange)charRange;
{
	[self invalidateDisplayForGlyphRange:[self glyphRangeForCharacterRange:charRange actualCharacterRange:NULL]];
}

- (void) invalidateDisplayForGlyphRange:(NSRange)glyphRange;
{
	// [textview setNeedsDisplayInRect:rect avoidAdditionalLayout:YES]
}

- (void) invalidateGlyphsForCharacterRange:(NSRange)charRange changeInLength:(int)delta actualCharacterRange:(NSRange *)actualCharRange;
{
	[self invalidateGlyphsOnLayoutInvalidationForGlyphRange:NSMakeRange(0, _numberOfGlyphs)];	// delete all we have
}

- (void) invalidateGlyphsOnLayoutInvalidationForGlyphRange:(NSRange) range;
{
	_firstUnlaidGlyphIndex=0;
	_layoutIsValid=_glyphsAreValid=NO;
}

- (void) invalidateLayoutForCharacterRange:(NSRange) range actualCharacterRange:(NSRangePointer) charRange;
{
	// Invalidates the layout information for the glyphs mapped to the given range of characters.
	[self invalidateLayoutForCharacterRange:range isSoft:NO actualCharacterRange:charRange];
}

- (void) invalidateLayoutForCharacterRange:(NSRange)charRange isSoft:(BOOL)flag actualCharacterRange:(NSRange *)actualCharRange;
{
	// Invalidates the layout information for the glyphs mapped to the given range of characters
	// flag: If YES, invalidates internal caches in the layout manager; if NO, invalidates layout.
	[_delegate layoutManagerDidInvalidateLayout:self];
	_layoutIsValid=NO;
}

- (BOOL) isValidGlyphIndex:(unsigned)glyphIndex;
{
	if(glyphIndex >= _numberOfGlyphs)
		return NO;
	return _glyphs[glyphIndex].validFlag;
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
	[self ensureLayoutForCharacterRange:NSMakeRange(0, [_textStorage length])];
	return [self lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:effectiveGlyphRange withoutAdditionalLayout:NO];
}

- (NSRect) lineFragmentRectForGlyphAtIndex:(NSUInteger) index effectiveRange:(NSRangePointer) charRange withoutAdditionalLayout:(BOOL) layoutFlag;
{
	NSRect lfr;
	if(!layoutFlag)
		;	// do additional layout
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	lfr=_glyphs[index].lineFragmentRect;
	if(charRange)
		{ // find the effective range by searching back and forth from the current index for glyphs with the same lft
			charRange->location=index;
			while(charRange->location > 0)
				{
				if(!NSEqualRects(lfr, _glyphs[charRange->location-1].lineFragmentRect))
					break;	// previous index is different
				charRange->location--;
				}
			charRange->length=index-charRange->location;
			while(NSMaxRange(*charRange)+1 < _numberOfGlyphs)
				{
				if(!NSEqualRects(lfr, _glyphs[NSMaxRange(*charRange)+1].lineFragmentRect))
					break;	// next index is different
				charRange->length++;
				}
		}
	return lfr;
}

- (NSRect) lineFragmentUsedRectForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange;
{
	NIMP;
	return NSZeroRect;
}

- (NSPoint) locationForGlyphAtIndex:(unsigned) index;
{
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	return _glyphs[index].location;
}

- (BOOL) notShownAttributeForGlyphAtIndex:(unsigned) index;
{
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	return _glyphs[index].notShownAttribute;
}

- (unsigned) numberOfGlyphs;
{
	if(!_allowsNonContiguousLayout)
		[self ensureGlyphsForCharacterRange:NSMakeRange(0, [_textStorage length])]; // generate all glyphs
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
	// invalidate this and following containers
}

- (void) replaceGlyphAtIndex:(unsigned)glyphIndex withGlyph:(NSGlyph)newGlyph;
{
	if(glyphIndex >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", glyphIndex];
	_glyphs[glyphIndex].glyph=newGlyph;
	// set invalidation!?! If the glyph is bigger, we have to update the layout from here to the end
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

- (NSArray *) rulerMarkersForTextView:(NSTextView *)view 
					   paragraphStyle:(NSParagraphStyle *)style 
								ruler:(NSRulerView *)ruler;
{
	return NIMP;
}

- (void) setAllowsNonContiguousLayout:(BOOL) flag;
{
	_allowsNonContiguousLayout=flag;
}

- (void) setAttachmentSize:(NSSize)attachmentSize forGlyphRange:(NSRange)glyphRange;
{
	// DEPRECATED
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	NIMP;
}

- (void) setBackgroundLayoutEnabled:(BOOL)flag; { _backgroundLayoutEnabled=flag; }

- (void) setBoundsRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;
{
	NIMP;
}

- (void) setCharacterIndex:(unsigned)charIndex forGlyphAtIndex:(unsigned) index;
{ // character indices should be ascending with glyphIndex...
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	_glyphs[index].characterIndex=charIndex;
}

- (void) setDefaultAttachmentScaling:(NSImageScaling)scaling; { _defaultAttachmentScaling=scaling; }

- (void) setDelegate:(id)obj; { _delegate=obj; }

- (void) setDrawsOutsideLineFragment:(BOOL)flag forGlyphAtIndex:(unsigned) index;
{
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	_glyphs[index].drawsOutsideLineFragment=flag;
}

- (void) setExtraLineFragmentRect:(NSRect)fragmentRect usedRect:(NSRect)usedRect textContainer:(NSTextContainer *)container;
{ // used to define a virtual extra line to display the insertion point if there is no content or the last character is a hard break
	_extraLineFragmentRect=fragmentRect;
	_extraLineFragmentUsedRect=usedRect;
	[_extraLineFragmentContainer autorelease];
	_extraLineFragmentContainer=[container retain];
}

- (void) setGlyphGenerator:(NSGlyphGenerator *)gg; { ASSIGN(_glyphGenerator, gg); }

- (void) setHyphenationFactor:(float)factor; { _hyphenationFactor=factor; }

- (void) setLayoutRect:(NSRect)rect forTextBlock:(NSTextBlock *)block glyphRange:(NSRange)glyphRange;
{
	NIMP;
}

- (void) setLineFragmentRect:(NSRect)fragmentRect forGlyphRange:(NSRange)glyphRange usedRect:(NSRect)usedRect;
{
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	while(glyphRange.length-- > 0)
		{
		_glyphs[glyphRange.location].lineFragmentRect=fragmentRect;
		_glyphs[glyphRange.location].usedLineFragmentRect=usedRect;
		glyphRange.location++;
		}
}

- (void) setLocation:(NSPoint)location forStartOfGlyphRange:(NSRange)glyphRange;
{
	// [self setLocations:&location startingGlyphIndexes:&glyphRange.location count:1 forGlyphRange:glyphRange];
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	_glyphs[glyphRange.location].location=location;
}

- (void) setLocations:(NSPointArray) locs 
 startingGlyphIndexes:(NSUInteger *) glyphIds 
				count:(NSUInteger) number 
		forGlyphRange:(NSRange) glyphRange; 
{
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	while(number-- > 0)
		{
		if(*glyphIds >= NSMaxRange(glyphRange) || *glyphIds < glyphRange.location)
			[NSException raise:@"NSLayoutManager" format:@"invalid glyph index not in range"];
		_glyphs[*glyphIds++].location=*locs++;	// set location
		}
}

- (void) setNotShownAttribute:(BOOL)flag forGlyphAtIndex:(unsigned) index;
{
	if(index >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
	_glyphs[index].notShownAttribute=flag;
}

// FIXME: does this trigger relayout?

- (void) setShowsControlCharacters:(BOOL)flag; { if(flag) _layoutOptions |= NSShowControlGlyphs; else _layoutOptions &= ~NSShowControlGlyphs; }

- (void) setShowsInvisibleCharacters:(BOOL)flag; { if(flag) _layoutOptions |= NSShowInvisibleGlyphs; else _layoutOptions &= ~NSShowInvisibleGlyphs; }

- (void) setTemporaryAttributes:(NSDictionary *)attrs forCharacterRange:(NSRange)charRange;
{
	NIMP;
	// FIXME: this is for characters!!!
	if(NSMaxRange(charRange) > [_textStorage length])
		[NSException raise:@"NSLayoutManager" format:@"invalid character range"];
//	return _glyphs[glyphIndex].extra=flag;
}

- (void) setTextContainer:(NSTextContainer *) container forGlyphRange:(NSRange) glyphRange;
{
	if(NSMaxRange(glyphRange) > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph range"];
	while(glyphRange.length-- > 0)
		_glyphs[glyphRange.location++].textContainer=container;
}

- (void) setTextStorage:(NSTextStorage *) ts; { _textStorage=ts; [_typesetter setAttributedString:_textStorage]; _layoutIsValid=_glyphsAreValid=NO; }	// The textStorage owns the layout manager(s)
- (void) setTypesetter:(NSTypesetter *) ts; { ASSIGN(_typesetter, ts); [_typesetter setAttributedString:_textStorage]; _layoutIsValid=_glyphsAreValid=NO; }
- (void) setTypesetterBehavior:(NSTypesetterBehavior) behavior; { [_typesetter setTypesetterBehavior:behavior]; }
- (void) setUsesFontLeading:(BOOL) flag; { _usesFontLeading=flag; _layoutIsValid=NO; }
- (void) setUsesScreenFonts:(BOOL) flag; { _usesScreenFonts=flag; _layoutIsValid=_glyphsAreValid=NO; }

- (void) showAttachmentCell:(NSCell *)cell inRect:(NSRect)rect characterIndex:(unsigned)attachmentIndex;
{
	// check for NSAttachmentCell or otherwise call without characterIndex
	[(NSTextAttachmentCell *) cell drawWithFrame:rect
				 inView:[self firstTextView]
		 characterIndex:attachmentIndex
		  layoutManager:self];
}

- (void) showPackedGlyphs:(char *) glyphs
				   length:(unsigned) glyphLen	// number of bytes = 2* number of glyphs
			   glyphRange:(NSRange) glyphRange
				  atPoint:(NSPoint) point
					 font:(NSFont *) font
					color:(NSColor *) color
	   printingAdjustment:(NSSize) adjust;
{
	NIMP;
	NSGraphicsContext *ctxt=[NSGraphicsContext currentContext];
	[ctxt _setTextPosition:point];
	if(font) [ctxt _setFont:font];
	if(color) [ctxt _setColor:color];
	// FIXME: this is used with packed glyphs!!!
//	[ctxt _drawGlyphs:glyphs count:glyphRange.length];	// -> (string) Tj
	// printingAdjustment???
}

- (BOOL) showsControlCharacters; { return (_layoutOptions&NSShowControlGlyphs) != 0; }
- (BOOL) showsInvisibleCharacters; { return (_layoutOptions&NSShowInvisibleGlyphs) != 0; }

- (void) strikethroughGlyphRange:(NSRange)glyphRange
			   strikethroughType:(int)strikethroughVal
				lineFragmentRect:(NSRect)lineRect
		  lineFragmentGlyphRange:(NSRange)lineGlyphRange
				 containerOrigin:(NSPoint)containerOrigin;
{
	[self ensureLayoutForGlyphRange:glyphRange];
	[self drawStrikethroughForGlyphRange:glyphRange strikethroughType:strikethroughVal baselineOffset:[_typesetter baselineOffsetInLayoutManager:self glyphIndex:glyphRange.location] lineFragmentRect:lineRect lineFragmentGlyphRange:lineGlyphRange containerOrigin:containerOrigin];
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

- (id) temporaryAttribute:(NSString *) name 
		 atCharacterIndex:(NSUInteger) loc 
		   effectiveRange:(NSRangePointer) effectiveRange;
{
//	if(index >= _numberOfGlyphs)
//		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
//	return _glyphs[glyphIndex].extra;	
	return NIMP;
}

- (id) temporaryAttribute:(NSString *) name 
		 atCharacterIndex:(NSUInteger) loc 
	longestEffectiveRange:(NSRangePointer) effectiveRange 
				  inRange:(NSRange) limit;
{
//	if(index >= _numberOfGlyphs)
//		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
//	return _glyphs[glyphIndex].extra;	
	return NIMP;
}

- (NSDictionary *) temporaryAttributesAtCharacterIndex:(NSUInteger) loc 
								 longestEffectiveRange:(NSRangePointer) effectiveRange 
											   inRange:(NSRange) limit;
{
//	if(index >= _numberOfGlyphs)
//		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", index];
//	return _glyphs[glyphIndex].extra;
	return NIMP;
}

- (NSDictionary *) temporaryAttributesAtCharacterIndex:(NSUInteger) index effectiveRange:(NSRangePointer) charRange;
{
	return NIMP;
}

- (void) textContainerChangedGeometry:(NSTextContainer *)container;
{
	// trigger invalidation
	[self invalidateDisplayForGlyphRange:[self glyphRangeForTextContainer:container]];
}

- (void) textContainerChangedTextView:(NSTextContainer *)container;
{
	// trigger invalidation
	[self invalidateDisplayForGlyphRange:[self glyphRangeForTextContainer:container]];
}

// FIXME

// we should circle through containers touched by range
// NOTE: the container rect might be very large if the container covers several 10-thousands lines
// therefore, this algorithm must be very efficient
// and there might be several thousand containers...

- (NSTextContainer *) textContainerForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRange *)effectiveGlyphRange;
{
	return [self textContainerForGlyphAtIndex:glyphIndex effectiveRange:effectiveGlyphRange withoutAdditionalLayout:NO];
}

- (NSTextContainer *) textContainerForGlyphAtIndex:(unsigned)glyphIndex effectiveRange:(NSRangePointer)effectiveGlyphRange withoutAdditionalLayout:(BOOL)flag
{
	if(!flag)
		[self ensureLayoutForCharacterRange:NSMakeRange(0, [_textStorage length])]; // additional layout
	if(glyphIndex >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", glyphIndex];
	if(effectiveGlyphRange)
		{ // search back/forth for effective range
			
		}
	return _glyphs[glyphIndex].textContainer;
}

- (NSArray *) textContainers; { return _textContainers; }
- (NSTextStorage *) textStorage; { return _textStorage; }

/* this is called by -[NSTextStorage processEditing] if the NSTextStorage has been changed */

- (void) textStorage:(NSTextStorage *)str edited:(unsigned)editedMask range:(NSRange)newCharRange changeInLength:(int)delta invalidatedRange:(NSRange)invalidatedCharRange;
{
	// this may be used to move around glyphs and separate between glyph generation (i.e.
	// translation of character codes to glyph codes through NSFont
	// and pure layout (not changing geometry of individual glyphs but their relative position)
	// check if only drawing attributes have been changed like NSColor/underline/striketrhough/link - then we do not even need to generate new glyphs or new layout positions
	if(editedMask&NSTextStorageEditedCharacters)
		[self invalidateLayoutForCharacterRange:invalidatedCharRange actualCharacterRange:NULL], _glyphsAreValid=NO;
	else if(editedMask&NSTextStorageEditedAttributes)
		[self invalidateLayoutForCharacterRange:invalidatedCharRange actualCharacterRange:NULL];
}
	 
- (NSTextView *) textViewForBeginningOfSelection;
{
	return NIMP;
}

- (NSTypesetter *) typesetter; { return _typesetter; }
- (NSTypesetterBehavior) typesetterBehavior; { return [_typesetter typesetterBehavior]; }

- (void) underlineGlyphRange:(NSRange)glyphRange 
			   underlineType:(int)underlineVal 
			lineFragmentRect:(NSRect)lineRect 
			   lineFragmentGlyphRange:(NSRange)lineGlyphRange 
			 containerOrigin:(NSPoint)containerOrigin;
{
	[self ensureLayoutForGlyphRange:glyphRange];
	// get fragments with same font???
	// use [font underlinePosition];
	[self drawUnderlineForGlyphRange:glyphRange underlineType:underlineVal baselineOffset:[_typesetter baselineOffsetInLayoutManager:self glyphIndex:glyphRange.location] lineFragmentRect:lineRect lineFragmentGlyphRange:lineGlyphRange containerOrigin:containerOrigin];
}

- (NSRect) usedRectForTextContainer:(NSTextContainer *)container;
{
	// Returns the text container's currently used area, which determines
	// the size that the view would need to be in order to display all the glyphs
	// that are currently laid out in the container.
	// This causes neither glyph generation nor layout.
	
	// Used rectangles are always in container coordinates.
	
	NSRect r=NSZeroRect;
	unsigned int i;
	BOOL any=NO;
	for(i=0; i<_numberOfGlyphs; i++)
		{
		if(_glyphs[i].textContainer != container)
			{
			if(any)
				break;	// does no longer match
			continue;	// skip if not inside this container			
			}
		r=NSUnionRect(r, _glyphs[i].usedLineFragmentRect);
		any=YES;
		}
	return r;	
}

- (BOOL) usesFontLeading; { return _usesFontLeading; }
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
	_typesetter=[[NSTypesetter sharedSystemTypesetter] retain];
	_glyphGenerator=[[NSGlyphGenerator sharedGlyphGenerator] retain];
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
	if(glyph > _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph insert position"];
	if(!_glyphs || _numberOfGlyphs+length >= _glyphBufferCapacity)
		_glyphs=(struct NSGlyphStorage *) objc_realloc(_glyphs, sizeof(_glyphs[0])*(_glyphBufferCapacity=_numberOfGlyphs+length+20));	// make more space
	if(glyph != _numberOfGlyphs)
		memmove(&_glyphs[glyph+length], &_glyphs[glyph], sizeof(_glyphs[0])*(_numberOfGlyphs-glyph));	// make room unless we append
	memset(&_glyphs[glyph], 0, sizeof(_glyphs[0])*length);	// clear all data and flags
	_numberOfGlyphs+=length;
	while(length-- > 0)
		{
		_glyphs[glyph].glyph=*glyphs++;
		_glyphs[glyph].characterIndex=index;	// all glyphs belong to the same character!
		_glyphs[glyph].validFlag=YES;
		glyph++;
		}
}

- (void) setIntAttribute:(int)attributeTag value:(int)val forGlyphAtIndex:(unsigned)glyphIndex;
{ // subclasses must provide storatge for additional attributeTag values and call this for the "old" ones
	if(glyphIndex >= _numberOfGlyphs)
		[NSException raise:@"NSLayoutManager" format:@"invalid glyph index: %u", glyphIndex];
	allocateExtra(&_glyphs[glyphIndex]);
	switch(attributeTag) {
		case NSGlyphAttributeSoft:
			_glyphs[glyphIndex].extra->softAttribute=val;
			break;
		case NSGlyphAttributeElastic:
			_glyphs[glyphIndex].extra->elasticAttribute=val;
			break;
		case NSGlyphAttributeBidiLevel:
			_glyphs[glyphIndex].extra->bidiLevelAttribute=val;
			break;
		case NSGlyphAttributeInscribe:
			_glyphs[glyphIndex].extra->inscribeAttribute=val;
			break;
		default:
			[NSException raise:@"NSLayoutManager" format:@"unknown intAttribute tag: %u", attributeTag];
	}
}

@end

