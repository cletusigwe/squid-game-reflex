import pkg/[raylib]
import std/[os, math, random, tables, strformat]
randomize()
const
    Width = 640 * 2
    Height = 480
    Title = "Squid Game Reflex"
    SpriteSheetColumns = 32
    SingleSpriteColumn = 8
    FpsDesired = 60
    PlayerWidth = 50
    MotionTime = 0.2

let resourcesFolder = "../resources"

type
    PlayerColor = enum
        RedGuy
        GreenGuy

    PlayerStates = enum
        Idle
        Running

    Player = object
        currentTextureIndex: range[0 .. SingleSpriteColumn - 1] = 0
        framesNoUpdate: uint = 0
        color: PlayerColor = GreenGuy
        pos: Vector2 = Vector2(x: 0, y: 0)
        state: PlayerStates = Running
        speed: float = 1.0
        isDead: bool

    Gun = object
        crosshairCenter: Vector2
        crossHairArea: int
        texture: Texture2D
        scale: float
        shootSound: Sound

    SquidGameMode = enum
        Playing
        Pause

    GameState = object
        gun: Gun
        players: seq[Player]
        playersTexture: Texture2D
        mode: SquidGameMode = Playing
        stopSound: Sound
        scanSound: Sound
        playingMusic: Music
        spriteCache:
            Table[tuple[color: PlayerColor, state: PlayerStates, index: int], Rectangle]
        faultyPlayerIndex: int = -1
        faultyRunStartTime: float
        finishLineX: float
        score: int
        maxScore: int

proc initGun(pos: Vector2, scale: float): Gun =
    result.crossHairArea = 200
    result.texture = loadTexture(resourcesFolder / "images" / "dikec.png")
    result.crosshairCenter = pos
    result.shootSound = loadSound(resourcesFolder / "sounds" / "shoot.mp3")
    result.scale = scale

proc initSpriteCache(gameState: GameState): typeof(GameState.spriteCache) =
    for color in PlayerColor:
        for state in PlayerStates:
            for index in 0 ..< SingleSpriteColumn:
                let
                    spriteOffset = block:
                        case color
                        of GreenGuy:
                            case state
                            of Idle: 0
                            else: 1
                        of RedGuy:
                            case state
                            of Idle: 2
                            else: 3

                    offset = (spriteOffset * SingleSpriteColumn) + index
                    singleSpriteWidth =
                        gameState.playersTexture.width / SpriteSheetColumns
                result[(color, state, index)] = Rectangle(
                    x: (singleSpriteWidth * offset.float),
                    y: 0,
                    width: singleSpriteWidth,
                    height: gameState.playersTexture.height.float,
                )

proc getRandomPlayers(n: int, enclosure: Rectangle): seq[Player] =
    # Gets n random players located within the enclosure on the screen.
    # Players line up top to bottom and move to the next row when the current row is filled up.
    let
        margin = -15
        cols = int(enclosure.width / (PlayerWidth + margin).float)
    var row, col: int

    for _ in 0 ..< n:
        let pos = Vector2(
            x: float(col * (PlayerWidth + margin)),
            y: float(row * (PlayerWidth + margin)),
        )

        if (pos.y.int + PlayerWidth) <= enclosure.height.int:
            var player =
                Player(color: rand(PlayerColor), speed: rand(0.5 .. 1.5), pos: pos)
            result.add(player)

        inc col
        if col >= cols:
            col = 0
            inc row

        if row * (PlayerWidth + margin) > enclosure.height.int:
            break

    return result

proc updatePlayer(player: var Player) {.inline.} =
    let framesBeforeUpdate = uint(FpsDesired / (10 * player.speed))
    if player.framesNoUpdate < framesBeforeUpdate:
        inc player.framesNoUpdate
    else:
        player.currentTextureIndex = (player.currentTextureIndex + 1) mod 8
        player.framesNoUpdate = 0

    if player.state == Running and player.pos.x < Width:
        player.pos.x += player.speed

proc drawSpriteN(
        spriteSheet: Texture2D, srcRect: Rectangle, newPos: Vector2
) {.inline.} =
    let
        singleSpriteWidth = spriteSheet.width / (SpriteSheetColumns)
        destRect = Rectangle(
            x: newPos.x,
            y: newPos.y,
            width: PlayerWidth,
            height: PlayerWidth.float * (spriteSheet.height.float / singleSpriteWidth),
        )
    # drawRectangleLines(destRect, 3.0, Red)
    drawTexture(spriteSheet, srcRect, destRect, Vector2(x: 0, y: 0), 0, White)

proc displayPlayer(gameState: var GameState, playerIndex: int) {.inline.} =
    # SpriteOffSets = Green_idle | Green_run | Red_idle | Red_run
    if gameState.players[playerIndex].pos.x > gameState.finishLineX:
        gameState.players[playerIndex].isDead = true

    let
        player = gameState.players[playerIndex]
        playerId = (
            color: player.color, state: player.state, index: player.currentTextureIndex
        )

    drawSpriteN(gameState.playersTexture, gameState.spriteCache[playerId], player.pos)

