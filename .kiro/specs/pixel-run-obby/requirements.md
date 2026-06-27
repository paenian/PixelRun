# Requirements Document

## Introduction

Pixel Run Obby is a near-endless running game for Roblox that places players on conveyor-belt-style obstacle courses (obbies). Players run through themed 10-level packs, earning experience to purchase power-ups while avoiding increasingly difficult obstacles. The game is built using Rojo with external development workflow for professional version control and organized code structure. Level packs are designed for weekly additions, keeping the game fresh with new themes, challenges, and art.

## Glossary

- **Game_System**: The overall Pixel Run Obby game application running on Roblox
- **Level_Generator**: The server-side module responsible for constructing and managing level geometry, obstacles, and conveyor mechanics
- **Player**: A Roblox user participating in the game
- **Level_Pack**: A themed collection of 10 sequential levels with shared visual identity and obstacle types
- **Level**: A single 1000-block-long obstacle course that is 10 blocks wide and repeats upon completion
- **Obstacle**: A physical object placed within a level that the Player must avoid or navigate around
- **Morass**: A visually themed advancing wall that enforces minimum speed (e.g., rolling Tetris blocks for the Tetris pack)
- **Experience_Points (XP)**: Currency earned by progressing through levels, used to purchase Power_Ups
- **Power_Up**: A persistent player upgrade purchased with XP that provides gameplay advantages
- **Lobby**: The central hub area where Players spawn and access Level_Packs
- **Leaderboard_System**: The real-time ranking system displaying player scores and progression
- **Data_Store**: The server-side persistence layer managing player stats, achievements, and purchases
- **Effects_Manager**: The client-side module responsible for particle explosions, floating text, and visual feedback
- **Sound_Manager**: The client-side module responsible for dynamic music and sound effects
- **Achievement_System**: The module tracking and awarding one achievement per Level_Pack
- **Rojo_Project**: The external development environment using Rojo for live sync with Roblox Studio
- **SharedModule**: A module accessible by both server and client code
- **Conveyor**: The visual and mechanical representation of the ground moving beneath the Player, enforcing forward momentum

## Requirements

### Requirement 1: Project Structure and Development Workflow

**User Story:** As a developer, I want the project organized using Rojo with proper service-based structure, so that I can develop externally with version control and live-sync to Roblox Studio.

#### Acceptance Criteria

1. THE Rojo_Project SHALL organize server code under ServerScriptService, client code under StarterPlayerScripts, and shared code under ReplicatedStorage
2. THE Rojo_Project SHALL include a default.project.json file that Rojo can parse to establish a live-sync session mapping the file system structure to Roblox services
3. THE Rojo_Project SHALL include SharedModules under ReplicatedStorage for LevelUtils, PowerUpManager, EffectsManager, SoundManager, GameModeManager, ComboManager, RewardsManager, and MascotManager
4. THE Rojo_Project SHALL separate Level_Pack definitions into individual module files within a dedicated Level_Packs directory under ReplicatedStorage so that new packs can be added without modifying existing game module files
5. THE Rojo_Project SHALL include a unit test framework capable of executing tests for SharedModules (LevelUtils, PowerUpManager, GameModeManager, ComboManager, RewardsManager) without requiring a Roblox Studio runtime environment
6. WHEN a new Level_Pack module file is placed in the Level_Packs directory, THE Rojo_Project SHALL require no changes to default.project.json for the new pack to be included in the build

### Requirement 2: Lobby and Navigation

**User Story:** As a player, I want to spawn in a lobby with clear access to all level packs, so that I can choose which challenge to attempt.

#### Acceptance Criteria

1. WHEN a Player joins the game, THE Game_System SHALL spawn the Player in the Lobby
2. THE Lobby SHALL display Level_Pack entry portals radiating outward from the center, with each portal showing the pack theme, difficulty rating (on a scale of 1 to 10), and completion status (number of levels completed out of 10)
3. WHEN a Player enters an unlocked Level_Pack portal, THE Game_System SHALL teleport the Player to level 1 of the selected Level_Pack
4. THE Lobby SHALL visually distinguish locked Level_Packs from unlocked Level_Packs using reduced opacity and a lock icon overlay on locked portals
5. WHEN a Player interacts with a locked Level_Pack portal, THE Game_System SHALL display a message indicating the unlock requirement (e.g., "Complete Pack 1 to unlock")
6. THE Game_System SHALL unlock Level_Packs sequentially, requiring completion of all 10 levels in the previous pack before the next pack becomes accessible

