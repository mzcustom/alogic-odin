package main

import rl "vendor:raylib"
import fmt "core:fmt"
import strings "core:strings"
import math "core:math"
import rand "core:math/rand"
import time "core:time"
import reflect "core:reflect"

// Constants
FPS                 :: 60
WINDOW_WIDTH        :: 560
WINDOW_HEIGHT       :: 800
UPPER_LAND_HEIGHT   :: WINDOW_WIDTH
MARGIN_HEIGHT       :: WINDOW_HEIGHT/40
MARGIN_WIDTH        :: MARGIN_HEIGHT
TITLE_WIDTH         :: WINDOW_WIDTH*0.75
TITLE_HEIGHT	    :: WINDOW_HEIGHT*0.2
MIN_TITLE_HEIGHT    :: TITLE_HEIGHT*0.5
TITLE_LANDING_Y     :: MARGIN_HEIGHT + ROW_HEIGHT
NUM_ROW             :: 4
NUM_COL             :: 4
ROW_HEIGHT          :: (UPPER_LAND_HEIGHT - 2 * MARGIN_HEIGHT) / NUM_ROW 
COL_WIDTH           :: (WINDOW_WIDTH - 2 * MARGIN_WIDTH) / NUM_COL
ANIM_SIZE           :: f32(ROW_HEIGHT * 0.65)
DUST_IMAGE_WIDTH    :: 320
DUST_IMAGE_HEIGHT   :: 256
MIN_ANIM_HEIGHT	    :: WINDOW_HEIGHT/160
MIN_JUMP_HEIGHT     :: MIN_ANIM_HEIGHT * 3
JUMP_SCALE_INC_RATE :: 0.075
MAX_DUST_DURATION   :: FPS/3
FRONT_ROW_Y         :: MARGIN_HEIGHT + (NUM_ROW - 1)*ROW_HEIGHT + ROW_HEIGHT/2
RESQUE_SPOT_X       :: MARGIN_WIDTH + (WINDOW_WIDTH - 2 * MARGIN_WIDTH) / 2 
RESQUE_SPOT_Y       :: (UPPER_LAND_HEIGHT + 7 * MARGIN_HEIGHT) + 
                       (WINDOW_HEIGHT - (UPPER_LAND_HEIGHT + 7 * MARGIN_HEIGHT)) / 2 
DEFAULT_FONT_SIZE   :: 24
MAX_MSG_LEN         :: DEFAULT_FONT_SIZE*1.8
MSG_POS_Y           :: UPPER_LAND_HEIGHT - MARGIN_HEIGHT
BOARD_SIZE          :: NUM_ROW * NUM_COL
FRONT_ROW_BASEINDEX :: BOARD_SIZE - NUM_COL
NUM_COLOR           :: 4
NUM_KIND            :: 4
NUM_GAME_MODE       :: 5
TOTAL_BIG_JUMP      :: 2

INDEFINITE          :: -1

// Raylib input int32 map
MOUSE_L     :: rl.MouseButton.LEFT
MOUSE_R     :: rl.MouseButton.RIGHT
KEY_A       :: rl.KeyboardKey.A 
KEY_S       :: rl.KeyboardKey.S
KEY_D       :: rl.KeyboardKey.D
KEY_F       :: rl.KeyboardKey.F
KEY_G       :: rl.KeyboardKey.G
KEY_Q       :: rl.KeyboardKey.Q
KEY_SPACE   :: rl.KeyboardKey.SPACE

// Type alias
Vec2 :: rl.Vector2

// Vec2 math
Vec2LenSq :: proc(v: Vec2) -> f32 { return v.x*v.x + v.y*v.y }

// GameMode Enums
GameMode :: enum {
    TITLE, 
    OPENING,
    GAME_PLAY,
    GAME_CLEAR,
    GAME_OVER,
}

// Asset structs
Textures :: struct {
    TitleTexture: rl.Texture2D,
    GroundTexture: rl.Texture2D,
    AnimalsTexture: rl.Texture2D,
    DustTexture: rl.Texture2D,
}

Sounds :: struct {
    JumpSound: rl.Sound,
    BigJumpSound: rl.Sound,
    TitleJump: rl.Sound,
    TitleLand: rl.Sound,
    Start: rl.Sound,
    Jump: rl.Sound,
    BigJump: rl.Sound,
    Land: rl.Sound,
    BigLand: rl.Sound,
    Success: rl.Sound,
    Fail: rl.Sound,
    Yay: rl.Sound,
}

// Message board system
Message :: struct {
    l1: string,
    l2: string,
    duration: int,
    frames: int,
    displayed: bool,
    alpha: u8,
    gameMode: GameMode,
}

Scripts :: struct {
    msgs: [NUM_GAME_MODE][dynamic]Message,
}

// TITLE GameMode states
TitleState :: struct {
    destForOpening: [3]Vec2,
    titleFrame: int,
    animToDrop: int,
    titleDropFrame: int,
    firstCompressFrame: int,
    lastAnimDropFrame: int,
    titlePressFrame: int,
    lastAnimJumpFrame: int,
    secondCompressFrame: int,
    fallOutFrame: int,
    titleMessageShown: bool,
    sceneEnd: bool,
}

// GamePlay GameMode states
GamePlayState :: struct {
    resquableIndex: [NUM_COL]int,
    resquedChanged: bool,
    firstMoveMade: bool,  
    bigJumpMade:  bool, 
    lastMsgShown: bool,
    numAnimalLeft: u8,
    bigJumpLeft: u8,
    mostRecentResqueType: u8,
    numNextMoves: u8,
}

// accel, veloc and press in pixels/frame.
TitleLogo :: struct {
    using pos: Vec2,
    dest: Vec2,
    accel: Vec2,
    veloc: Vec2,
    height: f32,
    press: f32,
}