proc drawCrossHair(gun: Gun, color: Color) {.inline.} =
    let
        crossHairSideLen = sqrt(gun.crossHairArea.float)
        crossHairLen = 3 * crossHairSideLen / 4
        thickness = crossHairSideLen / 5
    # drawRectangle(
    #     Rectangle(
    #         x: gun.crosshairCenter.x - crossHairSideLen / 2,
    #         y: gun.crosshairCenter.y - crossHairSideLen / 2,
    #         width: crossHairSideLen,
    #         height: crossHairSideLen,
    #     ),
    #     Red,
    # )

    # top
    drawLine(
        Vector2(
            x: gun.crosshairCenter.x, y: gun.crosshairCenter.y - (crossHairSideLen / 2)
        ),
        Vector2(
            x: gun.crosshairCenter.x,
            y: gun.crosshairCenter.y - crossHairSideLen / 2 - crossHairLen,
        ),
        thickness,
        color,
    )

    # bottom
    drawLine(
        Vector2(
            x: gun.crosshairCenter.x, y: gun.crosshairCenter.y + (crossHairSideLen / 2)
        ),
        Vector2(
            x: gun.crosshairCenter.x,
            y: gun.crosshairCenter.y + crossHairSideLen / 2 + crossHairLen,
        ),
        thickness,
        color,
    )

    # left
    drawLine(
        Vector2(x: gun.crosshairCenter.x - (crossHairLen / 2), y: gun.crosshairCenter.y),
        Vector2(
            x: gun.crosshairCenter.x - (crossHairLen / 2) - crossHairLen,
            y: gun.crosshairCenter.y,
        ),
        thickness,
        color,
    )

    #right
    drawLine(
        Vector2(x: gun.crosshairCenter.x + (crossHairLen / 2), y: gun.crosshairCenter.y),
        Vector2(
            x: gun.crosshairCenter.x + (crossHairLen / 2) + crossHairLen,
            y: gun.crosshairCenter.y,
        ),
        thickness,
        color,
    )

proc popAllDeadPlayers(gameState: var GameState) =
    for playerIndex in countdown(gameState.players.len - 1, 0):
        if gameState.players[playerIndex].isDead:
            gameState.players.delete(playerIndex)
            #swap and pop wont work because I need to keep order of sequence
            # gameState.players[playerIndex] = gameState.players[^1]
            # discard gameState.players.pop()

proc drawGun(gun: Gun) =
    #draws the player's gun, 
    #but I think better when the coordinate is bottom center of gun texture and not top left
    #so pos(x, y) are actually center of the texture
    let
        gunTextureRealWidth = gun.texture.width.float * gun.scale
        topLeft = Vector2(
            x: gun.crosshairCenter.x - (gunTextureRealWidth / 2),
            y: gun.crosshairCenter.y + sqrt(gun.crossHairArea.float),
        )

    # drawCircle(Vector2(x: pos.x, y: topLeft.y - 10), 10.0, Red)
    gun.drawCrossHair(Red)
    gun.texture.drawTexture(topLeft, 0.0, gun.scale, White)

proc shoot(gun: Gun) {.inline.} =
    # gun.scale -= 0.2
    playSound(gun.shootSound)
    # gun.scale += 0.2