### Requirement 3: Level Generation and Structure

**User Story:** As a player, I want to run through themed obstacle courses that are 10 blocks wide and 1000 blocks long, so that I have consistent and challenging gameplay.

#### Acceptance Criteria

1. THE Level_Generator SHALL create each Level as a course 10 blocks wide and 1000 blocks long
2. THE Level_Generator SHALL place Obstacles according to the active Level_Pack theme and difficulty configuration, with obstacle density increasing from a minimum of 1 obstacle per 50 blocks in level 1 to a maximum of 1 obstacle per 10 blocks in level 10
3. WHEN a Player reaches the 1000-block mark, THE Game_System SHALL register a level completion, increment the Player's completion count for that level, and present the Player with a choice to continue the same level or advance to the next level
4. THE Level_Generator SHALL increase obstacle difficulty progressively across the 10 levels within each Level_Pack: levels 1-3 introduce jump-over obstacles only, levels 4-6 add holes and gaps, levels 7-9 add void sections, and level 10 adds touch-and-die objects
5. WHEN a Player chooses to continue running a completed level, THE Level_Generator SHALL repeat the identical level layout from the beginning while continuing to award Experience_Points
6. WHEN a Player completes level 10 of a Level_Pack, THE Game_System SHALL register pack completion, trigger the Achievement_System, and offer the Player return to Lobby or replay of any level in the pack
7. THE Level_Generator SHALL produce a deterministic layout for each level number within a Level_Pack, ensuring the same obstacles appear at the same positions on every run

### Requirement 4: Conveyor and Minimum Speed Enforcement

**User Story:** As a player, I want a visual indicator of minimum speed, so that I understand the urgency to keep moving forward.

#### Acceptance Criteria

1. WHILE a Player is in a Level, THE Game_System SHALL enforce a minimum forward speed using the Conveyor mechanic, moving the ground surface beneath the Player at the level's configured minimum speed measured in blocks per second
2. THE Morass SHALL spawn at a position 50 blocks behind the Player's starting position and advance toward the Player at the minimum speed rate, providing a visual representation of the speed floor
3. THE Morass SHALL use theme-appropriate visuals matching the active Level_Pack (e.g., rolling Tetris blocks for the Tetris pack)
4. WHEN the Morass reaches the Player position, THE Game_System SHALL eliminate the Player, reset the Morass to its spawn position, and respawn the Player at the beginning of the current level
5. WHILE a Player moves faster than the minimum speed, THE Morass SHALL maintain a constant advance rate equal to the minimum speed, causing the gap between the Player and the Morass to increase
6. WHEN a Player is eliminated by the Morass, THE Game_System SHALL retain all Experience_Points earned during that run up to the point of elimination

### Requirement 5: Tetris Level Pack (First Pack)

**User Story:** As a player, I want the first level pack to be Tetris-themed with block-based obstacles, so that I have an engaging introductory experience.

#### Acceptance Criteria

1. THE Level_Generator SHALL create the Tetris Level_Pack as the first available pack containing 10 levels, accessible without completing any prerequisites
2. THE Level_Generator SHALL construct Obstacles from Tetris piece shapes (I, O, T, S, Z, L, J) placed on the ground in at least 4 distinct orientations per piece type (0°, 90°, 180°, 270°)
3. THE Level_Generator SHALL increase difficulty across the 10 Tetris levels: levels 1-3 use obstacles no taller than 3 blocks, levels 4-6 introduce obstacles up to 5 blocks tall with platform gaps up to 3 blocks wide, levels 7-9 introduce void sections up to 5 blocks long, and level 10 introduces glowing touch-and-die blocks
4. THE Morass for the Tetris Level_Pack SHALL appear as rolling Tetris blocks advancing from behind
5. THE Level_Generator SHALL use block-based visual aesthetics consistent with Tetris piece colors (cyan for I, yellow for O, purple for T, green for S, red for Z, orange for L, blue for J) throughout the pack
6. THE Tetris Level_Pack SHALL be completable without any purchased Power_Ups, ensuring all obstacles in levels 1 through 10 are passable using the default jump height and movement speed

### Requirement 6: Experience and Scoring

