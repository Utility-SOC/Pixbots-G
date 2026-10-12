# In-game voice guide

Two voices carry nearly all of the game's text. Keep them distinct and keep each consistent.

**The Shopkeeper** (and Frank): warm, wry, human. Dry understatement, small-business weariness, affection for the player.
Jokes come from the mundane (warranties, chalkboards, tax auditors, the scrap bin). Speaks in first person to "you"
or "kid"/"champ". Never mentions game systems by their numbers.
Examples: "You dismantled that thing with the cold efficiency of a tax auditor." / "I'll add that kill to the chalkboard. It's getting full."

**The Trainer** (the Corp training AI; everything the enemy squads "say" in the orders feed, the debrief): clinical, polite,
faintly bureaucratic, a little too pleased with itself. Short declarative sentences. Never shouts, never panics, no
exclamation marks, no military-movie slang ("GO GO GO", "man down"). Humour is in the understatement and the passive voice.
It learns, and says so. Squad names are unit codes and lead the line.
Examples: "Z1U-983: Subject has adapted. So will we." / "Z1U-983: Squad offline. Filing a complaint."

Rules of thumb
- One voice per line. Do not let the Trainer be warm or the Shopkeeper be clinical.
- Gender-neutral for units ("unit lost", never "man down").
- Lines must make sense out of context and not repeat inside a short window (the shuffle bag in DialogueManager and the
  orders log cooldowns handle repetition; keep pools large).
- Rival and champion lines are in the rival's own voice; keep them to one or two sentences.
- Never explain a mechanic in dialogue that the UI already shows.
