# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**FSE** is a Godot 4.6 (Forward Plus) third-person action/exploration game. The main scene is `levels/main.tscn`. The project uses the Godot MCP server for AI-assisted development — prefer MCP tools (`mcp__godot__*`) over direct file edits for scene manipulation.

## Running & Tooling

- **Open the project**: Launch Godot 4.6 and open the project at this directory, or use `mcp__godot__run_project` / `mcp__godot__launch_editor`.
- **Open Blender source files**: `make blend` (or `./open-blends`) — opens `blender/level/level.blend` and `blender/models/props.blend`. Requires Blender to be installed; override the app name with `BLENDER_APP=...`.
- **Godot version**: 4.6.stable.official — no GDScript 1.x syntax; use typed declarations throughout (untyped declarations are treated as warnings).

## Architecture

### Autoloads (always available as singletons)
- **`Events`** (`autoloads/events.gd`) — central signal bus. All cross-system communication goes through here. Manages dialogue state (`is_dialogue_active`, `active_dialogue_trigger`) and emits signals for combat, enemy HP, phase changes, and dialogue lifecycle. Systems check `Events.is_dialogue_active` to lock input.
- **`GameManager`** (`autoloads/game_manager.gd`) — holds runtime references to the navigator (`CharacterBody3D`) and overworld root. Systems that need the player reference use `GameManager.navigator`.
- **`McpInteractionServer`** (`autoloads/mcp_interaction_server.gd`) — TCP server on `127.0.0.1:9090` that accepts JSON commands from the Godot MCP tool. Runs with `PROCESS_MODE_ALWAYS` so it stays active while paused.

### Player (`objects/fse/overworld/player/navigator.gd`)
`CharacterBody3D` with a `SpringArm3D` third-person camera rig. Key behaviors:
- Two movement modes toggled by `use_gravity`: fly mode (default, no physics) and gravity mode with jump.
- ADS (Aim Down Sights) triggered by `AimDownSights` action — shifts camera to shoulder offset, constrains pitch/yaw, enables firing.
- Sprint input fires a dodge (impulse + cooldown), not a continuous sprint.
- Weapon is instantiated from `default_weapon_scene` and parented to `elena/WeaponSocket`. The model node is named `elena`.
- Firing requires ADS to be active. Aim direction is resolved via a raycast from the camera; falls back to `projectile_zero_distance` when nothing is hit.
- All input is gated by `_is_dialogue_locked()` which checks `Events.is_dialogue_active`.

**Input map** (keyboard defaults shown): Move = IJKL, Jump = Space, Sprint/Dodge = `;`, ADS = Shift, Attack = LMB. Controller fully supported.

### Enemy System (`objects/fse/enemy/`)
- **`FseEnemy`** (`base/fse_enemy.gd`, `class_name FseEnemy`) — `CharacterBody3D`. Reads stats from an `FseEnemyData` resource; instantiates a visual mesh from `enemy_data.character_scene`. Uses `NavigationAgent3D` with RVO avoidance (Y-axis locked).
- **`FseAIState`** (`base/AIState.gd`) — extends `BaseAIState`. States receive references to `character`, `player`, `nav_agent`, `attack_area`, `animator`, and `enemy_data` injected by `FseEnemy._setup_state_machine()`. States: `idle`, `pursue`, `wander`, `attack`, `death`.
- **`BaseStateMachine`** (`objects/fse/base/state/state_machine.gd`) — collects `BaseAIState` children by node type, calls `check_transition()` then `update()` each physics frame.
- Static helpers on `FseEnemy`: `spawn_from_markers()` (spawns N enemies at shuffled `Marker3D` children), `get_closest_to()`, `command_all()`.

### Weapons (`objects/fse/weapons/`)
- **`FseBaseWeapon`** (`base/BaseWeapon.gd`, `class_name FseBaseWeapon`) — data-driven via `FseWeaponData` resource. Exposes `try_fire(aim_direction)` and `should_fire_for_input(pressed, just_pressed)`. Projectiles are spawned at scene root, not as children of the weapon.
- **`FseWeaponData`** — `fire_rate`, `muzzle_velocity`, `burst_count`, `damage`, `ammo_count` (`-1` = infinite), `is_automatic`, `projectile_scene`.
- Projectile scenes must expose `launch(transform, direction, owner)` and `speed`/`damage` properties.

### Dialogue System
- **`DialogueTrigger`** (`objects/fse/overworld/triggers/dialogue/dialogue_trigger.gd`) — `CharacterBody3D` with an `Area3D`. Player proximity shows a prompt via `Events.request_dialogue_prompt()`; confirm input calls `Events.begin_dialogue()`. One-shot by default.
- Dialogue config is a `DialogueConfig` resource (not defined in this repo — likely a custom Resource).
- UI: `ui/overworld/DialogueBox.tscn` / `dialogue_box.gd` and `PromptBox.tscn` / `prompt_box.gd` listen to `Events` signals.

### Shader / Post-Processing (`objects/explore-shaders/`)
- **`outline-posterize-color-dither.gdshader`** — fullscreen post-processing effect using a `spatial` + `unshaded` quad placed in front of the camera (`POSITION = vec4(VERTEX.xy, 1.0, 1.0)`). Combines Sobel-Feldman edge detection (depth + normal buffers), color posterization, 8-color palette matching, and Bayer dithering.
- **Known limitation**: this technique conflicts with Volumetric Fog (fog is applied to the quad at max depth). Fix: add `fog_disabled` to `render_mode`. Long-term: migrate to a `CompositorEffect` (Godot 4.3+).

### Global Groups
Nodes self-register into `"player"`, `"enemy"`, and `"level"` groups. Enemy AI resolves the player via `get_tree().get_first_node_in_group("player")`.

## Conventions
- GDScript with static typing throughout. The linter warns on untyped declarations.
- Signals are emitted through `Events` — avoid direct node-to-node signal connections across systems.
- Scene files for exploration/prototyping live under `objects/explore-*/`; production game objects live under `objects/fse/`.
- Blender source files live in `blender/`; exported assets (`.glb`, `.obj`) are imported into the project root or `models/`.