**User Story:** As a player, I want to earn experience based on how far I progress, so that I feel rewarded for my effort and can unlock power-ups.

#### Acceptance Criteria

1. WHILE a Player is running a Level, THE Game_System SHALL accumulate Experience_Points at a rate of 1 XP per block traveled
2. WHEN a Player reaches the 1000-block mark completing a level, THE Game_System SHALL award a bonus of 500 Experience_Points
3. WHILE a Player is on a higher-numbered Level_Pack, THE Game_System SHALL apply an XP multiplier equal to the pack number (pack 1 = 1x, pack 2 = 2x, pack 3 = 3x) to all Experience_Points earned per block
4. WHILE a Player is in a Level, THE Game_System SHALL display the current XP total, XP earned this run, and XP needed for the next Power_Up on the player HUD, updating the display once per second
5. WHEN a Player is eliminated by the Morass or an Obstacle, THE Game_System SHALL retain all Experience_Points accumulated during that run

### Requirement 7: Power-Up System

**User Story:** As a player, I want to purchase power-ups with my earned experience, so that I can overcome harder obstacles in later level packs.

#### Acceptance Criteria

1. THE Game_System SHALL provide purchasable Power_Ups including: Higher Jump (3 tiers with multipliers of 1.25x, 1.5x, and 2.0x base jump height), Double Jump, and Faster Speed (3 tiers with multipliers of 1.25x, 1.5x, and 2.0x base movement speed)
2. WHEN a Player purchases a Power_Up, THE Game_System SHALL deduct the defined XP cost for that Power_Up tier and permanently apply the upgrade to the Player profile
3. IF a Player attempts to purchase a Power_Up with insufficient Experience_Points, THEN THE Game_System SHALL reject the purchase, display a message indicating the XP shortfall, and make no changes to the Player profile
4. THE Game_System SHALL require Power_Up tiers to be purchased sequentially (tier 1 before tier 2, tier 2 before tier 3)
5. WHILE a Player has a Higher Jump Power_Up active, THE Game_System SHALL increase the Player jump height by the purchased tier multiplier
6. WHILE a Player has a Double Jump Power_Up active, THE Game_System SHALL allow the Player to jump a second time while airborne
7. WHILE a Player has a Faster Speed Power_Up active, THE Game_System SHALL increase the Player movement speed by the purchased tier multiplier
8. THE Level_Pack configuration SHALL define which Power_Ups are required to complete specific obstacles, and THE Game_System SHALL enforce that those obstacles cannot be bypassed without the required Power_Up

### Requirement 8: Achievement System

**User Story:** As a player, I want to earn achievements for completing level packs, so that I have long-term goals to work toward.

#### Acceptance Criteria

1. THE Achievement_System SHALL define exactly one achievement per Level_Pack, each identified by a unique name and associated icon visible in the Player's achievement list
2. WHEN a Player completes all 10 levels in a Level_Pack, THE Achievement_System SHALL award the corresponding achievement to the Player
3. IF a Player completes a Level_Pack for which the achievement has already been awarded, THEN THE Achievement_System SHALL not award a duplicate and SHALL not display the award notification
4. WHEN an achievement is awarded, THE Effects_Manager SHALL display a particle explosion and floating text showing the achievement name to the Player for a duration between 3 and 5 seconds
5. THE Achievement_System SHALL persist awarded achievements across game sessions using the Data_Store
6. IF the Data_Store fails to persist an awarded achievement, THEN THE Achievement_System SHALL retry the save operation up to 3 times and notify the Player if persistence ultimately fails
7. THE Game_System SHALL provide an achievement list accessible from the Lobby and HUD that displays all defined achievements with earned or unearned status per Level_Pack

### Requirement 9: Visual Effects and Sound

**User Story:** As a player, I want particle effects, floating text, and dynamic music, so that the game feels polished and responsive.

#### Acceptance Criteria

1. WHEN a Player completes a level, THE Effects_Manager SHALL display a particle explosion at the Player position
2. WHEN a Player earns Experience_Points, THE Effects_Manager SHALL display floating text showing the XP amount gained, batching XP gains into a single display update no more frequently than once per second
3. WHEN a Player collides with a touch-and-die Obstacle, THE Effects_Manager SHALL display a death particle effect
4. WHILE a Player is in a Level, THE Sound_Manager SHALL play theme-appropriate background music matching the active Level_Pack, looping the track continuously until the Player exits the level
5. WHEN a Player transitions between the Lobby and a Level, THE Sound_Manager SHALL crossfade between the appropriate music tracks over a duration of 1 to 2 seconds