/*
Animal.type: High 4 bits - a bit fields of "color" ordered as blue-green-red-yellow
             Low 4 bits  - a bit fields of "kind" ordered as cat-giraffe-owl-panda 
             For instance, 0x00100001 is red panda and 0x10000100 is blue giraffe. 
             Its type has to be bumped up to u16 when adding more colors or kinds. 
*/
Animal :: struct {
    using pos: Vec2,
    dest: Vec2,
    accel: Vec2,
    veloc: Vec2,
    scale: f32,
    height: f32,
    press: f32,
    scaleDecRate: f32,
    dustDuration: u8,
    totalJumpFrames: u8,
    ascFrames: u8,
    currJumpFrame: u8,
    type: u8,
}

// Global Variables
textures: Textures  
sounds: Sounds
gameMode: GameMode
msg: Message
scripts: Scripts

// For DEBUG
printbd :: proc(board: ^[BOARD_SIZE]^Animal) {
    for row := 0; row < NUM_ROW; row += 1 {
        for col := 0; col < NUM_COL; col += 1 {
            anim := board[row*NUM_COL + col]
            if anim == nil { 
                fmt.printf("00000000 ") 
            } else { 
                fmt.printf("%08b ", anim.type)
            }
        }
        fmt.printf("\n")
    }
}

findFirst1Bit :: proc(target : u8) -> (order : int) {
    b := u8(1)
    for target & b == 0 { 
        b <<= 1
        order += 1
    }
    return
}

setTitleLogo :: proc(title: ^TitleLogo) {
    title.x = (WINDOW_WIDTH - TITLE_WIDTH)*0.5
    title.y = -TITLE_HEIGHT
    title.height = TITLE_HEIGHT
    title.dest = Vec2{title.x, TITLE_LANDING_Y} 
}

updateTitle :: proc(title: ^TitleLogo) {
    if title.press > 0 {
        title.height -= title.press 	
        if title.height < MIN_TITLE_HEIGHT {
            title.height = MIN_TITLE_HEIGHT
            title.press = -1
        } else {
            title.press /= 1.75
            if title.press < 0.0001 {
                title.press = -1
            }
        }
    }
    if title.press < 0 {
        title.height -= title.press
        if title.height >= TITLE_HEIGHT {
            title.height = TITLE_HEIGHT
            title.press = 0
        } else {
            title.press *= 1.75
        }
    }

    // Update Pos and Veloc if it's moving or has accel
    if ((title.veloc != {}) || (title.accel != {})) && title.press == 0 {
        title.pos += title.veloc
        title.veloc += title.accel
	     
        // take care of landing
        if title.veloc.y > 0 && Vec2LenSq(title.pos - title.dest) < Vec2LenSq(title.veloc)/2 {
            title.press = title.veloc.y*0.5
            title.pos = title.dest
            if title.veloc.y >= 2 {
                title.veloc.y *= -0.5 
            } else {
                title.press = 0
                title.veloc, title.accel = {}, {}
            }
        }
    }
}

drawTitle :: proc(title: ^TitleLogo) {
    srcRect := rl.Rectangle{0, 0, TITLE_WIDTH , TITLE_HEIGHT}
    desPos := Vec2{title.pos.x, title.pos.y + TITLE_HEIGHT - title.height}
    desRect := rl.Rectangle{desPos.x, desPos.y, TITLE_WIDTH, title.height}
    rl.DrawTexturePro(textures.TitleTexture, srcRect, desRect, Vec2{}, 0, rl.RAYWHITE)
}

setAnimals :: proc(animals: ^[BOARD_SIZE]Animal) {
    color, kind := u8(1), u8(1)

    for row := 0; row < NUM_ROW; row += 1 {
        colorBit := color << NUM_KIND
        for col := 0; col < NUM_COL; col += 1 {
            boardIndex := row * NUM_COL + col
            animals[boardIndex].height = ANIM_SIZE 
            animals[boardIndex].type = colorBit | kind
            animals[boardIndex].scale = 1
            kind <<= 1
        }
        kind = 1
        color <<= 1
    }
}

/*
Starting with the first index, swaps the element with that of a randomly chosen 
index that's greater than the current index until reaching the 2nd last index. Swap first with last.
Assign pos of Animals according to the index
*/
shuffleBoard :: proc(board: ^[BOARD_SIZE]^Animal, frontRowPos: ^[NUM_COL]Vec2) {
    for i := 0; i < BOARD_SIZE - 1; i += 1 {
        indexToSwap := i + 1 + int(math.floor_f32(rand.float32() * f32(BOARD_SIZE - i - 1)))
        board[i], board[indexToSwap] = board[indexToSwap], board[i]
    }
    board[0], board[BOARD_SIZE - 1] = board[BOARD_SIZE - 1], board[0]

    for row := 0; row < NUM_COL; row += 1 {
        posY := f32(MARGIN_HEIGHT + (row*ROW_HEIGHT) + (ROW_HEIGHT/2))
        for col := 0; col < NUM_ROW; col += 1 {
            boardIndex := row*NUM_COL + col
            posX := f32(MARGIN_WIDTH + (col*COL_WIDTH) + (COL_WIDTH/2))
            board[boardIndex].dest = {posX, posY}
            board[boardIndex].pos = {posX, posY - f32(4*ROW_HEIGHT)}
        }
    }
    for i := 0; i < NUM_COL; i += 1 {
        frontRowIndex := BOARD_SIZE - NUM_COL + i
        frontRowPos[i] = board[frontRowIndex].dest
    }
}


// Returns the number of animals that could be chosen from the front row(last NUM_COL elements of 
// the board) and fills the nextAnimIndexes array with the indexes of them
findResquables :: proc(board: ^[BOARD_SIZE]^Animal, mostRecentRescuedType: u8, 
                       nextAnimIndexes: ^[NUM_COL]int) -> (numNextMoves: u8) {
    frontRowOffset := BOARD_SIZE - NUM_COL

    for i := 0; i < NUM_COL; i += 1 {
        if board[i + frontRowOffset] != nil && 
           (board[i + frontRowOffset].type & mostRecentRescuedType != 0) {
            nextAnimIndexes[i] = i + frontRowOffset
            numNextMoves += 1
        }
    }
    return
}

