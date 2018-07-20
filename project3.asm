;Project 3 COMP 2201
;Programmer: Randi Tinney
;Updated:    17 Apr 17

;Program selects a random quote to be displayed on the screen from a list of 10 hardcoded movie quotes. The user then has to type the sentence
;	perfectly. If there is an error inside the users typed quote, the timer will increase by double and the error will be highlighted in red.
;	Only when the user goes back to fix the error will the timer resume its normal counting and the quote will be green again. Once the quote
;	is completely typed, the timer stops and the program ends. Program handles LEFT arrow, RIGHT arrow, BACKSPACE, DELETE keys

MyStack SEGMENT STACK
	DW 256 DUP(?)
MyStack ENDS

MyData SEGMENT
	quote1 DB "Toto, I've a feeling we're not in Kansas anymore.", 0                                 ;# of chars = 49
	quote2 DB "Here's looking at you, kid.", 0                                                       ;# of chars = 27
	quote3 DB "May the Force be with you.", 0                                                        ;# of chars = 26
	quote4 DB "I love the smell of napalm in the morning.", 0                                        ;# of chars = 42
	quote5 DB "You've got to ask yourself one question: 'Do I feel lucky?' Well, do ya, punk?", 0    ;# of chars = 78
	quote6 DB "You - shall not - pass!", 0                                                           ;# of chars = 21
	quote7 DB "Your mother was a hamster and your father smelt of elderberries.", 0                  ;# of chars = 64
	quote8 DB "A five ounce bird could not carry a one pound coconut.", 0                            ;# of chars = 54
	quote9 DB "You're gonna need a bigger boat.", 0                                                  ;# of chars = 32
	quote10 DB "The first rule of Fight Club is - you do not talk about Fight Club.", 0              ;# of chars = 67
	
	randQuote DW 0                                          ;Memory location of a quote chosen at random
	randQuoteLength DW 0                                    ;length of the random quote
	
	quoteLengths DW 49, 27, 26, 42, 78, 21, 64, 54, 32, 67  ;quote lengths in order 1 - 10 without ending 0
	
	actualCursorColumn DW 0                                 ;Sets the cursor column so it can change each time the user types, deletes, moves, etc.
	startTypingPos EQU 7                                    ;Zrow for where user will type sentence
	virtualCursorLocation DW 0                              ;the virtual cursor for usersTypedQuote (in actual memory location, not offset)
	currentColor DB 00001010b                               ;Current color of text, will change if what was typed is right or wrong 
								;(Green good; red bad)
	finishedFlag DB 0                                       ;Flag that will change in a PROC to determine if the user typed the quote 
								;correctly or not
	
	typedQuoteLength DW 0                                   ;length of typed quote. Will change with input
	usersTypedQuote DB 78 DUP(" ")                          ;Will be used to store what the user is typing for outputting purposes
	
	quoteArray DW 10 DUP(?)                                 ;Will be used to store the memory location of each sentence
													 
	doubleTimeFlag DB 0                                     ;Flag to be changed if there is an error so you can double the time
	currentTicks DW ?					;Current system time in ticks
	prevTicks DW ?						;Previous system time in ticks
	deltaTicks DW ?						;Difference in currentTicks and prevTicks
	totalDeltaTicks DW ?					;The total time it has taken for the user to type the sentence. This will be displayed
	
MyData ENDS

MyCode SEGMENT
	ASSUME CS:MyCode, DS: MyData
	
mainProc PROC
	MOV AX, MyData
	MOV DS, AX
	MOV AX, 0B800h
	MOV ES, AX
	
	LEA SI, usersTypedQuote
	MOV virtualCursorLocation, SI                                 ;get memory location of usersTypedQuote. Will now use this variable for
				      			              ;different inputs
	
	CALL clearScreen
	CALL getQuoteArray
	CALL getRandomQuote
	CALL displayRandomQuote
	CALL getUserTyping
	
	MOV AH, 4Ch                                                    ;end program with these two lines
	INT 21h
	
