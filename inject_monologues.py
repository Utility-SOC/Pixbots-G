import re

monologues = {
    "1. Arthur": [
        '- **Round 1 Monologue:** "Don\'t touch the paint, peasant. Do you know how much a single Mythic actuator costs? More than your whole garage."',
        '- **Round 2 Monologue:** "You got lucky last time. My chassis wasn\'t polished. Let\'s see you handle the real power of money."',
        '- **Round 3 Monologue:** "I don\'t care how many matches you\'ve won, you\'re still using scraps. I\'m going to put you in your place."',
        '- **Mythic Round Monologue:** "Okay... I admit it. You\'ve got skills. Even my dad\'s corporate engineers couldn\'t build a loadout like yours. Show me how you do it."'
    ],
    "2. Beatrice": [
        '- **Round 1 Monologue:** "Your build is highly inefficient. I\'ve calculated fourteen distinct structural flaws. Prepare to be optimized out of the bracket."',
        '- **Round 2 Monologue:** "I had to carry a remainder in my last equation to account for your... erratic playstyle. I won\'t make that mistake twice."',
        '- **Round 3 Monologue:** "Your loadout defies traditional mathematical models. It\'s fascinating. I\'d like to test a new theorem against it."'
    ],
    "3. Grog": [
        '- **Round 1 Monologue:** "Me smash your little toy into tiny pieces! Grog strongest!"',
        '- **Round 2 Monologue:** "You run fast. But Grog smash faster this time!"',
        '- **Round 3 Monologue:** "You tough. You take big hit and not break. Grog respect that. Let us have good smash!"'
    ],
    "4 & 5. Leo & Luna": [
        '- **Round 1 Monologue:** (Leo) "They won\'t even see us coming." (Luna) "They never do, brother. It\'s almost too easy."',
        '- **Round 2 Monologue:** (Leo) "You survived the crossfire last time." (Luna) "An anomaly. We\'ve adjusted our firing arcs."',
        '- **Round 3 Monologue:** (Leo) "You have eyes in the back of your head." (Luna) "A worthy prey. Let us dance in the shadows once more."'
    ],
    "6. Rudy": [
        '- **Round 1 Monologue:** "Limiters are for cowards! You\'re gonna see true power! Assuming my core doesn\'t melt first!"',
        '- **Round 2 Monologue:** "I tweaked the plasma regulator! It\'s running at 400% capacity! It burns! It burns so good!"',
        '- **Round 3 Monologue:** "You\'re crazy. You\'re crazier than me. You stare down the meltdown and you don\'t even blink. Let\'s see who burns out first!"'
    ],
    "7. Professor P.": [
        '- **Round 1 Monologue:** "Ah, a new specimen. Let\'s observe how your armor plating reacts to a concentrated sulfuric compound."',
        '- **Round 2 Monologue:** "Your resistance to corrosive agents was statistically anomalous. I\'ve prepared a more volatile mixture for this experiment."',
        '- **Round 3 Monologue:** "Your adaptations are nothing short of brilliant. This next match will be published in my most prestigious journal!"'
    ],
    "8. Zane": [
        '- **Round 1 Monologue:** "Try to keep up! Actually, don\'t. It\'s embarrassing to watch you try."',
        '- **Round 2 Monologue:** "You managed to clip my wing last time. I\'ve upgraded my thrusters. You won\'t even see the blur."',
        '- **Round 3 Monologue:** "You\'ve got fast reflexes. Real fast. Most people give up. Let\'s push the redline and see who breaks."'
    ],
    "9. Chloe": [
        '- **Round 1 Monologue:** "Why fight alone when you can bring friends? And by friends, I mean thirty autonomous kill-drones."',
        '- **Round 2 Monologue:** "You squashed my little ones. They didn\'t like that. And neither did I."',
        '- **Round 3 Monologue:** "You handle the swarm better than anyone. My drones actually consider you an apex threat now. I\'m honored."'
    ],
    "10. Vance": [
        '- **Round 1 Monologue:** "Go ahead. Shoot me. I\'ve got all day. My shields recharge faster than you can pull the trigger."',
        '- **Round 2 Monologue:** "You found a crack in the armor. Impressive. But I brought the heavy barricades this time."',
        '- **Round 3 Monologue:** "You\'re the unstoppable force, and I\'m the immovable object. This is what we play the game for."'
    ],
    "11. Maya": [
        '- **Round 1 Monologue:** "Distance is safety. By the time you figure out where I am, there\'ll be a hole through your chassis."',
        '- **Round 2 Monologue:** "You\'re good at closing the gap. I respect that. But I\'ve recalibrated my optics."',
        '- **Round 3 Monologue:** "I don\'t usually let anyone get this close. You\'ve earned the right to see the whites of my eyes."'
    ],
    "12. Declan": [
        '- **Round 1 Monologue:** "Watch your step. The board is mine. Every tile is a trap waiting to snap."',
        '- **Round 2 Monologue:** "You sidestepped the magnets. Clever. But I\'ve rigged the entire quadrant this time."',
        '- **Round 3 Monologue:** "You read the board like a grandmaster. It\'s a genuine pleasure trying to outsmart you."'
    ],
    "13. Jin": [
        '- **Round 1 Monologue:** "Snake eyes or jackpot, let\'s let the dice decide! I love the thrill of the unknown!"',
        '- **Round 2 Monologue:** "My luck ran dry last hand. But the house always takes another bet. Double or nothing!"',
        '- **Round 3 Monologue:** "You don\'t play the odds, you make your own luck. That\'s the mark of a true high roller. Deal me in!"'
    ],
    "14. Sammy": [
        '- **Round 1 Monologue:** "One man\'s trash is my treasure! Don\'t laugh at the rust, it adds character!"',
        '- **Round 2 Monologue:** "I found a shiny new exhaust pipe in the dumpster. It makes my bot 12% more unpredictable!"',
        '- **Round 3 Monologue:** "You don\'t care that my bot is made of cans and duct tape. You fight me like a pro. Thanks for not going easy on me."'
    ],
    "15. Rex": [
        '- **Round 1 Monologue:** "Anything you can do, I can do better. Let\'s see how you handle your own medicine."',
        '- **Round 2 Monologue:** "So you tweaked your build. Cute. I downloaded your new schematic ten minutes ago."',
        '- **Round 3 Monologue:** "You\'ve mastered this loadout. I can copy the parts, but I can\'t copy your instincts. Show me the masterclass."'
    ]
}

with open("story_script.md", "r", encoding="utf-8") as f:
    content = f.read()

for key, lines in monologues.items():
    # Find the block for the rival
    pattern = r'(### ' + re.escape(key) + r'.*?)(?=\n### |\n## )'
    match = re.search(pattern, content, re.M | re.S)
    if match:
        block = match.group(1)
        if "- **Round 1 Monologue:**" not in block:
            insertion = "\n".join(lines) + "\n"
            new_block = block.rstrip() + "\n" + insertion
            content = content.replace(block, new_block)

with open("story_script.md", "w", encoding="utf-8") as f:
    f.write(content)