// totalFrames: the total duration of the jump in frames.
// ascFrames: the duration of animal moving upward ing in frames.
// if dest.Y is greater than anim.pos.Y, ascFrames has to be less than totalFrames/2
// and dest.Y is less than anim.pos.Y, ascFrames has to be greater than totalFrmaes/2
// TotalFrames CANNOT be exactly 2*ascFrames otherwise divided by 0 occurs
jumpAnimal :: proc(anim: ^Animal, dest: Vec2, totalFrames, ascFrames: f32) {

    // desFrames: frames left at the its original position while desending to dest
    desFrames := totalFrames - ascFrames
	
    //veloc = -accel * ascFrames (accel is positive)
    //leastAlt = anim.pos.Y + 0.5*ascFrames*veloc (veloc is negative)
    //dest.Y = leastAlt + 0.5*accel*(desFrame)^2
    diff: f32
    if anim.y == dest.y {
        diff = -ANIM_SIZE
    } else {
        diff = dest.y - anim.y
    }
    anim.accel = {0, 2*diff/(desFrames*desFrames - ascFrames*ascFrames) }
    anim.veloc = {(dest.x - anim.x)/totalFrames, -anim.accel.y*ascFrames}
    anim.dest = dest
    anim.totalJumpFrames = u8(totalFrames)
    anim.ascFrames = u8(ascFrames)
    anim.currJumpFrame = 0
	
    if anim.height < ANIM_SIZE { anim.press = -anim.height*0.1}
    
    if anim.dest.x == RESQUE_SPOT_X && anim.dest.y == RESQUE_SPOT_Y {
        if gameMode == GameMode.GAME_PLAY && anim.height <= MIN_JUMP_HEIGHT { 
            rl.PlaySound(sounds.BigJump)
        } else {
            if gameMode != GameMode.GAME_CLEAR { rl.PlaySound(sounds.Jump) }
        }
    }
}

resqueAt :: proc(board, resqued: ^[BOARD_SIZE]^Animal, resqueIndex, numAnimalLeft: u8) {
    i := resqueIndex			  
    anim := board[i]
    assert(anim.type != 0)

    ascFrames := 2.5 * ANIM_SIZE/anim.height
    totalFrames := FPS/3 + ascFrames
    if ascFrames < FPS/15  { ascFrames, totalFrames = FPS/15, FPS/3 }
    jumpAnimal(anim, Vec2{RESQUE_SPOT_X, RESQUE_SPOT_Y}, totalFrames, ascFrames)
    resqued[BOARD_SIZE - numAnimalLeft] = anim

	// Advance the row where the selected animal is at 
    for i >= 0 && board[i] != nil {
        if i < NUM_COL || board[i - NUM_COL] == nil { 
            board[i] = nil
            break
        } else {
            board[i] = board[i - NUM_COL]
            anim := board[i]
            jumpAnimal(anim, Vec2{anim.x, anim.y + ROW_HEIGHT}, FPS/3, FPS/10)
        }
        i -= NUM_COL
    }
}

drawAnimal :: proc(anim: ^Animal) {
    colorBitfield := anim.type >> NUM_KIND
    kindBitfield := anim.type & 0b1111
    colorOffset := NUM_COLOR - 1 - findFirst1Bit(colorBitfield)
    kindOffset := NUM_KIND - 1 - findFirst1Bit(kindBitfield)
    srcRect := rl.Rectangle{f32(kindOffset)*ANIM_SIZE, f32(colorOffset)*ANIM_SIZE,
                            ANIM_SIZE, ANIM_SIZE}
	
    if anim.totalJumpFrames > 0 {
        if anim.currJumpFrame <= anim.ascFrames {
            anim.scale += JUMP_SCALE_INC_RATE
            if anim.currJumpFrame == anim.ascFrames { 
                anim.scaleDecRate = (anim.scale - 1) / f32(anim.totalJumpFrames - anim.ascFrames)
            }
        } else {
            anim.scale -= anim.scaleDecRate 
            if anim.scale < 1 { anim.scale = 1 }
        }
    }
	
    sc := anim.scale
    animOrigin := anim.pos - Vec2{sc*ANIM_SIZE*0.5, sc*ANIM_SIZE*0.5}
    desPos := animOrigin + Vec2{0, sc*ANIM_SIZE - sc*anim.height}
    desRect := rl.Rectangle{desPos.x, desPos.y, sc*ANIM_SIZE, sc*anim.height}

    rl.DrawTexturePro(textures.AnimalsTexture, srcRect, desRect, Vec2{}, 0, rl.RAYWHITE)
	
    // Draw dust
    if anim.dustDuration != 0 { 
        srcRect := rl.Rectangle{0, 0, DUST_IMAGE_WIDTH, DUST_IMAGE_HEIGHT}
        desRect := rl.Rectangle{anim.x - ANIM_SIZE*0.7, anim.y + ANIM_SIZE*0.4, 
                                ANIM_SIZE*0.5, ANIM_SIZE*0.15} 
        rl.DrawTexturePro(textures.DustTexture, srcRect, desRect, Vec2{}, 0, rl.RAYWHITE)

        desRect = rl.Rectangle{anim.x + ANIM_SIZE*0.2, anim.y + ANIM_SIZE*0.4,  
                               ANIM_SIZE*0.5, ANIM_SIZE*0.15} 
        rl.DrawTexturePro(textures.DustTexture, srcRect, desRect, Vec2{}, 0, rl.RAYWHITE)
        anim.dustDuration -= 1
    }
}

isAnimRectClicked :: proc(anim: ^Animal) -> bool {
    if anim == nil { return false }

    mouseX := f32(rl.GetMouseX())
    mouseY := f32(rl.GetMouseY())
    halfLength := ANIM_SIZE/2

    when ODIN_DEBUG {
        fmt.printf("Mouse Clicked at : %d, %d\n", mouseX, mouseY)
        fmt.printf("AnimPos : %d, %d\n", anim.x, anim.y)
    }

    return mouseX >= anim.x - halfLength && mouseX <= anim.x + halfLength &&
           mouseY >= anim.y - halfLength && mouseY <= anim.y + halfLength   
}