mainProc ENDP

;====================START clearScreen============================
clearScreen PROC
;On entry, nothing is passed. Doesn't use any variabes.
;On exit, clears the current screen of all chars. All registers preserved
	PUSH CX SI AX
	
	MOV CX, 4000                
	MOV SI, 0
	MOV AH, 00001111b
	MOV AL, 0
clearScreenLoop:
	MOV ES:[SI], AX
	ADD SI, 2
	LOOP clearScreenLoop
	
	POP AX SI CX
	RET
clearScreen ENDP
;====================END clearScreen==============================

;====================START getUserTyping==========================
getUserTyping PROC
;On entry, uses values in actualCursorColumn to set the onscreen cursor position and virtualCursorLocation for manipulating of usersTypedQuote
;	(which will store what the user types. Will change typedQuoteLength with each correct input (adding a char increases; backspace/delete
;	decreases). Each correct input will also change actualCursorColumn and virtualCursorLocation accordingly. Will store chars (or remove/move)
;	whenever the appropriate key is pressed into usersTypedQuote.
;	Calls on displayTypedSentence
;On exit, user correctly typed the random quote. All registers preserved

	PUSH SI AX DX BX

waitForStartingInput:
	MOV AH, 02h
	MOV DH, startTypingPos
	MOV DL, BYTE PTR actualCursorColumn
	INT 10h
	
	MOV AH, 11h
	INT 16h
	JNZ startProgram
	JMP waitForStartingInput
	
startProgram:
	MOV AH, 00h                                      ;Get clock tick
	INT 1Ah
	MOV prevTicks, DX                                ;prevTicks now has the starting time of the typing
	JMP getInput
	
loopTillQuoteIsTyped:
	CALL updateTimer
	MOV AH, 02h
	MOV DH, startTypingPos                           ;Set cursor row to be 7th row down (6)
	MOV DL, BYTE PTR actualCursorColumn              ;Set cursor column to the value cursorColumn
	INT 10h

waitForInput:
	MOV AH, 11h
	INT 16h
	JNZ getInput
	JMP toTheTop
	
getInput:	
	MOV AH, 10h
	INT 16h
	
	CMP AH, 53h                                      ;delete?
	JNE checkForLeftArrow
	MOV AX, typedQuoteLength
	CMP actualCursorColumn, AX
	JGE cannotDelete
		
	MOV SI, virtualCursorLocation	           
	MOV DI, SI				        ;With delete, the char the virtualCursor is pointing to will be removed (to pass to shiftToLeft)
	INC SI                                          ;SI points to the char to the right of DI so we can move all chars from the right to the left
						        ;(to pass to shiftToLeft)
		
	CALL shiftToLeft
	CALL displayTypedSentence
cannotDelete:
	JMP toTheTop
	
checkForLeftArrow:
	CMP AH, 4Bh                                     ;LEFT arrow?
	JNE checkForRightArrow
	CMP actualCursorColumn, 0
	JNE canMoveLeft
	JMP toTheTop
canMoveLeft:
	DEC actualCursorColumn
	DEC virtualCursorLocation
	JMP toTheTop
	
checkForRightArrow:
	CMP AH, 4Dh                                    ;RIGHT arrow?
	JNE checkForBackspace
	MOV AX, typedQuoteLength
	CMP actualCursorColumn, AX
	JL canMoveRight
	JMP toTheTop
canMoveRight:
	INC actualCursorColumn
	INC virtualCursorLocation
	JMP toTheTop
	
checkForBackSpace:	
	CMP AL, 8                                      ;backspace?
	JNE checkForASCIIChars
	CMP actualCursorColumn, 0
	JE cannotBackspace
	
	MOV SI, virtualCursorLocation	               ;SI now points to where the virtualCursor is in the usersTypedQuote (to pass to shiftToLeft)
	MOV DI, SI
	DEC DI                                         ;With backspace, the char before the virtualCursor is removed so need to put DI to one before
						       ;SI (to pass to shiftToLeft)
	
	CALL shiftToLeft
	CALL displayTypedSentence
	DEC virtualCursorLocation
	DEC actualCursorColumn
cannotBackspace:
	JMP toTheTop
		
checkForASCIIChars:
	CMP AL, 20h                                       
	JGE checkASCIICont                            ;Need to see if input value is between 20h (SPACE) and 7Eh (~)
	JMP toTheTop
checkASCIICont:
	CMP AL, 7Eh
	JG toTheTop
	
	CMP typedQuoteLength, 78
	JE toTheTop
	
	MOV BX, typedQuoteLength
	CMP actualCursorColumn, BX
	JE addToTheEnd
	CALL shiftToRight
	
addToTheEnd:
	MOV SI, virtualCursorLocation                ;Moving virtualCursorLocation into SI for use as pointer
	MOV [SI], AL
	INC typedQuoteLength
	CALL displayTypedSentence
	INC virtualCursorLocation
	INC actualCursorColumn 
	
toTheTop:
	CALL compareQuotes
	CMP finishedFlag, 1
	JE endProgram
	
continueProgram:
	JMP loopTillQuoteIsTyped

endProgram:
	POP BX DX AX SI
	RET
getUserTyping ENDP
;====================END getUserTyping============================

;====================START displayTypedSentence===================
;On entry, will clear the row where the typed sentence is output. Gets the memory location of usersTypedQuote and uses a loop to go through
;	the variable, outputting the char onto the screen.
;	Calls compareCurrentCharInQuotes to get what the current color should be and 
;	compareQuotes to set the finishedFlag if the typed quote is complete
;On exit, the contents of usersTypedQuote will be displayed on the screen
displayTypedSentence PROC
		PUSH SI DI AX BX
		
		MOV SI, 160 * startTypingPos
		MOV AH, 00000000b
		MOV AL, 0
		MOV CX, 80
clearTypedSentenceRow:
		MOV ES:[SI], AX
		ADD SI, 2
		LOOP clearTypedSentenceRow
		 
		MOV DX, randQuote                         ;Moving memory location of randQuote into DL to pass to compareCurrentCharInQuotes
		LEA SI, usersTypedQuote
		MOV DI, 160*startTypingPos
		MOV BX, 0
outputTypedSentenceLoop:
		MOV AL, [SI]                               ;Get current memory location of usersTypedQuote into AL to pass to compareCurrentCharInQuotes
		CALL compareCurrentCharInQuotes            ;Will change the currentColor whether the current letter is correct or not
		MOV AH, currentColor                       ;Just incase currentColor got changed from compareQuotes
		MOV ES:[DI], AX                            ;Output current char from usersTypedQuote with appropriate color
		INC SI                                     ;Go to next char in usersTypedQuote
		INC DX					   ;Go to next char in randQuote
		ADD DI, 2				   ;Go to next position on screen
		CMP BX, typedQuoteLength		   ;See if the current loop has finished outputting all of the usersTypedQuote
		JE leaveDisplayTypedProc
		INC BX
		JMP outputTypedSentenceLoop
leaveDisplayTypedProc:
		POP BX AX DI SI
		RET
displayTypedSentence ENDP
;===================END displayTypedSentence======================

;===================START compareCurrentCharInQuotes==============
compareCurrentCharInQuotes PROC
;On entry, AL contains the current char from the usersTypedQuote, DX contains the current memory location of the char from randQuote. 
;	Will compare the two and if they equal each other, the currentColor will be changed to GREEN. 
;	If they aren't equal, currentColor will be RED
;On exit, currentColor is changed to the appropriate color, all registers preserved
	PUSH AX DX SI
	
	MOV SI, DX                          ;Move memory location into SI so we can use a pointer
	MOV DL, [SI]                        ;Move char at memory location into DL
	MOV ES:[160*21], AX
	MOV currentColor, 00001010b         ;assume the user is smart and currentColor is GREEN
	CMP AL, DL
	JE smartUser
	MOV currentColor, 00001100b         ;dumb user, currentColor now RED
	
smartUser:
	POP SI DX AX
	RET
compareCurrentCharInQuotes ENDP
;==================END compareCurrentCharInQuotes===================

;==================START compareQuotes==============================
compareQuotes PROC
;One entry, no registers passed. Uses the memory location stored in randQuote and the variable usersTypedQuote and compares each char.
;	If the memory location in randQuote equals 0, the loop has reached the typedQuoteLength, or the comparing has found an error,
;	the loop will exit. If the loop number reaches the 0 in randQuote first and no errors were found, finishedFlag will be set to 1.
;	Else, finishedFlag will remain 0
;On exit, finishedFlag will either be a 0 or 1. 0 indicates the program needs to continue, 1 indicates the user has correctly typed the quote.
;	All registers preserved

	PUSH  CX SI DI AX BX
	
	MOV SI, randQuote                ;Get memory location of randQuote
	LEA DI, usersTypedQuote          ;Get memory location of usersTypedQuote
	MOV doubleTimeFlag, 0            ;Assume no error in sentence
	
comparingLoop:
	MOV BL, [SI]                     ;Move next char of randQuote into BL
	MOV AL, [DI]			 ;Move next char of usersTypedQuote into AL
	CMP BL, 0			 ;See if loop is at the end of randQuote
	JE endOfLoop			 ; if it is, get out of loop
	CMP BL, AL                       ;If not at the end of randQuote, see if BL and AL match
	JNE errorOccured 		 ; if not, the jump to errorOccured
	INC SI				 ;Go to next char in randQuote
	INC DI				 ;Go to nextChar in usersTypedQuote
	JMP comparingLoop
errorOccured:
	MOV doubleTimeFlag, 1            ;Error was found so change doubleTimeFlag to 1
	JMP leaveCompareProc
endOfLoop:
	MOV BX, randQuoteLength
	MOV AX, typedQuoteLength
	CMP AX, BX                       ;Need to compare lengths of randQuote and typedQuote. If equal, game finished
	JNE leaveCompareProc
	MOV finishedFlag, 1	    ;loop completed with no error
leaveCompareProc:
	POP BX AX DI SI CX
	RET
compareQuotes ENDP
;===================END compareQuotes=============================

;===================START shiftToLeft=============================
;On entry, SI and DI are passed into the function as arguments. DI contains the memory location from usersTypedQuote of the char the needs to be
;	erased. SI contains the memory location from usersTypedQuote of the char to the right of DI. Shifts all the chars in usersTypedQuote
;	to the left while erasing a single char.
;On exit, all registers preserved. A single char from usersTypedQuote will have been deleted and all the chars following it will have been shifted
;	to the left. The very last char in usersTypedQuote will be a ' ' to show the removal of the char
shiftToLeft PROC
	PUSH SI AX DI BX
	
	PUSH SI
	
	LEA SI, usersTypedQuote
	ADD SI, 78                                 ;gets the pointer for the end of usersTypedQuote
	MOV AX, SI
	
	POP SI
	
moveCharsLeft:
	MOV BX, [SI]                           
	MOV [DI], BX
	INC DI
	INC SI
	CMP SI, AX
	JNE moveCharsLeft
	
	MOV [SI], BYTE PTR ' '
	
	DEC typedQuoteLength
	
	POP BX DI AX SI
	RET
shiftToLeft ENDP
;===================END shiftToLeft===============================

;===================START shiftToRight============================
shiftToRight PROC
	PUSH SI DI AX BX
	
	LEA SI, usersTypedQuote
	ADD SI, 78                                 ;gets the pointer for the end of usersTypedQuote
	MOV DI, SI
	DEC DI                                     ;DI now points to char before SI
	
	MOV AX, virtualCursorLocation
	
moveCharsRight:
	MOV BX, [DI]
	MOV [SI], BX
	DEC DI
	DEC SI
	CMP SI, AX
	JNE moveCharsRight
	
	POP BX AX DI SI
	RET
shiftToRight ENDP
;==================END shiftToRight===============================

;====================START getQuoteArray==========================
getQuoteArray PROC
;On entry, nothing is passed. Will store the memory locations of all quotes into the variable, quoteArray
;On exit, all registers preserved, quoteArray will have memory locations for ten quotes

	PUSH BX DI SI CX
	
	LEA SI, quoteArray
	
	LEA DI, quote1                               ;puts memory location of quote1 into DI
	MOV [SI], DI
	ADD SI, 2				     ;Move to next position in quoteArray
	
	LEA DI, quote2
	MOV [SI], DI
	ADD SI, 2
	
	LEA DI, quote3
	MOV [SI], DI
	ADD SI, 2
	
	LEA DI, quote4                               
	MOV [SI], DI
	ADD SI, 2				     ;Move to next position in quoteArray
		
	LEA DI, quote5
	MOV [SI], DI
	ADD SI, 2
		
	LEA DI, quote6
	MOV [SI], DI
	ADD SI, 2
	
	LEA DI, quote7                               
	MOV [SI], DI
	ADD SI, 2				     ;Move to next position in quoteArray
		
	LEA DI, quote8
	MOV [SI], DI
	ADD SI, 2
		
	LEA DI, quote9
	MOV [SI], DI
	ADD SI, 2
	
	LEA DI, quote10
	MOV [SI], DI
	ADD SI, 2
	
	
	POP CX SI DI BX
	RET
	
getQuoteArray ENDP
;====================END getQuoteArray=============================

;===================START getRandomQuote===========================
getRandomQuote PROC
;On entry, nothing passed. Uses INT 1Ah FUNC 00h to get the clock ticks (stored in DX) for the seed of a random number generator.
;	uses the method, r1 := (7*r0)%101 and r2 := (r1-1)%10 to get a number between 0-9. Then multiply r2 by 2 because the array used
; 	is an array of DW so we need to move in steps of 2. The memory location of quoteArray is put into SI, the random number is added to
;	SI, and the corresponding quote is moved into the variable randQuote.
;On exit, randQuote will now store the memory location of a randomly chosen quote. All registers preserved

	PUSH AX BX DX SI DI
	
	MOV AH, 00h                 ;Get clock tick
	INT 1Ah
			
	MOV AX, DX                  ;gets the current clock tick in seconds for random number generator. AX := r0
	MOV BX, 7
	MUL BX
	MOV BX, 101
	DIV BX                      ;r1 := (7 * r0) % 101
	DEC DX
	MOV AX, DX
	MOV DX, 0
	MOV BX, 10
	DIV BX                      ;r2 := (r1 - 1) % 10
	MOV BX, 2
	MOV AX, DX
	MOV DX, 0
	MUL BX                      ;randNum (AX) := r2 * 2 (need an even number because quoteArray is full of DW so need to move 2 spaces)
	
	;MOV SI, 160*12 +40
	;CALL convertNumToASCII
	
	LEA SI, quoteArray          ;Get memory location of quoteArray
	LEA DI, quoteLengths        ;Get memory location of quoteLengths
	
	MOV BX, SI                  ;Move memory location of quoteArray into BX so we can manipulate it
	MOV DX, DI		    ;Move memory location of quoteLengths into DX so we can manipulate it
	
	ADD BX, AX                  ;Add the offset (randNum) to memory location to get a random quote
	ADD DX, AX		    ;Add the offset {randNum) to memory location of quoteLengths to get the randQuote length
	
	MOV SI, BX                  ;Move changed memory location back into SI so we can use a pointer
	MOV DI, DX
	MOV BX, [SI]                ;Need to move the values into BX/DL first 
	MOV DX, [DI]
	MOV randQuote, BX           ;Move the randomly chosen quote into the variable, randQuote
	MOV randQuoteLength, DX     ;Move the randomly chosen quote length into the variable, randQuoteLength
	
	;MOV SI, 160*13 +40
	;MOV AL, randQuoteLength
	;CALL convertNumToASCII
	
	POP DI SI DX BX AX
	RET
getRandomQuote ENDP
;====================END getRandomQuote============================

;====================START displayRandomQuote==============================
displayRandomQuote PROC
;On entry, nothing passed. Gets the memory location stored in randQuote(which should be filled by this point) and outputs 
;	the quote to the screen.
;On exit, the contents of randQuote will be displayed on screen. All registers preserved/

	PUSH SI AX DI
	
	MOV SI, randQuote
	MOV AH, 00001111b
	MOV DI, 160*5
	
loop1:
	MOV AL, [SI]
	CMP AL, 0
	JE leaveDisplayLoop
	MOV ES:[DI], AX
	INC SI
	ADD DI, 2
	JMP loop1
	
leaveDisplayLoop:
	
	POP DI AX SI
	RET
displayRandomQuote ENDP
;====================END displayRandomQuote=========================

;====================START updateTimer==============================
updateTimer PROC
;On entry, uses value in prevTicks to calculate the amount of time has passed the start of the timer. Updates value in prevTicks and
;	totalDeltaTicks in the end. Checks the doubleTimeFlag to see if we need to add the time twice
;On exit, totalDeltaTicks will be update to the current amount of time that has passed and prevTicks will be update for next time this
;	proc is called. All registers preserved
	PUSH AX DX CX 
	
	MOV AH, 00h                 ;Get clock tick
	INT 1Ah		            
	MOV AX, prevTicks
	MOV prevTicks, DX
	SUB DX, AX		    ;DX contains the current amount of ticks
	ADD totalDeltaTicks, DX     ;DX now contains the deltaTicks (currTicks - prevTicks) so it gets added to totalDeltaTicks
	CMP doubleTimeFlag, 1
	JE addTimeTwice
	JMP updateTimerOnScreen

addTimeTwice:
	ADD totalDeltaTicks, DX

updateTimerOnScreen:
	CALL changeOnScreenTimer
	
	POP CX DX AX
	RET
updateTimer ENDP
;=====================END updateTimer===============================

;=====================START changeOnScreenTimer=====================
changeOnScreenTimer PROC
;On entry, gets value in totalDeltaTicks and converts it to tenths of seconds (1 tick = 0.55 tenth of seconds). Then the value is displayed
;	on screen.
;On exit, timer is update on screen. All registers preserved.
	PUSH SI AX DX BX
	
	MOV SI, 160*3 + 150
	MOV AX, totalDeltaTicks	   ;Get the current total ticks
	MOV BX, 55                 ;Need to mult totalDeltaTicks by 55
	MUL BX
	MOV BX, 100                ;Now need to divide by 100 to get tenths of seconds
	DIV BX
;TIME SHOULD NOW BE CONVERTED TO TENTHS OF SECONDS IN AX
	MOV DX, 0	           ;clear remainder from last division
	MOV BX, 10
	DIV BX			   ;Need to divide value in DX:AX by ten to get the base ten number of the time
	ADD DL, '0'		   ;DX contains 0..9 so add '0' to DL to get the ASCII value
	MOV DH, 00001111b
	MOV ES:[SI], DX            ;puts the number onto the screen with white on black coloring
	SUB SI, 2
	MOV DL, '.'
	MOV ES:[SI], DX            ;puts a period onto the screen with white on black coloring
	SUB SI, 2
convertLoop:
	MOV DX, 0                  ;Convert the rest of the totalDeltaTicks into ASCII chars with this loop
	DIV BX			
	ADD DL, '0'
	MOV DH, 00001111b
	MOV ES:[SI], DX
	SUB SI, 2
	CMP AX, 0		   ;Will end when there is no remainder left
	JNE convertLoop
	
	POP BX DX AX SI
	RET
changeOnScreenTimer ENDP
;=====================END changeOnScreenTimer========================

;==========START testOutputOfQuotes=========================
testOutputOfQuotes PROC
;On entry, nothing passed. Uses the variable quoteArray (which should be filled at this point).
;	Will output the 10 quotes on the screen, one under another.
;	FOR TESTING PURPOSES ONLY! 
;On exit, the contents of quoteArray is displayed on screen. All registers preserved.

	PUSH SI DI CX AX
	
	LEA SI, quoteArray
	
	MOV DI, 160*5
	
	MOV CX, 10
	
	MOV AH, 00001111b
	
outputOuterLoop:
	PUSH DI SI
	MOV SI, [SI]
	MOV AL, [SI]
	
outputInnerLoop:
	MOV ES:[DI], AX
	ADD DI, 2
	INC SI
	MOV AL, [SI]
	CMP AL, 0
	JNE outputInnerLoop
	POP SI DI
	ADD DI, 160
	ADD SI, 2
	LOOP outputOuterLoop
	
	
	POP AX CX DI SI
	RET
testOutputOfQuotes ENDP
;====================END testOutputOfQuotes============================

;====================START convertNumToASCII===========================
convertNumToASCII PROC
;On entry, put some unsigned integer into AX (line 12). BL contains the number of the base to convert to
;	put a number into (line 15). SI for output onto screen (line 16). Has ability to loop if multiple numbers are needed.
; 	If you do this, the numbers will be below one another (uncomment lines 51 and 52 to enable this). 
;	DX is what is output, so DH is auto set for white on black. Has ability to stop numbers from going above 255
;	(Comment line 49 to disable this).
;On exit, converts the number put into AX into what ever base thats in BL and outputs it to screen, all registers preserved
	
	PUSH AX SI CX DX DI BX
	
	;MOV AX, 5                ;Erase everything in AX
	;MOV AL, startInt          ;Move starting integer into AL for division
	;MOV AL, AH
	MOV AH, 0
	MOV DH, 00001111b         ;Going to output DX to screen so put current color into DH
	MOV BL, 10
	;MOV SI, 160*15 + 40
convertLoopOuter:
	PUSH SI AX                ;Store starting position of output and the current integer for easy access
	MOV DI, 0                 ;Resets DI to use as counter for how many integers have been outputted

convertLoopInner:
	DIV BL                    ;Convert the integer in AL by whatever base was passed in BL
	CMP AH, 10                ;Compare the remainder of teh division to 10 to know if we need to change it to a letter or not
	JGE letter
	ADD AH, '0'               ;Converts the number to an ASCII code for output
	JMP bottomOfLoop
letter:
	ADD AH, 55                ;Add 55 to the remainder which would be 10-15 to get the correct letter to output (65 is ASCII for A)
bottomOfLoop:
	MOV DL, AH
	MOV ES:[SI], DX           ;Put the conversion onto th screen
	SUB SI, 2                 ;Move left to allow for another output
	INC DI                    ;Increase DI by 1 to see if we need to put a 0 infront of a letter for HEX
	MOV AH, 0                 ;Get rid of the remainder because it is no longer necessary and could screw up future divisions
	CMP AL, 0                 ;Check to see if the conversion is finished
	JG convertLoopInner
	
	CMP BL, 16                ;See if we converted to HEX
	JNE notHex
	CMP DI, 1                 ;See if we need to output a 0 infront of a HEX number
	JNE notHex
	ADD AL, '0'               ;Add '0' to AL because AL already contains a 0 so we need to convert it to ASCII
	MOV DL, AL
	MOV ES:[SI], DX           ;Output 0 to screen 

notHex:
	POP AX SI                 ;restores AX and SI so we can restart and move to next integer
	INC AX
	AND AX, 0FFh		  ;Make sure never get >255
continueAsIs:
	;ADD SI, 160               ;Move to next row
	;LOOP convertLoopOuter     ;Continues to fill in the column based on the CX counter passed into the PROC
	
	POP BX DI DX CX SI AX
	
	RET
convertNumToASCII ENDP
;==========END convertNumToASCII============


MyCode ENDS
END mainProc