proc handleUserInput(gameState: var GameState) =
    #Handle the user input, user pressing <CTRL> takes control of the mouse
    #mouse is used to point, and tapping the touchpad or leftclick shoots
    #target is static but the point to shoot changes and you only shoot when it turns green
    #getMousePositon,X, Y

    if LeftControl.isKeyDown() or RightControl.isKeyDown():
        #Take control of the mouse
        if isCursorOnScreen():
            gameState.gun.crossHairCenter.x = getMouseX().float
            # if gunPos.y >= Height/2:
            gameState.gun.crosshairCenter.y =
                getMouseY().float -
                (gameState.gun.texture.height.float * gameState.gun.scale)

    if getGestureDetected() == Tap and gameState.mode == Pause:
        gameState.gun.shoot()
        let crossHairRadius = sqrt(gameState.gun.crossHairArea.float) / 2
        let crossHairTargetRect = Rectangle(
            x: gameState.gun.crossHairCenter.x - (crossHairRadius / 4),
            y: gameState.gun.crossHairCenter.y - (crossHairRadius / 4),
            width: crossHairRadius,
            height: crossHairRadius,
        )

        var deadGuysIndex: seq[int]

        for index in 0 ..< gameState.players.len:
            if checkCollisionRecs(
                crossHairTargetRect,
                Rectangle(
                    x: gameState.players[index].pos.x,
                    y: gameState.players[index].pos.y,
                    width: PlayerWidth,
                    height: gameState.playersTexture.height.float,
                ),
            ):
                deadGuysIndex.add(index)

        # echo deadGuysIndex.len
        if deadGuysIndex.len > 0:
            gameState.players[deadGuysIndex[^1]].isDead = true
            # gameState.maxScore += 1
            # echo gameState.faultyPlayerIndex, " ", deadGuysIndex[^1]
            if deadGuysIndex[^1] == gameState.faultyPlayerIndex:
                gameState.score += 1
            gameState.faultyPlayerIndex = -1
            gameState.mode = Playing
            for index in 0 ..< gameState.players.len:
                gameState.players[index].state = Running
            gameState.playingMusic.resumeMusicStream()

    if gameState.mode == Playing:
        let randomValue = rand(100)
        echo randomValue
        if randomValue mod 3 == 0 and getTime() - gameState.faultyRunStartTime >= 4.0:
            gameState.maxscore += 1
            gameState.mode = Pause
            gameState.playingMusic.pauseMusicStream()
            for index, player in gameState.players:
                gameState.players[index].state = Idle
            gameState.stopSound.playSound()
            gameState.scanSound.playSound()

            gameState.faultyPlayerIndex = rand(gameState.players.len - 1)
            gameState.players[gameState.faultyPlayerIndex].state = Running
            gameState.faultyRunStartTime = getTime()

    # if isKeyPressed(Space):
    #     case gameState.mode
    #     of Playing:
    #         gameState.maxscore += 1
    #         gameState.mode = Pause
    #         gameState.playingMusic.pauseMusicStream()
    #         for index, player in gameState.players:
    #             gameState.players[index].state = Idle
    #         gameState.stopSound.playSound()
    #         gameState.scanSound.playSound()

    #         gameState.faultyPlayerIndex = rand(gameState.players.len - 1)
    #         gameState.players[gameState.faultyPlayerIndex].state = Running
    #         gameState.faultyRunStartTime = getTime()
    #     else:
    #         discard
    #         # gameState.mode = Playing
    #         # for index in 0 ..< gameState.players.len:
    #         #     gameState.players[index].state = Running
    #         # gameState.playingMusic.resumeMusicStream()
    #         # gameState.faultyPlayerIndex = -1

proc updateRunningPlayer(gameState: var GameState) =
    if gameState.mode == Pause and gameState.faultyPlayerIndex != -1:
        let runDuration = getTime() - gameState.faultyRunStartTime
        if runDuration >= MotionTime:
            gameState.players[gameState.faultyPlayerIndex].state = Idle

proc drawFinishLine(x: float) {.inline.} =
    drawLine(Vector2(x: x, y: 0), Vector2(x: x, y: Height / 2 + 20), 5.0, Red)

proc initGameState(): GameState =
    let partOfScreen = Rectangle(x: 0, y: 0, width: Width / 3, height: Height / 2)
    result.gun = initGun(Vector2(x: Width / 2, y: Height / 2), 0.5)
    result.players = getRandomPlayers(60, partOfScreen)
    result.playersTexture =
        loadTexture(resourcesFolder / "images" / "squid_game_sprites.png")
    result.playingMusic =
        loadMusicStream(resourcesFolder / "sounds" / "redlight_greenlight.mp3")
    result.stopSound = loadSound(resourcesFolder / "sounds" / "stop.mp3")
    result.scanSound = loadSound(resourcesFolder / "sounds" / "scanning.mp3")
    result.spriteCache = initSpriteCache(result)
    result.finishLineX = 3 * Width / 4
    result.mode = Playing

proc drawScore(gameState: GameState) =
    let
        score = fmt"{gameState.score} / {gameState.maxScore}"
        fontSize: int32 = 20
        padding: int32 = 10
        textWidth = measureText(score.cstring, fontSize)
        xPos: int32 = Width - textWidth - padding
        yPos: int32 = padding

    drawText(score.cstring, xPos, yPos, fontSize, Black)

proc runGame(gameState: var GameState) =
    case gameState.mode
    of Playing:
        gameState.playingMusic.updateMusicStream()
    of Pause:
        updateRunningPlayer(gameState)

    drawFinishLine(gameState.finishLineX)

    for index in 0 ..< gameState.players.len:
        displayPlayer(gameState, index)
        updatePlayer(gameState.players[index])

    popAllDeadPlayers(gameState)
    drawGun(gameState.gun)
    handleUserInput(gameState)
    drawScore(gameState)

proc main() =
    initWindow(Width, Height, Title)
    setTargetFPS(FpsDesired)
    initAudioDevice()

    var gameState = initGameState()
    gameState.playingMusic.playMusicStream()

    while (not (windowShouldClose())):
        drawing:
            clearBackground(LightGray)
            runGame(gameState)

when isMainModule:
    main()
