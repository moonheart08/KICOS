# KICOS
KICOS is intended to be an actively maintained alternative to OpenOS and Plan9k, for personal usage.

## Goals
- Decently space and memory efficient (Comfortable operation on 2x Tier 1 RAM is the performance target. Unfortunately 1x runs into issues with the source code being too large.)
- Not obfuscated or packed in any way for easy introspection and debugging.
- Networked shell and remote control support (eventually...)
- Remote logging and management for larger bases.

## Non-goals
- Pretty graphics. While good GPU APIs are planned the core experience is focused more on simply being functional.
- Multi-user support (this is lua, with limited RAM, even just asking for proper process isolation is a tall order and I don't want multi-user without that.)
- Defending against the hypothetical minecraft computer hacker when I'm writing this for a private minecraft server. (No passwords or encryption, sorry.)
- Making money (Who on earth would charge for a minecraft computer pr- Oh. People do that? Wow.)