loadAssets :: proc() {
    titleImage := rl.LoadImage("assets/textures/title.png")
    groundImage := rl.LoadImage("assets/textures/background.png")
    animalsImage := rl.LoadImage("assets/textures/animals.png")
    dustImage := rl.LoadImage("assets/textures/dust.png")
    
    rl.ImageResize(&titleImage, TITLE_WIDTH, TITLE_HEIGHT)
    rl.ImageResize(&groundImage, WINDOW_WIDTH, WINDOW_HEIGHT)
    rl.ImageResize(&animalsImage, i32(ANIM_SIZE*NUM_COL), i32(ANIM_SIZE*NUM_ROW))

    textures.TitleTexture = rl.LoadTextureFromImage(titleImage)
    textures.GroundTexture = rl.LoadTextureFromImage(groundImage)
    textures.AnimalsTexture = rl.LoadTextureFromImage(animalsImage)
    textures.DustTexture = rl.LoadTextureFromImage(dustImage)
    
    rl.UnloadImage(titleImage)
    rl.UnloadImage(groundImage)
    rl.UnloadImage(animalsImage)
    rl.UnloadImage(dustImage)

    sounds.TitleJump = rl.LoadSound("assets/sounds/titlejump.mp3")
    sounds.TitleLand = rl.LoadSound("assets/sounds/titleland.mp3")
    sounds.Start = rl.LoadSound("assets/sounds/start.mp3")
    sounds.Jump = rl.LoadSound("assets/sounds/jump.wav")
    sounds.BigJump = rl.LoadSound("assets/sounds/bigjump.mp3")
    sounds.Land = rl.LoadSound("assets/sounds/land.mp3")
    sounds.BigLand = rl.LoadSound("assets/sounds/bigland.mp3")
    sounds.Success = rl.LoadSound("assets/sounds/success.mp3")
    sounds.Fail = rl.LoadSound("assets/sounds/fail.mp3")
    sounds.Yay = rl.LoadSound("assets/sounds/yay.mp3")
    sounds.Fail = rl.LoadSound("assets/sounds/fail.mp3")
}

unloadSounds :: proc() {
    fieldNames := reflect.struct_field_names(type_of(sounds))
    for fieldName in fieldNames {
        rl.UnloadSound(reflect.struct_field_value_by_name(sounds, fieldName).(rl.Sound))
    }
}

findLastRowEmpties :: proc(board: ^[BOARD_SIZE]^Animal, empties: ^[NUM_COL]bool) -> (emptyColCount: int) {
    for i := 0; i < NUM_COL; i += 1 {
        if board[i] == nil {
            empties[i] = true
            emptyColCount += 1
        }
    }
    return
}

moveResquedToBoard :: proc(board, resqued: ^[BOARD_SIZE]^Animal, boardIndex, resquedIndex: int,
                           numAnimalLeft: ^u8, resquedChanged: ^bool) {
    i := boardIndex
    animToPush := resqued[resquedIndex]
    resqued[resquedIndex] = nil

    for i >= 0 {
        nextAnimToPush := board[i]
        board[i] = animToPush
        if nextAnimToPush != nil {
            jumpAnimal(nextAnimToPush, nextAnimToPush.pos - Vec2{0, ROW_HEIGHT}, 20, 12) 
            animToPush = nextAnimToPush
            i -= NUM_COL
        } else { 
            break 
        }
    }

    numAnimalLeft^ += 1
    resquedChanged^ = true
}

scatterResqued :: proc(board, resqued: ^[BOARD_SIZE]^Animal, maxIndexToScatter: int, 
                       frontRowPos: ^[NUM_COL]Vec2, numAnimalLeft: ^u8, resquedChanged: ^bool) {
    lastRowEmptyIndices := [NUM_COL]bool{}
    emptyCount := findLastRowEmpties(board, &lastRowEmptyIndices)
    indexToMoveToBoard := maxIndexToScatter

    for i := 0; i < NUM_COL; i += 1 {
        if lastRowEmptyIndices[i] {
            jumpAnimal(resqued[indexToMoveToBoard], frontRowPos[i], 24, 16)
            frontRowIndexToJump := BOARD_SIZE - NUM_COL + i
            moveResquedToBoard(board, resqued, frontRowIndexToJump, indexToMoveToBoard,
                               numAnimalLeft, resquedChanged)
            indexToMoveToBoard -= 1
            emptyCount -= 1
            if indexToMoveToBoard < 0 || emptyCount < 1  { 
                break
            }
        }
    }

    resqued[indexToMoveToBoard + 1] = resqued[maxIndexToScatter + 1]
    resqued[maxIndexToScatter + 1] = nil
}

