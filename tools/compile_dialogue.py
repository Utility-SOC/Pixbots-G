import re
import json

def parse_markdown(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    data = {
        "intermission_quips": [],
        "first_boss_intro": "",
        "first_boss_defeat": "",
        "boss_defeats": [],
        "rivals": {},
        "travelling_champion": {},
        "generic_rival_wins": [],
        "generic_rival_losses": [],
        "milestones": {},
        "black_market": [],
        "death_footers": [],
        "game_over_3_loss": "",
        "tournament_teaser": "",
        "boss_rush": {}
    }

    # Extract Intermission quips
    m = re.search(r'## Intermission quips.*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["intermission_quips"].append(line[3:-1])

    # Boss defeats
    m = re.search(r'## Boss defeats.*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["boss_defeats"].append(line[3:-1])

    # First boss
    m = re.search(r'## First boss.*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- Intro: "'):
                data["first_boss_intro"] = line[10:-1]
            elif line.startswith('- Defeat: "'):
                data["first_boss_defeat"] = line[11:-1]

    # Death footers
    m = re.search(r'## Death / kicked back to garage.*?$(.*?)(?=###|##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["death_footers"].append(line[3:-1])
                
    # 3 loss game over
    m = re.search(r'### Game Over \(3 Consecutive Rival Losses\).*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["game_over_3_loss"] = line[3:-1]
                
    # Generic wins/losses
    m = re.search(r'### Generic Rival Wins.*?$(.*?)(?=###)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["generic_rival_wins"].append(line[3:-1])
                
    m = re.search(r'### Generic Rival Losses.*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["generic_rival_losses"].append(line[3:-1])
                
    # Boss Rush
    m = re.search(r'## Boss Rush Mode.*?$(.*)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- Intro: "'):
                data["boss_rush"]["intro"] = line[10:-1]
            elif line.startswith('- Completion: "'):
                data["boss_rush"]["completion"] = line[15:-1]
                
    # Tournament teaser
    m = re.search(r'## Tournament arc teaser.*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["tournament_teaser"] = line[3:-1]

    # Rivals
    m = re.search(r'## Rival Challenges.*?$(.*?)(?=## Travelling)', content, re.M | re.S)
    if m:
        rival_text = m.group(1).strip()
        rival_blocks = re.split(r'### \d+(?: & \d+)?\. ', rival_text)
        for block in rival_blocks[1:]:
            lines = block.strip().split('\n')
            name = lines[0].split('(')[0].strip()
            rival_data = {"intro": "", "win": "", "loss": "", "gimmick": "", "monologues": {}}
            monologue_labels = [
                ("Round 1 Monologue", "round_1"),
                ("Round 2 Monologue", "round_2"),
                ("Round 3 Monologue", "round_3"),
                ("Mythic Round Monologue", "mythic"),
            ]
            for line in lines[1:]:
                if line.startswith('- **Intro:** "'): rival_data["intro"] = line[14:-1]
                elif line.startswith('- **Win:** "'): rival_data["win"] = line[12:-1]
                elif line.startswith('- **Loss:** "'): rival_data["loss"] = line[13:-1]
                elif line.startswith('- **Gimmick:**'): rival_data["gimmick"] = line[14:].strip()
                else:
                    # Some rivals (e.g. Leo & Luna) attribute lines per-speaker,
                    # e.g. `(Leo) "..." (Luna) "..."`, so the text doesn't start
                    # with a quote right after the label — match on the label only.
                    for label, key in monologue_labels:
                        prefix = f'- **{label}:**'
                        if line.startswith(prefix):
                            text = line[len(prefix):].strip()
                            if text.startswith('"') and text.endswith('"'):
                                text = text[1:-1]
                            rival_data["monologues"][key] = text
                            break
            data["rivals"][name] = rival_data
            
    # Travelling Champion
    m = re.search(r'## Travelling Champion.*?$(.*?)(?=## Generic)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- Intro: "'): data["travelling_champion"]["intro"] = line[10:-1]
            elif line.startswith('- Win: "'): data["travelling_champion"]["win"] = line[8:-1]
            elif line.startswith('- Loss: "'): data["travelling_champion"]["loss"] = line[9:-1]
            
    # Milestones
    m = re.search(r'## Milestones.*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        milestone_text = m.group(1).strip()
        if "10 bosses/champions defeated:" in milestone_text:
            data["milestones"]["10_bosses"] = milestone_text.split('defeated:\n')[1].split('- Level 100:')[0].strip()[1:-1]
        if "Level 100:" in milestone_text:
            data["milestones"]["level_100"] = milestone_text.split('Level 100:')[1].strip()[1:-1]
            
    # Black Market
    m = re.search(r'## Black Market flavor.*?$(.*?)(?=##)', content, re.M | re.S)
    if m:
        for line in m.group(1).strip().split('\n'):
            if line.startswith('- "'):
                data["black_market"].append(line[3:-1])

    with open('config/dialogue.json', 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=4)

parse_markdown('STORY_SCRIPT.md')