### Requirement 10: Real-Time Leaderboards

**User Story:** As a player, I want to see how I rank against other players, so that I feel motivated to improve.

#### Acceptance Criteria

1. THE Leaderboard_System SHALL display global real-time rankings based on total Experience_Points earned, showing the top 100 players
2. THE Leaderboard_System SHALL display global real-time rankings based on highest level completed, showing the top 100 players
3. WHEN a Player score changes, THE Leaderboard_System SHALL update the displayed rankings within 5 seconds
4. THE Leaderboard_System SHALL be accessible from both the Lobby and during active gameplay via the HUD
5. THE Leaderboard_System SHALL always display the current Player's own rank and score regardless of whether they are in the top 100
6. IF the Leaderboard_System cannot retrieve ranking data, THEN THE Game_System SHALL display a message indicating leaderboard data is temporarily unavailable and retry retrieval every 10 seconds

### Requirement 11: Data Persistence

**User Story:** As a player, I want my progress saved across sessions, so that I never lose my achievements or power-ups.

#### Acceptance Criteria

1. THE Data_Store SHALL persist Player Experience_Points, purchased Power_Ups, level completion records, and achievements across game sessions
2. WHEN a Player joins the game, THE Data_Store SHALL load the Player profile within 3 seconds of spawning
3. THE Data_Store SHALL save Player progress every 60 seconds and upon each level completion
4. IF the Data_Store fails to load Player data, THEN THE Game_System SHALL notify the Player with a message indicating data is unavailable and retry the load operation up to 3 times with a 2-second delay between attempts before spawning the Player with default values of 0 Experience_Points, no purchased Power_Ups, no level completions, and no achievements
5. IF the Data_Store fails to save Player data, THEN THE Game_System SHALL retry the save operation up to 3 times and notify the Player with a message indicating save failure if all retries are exhausted

### Requirement 12: Level Pack Extensibility

**User Story:** As a developer, I want to add new level packs weekly without modifying core systems, so that the game stays fresh with minimal development friction.

#### Acceptance Criteria

1. THE Level_Generator SHALL load Level_Pack configurations from individual module files following a standardized schema that requires the following fields: pack name, display order (numeric), theme identifier, obstacle type definitions, difficulty configuration per level (levels 1 through 10), morass visual definition, and achievement name
2. THE Level_Generator SHALL support adding a new Level_Pack by creating a single configuration module without modifying existing game code
3. THE Rojo_Project SHALL organize Level_Pack modules in a dedicated directory separate from core game logic
4. WHEN a new Level_Pack module is added, THE Game_System SHALL automatically detect and register the pack in the Lobby upon server start, positioning the pack portal according to the pack's numeric display order field
5. IF a Level_Pack module fails schema validation during loading, THEN THE Game_System SHALL skip the invalid pack, log an error message indicating the module name and missing or malformed field, and continue loading remaining valid packs without interrupting server start
6. WHEN multiple Level_Pack modules are loaded, THE Game_System SHALL register all valid packs and display their portals in ascending display order within 5 seconds of server start

### Requirement 13: Client-Server Architecture

**User Story:** As a developer, I want clear separation between server authoritative logic and client presentation, so that the game is secure and performant.

#### Acceptance Criteria

1. THE Game_System SHALL implement game logic, score validation, XP calculations, and Data_Store operations exclusively on the server
2. THE Game_System SHALL implement UI rendering, visual effects, user input handling, and Sound_Manager operations exclusively on the client
3. THE Game_System SHALL validate all state-changing Player actions (Power_Up purchases, level completion claims, XP award requests) on the server before applying state changes to prevent exploitation
4. THE Game_System SHALL use RemoteEvents for one-way client-to-server notifications and RemoteFunctions for request-response patterns requiring server acknowledgment
5. IF the server rejects a client request due to validation failure, THEN THE Game_System SHALL respond with an error code and descriptive message that the client displays to the Player without applying the rejected state change
6. THE Game_System SHALL enforce rate limiting of no more than 30 RemoteEvent calls per second per Player, dropping excess calls and logging a warning on the server