updateAnimState :: proc(animals: ^[BOARD_SIZE]Animal, board, resqued: ^[BOARD_SIZE]^Animal, 
                        frontRowPos: ^[NUM_COL]Vec2, gpState: ^GamePlayState) -> bool {
    using gpState
    isAllUpdated := true

    for _, i in animals {
        anim := &animals[i]
        // Update Press and Height 
        if anim.press > 0 {
            anim.height -= anim.press 	
            if anim.height < MIN_ANIM_HEIGHT {
                anim.height = MIN_ANIM_HEIGHT
            }
            anim.press *= 0.5
            if anim.press < 0.0001 {
                anim.press = -1
            }
        }
        if anim.press < 0 {
            if anim.height - anim.press >= ANIM_SIZE {
                anim.height = ANIM_SIZE
                anim.press = 0
            } else {
                anim.height -= anim.press
                anim.press *= 2
            }
        }

        // Update Pos and Veloc if it's moving or has accel
        if anim.veloc != {} || anim.accel != {} {
            isAllUpdated = false
            anim.pos += anim.veloc
            anim.veloc += anim.accel
            if anim.totalJumpFrames > 0 { anim.currJumpFrame += 1 }

            // Take care of landing
            if Vec2LenSq(anim.pos - anim.dest) < Vec2LenSq(anim.veloc)/2 {
                if gameMode == GameMode.GAME_PLAY && 
                   anim.ascFrames > anim.totalJumpFrames/2 && anim.dest.y == FRONT_ROW_Y {
                    rl.PlaySound(sounds.Yay)
                }
                if anim.veloc.y <= FPS {
                    if anim.veloc.y > FPS/2 { 
                        anim.press = anim.veloc.y/3 
                        if gameMode == GameMode.GAME_PLAY { rl.PlaySound(sounds.Land) }
                    }
                } else {
                    anim.press = anim.veloc.y/3 
                    anim.dustDuration = MAX_DUST_DURATION
                    if anim.dest.x == RESQUE_SPOT_X && anim.dest.y == RESQUE_SPOT_Y {
                        rl.PlaySound(sounds.BigLand)
                    } else {
                        rl.PlaySound(sounds.Land) 
                    }
                }
                // if the landing animal is the last resqued(the one crossing the bridge)
                lastResquedIndex := BOARD_SIZE - 1 - numAnimalLeft
                if gameMode == GameMode.GAME_PLAY && lastResquedIndex > 0 && 
                   anim == resqued[lastResquedIndex] {
                        // when a big jump is made, send previously resqued animals back to the land
                        if anim.veloc.y > FPS && bigJumpLeft > 0 {
                        bigJumpMade = true
                        scatterResqued(board, resqued, int(lastResquedIndex - 1), frontRowPos,
                                       &numAnimalLeft, &resquedChanged)
                        bigJumpLeft -= 1
                        if lastMsgShown && bigJumpLeft == 1 { setMsg(GameMode.GAME_PLAY, 3) }
                        if bigJumpLeft == 0 { setMsg(GameMode.GAME_PLAY, 4) }
                    } else {
                        // For regular jumps, compress and move the previously resqued sideway
                        prevAnimIndex := lastResquedIndex - 1
                        prevAnim := resqued[prevAnimIndex]
                        prevAnim.press = ANIM_SIZE
                        pushFactor := f32(prevAnimIndex/2 + 1)
                        pushDist := Vec2{pushFactor*ANIM_SIZE*0.25, 0}
                        pushAccel := Vec2{pushFactor*ANIM_SIZE*0.075, 0}
                        pushVeloc := Vec2{pushFactor*ANIM_SIZE*0.15, 0}
                        if prevAnimIndex % 2 == 0 {
                            prevAnim.dest = prevAnim.pos - pushDist
                            prevAnim.accel = pushAccel 
                            prevAnim.veloc = -pushVeloc
                        } else {
                            prevAnim.dest = prevAnim.pos + pushDist
                            prevAnim.accel = -pushAccel
                            prevAnim.veloc = pushVeloc 
                        }
                    }
                }

                anim.pos = anim.dest
                anim.veloc, anim.accel = {}, {}
                anim.scale = 1
                anim.scaleDecRate = 0
                anim.totalJumpFrames = 0
                anim.ascFrames = 0
                anim.currJumpFrame = 0
            }
        }
    }

    return isAllUpdated
}

resetAnimalsAndBoard :: proc(animals: ^[BOARD_SIZE]Animal, board, resqued: ^[BOARD_SIZE]^Animal,
                             frontRowPos: ^[NUM_COL]Vec2) {
    animals^, board^, resqued^ = {}, {}, {}
    setAnimals(animals)
    for i := 0; i < BOARD_SIZE; i += 1 { board[i] = &animals[i] }
    shuffleBoard(board, frontRowPos)
}

resetGamePlayState :: proc(board: ^[BOARD_SIZE]^Animal, gpState: ^GamePlayState) {
    gpState.numAnimalLeft = BOARD_SIZE
    gpState.bigJumpLeft = TOTAL_BIG_JUMP
    gpState.resquableIndex = [NUM_COL]int{}
    gpState.resquedChanged = true
    gpState.mostRecentResqueType = u8(0xFF)  
    gpState.numNextMoves = findResquables(board, gpState.mostRecentResqueType, &gpState.resquableIndex)
}

processKeyDown :: proc(anim: ^Animal) {
    anim.press = anim.height*0.05
    if anim.height < MIN_JUMP_HEIGHT { anim.height = MIN_JUMP_HEIGHT } 
}

addMsg :: proc(duration: int, gameMode: GameMode, l1, l2: string) {
    append(&scripts.msgs[gameMode], Message{l1, l2, duration, 1, false, 0, gameMode})
}

setMsg :: proc(gameMode: GameMode, msgNum: int) {
    if msgNum >= len(scripts.msgs[gameMode]) {
        when ODIN_DEBUG {
            fmt.printf("msgNum %d is greater than the msg len for game gameMode %d!\n", msgNum, gameMode)
        }
        msg = {}
    } else {
        msg = scripts.msgs[gameMode][msgNum]
    }
}

setTitleAnims :: proc(titleAnims: ^[3]^Animal, tstate: ^TitleState) {
    for i := 0; i < 3; i += 1 {
        tstate.destForOpening[i] = titleAnims[i].dest 
    }

    titleAnims[0].dest = Vec2{WINDOW_WIDTH*0.25*3, TITLE_LANDING_Y + TITLE_HEIGHT - ANIM_SIZE/3} 
    titleAnims[1].dest = Vec2{WINDOW_WIDTH*0.25*1.5, TITLE_LANDING_Y + TITLE_HEIGHT - ANIM_SIZE/3} 
    titleAnims[2].dest = Vec2{WINDOW_WIDTH*0.5, TITLE_LANDING_Y - TITLE_HEIGHT*0.25 + ANIM_SIZE*0.5} 
}


main :: proc() {
    title := TitleLogo{}
    setTitleLogo(&title)

    animals := [BOARD_SIZE]Animal{}
    board := [BOARD_SIZE]^Animal{}
    resqued := [BOARD_SIZE]^Animal{}
    frontRowPos := [NUM_COL]Vec2{}
    resetAnimalsAndBoard(&animals, &board, &resqued, &frontRowPos)

    tstate := TitleState{}
    firstRow := BOARD_SIZE - NUM_COL
    titleAnims :=[3]^Animal{board[firstRow], board[firstRow+2], board[firstRow+1]}
    setTitleAnims(&titleAnims, &tstate) 

    addMsg(INDEFINITE, GameMode.TITLE, "Press Space or Click anywhere to play", "")
    addMsg(INDEFINITE, GameMode.GAME_PLAY, "Pick one from the front row carefully", 
           "The following has to be same kind or color")
    addMsg(INDEFINITE, GameMode.GAME_PLAY, "Press and hold for BIG JUMP", "")
    addMsg(FPS*5, GameMode.GAME_PLAY, "Yay! Do BIG JUMP before getting stuck", "You have one more BIG JUMP")
    addMsg(FPS*5, GameMode.GAME_PLAY, "Only one more BIG JUMP left!", "Please, use it wisely...")
    addMsg(FPS*5, GameMode.GAME_PLAY, "Ugh.. No more BIG JUMP!!!", "")
    addMsg(INDEFINITE, GameMode.GAME_CLEAR, "All animals have crossed!",
           "Press G or click the last one to play again!")
    addMsg(INDEFINITE, GameMode.GAME_OVER, "Oops, it's a dead-end!",
           "Press G or click the last one to try again!")
    msg.gameMode = GameMode.TITLE

    gameMode = GameMode.TITLE 
    openingFrame := 0
    gameClearFrame := 0
    isQuitting := false
    willReplay := false
    isAllAnimUpdated := true

    gpState := GamePlayState{}
    gpState.numAnimalLeft = BOARD_SIZE
    gpState.resquableIndex = {}
    gpState.bigJumpLeft = TOTAL_BIG_JUMP
    gpState.firstMoveMade, gpState.bigJumpMade, gpState.lastMsgShown = false, false, false
    gpState.resquedChanged = true
    gpState.mostRecentResqueType = u8(0xFF)  // initially, all front row animals can be resqued.
    gpState.numNextMoves = findResquables(&board, gpState.mostRecentResqueType, &gpState.resquableIndex)
    when ODIN_DEBUG { fmt.printf("numPossibleMoves: %d, %v\n", gpState.numNextMoves, gpState.resquableIndex) }

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Animal Logic")
    rl.SetTargetFPS(FPS)
    rl.InitAudioDevice();
    loadAssets();
    
    // Game loop
    for !isQuitting && !rl.WindowShouldClose() {

        if msg.frames > 0 {
            if msg.duration != INDEFINITE && msg.frames > msg.duration && msg.alpha < 2 { 
                msg = {}
            } else { 
                msg.frames += 1
            }
        }

        switch gameMode {

            // title mode
            case GameMode.TITLE:
	
            if tstate.animToDrop < 2 && (tstate.titleFrame == 20 || tstate.titleFrame == 40) { 
                anim := titleAnims[tstate.animToDrop]
                jumpAnimal(anim, anim.dest, 20, 7)
                tstate.animToDrop += 1
                if tstate.animToDrop == 2 { tstate.titleDropFrame = tstate.titleFrame + FPS }
            }
            if tstate.animToDrop == 2 && tstate.titleFrame == tstate.titleDropFrame { 
                title.accel = {0, 1}
                tstate.firstCompressFrame = tstate.titleFrame + 0.4*FPS
            }
            if tstate.animToDrop == 2 && tstate.titleFrame == tstate.firstCompressFrame {
                rl.PlaySound(sounds.TitleLand)
                anim0, anim1 := titleAnims[0], titleAnims[1] 
                anim0.press = ANIM_SIZE*0.75
                anim0.veloc = {15, 0}
                anim0.accel = {-1.5, 0}
                anim0.dest = {75 + anim0.pos.x, anim0.pos.y}
                anim1.dest = {anim1.pos.x - 125, anim1.pos.y}
                jumpAnimal(anim1, anim1.dest, 14, 8)
                tstate.lastAnimDropFrame = tstate.titleFrame + 3*FPS
            }
            if tstate.animToDrop == 2 && tstate.titleFrame == tstate.lastAnimDropFrame {
                anim := titleAnims[tstate.animToDrop]
                jumpAnimal(anim, anim.dest, 20, 6)
                tstate.titlePressFrame = tstate.titleFrame + 0.3*FPS	
            }
            if tstate.animToDrop == 2 && tstate.titleFrame == tstate.titlePressFrame {
                rl.PlaySound(sounds.TitleJump)
                title.press = 12.5
                tstate.lastAnimJumpFrame = tstate.titleFrame + 0.2*FPS
            }
            if tstate.animToDrop == 2 && tstate.titleFrame == tstate.lastAnimJumpFrame {
                anim := titleAnims[2]
                jumpAnimal(anim, titleAnims[1].pos, 24, 11)
                tstate.animToDrop += 1
                tstate.secondCompressFrame = tstate.titleFrame + 24
            }
            if tstate.animToDrop == 3 && tstate.titleFrame == tstate.secondCompressFrame {
                anim := titleAnims[1]
                anim0 := titleAnims[0]
                anim.press = ANIM_SIZE*0.75
                anim.veloc = {30, 0}
                anim.accel = {-1, 0}
                anim.dest = {anim0.x, anim.y}
                tstate.fallOutFrame = tstate.titleFrame + 24
            }
            if tstate.animToDrop == 3 && tstate.titleFrame == tstate.fallOutFrame {
                anim := titleAnims[0]
                jumpAnimal(anim, Vec2{RESQUE_SPOT_X, RESQUE_SPOT_Y}, 26, 8)
                tstate.sceneEnd = true
            }
			
            updateTitle(&title)
		    
            if tstate.sceneEnd && isAllAnimUpdated {
                if !tstate.titleMessageShown {
                    setMsg(gameMode, 0)
                    tstate.titleMessageShown = true
                }
                if rl.IsKeyReleased(KEY_SPACE) || rl.IsMouseButtonReleased(MOUSE_L) {
                    when ODIN_DEBUG { fmt.println("Space released!") }
                    rl.PlaySound(sounds.Start)
                    for _, i in titleAnims { titleAnims[i].dest = tstate.destForOpening[i] }
                    gameMode = GameMode.OPENING
                }
            }

            tstate.titleFrame += 1

            // opening mode
            case GameMode.OPENING:

            frameDiv := openingFrame / 10
            frameMod := openingFrame % 10
            if frameDiv < BOARD_SIZE {
                anim := &animals[frameDiv]
                if frameMod == 0 {
                    if anim == titleAnims[0] {
                        jumpAnimal(anim, anim.dest, 24, 16)
                    } else {
                        jumpAnimal(anim, anim.dest, 20, 4)
                    }
                }
                openingFrame += 1
            } else if isAllAnimUpdated {
                openingFrame = 0
                gameMode = GameMode.GAME_PLAY
            }

            // gameplay mode
            case GameMode.GAME_PLAY:

            if msg.gameMode != gameMode { 
                msg.gameMode = gameMode
                msg.frames = 0
            }

            if isAllAnimUpdated {
                if !gpState.firstMoveMade && msg.frames == 0 { setMsg(gameMode, 0) }

                // After new move is made, check the message states and get the new possible next moves
                if gpState.numAnimalLeft < BOARD_SIZE && gpState.resquedChanged { 
                    assert(resqued[BOARD_SIZE - gpState.numAnimalLeft - 1] != nil)
					
                    if !gpState.firstMoveMade {
                        gpState.firstMoveMade = true
                        setMsg(gameMode, 1)
                    }
                    if !gpState.bigJumpMade && gpState.numAnimalLeft < BOARD_SIZE - 1 { 
                        setMsg(gameMode, 1)
                    }
                    if gpState.bigJumpMade && !gpState.lastMsgShown{
                        gpState.lastMsgShown = true
                        setMsg(gameMode, 2)
                    }

                    gpState.mostRecentResqueType = resqued[BOARD_SIZE - gpState.numAnimalLeft - 1].type
                    for _, i in gpState.resquableIndex { gpState.resquableIndex[i] = 0 }
                    gpState.numNextMoves = findResquables(&board,gpState.mostRecentResqueType, 
                                                          &gpState.resquableIndex)
                    gpState.resquedChanged = false
                    if gpState.numAnimalLeft == 0 {
                        rl.PlaySound(sounds.Success)
                        gameMode = GameMode.GAME_CLEAR
                    } else if gpState.numNextMoves == 0 {
                        rl.PlaySound(sounds.Fail)
                        gameMode = GameMode.GAME_OVER
                    }

                    when ODIN_DEBUG {
                        fmt.printf("numNextMoves: %d, %v\n", gpState.numNextMoves, gpState.resquableIndex)
                        fmt.printf("numAnimalLeft: %d\n", gpState.numAnimalLeft)
                        printbd(&board)
                    }
                }

                // KeyDown event 
                if rl.IsKeyDown(KEY_A) || (rl.IsMouseButtonDown(MOUSE_L) && 
                   isAnimRectClicked(board[FRONT_ROW_BASEINDEX])) {
                    when ODIN_DEBUG { fmt.println("A pressed!") }
                    if gpState.resquableIndex[0] != 0 { processKeyDown(board[FRONT_ROW_BASEINDEX]) }
                } else if rl.IsKeyDown(KEY_S) || (rl.IsMouseButtonDown(MOUSE_L) && 
                          isAnimRectClicked(board[FRONT_ROW_BASEINDEX+1])) {
                    when ODIN_DEBUG { fmt.println("S pressed!") }
                    if gpState.resquableIndex[1] != 0 { processKeyDown(board[FRONT_ROW_BASEINDEX+1]) }
                } else if rl.IsKeyDown(KEY_D) || (rl.IsMouseButtonDown(MOUSE_L) && 
                          isAnimRectClicked(board[FRONT_ROW_BASEINDEX+2])) {
                    when ODIN_DEBUG { fmt.println("D pressed!") }
                    if gpState.resquableIndex[2] != 0 { processKeyDown(board[FRONT_ROW_BASEINDEX+2]) }
                } else if rl.IsKeyDown(KEY_F) || (rl.IsMouseButtonDown(MOUSE_L) && 
                          isAnimRectClicked(board[FRONT_ROW_BASEINDEX+3])) {
                    when ODIN_DEBUG { fmt.println("F pressed!") }
                    if gpState.resquableIndex[3] != 0 { processKeyDown(board[FRONT_ROW_BASEINDEX+3]) }

                // KeyRelease event
                } else if rl.IsKeyReleased(KEY_A) || (rl.IsMouseButtonReleased(MOUSE_L) && 
                          isAnimRectClicked(board[FRONT_ROW_BASEINDEX])) {
                    when ODIN_DEBUG { fmt.println("A released!") }
                    if gpState.resquableIndex[0] != 0 {
                        resqueAt(&board, &resqued, FRONT_ROW_BASEINDEX, gpState.numAnimalLeft)
                        gpState.numAnimalLeft -= 1
                        gpState.resquedChanged = true
                        msg = {}
                    }
                } else if rl.IsKeyReleased(KEY_S) || (rl.IsMouseButtonReleased(MOUSE_L) && 
                          isAnimRectClicked(board[FRONT_ROW_BASEINDEX + 1])) {
                    when ODIN_DEBUG { fmt.println("S released!") }
                    if gpState.resquableIndex[1] != 0 {
                        resqueAt(&board, &resqued, FRONT_ROW_BASEINDEX + 1, gpState.numAnimalLeft)
                        gpState.numAnimalLeft -= 1
                        gpState.resquedChanged = true
                        msg = {}
                    }
                } else if rl.IsKeyReleased(KEY_D) || (rl.IsMouseButtonReleased(MOUSE_L) && 
                          isAnimRectClicked(board[FRONT_ROW_BASEINDEX + 2])) {
					when ODIN_DEBUG { fmt.println("D released!") }
					if gpState.resquableIndex[2] != 0 {
                        resqueAt(&board, &resqued, FRONT_ROW_BASEINDEX + 2, gpState.numAnimalLeft)
                        gpState.numAnimalLeft -= 1
                        gpState.resquedChanged = true
                        msg = {}
                    }
                } else if rl.IsKeyReleased(KEY_F) || (rl.IsMouseButtonReleased(MOUSE_L) && 
                          isAnimRectClicked(board[FRONT_ROW_BASEINDEX + 3])) {
                    when ODIN_DEBUG { fmt.println("F released!") }
                    if gpState.resquableIndex[3] != 0 {
                        resqueAt(&board, &resqued, FRONT_ROW_BASEINDEX + 3, gpState.numAnimalLeft)
                        gpState.numAnimalLeft -= 1
                        gpState.resquedChanged = true
                        msg = {}
                    }
                }
            }

            // gameclear mode
            case GameMode.GAME_CLEAR:

            if msg.gameMode != gameMode { setMsg(gameMode, 0) }
			
            if isAllAnimUpdated {
                if !willReplay {
                    if gameClearFrame < BOARD_SIZE {
                        anim := resqued[gameClearFrame]
                        jumpAnimal(anim, anim.pos, 18, 10)
                    }
                    gameClearFrame += 1
                    if gameClearFrame >= BOARD_SIZE { gameClearFrame = 0 }
                } else {
                    resetAnimalsAndBoard(&animals, &board, &resqued, &frontRowPos)
                    time.sleep(time.Millisecond * 500)
                    gameMode = GameMode.OPENING
                    msg = {}
                    willReplay = false
                    resetGamePlayState(&board, &gpState)
                }
            }
				
            if !willReplay && rl.IsKeyReleased(KEY_G) || (rl.IsMouseButtonReleased(MOUSE_L) && 
                isAnimRectClicked(resqued[BOARD_SIZE - 1 - gpState.numAnimalLeft])) {
                when ODIN_DEBUG { fmt.println("G released on GAME_Clear! Play Again!") }
                rl.PlaySound(sounds.Start)
                for anim in resqued { jumpAnimal(anim, Vec2{anim.x, -ANIM_SIZE} , 24, 20) }
                willReplay = true
            }

            // gamover mode
            case GameMode.GAME_OVER:
			
            if msg.gameMode != gameMode { setMsg(gameMode, 0) }

            if isAllAnimUpdated {
                if !willReplay {
                    for i := 0; i < BOARD_SIZE; i += 1 {
                        if board[i] != nil && board[i].height >= MIN_ANIM_HEIGHT*5 { 
                            board[i].height -= 1 
                        }
                    }
                } else {
                    resetAnimalsAndBoard(&animals, &board, &resqued, &frontRowPos)
                    time.sleep(time.Millisecond * 500)
                    gameMode = GameMode.OPENING
                    willReplay = false
                    msg = {}
                    resetGamePlayState(&board, &gpState)
                }
            }

            if !willReplay && rl.IsKeyReleased(KEY_G) || (rl.IsMouseButtonReleased(MOUSE_L) && 
               isAnimRectClicked(resqued[BOARD_SIZE - 1 - gpState.numAnimalLeft])) {
                when ODIN_DEBUG { fmt.println("G released on GAME_OVER! Play Again!") }
                rl.PlaySound(sounds.Start)
                for anim in board {
                    if anim != nil {jumpAnimal(anim, Vec2{anim.x, -ANIM_SIZE}, 24, 20)}
                }
                for anim in resqued {
                    if anim != nil {jumpAnimal(anim, Vec2{anim.x, -ANIM_SIZE}, 24, 20)}
                }
                willReplay = true
            }

        } //end switch(GameMode)

        isAllAnimUpdated = updateAnimState(&animals, &board, &resqued, &frontRowPos, &gpState)

        // render
        rl.BeginDrawing()
        {
            rl.DrawTextureEx(textures.GroundTexture, Vec2{0, 0}, 0, 1, rl.RAYWHITE)
			
            if gameMode == GameMode.TITLE {
                drawTitle(&title)
                for anim in titleAnims { drawAnimal(anim) }
            } else {
                i: u8
                for i = 0; i < BOARD_SIZE; i += 1 {
                    if board[i] != nil { drawAnimal(board[i]) }
                }
                for i = 0; i < BOARD_SIZE - gpState.numAnimalLeft; i += 1 {
                    if resqued[i] != nil { drawAnimal(resqued[i]) }
                }
            }

            // draw message
            if gameMode == msg.gameMode {
                fontColor := rl.GOLD
                if msg.duration == INDEFINITE {
                    if msg.frames < FPS*3 {
                        alpha := (msg.frames*2 % 255*2) 
                        if alpha > 255 { alpha = 255*2 - alpha }
                        msg.alpha = u8(alpha)
                    } else if msg.alpha <= 253 {
                        msg.alpha += 2
                    }
                } else {
                    if msg.frames <= msg.duration {
                        alpha := (msg.frames*2 % 255*2) 
                        if alpha > 255 { alpha = 255*2 - alpha }
                        msg.alpha = u8(alpha)
                    } else {
                        if msg.alpha <= 1 {
                            msg.alpha = 0
                        } else {
                            msg.alpha -= 2
                        }
                    }
                }

                fontColor.a = u8(msg.alpha)
                l1PosX := i32((1 - (f32(len(msg.l1))/MAX_MSG_LEN))*WINDOW_WIDTH/2)
                if msg.l2 == "" {
                    rl.DrawText(cstring(raw_data(msg.l1)), MARGIN_WIDTH + l1PosX, MSG_POS_Y,
                                DEFAULT_FONT_SIZE, fontColor)
                } else {
                    l2PosX := i32((1 - (f32(len(msg.l2))/MAX_MSG_LEN))*WINDOW_WIDTH/2)
                    rl.DrawText(cstring(raw_data(msg.l1)), MARGIN_WIDTH + l1PosX, 
                                MSG_POS_Y - DEFAULT_FONT_SIZE*0.5, DEFAULT_FONT_SIZE, fontColor)
                    rl.DrawText(cstring(raw_data(msg.l2)), MARGIN_WIDTH + l2PosX, 
                                MSG_POS_Y + DEFAULT_FONT_SIZE*0.5, DEFAULT_FONT_SIZE, fontColor)
                }
            }
        }
        rl.EndDrawing()
    }

    unloadSounds()
}

